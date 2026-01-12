--[[
    Waypoints - Named map locations for scenarios
    Used by triggers, AI teams, and reinforcement spawns
    Reference: Original C&C waypoint system (SCENARIO.CPP)
]]

local Events = require("src.core.events")

local Waypoints = {}
Waypoints.__index = Waypoints

-- Standard waypoint names (from original C&C)
Waypoints.STANDARD = {
    -- Player spawn points
    "PLAYER_SPAWN",      -- Waypoint 0-3: Player starting positions
    "ENEMY_SPAWN",

    -- Reinforcement entry points
    "REINFORCE_NORTH",
    "REINFORCE_SOUTH",
    "REINFORCE_EAST",
    "REINFORCE_WEST",

    -- Special locations
    "HOME",              -- Base center
    "FLARE",             -- Flare/signal location
    "SPECIAL",           -- Special objective

    -- Generic waypoints 0-25 (original uses letters A-Z)
    -- These are accessed by index
}

function Waypoints.new()
    local self = setmetatable({}, Waypoints)

    -- Waypoint storage (name -> {cell_x, cell_y})
    self.waypoints = {}

    -- Indexed waypoints (0-based for compatibility)
    self.indexed = {}

    -- Cell size for pixel conversion
    self.cell_size = 24

    return self
end

-- Add a waypoint by name
function Waypoints:add(name, cell_x, cell_y)
    if not name then return false end

    self.waypoints[name] = {
        cell_x = cell_x,
        cell_y = cell_y,
        x = cell_x * self.cell_size + self.cell_size / 2,
        y = cell_y * self.cell_size + self.cell_size / 2
    }

    Events.emit("WAYPOINT_ADDED", name, cell_x, cell_y)
    return true
end

-- Add a waypoint by index (original C&C style)
function Waypoints:add_indexed(index, cell_x, cell_y)
    self.indexed[index] = {
        cell_x = cell_x,
        cell_y = cell_y,
        x = cell_x * self.cell_size + self.cell_size / 2,
        y = cell_y * self.cell_size + self.cell_size / 2
    }

    -- Also add as letter name (A=0, B=1, etc.)
    if index >= 0 and index <= 25 then
        local letter = string.char(65 + index)  -- 65 = 'A'
        self.waypoints[letter] = self.indexed[index]
    end

    return true
end

-- Get waypoint by name
function Waypoints:get(name)
    return self.waypoints[name]
end

-- Get waypoint by index
function Waypoints:get_by_index(index)
    return self.indexed[index]
end

-- Get waypoint cell coordinates
function Waypoints:get_cell(name)
    local wp = self.waypoints[name]
    if wp then
        return wp.cell_x, wp.cell_y
    end
    return nil, nil
end

-- Get waypoint pixel coordinates (center of cell)
function Waypoints:get_position(name)
    local wp = self.waypoints[name]
    if wp then
        return wp.x, wp.y
    end
    return nil, nil
end

-- Check if waypoint exists
function Waypoints:exists(name)
    return self.waypoints[name] ~= nil
end

-- Remove waypoint
function Waypoints:remove(name)
    if self.waypoints[name] then
        self.waypoints[name] = nil
        Events.emit("WAYPOINT_REMOVED", name)
        return true
    end
    return false
end

-- Clear all waypoints
function Waypoints:clear()
    self.waypoints = {}
    self.indexed = {}
end

-- Get all waypoint names
function Waypoints:get_all_names()
    local names = {}
    for name in pairs(self.waypoints) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Get count of waypoints
function Waypoints:count()
    local count = 0
    for _ in pairs(self.waypoints) do
        count = count + 1
    end
    return count
end

-- Find nearest waypoint to a position
function Waypoints:find_nearest(x, y)
    local nearest_name = nil
    local nearest_dist = math.huge

    for name, wp in pairs(self.waypoints) do
        local dx = x - wp.x
        local dy = y - wp.y
        local dist = dx * dx + dy * dy

        if dist < nearest_dist then
            nearest_dist = dist
            nearest_name = name
        end
    end

    return nearest_name, math.sqrt(nearest_dist)
end

-- Find waypoints within radius
function Waypoints:find_within_radius(x, y, radius)
    local result = {}
    local radius_sq = radius * radius

    for name, wp in pairs(self.waypoints) do
        local dx = x - wp.x
        local dy = y - wp.y
        local dist_sq = dx * dx + dy * dy

        if dist_sq <= radius_sq then
            table.insert(result, {name = name, distance = math.sqrt(dist_sq)})
        end
    end

    -- Sort by distance
    table.sort(result, function(a, b) return a.distance < b.distance end)

    return result
end

-- Load waypoints from scenario data
function Waypoints:load_from_scenario(waypoint_data)
    self:clear()

    if not waypoint_data then return end

    -- Handle array format (index-based)
    if waypoint_data[1] or waypoint_data[0] then
        for i = 0, 99 do
            local wp = waypoint_data[i] or waypoint_data[tostring(i)]
            if wp then
                local cell_x, cell_y

                if type(wp) == "table" then
                    cell_x = wp.cell_x or wp.x or wp[1]
                    cell_y = wp.cell_y or wp.y or wp[2]
                elseif type(wp) == "number" then
                    -- Cell index format (cell = y * map_width + x)
                    local map_width = 64  -- Default map width
                    cell_x = wp % map_width
                    cell_y = math.floor(wp / map_width)
                end

                if cell_x and cell_y then
                    self:add_indexed(i, cell_x, cell_y)
                end
            end
        end
    end

    -- Handle named waypoints
    for name, wp in pairs(waypoint_data) do
        if type(name) == "string" and not tonumber(name) then
            local cell_x, cell_y

            if type(wp) == "table" then
                cell_x = wp.cell_x or wp.x or wp[1]
                cell_y = wp.cell_y or wp.y or wp[2]
            elseif type(wp) == "number" then
                -- Cell index format
                local map_width = 64
                cell_x = wp % map_width
                cell_y = math.floor(wp / map_width)
            end

            if cell_x and cell_y then
                self:add(name, cell_x, cell_y)
            end
        end
    end
end

-- Serialize waypoints for saving
function Waypoints:serialize()
    local data = {
        named = {},
        indexed = {}
    }

    for name, wp in pairs(self.waypoints) do
        -- Skip letter names (they're duplicates of indexed)
        if #name > 1 or not name:match("^[A-Z]$") then
            data.named[name] = {
                cell_x = wp.cell_x,
                cell_y = wp.cell_y
            }
        end
    end

    for index, wp in pairs(self.indexed) do
        data.indexed[index] = {
            cell_x = wp.cell_x,
            cell_y = wp.cell_y
        }
    end

    return data
end

-- Deserialize waypoints
function Waypoints:deserialize(data)
    self:clear()

    if not data then return end

    if data.named then
        for name, wp in pairs(data.named) do
            self:add(name, wp.cell_x, wp.cell_y)
        end
    end

    if data.indexed then
        for index, wp in pairs(data.indexed) do
            self:add_indexed(tonumber(index), wp.cell_x, wp.cell_y)
        end
    end
end

-- Draw waypoints (for editor/debug)
function Waypoints:draw(camera_x, camera_y, scale)
    camera_x = camera_x or 0
    camera_y = camera_y or 0
    scale = scale or 1

    local font = love.graphics.getFont()

    for name, wp in pairs(self.waypoints) do
        local screen_x = (wp.x - camera_x) * scale
        local screen_y = (wp.y - camera_y) * scale

        -- Skip if off screen
        local sw, sh = love.graphics.getDimensions()
        if screen_x < -50 or screen_x > sw + 50 or screen_y < -50 or screen_y > sh + 50 then
            goto continue
        end

        -- Draw marker
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("line", screen_x, screen_y, 8 * scale)

        -- Draw crosshair
        love.graphics.line(screen_x - 12 * scale, screen_y, screen_x + 12 * scale, screen_y)
        love.graphics.line(screen_x, screen_y - 12 * scale, screen_x, screen_y + 12 * scale)

        -- Draw name
        love.graphics.setColor(1, 1, 0, 1)
        local text_w = font:getWidth(name)
        love.graphics.print(name, screen_x - text_w / 2, screen_y + 14 * scale)

        ::continue::
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Get iterator for all waypoints
function Waypoints:iter()
    return pairs(self.waypoints)
end

-- Convert waypoint name to cell index (for compatibility)
function Waypoints:name_to_cell_index(name, map_width)
    map_width = map_width or 64
    local wp = self.waypoints[name]
    if wp then
        return wp.cell_y * map_width + wp.cell_x
    end
    return nil
end

-- Convert cell index to cell coordinates
function Waypoints.cell_index_to_coords(cell_index, map_width)
    map_width = map_width or 64
    local cell_x = cell_index % map_width
    local cell_y = math.floor(cell_index / map_width)
    return cell_x, cell_y
end

return Waypoints
