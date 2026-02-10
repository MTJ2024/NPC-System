-- NPC Dashboard Client with proper behavior-specific combat logic
-- KEIN dofile, KEIN require – Config kommt global durch fxmanifest.lua

ESX = exports["es_extended"]:getSharedObject()

local istDashboardOffen = false
local istKoordinatenWahl = false
local gespawnteNpcs = {}
local npcStatus = {}
local AlleNPCsSpawnenLastList = nil
local lastNpcDelete = {}

-- Debug logging helper
local function debugLog(msg)
    if Config and Config.Debug then
        print("[NPC-DEBUG] " .. tostring(msg))
    end
end

-- Spezialwerte aus Config holen
local function getNpcConfig(npc, key)
    if npc and npc.id and Config.SpecialNpcs and Config.SpecialNpcs[npc.id] and Config.SpecialNpcs[npc.id][key] ~= nil then
        return Config.SpecialNpcs[npc.id][key]
    end
    -- Map config keys that don't follow the Default... pattern
    if key == "invincible" then
        return Config.NPCInvincible
    end
    return Config["Default" .. key:sub(1,1):upper() .. key:sub(2)]
end

-- Helper: check if movement is enabled (handles number, string, bool from DB/JSON)
local function isMovementEnabled(npc)
    return npc.movement == 1 or npc.movement == true or npc.movement == "1" or tonumber(npc.movement) == 1
end

local function npcIsAtOrigin(npc, ped)
    if not npc or not ped then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(npc.x, npc.y, npc.z)) < (getNpcConfig(npc, "radius") * 1.2)
end

-- Helper: Get ground Z coordinate for proper placement
local function getGroundZ(x, y, z)
    local retval, groundZ = GetGroundZFor_3dCoord(x, y, z + 1000.0, false)
    if retval then
        return groundZ
    end
    return z
end

-- Helper: Setup NPC with proper ground placement and behavior
local function setupNpcPed(ped, npc, idx)
    if not DoesEntityExist(ped) then return false end
    
    debugLog("Setting up NPC: " .. tostring(npc.name or npc.model) .. " (Behavior: " .. tostring(npc.behavior) .. ")")
    
    SetEntityAsMissionEntity(ped, true, true)
    SetPedKeepTask(ped, true)
    
    -- Get proper ground Z and place NPC
    local groundZ = getGroundZ(npc.x, npc.y, npc.z)
    SetEntityCoords(ped, npc.x, npc.y, groundZ, false, false, false, false)
    SetEntityHeading(ped, npc.heading or 0.0)
    
    -- Wait a frame for physics to settle
    Citizen.Wait(100)
    
    -- Set health and invincibility
    SetEntityHealth(ped, getNpcConfig(npc, "health"))
    SetEntityInvincible(ped, getNpcConfig(npc, "invincible") == true)
    
    -- Give weapon if configured
    local npcWeapon = npc.weapon
    if npcWeapon and npcWeapon ~= "" and npcWeapon ~= "None" then
        GiveWeaponToPed(ped, GetHashKey(npcWeapon), 999, false, true)
        debugLog("  Weapon given: " .. npcWeapon)
    end
    
    -- Behavior-specific setup
    local behavior = npc.behavior or "Passiv"
    
    if behavior == "Passiv" then
        -- Passive NPCs block all events and never fight
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, true) -- Can flee
        debugLog("  Behavior: Passive (non-combat)")
        
    elseif behavior == "Neutral" then
        -- Neutral NPCs can fight back when attacked but don't seek combat
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCombatAbility(ped, 1) -- Average combat ability
        SetPedCombatRange(ped, 2) -- Medium range
        SetPedFleeAttributes(ped, 0, false) -- Won't flee
        debugLog("  Behavior: Neutral (defensive)")
        
    elseif behavior == "Wache" or behavior == "Guard" then
        -- Guard NPCs actively defend and help allies
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCombatAbility(ped, 2) -- Professional
        SetPedCombatRange(ped, 2) -- Medium range
        SetPedFleeAttributes(ped, 0, false) -- Never flee
        SetPedCombatAttributes(ped, 46, true) -- Can fight armed peds when not armed
        SetPedCombatAttributes(ped, 5, true) -- Can use vehicles
        SetPedSeeingRange(ped, getNpcConfig(npc, "radius") * 1.5)
        SetPedHearingRange(ped, getNpcConfig(npc, "radius") * 1.5)
        debugLog("  Behavior: Guard (protective, will help allies)")
        
    elseif behavior == "Aggressiv" then
        -- Aggressive NPCs attack on sight within radius
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCombatAbility(ped, 2) -- Professional
        SetPedCombatRange(ped, 2) -- Medium range
        SetPedFleeAttributes(ped, 0, false) -- Never flee
        SetPedCombatAttributes(ped, 46, true) -- Can fight armed peds when not armed
        SetPedCombatAttributes(ped, 5, true) -- Can use vehicles
        SetPedSeeingRange(ped, getNpcConfig(npc, "radius"))
        SetPedHearingRange(ped, getNpcConfig(npc, "radius"))
        debugLog("  Behavior: Aggressive (hostile)")
    end
    
    -- Initialize status tracking
    npcStatus[idx] = {
        busy = false,
        pursuing = false,
        origin = vector3(npc.x, npc.y, groundZ),
        deathTime = nil,
        dead = false,
        respawnAt = 0,
        inCombat = false,
        lastAttacker = nil
    }
    
    -- Set initial movement behavior
    if isMovementEnabled(npc) then
        FreezeEntityPosition(ped, false)
        TaskWanderStandard(ped, 10.0, 10)
        debugLog("  Movement: Wandering")
    else
        ClearPedTasksImmediately(ped)
        TaskStandStill(ped, -1)
        FreezeEntityPosition(ped, true)
        debugLog("  Movement: Stationary")
    end
    
    return true
end

RegisterNetEvent("npc_dashboard:syncAllNpcs")
AddEventHandler("npc_dashboard:syncAllNpcs", function(npcList)
    debugLog("Syncing all NPCs - Total: " .. #(npcList or {}))
    
    for idx, ped in pairs(gespawnteNpcs) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    gespawnteNpcs = {}
    npcStatus = {}
    AlleNPCsSpawnenLastList = npcList

    for idx, npc in ipairs(npcList or {}) do
        if npc.x and npc.y and npc.z and npc.model then
            local modelHash = GetHashKey(npc.model)
            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 100 do 
                Citizen.Wait(10)
                timeout = timeout + 1
            end
            
            if HasModelLoaded(modelHash) then
                local ped = CreatePed(4, modelHash, npc.x, npc.y, npc.z, npc.heading or 0.0, true, false)
                if setupNpcPed(ped, npc, idx) then
                    gespawnteNpcs[idx] = ped
                    debugLog("NPC spawned successfully: " .. tostring(npc.name or npc.model))
                else
                    debugLog("Failed to setup NPC: " .. tostring(npc.name or npc.model))
                    if DoesEntityExist(ped) then DeleteEntity(ped) end
                end
            else
                debugLog("Failed to load model: " .. npc.model)
            end
        end
    end
    
    debugLog("Sync complete - Active NPCs: " .. #gespawnteNpcs)
end)

RegisterNetEvent("npc_dashboard:updateNPCList")
AddEventHandler("npc_dashboard:updateNPCList", function(npcList)
    SendNUIMessage({ type = "refresh", npcs = npcList or {} })
end)

-- Respawn/Leichenüberwachung
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
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

        for idx, npc in ipairs(AlleNPCsSpawnenLastList or {}) do
            local status = npcStatus[idx]
            if status and status.dead and not gespawnteNpcs[idx] and GetGameTimer() - (status.deathTime or 0) > Config.DeadTimeout then
                debugLog("Respawning NPC: " .. tostring(npc.name or npc.model))
                status.dead = false
                status.deathTime = nil
                status.inCombat = false
                status.pursuing = false
                
                local modelHash = GetHashKey(npc.model)
                RequestModel(modelHash)
                local timeout = 0
                while not HasModelLoaded(modelHash) and timeout < 100 do 
                    Citizen.Wait(10) 
                    timeout = timeout + 1
                end
                
                if HasModelLoaded(modelHash) then
                    local ped = CreatePed(4, modelHash, npc.x, npc.y, npc.z, npc.heading or 0.0, true, false)
                    if setupNpcPed(ped, npc, idx) then
                        gespawnteNpcs[idx] = ped
                        debugLog("NPC respawned successfully: " .. tostring(npc.name or npc.model))
                    else
                        debugLog("Failed to respawn NPC: " .. tostring(npc.name or npc.model))
                        if DoesEntityExist(ped) then DeleteEntity(ped) end
                    end
                end
            end
        end
    end
end)

-- NEW: Behavior-specific combat logic
-- Guards help each other, Aggressive attack on sight, Neutral only when attacked, Passive flee

local function isPlayerArmed()
    local playerPed = PlayerPedId()
    local weaponHash = GetSelectedPedWeapon(playerPed)
    -- Unarmed is hash 2725352035
    return weaponHash ~= GetHashKey("WEAPON_UNARMED")
end

local function getNearbyGuards(centerPed, radius)
    local guards = {}
    for idx, ped in pairs(gespawnteNpcs) do
        local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
        if npc and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            if npc.behavior == "Wache" or npc.behavior == "Guard" then
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
                if npc.behavior == "Aggressiv" then
                    local npcCoords = GetEntityCoords(ped)
                    local distToPlayer = #(npcCoords - playerCoords)
                    local radius = getNpcConfig(npc, "radius")
                    
                    -- Attack if player is within radius and NPC is not already in combat
                    if distToPlayer <= radius and not status.inCombat then
                        if not istSpielerIgnoriert(npc) then
                            debugLog("Aggressive NPC attacking player in radius: " .. tostring(npc.name or npc.model))
                            FreezeEntityPosition(ped, false)
                            ClearPedTasksImmediately(ped)
                            TaskCombatPed(ped, playerPed, 0, 16)
                            status.inCombat = true
                            status.pursuing = true
                            status.lastAttacker = playerPed
                        end
                    elseif distToPlayer > radius * 1.5 and status.inCombat then
                        -- Return to patrol if player gets too far
                        debugLog("Aggressive NPC ending combat - player too far")
                        status.inCombat = false
                        status.pursuing = false
                        ClearPedTasksImmediately(ped)
                        if isMovementEnabled(npc) then
                            TaskWanderStandard(ped, 10.0, 10)
                        else
                            TaskGoToCoordAnyMeans(ped, npc.x, npc.y, npc.z, 1.0, 0, false, 786603, 0.0)
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
                if npc.behavior == "Wache" or npc.behavior == "Guard" then
                    local npcCoords = GetEntityCoords(ped)
                    local distToPlayer = #(npcCoords - playerCoords)
                    local radius = getNpcConfig(npc, "radius")
                    
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
                                TaskCombatPed(guard.ped, playerPed, 0, 16)
                                guardStatus.inCombat = true
                                guardStatus.pursuing = true
                                guardStatus.lastAttacker = playerPed
                            end
                        end
                    elseif status.inCombat and distToPlayer > radius * 2 then
                        -- Return to post if player gets too far
                        debugLog("Guard NPC ending combat - player too far")
                        status.inCombat = false
                        status.pursuing = false
                        ClearPedTasksImmediately(ped)
                        if isMovementEnabled(npc) then
                            TaskWanderStandard(ped, 10.0, 10)
                        else
                            TaskGoToCoordAnyMeans(ped, npc.x, npc.y, npc.z, 1.0, 0, false, 786603, 0.0)
                        end
                    end
                end
            end
        end
    end
end)

-- Neutral NPCs: Only fight back when directly attacked
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                if npc.behavior == "Neutral" then
                    local npcCoords = GetEntityCoords(ped)
                    local distToPlayer = #(npcCoords - playerCoords)
                    local radius = getNpcConfig(npc, "radius")
                    
                    -- Only fight back if directly attacked
                    if HasEntityBeenDamagedByEntity(ped, playerPed, true) and not status.inCombat then
                        if not istSpielerIgnoriert(npc) then
                            debugLog("Neutral NPC defending itself: " .. tostring(npc.name or npc.model))
                            FreezeEntityPosition(ped, false)
                            ClearPedTasksImmediately(ped)
                            TaskCombatPed(ped, playerPed, 0, 16)
                            status.inCombat = true
                            status.pursuing = false -- Don't pursue, just defend
                            status.lastAttacker = playerPed
                        end
                        ClearEntityLastDamageEntity(ped)
                    elseif status.inCombat and distToPlayer > radius * 1.5 then
                        -- Stop fighting if player gets away
                        debugLog("Neutral NPC ending combat - player escaped")
                        status.inCombat = false
                        ClearPedTasksImmediately(ped)
                        if isMovementEnabled(npc) then
                            TaskWanderStandard(ped, 10.0, 10)
                        else
                            TaskGoToCoordAnyMeans(ped, npc.x, npc.y, npc.z, 1.0, 0, false, 786603, 0.0)
                        end
                    end
                end
            end
        end
    end
end)

-- Movement and despawn logic for NPCs that wander too far
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                local origin = status.origin or vector3(npc.x, npc.y, npc.z)
                local pedCoords = GetEntityCoords(ped)
                local distToOrigin = #(pedCoords - origin)
                local radius = getNpcConfig(npc, "radius")
                
                -- For moving NPCs, despawn if they wander too far
                if isMovementEnabled(npc) and not status.pursuing and distToOrigin > radius * 1.5 then
                    debugLog("Moving NPC wandered too far, respawning: " .. tostring(npc.name or npc.model))
                    status.dead = true
                    status.deathTime = GetGameTimer()
                    DeleteEntity(ped)
                    gespawnteNpcs[idx] = nil
                    
                -- For stationary NPCs not in combat, keep them frozen at origin
                elseif not isMovementEnabled(npc) and not status.inCombat then
                    if not IsEntityPositionFrozen(ped) or distToOrigin > 2.0 then
                        -- Return to origin if moved
                        if distToOrigin > 5.0 then
                            debugLog("Stationary NPC moved too far, teleporting back: " .. tostring(npc.name or npc.model))
                            SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false)
                        end
                        ClearPedTasksImmediately(ped)
                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                    end
                    
                -- Return stationary NPCs to origin after combat ends
                elseif not isMovementEnabled(npc) and status.inCombat and distToOrigin > radius * 2 then
                    debugLog("Stationary NPC too far from origin, returning: " .. tostring(npc.name or npc.model))
                    status.inCombat = false
                    status.pursuing = false
                    ClearPedTasksImmediately(ped)
                    TaskGoToCoordAnyMeans(ped, origin.x, origin.y, origin.z, 1.0, 0, false, 786603, 0.0)
                    Citizen.Wait(5000) -- Wait for NPC to get back
                    if DoesEntityExist(ped) then
                        FreezeEntityPosition(ped, true)
                    end
                end
            end
        end
    end
end)

function istSpielerIgnoriert(npc)
    local xPlayer = ESX.GetPlayerData()
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

-- Dashboard, NUI, Teleport, Koordinatenwahl, Help etc. (wie gehabt)
Citizen.CreateThread(function()
    while ESX == nil do Citizen.Wait(10) end
    TriggerServerEvent("npc_dashboard:clientGeladen")
end)

RegisterCommand("npcdashboard", function()
    if not istDashboardOffen then
        istDashboardOffen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "open" })
        ESX.TriggerServerCallback('npc_dashboard:getNPCList', function(data)
            SendNUIMessage({ type = "refresh", npcs = data or {} })
        end)
    end
end)

RegisterNUICallback("close", function()
    istDashboardOffen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "close" })
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
    istDashboardOffen = false
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
            cb('error')
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
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    TriggerEvent("npc_dashboard:hideHelp")
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "open" })
    cb('ok')
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