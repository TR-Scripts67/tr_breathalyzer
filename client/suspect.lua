--[[
    The suspect's side: asked first (Config.consent; the hint bar, a key to accept and one to refuse), then held
    still while the officer holds the mouthpiece to their lips: on foot frozen where they stand, and their head
    doesn't follow their camera (it would take the lips off the mouthpiece). On foot they stand still leaning to it
    (the blow clip, the whole body: no idle sways the lips off it, and every game has them the same); in a car they
    turn to the window (blow_l for a window on their left, blow_r on their right) and it rolls down; in a high cab
    the door by them opens and they lean out of it (blow_l_door / blow_r_door, client/body.lua). They hold the blow
    key until the bar is full; the server times the breath, then lets them go.
]]
local t = TR.locale.t
local anim = Breathalyzer.anim
local DOOR_MS = 4000    -- longest they wait for the door to open before leaning out
local LET_GO_MS = 1000  -- longest they're held after the test for the officer to be let go of on this game

---@class BrSubject
---@field officer integer server id
---@field clip? string nil until a door they lean out of is open
---@field flag integer
---@field ready boolean the officer holds it to their lips
---@field blowing boolean
---@field breaths integer
---@field frozen boolean they stand frozen (on foot)
Breathalyzer.subject = nil ---@type BrSubject?

-- What stays still while they blow: walking, jumping, fighting, driving, the horn, getting out, and E for other
-- scripts (it is the blow key).
local BLOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 38, 44, 59, 60, 63, 64, 71, 72, 75, 86, 140, 141, 142, 257, 263 }

local function nameOf(sid)
    local id = GetPlayerFromServerId(sid)
    return id ~= -1 and GetPlayerName(id) or tostring(sid)
end

-- Asking: in the hint bar, the accept and refuse keys on it; no answer in time is a no ----------------------------
local answer ---@type fun(yes: boolean)? the question on the hint bar now
Breathalyzer.asked = false

TR.callback.register('tr_breathalyzer:ask', function(officer)
    if type(officer) ~= 'number' or answer then return false end
    local p = promise.new()
    answer = function(yes)
        answer = nil
        Breathalyzer.asked = false
        TR.ui.hud.hide()
        p:resolve(yes)
    end
    Breathalyzer.asked = true
    TR.ui.hud.set({ hint = { text = t('hint.subject'), sub = t('ask.title', { name = nameOf(officer) }), keys = {
        { key = TR.ui.keyOf('+tr_breath_accept', Config.keys.accept), label = t('ask.accept') },
        { key = TR.ui.keyOf('+tr_breath_refuse', Config.keys.refuse), label = t('ask.refuse') },
    } } })
    local mine = answer
    SetTimeout(Config.consentSeconds * 1000, function()
        if answer == mine then answer(false) end
    end)
    return Citizen.Await(p)
end)

RegisterCommand('+tr_breath_accept', function() if answer then answer(true) end end, false)
RegisterCommand('-tr_breath_accept', function() end, false)
RegisterKeyMapping('+tr_breath_accept', t('keymap.accept'), 'keyboard', Config.keys.accept)
RegisterCommand('+tr_breath_refuse', function() if answer then answer(false) end end, false)
RegisterCommand('-tr_breath_refuse', function() end, false)
RegisterKeyMapping('+tr_breath_refuse', t('keymap.refuse'), 'keyboard', Config.keys.refuse)

-- Blowing -------------------------------------------------------------------------------------------------------
local function play(ped, s)
    TaskPlayAnim(ped, anim.dict, s.clip, 3.0, 3.0, -1, s.flag, 0.0, false, false, false)
end

---The door opened (the car's owner's game does it), then out of it; nil the clip when it never opens.
local function leanOut(s, ped, kind, door)
    Breathalyzer.openDoor(ped, door)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local started = GetGameTimer()
    while Breathalyzer.subject == s and vehicle ~= 0 and not Breathalyzer.doorOpen(vehicle, door) do
        if GetGameTimer() - started > DOOR_MS then
            TR.log.warn('the door by the suspect did not open (door %d of car %d)', door, vehicle)
            return
        end
        Wait(50)
    end
    if Breathalyzer.subject ~= s then return end
    s.clip = anim.blow[kind]
    if TR.stream.anim(anim.dict) then play(ped, s) end
end

local function hint(s)
    local st = Player(s.officer).state.trBreath or {}
    local sub
    if not s.ready then sub = t('hint.subject_wait')
    elseif st.s == 'analyze' or st.s == 'result' then sub = t('hint.subject_analyze')
    elseif st.s == 'again' then sub = t('hint.subject_again')
    elseif s.blowing then sub = t('hint.subject_blowing')
    else sub = t('hint.subject_ready') end
    local keys = { { key = TR.ui.keyOf('+tr_breath_cancel', Config.keys.cancel), label = t('key.stop') } }
    if s.ready and st.s ~= 'analyze' and st.s ~= 'result' then
        table.insert(keys, 1, { key = TR.ui.keyOf('+tr_breath_blow', Config.keys.blow), label = t('key.blow') })
    end
    local state = { hint = { text = t('hint.subject'), sub = sub, keys = keys } }
    if s.blowing then
        state.meter = { label = t('meter.breath'), duration = math.floor(Config.blowSeconds * 1000), run = s.breaths }
    end
    TR.ui.hud.set(state)
    -- The breath went in (or the officer's device moved on): the key may still be down, but it's over.
    if s.blowing and (st.s == 'analyze' or st.s == 'result' or st.s == 'failed') then s.blowing = false end
end

local function still(s)
    local frame = 0
    while Breathalyzer.subject == s do
        for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
        SetPedCanHeadIk(PlayerPedId(), false)
        frame = frame + 1
        if frame % 15 == 0 then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedRagdoll(ped) then
                TriggerServerEvent('tr_breathalyzer:cancel')
            elseif s.clip and not IsEntityPlayingAnim(ped, anim.dict, s.clip, 3) then
                play(ped, s)
            end
            hint(s)
        end
        Wait(0)
    end
end

RegisterNetEvent('tr_breathalyzer:subject', function(officer)
    if type(officer) ~= 'number' then return end
    local ped = PlayerPedId()
    local kind, window, door = Breathalyzer.subjectKind(ped)
    if window then RollDownWindow(GetVehiclePedIsIn(ped, false), window) end
    local s = { officer = officer, flag = anim.blowFlag[kind], ready = false, blowing = false, breaths = 0, frozen = kind == 'stand' }
    Breathalyzer.subject = s
    if s.frozen then FreezeEntityPosition(ped, true) end
    TaskClearLookAt(ped)
    if door then
        CreateThread(function() leanOut(s, ped, kind, door) end)
    else
        s.clip = anim.blow[kind]
        if TR.stream.anim(anim.dict) then play(ped, s) end
    end
    hint(s)
    CreateThread(function() still(s) end)
end)

---Whether this game still has the officer attached to them (client/officer.lua holds them there with the mouthpiece in).
local function officerOn(s, ped)
    local id = GetPlayerFromServerId(s.officer)
    local officer = id ~= -1 and GetPlayerPed(id) or 0
    return officer ~= 0 and IsEntityAttachedToEntity(officer, ped)
end

---Free again: the clip off, unfrozen, the head following the camera again. With `wait`: while this game still has
---the officer attached to them, held still (the same controls off) until it hasn't, `wait` ms at most: moving before
---would take the officer along here.
local function letGo(s, wait)
    local ped = PlayerPedId()
    if s.clip then StopAnimTask(ped, anim.dict, s.clip, 2.0) end
    local function free()
        if Breathalyzer.subject and Breathalyzer.subject ~= s then return end   -- in another test meanwhile: that holds them
        if s.frozen then FreezeEntityPosition(ped, false) end
        SetPedCanHeadIk(ped, true)
    end
    if not wait or not officerOn(s, ped) then return free() end
    CreateThread(function()
        local started = GetGameTimer()
        while officerOn(s, ped) and GetGameTimer() - started < wait do
            for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
            Wait(0)
        end
        free()
    end)
end

RegisterNetEvent('tr_breathalyzer:ready', function(officer)
    local s = Breathalyzer.subject
    if s and s.officer == officer then s.ready = true end
end)

RegisterNetEvent('tr_breathalyzer:done', function(other)
    local s = Breathalyzer.subject
    if not s or s.officer ~= other then return end
    Breathalyzer.subject = nil
    TR.ui.hud.hide()
    letGo(s, LET_GO_MS)
end)

RegisterCommand('+tr_breath_blow', function()
    local s = Breathalyzer.subject
    if not s or not s.ready or s.blowing then return end
    local st = Player(s.officer).state.trBreath
    if not st or (st.s ~= 'blow' and st.s ~= 'again') or st.b then return end
    s.blowing, s.breaths = true, s.breaths + 1
    TriggerServerEvent('tr_breathalyzer:blow', true)
end, false)
RegisterCommand('-tr_breath_blow', function()
    local s = Breathalyzer.subject
    if not s or not s.blowing then return end
    s.blowing = false
    TriggerServerEvent('tr_breathalyzer:blow', false)
end, false)
RegisterKeyMapping('+tr_breath_blow', t('keymap.blow'), 'keyboard', Config.keys.blow)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    local s = Breathalyzer.subject
    if s then letGo(s) end
end)
