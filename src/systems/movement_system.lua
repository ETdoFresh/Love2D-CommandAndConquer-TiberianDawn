--[[
    Movement System - Handles unit movement and pathfinding
    Uses original C&C pathfinding behavior
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Direction = require("src.util.direction")

local MovementSystem = setmetatable({}, {__index = System})
MovementSystem.__index = MovementSystem

function MovementSystem.new(grid)
    local self = System.new("movement", {"transform", "mobile"})
    setmetatable(self, MovementSystem)

    self.grid = grid  -- Reference to map grid

    return self
end

function MovementSystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end
end

function MovementSystem:process_entity(dt, entity)
    local transform = entity:get("transform")
    local mobile = entity:get("mobile")

    -- Check for tiberium damage to infantry
    if entity:has("infantry") and entity:has("health") and self.grid then
        local cell = self.grid:get_cell(transform.cell_x, transform.cell_y)
        if cell and cell:has_tiberium() then
            -- Infantry take damage on tiberium (1 damage per tick)
            local health = entity:get("health")
            health.hp = health.hp - 1
            if health.hp <= 0 then
                health.hp = 0
                -- Unit dies from tiberium
                local Events = require("src.core.events")
                Events.emit(Events.EVENTS.ENTITY_KILLED, entity, nil)
                if self.world then
                    self.world:destroy_entity(entity)
                end
                return
            end
        end
    end

    if not mobile.is_moving then
        return
    end

    -- Check if we have a path to follow
    if #mobile.path == 0 then
        mobile.is_moving = false
        return
    end

    -- Get current target cell from path
    local target_cell = mobile.path[mobile.path_index]
    if not target_cell then
        mobile.is_moving = false
        mobile.path = {}
        return
    end

    -- Calculate target position (center of cell) in leptons
    local target_x = target_cell.x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
    local target_y = target_cell.y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2

    -- Calculate distance to target
    local dx = target_x - transform.x
    local dy = target_y - transform.y
    local distance = math.sqrt(dx * dx + dy * dy)

    -- Calculate movement speed (leptons per frame, adjusted for tick rate)
    local speed = mobile.speed * (dt * Constants.TICKS_PER_SECOND)

    -- Check if we've arrived at current path node
    if distance <= speed then
        -- Snap to cell center
        transform.x = target_x
        transform.y = target_y
        transform.cell_x = target_cell.x
        transform.cell_y = target_cell.y

        -- Move to next path node
        mobile.path_index = mobile.path_index + 1
        if mobile.path_index > #mobile.path then
            -- Path complete
            mobile.is_moving = false
            mobile.path = {}
            mobile.path_index = 0
        end
    else
        -- Move towards target
        local move_x = (dx / distance) * speed
        local move_y = (dy / distance) * speed

        transform.x = transform.x + move_x
        transform.y = transform.y + move_y

        -- Update cell position
        transform.cell_x = math.floor(transform.x / Constants.LEPTON_PER_CELL)
        transform.cell_y = math.floor(transform.y / Constants.LEPTON_PER_CELL)

        -- Update facing
        transform.facing = Direction.from_points(0, 0, dx, dy)
    end
end

-- Command unit to move to destination
function MovementSystem:move_to(entity, dest_x, dest_y)
    if not entity:has("mobile") then return false end

    local transform = entity:get("transform")
    local mobile = entity:get("mobile")

    -- Convert destination to cell coordinates
    local dest_cell_x = math.floor(dest_x / Constants.LEPTON_PER_CELL)
    local dest_cell_y = math.floor(dest_y / Constants.LEPTON_PER_CELL)

    -- Calculate path
    local path = self:find_path(
        transform.cell_x, transform.cell_y,
        dest_cell_x, dest_cell_y,
        mobile.locomotor
    )

    if path and #path > 0 then
        mobile.path = path
        mobile.path_index = 1
        mobile.destination_x = dest_x
        mobile.destination_y = dest_y
        mobile.is_moving = true
        return true
    end

    return false
end

-- Simple A* pathfinding
function MovementSystem:find_path(start_x, start_y, end_x, end_y, locomotor)
    if not self.grid then return nil end

    -- Check if destination is valid
    local end_cell = self.grid:get_cell(end_x, end_y)
    if not end_cell or not end_cell:is_passable(locomotor) then
        -- Try to find nearest valid cell
        end_cell = self:find_nearest_passable(end_x, end_y, locomotor)
        if not end_cell then
            return nil
        end
        end_x = end_cell.x
        end_y = end_cell.y
    end

    -- A* implementation
    local open_set = {}
    local closed_set = {}
    local came_from = {}
    local g_score = {}
    local f_score = {}

    local start_key = start_y * Constants.MAP_CELL_W + start_x
    local end_key = end_y * Constants.MAP_CELL_W + end_x

    g_score[start_key] = 0
    f_score[start_key] = self:heuristic(start_x, start_y, end_x, end_y)
    open_set[start_key] = {x = start_x, y = start_y}

    local max_iterations = 1000
    local iterations = 0

    while next(open_set) and iterations < max_iterations do
        iterations = iterations + 1

        -- Find node with lowest f_score
        local current_key = nil
        local current = nil
        local lowest_f = math.huge

        for key, node in pairs(open_set) do
            local f = f_score[key] or math.huge
            if f < lowest_f then
                lowest_f = f
                current_key = key
                current = node
            end
        end

        if not current then break end

        -- Check if we've reached the goal
        if current.x == end_x and current.y == end_y then
            return self:reconstruct_path(came_from, current_key)
        end

        open_set[current_key] = nil
        closed_set[current_key] = true

        -- Check all neighbors
        for dir = 0, 7 do
            local neighbor = self.grid:get_adjacent(current.x, current.y, dir)
            if neighbor then
                local neighbor_key = neighbor.y * Constants.MAP_CELL_W + neighbor.x

                if not closed_set[neighbor_key] then
                    -- Check passability
                    if neighbor:is_passable(locomotor) then
                        -- Calculate tentative g_score
                        local move_cost = Direction.is_diagonal(dir) and Direction.DIAGONAL_COST or 1
                        local tentative_g = (g_score[current_key] or math.huge) + move_cost

                        if tentative_g < (g_score[neighbor_key] or math.huge) then
                            came_from[neighbor_key] = current_key
                            g_score[neighbor_key] = tentative_g
                            f_score[neighbor_key] = tentative_g + self:heuristic(neighbor.x, neighbor.y, end_x, end_y)

                            if not open_set[neighbor_key] then
                                open_set[neighbor_key] = {x = neighbor.x, y = neighbor.y}
                            end
                        end
                    end
                end
            end
        end
    end

    -- No path found
    return nil
end

-- Heuristic: octile distance
function MovementSystem:heuristic(x1, y1, x2, y2)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local D = 1
    local D2 = Direction.DIAGONAL_COST
    return D * (dx + dy) + (D2 - 2 * D) * math.min(dx, dy)
end

-- Reconstruct path from A* result
function MovementSystem:reconstruct_path(came_from, current_key)
    local path = {}
    local key = current_key

    while key do
        local x = key % Constants.MAP_CELL_W
        local y = math.floor(key / Constants.MAP_CELL_W)
        local cell = self.grid:get_cell(x, y)
        table.insert(path, 1, cell)  -- Insert at beginning
        key = came_from[key]
    end

    -- Remove starting cell (we're already there)
    if #path > 1 then
        table.remove(path, 1)
    end

    return path
end

-- Find nearest passable cell
function MovementSystem:find_nearest_passable(x, y, locomotor)
    -- Search in expanding squares
    for radius = 1, 10 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local cell = self.grid:get_cell(x + dx, y + dy)
                    if cell and cell:is_passable(locomotor) then
                        return cell
                    end
                end
            end
        end
    end
    return nil
end

-- Stop unit movement
function MovementSystem:stop(entity)
    if not entity:has("mobile") then return end

    local mobile = entity:get("mobile")
    mobile.is_moving = false
    mobile.path = {}
    mobile.path_index = 0
end

-- Check if unit is moving
function MovementSystem:is_moving(entity)
    if not entity:has("mobile") then return false end
    return entity:get("mobile").is_moving
end

return MovementSystem
