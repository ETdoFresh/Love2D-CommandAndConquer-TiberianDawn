--[[
    Fog of War System - Visibility and shroud management
    Handles fog of war and permanent shroud like original C&C
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")
local System = require("src.ecs.system")

local FogSystem = setmetatable({}, {__index = System})
FogSystem.__index = FogSystem

-- Visibility states
FogSystem.VISIBILITY = {
    UNSEEN = 0,      -- Never seen (black)
    FOGGED = 1,      -- Previously seen (dark)
    VISIBLE = 2      -- Currently visible
}

function FogSystem.new(grid)
    local self = setmetatable(System.new(), FogSystem)

    self.name = "FogSystem"
    self.grid = grid

    -- Visibility per player per cell
    -- visibility[house][y][x] = state
    self.visibility = {}

    -- Sight range cache per entity
    self.sight_ranges = {}

    -- Default sight range
    self.default_sight_range = 5

    -- Fog enabled
    self.fog_enabled = true
    self.shroud_enabled = true

    -- Current player house (for rendering)
    self.player_house = Constants.HOUSE.GOOD

    -- Initialize visibility arrays
    self:init_visibility()

    -- Register events
    self:register_events()

    return self
end

-- Initialize visibility arrays for all houses
function FogSystem:init_visibility()
    local width = self.grid and self.grid.width or 64
    local height = self.grid and self.grid.height or 64

    for _, house in pairs(Constants.HOUSE) do
        self.visibility[house] = {}
        for y = 0, height - 1 do
            self.visibility[house][y] = {}
            for x = 0, width - 1 do
                self.visibility[house][y][x] = FogSystem.VISIBILITY.UNSEEN
            end
        end
    end
end

-- Register event listeners
function FogSystem:register_events()
    Events.on("REVEAL_MAP", function(house)
        self:reveal_all(house)
    end)

    Events.on("REVEAL_ZONE", function(house, cell_x, cell_y, radius)
        self:reveal_area(house, cell_x, cell_y, radius or 5)
    end)
end

-- Update fog of war
function FogSystem:update(dt)
    if not self.fog_enabled then return end

    -- Reset current visibility to fogged (keep shroud revealed)
    for house, house_vis in pairs(self.visibility) do
        for y, row in pairs(house_vis) do
            for x, state in pairs(row) do
                if state == FogSystem.VISIBILITY.VISIBLE then
                    house_vis[y][x] = FogSystem.VISIBILITY.FOGGED
                end
            end
        end
    end

    -- Update visibility based on units
    local entities = self.world:get_all_entities()

    for _, entity in ipairs(entities) do
        local owner = entity:get("owner")
        local transform = entity:get("transform")

        if owner and transform then
            local house = owner.house
            local cell_x = math.floor(transform.x / Constants.LEPTON_PER_CELL)
            local cell_y = math.floor(transform.y / Constants.LEPTON_PER_CELL)

            local sight = self:get_sight_range(entity)
            self:reveal_area(house, cell_x, cell_y, sight)
        end
    end
end

-- Get sight range for an entity
function FogSystem:get_sight_range(entity)
    -- Check cached value
    if self.sight_ranges[entity.id] then
        return self.sight_ranges[entity.id]
    end

    local sight = self.default_sight_range

    -- Check for sight component or data
    local vehicle = entity:get("vehicle")
    local building = entity:get("building")
    local infantry = entity:get("infantry")

    if vehicle then
        -- Vehicles typically have range 5-8
        sight = 5
    elseif building then
        -- Buildings have larger sight
        sight = 6
        -- Radar extends sight
        if building.building_type == "HQ" or building.building_type == "EYE" then
            sight = 10
        end
    elseif infantry then
        -- Infantry typically have range 3-5
        sight = 4
    end

    self.sight_ranges[entity.id] = sight
    return sight
end

-- Reveal area around a point
function FogSystem:reveal_area(house, center_x, center_y, radius)
    local house_vis = self.visibility[house]
    if not house_vis then return end

    local width = self.grid and self.grid.width or 64
    local height = self.grid and self.grid.height or 64

    -- Circular reveal
    local radius_sq = radius * radius

    for dy = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dy * dy <= radius_sq then
                local x = center_x + dx
                local y = center_y + dy

                if x >= 0 and x < width and y >= 0 and y < height then
                    if not house_vis[y] then
                        house_vis[y] = {}
                    end
                    house_vis[y][x] = FogSystem.VISIBILITY.VISIBLE
                end
            end
        end
    end
end

-- Reveal entire map for a house
function FogSystem:reveal_all(house)
    local house_vis = self.visibility[house]
    if not house_vis then return end

    local width = self.grid and self.grid.width or 64
    local height = self.grid and self.grid.height or 64

    for y = 0, height - 1 do
        if not house_vis[y] then
            house_vis[y] = {}
        end
        for x = 0, width - 1 do
            house_vis[y][x] = FogSystem.VISIBILITY.VISIBLE
        end
    end
end

-- Check if a cell is visible to a house
function FogSystem:is_visible(house, cell_x, cell_y)
    if not self.fog_enabled then
        return true
    end

    local house_vis = self.visibility[house]
    if not house_vis or not house_vis[cell_y] then
        return false
    end

    return house_vis[cell_y][cell_x] == FogSystem.VISIBILITY.VISIBLE
end

-- Check if a cell has been explored
function FogSystem:is_explored(house, cell_x, cell_y)
    if not self.shroud_enabled then
        return true
    end

    local house_vis = self.visibility[house]
    if not house_vis or not house_vis[cell_y] then
        return false
    end

    return house_vis[cell_y][cell_x] >= FogSystem.VISIBILITY.FOGGED
end

-- Get visibility state
function FogSystem:get_visibility(house, cell_x, cell_y)
    local house_vis = self.visibility[house]
    if not house_vis or not house_vis[cell_y] then
        return FogSystem.VISIBILITY.UNSEEN
    end

    return house_vis[cell_y][cell_x] or FogSystem.VISIBILITY.UNSEEN
end

-- Check if entity is visible to current player
function FogSystem:is_entity_visible(entity)
    local transform = entity:get("transform")
    if not transform then return false end

    local cell_x = math.floor(transform.x / Constants.LEPTON_PER_CELL)
    local cell_y = math.floor(transform.y / Constants.LEPTON_PER_CELL)

    return self:is_visible(self.player_house, cell_x, cell_y)
end

-- Draw fog overlay
-- Note: This is called explicitly from game.lua with render_system, NOT from world:draw()
function FogSystem:draw(render_system)
    if not self.fog_enabled and not self.shroud_enabled then
        return
    end

    -- Guard: fog_system:draw() is called with render_system, not entities
    -- If called from world:draw() with entities table, silently return
    if type(render_system) == "table" and render_system[1] then
        return  -- Called with entities array, skip
    end
    if not render_system or not render_system.camera_x then
        return  -- Invalid render_system, skip
    end

    love.graphics.push()
    love.graphics.scale(render_system.scale, render_system.scale)
    love.graphics.translate(-render_system.camera_x, -render_system.camera_y)

    local start_x = render_system.view_x
    local start_y = render_system.view_y
    local end_x = start_x + render_system.view_width
    local end_y = start_y + render_system.view_height

    local house_vis = self.visibility[self.player_house]

    -- Debug: Track how many cells we're drawing fog for
    self._debug_unseen_count = 0
    self._debug_fogged_count = 0

    for y = start_y, end_y do
        if house_vis[y] then
            for x = start_x, end_x do
                local state = house_vis[y][x] or FogSystem.VISIBILITY.UNSEEN
                local px = x * Constants.CELL_PIXEL_W
                local py = y * Constants.CELL_PIXEL_H

                if state == FogSystem.VISIBILITY.UNSEEN then
                    -- Black shroud - completely unexplored areas
                    if self.shroud_enabled then
                        self._debug_unseen_count = self._debug_unseen_count + 1

                        -- Check neighboring cells to create edge transitions
                        local edge_mask = self:get_shroud_edge_mask(house_vis, x, y)

                        if edge_mask == 0 then
                            -- Interior shroud - solid black
                            love.graphics.setColor(0, 0, 0, 1)
                            love.graphics.rectangle("fill", px, py,
                                Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
                        else
                            -- Edge shroud - draw with fade edges
                            love.graphics.setColor(0, 0, 0, 1)
                            love.graphics.rectangle("fill", px, py,
                                Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)

                            -- Draw edge fade effect (triangles cut from corners)
                            love.graphics.setColor(0, 0, 0, 0.7)
                            local hw, hh = Constants.CELL_PIXEL_W / 2, Constants.CELL_PIXEL_H / 2

                            -- bit.band would be cleaner but we use simple checks
                            if edge_mask >= 8 then -- North neighbor visible
                                love.graphics.polygon("fill",
                                    px, py,
                                    px + Constants.CELL_PIXEL_W, py,
                                    px + hw, py + hh / 2
                                )
                            end
                        end
                    end
                elseif state == FogSystem.VISIBILITY.FOGGED then
                    -- Semi-transparent fog - previously seen but no current vision
                    -- Slightly blue tint to distinguish from shroud (like original C&C)
                    if self.fog_enabled then
                        self._debug_fogged_count = self._debug_fogged_count + 1
                        -- Draw darker overlay first
                        love.graphics.setColor(0, 0, 0.05, 0.55)
                        love.graphics.rectangle("fill", px, py,
                            Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
                        -- Add subtle edge darkening for depth
                        love.graphics.setColor(0, 0, 0, 0.15)
                        love.graphics.rectangle("line", px, py,
                            Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
                    end
                end
                -- VISIBLE = no overlay
            end
        else
            -- Row not initialized = unseen
            if self.shroud_enabled then
                for x = start_x, end_x do
                    local px = x * Constants.CELL_PIXEL_W
                    local py = y * Constants.CELL_PIXEL_H
                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.rectangle("fill", px, py,
                        Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Enable/disable fog
function FogSystem:set_fog_enabled(enabled)
    self.fog_enabled = enabled
end

-- Enable/disable shroud
function FogSystem:set_shroud_enabled(enabled)
    self.shroud_enabled = enabled
end

-- Set current player
function FogSystem:set_player_house(house)
    self.player_house = house
end

-- Get edge mask for shroud cell (which neighbors are visible)
-- Returns bitmask: 1=S, 2=E, 4=W, 8=N, 16=SE, 32=SW, 64=NE, 128=NW
function FogSystem:get_shroud_edge_mask(house_vis, x, y)
    local mask = 0

    -- Check cardinal directions
    local n = house_vis[y - 1] and house_vis[y - 1][x] or FogSystem.VISIBILITY.UNSEEN
    local s = house_vis[y + 1] and house_vis[y + 1][x] or FogSystem.VISIBILITY.UNSEEN
    local e = house_vis[y] and house_vis[y][x + 1] or FogSystem.VISIBILITY.UNSEEN
    local w = house_vis[y] and house_vis[y][x - 1] or FogSystem.VISIBILITY.UNSEEN

    if n ~= FogSystem.VISIBILITY.UNSEEN then mask = mask + 8 end
    if s ~= FogSystem.VISIBILITY.UNSEEN then mask = mask + 1 end
    if e ~= FogSystem.VISIBILITY.UNSEEN then mask = mask + 2 end
    if w ~= FogSystem.VISIBILITY.UNSEEN then mask = mask + 4 end

    return mask
end

-- Reset for new game
function FogSystem:reset()
    self:init_visibility()
    self.sight_ranges = {}
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of fog system state.
]]
function FogSystem:Debug_Dump()
    print("FogSystem:")
    print(string.format("  Enabled: fog=%s shroud=%s",
        tostring(self.fog_enabled), tostring(self.shroud_enabled)))
    print(string.format("  Player house: %d", self.player_house))
    print(string.format("  Default sight range: %d cells", self.default_sight_range))
    print(string.format("  Sight range cache entries: %d", self:count_sight_ranges()))

    -- Count visibility per house
    for house, house_vis in pairs(self.visibility) do
        local unseen, fogged, visible = 0, 0, 0
        for y, row in pairs(house_vis) do
            for x, state in pairs(row) do
                if state == FogSystem.VISIBILITY.UNSEEN then
                    unseen = unseen + 1
                elseif state == FogSystem.VISIBILITY.FOGGED then
                    fogged = fogged + 1
                elseif state == FogSystem.VISIBILITY.VISIBLE then
                    visible = visible + 1
                end
            end
        end
        print(string.format("  House %d visibility: unseen=%d fogged=%d visible=%d",
            house, unseen, fogged, visible))
    end
end

-- Helper: Count sight range cache entries
function FogSystem:count_sight_ranges()
    local count = 0
    for _ in pairs(self.sight_ranges) do count = count + 1 end
    return count
end

return FogSystem
