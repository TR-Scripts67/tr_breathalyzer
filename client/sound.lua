--[[
    The device's sounds, heard by everyone near it: real recordings in sounds/ (CC0 from freesound.org, who made each
    is in sounds/CREDITS.txt; the br_ slots of dev/sounds/clips.mjs in the TR Scripts repo build them), played on this
    resource's page. client/device.lua hands over each look at an officer's trBreath state as it draws it, so a beep
    comes with the picture it goes with, and at their slip's bags (printing, torn off, read). A state that was there
    before this game saw the player makes no sound.
]]

-- The levels bring each recording to about as loud as the others: the beeps are pure tones, which carry, so lower
-- (dev/tools/trbreath/levels.cjs measures them after another take is picked).
TR.ui.sound.register({
    br_button = { files = { 'sounds/br_button.wav' }, level = 0.5, variance = 0.03 },      -- switched off
    br_beep = { files = { 'sounds/br_beep.wav' }, level = 0.13 },                          -- on, and ready for a breath
    br_mouthpiece = { files = { 'sounds/br_mouthpiece.wav' }, level = 0.6, variance = 0.04 }, -- a new one clicked on
    br_breath = { files = { 'sounds/br_breath.wav' }, level = 0.13, variance = 0.04, loop = true }, -- the suspect blowing,
    br_tone = { files = { 'sounds/br_tone.wav' }, level = 0.065, loop = true },            -- and the device's tone with it
    br_sample = { files = { 'sounds/br_sample.wav' }, level = 0.28, variance = 0.02 },     -- the breath taken
    br_again = { files = { 'sounds/br_again.wav' }, level = 0.13 },                        -- too short
    br_result = { files = { 'sounds/br_result.wav' }, level = 0.13 },                      -- the reading
    br_fail = { files = { 'sounds/br_fail.wav' }, level = 0.16 },                          -- TEST FAILED
    br_print = { files = { 'sounds/br_print.wav' }, level = 0.2 },                         -- the slip printing
    br_tear = { files = { 'sounds/br_tear.wav' }, level = 0.25, variance = 0.05 },         -- torn off
    br_paper = { files = { 'sounds/br_paper.wav' }, level = 0.8, variance = 0.05 },        -- taken out to read, put away
})

local REF = 1.5         -- m: nearer than this the device plays at its full level; past it, half as loud each time as far
local HEAR = 20.0       -- m: further than this it isn't heard
local AFTER = 350       -- ms from a mouthpiece clicking on to the beep for a breath

-- What a new state sounds like, by what it shows.
local ON_STATE = { again = 'br_again', analyze = 'br_sample', result = 'br_result', failed = 'br_fail' }

---How loud the device in `ped`'s hand is heard here, 0..1.
local function heard(ped)
    local d = #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId()))
    if d > HEAR then return 0.0 end
    return d <= REF and 1.0 or REF / d
end

local function play(name, ped, after)
    if after then
        return SetTimeout(after, function()
            if DoesEntityExist(ped) then play(name, ped) end
        end)
    end
    local volume = heard(ped)
    if volume > 0.0 then TR.ui.sound.play(name, volume * Config.volume) end
end

---What officer `sid`'s device does going from the state `was` to `state` at this look (either nil: none out).
---@param sid integer
---@param ped integer the officer
---@param was? table
---@param state? table
function Breathalyzer.soundChange(sid, ped, was, state)
    if not was then return play('br_beep', ped) end         -- switched on: its beep, nothing else
    if not state then return play('br_button', ped) end     -- switched off
    local clicked = state.mp and not was.mp
    if clicked then play('br_mouthpiece', ped) end
    -- waiting for a breath: the first, or another after one too short
    if state.s == 'blow' and not state.b and not (was.s == 'blow' and not was.b) then
        play('br_beep', ped, clicked and AFTER or nil)
    end
    if state.s ~= was.s and ON_STATE[state.s] then play(ON_STATE[state.s], ped) end
end

---What a player's slip does from one look to the next (client/device.lua): the device printing it, and taking one out
---to read or putting it away.
---@param ped integer
---@param was? table their trBreathSlip bag at the last look
---@param bag? table and now
---@param wasReading boolean
---@param reading boolean
function Breathalyzer.soundSlip(ped, was, bag, wasReading, reading)
    local s, before = bag and bag.s, was and was.s
    if s == 'print' and before ~= 'print' then play('br_print', ped) end
    if reading ~= wasReading then play('br_paper', ped) end
end

---The slip torn off: on the tear clip's frame the hand takes it (client/device.lua), not when its bag is seen.
---@param ped integer the officer
function Breathalyzer.soundTorn(ped)
    play('br_tear', ped)
end

local breathing = {} ---@type table<integer, true> the officers whose device has a breath going in, heard here

---Stops the breath going into officer `sid`'s device (it's in, too short, or out of sight).
function Breathalyzer.soundQuiet(sid)
    if not breathing[sid] then return end
    breathing[sid] = nil
    TR.ui.sound.stop('tr_breathalyzer:breath:' .. sid)
    TR.ui.sound.stop('tr_breathalyzer:tone:' .. sid)
end

---While a breath goes into officer `sid`'s device: the breath and the device's tone, as loud as it's heard here (in
---twentieths, so a step closer isn't sent to the page each look).
---@param state? table
function Breathalyzer.soundBreath(sid, ped, state)
    local volume = state and state.s == 'blow' and state.b and heard(ped) or 0.0
    volume = math.floor(volume * 20.0 + 0.5) / 20.0
    if volume <= 0.0 then return Breathalyzer.soundQuiet(sid) end
    breathing[sid] = true
    TR.ui.sound.loop('tr_breathalyzer:breath:' .. sid, 'br_breath', nil, volume * Config.volume)
    TR.ui.sound.loop('tr_breathalyzer:tone:' .. sid, 'br_tone', nil, volume * Config.volume)
end
