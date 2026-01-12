--[[
    Cell - Single map cell data structure
    Reference: CELL.H
]]

local Constants = require("src.core.constants")

-- LuaJIT bit operations (compatible with Love2D)
local bit = bit or bit32 or require("bit")

local Cell = {}
Cell.__index = Cell

-- Cell flags for occupancy (from original C&C CELL.H)
Cell.FLAG = {
    CENTER = 1,     -- Center position occupied
    NW = 2,         -- Northwest position (infantry)
    NE = 4,         -- Northeast position (infantry)
    SW = 8,         -- Southwest position (infantry)
    SE = 16,        -- Southeast position (infantry)
    VEHICLE = 32,   -- Vehicle present
    MONOLITH = 64,  -- Immovable blockage
    BUILDING = 128, -- Building present
    WALL = 256      -- Wall segment present (extends base for adjacency)
}

-- Create a new cell
function Cell.new(x, y)
    local self = setmetatable({}, Cell)

    -- Position
    self.x = x or 0
    self.y = y or 0

    -- Visibility flags (per house)
    self.is_mapped = {}     -- Has been explored
    self.is_visible = {}    -- Currently visible

    -- Terrain
    self.template_type = 0  -- Base terrain template
    self.template_icon = 0  -- Icon within template

    -- Overlay (walls, tiberium, etc.)
    self.overlay = -1       -- Overlay type (-1 = none)
    self.overlay_data = 0   -- Overlay-specific data (e.g., wall connections)

    -- Smudge (craters, scorch marks)
    self.smudge = -1        -- Smudge type (-1 = none)
    self.smudge_data = 0    -- Smudge variant

    -- Ownership
    self.owner = -1         -- House that owns this cell

    -- Infantry type in cell
    self.infantry_type = -1

    -- Occupancy flags
    self.flags = 0

    -- References to occupying objects
    self.occupier = nil     -- Main occupier entity ID
    self.overlappers = {}   -- Entities overlapping this cell

    -- Trigger reference
    self.trigger = nil

    -- Waypoint
    self.waypoint = nil

    -- Flag for capture-the-flag mode
    self.has_flag = false
    self.flag_owner = -1

    return self
end

-- Check if cell is passable for a locomotor type
function Cell:is_passable(locomotor)
    -- Buildings block everything
    if self:has_flag_set(Cell.FLAG.BUILDING) then
        return false
    end

    -- Monoliths block everything
    if self:has_flag_set(Cell.FLAG.MONOLITH) then
        return false
    end

    -- Vehicles block other ground units
    if locomotor ~= "fly" and self:has_flag_set(Cell.FLAG.VEHICLE) then
        return false
    end

    return true
end

-- Check if infantry can occupy a sub-position
function Cell:is_spot_free(spot_flag)
    return bit.band(self.flags, spot_flag) == 0
end

-- Get a free infantry spot
function Cell:get_free_spot()
    local spots = {Cell.FLAG.CENTER, Cell.FLAG.NW, Cell.FLAG.NE, Cell.FLAG.SW, Cell.FLAG.SE}
    for _, spot in ipairs(spots) do
        if self:is_spot_free(spot) then
            return spot
        end
    end
    return nil
end

-- Set a flag
function Cell:set_flag(flag)
    self.flags = bit.bor(self.flags, flag)
end

-- Clear a flag
function Cell:clear_flag(flag)
    self.flags = bit.band(self.flags, bit.bnot(flag))
end

-- Check if flag is set
function Cell:has_flag_set(flag)
    return bit.band(self.flags, flag) ~= 0
end

-- Set visibility for a house
function Cell:set_mapped(house, mapped)
    self.is_mapped[house] = mapped
end

function Cell:set_visible(house, visible)
    self.is_visible[house] = visible
    if visible then
        self.is_mapped[house] = true
    end
end

-- Check visibility
function Cell:is_mapped_by(house)
    return self.is_mapped[house] == true
end

function Cell:is_visible_to(house)
    return self.is_visible[house] == true
end

-- Check if cell has tiberium
function Cell:has_tiberium()
    -- Tiberium overlay types are 6-17 (OVERLAY_TIBERIUM1 through OVERLAY_TIBERIUM12)
    return self.overlay >= 6 and self.overlay <= 17
end

-- Get tiberium value
function Cell:get_tiberium_value()
    if not self:has_tiberium() then
        return 0
    end
    -- Higher overlay numbers = more tiberium
    return (self.overlay - 5) * 10
end

-- Reduce tiberium (harvesting)
function Cell:harvest_tiberium(amount)
    if not self:has_tiberium() then
        return 0
    end

    local harvested = math.min(amount, self:get_tiberium_value())

    -- Reduce overlay level
    local new_level = self:get_tiberium_value() - harvested
    if new_level <= 0 then
        self.overlay = -1
        self.overlay_data = 0
    else
        self.overlay = 5 + math.ceil(new_level / 10)
    end

    return harvested
end

-- Add overlapper
function Cell:add_overlapper(entity_id)
    for _, id in ipairs(self.overlappers) do
        if id == entity_id then
            return -- Already added
        end
    end
    table.insert(self.overlappers, entity_id)
end

-- Remove overlapper
function Cell:remove_overlapper(entity_id)
    for i, id in ipairs(self.overlappers) do
        if id == entity_id then
            table.remove(self.overlappers, i)
            return
        end
    end
end

-- Get cell number (for serialization)
function Cell:get_cell_number()
    return self.y * Constants.MAP_CELL_W + self.x
end

-- Convert cell to world coordinates (leptons at cell center)
function Cell:to_leptons()
    return self.x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2,
           self.y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
end

-- Convert cell to pixel coordinates
function Cell:to_pixels()
    return self.x * Constants.CELL_PIXEL_W,
           self.y * Constants.CELL_PIXEL_H
end

-- Serialize cell state
function Cell:serialize()
    return {
        x = self.x,
        y = self.y,
        template_type = self.template_type,
        template_icon = self.template_icon,
        overlay = self.overlay,
        overlay_data = self.overlay_data,
        smudge = self.smudge,
        smudge_data = self.smudge_data,
        owner = self.owner,
        flags = self.flags,
        is_mapped = self.is_mapped,
        waypoint = self.waypoint
    }
end

-- Deserialize cell state
function Cell:deserialize(data)
    self.template_type = data.template_type
    self.template_icon = data.template_icon
    self.overlay = data.overlay
    self.overlay_data = data.overlay_data
    self.smudge = data.smudge or -1
    self.smudge_data = data.smudge_data or 0
    self.owner = data.owner
    self.flags = data.flags or 0
    self.is_mapped = data.is_mapped or {}
    self.waypoint = data.waypoint
end

return Cell
