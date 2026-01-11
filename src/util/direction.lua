--[[
    Direction helpers for 8-direction and 32-direction facing
    Matches original C&C direction system
]]

local Direction = {}

-- 8 cardinal directions (used for movement and basic facing)
Direction.FACING = {
    N = 0,      -- North (up)
    NE = 1,     -- Northeast
    E = 2,      -- East (right)
    SE = 3,     -- Southeast
    S = 4,      -- South (down)
    SW = 5,     -- Southwest
    W = 6,      -- West (left)
    NW = 7      -- Northwest
}

-- Direction offsets for cell movement (dx, dy)
Direction.OFFSETS = {
    [0] = {x = 0, y = -1},   -- N
    [1] = {x = 1, y = -1},   -- NE
    [2] = {x = 1, y = 0},    -- E
    [3] = {x = 1, y = 1},    -- SE
    [4] = {x = 0, y = 1},    -- S
    [5] = {x = -1, y = 1},   -- SW
    [6] = {x = -1, y = 0},   -- W
    [7] = {x = -1, y = -1}   -- NW
}

-- Full 32-direction system (used for turret facing and smooth rotation)
Direction.FULL_COUNT = 32
Direction.FACING_COUNT = 8

-- Angle per facing direction (radians)
Direction.ANGLE_PER_FACING = (2 * math.pi) / Direction.FACING_COUNT
Direction.ANGLE_PER_FULL = (2 * math.pi) / Direction.FULL_COUNT

-- Convert 8-direction facing to radians
function Direction.facing_to_angle(facing)
    -- Facing 0 = North = -pi/2 radians (up on screen)
    return ((facing * Direction.ANGLE_PER_FACING) - math.pi / 2)
end

-- Convert radians to 8-direction facing
function Direction.angle_to_facing(angle)
    -- Normalize angle to 0-2pi
    angle = angle + math.pi / 2  -- Offset so 0 = North
    while angle < 0 do angle = angle + 2 * math.pi end
    while angle >= 2 * math.pi do angle = angle - 2 * math.pi end

    -- Convert to facing
    local facing = math.floor((angle / Direction.ANGLE_PER_FACING) + 0.5)
    return facing % Direction.FACING_COUNT
end

-- Convert 32-direction to radians
function Direction.full_to_angle(facing)
    return ((facing * Direction.ANGLE_PER_FULL) - math.pi / 2)
end

-- Convert radians to 32-direction
function Direction.angle_to_full(angle)
    angle = angle + math.pi / 2
    while angle < 0 do angle = angle + 2 * math.pi end
    while angle >= 2 * math.pi do angle = angle - 2 * math.pi end

    local facing = math.floor((angle / Direction.ANGLE_PER_FULL) + 0.5)
    return facing % Direction.FULL_COUNT
end

-- Convert 8-direction to 32-direction
function Direction.facing_to_full(facing)
    return (facing * 4) % Direction.FULL_COUNT
end

-- Convert 32-direction to 8-direction (nearest)
function Direction.full_to_facing(full)
    return math.floor((full + 2) / 4) % Direction.FACING_COUNT
end

-- Get direction from one point to another (8-direction)
function Direction.from_points(x1, y1, x2, y2)
    local angle = math.atan2(y2 - y1, x2 - x1)
    return Direction.angle_to_facing(angle)
end

-- Get 32-direction from points
function Direction.from_points_full(x1, y1, x2, y2)
    local angle = math.atan2(y2 - y1, x2 - x1)
    return Direction.angle_to_full(angle)
end

-- Get opposite direction
function Direction.opposite(facing)
    return (facing + 4) % Direction.FACING_COUNT
end

function Direction.opposite_full(facing)
    return (facing + 16) % Direction.FULL_COUNT
end

-- Rotate direction by amount (positive = clockwise)
function Direction.rotate(facing, amount)
    return (facing + amount) % Direction.FACING_COUNT
end

function Direction.rotate_full(facing, amount)
    return (facing + amount) % Direction.FULL_COUNT
end

-- Calculate shortest rotation between two facings
-- Returns positive for clockwise, negative for counter-clockwise
function Direction.shortest_turn(from, to)
    local diff = to - from
    if diff > 4 then
        diff = diff - 8
    elseif diff < -4 then
        diff = diff + 8
    end
    return diff
end

function Direction.shortest_turn_full(from, to)
    local diff = to - from
    if diff > 16 then
        diff = diff - 32
    elseif diff < -16 then
        diff = diff + 32
    end
    return diff
end

-- Step one facing increment towards target
function Direction.turn_towards(current, target)
    local diff = Direction.shortest_turn(current, target)
    if diff > 0 then
        return (current + 1) % Direction.FACING_COUNT
    elseif diff < 0 then
        return (current - 1 + Direction.FACING_COUNT) % Direction.FACING_COUNT
    end
    return current
end

function Direction.turn_towards_full(current, target)
    local diff = Direction.shortest_turn_full(current, target)
    if diff > 0 then
        return (current + 1) % Direction.FULL_COUNT
    elseif diff < 0 then
        return (current - 1 + Direction.FULL_COUNT) % Direction.FULL_COUNT
    end
    return current
end

-- Get cell offset for a direction
function Direction.get_offset(facing)
    return Direction.OFFSETS[facing]
end

-- Get adjacent cell coordinates
function Direction.get_adjacent_cell(cell_x, cell_y, facing)
    local offset = Direction.OFFSETS[facing]
    return cell_x + offset.x, cell_y + offset.y
end

-- Check if a direction is diagonal
function Direction.is_diagonal(facing)
    return facing % 2 == 1
end

-- Distance modifier for diagonal movement (sqrt(2))
Direction.DIAGONAL_COST = 1.41421356

-- Get movement cost multiplier for direction
function Direction.movement_cost(facing)
    if Direction.is_diagonal(facing) then
        return Direction.DIAGONAL_COST
    end
    return 1.0
end

-- Direction names for debugging
Direction.NAMES = {
    [0] = "N",
    [1] = "NE",
    [2] = "E",
    [3] = "SE",
    [4] = "S",
    [5] = "SW",
    [6] = "W",
    [7] = "NW"
}

function Direction.to_string(facing)
    return Direction.NAMES[facing] or "?"
end

return Direction
