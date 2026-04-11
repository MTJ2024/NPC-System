-- NPC Dashboard Client with proper behavior-specific combat logic
-- KEIN dofile, KEIN require – Config kommt global durch fxmanifest.lua

ESX = exports["es_extended"]:getSharedObject()

local istDashboardOffen = false
local istKoordinatenWahl = false
local gespawnteNpcs = {}
local npcStatus = {}
local AlleNPCsSpawnenLastList = nil
local lastNpcDelete = {}
local syncInProgress = false

-- Relationship group hashes - control NPC reactions to the player
local NPC_RELATIONSHIP_GROUP = nil   -- Passive/Neutral: Respect(1) - flee from threats
local NPC_GUARD_GROUP = nil          -- Guard/Wache:     Dislike(4) - fight back when provoked
local NPC_AGGRESSIVE_GROUP = nil     -- Aggressive:      Hate(5)    - attack on sight

-- Stuck detection thresholds (tuned for responsive obstacle avoidance)
local STUCK_CHECK_INTERVAL_MS = 1000   -- Minimum time between stuck checks (ms)
local STUCK_DISTANCE_THRESHOLD = 0.3   -- NPC must move at least this far (meters) to not be stuck
local STUCK_SPEED_THRESHOLD = 0.2      -- NPC speed below this (m/s) is considered stopped
local STUCK_COUNT_THRESHOLD = 3        -- Consecutive stuck checks before re-routing (~6s of standstill)
local REROUTE_COOLDOWN_MS = 12000      -- Cooldown after re-routing before next stuck check (ms)
local REROUTE_RECOVERY_MS = 4000       -- Wait time before resuming wander after re-route (ms)

-- Movement redirect cooldown (prevents constant task clearing that freezes NPCs)
local REDIRECT_COOLDOWN_MS = 10000     -- Min time between radius-redirect (ms)
local RADIUS_EXCEED_BUFFER = 1.5       -- Only redirect when NPC exceeds radius * this factor
local DESPAWN_RADIUS_MULTIPLIER = 5    -- Despawn NPC if it exceeds radius * this factor
local DUPLICATE_DETECTION_RADIUS = 3.0  -- Distance (meters) to check for existing NPC before respawning

-- Sync debounce: prevent multiple rapid syncAllNpcs from respawning NPCs over and over
local lastSyncTime = 0
local SYNC_DEBOUNCE_MS = 5000          -- Ignore syncs within this many ms of last sync

-- Debug logging helper
local function debugLog(msg)
    if Config and Config.Debug then
        print("[NPC-DEBUG] " .. tostring(msg))
    end
end

-- Initialize NPC relationship groups:
--   NPC_DASHBOARD_GROUP  (Passive/Neutral) → Respect(1) to player  → flee from threats
--   NPC_GUARD_GROUP      (Guard/Wache)     → Dislike(4) to player  → fight back when provoked
--   NPC_AGGRESSIVE_GROUP (Aggressive)      → Hate(5)    to player  → native AI auto-attacks on sight
-- All groups are Companion(0) to each other so NPCs never fight each other.
Citizen.CreateThread(function()
    AddRelationshipGroup("NPC_DASHBOARD_GROUP")
    NPC_RELATIONSHIP_GROUP = GetHashKey("NPC_DASHBOARD_GROUP")
    AddRelationshipGroup("NPC_GUARD_GROUP")
    NPC_GUARD_GROUP = GetHashKey("NPC_GUARD_GROUP")
    AddRelationshipGroup("NPC_AGGRESSIVE_GROUP")
    NPC_AGGRESSIVE_GROUP = GetHashKey("NPC_AGGRESSIVE_GROUP")

    -- All NPC groups are companions to each other (they must not fight each other)
    SetRelationshipBetweenGroups(0, NPC_RELATIONSHIP_GROUP, NPC_RELATIONSHIP_GROUP)
    SetRelationshipBetweenGroups(0, NPC_GUARD_GROUP, NPC_GUARD_GROUP)
    SetRelationshipBetweenGroups(0, NPC_AGGRESSIVE_GROUP, NPC_AGGRESSIVE_GROUP)
    SetRelationshipBetweenGroups(0, NPC_RELATIONSHIP_GROUP, NPC_GUARD_GROUP)
    SetRelationshipBetweenGroups(0, NPC_GUARD_GROUP, NPC_RELATIONSHIP_GROUP)
    SetRelationshipBetweenGroups(0, NPC_RELATIONSHIP_GROUP, NPC_AGGRESSIVE_GROUP)
    SetRelationshipBetweenGroups(0, NPC_AGGRESSIVE_GROUP, NPC_RELATIONSHIP_GROUP)
    SetRelationshipBetweenGroups(0, NPC_GUARD_GROUP, NPC_AGGRESSIVE_GROUP)
    SetRelationshipBetweenGroups(0, NPC_AGGRESSIVE_GROUP, NPC_GUARD_GROUP)

    local playerGroup = GetHashKey("PLAYER")
    -- Passive/Neutral NPCs respect the player → GTA native AI makes them flee from armed players
    SetRelationshipBetweenGroups(1, NPC_RELATIONSHIP_GROUP, playerGroup)
    SetRelationshipBetweenGroups(1, playerGroup, NPC_RELATIONSHIP_GROUP)
    -- Guard NPCs dislike the player → GTA native AI fights back when provoked (no flee)
    SetRelationshipBetweenGroups(4, NPC_GUARD_GROUP, playerGroup)
    SetRelationshipBetweenGroups(4, playerGroup, NPC_GUARD_GROUP)
    -- Aggressive NPCs hate the player → GTA native AI attacks on sight (no flee)
    SetRelationshipBetweenGroups(5, NPC_AGGRESSIVE_GROUP, playerGroup)
    SetRelationshipBetweenGroups(5, playerGroup, NPC_AGGRESSIVE_GROUP)
    debugLog("NPC relationship groups initialized (Passive/Guard/Aggressive)")
end)

-- Spezialwerte aus Config holen (priority: SpecialNpcs > per-NPC DB value > Config default)
local function getNpcConfig(npc, key)
    -- 1. Check SpecialNpcs override from config file
    if npc and npc.id and Config.SpecialNpcs and Config.SpecialNpcs[npc.id] and Config.SpecialNpcs[npc.id][key] ~= nil then
        return Config.SpecialNpcs[npc.id][key]
    end
    -- 2. Check per-NPC value from database (e.g., npc.radius, npc.weapon)
    if npc and npc[key] ~= nil then
        local val = tonumber(npc[key])
        if val then return val end
        -- Non-numeric DB values (strings)
        if type(npc[key]) == "string" and npc[key] ~= "" then return npc[key] end
    end
    -- 3. Map config keys that don't follow the Default... pattern
    if key == "invincible" then
        return Config.NPCInvincible
    end
    return Config["Default" .. key:sub(1,1):upper() .. key:sub(2)]
end

-- Helper: check if movement is enabled (handles number, string, bool from DB/JSON)
local function isMovementEnabled(npc)
    if not npc then return false end
    local movement = npc.movement
    if movement == 1 or movement == true or movement == "1" or tonumber(movement) == 1 then
        return true
    end
    if type(movement) == "string" then
        local normalized = movement:lower():gsub("^%s*(.-)%s*$", "%1")
        return normalized == "on" or normalized == "true" or normalized == "yes" or normalized == "an"
    end
    return false
end

-- Helper: normalize behavior strings from DB/UI to canonical values
local function normalizeBehavior(behavior)
    if type(behavior) ~= "string" then
        return "Passiv"
    end
    local normalized = behavior:lower():gsub("^%s*(.-)%s*$", "%1")
    if normalized == "wache" or normalized == "guard" or normalized == "wach" or normalized == "wachmodus" then
        return "Wache"
    elseif normalized == "aggressiv" or normalized == "aggressive" then
        return "Aggressiv"
    elseif normalized == "neutral" then
        return "Neutral"
    elseif normalized == "passiv" or normalized == "passive" then
        return "Passiv"
    end
    return "Passiv"
end

-- Helper: Get a random navigable point within radius for obstacle avoidance re-routing.
-- Instead of always going back to origin (which can lead to the same wall), pick a
-- random offset direction. Uses GetSafeCoordForPed to find a point on the navmesh.
-- NOTE: In FiveM Lua, GetSafeCoordForPed returns (bool, vector3) – NOT (bool, x, y, z).
local function getRandomNavPoint(origin, radius)
    local angle = math.random() * 2 * math.pi
    local dist = radius * (0.3 + math.random() * 0.5) -- 30-80% of radius
    local targetX = origin.x + math.cos(angle) * dist
    local targetY = origin.y + math.sin(angle) * dist
    local found, safeCoord = GetSafeCoordForPed(targetX, targetY, origin.z, true, 16)
    if found and safeCoord then
        return safeCoord
    end
    -- Fallback: return origin if no safe coord found
    return origin
end

-- Helper: Reinforce combat mode so the GTA engine cannot override a TaskCombatPed
-- call with flee/surrender behaviour.  Must be called immediately before every
-- TaskCombatPed invocation.
local function reinforceCombatMode(ped)
    SetPedCombatAbility(ped, 2)             -- Professional
    SetPedCombatMovement(ped, 2)            -- Aggressive: advance toward enemy
    SetPedCombatAttributes(ped, 5, true)    -- BF_AlwaysFight: always fight, never flee
    SetPedCombatAttributes(ped, 17, true)   -- BF_CanFightArmedPedsWhenNotArmed
    SetPedCombatAttributes(ped, 14, false)  -- NOT BF_AlwaysFlee
    SetPedCombatAttributes(ped, 46, true)   -- BF_CanInvestigate: perceive threats
    SetPedFleeAttributes(ped, 0, true)      -- Clear ALL flee attributes
    SetBlockingOfNonTemporaryEvents(ped, false) -- Allow events (enables weapon awareness; combat must be filtered via istSpielerIgnoriert)
end

local function npcIsAtOrigin(npc, ped)
    if not npc or not ped then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(npc.x, npc.y, npc.z)) < (getNpcConfig(npc, "radius") * 1.2)
end

-- Helper: Setup NPC with behavior (coordinates already set by CreatePed)
local function setupNpcPed(ped, npc, idx)
    if not DoesEntityExist(ped) then return false end
    
    print("[NPC-SPAWN] Setting up: " .. tostring(npc.name or npc.model) .. " | Behavior: " .. tostring(npc.behavior) .. " | Pos: " .. tostring(npc.x) .. "," .. tostring(npc.y) .. "," .. tostring(npc.z))
    
    SetEntityAsMissionEntity(ped, true, true)
    SetPedKeepTask(ped, true)
    
    -- Use the exact coordinates from the database (user already picked correct position)
    -- Do NOT use GetGroundZFor_3dCoord - it returns wrong Z when collision isn't loaded,
    -- which sends NPCs underground where they're invisible but alive
    SetEntityHeading(ped, tonumber(npc.heading) or 0.0)
    
    -- Set health and invincibility
    SetEntityHealth(ped, getNpcConfig(npc, "health"))
    SetEntityInvincible(ped, getNpcConfig(npc, "invincible") == true)
    
    -- Give weapon if configured
    local npcWeapon = npc.weapon
    if type(npcWeapon) == "string" and npcWeapon ~= "" and npcWeapon ~= "None" then
        npcWeapon = npcWeapon:gsub("^%s*(.-)%s*$", "%1")
        local weaponHash = GetHashKey(npcWeapon)
        GiveWeaponToPed(ped, weaponHash, 999, false, true)
        SetCurrentPedWeapon(ped, weaponHash, true)
        debugLog("  Weapon given and equipped: " .. npcWeapon)
    end
    
    -- Behavior-specific setup
    local behavior = normalizeBehavior(npc and npc.behavior)
    local moving = isMovementEnabled(npc)
    
    if behavior == "Passiv" then
        -- Passive NPCs never fight
        -- Only block events for stationary NPCs; moving NPCs need navigation events
        SetBlockingOfNonTemporaryEvents(ped, not moving)
        SetPedFleeAttributes(ped, 0, true) -- Can flee
        SetPedCombatAbility(ped, 0)
        SetPedCombatAttributes(ped, 46, false)
        debugLog("  Behavior: Passive (non-combat, blocking=" .. tostring(not moving) .. ")")
        
    elseif behavior == "Neutral" then
        -- Neutral NPCs are non-violent - they don't fight and don't flee
        -- Only block events for stationary NPCs; moving NPCs need navigation events
        SetBlockingOfNonTemporaryEvents(ped, not moving)
        SetPedCombatAbility(ped, 0) -- No combat
        SetPedCombatRange(ped, 0) -- No range
        SetPedFleeAttributes(ped, 0, false) -- Won't flee
        SetPedCombatAttributes(ped, 46, false)
        debugLog("  Behavior: Neutral (non-violent, blocking=" .. tostring(not moving) .. ")")
        
    elseif behavior == "Wache" or behavior == "Guard" then
        -- Guard NPCs actively defend and help allies
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCombatAbility(ped, 2) -- Professional
        SetPedCombatRange(ped, 2) -- Medium range
        SetPedCombatMovement(ped, 2) -- Aggressive: advance toward enemy (prevents standing still)
        SetPedFleeAttributes(ped, 0, true) -- Clear ALL flee attributes so NPC never flees
        SetPedCombatAttributes(ped, 46, true) -- BF_CanInvestigate: enables investigation mode (perceive threats)
        SetPedCombatAttributes(ped, 5, true) -- BF_AlwaysFight: always fight, never flee
        SetPedCombatAttributes(ped, 17, true) -- BF_CanFightArmedPedsWhenNotArmed
        SetPedCombatAttributes(ped, 14, false) -- NOT BF_AlwaysFlee
        SetPedSeeingRange(ped, getNpcConfig(npc, "radius") * 1.5)
        SetPedHearingRange(ped, getNpcConfig(npc, "radius") * 1.5)
        debugLog("  Behavior: Guard (protective, will help allies)")
        
    elseif behavior == "Aggressiv" then
        -- Aggressive NPCs attack on sight within radius
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCombatAbility(ped, 2) -- Professional
        SetPedCombatRange(ped, 2) -- Medium range
        SetPedCombatMovement(ped, 2) -- Aggressive: advance toward enemy (prevents standing still)
        SetPedFleeAttributes(ped, 0, true) -- Clear ALL flee attributes so NPC never flees
        SetPedCombatAttributes(ped, 46, true) -- BF_CanInvestigate: enables investigation mode (perceive threats)
        SetPedCombatAttributes(ped, 5, true) -- BF_AlwaysFight: always fight, never flee
        SetPedCombatAttributes(ped, 17, true) -- BF_CanFightArmedPedsWhenNotArmed
        SetPedCombatAttributes(ped, 14, false) -- NOT BF_AlwaysFlee
        SetPedSeeingRange(ped, getNpcConfig(npc, "radius"))
        SetPedHearingRange(ped, getNpcConfig(npc, "radius"))
        debugLog("  Behavior: Aggressive (hostile)")
    end
    
    -- Enable improved pathfinding for all NPCs (navigate around obstacles, use climbovers/ladders)
    SetPedPathCanUseClimbovers(ped, true)
    SetPedPathCanUseLadders(ped, true)
    SetPedPathCanDropFromHeight(ped, true)
    SetPedPathAvoidFire(ped, true)
    SetPedPathPreferToAvoidWater(ped, true)
    SetPedConfigFlag(ped, 208, true)   -- CPED_CONFIG_FLAG_DisableShockingEvents: ignore shocking events but still navigate
    SetPedConfigFlag(ped, 400, true)   -- CPED_CONFIG_FLAG_CanUseDynamicNavmesh: use dynamic navmesh around obstacles
    SetPedConfigFlag(ped, 2, true)     -- CPED_CONFIG_FLAG_NoCriticalHits: avoid ragdolling into obstacles
    
    -- Assign to the appropriate relationship group based on behavior.
    -- Guard/Aggressive groups have Dislike/Hate toward the player so GTA's native AI
    -- reacts adversarially (fights back) instead of fleeing when a weapon is drawn.
    local assignBehavior = normalizeBehavior(npc and npc.behavior)
    if assignBehavior == "Wache" and NPC_GUARD_GROUP then
        SetPedRelationshipGroupHash(ped, NPC_GUARD_GROUP)
    elseif assignBehavior == "Aggressiv" and NPC_AGGRESSIVE_GROUP then
        SetPedRelationshipGroupHash(ped, NPC_AGGRESSIVE_GROUP)
    elseif NPC_RELATIONSHIP_GROUP then
        SetPedRelationshipGroupHash(ped, NPC_RELATIONSHIP_GROUP)
    end
    
    -- Initialize status tracking
    npcStatus[idx] = {
        busy = false,
        pursuing = false,
        origin = vector3(tonumber(npc.x), tonumber(npc.y), tonumber(npc.z)),
        deathTime = nil,
        dead = false,
        respawnAt = 0,
        inCombat = false,
        lastAttacker = nil,
        lastMoveCheck = 0,
        lastMovePos = nil,
        stuckCount = 0,
        lastRedirectTime = 0,
        lastRerouteTime = 0
    }
    
    -- Set initial movement behavior
    -- NOTE: do NOT freeze or issue wander tasks immediately after CreatePed.
    -- Collision and navmesh are still loading; doing so causes NPCs to hover in mid-air
    -- (frozen above unloaded ground) or snap to wrong Z.  A short async delay lets the
    -- engine settle the ped on the correct ground level first.
    if moving then
        FreezeEntityPosition(ped, false)
        local radius = tonumber(getNpcConfig(npc, "radius")) or Config.DefaultRadius
        local ox, oy, oz = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z)
        local pedRef = ped
        Citizen.CreateThread(function()
            Citizen.Wait(500) -- let navmesh/collision initialise
            if DoesEntityExist(pedRef) then
                PlaceObjectOnGroundProperly(pedRef) -- snap to actual ground surface
                ClearPedTasksImmediately(pedRef)
                FreezeEntityPosition(pedRef, false)
                TaskWanderInArea(pedRef, ox, oy, oz, radius, 2.0, 1.0)
                SetPedKeepTask(pedRef, true) -- keep wander task, prevent it from being silently dropped
                debugLog("  Movement: Wandering within radius " .. tostring(radius) .. "m (after ground snap)")
            end
        end)
    else
        ClearPedTasksImmediately(ped)
        TaskStandStill(ped, -1)
        -- Delay freeze so gravity can pull the ped onto the ground before we lock it
        local pedRef = ped
        local pedIdx = idx
        Citizen.CreateThread(function()
            Citizen.Wait(1000) -- wait for collision/ground to load
            if DoesEntityExist(pedRef) then
                PlaceObjectOnGroundProperly(pedRef) -- snap to actual ground surface
                Citizen.Wait(200) -- brief settle time after snap
                local st = npcStatus[pedIdx]
                if DoesEntityExist(pedRef) and st and not st.dead then
                    FreezeEntityPosition(pedRef, true)
                    debugLog("  Movement: Stationary (ground-snapped and frozen)")
                end
            end
        end)
    end
    
    return true
end

-- Helper: Clean up untracked (zombie) peds at NPC spawn locations from previous resource instances
local function cleanupZombiePeds(npcList)
    local allPeds = GetGamePool('CPed')
    local playerPed = PlayerPedId()
    local cleaned = 0
    for _, ped in ipairs(allPeds) do
        if DoesEntityExist(ped) and ped ~= playerPed and not IsPedAPlayer(ped) then
            local pedCoords = GetEntityCoords(ped)
            for _, npc in ipairs(npcList or {}) do
                local nx, ny, nz = tonumber(npc.x) or 0, tonumber(npc.y) or 0, tonumber(npc.z) or 0
                if #(pedCoords - vector3(nx, ny, nz)) < DUPLICATE_DETECTION_RADIUS then
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                    cleaned = cleaned + 1
                    break
                end
            end
        end
    end
    return cleaned
end

RegisterNetEvent("npc_dashboard:syncAllNpcs")
AddEventHandler("npc_dashboard:syncAllNpcs", function(npcList)
    -- Debounce: ignore rapid re-syncs (e.g. multiple triggers on restart)
    local now = GetGameTimer()
    if (now - lastSyncTime) < SYNC_DEBOUNCE_MS then
        print("[NPC-SPAWN] syncAllNpcs DEBOUNCED - ignoring (last sync " .. (now - lastSyncTime) .. "ms ago)")
        -- Still update the NPC list for dashboard UI
        AlleNPCsSpawnenLastList = npcList
        return
    end
    
    -- Prevent concurrent sync operations (yields during model loading could allow re-entry)
    if syncInProgress then
        print("[NPC-SPAWN] syncAllNpcs BLOCKED - sync already in progress")
        AlleNPCsSpawnenLastList = npcList
        return
    end
    syncInProgress = true
    lastSyncTime = now
    
    print("[NPC-SPAWN] syncAllNpcs received - " .. #(npcList or {}) .. " NPCs to spawn")
    
    for idx, ped in pairs(gespawnteNpcs) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    gespawnteNpcs = {}
    npcStatus = {}
    AlleNPCsSpawnenLastList = npcList

    -- Clean up zombie peds from previous resource instance at NPC spawn locations
    local zombiesCleaned = cleanupZombiePeds(npcList)
    if zombiesCleaned > 0 then
        print("[NPC-SPAWN] Cleaned up " .. zombiesCleaned .. " zombie peds from previous instance")
    end

    for idx, npc in ipairs(npcList or {}) do
        if npc.x and npc.y and npc.z and npc.model then
            local modelName = tostring(npc.model):gsub("^%s*(.-)%s*$", "%1")
            local modelHash = GetHashKey(modelName)
            
            if not IsModelValid(modelHash) then
                print("[NPC-SPAWN] FAIL: Invalid model: " .. modelName .. " (hash=" .. tostring(modelHash) .. ")")
                goto continueSpawn
            end
            
            local x, y, z = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z)
            local heading = tonumber(npc.heading) or 0.0
            
            -- Load collision at spawn point so the ped doesn't fall through ground
            RequestCollisionAtCoord(x, y, z)
            Citizen.Wait(100) -- Brief wait for collision to begin loading
            
            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 500 do -- 500 × 10ms = 5 seconds max
                Citizen.Wait(10)
                timeout = timeout + 1
            end
            
            if HasModelLoaded(modelHash) then
                local ped = CreatePed(4, modelHash, x, y, z, heading, false, false)
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    if setupNpcPed(ped, npc, idx) then
                        gespawnteNpcs[idx] = ped
                        print("[NPC-SPAWN] SUCCESS: " .. tostring(npc.name or modelName) .. " spawned (ped=" .. tostring(ped) .. ") at " .. x .. "," .. y .. "," .. z)
                    else
                        print("[NPC-SPAWN] FAIL: setupNpcPed failed for " .. tostring(npc.name or modelName))
                        if DoesEntityExist(ped) then DeleteEntity(ped) end
                    end
                else
                    print("[NPC-SPAWN] FAIL: CreatePed returned invalid ped for " .. tostring(npc.name or modelName) .. " (model=" .. modelName .. ", hash=" .. tostring(modelHash) .. ")")
                end
                SetModelAsNoLongerNeeded(modelHash)
            else
                print("[NPC-SPAWN] FAIL: Model not loaded after 5s: " .. modelName .. " (hash=" .. tostring(modelHash) .. ")")
            end
            ::continueSpawn::
        else
            print("[NPC-SPAWN] SKIP: NPC idx=" .. tostring(idx) .. " missing x/y/z/model")
        end
    end
    
    local count = 0
    for _ in pairs(gespawnteNpcs) do count = count + 1 end
    print("[NPC-SPAWN] Sync complete - " .. count .. " NPCs active")
    lastSyncTime = GetGameTimer() -- Update debounce after sync completes (prevents rapid re-syncs)
    syncInProgress = false
end)

RegisterNetEvent("npc_dashboard:updateNPCList")
AddEventHandler("npc_dashboard:updateNPCList", function(npcList)
    SendNUIMessage({ type = "refresh", npcs = npcList or {} })
end)

-- Respawn/Leichenüberwachung
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        -- Skip respawn checks while a full sync is in progress
        if syncInProgress then goto continueLoop end
        
        -- Detect dead NPCs
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            if npc and status and DoesEntityExist(ped) and IsPedDeadOrDying(ped, true) and not status.dead then
                status.dead = true
                status.deathTime = GetGameTimer()
                status.inCombat = false
                status.pursuing = false
                debugLog("NPC died: " .. tostring(npc.name or npc.model))
                DeleteEntity(ped)
                gespawnteNpcs[idx] = nil
            end
        end
        
        -- Detect entities that vanished without dying (streamed out, game engine cleanup)
        for idx, ped in pairs(gespawnteNpcs) do
            if not DoesEntityExist(ped) then
                local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
                local status = npcStatus[idx]
                if status and not status.dead then
                    debugLog("NPC entity vanished (not dead): " .. tostring(npc and (npc.name or npc.model) or "unknown"))
                    status.dead = true
                    status.deathTime = GetGameTimer()
                    gespawnteNpcs[idx] = nil
                end
            end
        end

        -- Respawn dead NPCs after timeout (only if NPC is actually dead and no alive ped exists there)
        -- Pre-fetch game pool once for zombie ped detection (avoid repeated expensive calls per NPC)
        local allPedsForRespawn = nil
        local playerPedForRespawn = PlayerPedId()
        for idx, npc in ipairs(AlleNPCsSpawnenLastList or {}) do
            local status = npcStatus[idx]
            if status and status.dead and not gespawnteNpcs[idx] and GetGameTimer() - (status.deathTime or 0) > Config.DeadTimeout then
                local x, y, z = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z)
                
                -- Check if there's already an alive NPC at this position (prevent duplicates)
                -- Check both tracked NPCs and untracked peds in the game world (zombie peds)
                local alreadyExists = false
                for _, existingPed in pairs(gespawnteNpcs) do
                    if DoesEntityExist(existingPed) and not IsPedDeadOrDying(existingPed, true) then
                        local existingCoords = GetEntityCoords(existingPed)
                        if #(existingCoords - vector3(x, y, z)) < DUPLICATE_DETECTION_RADIUS then
                            alreadyExists = true
                            break
                        end
                    end
                end
                if not alreadyExists then
                    -- Also check game pool for untracked peds at this location (lazy-init once)
                    if not allPedsForRespawn then
                        allPedsForRespawn = GetGamePool('CPed')
                    end
                    for _, ped in ipairs(allPedsForRespawn) do
                        if DoesEntityExist(ped) and ped ~= playerPedForRespawn and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) then
                            local pedCoords = GetEntityCoords(ped)
                            if #(pedCoords - vector3(x, y, z)) < DUPLICATE_DETECTION_RADIUS then
                                alreadyExists = true
                                break
                            end
                        end
                    end
                end
                if alreadyExists then
                    debugLog("Respawn skipped - NPC already alive at position: " .. tostring(npc.name or npc.model))
                    status.dead = false
                    status.deathTime = nil
                    goto continueRespawn
                end
                
                print("[NPC-SPAWN] Respawning: " .. tostring(npc.name or npc.model))
                status.dead = false
                status.deathTime = nil
                status.inCombat = false
                status.pursuing = false
                
                local modelName = tostring(npc.model):gsub("^%s*(.-)%s*$", "%1")
                local modelHash = GetHashKey(modelName)
                
                if not IsModelValid(modelHash) then
                    print("[NPC-SPAWN] Respawn FAIL: Invalid model: " .. modelName)
                    goto continueRespawn
                end
                
                local heading = tonumber(npc.heading) or 0.0
                
                -- Load collision at respawn point
                RequestCollisionAtCoord(x, y, z)
                
                RequestModel(modelHash)
                local timeout = 0
                while not HasModelLoaded(modelHash) and timeout < 500 do -- 500 × 10ms = 5 seconds max
                    Citizen.Wait(10) 
                    timeout = timeout + 1
                end
                
                if HasModelLoaded(modelHash) then
                    local ped = CreatePed(4, modelHash, x, y, z, heading, false, false)
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        if setupNpcPed(ped, npc, idx) then
                            gespawnteNpcs[idx] = ped
                            print("[NPC-SPAWN] Respawn SUCCESS: " .. tostring(npc.name or modelName))
                        else
                            print("[NPC-SPAWN] Respawn FAIL: setup failed for " .. tostring(npc.name or modelName))
                            if DoesEntityExist(ped) then DeleteEntity(ped) end
                        end
                    else
                        print("[NPC-SPAWN] Respawn FAIL: CreatePed invalid for " .. tostring(npc.name or modelName))
                    end
                    SetModelAsNoLongerNeeded(modelHash)
                else
                    print("[NPC-SPAWN] Respawn FAIL: Model not loaded: " .. modelName)
                end
                ::continueRespawn::
            end
        end
        ::continueLoop::
    end
end)

-- NEW: Behavior-specific combat logic
-- Guards help each other, Aggressive attack on sight, Neutral only when attacked, Passive flee

local function isPlayerArmed()
    local playerPed = PlayerPedId()
    local weaponHash = GetSelectedPedWeapon(playerPed)
    -- Check if player has any weapon other than fists/unarmed (hash 2725352035 or GetHashKey("WEAPON_UNARMED"))
    return weaponHash ~= GetHashKey("WEAPON_UNARMED")
end

local function getNearbyGuards(centerPed, radius)
    local guards = {}
    for idx, ped in pairs(gespawnteNpcs) do
        local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
        if npc and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            if normalizeBehavior(npc.behavior) == "Wache" then
                local dist = #(GetEntityCoords(ped) - GetEntityCoords(centerPed))
                if dist <= radius then
                    table.insert(guards, {idx = idx, ped = ped, npc = npc})
                end
            end
        end
    end
    return guards
end

-- Aggressive NPCs: Attack player on sight within radius
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- Check every second
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                if normalizeBehavior(npc.behavior) == "Aggressiv" then
                    local npcCoords = GetEntityCoords(ped)
                    local distToPlayer = #(npcCoords - playerCoords)
                    local radius = getNpcConfig(npc, "radius")
                    local origin = status.origin or vector3(npc.x, npc.y, npc.z)

                    -- FIX #2: Stop any native-GTA-AI combat against an ignored player.
                    -- SetBlockingOfNonTemporaryEvents(false) lets the engine start combat on its
                    -- own (e.g. weapon-draw events), bypassing istSpielerIgnoriert.  We detect
                    -- that here and force-clear it before any attack logic runs.
                    if not status.inCombat and IsPedInCombat(ped, playerPed) and istSpielerIgnoriert(npc) then
                        debugLog("Aggressive NPC: stopping native-AI combat against ignored player: " .. tostring(npc.name or npc.model))
                        ClearPedTasksImmediately(ped)
                        if isMovementEnabled(npc) then
                            FreezeEntityPosition(ped, false)
                            TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                        else
                            TaskStandStill(ped, -1)
                            FreezeEntityPosition(ped, true)
                        end
                    -- Attack if player is within radius and NPC is not already in combat
                    elseif distToPlayer <= radius and not status.inCombat then
                        if not istSpielerIgnoriert(npc) then
                            debugLog("Aggressive NPC attacking player in radius: " .. tostring(npc.name or npc.model))
                            FreezeEntityPosition(ped, false)
                            ClearPedTasksImmediately(ped)
                            reinforceCombatMode(ped)
                            TaskCombatPed(ped, playerPed, 0, 16)
                            status.inCombat = true
                            status.pursuing = true
                            status.lastAttacker = playerPed
                        end
                    elseif status.inCombat then
                        -- FIX #2 (cont.): if an ignored player somehow still has combat tracked,
                        -- cancel it now.
                        if istSpielerIgnoriert(npc) then
                            debugLog("Aggressive NPC: cancelling tracked combat against ignored player: " .. tostring(npc.name or npc.model))
                            status.inCombat = false
                            status.pursuing = false
                            ClearPedTasksImmediately(ped)
                            if isMovementEnabled(npc) then
                                FreezeEntityPosition(ped, false)
                                TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                SetPedKeepTask(ped, true)
                            else
                                TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                            end
                        else
                            -- Pursuit zone: moving NPCs get a larger origin buffer (radius*2) so
                            -- an NPC that wandered to the edge of its area can still chase the
                            -- player without immediately dropping combat.
                            local distToOrigin = #(npcCoords - origin)
                            local maxOriginDist = isMovementEnabled(npc) and (radius * 2.0) or radius
                            if distToOrigin > maxOriginDist or distToPlayer > radius * 1.5 then
                                -- Return to patrol if NPC left zone or player got too far
                                debugLog("Aggressive NPC ending combat - outside radius zone")
                                status.inCombat = false
                                status.pursuing = false
                                ClearPedTasksImmediately(ped)
                                if isMovementEnabled(npc) then
                                    FreezeEntityPosition(ped, false)
                                    TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                    SetPedKeepTask(ped, true)
                                else
                                    TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Guard/Wache NPCs: Defend when attacked, see weapon, or ally is attacked
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local playerArmed = isPlayerArmed()
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                if normalizeBehavior(npc.behavior) == "Wache" then
                    local npcCoords = GetEntityCoords(ped)
                    local distToPlayer = #(npcCoords - playerCoords)
                    local radius = getNpcConfig(npc, "radius")
                    local origin = status.origin or vector3(npc.x, npc.y, npc.z)

                    -- FIX #2: Stop any native-GTA-AI combat against an ignored player.
                    -- Without this, SetBlockingOfNonTemporaryEvents(false) lets the engine
                    -- automatically react to weapon-draw events and start combat, which
                    -- bypasses istSpielerIgnoriert entirely.
                    if not status.inCombat and IsPedInCombat(ped, playerPed) and istSpielerIgnoriert(npc) then
                        debugLog("Guard NPC: stopping native-AI combat against ignored player: " .. tostring(npc.name or npc.model))
                        ClearPedTasksImmediately(ped)
                        if isMovementEnabled(npc) then
                            FreezeEntityPosition(ped, false)
                            TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                        else
                            TaskStandStill(ped, -1)
                            FreezeEntityPosition(ped, true)
                        end
                    else
                    -- Check if this NPC or any nearby guard was attacked
                    local shouldAttack = false
                    local attackReason = ""
                    
                    -- 1. Direct attack on this NPC
                    if HasEntityBeenDamagedByEntity(ped, playerPed, true) then
                        shouldAttack = true
                        attackReason = "was attacked"
                        ClearEntityLastDamageEntity(ped)
                    end
                    
                    -- 2. Player has weapon drawn nearby
                    if not shouldAttack and playerArmed and distToPlayer <= radius * 0.7 then
                        shouldAttack = true
                        attackReason = "player armed nearby"
                    end
                    
                    -- 3. Another guard nearby was attacked
                    if not shouldAttack then
                        local nearbyGuards = getNearbyGuards(ped, radius * 2)
                        for _, guard in ipairs(nearbyGuards) do
                            if HasEntityBeenDamagedByEntity(guard.ped, playerPed, true) then
                                shouldAttack = true
                                attackReason = "ally guard attacked"
                                ClearEntityLastDamageEntity(guard.ped)
                                break
                            end
                        end
                    end
                    
                    if shouldAttack and not status.inCombat and not istSpielerIgnoriert(npc) then
                        debugLog("Guard NPC engaging combat: " .. tostring(npc.name or npc.model) .. " - Reason: " .. attackReason)
                        FreezeEntityPosition(ped, false)
                        ClearPedTasksImmediately(ped)
                        reinforceCombatMode(ped)
                        TaskCombatPed(ped, playerPed, 0, 16)
                        status.inCombat = true
                        status.pursuing = true
                        status.lastAttacker = playerPed
                        
                        -- Alert nearby guards to help
                        local nearbyGuards = getNearbyGuards(ped, radius * 2)
                        for _, guard in ipairs(nearbyGuards) do
                            local guardStatus = npcStatus[guard.idx]
                            if guardStatus and not guardStatus.inCombat then
                                debugLog("  Nearby guard joining fight: " .. tostring(guard.npc.name or guard.npc.model))
                                FreezeEntityPosition(guard.ped, false)
                                ClearPedTasksImmediately(guard.ped)
                                reinforceCombatMode(guard.ped)
                                TaskCombatPed(guard.ped, playerPed, 0, 16)
                                guardStatus.inCombat = true
                                guardStatus.pursuing = true
                                guardStatus.lastAttacker = playerPed
                            end
                        end
                    elseif status.inCombat then
                        -- FIX #2 (cont.): cancel tracked combat against an ignored player
                        if istSpielerIgnoriert(npc) then
                            debugLog("Guard NPC: cancelling tracked combat against ignored player: " .. tostring(npc.name or npc.model))
                            status.inCombat = false
                            status.pursuing = false
                            ClearPedTasksImmediately(ped)
                            if isMovementEnabled(npc) then
                                FreezeEntityPosition(ped, false)
                                TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                SetPedKeepTask(ped, true)
                            else
                                TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                            end
                        else
                            -- Pursuit zone: moving NPCs get a larger origin buffer (radius*2) so
                            -- an NPC that wandered to the edge of its area can still chase the
                            -- player without immediately dropping combat.
                            local distToOrigin = #(npcCoords - origin)
                            local maxOriginDist = isMovementEnabled(npc) and (radius * 2.0) or radius
                            if distToOrigin > maxOriginDist or distToPlayer > radius * 2 then
                                -- Return to post if NPC left zone or player got too far
                                debugLog("Guard NPC ending combat - outside radius zone")
                                status.inCombat = false
                                status.pursuing = false
                                ClearPedTasksImmediately(ped)
                                if isMovementEnabled(npc) then
                                    FreezeEntityPosition(ped, false)
                                    TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                    SetPedKeepTask(ped, true)
                                else
                                    TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                                end
                            end
                        end
                    end
                    end -- end of ignored-player check / native-AI combat prevention
                end
            end
        end
    end
end)

-- Neutral NPCs: Non-violent, no combat at all
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                if normalizeBehavior(npc.behavior) == "Neutral" then
                    -- Ensure neutral NPCs never enter combat
                    if status.inCombat then
                        debugLog("Neutral NPC was in combat, clearing: " .. tostring(npc.name or npc.model))
                        status.inCombat = false
                        status.pursuing = false
                        ClearPedTasksImmediately(ped)
                        -- Only block events for stationary NPCs
                        SetBlockingOfNonTemporaryEvents(ped, not isMovementEnabled(npc))
                        if isMovementEnabled(npc) then
                            local radius = getNpcConfig(npc, "radius")
                            local origin = status.origin or vector3(npc.x, npc.y, npc.z)
                            FreezeEntityPosition(ped, false)
                            TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                        else
                            TaskStandStill(ped, -1)
                            FreezeEntityPosition(ped, true)
                        end
                    end
                    -- Clear any damage flags so NPC doesn't react
                    ClearEntityLastDamageEntity(ped)
                end
            end
        end
    end
end)

-- Movement and despawn logic for NPCs that wander too far
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- Check every second (was 500ms - too aggressive)
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                local origin = status.origin or vector3(npc.x, npc.y, npc.z)
                local pedCoords = GetEntityCoords(ped)
                local distToOrigin = #(pedCoords - origin)
                local radius = getNpcConfig(npc, "radius")
                local now = GetGameTimer()
                
                -- For moving NPCs not in combat:
                -- Only redirect if SIGNIFICANTLY beyond radius (with buffer) AND cooldown has passed
                -- This prevents the old bug where TaskWanderInArea's soft boundary caused
                -- the NPC to slightly exceed radius → task cleared every 500ms → NPC frozen in place
                if isMovementEnabled(npc) and not status.inCombat and distToOrigin > (radius * RADIUS_EXCEED_BUFFER) and (now - (status.lastRedirectTime or 0)) > REDIRECT_COOLDOWN_MS then
                    debugLog("Moving NPC exceeded radius buffer, redirecting: " .. tostring(npc.name or npc.model) .. " (dist: " .. string.format("%.1f", distToOrigin) .. "m, radius: " .. tostring(radius) .. "m)")
                    ClearPedTasksImmediately(ped)
                    FreezeEntityPosition(ped, false)
                    -- Navigate to a random point near origin (not straight to origin, avoids same obstacle path)
                    local navPoint = getRandomNavPoint(origin, radius * 0.5)
                    TaskGoToCoordAnyMeans(ped, navPoint.x, navPoint.y, navPoint.z, 1.0, 0, false, 786603, 0.0)
                    status.lastRedirectTime = now
                    -- After a delay, resume wandering (in separate thread to not block)
                    Citizen.CreateThread(function()
                        Citizen.Wait(5000)
                        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                            local st = npcStatus[idx]
                            if st and not st.inCombat and isMovementEnabled(npc) then
                                FreezeEntityPosition(ped, false)
                                TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                SetPedKeepTask(ped, true)
                            end
                        end
                    end)
                    
                -- For moving NPCs way too far, despawn and respawn
                elseif isMovementEnabled(npc) and not status.pursuing and distToOrigin > radius * DESPAWN_RADIUS_MULTIPLIER then
                    debugLog("Moving NPC way too far, respawning: " .. tostring(npc.name or npc.model))
                    status.dead = true
                    status.deathTime = GetGameTimer()
                    status.inCombat = false
                    status.pursuing = false
                    DeleteEntity(ped)
                    gespawnteNpcs[idx] = nil
                    
                -- For stationary NPCs not in combat, keep them frozen at origin
                elseif not isMovementEnabled(npc) and not status.inCombat then
                    if not IsEntityPositionFrozen(ped) or distToOrigin > 2.0 then
                        -- Return to origin if moved
                        if distToOrigin > 3.0 then
                            debugLog("Stationary NPC moved too far, teleporting back: " .. tostring(npc.name or npc.model))
                            SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false)
                        end
                        ClearPedTasksImmediately(ped)
                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                    end
                    
                -- Return stationary NPCs to origin after combat - tighter radius check
                elseif not isMovementEnabled(npc) and status.inCombat and distToOrigin > radius then
                    debugLog("Stationary NPC too far from origin during combat, returning: " .. tostring(npc.name or npc.model))
                    status.inCombat = false
                    status.pursuing = false
                    ClearPedTasksImmediately(ped)
                    TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                    -- Give NPC time to return, then check and freeze
                    Citizen.Wait(100)
                    Citizen.CreateThread(function()
                        local startTime = GetGameTimer()
                        while DoesEntityExist(ped) and (GetGameTimer() - startTime) < 10000 do
                            local currentDist = #(GetEntityCoords(ped) - origin)
                            if currentDist < 2.0 then
                                -- Close enough, freeze them
                                ClearPedTasksImmediately(ped)
                                TaskStandStill(ped, -1)
                                FreezeEntityPosition(ped, true)
                                debugLog("  NPC returned to origin and frozen")
                                break
                            end
                            Citizen.Wait(500)
                        end
                    end)
                end
            end
        end
    end
end)

-- Stuck detection: re-issue movement tasks when moving NPCs get stuck against walls/obstacles
-- Detects NPCs that aren't moving despite having a wander task, and re-routes them to a
-- random navigable point within their radius for clean direction changes around obstacles.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000) -- Check every 2 seconds
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                if isMovementEnabled(npc) and not status.inCombat then
                    local now = GetGameTimer()
                    
                    -- Skip stuck check during reroute cooldown (NPC was recently re-routed)
                    if (now - (status.lastRerouteTime or 0)) < REROUTE_COOLDOWN_MS then
                        status.lastMovePos = GetEntityCoords(ped)
                        status.lastMoveCheck = now
                    else
                        local pedCoords = GetEntityCoords(ped)
                        local speed = GetEntitySpeed(ped)
                        local origin = status.origin or vector3(npc.x, npc.y, npc.z)
                        local radius = getNpcConfig(npc, "radius")
                        
                        if status.lastMovePos then
                            local movedDist = #(pedCoords - status.lastMovePos)
                            local elapsed = now - (status.lastMoveCheck or 0)
                            
                            -- If NPC barely moved in the last check interval and speed is near 0
                            if elapsed > STUCK_CHECK_INTERVAL_MS and movedDist < STUCK_DISTANCE_THRESHOLD and speed < STUCK_SPEED_THRESHOLD then
                                status.stuckCount = (status.stuckCount or 0) + 1
                                
                                -- After consecutive stuck checks, re-route via random navigable point
                                if status.stuckCount >= STUCK_COUNT_THRESHOLD then
                                    debugLog("Stuck NPC detected, re-routing via random point: " .. tostring(npc.name or npc.model) .. " (stuck " .. tostring(status.stuckCount) .. "x)")
                                    ClearPedTasksImmediately(ped)
                                    Citizen.Wait(50)
                                    if DoesEntityExist(ped) then
                                        FreezeEntityPosition(ped, false)
                                        -- Pick a random navigable point within radius (avoids walking into same obstacle again)
                                        local navPoint = getRandomNavPoint(origin, radius)
                                        TaskGoToCoordAnyMeans(ped, navPoint.x, navPoint.y, navPoint.z, 1.0, 0, false, 786603, 0.0)
                                        -- Resume wandering after reaching the nav point
                                        Citizen.CreateThread(function()
                                            Citizen.Wait(REROUTE_RECOVERY_MS)
                                            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                                                local st = npcStatus[idx]
                                                if st and not st.inCombat and isMovementEnabled(npc) then
                                                    FreezeEntityPosition(ped, false)
                                                    TaskWanderInArea(ped, origin.x, origin.y, origin.z, radius, 2.0, 1.0)
                                                    SetPedKeepTask(ped, true)
                                                end
                                            end
                                        end)
                                    end
                                    status.stuckCount = 0
                                    status.lastRerouteTime = now
                                end
                            else
                                status.stuckCount = 0
                            end
                        end
                        
                        status.lastMovePos = pedCoords
                        status.lastMoveCheck = now
                    end
                end
            end
        end
    end
end)

function istSpielerIgnoriert(npc)
    local xPlayer = ESX.GetPlayerData()
    if not xPlayer then
        debugLog("istSpielerIgnoriert: ESX player data not available yet, defaulting to not ignored")
        return false
    end
    local spielerGruppe = xPlayer.group or ""
    local spielerJob = xPlayer.job and xPlayer.job.name or ""

    local ignorierteGruppen = {}
    local ignorierteJobs = {}
    if npc.ignoreGroups and #npc.ignoreGroups > 0 then
        for group in string.gmatch(npc.ignoreGroups, "([^,%s]+)") do
            ignorierteGruppen[group:lower()] = true
        end
    end
    if npc.ignoreJobs and #npc.ignoreJobs > 0 then
        for job in string.gmatch(npc.ignoreJobs, "([^,%s]+)") do
            ignorierteJobs[job:lower()] = true
        end
    end

    if ignorierteGruppen[spielerGruppe:lower()] or ignorierteJobs[spielerJob:lower()] then
        return true
    end
    return false
end

-- Cleanup: Delete all NPC entities when resource stops (prevents zombie peds after restart)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        local count = 0
        for idx, ped in pairs(gespawnteNpcs) do
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
                count = count + 1
            end
        end
        print("[NPC-SPAWN] Resource stopping - cleaned up " .. count .. " NPC entities")
        gespawnteNpcs = {}
        npcStatus = {}
        AlleNPCsSpawnenLastList = nil
    end
end)

-- Dashboard, NUI, Teleport, Koordinatenwahl, Help etc. (wie gehabt)
Citizen.CreateThread(function()
    while ESX == nil do Citizen.Wait(10) end
    TriggerServerEvent("npc_dashboard:clientGeladen")
end)

-- When player ped spawns (initial spawn + respawns), request NPC sync
AddEventHandler('playerSpawned', function()
    debugLog("Player spawned, checking if NPC sync needed...")
    Citizen.Wait(2000) -- Wait for client scripts and streaming to fully initialize
    -- Only request sync if no NPCs are currently active and no sync is running
    local activeCount = 0
    for _ in pairs(gespawnteNpcs) do activeCount = activeCount + 1 end
    if activeCount == 0 and not syncInProgress then
        debugLog("Player spawned with no active NPCs, requesting sync...")
        TriggerServerEvent("npc_dashboard:clientGeladen")
    else
        debugLog("Player spawned but NPCs already active (" .. activeCount .. "), skipping sync")
    end
end)

-- Fallback: If no NPCs spawned after 10 seconds, request them explicitly
-- This catches edge cases where all other sync mechanisms failed (e.g. race conditions on resource restart)
Citizen.CreateThread(function()
    Citizen.Wait(10000)
    local activeCount = 0
    for _ in pairs(gespawnteNpcs) do activeCount = activeCount + 1 end
    if activeCount == 0 and not syncInProgress then
        debugLog("Fallback: No NPCs spawned after 10s, requesting NPC list...")
        ESX.TriggerServerCallback('npc_dashboard:getNPCList', function(npcs)
            if npcs and #npcs > 0 then
                debugLog("Fallback: Received " .. #npcs .. " NPCs, spawning...")
                TriggerEvent("npc_dashboard:syncAllNpcs", npcs)
            else
                debugLog("Fallback: No NPCs in database")
            end
        end)
    end
end)

RegisterCommand("npcdashboard", function()
    if not istDashboardOffen then
        debugLog("Opening NPC Dashboard")
        istDashboardOffen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "open" })
        ESX.TriggerServerCallback('npc_dashboard:getNPCList', function(data)
            debugLog("Received " .. #(data or {}) .. " NPCs from server for dashboard")
            SendNUIMessage({ type = "refresh", npcs = data or {} })
        end)
    end
end)

RegisterNUICallback("close", function(data, cb)
    debugLog("Closing NPC Dashboard")
    istDashboardOffen = false
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("htmlGeladen", function(data, cb)
    debugLog("HTML/NUI page loaded successfully")
    TriggerServerEvent("npc_dashboard:htmlGeladen")
    cb("ok")
end)

-- ESC key monitoring: force-close dashboard if player presses ESC while it's open
-- Note: When NUI has focus, the JS ESC handler fires first via the browser.
-- This Lua handler is a safety net in case focus state gets out of sync.
Citizen.CreateThread(function()
    while true do
        if istDashboardOffen then
            Citizen.Wait(0) -- Must run every frame to reliably disable ESC/pause menu
            DisableControlAction(0, 200, true) -- Disable ESC default (pause menu) while dashboard is open
            if IsDisabledControlJustPressed(0, 200) then
                debugLog("ESC pressed (Lua) - closing NPC Dashboard")
                istDashboardOffen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ type = "close" })
            end
        else
            Citizen.Wait(200) -- Reduce CPU usage when dashboard is closed
        end
    end
end)

RegisterNUICallback("getNPCList", function(data, cb)
    ESX.TriggerServerCallback('npc_dashboard:getNPCList', function(npcs)
        SendNUIMessage({ type = "refresh", npcs = npcs or {} })
    end)
    cb("ok")
end)

-- Normalize NPC data from NUI before sending to server
local function normalizeNpcData(data)
    if type(data.behavior) == "number" then
        data.behavior = tostring(data.behavior)
    end
    data.movement = tonumber(data.movement) or 0
    data.radius = tonumber(data.radius) or 10
    data.heading = tonumber(data.heading) or 0.0
    return data
end

RegisterNUICallback("addNPC", function(data, cb)
    normalizeNpcData(data)
    TriggerServerEvent("npc_dashboard:addNPC", data)
    cb("ok")
end)

RegisterNUICallback("updateNPC", function(data, cb)
    normalizeNpcData(data)
    TriggerServerEvent("npc_dashboard:updateNPC", data)
    cb("ok")
end)

RegisterNUICallback("deleteNPC", function(data, cb)
    TriggerServerEvent("npc_dashboard:deleteNPC", data.id)
    cb("ok")
end)

RegisterNUICallback("start_coord_pick", function(data, cb)
    istKoordinatenWahl = true
    istDashboardOffen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "open_coordpick" })
    TriggerEvent("npc_dashboard:showHelp", "Gehe zur gewünschten Position und drücke ENTER!")
    cb('ok')

    Citizen.CreateThread(function()
        while istKoordinatenWahl do
            Citizen.Wait(0)
            if IsControlJustPressed(0, 191) then
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local heading = GetEntityHeading(ped)
                SendNUIMessage({
                    type = "coord_selected",
                    coords = { x = coords.x, y = coords.y, z = coords.z },
                    heading = heading
                })
                istKoordinatenWahl = false
                TriggerEvent("npc_dashboard:hideHelp")
                SetNuiFocus(true, true)
                SendNUIMessage({ type = "open" })
                break
            end
        end
    end)
end)

RegisterNUICallback("start_coord_heading_edit", function(data, cb)
    cb('ok') -- Respond immediately; blocking while-loop runs in separate thread to avoid hanging the NUI callback

    Citizen.CreateThread(function()
        istDashboardOffen = false
        SetNuiFocus(false, false)
        local coords = vector3(data.x or 0, data.y or 0, data.z or 0)
        local heading = tonumber(data.npc and data.npc.heading) or 0.0
        local model = (data.model or "mp_m_freemode_01"):gsub("^%s*(.-)%s*$", "%1")
        local hash = GetHashKey(model)

        RequestModel(hash)
        local timer = 0
        while not HasModelLoaded(hash) do
            Citizen.Wait(10)
            timer = timer + 10
            if timer > 5000 then
                debugLog("Failed to load model for heading edit: " .. model)
                SetNuiFocus(true, true)
                SendNUIMessage({ type = "open" })
                return
            end
        end

        local previewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, true)
        FreezeEntityPosition(previewPed, true)
        SetEntityInvincible(previewPed, true)
        SetBlockingOfNonTemporaryEvents(previewPed, true)

        local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(cam, coords.x, coords.y - 3.5, coords.z + 1.5)
        PointCamAtEntity(cam, previewPed, 0.0, 0.0, 0.0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)

        TriggerEvent("npc_dashboard:showHelp", "Bewege mit Maus, Mausrad/A/D für Drehung, ENTER bestätigt, ESC abbricht")
        local running = true

        while running and previewPed and DoesEntityExist(previewPed) do
            local mx, my = GetControlNormal(0, 239), GetControlNormal(0, 240)
            local hit, newCoords = RaycastFromScreen(mx, my, 1000.0)
            if hit and newCoords then
                coords = newCoords
                SetEntityCoords(previewPed, coords.x, coords.y, coords.z, false, false, false, true)
            end

            DisableControlAction(0, 15, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 191, true)
            DisableControlAction(0, 202, true)

            if IsControlJustPressed(0, 15) then heading = heading + 5.0 end
            if IsControlJustPressed(0, 14) then heading = heading - 5.0 end
            if IsControlPressed(0, 34) then heading = heading - 1.0 end
            if IsControlPressed(0, 35) then heading = heading + 1.0 end

            if heading < 0.0 then heading = heading + 360.0 end
            if heading > 360.0 then heading = heading - 360.0 end
            SetEntityHeading(previewPed, heading)

            if IsControlJustPressed(0, 191) then
                SendNUIMessage({ type = "heading_selected", heading = heading, coords = {x = coords.x, y = coords.y, z = coords.z} })
                running = false
            end
            if IsControlJustPressed(0, 202) then
                running = false
            end
            Citizen.Wait(0)
        end
        if previewPed and DoesEntityExist(previewPed) then
            DeleteEntity(previewPed)
        end
        SetModelAsNoLongerNeeded(hash)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        TriggerEvent("npc_dashboard:hideHelp")
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "open" })
    end)
end)

RegisterNUICallback("mouse_pick", function(data, cb)
    local screenX, screenY = data.x, data.y
    local resX, resY = GetActiveScreenResolution()
    local normX = screenX / resX
    local normY = screenY / resY
    local hit, coords = RaycastFromScreen(normX, normY, 1000.0)
    if hit and coords then
        SendNUIMessage({
            type = "coord_selected",
            coords = { x = coords.x, y = coords.y, z = coords.z }
        })
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "close_coordpick" })
    istKoordinatenWahl = false
    cb('ok')
end)

function RaycastFromScreen(normX, normY, distanz)
    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local resX, resY = GetActiveScreenResolution()
    local aspect = resX / resY
    local x = (normX - 0.5) * 2.0 * aspect
    local y = (normY - 0.5) * -2.0
    local dir = camRotToWorld(camRot, x, y)
    local ziel = camPos + dir * distanz
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, ziel.x, ziel.y, ziel.z, 1, PlayerPedId(), 0)
    local _, hit, endCoords, _, _ = GetShapeTestResult(rayHandle)
    return hit, endCoords
end

function camRotToWorld(camRot, relX, relY)
    local radX = math.rad(camRot.x)
    local radY = math.rad(camRot.y)
    local radZ = math.rad(camRot.z)
    local cosX = math.cos(radX)
    local sinX = math.sin(radX)
    local cosY = math.cos(radY)
    local sinY = math.sin(radY)
    local cosZ = math.cos(radZ)
    local sinZ = math.sin(radZ)
    local forward = vector3(-sinZ * cosX, cosZ * cosX, sinX)
    local right = vector3(cosZ * cosY + sinZ * sinX * sinY, sinZ * cosY - cosZ * sinX * sinY, -cosX * sinY)
    local up = vector3(cosZ * sinY - sinZ * sinX * cosY, sinZ * sinY + cosZ * sinX * cosY, cosX * cosY)
    return forward + right * relX + up * relY
end

RegisterNetEvent("npc_dashboard:showHelp")
AddEventHandler("npc_dashboard:showHelp", function(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, 5000)
end)

RegisterNetEvent("npc_dashboard:hideHelp")
AddEventHandler("npc_dashboard:hideHelp", function()
    ClearAllHelpMessages()
end)

RegisterNUICallback("teleportToNPC", function(data, cb)
    TriggerServerEvent("npc_dashboard:teleportToNpc", data.id)
    cb("ok")
end)

RegisterNetEvent("npc_dashboard:doTeleport")
AddEventHandler("npc_dashboard:doTeleport", function(x, y, z, richtung)
    local ped = PlayerPedId()
    if ped and x and y and z then
        SetEntityCoords(ped, tonumber(x), tonumber(y), tonumber(z), false, false, false, true)
        SetEntityHeading(ped, tonumber(richtung) or 0.0)
    end
end)
