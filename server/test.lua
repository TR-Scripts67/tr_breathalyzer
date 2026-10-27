--[[
    The test, as the server runs it. Every step is checked here; the players' games only ask.

    The officer's device is a state bag on their player, trBreath, which every game draws from (client/device.lua):
        nil                 put away
        { s = 'ready' }     out, nothing on the screen but READY
        { s = 'blow', mp = true }            the mouthpiece on, waiting for a breath
        { s = 'blow', mp = true, b = ms }    a breath going in: the bar fills over b ms from when it arrived
        { s = 'again', mp = true, n = 2 }    too short, n tries left
        { s = 'analyze', mp = true, b = ms } working it out
        { s = 'result', v = '0.084', u = '% BAC', o = true }   the reading (o: over the limit)
        { s = 'failed' }    out of tries
    A test: the officer uses the target on someone (start), who is asked (Config.consent), a mouthpiece is used,
    both games are told (go / subject); the officer's game walks them to the suspect and holds it out (placed);
    the suspect holds the blow key (blow true / false) until a breath is long enough. Then the suspect is free
    (done) and the officer takes the device back to read it (back, their camera on its screen): it analyzes, the
    reading shows, the officer is told (done) and the suspect gets it as a notification, and the device prints the
    slip (server/slip.lua). Either may stop it (cancel) until the breath is in; it stops if they part, die or leave.

    Admins (TR.player.isAdmin) can test alone on a dummy (/br_dummy, client/dummy.lua): a ped made by their own game
    that agrees, blows by itself and reads what they asked for. Its test has suspect 0 and the dummy's net id.

    A suspect sat in a high cab leans out of its open door (client/body.lua): their game (the officer's for a dummy)
    asks for it here (door), the game that owns the car opens it, and it is shut again when the suspect is let go.
]]
local t = TR.locale.t

local out = {}      ---@type table<integer, { slot: integer }> officers with the device out (the item they took out)
local sessions = {} ---@type table<integer, table> officer -> test
local suspects = {} ---@type table<integer, integer> suspect -> officer
local BLOW_SLACK = 250 -- ms a breath may be short of blowSeconds (the key's trip to the server and back)

local function show(src, screen)
    Player(src).state:set('trBreath', screen, true)
end

local function allowed(src)
    return not Config.jobs or TR.player.hasJob(src, Config.jobs, Config.onDuty)
end

local function between(pa, pb)
    if pa == 0 or pb == 0 or not DoesEntityExist(pa) or not DoesEntityExist(pb) then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function distance(a, b)
    return between(GetPlayerPed(a), GetPlayerPed(b))
end

---The suspect's ped: a player's, or the dummy's.
local function suspectPed(session)
    if session.dummy then return NetworkGetEntityFromNetworkId(session.dummy) end
    return GetPlayerPed(session.suspect)
end

local function apart(session)
    return between(GetPlayerPed(session.officer), suspectPed(session))
end

local function present(src)
    return src > 0 and GetPlayerName(src) ~= nil
end

local function tell(src, key, kind, vars)
    TR.notify.send(src, { description = t(key, vars), type = kind or 'info' })
end

---Tells the game that owns a car to open or shut one of its doors (client/body.lua), `asked`'s if none does.
local function doorTo(netId, door, open, asked)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local owner = NetworkGetEntityOwner(vehicle)
    if not owner or owner <= 0 then owner = asked end
    if owner and owner > 0 and GetPlayerName(owner) then TriggerClientEvent('tr_breathalyzer:door', owner, netId, door, open) end
end

---The suspect out of the test (no longer anyone's suspect), their game told, unless that already happened. A door
---opened for them shuts.
local function freeSuspect(session)
    if session.released then return false end
    session.released = true
    if suspects[session.suspect] == session.officer then suspects[session.suspect] = nil end
    if present(session.suspect) then
        TriggerClientEvent('tr_breathalyzer:done', session.suspect, session.officer, session.phase)
    end
    if session.door then doorTo(session.door.car, session.door.door, false, session.door.asked) end
    return true
end

---Ends a test: both games told, the device back to READY unless it shows the reading or TEST FAILED.
---@param why? string locale key both are told (the suspect only while still in it)
local function finish(session, why)
    if sessions[session.officer] ~= session then return end
    sessions[session.officer] = nil
    session.over = true
    if out[session.officer] and session.phase ~= 'result' and session.phase ~= 'failed' then
        show(session.officer, { s = 'ready' })
    end
    TriggerClientEvent('tr_breathalyzer:done', session.officer, session.suspect, session.phase)
    local told = freeSuspect(session)
    if why then
        tell(session.officer, why, 'error')
        if told and present(session.suspect) then tell(session.suspect, why, 'error') end
    end
end

local function putAway(src)
    local session = sessions[src]
    if session then finish(session, 'test.stopped') end
    out[src] = nil
    show(src, nil)
    Breathalyzer.slipAway(src)
end

TR.inventory.onUse(Config.item, function(src, used)
    if out[src] then return putAway(src) end
    if suspects[src] then return end
    if not allowed(src) then return tell(src, 'not_allowed', 'error') end
    Breathalyzer.stopReading(src)
    out[src] = { slot = type(used) == 'table' and used.slot or nil }
    show(src, { s = 'ready' })
end)

---Whether the officer has the device out, and puts it away (server/slip.lua).
function Breathalyzer.isOut(src) return out[src] ~= nil end
Breathalyzer.putAway = putAway

---Whether a player is in a test, either side.
function Breathalyzer.busy(src) return sessions[src] ~= nil or suspects[src] ~= nil end

TR.net.on('tr_breathalyzer:away', function(src)
    if out[src] then putAway(src) end
end, { rateLimit = { max = 4, window = 4000 } })

-- Starting --------------------------------------------------------------------------------------------------
local function ask(session)
    local officer, suspect = session.officer, session.suspect
    if Config.consent and not session.dummy then
        local yes = TR.callback.awaitChecked('tr_breathalyzer:ask', suspect,
            { timeout = (Config.consentSeconds + 2) * 1000, schema = { 'boolean?' } }, officer)
        if session.over then return end
        if yes ~= true then
            finish(session)
            return tell(officer, 'test.refused', 'error', { name = GetPlayerName(suspect) or '' })
        end
    end
    if apart(session) > Config.distance + 2.0 then return finish(session, 'test.too_far') end
    if Config.mouthpiece and not TR.inventory.removeItem(officer, Config.mouthpiece, 1) then
        return finish(session, 'test.no_mouthpiece')
    end
    session.phase = 'place'
    show(officer, { s = 'blow', mp = true })
    if not session.dummy then TriggerClientEvent('tr_breathalyzer:subject', suspect, officer) end
    TriggerClientEvent('tr_breathalyzer:go', officer, suspect, session.dummy)
end

---Why the officer can't start a test now, if they can't.
local function cannotStart(src)
    if not out[src] then return 'test.no_device' end
    if sessions[src] or suspects[src] or Breathalyzer.slipPending(src) then return 'test.busy' end
    if not allowed(src) then return 'not_allowed' end
    if not TR.inventory.hasItem(src, Config.item, 1) then return 'test.no_device' end
    if Config.mouthpiece and not TR.inventory.hasItem(src, Config.mouthpiece, 1) then return 'test.no_mouthpiece' end
end

local function begin(session)
    sessions[session.officer] = session
    if session.suspect > 0 then suspects[session.suspect] = session.officer end
    CreateThread(function() ask(session) end)
end

TR.callback.register('tr_breathalyzer:start', function(src, target)
    local why = cannotStart(src)
    if why then return false, why end
    if target == src or not GetPlayerName(target) then return false, 'test.no_player' end
    if sessions[target] or suspects[target] then return false, 'test.they_busy' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) or distance(src, target) > Config.distance + 1.5 then
        return false, 'test.too_far'
    end
    begin({ officer = src, suspect = target, phase = 'ask', tries = 0, blow = 0 })
    return true, Config.consent
end, {
    schema = { { type = 'integer', min = 1, max = 65535 } },
    rateLimit = { max = 3, window = 5000 },
})

-- The dummy ---------------------------------------------------------------------------------------------------
local dummies = {} ---@type table<integer, { owner: integer, bac: number }> net id -> who made it, what it reads

local function admin(src) return TR.player.isAdmin(src) end

-- /br_dummy [bac] [car]: makes one, or sends the one there is away.
RegisterCommand('br_dummy', function(src, args)
    if src == 0 or not admin(src) then return end
    local bac, car = 0.09, false
    for _, a in ipairs(args) do
        local n = tonumber(a)
        if n then bac = math.max(0.0, math.min(0.6, n)) elseif a == 'car' then car = true end
    end
    TriggerClientEvent('tr_breathalyzer:makeDummy', src, bac, car)
end, false)

-- Its maker's game made the ped (client/dummy.lua) and tells the server which it is.
TR.net.on('tr_breathalyzer:dummy', function(src, netId, bac)
    if not admin(src) then return end
    for id, d in pairs(dummies) do
        if d.owner == src then dummies[id] = nil end
    end
    if not netId then return end
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or GetEntityType(ped) ~= 1 or IsPedAPlayer(ped) then return end
    dummies[netId] = { owner = src, bac = bac }
    Entity(ped).state:set('trBreathDummy', true, true)
end, {
    schema = { { type = 'integer', min = 1, max = 65535, optional = true }, { type = 'number', min = 0, max = 0.6, optional = true } },
    rateLimit = { max = 4, window = 4000 },
})

TR.callback.register('tr_breathalyzer:startDummy', function(src, netId)
    local d = dummies[netId]
    if not d or d.owner ~= src then return false, 'test.no_player' end
    local why = cannotStart(src)
    if why then return false, why end
    for _, session in pairs(sessions) do
        if session.dummy == netId then return false, 'test.they_busy' end
    end
    local session = { officer = src, suspect = 0, dummy = netId, bac = d.bac or 0.0, phase = 'ask', tries = 0, blow = 0 }
    if apart(session) > Config.distance + 1.5 then return false, 'test.too_far' end
    begin(session)
    return true, false
end, {
    schema = { { type = 'integer', min = 1, max = 65535 } },
    rateLimit = { max = 3, window = 5000 },
})

-- The door of a high cab: asked for by the suspect's game (the officer's for a dummy) for the door by the suspect.
TR.net.on('tr_breathalyzer:door', function(src, netId, door)
    local session = sessions[src] or (suspects[src] and sessions[suspects[src]])
    if not session or session.released or session.door then return end
    if (session.dummy and src ~= session.officer) or (not session.dummy and src ~= session.suspect) then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local ped = suspectPed(session)
    if vehicle == 0 or ped == 0 or not DoesEntityExist(vehicle) or GetVehiclePedIsIn(ped, false) ~= vehicle then return end
    session.door = { car = netId, door = door, asked = src }
    doorTo(netId, door, true, src)
end, {
    schema = { { type = 'integer', min = 1, max = 65535 }, { type = 'integer', min = 0, max = 3 } },
    rateLimit = { max = 3, window = 3000 },
})

-- The breath --------------------------------------------------------------------------------------------------
local function result(session)
    if session.over then return end
    local err = (math.random() * 2 - 1) * Config.deviceError
    local bac = session.dummy and session.bac or Breathalyzer.getBAC(session.suspect)
    local reading = bac < 0.002 and 0.0 or math.max(0.0, bac + err)
    local value, label, over = Breathalyzer.format(reading, Config.unit, Config.limits)
    session.phase = 'result'
    -- The officer reads it off the screen (their camera is on it); the suspect is told.
    show(session.officer, { s = 'result', v = value, u = label, o = over })
    Breathalyzer.printSlip(session, out[session.officer], { v = value, u = label, o = over })
    local name = session.dummy and t('dummy.name') or GetPlayerName(session.suspect) or ''
    if present(session.suspect) then
        tell(session.suspect, over and 'test.your_result_over' or 'test.your_result', 'info', { value = value, unit = label })
    end
    TR.log.info('%s (%d) tested %s (%d): %s %s', GetPlayerName(session.officer), session.officer, name, session.suspect, value, label)
    finish(session)
end

---The breath is in: the suspect is free (the device works it out on its own) and the officer takes it back to
---read it.
local function analyze(session, blow)
    if session.over or session.blow ~= blow or session.phase ~= 'blowing' then return end
    session.phase = 'analyze'
    local ms = math.floor(Config.analyzeSeconds * 1000)
    show(session.officer, { s = 'analyze', mp = true, b = ms })
    freeSuspect(session)
    TriggerClientEvent('tr_breathalyzer:back', session.officer, session.suspect)
    SetTimeout(ms, function() result(session) end)
end

local function startBreath(session)
    if session.over or session.phase ~= 'ready' then return end
    session.phase, session.blow, session.since = 'blowing', session.blow + 1, GetGameTimer()
    local ms = math.floor(Config.blowSeconds * 1000)
    show(session.officer, { s = 'blow', mp = true, b = ms })
    local blow = session.blow
    SetTimeout(ms - BLOW_SLACK, function() analyze(session, blow) end)
end

TR.net.on('tr_breathalyzer:placed', function(src)
    local session = sessions[src]
    if not session or session.phase ~= 'place' then return end
    if apart(session) > 3.0 then return finish(session, 'test.too_far') end
    session.phase = 'ready'
    if session.dummy then
        SetTimeout(1500, function() startBreath(session) end)  -- a dummy blows by itself
    else
        TriggerClientEvent('tr_breathalyzer:ready', session.suspect, src)
    end
end, { rateLimit = { max = 3, window = 3000 } })

TR.net.on('tr_breathalyzer:blow', function(src, blowing)
    local officer = suspects[src]
    local session = officer and sessions[officer]
    if not session then return end
    if blowing then return startBreath(session) end

    if session.phase ~= 'blowing' then return end
    if GetGameTimer() - session.since >= Config.blowSeconds * 1000 - BLOW_SLACK then return end
    session.tries = session.tries + 1
    session.blow = session.blow + 1    -- the pending analyze is for a breath that stopped
    if session.tries >= Config.tries then
        session.phase = 'failed'
        show(officer, { s = 'failed' })     -- the officer reads TEST FAILED off the screen
        local _, label = Breathalyzer.format(0.0, Config.unit, Config.limits)
        Breathalyzer.printSlip(session, out[officer], { u = label })
        return finish(session)
    end
    session.phase = 'ready'
    show(officer, { s = 'again', mp = true, n = Config.tries - session.tries })
    local blow = session.blow
    SetTimeout(1600, function()
        if not session.over and session.phase == 'ready' and session.blow == blow then
            show(officer, { s = 'blow', mp = true })
        end
    end)
end, {
    schema = { 'boolean' },
    rateLimit = { max = 12, window = 4000 },
})

-- Stopping -----------------------------------------------------------------------------------------------
TR.net.on('tr_breathalyzer:cancel', function(src)
    local session = sessions[src] or (suspects[src] and sessions[suspects[src]])
    if not session then return end
    finish(session, src == session.officer and 'test.stopped' or 'test.they_stopped')
end, { rateLimit = { max = 3, window = 3000 } })

-- Every second: a test stops when the two part or either leaves (their games stop it when they die or fall). Once
-- the breath is in, only the officer matters.
CreateThread(function()
    while true do
        Wait(1000)
        for _, session in pairs(sessions) do
            local o, s = session.officer, session.suspect
            local gone = not GetPlayerName(o) or (not session.released and ((not session.dummy and not GetPlayerName(s))
                or (session.dummy and suspectPed(session) == 0)))
            local far = not gone and not session.released
                and (apart(session) > 6.0 or (not session.dummy and GetPlayerRoutingBucket(o) ~= GetPlayerRoutingBucket(s)))
            if gone or far then finish(session, gone and 'test.left' or 'test.too_far') end
        end
    end
end)

local function forget(src)
    local session = sessions[src] or (suspects[src] and sessions[suspects[src]])
    if session then finish(session, 'test.left') end
    out[src] = nil
    Breathalyzer.slipForget(src)
    for id, d in pairs(dummies) do
        if d.owner == src then dummies[id] = nil end
    end
end

AddEventHandler('playerDropped', function() forget(source) end)
TR.player.onUnloaded(function(src)
    forget(src)
    if GetPlayerName(src) then show(src, nil) end
end)

-- The item went (dropped, given away, taken): the device goes too.
CreateThread(function()
    while true do
        Wait(3000)
        for src in pairs(out) do
            if GetPlayerName(src) and not TR.inventory.hasItem(src, Config.item, 1) then putAway(src) end
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for src in pairs(out) do
        if GetPlayerName(src) then show(src, nil) end
    end
end)

-- A device left out by a stop that never finished (a crash) goes when the resource comes back.
for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if Player(src).state.trBreath then show(src, nil) end
end
