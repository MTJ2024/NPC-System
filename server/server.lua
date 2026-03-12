ESX = exports["es_extended"]:getSharedObject()

-- Debug logging helper
local function debugLog(msg)
    print("[NPC-SERVER-DEBUG] " .. tostring(msg))
end

debugLog("NPC Dashboard Server starting...")

-- Nur diese Typen sind erlaubt! (inkl. Army)
local npcTypes = {
    { name = "Polizist", model = "s_m_y_cop_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Sheriff", model = "s_m_y_sheriff_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Gangmitglied", model = "g_m_y_ballaeast_01", weapon = "WEAPON_MICROSMG", behavior = "Aggressiv", radius = 10 },
    { name = "Mafia", model = "g_m_m_chicold_01", weapon = "WEAPON_PISTOL", behavior = "Aggressiv", radius = 10 },
    { name = "Dealer", model = "g_m_y_mexgoon_01", weapon = "WEAPON_PISTOL", behavior = "Neutral", radius = 10 },
    { name = "Sicherheitskraft", model = "s_m_m_security_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Leibwächter", model = "s_m_m_highsec_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Leibwächter 2", model = "s_m_m_highsec_02", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Türsteher", model = "s_m_m_bouncer_01", weapon = "WEAPON_BAT", behavior = "Wache", radius = 10 },
    { name = "Koch mit Messer", model = "s_m_y_chef_01", weapon = "WEAPON_KNIFE", behavior = "Passiv", radius = 8 },
    { name = "Pilot mit Pistole", model = "s_m_m_pilot_01", weapon = "WEAPON_PISTOL", behavior = "Neutral", radius = 10 },
    { name = "Mechaniker mit Schraubenschlüssel", model = "s_m_m_autoshop_01", weapon = "WEAPON_WRENCH", behavior = "Neutral", radius = 8 },
    { name = "Geschäftsmann", model = "a_m_m_business_01", weapon = "", behavior = "Passiv", radius = 8 },
    { name = "VIP", model = "a_m_y_business_01", weapon = "", behavior = "Neutral", radius = 8 },
    { name = "Sanitäter", model = "s_m_m_paramedic_01", weapon = "", behavior = "Passiv", radius = 10 },
    { name = "Feuerwehrmann", model = "s_m_y_fireman_01", weapon = "", behavior = "Passiv", radius = 10 },
    { name = "Taxifahrer", model = "s_m_m_taxi_01", weapon = "", behavior = "Passiv", radius = 8 },
    { name = "Obdachloser", model = "a_m_m_tramp_01", weapon = "", behavior = "Passiv", radius = 8 },
    { name = "Jogger", model = "a_m_y_jogger_01", weapon = "", behavior = "Passiv", radius = 8 },
    { name = "Bauarbeiter", model = "s_m_y_construct_01", weapon = "", behavior = "Neutral", radius = 10 },
    { name = "Arzt", model = "s_m_m_doctor_01", weapon = "", behavior = "Passiv", radius = 10 },
    { name = "Landwirt", model = "a_m_m_farmer_01", weapon = "", behavior = "Passiv", radius = 10 },
    { name = "Army", model = "s_m_y_marine_03", weapon = "WEAPON_CARBINERIFLE", behavior = "Aggressiv", radius = 20 }
}

local allowedModels = {}
local allowedWeapons = {}
for _, v in ipairs(npcTypes) do
    allowedModels[v.model] = true
    if v.weapon and v.weapon ~= "" then
        allowedWeapons[v.weapon] = true
    end
end

local function isAllowedModel(model)
    return allowedModels[model] == true
end
local function isAllowedWeapon(weapon)
    return weapon == "" or allowedWeapons[weapon] == true
end

local function isAdmin(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local group = xPlayer.getGroup and xPlayer.getGroup() or xPlayer.group
    return group == "admin" or group == "superadmin"
end

local function npcExists(model, x, y, z)
    local finished, exists = false, false
    exports.oxmysql:execute('SELECT id FROM npc_dashboard_npcs WHERE model = ? AND x = ? AND y = ? AND z = ? LIMIT 1',
    {model, x, y, z}, function(rows)
        exists = rows and #rows > 0
        finished = true
    end)
    while not finished do Citizen.Wait(0) end
    return exists
end

local clientGeladen, serverGeladen, htmlGeladen = false, false, false

RegisterNetEvent("npc_dashboard:clientGeladen")
AddEventHandler("npc_dashboard:clientGeladen", function()
    local src = source
    clientGeladen = true
    debugLog("Client " .. tostring(src) .. " loaded, sending NPCs...")
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        if GetPlayerName(src) then
            TriggerClientEvent("npc_dashboard:syncAllNpcs", src, npcs or {})
            TriggerClientEvent("npc_dashboard:updateNPCList", src, npcs or {})
            debugLog("Sent " .. #(npcs or {}) .. " NPCs to client " .. tostring(src))
        end
    end)
end)

RegisterNetEvent("npc_dashboard:htmlGeladen")
AddEventHandler("npc_dashboard:htmlGeladen", function()
    htmlGeladen = true
end)

local function ladeAlleNpcs(callback)
    debugLog("Loading all NPCs from database...")
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        local placedNpcs = npcs or {}
        debugLog("Loaded " .. #placedNpcs .. " NPCs from database")
        if callback then callback(placedNpcs) end
        -- Update the UI list for all clients
        TriggerClientEvent("npc_dashboard:updateNPCList", -1, placedNpcs)
        -- Also sync/spawn the actual NPC peds in-game for all clients
        TriggerClientEvent("npc_dashboard:syncAllNpcs", -1, placedNpcs)
        debugLog("Broadcasted NPCs to all clients")
    end)
end

RegisterNetEvent("npc_dashboard:forceBroadcastAllNpcs")
AddEventHandler("npc_dashboard:forceBroadcastAllNpcs", function()
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        TriggerClientEvent("npc_dashboard:syncAllNpcs", -1, npcs or {})
    end)
end)

RegisterNetEvent("esx:playerLoaded")
AddEventHandler("esx:playerLoaded", function(playerData, isNew, skin)
    local src = source
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        if src then
            TriggerClientEvent("npc_dashboard:syncAllNpcs", src, npcs or {})
        end
    end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        serverGeladen = true
        debugLog("Resource started, loading NPCs from database...")
        -- ladeAlleNpcs already broadcasts syncAllNpcs to all clients when DB responds.
        -- Clients also request NPCs via clientGeladen when they initialize.
        -- No additional delayed broadcast needed - it caused duplicate respawns.
        ladeAlleNpcs()
    end
end)

RegisterNetEvent("npc_dashboard:addNPC")
AddEventHandler("npc_dashboard:addNPC", function(data)
    local src = source
    debugLog("addNPC called by player " .. src)
    if not isAdmin(src) then 
        debugLog("  DENIED: Player is not admin")
        return 
    end
    if not data or not data.model or not isAllowedModel(data.model) then 
        debugLog("  DENIED: Invalid model or data")
        return 
    end
    local weapon = data.weapon or ""
    if not isAllowedWeapon(weapon) then 
        debugLog("  DENIED: Invalid weapon")
        return 
    end
    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
    if not x or not y or not z then 
        debugLog("  DENIED: Invalid coordinates")
        return 
    end
    if npcExists(data.model, x, y, z) then 
        debugLog("  DENIED: NPC already exists at this location")
        return 
    end
    
    debugLog("  Adding NPC: " .. tostring(data.name or "NPC") .. " (" .. data.model .. ") at " .. x .. "," .. y .. "," .. z)
    exports.oxmysql:execute([[
        INSERT INTO npc_dashboard_npcs 
        (name, model, weapon, behavior, radius, x, y, z, heading, violent, movement, ignoreGroups, ignoreJobs)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name or "NPC", data.model, weapon, data.behavior or "Passiv",
        tonumber(data.radius) or 10, x, y, z, tonumber(data.heading) or 0.0,
        tonumber(data.violent) or 0, tonumber(data.movement) or 0,
        data.ignoreGroups or '', data.ignoreJobs or ''
    }, function()
        debugLog("  NPC added successfully, reloading all NPCs")
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:updateNPC")
AddEventHandler("npc_dashboard:updateNPC", function(data)
    local src = source
    debugLog("updateNPC called by player " .. src)
    if not isAdmin(src) then 
        debugLog("  DENIED: Player is not admin")
        return 
    end
    if not data or not data.model or not data.id or not isAllowedModel(data.model) then 
        debugLog("  DENIED: Invalid model, data, or missing ID")
        return 
    end
    local weapon = data.weapon or ""
    if not isAllowedWeapon(weapon) then 
        debugLog("  DENIED: Invalid weapon")
        return 
    end
    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
    if not x or not y or not z then 
        debugLog("  DENIED: Invalid coordinates")
        return 
    end
    
    debugLog("  Updating NPC ID " .. data.id .. ": " .. tostring(data.name or "NPC") .. " (" .. data.model .. ")")
    exports.oxmysql:execute([[
        UPDATE npc_dashboard_npcs SET
        name = ?, model = ?, weapon = ?, behavior = ?, radius = ?, x = ?, y = ?, z = ?, heading = ?, violent = ?, movement = ?, ignoreGroups = ?, ignoreJobs = ?
        WHERE id = ?
    ]], {
        data.name or "NPC", data.model, weapon, data.behavior or "Passiv",
        tonumber(data.radius) or 10, x, y, z,
        tonumber(data.heading) or 0.0, tonumber(data.violent) or 0, tonumber(data.movement) or 0,
        data.ignoreGroups or '', data.ignoreJobs or '', data.id
    }, function()
        debugLog("  NPC updated successfully, reloading all NPCs")
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:deleteNPC")
AddEventHandler("npc_dashboard:deleteNPC", function(id)
    local src = source
    debugLog("deleteNPC called by player " .. src .. " for NPC ID " .. tostring(id))
    if not isAdmin(src) then 
        debugLog("  DENIED: Player is not admin")
        return 
    end
    exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs WHERE id = ?', {id}, function()
        debugLog("  NPC deleted successfully, reloading all NPCs")
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:deleteAllNPCs")
AddEventHandler("npc_dashboard:deleteAllNPCs", function()
    local src = source
    if not isAdmin(src) then return end
    exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs', {}, function()
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:teleportToNpc")
AddEventHandler("npc_dashboard:teleportToNpc", function(npcId)
    local src = source
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs WHERE id = ?', {npcId}, function(rows)
        local npc = rows and rows[1]
        if npc and src then
            TriggerClientEvent("npc_dashboard:doTeleport", src, npc.x or 0, npc.y or 0, npc.z or 0, npc.heading or 0)
        end
    end)
end)

ESX.RegisterServerCallback('npc_dashboard:getNPCList', function(source, cb)
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        cb(npcs or {})
    end)
end)

ESX.RegisterServerCallback('npc_dashboard:getNPCTypes', function(source, cb)
    cb(npcTypes)
end)

-- Respawn-System: Handled entirely on client side (client/client.lua death monitoring thread).
-- Server-side DB manipulation on NPC death was removed because:
-- 1. It created new DB records (delete+insert) which caused duplicate NPC spawns
-- 2. The full broadcast (forceBroadcastAllNpcs) triggered all clients to respawn ALL NPCs
-- 3. Multiple clients reporting the same death caused cascading duplicates
-- Client handles respawn locally after Config.DeadTimeout with duplicate detection.
