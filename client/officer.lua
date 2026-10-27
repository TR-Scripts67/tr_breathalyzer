--[[
    The officer's side. With the device out they hold it in front of them reading the screen (the hold clip), and
    the target offers a breath test on a player near them, on foot or by a car window. In a test, once the suspect is in
    their clip (out of the door of a high cab, once it's open) and their mouth keeps still in it, the officer walks up
    to where the reach clip made for how high the lips are above the officer's floor puts the mouthpiece's end in the
    mouth (shared/anim.lua), as the game walks any ped, and the arm comes up to the mouth as they stop, the officer
    going with the mouth meanwhile: one move, the same on every game. Where the game has the end in each clip is seen at
    each test and kept (for freemode it's where Blender has it, to 0.1 mm in game; another model may be made otherwise),
    so the next walk goes straight to where it goes in. From the walk's end they're
    attached to the suspect: every game has the two as far apart as the officer's does. The clip is picked once and kept
    to the end (another would move the arm again), and the officer is only ever moved along the ground: raised or
    lowered, the game keeps their feet on it and the device doesn't go with them, so the height is the clip's. Once the
    breath is in they take it back and the camera goes to its screen (client/view.lua) for the reading. Then the device
    prints the slip and they tear it off.
]]
local t = TR.locale.t
local anim = Breathalyzer.anim
local UNARMED = GetHashKey('WEAPON_UNARMED')
local LOWEST, HIGHEST = anim.heights[1], anim.heights[#anim.heights]
local WALK_MS = 8000    -- longest the walk to the suspect may take
local WALK_SLIDE = 0.05 -- m: the walk's last bit, where the game slides them onto the spot
local GO_STRAIGHT = 0x7D8F4411  -- the walk's task, for GetScriptTaskStatus (7: done)
local STILL_MS = 1000   -- the walk is over once they've stood this long (against something)
local POSE_MS = 7000    -- longest the suspect may take to be in their clip (a door opens first)
-- Once their clip plays, their mouth is where it stays when it has kept within LIPS_STILL (m) of where it was on
-- average for LIPS_FOR ms (a player's on this game can take a second or more: 5.5 cm in one test); LIPS_WAIT_MS at most
local LIPS_FOR = 500
local LIPS_STILL = 0.004
local LIPS_WAIT_MS = 2500
local REACH = 2.0       -- the reach clip's blend speed: the arm comes up to the mouth in 1 / REACH s
local GLIDE = 0.6       -- m/s: fastest the officer is eased onto the spot as the arm comes up (the walk ended short)
local TURN = 180.0      -- degrees a second: and turned to face it
local MOVE_MS = 400     -- ms a move putting the mouthpiece in the mouth takes
local SLIDE = 1.2       -- m the officer may be put the rest of the way when something stood in the way
local TIP_OFF = 0.10    -- m: a mouthpiece's end seen further than this off the clip as made isn't kept (keepTip())
-- Putting the mouthpiece's end in the mouth the last bit, by where the game has it (settle()): how far off the spot
-- the clip was made for the officer may be moved, along the ground.
local SETTLE = 0.15
-- How far off the mouth the end may be along the ground (averaged over SAMPLES frames; up or down is the clip's):
-- placing stops under AIM; held, it's put back once more than HOLD off (a seated suspect's idle moves their lips up to
-- ~11 mm; standing they're still); a step that made it more than WORSE further off is undone.
local SAMPLES = 8
local AIM = 0.005
local HOLD = 0.015
local WORSE = 0.008
local SPREAD = 0.005    -- m: the device must keep this still in the officer's own space for where it is to be kept
local READ_MS = 4000    -- how long the camera stays on the reading

---@class BrTest
---@field suspect integer server id (0 for a dummy)
---@field dummy? integer the dummy's net id
---@field name string
---@field phase 'ask' | 'place' | 'held' | 'back' | 'over'
---@field clip? string the reach clip playing (picked once for the suspect's lips)
---@field cm? integer its lip height
---@field spot? vector3 where the officer was stood for that (their origin, on the ground), from the suspect (fromThem())
---@field heading? number degrees from the suspect's heading
---@field to? integer the suspect's ped, the officer attached to it from the walk's end
---@field at? vector3 where the officer was put last, from the suspect
---@field facing? number and the way they faced, degrees from the suspect's heading
---@field off? vector3 how far settle() has moved them off the spot (along the ground)
---@field steady? integer GetGameTimer() from which the device is where the clip and the spot put it
---@field last? table settle()'s last step: how far off it was before, and the place it was taken from
---@field stuck? boolean settle() stopped: its last step made it worse
---@field warned? boolean
---@field model? integer the officer's model (seenTips())
---@field seen? boolean where the device has the end in this clip was looked at this test
---@field moves? integer how many times settle() moved them
---@field miss? number how far off the mouth the end was at the last look, along the ground
---@field up? number and up (or down, under 0)
---@field first? number how far off at the first look, along the ground
---@field mouth? vector3 where the end should be (wantOf()) when the spot was worked out
---@field drift? number how far the spot went with the mouth as the arm came up (raise())
local test ---@type BrTest?
local starting = false

local function deviceOut() return LocalPlayer.state.trBreath ~= nil end

function Breathalyzer.officerTest() return test end

local function notify(key, kind, vars)
    TR.notify.send({ description = t(key, vars), type = kind or 'error' })
end

local REASONS = {
    not_allowed = true, ['test.no_device'] = true, ['test.busy'] = true, ['test.no_player'] = true,
    ['test.they_busy'] = true, ['test.no_mouthpiece'] = true, ['test.too_far'] = true,
}

---Whether the officer can't hold it any more: the device goes back.
local function unable(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedSwimming(ped)
        or IsPedInAnyVehicle(ped, true) or IsPedCuffed(ped) or GetSelectedPedWeapon(ped) ~= UNARMED
end

local function nameOf(sid)
    local id = GetPlayerFromServerId(sid)
    return id ~= -1 and GetPlayerName(id) or tostring(sid)
end

-- Starting ----------------------------------------------------------------------------------------------------
local function begin(callback, arg, suspect, dummy, name)
    if starting or test then return end
    starting = true
    local ok, why = TR.callback.await(callback, arg)
    starting = false
    if not ok then return notify(REASONS[why] and why or 'test.no_answer') end
    test = test or { suspect = suspect, dummy = dummy, name = name, phase = 'ask' }
    if why then notify('test.asking', 'info', { name = name }) end
end

local function startOn(ped)
    if ped == 0 or ped == PlayerPedId() then return end
    if Breathalyzer.isDummy(ped) then
        return begin('tr_breathalyzer:startDummy', NetworkGetNetworkIdFromEntity(ped), 0, NetworkGetNetworkIdFromEntity(ped), t('dummy.name'))
    end
    if not IsPedAPlayer(ped) then return end
    local id = NetworkGetPlayerIndexFromPed(ped)
    if id == -1 then return end
    local sid = GetPlayerServerId(id)
    begin('tr_breathalyzer:start', sid, sid, nil, GetPlayerName(id))
end

---Whether a point is on a vehicle's left (-X) side.
local function onLeft(vehicle, at)
    return GetOffsetFromEntityGivenWorldCoords(vehicle, at.x, at.y, at.z).x < 0.0
end

-- The window a player (or the dummy) sits behind, nearest the officer and in reach, on the officer's side of the car.
local DOORS = { [-1] = 'door_dside_f', [0] = 'door_pside_f', [1] = 'door_dside_r', [2] = 'door_pside_r' }
local function occupantNear(vehicle)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local left = onLeft(vehicle, at)
    local best, bestD
    for seat, bone in pairs(DOORS) do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and ped ~= me and (IsPedAPlayer(ped) or Breathalyzer.isDummy(ped)) then
            local i = GetEntityBoneIndexByName(vehicle, bone)
            if i ~= -1 then
                local door = GetWorldPositionOfEntityBone(vehicle, i)
                local d = #(at - door)
                if d <= Config.distance + 0.5 and onLeft(vehicle, door) == left and (not bestD or d < bestD) then
                    best, bestD = ped, d
                end
            end
        end
    end
    return best
end

local function canTest()
    return deviceOut() and not test and not starting and not Breathalyzer.subject and not Breathalyzer.viewing()
end

TR.target.addGlobalPlayer({
    {
        name = 'tr_breathalyzer:test',
        label = t('target.test'),
        icon = 'fa-solid fa-wind',
        distance = Config.distance,
        canInteract = function(entity) return canTest() and not IsPedInAnyVehicle(entity, false) end,
        onSelect = function(data) startOn(data.entity) end,
    },
})

TR.target.addGlobalPed({
    {
        name = 'tr_breathalyzer:test_dummy',
        label = t('target.test'),
        icon = 'fa-solid fa-wind',
        distance = Config.distance,
        canInteract = function(entity) return canTest() and Breathalyzer.isDummy(entity) and not IsPedInAnyVehicle(entity, false) end,
        onSelect = function(data) startOn(data.entity) end,
    },
})

TR.target.addGlobalVehicle({
    {
        name = 'tr_breathalyzer:test_car',
        label = t('target.test_car'),
        icon = 'fa-solid fa-wind',
        distance = Config.distance + 1.0,
        canInteract = function(entity) return canTest() and occupantNear(entity) ~= nil end,
        onSelect = function(data)
            local ped = data.entity and data.entity ~= 0 and occupantNear(data.entity)
            if ped then startOn(ped) end
        end,
    },
})

-- Holding it to their lips --------------------------------------------------------------------------------------
local lipsOf = Breathalyzer.lipsOf

-- Where the mouthpiece's end is in each reach clip as this game draws it, by the officer's model, in their own space:
-- the clips are made in Blender (anim.tip), the game has the end a little off that (the hand, the grip), the same each
-- time. Seen once the arm is up in a test and kept (KVP, "cm:x,y,z;..."), so the next test with that clip walks straight
-- to where it goes in, and the clip is picked by the height it really reaches.
local function tipsKey(model) return 'tips:' .. tostring(model) end

---The ends seen for `model`, by clip.
---@return table<integer, vector3>
local function seenTips(model)
    local tips = {}
    local s = GetResourceKvpString(tipsKey(model))
    if type(s) ~= 'string' then return tips end
    for cm, x, y, z in s:gmatch('(%d+):([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)') do
        cm = tonumber(cm)
        local tip = anim.tip[cm] and tonumber(x) and tonumber(y) and tonumber(z) and vec3(tonumber(x), tonumber(y), tonumber(z))
        if tip and #(tip - anim.tip[cm]) <= TIP_OFF then tips[cm] = tip end
    end
    return tips
end

---Keeps where `model` has the end in clip `cm`; not when it's further than TIP_OFF off Blender's (a look gone wrong).
local function keepTip(model, cm, tip)
    if #(tip - anim.tip[cm]) > TIP_OFF then return false end
    local tips = seenTips(model)
    tips[cm] = tip
    local parts = {}
    for c, e in pairs(tips) do parts[#parts + 1] = ('%d:%.4f,%.4f,%.4f'):format(c, e.x, e.y, e.z) end
    table.sort(parts)
    SetResourceKvp(tipsKey(model), table.concat(parts, ';'))
    return true
end

---Where clip `cm` has the end: as seen; else Blender's, as far off it as in the nearest clip seen (the arm much the
---same); else Blender's.
local function tipOf(tips, cm)
    if tips[cm] then return tips[cm] end
    local nearest, gap = nil, math.huge
    for c in pairs(tips) do
        if math.abs(c - cm) < gap then nearest, gap = c, math.abs(c - cm) end
    end
    return nearest and anim.tip[cm] + (tips[nearest] - anim.tip[nearest]) or anim.tip[cm]
end

---The reach clip for lips h metres above the officer's floor (the one whose end comes nearest that height), or nil
---when none reaches.
local function clipFor(h, tips)
    local cm = h * 100
    if cm < LOWEST - 1.5 or cm > HIGHEST + 1.5 then return nil end
    local best, gap = nil, math.huge
    for _, x in ipairs(anim.heights) do
        local reach = (tipOf(tips, x).z - anim.floor) * 100
        if math.abs(reach - cm) < gap then best, gap = x, math.abs(reach - cm) end
    end
    return best
end

---Where the officer stands (their origin, on `floor`) facing `ahead` (flat, unit) for clip `cm` to put the
---mouthpiece's end in the mouth, and their heading.
local function spotFor(lips, face, cm, ahead, floor, tips)
    local heading = math.atan(-ahead.x, ahead.y)
    local right = vec3(math.cos(heading), math.sin(heading), 0.0)
    local tip = tipOf(tips, cm)
    local want = lips - face * anim.insert
    local at = want - right * tip.x - ahead * tip.y
    return vec3(at.x, at.y, floor - anim.floor), math.deg(heading)
end

---Which way the officer faces: on foot back along the suspect's face; to someone in a car square to the side of it
---they sit on, facing in (standing back along the face would put the officer into the door: the suspect's clip turns
---them to the window, the officer stands clear of the car, props/breathalyzer/anim.py's car previews).
local function aheadFor(sped, lips, face)
    local vehicle = GetVehiclePedIsIn(sped, false)
    if vehicle ~= 0 then
        local r = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - GetEntityCoords(vehicle)
        local len = math.sqrt(r.x * r.x + r.y * r.y)
        if len < 0.2 then return nil, 'the car is on its side' end
        local s = onLeft(vehicle, lips) and 1.0 or -1.0
        return vec3(r.x / len * s, r.y / len * s, 0.0)
    end
    local len = math.sqrt(face.x * face.x + face.y * face.y)
    if len < 0.2 then return nil, 'their face looks straight up or down' end
    return vec3(-face.x / len, -face.y / len, 0.0)
end

---The ground under a spot, nil when the map there isn't loaded.
local function groundAt(x, y, z)
    local found, ground = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 0.0, false)
    if found then return ground end
end

---The clip and the spot; nil and why not when there's none. The clip goes by how high the lips are over the ground
---where the officer will stand (not where they stand now: the kerb is higher than the road by the car), `floor` the
---guess to start from. `tips`: the ends seen (seenTips()).
local function plan(sped, floor, tips)
    local lips, face = lipsOf(sped)
    local ahead, why = aheadFor(sped, lips, face)
    if not ahead then return nil, why end
    local cm, at, heading
    for _ = 1, 3 do
        cm = clipFor(lips.z - floor, tips)
        if not cm then
            return nil, ('their lips are %.2f m above the ground (the clips reach %.2f to %.2f)'):format(lips.z - floor, LOWEST / 100, HIGHEST / 100)
        end
        at, heading = spotFor(lips, face, cm, ahead, floor, tips)
        local ground = groundAt(at.x, at.y, lips.z + 0.5)
        if not ground or math.abs(ground - floor) < 0.01 then break end
        floor = ground
    end
    return cm, at, heading
end

---Whether the officer fits at `at` (an origin): nothing of the map or a vehicle in the way from the knees up where
---their body is (0.15 m round; GTA's ped capsule is 0.25 m, pedbounds.xml, but the officer is put the last bit and
---held there). `car`: a car not to count, the suspect's when they lean out of its door (the officer stands in the
---doorway, where a high cab's collision reaches out past its body: props/breathalyzer/anim.py's c_sandking_* show
---them clear of the body).
local function free(at, car)
    local floor = at.z + anim.floor
    local probe = StartShapeTestCapsule(at.x, at.y, floor + 0.6, at.x, at.y, floor + 1.65, 0.15, 3, car or PlayerPedId(), 7)   -- 3: the map, vehicles
    local status, hit, _, _, entity = 1, false, nil, nil, 0
    local started = GetGameTimer()
    while status == 1 and GetGameTimer() - started < 500 do
        status, hit, _, _, entity = GetShapeTestResult(probe)
        if status == 1 then Wait(0) end
    end
    return hit ~= 1 and hit ~= true, entity
end

---"Can't reach", and what was in the way in the console (F8) for whoever looks into it.
local function unreachable(session, why, ...)
    TR.log.warn("can't reach %s's mouth: " .. why, session.name, ...)
end

local function suspectPed(session)
    if session.dummy then
        local ped = NetworkGetEntityFromNetworkId(session.dummy)
        return ped ~= 0 and DoesEntityExist(ped) and ped or nil
    end
    local id = GetPlayerFromServerId(session.suspect)
    local ped = id ~= -1 and GetPlayerPed(id) or 0
    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function cancel(key)
    TriggerServerEvent('tr_breathalyzer:cancel')
    if key then notify(key) end
end

---`p` (in the world) as it is from the suspect: in their ped's own space, the one the officer is attached in.
local function fromThem(sped, p)
    return GetOffsetFromEntityGivenWorldCoords(sped, p.x, p.y, p.z)
end

---Where this game has the mouthpiece's end in the officer's hand, and where it should be (`insert` into the suspect's
---mouth), both from the suspect (fromThem()); nil without a device to measure. From them, not in the world: a
---player's ped on another game is put where the network has it, which it corrects now and then by some centimetres
---while they stand still (in game: the lips 6 cm further between two looks, the officer still). The officer, attached
---to them, goes with it, and so does what's measured from them.
---@return vector3? tip, vector3? want
local function tipAndWant(sped)
    local device = Breathalyzer.deviceOf(GetPlayerServerId(PlayerId()))
    if not device or not DoesEntityExist(device) then return nil end
    local e = anim.tipOnDevice
    local tip = GetOffsetFromEntityInWorldCoords(device, e.x, e.y, e.z)
    local lips, face = lipsOf(sped)
    return fromThem(sped, tip), fromThem(sped, lips - face * anim.insert)
end

---Where the mouthpiece's end should be (`insert` into the mouth), from the suspect.
local function wantOf(sped)
    local lips, face = lipsOf(sped)
    return fromThem(sped, lips - face * anim.insert)
end

---Points kept as { at = GetGameTimer(), p = vector3 }: their average and how far the furthest is from it.
local function spreadOf(points)
    local mean = vec3(0.0, 0.0, 0.0)
    for _, x in ipairs(points) do mean = mean + x.p end
    mean = mean / #points
    local most = 0.0
    for _, x in ipairs(points) do most = math.max(most, #(x.p - mean)) end
    return mean, most
end

---`v` along the ground (what moving the officer can change).
local function flat(v)
    return vec3(v.x, v.y, 0.0)
end

---`v` turned `heading` degrees about the up axis (the officer's own space to the suspect's).
local function turned(v, heading)
    local h = math.rad(heading)
    local c, s = math.cos(h), math.sin(h)
    return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
end

---Over SAMPLES frames, the officer still: from the mouthpiece's end to where it should be (averaged), where the device
---has the end in the officer's own space (averaged) and how far from that it strayed; nil without a device, or when the
---test or the suspect went meanwhile.
---@return vector3? gap, vector3? tip, number? spread
local function measure(session, sped)
    local gap, tips = vec3(0.0, 0.0, 0.0), {}
    for i = 1, SAMPLES do
        if test ~= session or not DoesEntityExist(sped) then return nil end
        local tip, want = tipAndWant(sped)
        if not tip then return nil end
        gap = gap + (want - tip)
        tips[i] = turned(tip - session.at, -session.facing)
        if i < SAMPLES then Wait(0) end
    end
    local mean = vec3(0.0, 0.0, 0.0)
    for _, e in ipairs(tips) do mean = mean + e end
    mean = mean / SAMPLES
    local spread = 0.0
    for _, e in ipairs(tips) do spread = math.max(spread, #(e - mean)) end
    return gap / SAMPLES, mean, spread
end

---Reach clip `cm` on, blending in at `speed`: the device is only where it stays once the clip is fully in.
local function reachClip(session, ped, cm, speed)
    session.cm, session.clip = cm, anim.reach:format(cm)
    TaskPlayAnim(ped, anim.dict, session.clip, speed, speed, -1, 1, 0.0, false, false, false)
    session.steady = GetGameTimer() + math.ceil(1000 / speed) + 100
end

---Whether the officer still holds it to the mouth in this test (not once the server took it back or ended it).
local function holding(session)
    return test == session and session.phase == 'held'
end

---The officer put at `at` (their origin, from the suspect: fromThem()) facing `facing` (degrees from the suspect's
---heading), attached to the suspect (`session.to`). Each game draws another player's ped where the network puts it,
---near but not quite where it is (the first test with a player: on the suspect's screen the officer stood about where
---their walk ended, the device short of the mouth); what's attached is drawn where it's attached on every game, so
---every game has the two as this one has them. Everything from the walk's end on is from the suspect, so nothing goes
---by where the world had them before the network moved them.
local function put(session, ped, at, facing)
    session.at, session.facing = at, facing
    AttachEntityToEntity(ped, session.to, -1, at.x, at.y, at.z, 0.0, 0.0, facing, false, false, false, false, 2, true)
end

---The officer off the suspect, where they stand.
local function letGo(session, ped)
    if session.to and IsEntityAttachedToEntity(ped, session.to) then DetachEntity(ped, false, true) end
end

---The officer moved to `at` over `ms`, a frame at a time, eased in and out, facing as they do.
local function glide(session, ped, at, ms)
    local from = session.at
    local started = GetGameTimer()
    while holding(session) do
        local k = math.min((GetGameTimer() - started) / ms, 1.0)
        k = k * k * (3.0 - 2.0 * k)
        put(session, ped, from + (at - from) * k, session.facing)
        if k >= 1.0 then return end
        Wait(0)
    end
end

---The officer eased to `off` off the spot.
local function standAt(session, ped, off)
    session.off = off
    glide(session, ped, session.spot + off, MOVE_MS)
    session.steady = math.max(session.steady or 0, GetGameTimer() + 100)    -- the ped, then what's attached to it
end

---Where the officer goes (off the spot, along the ground) for the mouthpiece's end to be `want` (flat) from where the
---clip has it at the spot; never further than SETTLE (said once in F8 when that's short of it, `miss` off).
---@return vector3 off
local function placeFor(session, want, miss)
    local side = #want
    local k = side > SETTLE and SETTLE / side or 1.0
    if k < 1.0 and not session.warned then
        session.warned = true
        TR.log.warn("the mouthpiece is %.2f m from %s's mouth: further than the officer may be moved (%.2f)", miss, session.name, SETTLE)
    end
    return want * k
end

---The arm up to the mouth as the walk ends: the reach clip (on already) blends in while the officer, attached to the
---suspect where the walk left them, is eased the rest of the way onto the spot and turned to face it. After the game's
---walk that's a centimetre or two and a few degrees, taken in the time the arm takes to come up: the two are one move.
---The spot goes with the mouth meanwhile (along the ground, by its last SAMPLES frames), so should it still move the
---officer arrives where it is now, not where it was (`session.mouth`, from the suspect, when the spot was worked out).
local function raise(session, ped, sped)
    put(session, ped, fromThem(sped, GetEntityCoords(ped)), GetEntityHeading(ped) - GetEntityHeading(sped))
    local from, h0 = session.at, session.facing
    local turn = (session.heading - h0 + 540.0) % 360.0 - 180.0
    local ms = math.max(1000 / REACH, #(session.spot - from) / GLIDE * 1000, math.abs(turn) / TURN * 1000)
    local recent, n, spot = {}, 0, session.spot
    local started = GetGameTimer()
    while holding(session) and DoesEntityExist(sped) do
        n = n + 1
        recent[(n - 1) % SAMPLES + 1] = wantOf(sped)
        local sum = vec3(0.0, 0.0, 0.0)
        for _, w in ipairs(recent) do sum = sum + w end
        spot = session.spot + flat(sum / #recent - session.mouth)
        local k = math.min((GetGameTimer() - started) / ms, 1.0)
        local e = k * k * (3.0 - 2.0 * k)
        put(session, ped, from + (spot - from) * e, h0 + turn * e)
        if k >= 1.0 then break end
        Wait(0)
    end
    session.drift = #(spot - session.spot)
    session.spot = spot
end

---A look at where the game has the device and the lips (the spot came from the clip as seen before, or as made in
---Blender), and a move putting the mouthpiece's end in the mouth along the ground as placeFor() has it when it's more
---than `aim` off (the clip stays). A move that made it worse is undone and no more are taken. The first look in a test
---keeps where the device has the end in the clip (keepTip()). Look only once `session.steady`. Returns whether it moved
---them (then look again once steady).
local function settle(session, ped, sped, aim)
    if session.stuck then return false end
    local gap, tip, spread = measure(session, sped)
    if not gap then return false end
    if not session.seen and spread <= SPREAD then
        session.seen = true
        if not keepTip(session.model, session.cm, tip) then
            TR.log.warn('the mouthpiece is %.3f m off where clip %d has it: not kept', #(tip - anim.tip[session.cm]), session.cm)
        end
    end
    local side = flat(gap)
    local miss, last = #side, session.last
    session.last, session.miss, session.up, session.first = nil, miss, -gap.z, session.first or miss
    if last and miss > last.miss + WORSE then
        TR.log.warn("putting the mouthpiece in %s's mouth: a move took it from %.3f to %.3f m off, undone",
            session.name, last.miss, miss)
        session.stuck, session.miss = true, last.miss
        session.moves = (session.moves or 0) + 1
        standAt(session, ped, last.off)
        return true
    end
    if miss < aim then return false end

    local want = placeFor(session, session.off + side, miss)
    if #(want - session.off) < 0.001 then return false end

    session.last = { miss = miss, off = session.off }
    session.moves = (session.moves or 0) + 1
    TR.log.debug("putting the mouthpiece in %s's mouth: %.3f m off (%.3f up, the clip's), moved %.3f m", session.name,
        miss, -gap.z, #(want - session.off))
    standAt(session, ped, want)
    return true
end

---Waits for the device to be steady; false when the test ended meanwhile.
local function steady(session)
    while test == session and GetGameTimer() < session.steady do Wait(0) end
    return test == session
end

---Which of anim.blow the suspect plays, as this game has them.
local function blowing(sped)
    for kind, clip in pairs(anim.blow) do
        if IsEntityPlayingAnim(sped, anim.dict, clip, 3) then return kind end
    end
end

---Waits for the suspect to be in their clip as this game has them (for one leaning out of a door, the door open here
---too) and their mouth to keep still in it (LIPS_STILL for LIPS_FOR, from them): it's where it stays. A player's ped
---on this game can take a second or more to get there after their clip plays (in game the spot moved 5.5 cm during
---the walk, the mouth 2 cm lower again once the arm was up). Their kind and how long it took (ms; nil: the mouth
---never kept still, gone on after LIPS_WAIT_MS), or nil and why not.
local function posed(session)
    local started, since, seen = GetGameTimer(), nil, {}
    while test == session do
        local sped = suspectPed(session)
        if not sped then return nil, 'they went' end
        local kind = blowing(sped)
        local ready = kind ~= nil
        if ready and Breathalyzer.isDoorKind(kind) then
            local vehicle, _, door = Breathalyzer.seatOf(sped)
            ready = vehicle ~= nil and door ~= nil and Breathalyzer.doorOpen(vehicle, door)
        end
        local now = GetGameTimer()
        if not ready then
            since, seen = nil, {}
            if now - started > POSE_MS then
                return nil, kind and 'the door by them did not open' or 'they never leaned to it (their clip did not play)'
            end
        else
            since = since or now
            seen[#seen + 1] = { at = now, p = wantOf(sped) }
            while seen[1].at < now - LIPS_FOR do table.remove(seen, 1) end
            if now - since >= LIPS_FOR and select(2, spreadOf(seen)) <= LIPS_STILL then return kind, now - since end
            if now - since >= LIPS_WAIT_MS then return kind, nil end
        end
        Wait(50)
    end
end

---The suspect's head as their own game has it in a test: not following their camera (client/suspect.lua), here too,
---where their mouth is measured.
local function headStill(session)
    local sped
    while test == session and (session.phase == 'place' or session.phase == 'held') do
        sped = suspectPed(session) or sped
        if sped then SetPedCanHeadIk(sped, false) end
        Wait(0)
    end
    if sped and DoesEntityExist(sped) then SetPedCanHeadIk(sped, true) end
end

---The officer walked to `at` (their origin) to face `heading`, as the game walks any ped: every game sees an ordinary
---walk, its own stop and turn. Back once the walk is done, they've stood still a while (against something), or the
---test ended.
local function walkTo(session, ped, at, heading)
    TaskGoStraightToCoord(ped, at.x, at.y, at.z, 1.0, -1, heading, WALK_SLIDE)    -- (any timeout but -1 breaks the walk)
    local started, still, going = GetGameTimer(), nil, false
    while test == session and GetGameTimer() - started < WALK_MS do
        Wait(0)
        -- done; or never given (it starts a frame after it's asked for)
        if GetScriptTaskStatus(ped, GO_STRAIGHT) ~= 7 then going = true
        elseif going or GetGameTimer() - started > 250 then return end
        if GetEntitySpeed(ped) >= 0.05 then still = nil
        elseif not still then still = GetGameTimer()
        elseif GetGameTimer() - still > STILL_MS then return end
    end
end

local function approach(session)
    if session.dummy then Breathalyzer.dummyBlow(session.dummy) else CreateThread(function() headStill(session) end) end
    local kind, took = posed(session)
    if test ~= session then return end
    if not kind then
        unreachable(session, took)
        return cancel('test.cant_reach')
    end
    local ped, sped = PlayerPedId(), suspectPed(session)
    if not sped then return cancel('test.left') end
    local car = Breathalyzer.isDoorKind(kind) and GetVehiclePedIsIn(sped, false) or nil
    local model = GetEntityModel(ped)
    local tips = seenTips(model)

    local cm, at, heading = plan(sped, GetEntityCoords(ped).z + anim.floor, tips)
    if not cm then
        unreachable(session, at)
        return cancel('test.cant_reach')
    end
    local clear, blocker = free(at, car)
    if not clear then
        unreachable(session, 'no room to stand at %.2f, %.2f, %.2f (entity %s in the way)', at.x, at.y, at.z, blocker)
        return cancel('test.cant_reach')
    end
    local mouth = wantOf(sped)
    walkTo(session, ped, at, heading)
    if test ~= session then return ClearPedTasks(ped) end

    -- From where they stand now, the floor is known: the clip and the spot again, for the last centimetre or two.
    sped = suspectPed(session)
    if not sped then return cancel('test.left') end
    cm, at, heading = plan(sped, GetEntityCoords(ped).z + anim.floor, tips)
    if not cm then
        ClearPedTasks(ped)
        unreachable(session, at)
        return cancel('test.cant_reach')
    end
    local short = #(GetEntityCoords(ped).xy - at.xy)
    if short > SLIDE then
        ClearPedTasks(ped)
        unreachable(session, 'the walk ended %.2f m short of where to stand (%.2f, %.2f)', short, at.x, at.y)
        return cancel('test.cant_reach')
    end

    -- The arm comes up as they stop (raise()). From here on they're attached to the suspect (put()), and the spot and
    -- everything looked at is from the suspect.
    StopAnimTask(ped, anim.dict, anim.hold, 2.0)
    session.to, session.model = sped, model
    session.spot, session.heading, session.off = fromThem(sped, at), heading - GetEntityHeading(sped), vec3(0.0, 0.0, 0.0)
    session.mouth, session.drift = wantOf(sped), nil
    session.last, session.stuck, session.warned, session.seen, session.moves, session.first = nil, nil, nil, nil, 0, nil
    local walked = #(session.mouth - mouth)
    reachClip(session, ped, cm, REACH)
    session.phase = 'held'
    raise(session, ped, sped)
    if test ~= session then return end
    session.steady = math.max(session.steady, GetGameTimer() + 100)
    -- The arm up: a look, and a move only when the end isn't in the mouth (the mouth moved after all, or a clip not
    -- seen yet on a model not made like freemode); a second should that one fall short; a last look for F8.
    for i = 1, 3 do
        if not steady(session) then return end
        sped = suspectPed(session)
        if not sped or not settle(session, ped, sped, i < 3 and AIM or math.huge) then break end
    end
    if test ~= session then return end
    TR.log.info("breath test: the mouthpiece to %s's mouth with clip %d (%s); their mouth %s, then moved %.1f cm while the officer walked and %.1f cm as the arm came up; the walk ended %.1f cm from the spot; %s; %d move%s after the arm came up",
        session.name, cm, tips[cm] and 'seen before' or next(tips) and 'by another clip seen' or 'as made in Blender',
        took and ('kept still after %.1f s'):format(took / 1000) or ('never kept still (went on after %.1f s)'):format(LIPS_WAIT_MS / 1000),
        walked * 100, (session.drift or 0.0) * 100, short * 100,
        session.miss and ('%.1f cm off along the ground, %.1f cm %s (the first look: %.1f cm off)'):format(session.miss * 100,
            math.abs(session.up) * 100, session.up >= 0 and 'high' or 'low', session.first * 100) or 'not looked at',
        session.moves, session.moves == 1 and '' or 's')
    TriggerServerEvent('tr_breathalyzer:placed')

    -- Held there: the clip kept on, and the mouthpiece kept in the mouth should the suspect move a little.
    while test == session and session.phase == 'held' do
        ped = PlayerPedId()
        if IsEntityDead(ped) or IsPedRagdoll(ped) then return cancel() end
        if not IsEntityPlayingAnim(ped, anim.dict, session.clip, 3) then reachClip(session, ped, session.cm, 4.0) end
        sped = suspectPed(session)
        if sped and GetGameTimer() >= session.steady then settle(session, ped, sped, HOLD) end
        Wait(250)
    end
end

RegisterNetEvent('tr_breathalyzer:go', function(suspect, dummy)
    if type(suspect) ~= 'number' then return end
    if not test or test.suspect ~= suspect or test.dummy ~= dummy then
        test = { suspect = suspect, dummy = dummy, name = dummy and t('dummy.name') or nameOf(suspect) }
    end
    test.phase = 'place'
    local session = test
    CreateThread(function() approach(session) end)
end)

---The device away from the mouth: the suspect (a dummy) let go, the officer free, and with `read` the device back in
---front of them to read, the camera on its screen.
local function takeBack(session, read)
    local ped = PlayerPedId()
    letGo(session, ped)
    if session.dummy then Breathalyzer.dummyStop(session.dummy) end
    if session.clip then StopAnimTask(ped, anim.dict, session.clip, 2.0) end
    session.clip = nil
    if read and deviceOut() then
        TaskPlayAnim(ped, anim.dict, anim.hold, 2.0, 2.0, -1, 49, 0.0, false, false, false)
        Breathalyzer.viewOpen()
    end
end

-- The breath is in: the suspect is free, the officer reads the device while it analyzes.
RegisterNetEvent('tr_breathalyzer:back', function(other)
    local session = test
    if not session or session.suspect ~= other or session.phase ~= 'held' then return end
    session.phase = 'back'
    takeBack(session, true)
end)

-- The reading (or TEST FAILED) stays on the camera a moment; a test that stopped takes the camera back now.
RegisterNetEvent('tr_breathalyzer:done', function(other, phase)
    local session = test
    if not session or session.suspect ~= other then return end
    local read = phase == 'result' or phase == 'failed'
    if session.phase ~= 'back' then takeBack(session, read) end
    session.phase = 'over'
    if test == session then test = nil end
    Breathalyzer.viewClose(read and READ_MS or nil)
end)

-- The slip --------------------------------------------------------------------------------------------------------
-- Once it's all out and the reading has been read, the left hand tears it off and puts it in the pocket (the tear
-- clip; client/device.lua moves the prop from the device to the hand on its frame, server/slip.lua gives the item).
local tearing = false
local TEAR_WAIT_MS = 15000  -- how long it may wait for that (the server gives it anyway soon after)

local function canTear(ped)
    return deviceOut() and not test and not Breathalyzer.viewing() and not unable(ped)
end

RegisterNetEvent('tr_breathalyzer:printed', function()
    if tearing then return end
    tearing = true
    CreateThread(function()
        local giveUp = GetGameTimer() + TEAR_WAIT_MS
        while not canTear(PlayerPedId()) do
            if not deviceOut() or GetGameTimer() > giveUp then
                tearing = false
                return
            end
            Wait(200)
        end
        local ped = PlayerPedId()
        TriggerServerEvent('tr_breathalyzer:tear')
        TaskPlayAnim(ped, anim.dict, anim.tear.clip, 4.0, 4.0, -1, 50, 0.0, false, false, false)
        local ends = GetGameTimer() + anim.tear.ms
        while GetGameTimer() < ends and deviceOut() and not unable(PlayerPedId()) do Wait(100) end
        ped = PlayerPedId()
        -- Back to the hold from the tear's last frame (the hold on average), or out of it if the device went.
        if deviceOut() and not unable(ped) then
            TaskPlayAnim(ped, anim.dict, anim.hold, 2.0, 2.0, -1, 49, 0.0, false, false, false)
        else
            StopAnimTask(ped, anim.dict, anim.tear.clip, 3.0)
        end
        tearing = false
    end)
end)

-- Holding it ------------------------------------------------------------------------------------------------------
local held = false     -- the hold clip was started
local hud = false      -- this file has the hint bar

local function hint(ped)
    if Breathalyzer.subject or Breathalyzer.asked or Breathalyzer.reading() then
        hud = false
        return
    end
    local cancelKey = TR.ui.keyOf('+tr_breath_cancel', Config.keys.cancel)
    if Breathalyzer.viewing() then
        local s = LocalPlayer.state.trBreath or {}
        TR.ui.hud.set({ hint = { text = t('hint.officer'), sub = t(s.s == 'analyze' and 'hint.officer_analyze' or 'hint.officer_read'),
            keys = { { key = cancelKey, label = t('key.back') } } } })
        hud = true
    elseif test then
        local s = LocalPlayer.state.trBreath or {}
        local sub
        if test.phase == 'ask' then sub = t('hint.officer_ask', { name = test.name })
        elseif test.phase == 'place' then sub = t('hint.officer_place')
        elseif test.phase == 'back' then sub = t(s.s == 'analyze' and 'hint.officer_analyze' or 'hint.officer_read')
        elseif s.s == 'blow' then sub = t(s.b and 'hint.officer_blowing' or 'hint.officer_blow', { name = test.name })
        elseif s.s == 'again' then sub = t('hint.officer_again', { name = test.name })
        elseif s.s == 'analyze' then sub = t('hint.officer_analyze')
        else sub = t('hint.officer_place') end
        TR.ui.hud.set({ hint = { text = t('hint.officer'), sub = sub, keys = { { key = cancelKey, label = t('key.stop') } } } })
        hud = true
    elseif deviceOut() then
        TR.ui.hud.set({ hint = { text = t('hint.out'), sub = t('hint.out_sub'), keys = { { key = cancelKey, label = t('key.away') } } } })
        hud = true
    elseif hud then
        TR.ui.hud.hide()
        hud = false
    end
end

CreateThread(function()
    TR.stream.anim(anim.dict)
    local awaySent = 0
    while true do
        local ped = PlayerPedId()
        local out = deviceOut()
        if out and (not test or test.phase == 'back') then
            if unable(ped) then
                if GetGameTimer() - awaySent > 2000 then
                    awaySent = GetGameTimer()
                    TriggerServerEvent('tr_breathalyzer:away')
                end
            elseif not tearing and not IsEntityPlayingAnim(ped, anim.dict, anim.hold, 3) then
                TaskPlayAnim(ped, anim.dict, anim.hold, 3.0, 3.0, -1, 49, 0.0, false, false, false)
            end
            held = true
        elseif held and not out then
            held = false
            StopAnimTask(ped, anim.dict, anim.hold, 3.0)
            StopAnimTask(ped, anim.dict, anim.tear.clip, 3.0)
        end
        hint(ped)
        Wait(250)
    end
end)

-- No punching or aiming with it in the hand.
CreateThread(function()
    while true do
        if deviceOut() or test then
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 140, true)  -- melee attacks
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Put away / stop: one key for both (the suspect's stop is the same key). On the screen's camera: back from it.
-- Reading a slip: puts it away.
RegisterCommand('+tr_breath_cancel', function()
    if Breathalyzer.reading() then return Breathalyzer.readStop() end
    if Breathalyzer.viewing() then return Breathalyzer.viewClose() end
    if test or Breathalyzer.subject then return TriggerServerEvent('tr_breathalyzer:cancel') end
    if deviceOut() then TriggerServerEvent('tr_breathalyzer:away') end
end, false)
RegisterCommand('-tr_breath_cancel', function() end, false)
RegisterKeyMapping('+tr_breath_cancel', t('keymap.cancel'), 'keyboard', Config.keys.cancel)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    if test and test.clip then StopAnimTask(ped, anim.dict, test.clip, 8.0) end
    if test then letGo(test, ped) end
    if held then StopAnimTask(ped, anim.dict, anim.hold, 8.0) end
    if tearing then StopAnimTask(ped, anim.dict, anim.tear.clip, 8.0) end
end)
