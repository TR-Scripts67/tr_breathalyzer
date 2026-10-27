--[[
    Where a suspect's mouth is and how they take the test: standing, in a car turned to the window, or in a high cab
    (a Sandking: its window's sill is above an officer's head) leaning out of the open door to the officer stood in
    the doorway. Only the game that owns a car can open its door for everyone, so the server passes it on
    (server/test.lua) and has it shut again once the suspect is let go and nobody stands in its way.
]]
local anim = Breathalyzer.anim
local HEAD = 31086          -- SKEL_Head
local OPEN = 0.9            -- how far open (GetVehicleDoorAngleRatio) a door is open enough to lean out of
local SHUT_CLEAR = 1.5      -- m from the hinge nobody on foot may stand for the door to swing shut (it's ~1.1 m long)
local SHUT_WAIT = 30000     -- ms the door waits for that, then shuts anyway
local DOOR_BONES = { [0] = 'door_dside_f', [1] = 'door_pside_f', [2] = 'door_dside_r', [3] = 'door_pside_r' }

---A ped's lips (their front) and the way their face looks, in the world: by the face's own lip bones, where this ped
---has its mouth; for one without them by the head bone, where freemode has the lips on it.
---@return vector3 lips, vector3 face
function Breathalyzer.lipsOf(ped)
    local head = GetPedBoneIndex(ped, HEAD)
    local up, low = GetPedBoneIndex(ped, anim.lipBones[1]), GetPedBoneIndex(ped, anim.lipBones[2])
    if head ~= -1 and up ~= -1 and low ~= -1 then
        local h = GetWorldPositionOfEntityBone(ped, head)
        local a, b = GetWorldPositionOfEntityBone(ped, up), GetWorldPositionOfEntityBone(ped, low)
        local out = #(a - h)
        if out > 0.05 and out < 0.2 then          -- a real lip, not a bone the ped hasn't got
            local face = (a - h) / out
            return (a + b) / 2 + face * anim.lipFront, face
        end
    end
    local l, f = anim.lips, anim.face
    local lips = GetPedBoneCoords(ped, HEAD, l.x, l.y, l.z)
    local ahead = GetPedBoneCoords(ped, HEAD, l.x + f.x * 0.1, l.y + f.y * 0.1, l.z + f.z * 0.1)
    local face = ahead - lips
    return lips, face / #face
end

local function seatOf(ped, vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
end

---How high `lips` are above the ground 1.2 m out from the car on its left (or right) side, where the officer stands.
local function aboveGround(vehicle, lips, left)
    local right = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - GetEntityCoords(vehicle)
    local at = lips + right * (left and -1.2 or 1.2)
    local found, ground = GetGroundZFor_3dCoord(at.x + 0.0, at.y + 0.0, lips.z + 0.5, false)
    if not found then ground = GetEntityCoords(vehicle).z - GetEntityHeightAboveGround(vehicle) end
    return lips.z - ground
end

---The car `ped` sits in, the side of it they sit on ('left' / 'right') and the door (and window) by their seat: 0..3,
---front left, front right, rear left, rear right; nil past the fourth seat.
---@return integer? vehicle, string? side, integer? door
function Breathalyzer.seatOf(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return nil end
    local seat = seatOf(ped, vehicle) or -1
    return vehicle, (seat + 2) % 2 == 1 and 'left' or 'right', seat <= 2 and seat + 1 or nil   -- the driver (-1) and the odd seats sit on the left
end

---How the suspect takes it (a key of anim.blow): 'stand'; in a car 'left' / 'right' (the side their window is on)
---and the window to roll down; or in a high cab 'left_door' / 'right_door' and the door to open. It goes by how high
---they sit: ask before their clip plays.
---@return string kind, integer? window, integer? door
function Breathalyzer.subjectKind(ped)
    local vehicle, side, door = Breathalyzer.seatOf(ped)
    if not vehicle then return 'stand' end
    if not door then return side end
    local up = aboveGround(vehicle, Breathalyzer.lipsOf(ped), side == 'left')
    if up >= anim.door.from and up <= anim.door.to then return side .. '_door', nil, door end
    return side, door
end

---Whether `kind` leans out of a door.
function Breathalyzer.isDoorKind(kind) return kind == 'left_door' or kind == 'right_door' end

---Whether a car's door is open enough to lean out of (or there's none there to open: gone, or never had one).
function Breathalyzer.doorOpen(vehicle, door)
    if not GetIsDoorValid(vehicle, door) or IsVehicleDoorDamaged(vehicle, door) then return true end
    return GetVehicleDoorAngleRatio(vehicle, door) >= OPEN
end

---Asks for the door of `ped`'s car to be opened (the server checks they're in a test; the car's owner opens it).
function Breathalyzer.openDoor(ped, door)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then return end
    TriggerServerEvent('tr_breathalyzer:door', NetworkGetNetworkIdFromEntity(vehicle), door)
end

---Whether anyone on foot stands where the door swings.
local function inTheWay(vehicle, door)
    local bone = GetEntityBoneIndexByName(vehicle, DOOR_BONES[door])
    local hinge = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedInAnyVehicle(ped, true) and #(GetEntityCoords(ped) - hinge) < SHUT_CLEAR then return true end
    end
    return false
end

local shutting = {} ---@type table<string, true> the doors waiting to shut, by net id and door

-- The server, to the game that owns the car: open a door, or shut it (after a moment, and once nobody stands where
-- it swings or the car drives off).
RegisterNetEvent('tr_breathalyzer:door', function(netId, door, open)
    if type(netId) ~= 'number' or not DOOR_BONES[door] then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local key = netId .. ':' .. door
    if open then
        shutting[key] = nil
        return SetVehicleDoorOpen(vehicle, door, false, false)
    end
    if shutting[key] then return end
    shutting[key] = true
    CreateThread(function()
        Wait(1000)      -- the suspect leans back in first
        local started = GetGameTimer()
        while shutting[key] and DoesEntityExist(vehicle) and GetGameTimer() - started < SHUT_WAIT
            and inTheWay(vehicle, door) and GetEntitySpeed(vehicle) < 1.0 do
            Wait(250)
        end
        if shutting[key] and DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, door, false) end
        shutting[key] = nil
    end)
end)
