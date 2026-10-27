--[[
    The printed slip. After a reading (or TEST FAILED) the device prints the test's record: it comes out of the bottom
    over PRINT_MS, then the officer's game tears it off (the tear clip: it goes from the device into their left hand
    and the pocket) and it becomes an item, Config.slip, with the record in its metadata. Using that item reads it
    (client/slip.lua): the device goes away, they hold the slip up in their right hand and their page shows it.

    trBreathSlip on the officer, which every game draws from (client/device.lua):
        nil                     no slip
        { s = 'print', ms = n } coming out of the device over n ms from when it arrived
        { s = 'out' }           all of it out, waiting to be torn off
        { s = 'tear' }          being torn off (the officer plays the tear clip)
    trBreathRead on a player reading one (true): every game draws a slip in their hand while the clip plays.
    The device's item keeps its serial number, calibration date and how many tests it has printed (its metadata).
]]
local t = TR.locale.t
local anim = Breathalyzer.anim
local PRINT_MS = 2000
local WAIT_MS = 20000   -- the officer's game has this long after it's printed to tear it off; then it's theirs anyway
local CAL_DAYS = 182    -- a new device is next due for calibration this many days on

---@class BrSlip
---@field phase 'clock' | 'print' | 'out' | 'tear'
---@field record? table
local slips = {} ---@type table<integer, BrSlip> officer -> the slip their device is printing
local reading = {} ---@type table<integer, true> players reading a slip

local function setSlip(src, value)
    Player(src).state:set('trBreathSlip', value, true)
end

local function tell(src, key, kind, vars)
    TR.notify.send(src, { description = t(key, vars), type = kind or 'info' })
end

local function nameOf(src)
    if not src or src <= 0 or not GetPlayerName(src) then return '' end
    local name = TR.player.getName(src)
    return type(name) == 'string' and name ~= '' and name or GetPlayerName(src)
end

---What a slip item keeps: the record, and a line about it for the inventory's tooltip.
local function metadataOf(r)
    local m = {}
    for k, v in pairs(r) do m[k] = v end
    m.description = t('slip.description', {
        no = ('%06d'):format(r.no),
        result = r.v and ('%s %s'):format(r.v, r.u) or t('slip.failed'),
        name = r.subject,
    })
    return m
end

---The slip to the officer as an item, unless it went with them.
local function give(src)
    local slip = slips[src]
    if not slip then return end
    slips[src] = nil
    if not GetPlayerName(src) then return end
    setSlip(src, nil)
    if not slip.record then return end
    local metadata = metadataOf(slip.record)
    if not TR.inventory.canCarry(src, Config.slip, 1, metadata) or not TR.inventory.addItem(src, Config.slip, 1, metadata) then
        tell(src, 'slip.full', 'error')
    end
end

---The device's serial number, calibration date and how many tests it has printed, counting this one (kept in its
---item's metadata; a device that has none gets them). nil when the officer has no device.
---@param device? { slot: integer } the device's item as it was taken out
local function countTest(src, device)
    local slots = TR.inventory.getSlots(src, Config.item)
    local slot = slots[1]
    for _, s in ipairs(slots) do
        if device and s.slot == device.slot then slot = s end
    end
    if not slot then return nil end
    local meta = {}
    for k, v in pairs(type(slot.metadata) == 'table' and slot.metadata or {}) do meta[k] = v end
    if type(meta.serial) ~= 'string' then meta.serial = ('VX-560-%04d'):format(math.random(1, 9999)) end
    if type(meta.cal) ~= 'string' then meta.cal = os.date('%m/%Y', os.time() + CAL_DAYS * 86400) end
    meta.tests = (math.tointeger(meta.tests) or 0) + 1
    TR.inventory.setMetadata(src, slot.slot, meta)
    return meta
end

---Whether the officer's device has a slip in it (printing, out, being torn off).
function Breathalyzer.slipPending(src)
    return slips[src] ~= nil
end

---Prints the test's record (server/test.lua, once the device shows the reading or TEST FAILED).
---@param session table the test
---@param device? { slot: integer } the device's item as it was taken out
---@param reading { v?: string, u: string, o?: boolean } v: the reading as the screen shows it, none when it failed
function Breathalyzer.printSlip(session, device, reading)
    local src = session.officer
    if slips[src] then return end
    local slip = { phase = 'clock' }
    slips[src] = slip
    CreateThread(function()
        -- The time as the device's screen shows it: the officer's game clock
        local time = TR.callback.awaitChecked('tr_breathalyzer:clock', src, { timeout = 3000, schema = { 'string?' } })
        if slips[src] ~= slip then return end
        if type(time) ~= 'string' or not time:match('^%d%d:%d%d$') then time = os.date('%H:%M') end
        local meta = countTest(src, device)
        slip.record = {
            device = meta and meta.serial or 'VX-560-0000',
            no = meta and meta.tests or 1,
            date = os.date('%d/%m/%Y'),
            time = time,
            cal = meta and meta.cal or os.date('%m/%Y', os.time() + CAL_DAYS * 86400),
            v = reading.v,
            u = reading.u,
            o = reading.o or nil,
            limit = Breathalyzer.formatLimit(Config.unit, Config.limits),
            subject = session.dummy and t('dummy.name') or nameOf(session.suspect),
            officer = nameOf(src),
        }
        if not Breathalyzer.isOut(src) then return give(src) end
        slip.phase = 'print'
        setSlip(src, { s = 'print', ms = PRINT_MS })
        TriggerClientEvent('tr_breathalyzer:print', src, slip.record)
        Wait(PRINT_MS)
        if slips[src] ~= slip then return end
        slip.phase = 'out'
        setSlip(src, { s = 'out' })
        TriggerClientEvent('tr_breathalyzer:printed', src)
        Wait(WAIT_MS)
        if slips[src] == slip and slip.phase == 'out' then give(src) end
    end)
end

-- The officer's game tears it off: it's in their pocket when the clip has it there.
TR.net.on('tr_breathalyzer:tear', function(src)
    local slip = slips[src]
    if not slip or slip.phase ~= 'out' then return end
    slip.phase = 'tear'
    setSlip(src, { s = 'tear' })
    SetTimeout(math.floor(anim.tear.ms * anim.tear.pocket), function()
        if slips[src] == slip then give(src) end
    end)
end, { rateLimit = { max = 3, window = 3000 } })

---The device put away: a slip it printed goes with the officer (one still printing is theirs when it's done).
function Breathalyzer.slipAway(src)
    local slip = slips[src]
    if slip and slip.phase ~= 'clock' then give(src) end
end

---The officer left: their slip goes with them.
function Breathalyzer.slipForget(src)
    if not slips[src] then return end
    slips[src] = nil
    if GetPlayerName(src) then setSlip(src, nil) end
end

-- Reading one --------------------------------------------------------------------------------------------------
local FIELDS = { device = 20, date = 12, time = 5, cal = 7, v = 8, u = 8, limit = 8, subject = 60, officer = 60 }

---The record in a slip's metadata, or nil when there's none (an item made without a test).
local function recordOf(meta)
    if type(meta) ~= 'table' or not math.tointeger(meta.no) then return nil end
    local r = { no = math.tointeger(meta.no), o = meta.o == true or nil }
    for k, most in pairs(FIELDS) do
        local v = meta[k]
        if v ~= nil and (type(v) ~= 'string' or #v > most) then return nil end
        r[k] = v
    end
    if not (r.device and r.date and r.time and r.cal and r.u and r.limit) then return nil end
    r.subject, r.officer = r.subject or '', r.officer or ''
    return r
end

local function setReading(src, on)
    reading[src] = on or nil
    if GetPlayerName(src) then Player(src).state:set('trBreathRead', on or nil, true) end
end

local function stopReading(src)
    if not reading[src] then return end
    setReading(src, false)
    if GetPlayerName(src) then TriggerClientEvent('tr_breathalyzer:read', src, nil) end
end
Breathalyzer.stopReading = stopReading

-- Using a slip reads it, using it again puts it away. Not in a test; the device goes away first.
TR.inventory.onUse(Config.slip, function(src, used)
    if reading[src] then return stopReading(src) end
    if Breathalyzer.busy(src) then return tell(src, 'test.busy', 'error') end
    local record = recordOf(type(used) == 'table' and used.metadata or nil)
    if not record then return tell(src, 'slip.blank', 'error') end
    if Breathalyzer.isOut(src) then Breathalyzer.putAway(src) end
    setReading(src, true)
    TriggerClientEvent('tr_breathalyzer:read', src, record)
end)

-- Their game put it away (the key, falling, a weapon).
TR.net.on('tr_breathalyzer:readStop', function(src)
    if reading[src] then setReading(src, false) end
end, { rateLimit = { max = 4, window = 4000 } })

-- The slip went (dropped, given away): it's put away.
CreateThread(function()
    while true do
        Wait(3000)
        for src in pairs(reading) do
            if not GetPlayerName(src) then
                reading[src] = nil
            elseif not TR.inventory.hasItem(src, Config.slip, 1) then
                stopReading(src)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    reading[source] = nil
end)
TR.player.onUnloaded(function(src)
    if reading[src] then stopReading(src) end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for src in pairs(slips) do
        if GetPlayerName(src) then setSlip(src, nil) end
    end
    for src in pairs(reading) do
        if GetPlayerName(src) then Player(src).state:set('trBreathRead', nil, true) end
    end
end)

-- A slip left on a device or in a hand by a stop that never finished (a crash) goes when the resource comes back.
for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if Player(src).state.trBreathSlip then setSlip(src, nil) end
    if Player(src).state.trBreathRead then Player(src).state:set('trBreathRead', nil, true) end
end
