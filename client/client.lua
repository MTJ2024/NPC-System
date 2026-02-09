-- NPC Dashboard Client (Alarm: Alle Wachen/Aggressiv/Guard/Neutral NPCs agieren, sobald EINER angegriffen wird ODER du ein Wanted Level hast!)
-- KEIN dofile, KEIN require – Config kommt global durch fxmanifest.lua

ESX = exports["es_extended"]:getSharedObject()

local istDashboardOffen = false
local istKoordinatenWahl = false
local gespawnteNpcs = {}
local npcStatus = {}
local AlleNPCsSpawnenLastList = nil
local lastNpcDelete = {}

-- Spezialwerte aus Config holen
local function getNpcConfig(npc, key)
    if npc and npc.id and Config.SpecialNpcs and Config.SpecialNpcs[npc.id] and Config.SpecialNpcs[npc.id][key] ~= nil then
        return Config.SpecialNpcs[npc.id][key]
    end
    return Config["Default" .. key:sub(1,1):upper() .. key:sub(2)]
end

local function npcIsAtOrigin(npc, ped)
    if not npc or not ped then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(npc.x, npc.y, npc.z)) < (getNpcConfig(npc, "radius") * 1.2)
end

RegisterNetEvent("npc_dashboard:syncAllNpcs")
AddEventHandler("npc_dashboard:syncAllNpcs", function(npcList)
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
            while not HasModelLoaded(modelHash) do Citizen.Wait(10) end
            if HasModelLoaded(modelHash) then
                local ped = CreatePed(4, modelHash, npc.x, npc.y, npc.z, npc.heading or 0.0, true, false)
                if DoesEntityExist(ped) then
                    SetEntityAsMissionEntity(ped, true, true)
                    SetPedKeepTask(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    PlaceObjectOnGroundProperly(ped)
                    SetEntityHealth(ped, getNpcConfig(npc, "health"))
                    if (npc.weapon and npc.weapon ~= "" and npc.weapon ~= "None") or Config.DefaultWeapon then
                        GiveWeaponToPed(ped, GetHashKey(npc.weapon or Config.DefaultWeapon), 999, false, true)
                    end
                    SetEntityInvincible(ped, getNpcConfig(npc, "invincible"))
                    npcStatus[idx] = {
                        busy = false,
                        pursuing = false,
                        origin = vector3(npc.x, npc.y, npc.z),
                        deathTime = nil,
                        dead = false,
                        respawnAt = 0
                    }
                    if not (npc.movement == 1 or npc.movement == true) then
                        ClearPedTasksImmediately(ped)
                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                    else
                        FreezeEntityPosition(ped, false)
                    end
                    gespawnteNpcs[idx] = ped
                end
            end
        end
    end
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
                DeleteEntity(ped)
                gespawnteNpcs[idx] = nil
            end
        end

        for idx, npc in ipairs(AlleNPCsSpawnenLastList or {}) do
            local status = npcStatus[idx]
            if status and status.dead and not gespawnteNpcs[idx] and GetGameTimer() - (status.deathTime or 0) > Config.DeadTimeout then
                status.dead = false
                status.deathTime = nil
                local modelHash = GetHashKey(npc.model)
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do Citizen.Wait(10) end
                local ped = CreatePed(4, modelHash, npc.x, npc.y, npc.z, npc.heading or 0.0, true, false)
                if DoesEntityExist(ped) then
                    SetEntityAsMissionEntity(ped, true, true)
                    SetPedKeepTask(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    PlaceObjectOnGroundProperly(ped)
                    SetEntityHealth(ped, getNpcConfig(npc, "health"))
                    if (npc.weapon and npc.weapon ~= "" and npc.weapon ~= "None") or Config.DefaultWeapon then
                        GiveWeaponToPed(ped, GetHashKey(npc.weapon or Config.DefaultWeapon), 999, false, true)
                    end
                    SetEntityInvincible(ped, getNpcConfig(npc, "invincible"))
                    if not (npc.movement == 1 or npc.movement == true) then
                        ClearPedTasksImmediately(ped)
                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                    else
                        FreezeEntityPosition(ped, false)
                    end
                    gespawnteNpcs[idx] = ped
                end
            end
        end
    end
end)

local function triggerAlarmAggro(spielerPed)
    for otherIdx, otherPed in pairs(gespawnteNpcs) do
        local otherNpc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[otherIdx]
        if otherNpc and DoesEntityExist(otherPed) and not IsPedDeadOrDying(otherPed, true) then
            if otherNpc.behavior == "Aggressiv" or otherNpc.behavior == "Wache" or otherNpc.behavior == "Guard" or otherNpc.behavior == "Neutral" then
                FreezeEntityPosition(otherPed, false)
                ClearPedTasksImmediately(otherPed)
                TaskCombatPed(otherPed, spielerPed, 0, 16)
                npcStatus[otherIdx].pursuing = true
                ClearEntityLastDamageEntity(otherPed)
            end
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(400)
        local spielerPed = PlayerPedId()
        local wantedLevel = GetPlayerWantedLevel(PlayerId())
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and (npc.movement == 1 or npc.movement == true) then
                local spawnCoords = vector3(npc.x, npc.y, npc.z)
                local pedCoords = GetEntityCoords(ped)
                local distanz = #(pedCoords - spawnCoords)
                local radius = getNpcConfig(npc, "radius")
                if HasEntityBeenDamagedByEntity(ped, spielerPed, true) or wantedLevel > 0 then
                    triggerAlarmAggro(spielerPed)
                end
                if not status.pursuing and distanz > radius * 1.05 then
                    status.dead = true
                    status.deathTime = GetGameTimer()
                    DeleteEntity(ped)
                    gespawnteNpcs[idx] = nil
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(400)
        local spielerPed = PlayerPedId()
        local wantedLevel = GetPlayerWantedLevel(PlayerId())
        for idx, ped in pairs(gespawnteNpcs) do
            local npc = AlleNPCsSpawnenLastList and AlleNPCsSpawnenLastList[idx]
            local status = npcStatus[idx]
            if npc and status and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and not (npc.movement == 1 or npc.movement == true) then
                local origin = status.origin or vector3(npc.x, npc.y, npc.z)
                local pedCoords = GetEntityCoords(ped)
                local dist_to_origin = #(pedCoords - origin)
                local radius = getNpcConfig(npc, "radius")
                local max_radius = 100.0
                if HasEntityBeenDamagedByEntity(ped, spielerPed, true) or wantedLevel > 0 then
                    triggerAlarmAggro(spielerPed)
                else
                    if not IsEntityPositionFrozen(ped) then
                        ClearPedTasksImmediately(ped)
                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                    end
                end
                if not status.pursuing and dist_to_origin > max_radius then
                    status.dead = true
                    status.deathTime = GetGameTimer()
                    DeleteEntity(ped)
                    gespawnteNpcs[idx] = nil
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

RegisterNUICallback("addNPC", function(data, cb)
    if type(data.behavior) == "number" then
        data.behavior = tostring(data.behavior)
    end
    TriggerServerEvent("npc_dashboard:addNPC", data)
    cb("ok")
end)

RegisterNUICallback("updateNPC", function(data, cb)
    if type(data.behavior) == "number" then
        data.behavior = tostring(data.behavior)
    end
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