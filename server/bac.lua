-- Each character's blood alcohol (% BAC). Drinks go in to be taken up over Config.absorbMinutes, the body clears
-- Config.burnPerHour. Kept in the resource's KVP per character, so logging out doesn't sober anyone up: the
-- time keeps counting, so it comes down while they're away the same as in the city.
local t = TR.locale.t
local KEY = 'bac:%s'
local cache = {} ---@type table<string, { bac: number, pending: number, at: integer }>

local function load(id)
    local s = cache[id]
    if s then return s end
    local raw = GetResourceKvpString(KEY:format(id))
    local ok, data = pcall(json.decode, raw or '')
    if ok and type(data) == 'table' and type(data.bac) == 'number' and type(data.pending) == 'number' and type(data.at) == 'number' then
        s = data
    else
        s = { bac = 0.0, pending = 0.0, at = os.time() }
    end
    cache[id] = s
    return s
end

local function save(id, s)
    if s.bac <= 0 and s.pending <= 0 then
        DeleteResourceKvp(KEY:format(id))
    else
        SetResourceKvp(KEY:format(id), json.encode(s))
    end
end

-- Brings s up to now, a minute at a time: what is still to be taken up goes in (95% of it within
-- absorbMinutes), and burnPerHour comes off. Whole minutes only; the rest waits for the next look.
local function advance(s, now)
    local minutes = (now - s.at) // 60
    if minutes <= 0 then return end
    s.at = s.at + minutes * 60
    if minutes > 24 * 60 then
        s.bac, s.pending = 0.0, 0.0
        return
    end
    local keep = math.exp(-3 / Config.absorbMinutes)
    local burn = Config.burnPerHour / 60
    for _ = 1, minutes do
        local taken = s.pending * (1 - keep)
        s.pending = s.pending - taken
        if s.pending < 1e-5 then s.pending = 0.0 end
        s.bac = math.max(0.0, s.bac + taken - burn)
        if s.bac == 0 and s.pending == 0 then return end
    end
end

---@return table? state, string? identifier
local function stateOf(src)
    local id = TR.player.getIdentifier(src)
    if not id then return end
    local s = load(id)
    advance(s, os.time())
    return s, id
end

---The player's blood alcohol now, % BAC (0 when they have no character loaded).
---@param src integer
---@return number
function Breathalyzer.getBAC(src)
    local s = stateOf(src)
    return s and s.bac or 0.0
end

---Adds drinks (standard drinks: one beer, a glass of wine, a shot) to be taken up over the next minutes.
---@param src integer
---@param drinks number
---@return boolean
function Breathalyzer.addAlcohol(src, drinks)
    drinks = tonumber(drinks)
    if not drinks or drinks ~= drinks or drinks <= 0 or drinks > 20 then return false end
    local s, id = stateOf(src)
    if not s then return false end
    s.pending = s.pending + drinks * Config.perDrink
    save(id, s)
    TR.log.debug('%d drank %.2f (now %.3f, %.3f still to come)', src, drinks, s.bac, s.pending)
    return true
end

---Sets the blood alcohol (% BAC, 0 to 0.6), with nothing more to come.
---@param src integer
---@param value number
---@return boolean
function Breathalyzer.setBAC(src, value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value > 0.6 then return false end
    local s, id = stateOf(src)
    if not s then return false end
    s.bac, s.pending = value, 0.0
    save(id, s)
    return true
end

exports('getBAC', function(src) return Breathalyzer.getBAC(tonumber(src)) end)
exports('addAlcohol', function(src, drinks) return Breathalyzer.addAlcohol(tonumber(src), drinks) end)
exports('setBAC', function(src, value) return Breathalyzer.setBAC(tonumber(src), value) end)

-- What's cached goes when the character does; the KVP has it (the numbers follow from it at any time).
TR.player.onUnloaded(function(src)
    local id = TR.player.getIdentifier(src)
    if id then cache[id] = nil end
end)

-- Admin -------------------------------------------------------------------------------------------------
-- /bac [id] and /setbac <id> <value>, for the console and admins (TR.player.isAdmin: the tr.admin ace or the
-- framework's admin groups).
local function allowed(src) return src == 0 or TR.player.isAdmin(src) end

local function reply(src, text, kind)
    if src == 0 then return print(text) end
    TR.notify.send(src, { description = text, type = kind or 'info' })
end

RegisterCommand('bac', function(src, args)
    if not allowed(src) then return end
    local target = tonumber(args[1]) or src
    local s = target ~= 0 and GetPlayerName(target) and stateOf(target)
    if not s then return reply(src, t('admin.no_player'), 'error') end
    local value, label = Breathalyzer.format(s.bac, Config.unit)
    local coming = Breathalyzer.format(s.pending, Config.unit)
    reply(src, t('admin.bac', { name = GetPlayerName(target), id = target, value = value, unit = label, coming = coming }))
end, false)

RegisterCommand('setbac', function(src, args)
    if not allowed(src) then return end
    local target, value = tonumber(args[1]), tonumber(args[2])
    if not target or not GetPlayerName(target) then return reply(src, t('admin.no_player'), 'error') end
    if not Breathalyzer.setBAC(target, value) then return reply(src, t('admin.bad_value'), 'error') end
    reply(src, t('admin.set', { name = GetPlayerName(target), id = target, value = ('%.3f'):format(value) }), 'success')
end, false)
