ESX = exports["es_extended"]:getSharedObject()

-- Nur diese Typen sind erlaubt! (inkl. Army)
local npcTypes = {
    { name = "Polizist", model = "s_m_y_cop_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Sheriff", model = "s_m_y_sheriff_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
    { name = "Gangmitglied", model = "g_m_y_ballaeast_01", weapon = "WEAPON_MICROSMG", behavior = "Aggressiv", radius = 10 },
    { name = "Mafia", model = "g_m_m_chicold_01", weapon = "WEAPON_PISTOL", behavior = "Aggressiv", radius = 10 },
    { name = "Dealer", model = "g_m_y_mexgoon_01", weapon = "WEAPON_PISTOL", behavior = "Neutral", radius = 10 },
    { name = "Sicherheitskraft", model = "s_m_m_security_01", weapon = "WEAPON_PISTOL", behavior = "Wache", radius = 15 },
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
    clientGeladen = true
end)

RegisterNetEvent("npc_dashboard:htmlGeladen")
AddEventHandler("npc_dashboard:htmlGeladen", function()
    htmlGeladen = true
end)

local function ladeAlleNpcs(callback)
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs', {}, function(npcs)
        local placedNpcs = npcs or {}
        if callback then callback(placedNpcs) end
        -- Update the UI list for all clients
        TriggerClientEvent("npc_dashboard:updateNPCList", -1, placedNpcs)
        -- Also sync/spawn the actual NPC peds in-game for all clients
        TriggerClientEvent("npc_dashboard:syncAllNpcs", -1, placedNpcs)
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
        ladeAlleNpcs(function(npcs)
            Citizen.CreateThread(function()
                Citizen.Wait(3000)
                if type(npcs) == "table" and #npcs > 0 then
                    TriggerEvent("npc_dashboard:forceBroadcastAllNpcs")
                end
            end)
        end)
    end
end)

RegisterNetEvent("npc_dashboard:addNPC")
AddEventHandler("npc_dashboard:addNPC", function(data)
    local src = source
    if not isAdmin(src) then return end
    if not data or not isAllowedModel(data.model) or not isAllowedWeapon(data.weapon) then return end
    if npcExists(data.model, data.x, data.y, data.z) then return end
    exports.oxmysql:execute([[
        INSERT INTO npc_dashboard_npcs 
        (name, model, weapon, behavior, radius, x, y, z, heading, violent, movement, ignoreGroups, ignoreJobs)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name, data.model, data.weapon, data.behavior, data.radius or 10, data.x, data.y, data.z, data.heading or 0.0,
        data.violent or 0, data.movement or 0, data.ignoreGroups or '', data.ignoreJobs or ''
    }, function()
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:updateNPC")
AddEventHandler("npc_dashboard:updateNPC", function(data)
    local src = source
    if not isAdmin(src) then return end
    if not data or not isAllowedModel(data.model) or not isAllowedWeapon(data.weapon) then return end
    exports.oxmysql:execute([[
        UPDATE npc_dashboard_npcs SET
        name = ?, model = ?, weapon = ?, behavior = ?, radius = ?, x = ?, y = ?, z = ?, heading = ?, violent = ?, movement = ?, ignoreGroups = ?, ignoreJobs = ?
        WHERE id = ?
    ]], {
        data.name, data.model, data.weapon, data.behavior, data.radius or 10, data.x, data.y, data.z, data.heading or 0.0,
        data.violent or 0, data.movement or 0, data.ignoreGroups or '', data.ignoreJobs or '', data.id
    }, function()
        ladeAlleNpcs()
    end)
end)

RegisterNetEvent("npc_dashboard:deleteNPC")
AddEventHandler("npc_dashboard:deleteNPC", function(id)
    local src = source
    if not isAdmin(src) then return end
    exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs WHERE id = ?', {id}, function()
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

-- Respawn-System: Spawnt einen neuen NPC, wenn keiner im Radius existiert
RegisterNetEvent("npc_dashboard:npcDied")
AddEventHandler("npc_dashboard:npcDied", function(npcId, x, y, z, model, radius)
    exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs WHERE model = ?', {model}, function(npcs)
        local found = false
        for _, npc in ipairs(npcs) do
            if tostring(npc.id) ~= tostring(npcId) then
                local dx = tonumber(x) - tonumber(npc.x)
                local dy = tonumber(y) - tonumber(npc.y)
                local dz = tonumber(z) - tonumber(npc.z)
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist < (tonumber(radius) or 10.0) then
                    found = true
                    break
                end
            end
        end
        if not found then
            exports.oxmysql:execute('SELECT * FROM npc_dashboard_npcs WHERE id = ?', {npcId}, function(rows)
                local old = rows and rows[1]
                if old then
                    exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs WHERE id = ?', {npcId}, function()
                        exports.oxmysql:execute([[
                            INSERT INTO npc_dashboard_npcs 
                            (name, model, weapon, behavior, radius, x, y, z, heading, violent, movement, ignoreGroups, ignoreJobs)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ]], {
                            old.name, old.model, old.weapon, old.behavior, old.radius, x, y, z, old.heading,
                            old.violent, old.movement, old.ignoreGroups or '', old.ignoreJobs or ''
                        }, function()
                            TriggerEvent("npc_dashboard:forceBroadcastAllNpcs")
                        end)
                    end)
                else
                    exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs WHERE id = ?', {npcId})
                end
            end)
        else
            exports.oxmysql:execute('DELETE FROM npc_dashboard_npcs WHERE id = ?', {npcId})
        end
    end)
end)