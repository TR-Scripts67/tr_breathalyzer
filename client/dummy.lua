--[[
    A dummy to test on alone, for admins (TR.player.isAdmin: the tr.admin ace or the framework's admins).
    /br_dummy [bac] [car] puts a man in front of you, or with `car` in the driver's seat of the nearest car. He
    agrees, blows by himself and reads `bac` (% BAC, 0.09 if not given). /br_dummy again sends him away. The server
    checks who may (server/test.lua).
]]
local anim = Breathalyzer.anim
local MODEL = 'a_m_y_business_01'
local DOOR_MS = 4000    -- longest the dummy waits for the door to open before leaning out
local mine ---@type integer? the dummy this game made

local function remove()
    if mine and DoesEntityExist(mine) then DeleteEntity(mine) end
    mine = nil
end

---Whether a ped is someone's dummy.
function Breathalyzer.isDummy(ped)
    return ped ~= 0 and not IsPedAPlayer(ped) and Entity(ped).state.trBreathDummy == true
end

local function nearestCar(at)
    local best, gap = nil, 6.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(vehicle) - at)
        if d < gap then best, gap = vehicle, d end
    end
    return best
end

RegisterNetEvent('tr_breathalyzer:makeDummy', function(bac, car)
    if mine then
        remove()
        return TriggerServerEvent('tr_breathalyzer:dummy')
    end
    local me = PlayerPedId()
    local at = GetOffsetFromEntityInWorldCoords(me, 0.0, 1.6, 0.0)
    local vehicle
    if car then
        vehicle = nearestCar(GetEntityCoords(me))
        if not vehicle or not IsVehicleSeatFree(vehicle, -1) then
            return TR.notify.send({ description = TR.locale.t('dummy.no_car'), type = 'error' })
        end
    end
    local hash = TR.stream.model(MODEL)
    if not hash then return end
    local ped = CreatePed(4, hash, at.x, at.y, at.z - 1.0, GetEntityHeading(me) + 180.0, true, false)
    TR.stream.release('model', hash)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    if vehicle then
        SetPedIntoVehicle(ped, vehicle, -1)
    else
        TaskStandStill(ped, -1)
    end
    mine = ped
    local started = GetGameTimer()
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() - started < 3000 do Wait(0) end
    TriggerServerEvent('tr_breathalyzer:dummy', NetworkGetNetworkIdFromEntity(ped), bac)
end)

local held = {} ---@type table<integer, true> dummies held still for a test

---The dummy leans to the mouthpiece (in a high cab out of its door, once open) and is held still, as a player's game
---does for them (client/suspect.lua).
function Breathalyzer.dummyBlow(netId)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not DoesEntityExist(ped) then return end
    local kind, window, door = Breathalyzer.subjectKind(ped)
    if window then RollDownWindow(GetVehiclePedIsIn(ped, false), window) end
    if kind == 'stand' then FreezeEntityPosition(ped, true) end
    TaskClearLookAt(ped)
    if held[ped] then return end
    held[ped] = true
    CreateThread(function()
        while held[ped] and DoesEntityExist(ped) do
            SetPedCanHeadIk(ped, false)     -- no looking round at who's near: the lips stay on the mouthpiece
            Wait(0)
        end
    end)
    if door then
        Breathalyzer.openDoor(ped, door)
        local vehicle, started = GetVehiclePedIsIn(ped, false), GetGameTimer()
        while held[ped] and vehicle ~= 0 and not Breathalyzer.doorOpen(vehicle, door) and GetGameTimer() - started < DOOR_MS do
            Wait(50)
        end
        if not held[ped] or not Breathalyzer.doorOpen(vehicle, door) then return end
    end
    TaskPlayAnim(ped, anim.dict, anim.blow[kind], 3.0, 3.0, -1, anim.blowFlag[kind], 0.0, false, false, false)
end

function Breathalyzer.dummyStop(netId)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not DoesEntityExist(ped) then return end
    held[ped] = nil
    for _, clip in pairs(anim.blow) do StopAnimTask(ped, anim.dict, clip, 2.0) end
    FreezeEntityPosition(ped, false)
    SetPedCanHeadIk(ped, true)
end

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then remove() end
end)
