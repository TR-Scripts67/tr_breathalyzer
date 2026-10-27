--[[
    The breathalyzer as every game draws it, from each officer's trBreath state bag (server/test.lua): the device in
    their right hand, the mouthpiece in it during a test, and its live screen. All props are local to each game. What
    it sounds like goes by the same looks (client/sound.lua).

    The screen: the page (web/, screens.ts) draws what the state says and hands the picture back (br:screen), which
    goes in one of four runtime textures. Each replaces the texture of one tr_br_lcd model, a window laid over the
    device's own. The nearest devices get one (the player's own first); the rest show the model's own, switched off.

    The slip, from each officer's trBreathSlip bag (server/slip.lua): sliding out of the device's slot as it prints,
    out, then torn off into their left hand (the tear clip has it on PH_L_Hand from tear.grab to tear.pocket); and from
    each player's trBreathRead bag, in their right hand while the slip_read clip plays (it has it on PH_R_Hand). The
    player's own is rig.slipLive with their record printed on it (the page draws it, Breathalyzer.slipPrint); everyone
    else's shows the plain print.
]]
local rig, anim = Breathalyzer.rig, Breathalyzer.anim
local SLOTS = #rig.screens
local SIZE = 512        -- the screen textures' sides (the models' own are 512 x 512, the UVs stretch it over the glass)
local NEAR = 15.0       -- m: devices nearer than this get a live screen
local FAR = 80.0        -- m: further than this nobody's device is drawn
local TICK = 200        -- ms between looks at who has one out

local txdName = ('tr_br_rt_%d'):format(GetGameTimer()) -- a txd name can't be used twice in a session
local txd = CreateRuntimeTxd(txdName)
local textures = {}
for i = 1, SLOTS do textures[i] = CreateRuntimeTexture(txd, 'lcd' .. i, SIZE, SIZE) end
local slipTexture = CreateRuntimeTexture(txd, 'slip', rig.slipPx[1], rig.slipPx[2])

---@class BrShown
---@field ped integer
---@field device integer
---@field mouthpiece? integer
---@field screen? integer the slot's overlay
---@field slot? integer
---@field state table what the bag said
---@field key string the state as JSON, to see changes
---@field since integer GetGameTimer() when this state came

local shown = {} ---@type table<integer, BrShown> server id -> what's drawn
local bySlot = {} ---@type table<integer, integer> slot -> server id

local function spawn(model, at)
    local hash = TR.stream.model(model)
    if not hash then return nil end
    local entity = CreateObjectNoOffset(hash, at.x, at.y, at.z, false, false, false)
    TR.stream.release('model', hash)
    SetEntityCollision(entity, false, false)
    return entity
end

local function remove(entity)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function onDevice(entity, device, offset)
    AttachEntityToEntity(entity, device, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
end

local function clock()
    return ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
end

local function sendScreen(slot, s)
    SendNUIMessage({
        action = 'br:screen',
        data = { slot = slot, screen = s and s.state or nil, clock = clock(), age = s and (GetGameTimer() - s.since) or nil },
    })
end

local function dropSlot(s)
    if not s.slot then return end
    remove(s.screen)
    bySlot[s.slot], s.screen = nil, nil
    sendScreen(s.slot, nil)
    s.slot = nil
end

local function giveSlot(s, slot)
    local name = rig.screens[slot]
    local screen = spawn(name, GetEntityCoords(s.device))
    if not screen then return end
    onDevice(screen, s.device, vec3(0.0, 0.0, 0.0))
    -- Each time: the game forgets the swap when the model is let go of.
    AddReplaceTexture(name, name, txdName, 'lcd' .. slot)
    s.slot, s.screen, bySlot[slot] = slot, screen, s.sid
    sendScreen(slot, s)
end

local function hide(sid)
    local s = shown[sid]
    if not s then return end
    dropSlot(s)
    remove(s.mouthpiece)
    remove(s.device)
    shown[sid] = nil
end

local function show(sid, ped, state, key)
    local s = shown[sid]
    if s and (s.ped ~= ped or not DoesEntityExist(s.device)) then
        hide(sid)
        s = nil
    end
    if not s then
        local device = spawn(rig.device, GetEntityCoords(ped))
        if not device then return end
        local g = anim.grip
        AttachEntityToEntity(device, ped, GetPedBoneIndex(ped, g.bone), g.at.x, g.at.y, g.at.z, g.rot.x, g.rot.y, g.rot.z,
            false, false, false, false, 2, true)
        s = { sid = sid, ped = ped, device = device, state = state, key = key, since = GetGameTimer() }
        shown[sid] = s
    elseif s.key ~= key then
        s.state, s.key, s.since = state, key, GetGameTimer()
        if s.slot then sendScreen(s.slot, s) end
    end

    if state.mp and not s.mouthpiece then
        s.mouthpiece = spawn(rig.mouthpiece, GetEntityCoords(s.device))
        if s.mouthpiece then onDevice(s.mouthpiece, s.device, rig.mouthpieceAt) end
    elseif not state.mp and s.mouthpiece then
        remove(s.mouthpiece)
        s.mouthpiece = nil
    end
end

-- The nearest devices keep or get a slot; the rest give theirs up.
local function share(me, mine)
    local want = {}
    for sid, s in pairs(shown) do
        local d = sid == me and -1.0 or #(GetEntityCoords(s.ped) - mine)
        if d <= NEAR then want[#want + 1] = { s = s, d = d } end
    end
    table.sort(want, function(a, b) return a.d < b.d end)
    local keep = {}
    for i = 1, math.min(SLOTS, #want) do keep[want[i].s] = true end
    for _, s in pairs(shown) do
        if s.slot and not keep[s] then dropSlot(s) end
    end
    for s in pairs(keep) do
        if not s.slot then
            for slot = 1, SLOTS do
                if not bySlot[slot] then
                    giveSlot(s, slot)
                    break
                end
            end
        end
    end
end

-- The slip ---------------------------------------------------------------------------------------------------------
---@class BrSlipShown
---@field sid integer
---@field ped integer
---@field mine boolean the player's own (the live print)
---@field bag? table their trBreathSlip bag
---@field key string|false the bag as JSON, to see changes
---@field since integer GetGameTimer() when this bag came
---@field reading boolean their trBreathRead bag
---@field entity? integer
---@field to? integer what it's attached to (the device or the ped)
---@field on? 'slot' | 'left' | 'right'
---@field d? number how far in the slot it was put

local slips = {} ---@type table<integer, BrSlipShown> server id -> the slip drawn (or looked out for)
-- Each player near at the last look and their slip's bags then, for its sounds.
local slipSeen = {} ---@type table<integer, { key: string|false, bag?: table, reading: boolean }>

local function slipRemove(p)
    remove(p.entity)
    p.entity, p.to, p.on, p.d = nil, nil, nil, nil
end

local function slipDrop(sid)
    local p = slips[sid]
    if not p then return end
    slipRemove(p)
    slips[sid] = nil
end

---Each look: what player `sid`'s bags say about their slip.
local function slipLook(sid, ped, mine)
    local bag = Player(sid).state.trBreathSlip
    if type(bag) ~= 'table' then bag = nil end
    local reading = Player(sid).state.trBreathRead == true
    local key = bag and json.encode(bag) or false
    local seen = slipSeen[sid]
    if seen and (seen.key ~= key or seen.reading ~= reading) then
        Breathalyzer.soundSlip(ped, seen.bag, bag, seen.reading, reading)
    end
    slipSeen[sid] = { key = key, bag = bag, reading = reading }
    if not bag and not reading then return slipDrop(sid) end
    local p = slips[sid]
    if p and p.ped ~= ped then
        slipDrop(sid)
        p = nil
    end
    if not p then
        p = { sid = sid, ped = ped, mine = mine, key = false, since = GetGameTimer(), reading = false }
        slips[sid] = p
    end
    if key ~= p.key then p.bag, p.key, p.since = bag, key, GetGameTimer() end
    p.reading = reading
end

---Where a slip goes now: 'slot' and how far it's still in it (m), 'left' or 'right' (the hand), or nil.
local function slipWhere(p, now)
    local ped = p.ped
    if p.reading and IsEntityPlayingAnim(ped, anim.dict, anim.read.clip, 3) then return 'right' end
    local bag = p.bag
    if not bag then return nil end
    if bag.s == 'print' then
        local ms = math.max(1, tonumber(bag.ms) or 1)
        return 'slot', rig.slipLength * (1.0 - math.min(1.0, (now - p.since) / ms))
    elseif bag.s == 'out' then
        return 'slot', 0.0
    elseif bag.s == 'tear' then
        local tear = anim.tear
        local k = IsEntityPlayingAnim(ped, anim.dict, tear.clip, 3) and GetEntityAnimCurrentTime(ped, anim.dict, tear.clip)
            or (now - p.since) / tear.ms
        if k < tear.grab then return 'slot', 0.0 end
        if k < tear.pocket then return 'left' end
    end
    return nil
end

local function slipPlace(p, now)
    local on, d = slipWhere(p, now)
    local to = p.ped
    if on == 'slot' then to = shown[p.sid] and shown[p.sid].device end    -- none drawn: no slip either
    if not on or not to or not DoesEntityExist(to) then return slipRemove(p) end
    if p.entity and not DoesEntityExist(p.entity) then p.entity, p.to = nil, nil end
    if not p.entity then
        local model = p.mine and rig.slipLive or rig.slip
        local entity = spawn(model, GetEntityCoords(p.ped))
        if not entity then return end
        if slips[p.sid] ~= p then return remove(entity) end     -- gone while it loaded
        -- Each time: the game forgets the swap when the model is let go of.
        if p.mine then AddReplaceTexture(model, model, txdName, 'slip') end
        p.entity = entity
    end
    if to == p.to and on == p.on and d == p.d then return end
    if on == 'left' and p.on == 'slot' then Breathalyzer.soundTorn(p.ped) end
    p.to, p.on, p.d = to, on, d
    if on == 'slot' then
        -- d back in: turned about the arc's centre (slipAt + (0, 0, slipCurl)) by d / slipCurl radians.
        local r, a = rig.slipCurl, d / rig.slipCurl
        local at = rig.slipAt + vec3(0.0, r * math.sin(a), r - r * math.cos(a))
        AttachEntityToEntity(p.entity, to, 0, at.x, at.y, at.z, math.deg(a), 0.0, 0.0, false, false, false, false, 2, true)
    else
        local bone = GetPedBoneIndex(p.ped, on == 'left' and anim.tear.bone or anim.read.bone)
        AttachEntityToEntity(p.entity, to, bone, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    end
end

-- Every frame while there is one: it slides out, and goes from the device to the hand on the clip's frame.
CreateThread(function()
    while true do
        if next(slips) then
            local now, list = GetGameTimer(), {}
            for _, p in pairs(slips) do list[#list + 1] = p end
            for _, p in ipairs(list) do
                if slips[p.sid] == p then slipPlace(p, now) end
            end
            Wait(0)
        else
            Wait(TICK)
        end
    end
end)

---The player's own slip shows this record (the page draws it and hands it back, br:slipTexture).
---@param record table
function Breathalyzer.slipPrint(record)
    SendNUIMessage({ action = 'br:slipTexture', data = { record = record } })
end

RegisterNUICallback('br:slipTexture', function(data, cb)
    cb({})
    local image = type(data) == 'table' and data.image
    if type(image) ~= 'string' or image:sub(1, 22) ~= 'data:image/png;base64,' then return end
    SetRuntimeTextureImage(slipTexture, image)
end)

-- Each player near at the last look and what their device showed (key false: none out), for its sounds
-- (client/sound.lua): a change from one look to the next, not what was there when they came near.
local looked = {} ---@type table<integer, { key: string|false, state?: table }>

local lastClock
CreateThread(function()
    while true do
        local me = GetPlayerServerId(PlayerId())
        local mine = GetEntityCoords(PlayerPedId())
        local near = {}
        for _, id in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(id)
            local ped = GetPlayerPed(id)
            if ped ~= 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped) - mine) <= FAR then
                local state = Player(sid).state.trBreath
                if type(state) ~= 'table' then state = nil end
                local key = state and json.encode(state) or false
                if state then show(sid, ped, state, key) end
                local was = looked[sid]
                if was and was.key ~= key then Breathalyzer.soundChange(sid, ped, was.state, state) end
                Breathalyzer.soundBreath(sid, ped, state)
                near[sid] = { key = key, state = state }
                slipLook(sid, ped, sid == me)
            end
        end
        for sid in pairs(shown) do
            if not (near[sid] and near[sid].state) then hide(sid) end
        end
        for sid in pairs(slips) do
            if not near[sid] then slipDrop(sid) end
        end
        for sid in pairs(slipSeen) do
            if not near[sid] then slipSeen[sid] = nil end
        end
        for sid in pairs(looked) do
            if not near[sid] then Breathalyzer.soundQuiet(sid) end
        end
        looked = near
        share(me, mine)

        local now = clock()
        if now ~= lastClock then
            lastClock = now
            for slot, sid in pairs(bySlot) do sendScreen(slot, shown[sid]) end
        end
        Wait(TICK)
    end
end)

-- The page's picture of a slot's screen.
RegisterNUICallback('br:screen', function(data, cb)
    cb({})
    if type(data) ~= 'table' then return end
    local slot, image = tonumber(data.slot), data.image
    slot = slot and math.tointeger(slot)
    if not slot or not textures[slot] or type(image) ~= 'string' or image:sub(1, 22) ~= 'data:image/png;base64,' then return end
    SetRuntimeTextureImage(textures[slot], image)
end)

---The device prop in a player's hand, if this game draws one.
---@param sid integer server id
---@return integer?
function Breathalyzer.deviceOf(sid)
    local s = shown[sid]
    return s and s.device or nil
end

-- Props on this resource's models go before the models do (they're dropped right after this event).
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for sid in pairs(shown) do
        local s = shown[sid]
        remove(s.screen)
        remove(s.mouthpiece)
        remove(s.device)
    end
    for _, p in pairs(slips) do remove(p.entity) end
    for i = 1, SLOTS do RemoveReplaceTexture(rig.screens[i], rig.screens[i]) end
    RemoveReplaceTexture(rig.slipLive, rig.slipLive)
end)
