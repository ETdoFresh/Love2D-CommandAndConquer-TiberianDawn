--[[
    Pathfinding - A* pathfinding with original C&C behavior
    Implements cell-based pathfinding with terrain costs and blocking
    Reference: Original C&C pathfinding (FOOT.CPP, DRIVE.CPP)
]]

local Pathfinding = {}
Pathfinding.__index = Pathfinding

-- Movement costs (from original C&C)
Pathfinding.COST = {
    CLEAR = 1,
    ROUGH = 2,
    ROAD = 0.8,
    WATER = 255,      -- Impassable for ground
    CLIFF = 255,      -- Impassable
    TIBERIUM = 1,     -- Same as clear (damages infantry)
    BUILDING = 255    -- Impassable
}

-- Locomotor types affect passability
Pathfinding.LOCOMOTOR = {
    FOOT = "foot",      -- Infantry
    TRACK = "track",    -- Tanks
    WHEEL = "wheel",    -- Wheeled vehicles
    FLOAT = "float",    -- Hovercraft
    FLY = "fly"         -- Aircraft
}

-- Direction offsets (8-directional)
Pathfinding.DIRECTIONS = {
    {dx = 0, dy = -1, cost = 1.0},     -- N
    {dx = 1, dy = -1, cost = 1.414},   -- NE
    {dx = 1, dy = 0, cost = 1.0},      -- E
    {dx = 1, dy = 1, cost = 1.414},    -- SE
    {dx = 0, dy = 1, cost = 1.0},      -- S
    {dx = -1, dy = 1, cost = 1.414},   -- SW
    {dx = -1, dy = 0, cost = 1.0},     -- W
    {dx = -1, dy = -1, cost = 1.414}   -- NW
}

function Pathfinding.new(grid)
    local self = setmetatable({}, Pathfinding)

    -- Reference to map grid
    self.grid = grid

    -- Map dimensions
    self.width = grid and grid.width or 64
    self.height = grid and grid.height or 64

    -- Pathfinding limits (from original C&C)
    self.max_iterations = 500       -- Max A* iterations
    self.max_path_length = 128      -- Max path cells

    -- Cached terrain costs
    self.terrain_costs = {}

    -- Blocked cells (dynamic, from units/buildings)
    self.blocked = {}

    -- Reserved cells (units moving into)
    self.reserved = {}

    return self
end

-- Find path from start to goal
function Pathfinding:find_path(start_x, start_y, goal_x, goal_y, locomotor)
    locomotor = locomotor or Pathfinding.LOCOMOTOR.TRACK

    -- Validate coordinates
    if not self:is_valid_cell(start_x, start_y) or not self:is_valid_cell(goal_x, goal_y) then
        return nil
    end

    -- Check if goal is reachable
    if not self:is_passable(goal_x, goal_y, locomotor) then
        -- Try to find nearest passable cell to goal
        goal_x, goal_y = self:find_nearest_passable(goal_x, goal_y, locomotor)
        if not goal_x then
            return nil
        end
    end

    -- A* algorithm
    local open_set = {}
    local closed_set = {}
    local came_from = {}
    local g_score = {}
    local f_score = {}

    local start_key = self:cell_key(start_x, start_y)
    local goal_key = self:cell_key(goal_x, goal_y)

    g_score[start_key] = 0
    f_score[start_key] = self:heuristic(start_x, start_y, goal_x, goal_y)
    open_set[start_key] = {x = start_x, y = start_y, f = f_score[start_key]}

    local iterations = 0

    while next(open_set) do
        iterations = iterations + 1
        if iterations > self.max_iterations then
            -- Path too complex, return partial path
            return self:reconstruct_path(came_from, self:find_best_partial(closed_set, goal_x, goal_y))
        end

        -- Find node with lowest f_score
        local current_key, current = self:get_lowest_f(open_set)

        -- Reached goal
        if current_key == goal_key then
            return self:reconstruct_path(came_from, current_key)
        end

        -- Move to closed set
        open_set[current_key] = nil
        closed_set[current_key] = true

        -- Check neighbors
        for _, dir in ipairs(Pathfinding.DIRECTIONS) do
            local nx = current.x + dir.dx
            local ny = current.y + dir.dy
            local neighbor_key = self:cell_key(nx, ny)

            -- Skip if already evaluated or invalid
            if closed_set[neighbor_key] then
                goto continue
            end

            if not self:is_valid_cell(nx, ny) then
                goto continue
            end

            if not self:is_passable(nx, ny, locomotor) then
                goto continue
            end

            -- Calculate tentative g_score
            local terrain_cost = self:get_terrain_cost(nx, ny, locomotor)
            local move_cost = dir.cost * terrain_cost
            local tentative_g = g_score[current_key] + move_cost

            -- Check if this is a better path
            if not g_score[neighbor_key] or tentative_g < g_score[neighbor_key] then
                came_from[neighbor_key] = current_key
                g_score[neighbor_key] = tentative_g
                f_score[neighbor_key] = tentative_g + self:heuristic(nx, ny, goal_x, goal_y)

                if not open_set[neighbor_key] then
                    open_set[neighbor_key] = {x = nx, y = ny, f = f_score[neighbor_key]}
                end
            end

            ::continue::
        end
    end

    -- No path found
    return nil
end

-- Find path with maximum distance limit
function Pathfinding:find_path_limited(start_x, start_y, goal_x, goal_y, max_distance, locomotor)
    local path = self:find_path(start_x, start_y, goal_x, goal_y, locomotor)

    if path and #path > max_distance then
        -- Truncate path
        local truncated = {}
        for i = 1, max_distance do
            truncated[i] = path[i]
        end
        return truncated
    end

    return path
end

-- Heuristic function (Manhattan distance with diagonal shortcut)
function Pathfinding:heuristic(x1, y1, x2, y2)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)

    -- Octile distance (allows diagonal movement)
    return math.max(dx, dy) + (1.414 - 1) * math.min(dx, dy)
end

-- Get node with lowest f_score from open set
function Pathfinding:get_lowest_f(open_set)
    local best_key = nil
    local best_node = nil
    local best_f = math.huge

    for key, node in pairs(open_set) do
        if node.f < best_f then
            best_f = node.f
            best_key = key
            best_node = node
        end
    end

    return best_key, best_node
end

-- Reconstruct path from came_from map
function Pathfinding:reconstruct_path(came_from, current_key)
    local path = {}

    while current_key do
        local x, y = self:key_to_cell(current_key)
        table.insert(path, 1, {x = x, y = y})
        current_key = came_from[current_key]
    end

    -- Limit path length
    if #path > self.max_path_length then
        local truncated = {}
        for i = 1, self.max_path_length do
            truncated[i] = path[i]
        end
        return truncated
    end

    return path
end

-- Find best partial path when full path not found
function Pathfinding:find_best_partial(closed_set, goal_x, goal_y)
    local best_key = nil
    local best_dist = math.huge

    for key in pairs(closed_set) do
        local x, y = self:key_to_cell(key)
        local dist = self:heuristic(x, y, goal_x, goal_y)
        if dist < best_dist then
            best_dist = dist
            best_key = key
        end
    end

    return best_key
end

-- Check if cell is valid
function Pathfinding:is_valid_cell(x, y)
    return x >= 0 and x < self.width and y >= 0 and y < self.height
end

-- Check if cell is passable for locomotor
function Pathfinding:is_passable(x, y, locomotor)
    -- Aircraft can fly anywhere
    if locomotor == Pathfinding.LOCOMOTOR.FLY then
        return self:is_valid_cell(x, y)
    end

    -- Check terrain
    if self.grid then
        local cell = self.grid:get_cell(x, y)
        if cell then
            -- Check if blocked by terrain
            if cell.passability == false then
                return false
            end

            -- Check water for non-hover units
            if cell.terrain_type == "water" and locomotor ~= Pathfinding.LOCOMOTOR.FLOAT then
                return false
            end
        end
    end

    -- Check dynamic blocking
    local key = self:cell_key(x, y)
    if self.blocked[key] then
        return false
    end

    return true
end

-- Get terrain movement cost
function Pathfinding:get_terrain_cost(x, y, locomotor)
    if locomotor == Pathfinding.LOCOMOTOR.FLY then
        return 1.0  -- Aircraft ignore terrain
    end

    local key = self:cell_key(x, y)

    -- Check cache
    if self.terrain_costs[key] then
        return self.terrain_costs[key]
    end

    local cost = Pathfinding.COST.CLEAR

    if self.grid then
        local cell = self.grid:get_cell(x, y)
        if cell then
            if cell.terrain_type == "rough" then
                cost = Pathfinding.COST.ROUGH
            elseif cell.terrain_type == "road" then
                cost = Pathfinding.COST.ROAD
            elseif cell.has_tiberium then
                cost = Pathfinding.COST.TIBERIUM
            end

            -- Wheeled vehicles are slower on rough terrain
            if locomotor == Pathfinding.LOCOMOTOR.WHEEL and cell.terrain_type == "rough" then
                cost = cost * 1.5
            end
        end
    end

    self.terrain_costs[key] = cost
    return cost
end

-- Find nearest passable cell to target
function Pathfinding:find_nearest_passable(x, y, locomotor)
    -- Search in expanding rings
    for radius = 1, 10 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local nx = x + dx
                    local ny = y + dy
                    if self:is_valid_cell(nx, ny) and self:is_passable(nx, ny, locomotor) then
                        return nx, ny
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Mark cell as blocked (by unit or building)
function Pathfinding:block_cell(x, y, entity_id)
    local key = self:cell_key(x, y)
    self.blocked[key] = entity_id or true
end

-- Unblock cell
function Pathfinding:unblock_cell(x, y)
    local key = self:cell_key(x, y)
    self.blocked[key] = nil
end

-- Check if cell is blocked
function Pathfinding:is_blocked(x, y)
    return self.blocked[self:cell_key(x, y)] ~= nil
end

-- Reserve cell (unit moving into it)
function Pathfinding:reserve_cell(x, y, entity_id)
    local key = self:cell_key(x, y)
    self.reserved[key] = entity_id
end

-- Unreserve cell
function Pathfinding:unreserve_cell(x, y)
    local key = self:cell_key(x, y)
    self.reserved[key] = nil
end

-- Check if cell is reserved
function Pathfinding:is_reserved(x, y)
    return self.reserved[self:cell_key(x, y)] ~= nil
end

-- Get who reserved a cell
function Pathfinding:get_reservation(x, y)
    return self.reserved[self:cell_key(x, y)]
end

-- Block cells for a multi-cell building
function Pathfinding:block_building(x, y, width, height, entity_id)
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            self:block_cell(x + dx, y + dy, entity_id)
        end
    end
end

-- Unblock cells for a building
function Pathfinding:unblock_building(x, y, width, height)
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            self:unblock_cell(x + dx, y + dy)
        end
    end
end

-- Clear terrain cost cache
function Pathfinding:clear_cost_cache()
    self.terrain_costs = {}
end

-- Clear all dynamic blocks
function Pathfinding:clear_blocks()
    self.blocked = {}
    self.reserved = {}
end

-- Cell key utilities
function Pathfinding:cell_key(x, y)
    return y * self.width + x
end

function Pathfinding:key_to_cell(key)
    local x = key % self.width
    local y = math.floor(key / self.width)
    return x, y
end

-- Get straight line distance
function Pathfinding:distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Get Manhattan distance
function Pathfinding:manhattan_distance(x1, y1, x2, y2)
    return math.abs(x2 - x1) + math.abs(y2 - y1)
end

-- Check line of sight between two cells
function Pathfinding:has_line_of_sight(x1, y1, x2, y2, locomotor)
    -- Bresenham's line algorithm
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    local x, y = x1, y1

    while x ~= x2 or y ~= y2 do
        if not self:is_passable(x, y, locomotor) then
            return false
        end

        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x = x + sx
        end
        if e2 < dx then
            err = err + dx
            y = y + sy
        end
    end

    return true
end

-- Smooth path by removing unnecessary waypoints
function Pathfinding:smooth_path(path, locomotor)
    if not path or #path < 3 then
        return path
    end

    local smoothed = {path[1]}
    local i = 1

    while i < #path do
        local current = smoothed[#smoothed]
        local farthest_visible = i + 1

        -- Find farthest visible point
        for j = i + 2, #path do
            if self:has_line_of_sight(current.x, current.y, path[j].x, path[j].y, locomotor) then
                farthest_visible = j
            else
                break
            end
        end

        table.insert(smoothed, path[farthest_visible])
        i = farthest_visible
    end

    return smoothed
end

-- Debug: draw path
function Pathfinding:draw_path(path, cell_size, camera_x, camera_y)
    if not path then return end

    cell_size = cell_size or 24
    camera_x = camera_x or 0
    camera_y = camera_y or 0

    love.graphics.setColor(0, 1, 0, 0.7)
    love.graphics.setLineWidth(2)

    for i = 1, #path - 1 do
        local x1 = (path[i].x + 0.5) * cell_size - camera_x
        local y1 = (path[i].y + 0.5) * cell_size - camera_y
        local x2 = (path[i + 1].x + 0.5) * cell_size - camera_x
        local y2 = (path[i + 1].y + 0.5) * cell_size - camera_y

        love.graphics.line(x1, y1, x2, y2)
        love.graphics.circle("fill", x1, y1, 3)
    end

    -- Draw end point
    if #path > 0 then
        local last = path[#path]
        local x = (last.x + 0.5) * cell_size - camera_x
        local y = (last.y + 0.5) * cell_size - camera_y
        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.circle("fill", x, y, 5)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Pathfinding
