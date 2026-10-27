--[[
    The slip, the player's own side. Printing: the device's clock for the record (the time its screen shows), and the
    record drawn on their slip prop (client/device.lua draws the prop). Reading one (using the item, server/slip.lua):
    the slip_read clip with the slip in the right hand (client/device.lua, from the trBreathRead bag), and the page
    shows it big beside them (SlipView). The cancel key puts it away, as do using it again, falling, a weapon; in a car
    there's no clip, only the page.
]]
local t = TR.locale.t
local anim = Breathalyzer.anim
local UNARMED = GetHashKey('WEAPON_UNARMED')

-- The time on the device's screen, for the record.
TR.callback.register('tr_breathalyzer:clock', function()
    return ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
end)

-- The officer's own slip coming out: their record on the prop.
RegisterNetEvent('tr_breathalyzer:print', function(record)
    if type(record) == 'table' then Breathalyzer.slipPrint(record) end
end)

---@class BrReading
---@field record table
local reading ---@type BrReading?

---Whether the player is reading a slip.
function Breathalyzer.reading() return reading ~= nil end

local function stop(tell)
    if not reading then return end
    reading = nil
    StopAnimTask(PlayerPedId(), anim.dict, anim.read.clip, 3.0)
    SendNUIMessage({ action = 'br:read', data = nil })
    TR.ui.hud.hide()
    if tell then TriggerServerEvent('tr_breathalyzer:readStop') end
end

---Puts the slip away (the cancel key).
function Breathalyzer.readStop() stop(true) end

local function unable(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedSwimming(ped) or IsPedCuffed(ped)
        or GetSelectedPedWeapon(ped) ~= UNARMED
end

local function hint(r)
    local record = r.record
    TR.ui.hud.set({ hint = {
        text = t('hint.slip'),
        sub = t('hint.slip_sub', { no = ('%06d'):format(record.no), name = record.subject ~= '' and record.subject or '-' }),
        keys = { { key = TR.ui.keyOf('+tr_breath_cancel', Config.keys.cancel), label = t('key.away') } },
    } })
end

-- Held up while it's read: the clip kept on (none in a car), put away when they can't hold it.
local function hold(r)
    TR.stream.anim(anim.dict)
    while reading == r do
        local ped = PlayerPedId()
        if unable(ped) then return stop(true) end
        if IsPedInAnyVehicle(ped, true) then
            if IsEntityPlayingAnim(ped, anim.dict, anim.read.clip, 3) then StopAnimTask(ped, anim.dict, anim.read.clip, 3.0) end
        elseif not IsEntityPlayingAnim(ped, anim.dict, anim.read.clip, 3) then
            TaskPlayAnim(ped, anim.dict, anim.read.clip, 3.0, 3.0, -1, 49, 0.0, false, false, false)
        end
        Wait(250)
    end
end

-- No punching or aiming with it in the hand.
local function noFists(r)
    while reading == r do
        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 25, true)   -- aim
        DisableControlAction(0, 140, true)  -- melee attacks
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisableControlAction(0, 257, true)
        DisableControlAction(0, 263, true)
        Wait(0)
    end
end

-- The server's word: read this record, or (none) put it away.
RegisterNetEvent('tr_breathalyzer:read', function(record)
    if type(record) ~= 'table' then return stop(false) end
    Breathalyzer.slipPrint(record)
    SendNUIMessage({ action = 'br:read', data = { record = record } })
    if reading then
        reading.record = record
        return hint(reading)
    end
    local r = { record = record }
    reading = r
    hint(r)
    CreateThread(function() hold(r) end)
    CreateThread(function() noFists(r) end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() or not reading then return end
    StopAnimTask(PlayerPedId(), anim.dict, anim.read.clip, 8.0)
end)
