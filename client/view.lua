--[[
    The officer's camera on the device's screen once the breath is in: from the game's camera out round the right of
    their head to in front of the screen (shared/anim.lua's view, found in Blender from where the hold has the eyes),
    fixed to the device there so the screen stays still in the picture while the hold sways it, until the reading
    has been read; then back the same way. The officer stands still meanwhile.
]]
local anim = Breathalyzer.anim
local GLIDE_MS = 900        -- the way in, and the way back
local LONGEST = 20000       -- ms a view lasts at most, whatever happens (a reading that never came)
-- What stays still during it: moving, jumping, getting in, cover, the camera and its modes, weapons, fists.
local BLOCKED = { 0, 1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 140, 141, 142, 257, 263 }

---@class BrView
---@field cam integer
---@field opened integer GetGameTimer() when the way in started
---@field from table the camera the way in starts from: { at, look, fov }
---@field now? table where it is
---@field closeAt? integer when it goes back by itself
---@field back? { at: integer, from: table } on its way back since `at`
local view ---@type BrView?

local function ease(k)
    k = math.min(math.max(k, 0.0), 1.0)
    return k * k * (3.0 - 2.0 * k)
end

local function myDevice()
    local device = Breathalyzer.deviceOf(GetPlayerServerId(PlayerId()))
    return device and DoesEntityExist(device) and device or nil
end

---The game's own camera: { at, look (a point it looks at), fov }.
local function gameCamera()
    local at, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local ahead = vec3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    return { at = at, look = at + ahead, fov = GetGameplayCamFov() }
end

---The camera in front of the screen, where the device is now.
local function screenCamera(device)
    local v = anim.view
    return {
        at = GetOffsetFromEntityInWorldCoords(device, v.at.x, v.at.y, v.at.z),
        look = GetOffsetFromEntityInWorldCoords(device, v.look.x, v.look.y, v.look.z),
        fov = v.fov,
    }
end

---k of the way from camera a to camera b (eased), on a curve out round the officer's right: a straight line from
---behind them to in front of their face would go through their head.
local function between(a, b, k)
    k = ease(k)
    local ped = PlayerPedId()
    local right = GetOffsetFromEntityInWorldCoords(ped, 1.0, 0.0, 0.0) - GetEntityCoords(ped)
    local bend = (a.at + b.at) / 2 + right * math.min(#(b.at - a.at) * 0.35, 0.8)
    local u = 1.0 - k
    return {
        at = a.at * (u * u) + bend * (2.0 * u * k) + b.at * (k * k),
        look = a.look + (b.look - a.look) * k,
        fov = a.fov + (b.fov - a.fov) * k,
    }
end

local function aim(v, c)
    SetCamCoord(v.cam, c.at.x, c.at.y, c.at.z)
    PointCamAtCoord(v.cam, c.look.x, c.look.y, c.look.z)
    SetCamFov(v.cam, c.fov + 0.0)
    v.now = c
end

local function release(v)
    if view ~= v then return end
    view = nil
    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(v.cam, false)
end

local function run(v)
    while view == v do
        local now = GetGameTimer()
        for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
        local ped, device = PlayerPedId(), myDevice()
        if not v.back and (not device or IsEntityDead(ped) or IsPedRagdoll(ped) or now - v.opened > LONGEST
                or (v.closeAt and now >= v.closeAt)) then
            v.back = { at = now, from = v.now }
        end
        if v.back then
            local k = (now - v.back.at) / GLIDE_MS
            if k >= 1.0 then return release(v) end
            aim(v, between(v.back.from, gameCamera(), k))
        else
            local there = screenCamera(device)
            local k = (now - v.opened) / GLIDE_MS
            aim(v, k < 1.0 and between(v.from, there, k) or there)
        end
        Wait(0)
    end
end

---The camera to the screen of the device in this game's hand (from where it is, if it was on its way back).
function Breathalyzer.viewOpen()
    if view then
        if view.back then
            view.from, view.opened, view.back, view.closeAt = view.now, GetGameTimer(), nil, nil
        end
        return
    end
    if not myDevice() then return end
    local v = { cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true), opened = GetGameTimer(), from = gameCamera() }
    view = v
    aim(v, v.from)
    RenderScriptCams(true, false, 0, true, false)
    CreateThread(function() run(v) end)
end

---The camera back to the game's in `ms` (now when not given).
---@param ms? integer
function Breathalyzer.viewClose(ms)
    local v = view
    if not v or v.back then return end
    if ms and ms > 0 then
        v.closeAt = GetGameTimer() + ms
    else
        v.back = { at = GetGameTimer(), from = v.now }
    end
end

---Whether the camera is on (or going to or from) the screen.
function Breathalyzer.viewing() return view ~= nil end

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and view then release(view) end
end)
