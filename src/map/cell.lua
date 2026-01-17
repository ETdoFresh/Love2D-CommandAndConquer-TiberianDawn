--[[
    Cell - Single map cell data structure
    Reference: CELL.H
]]

local Constants = require("src.core.constants")
local Target = require("src.core.target")

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

    -- References to occupying objects (stored as TARGET values for heap resolution)
    self.occupier = Target.TARGET_NONE  -- Main occupier TARGET (building/vehicle)
    self.overlappers = {}               -- TARGET values of objects overlapping this cell

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
function Cell:is_passable(locomotor, terrain_type)
    -- Aircraft can fly over anything
    if locomotor == "fly" then
        return true
    end

    -- Buildings block everything on ground
    if self:has_flag_set(Cell.FLAG.BUILDING) then
        return false
    end

    -- Monoliths block everything
    if self:has_flag_set(Cell.FLAG.MONOLITH) then
        return false
    end

    -- Vehicles block other ground units
    if self:has_flag_set(Cell.FLAG.VEHICLE) then
        return false
    end

    -- Check if this cell has a passable bridge over impassable terrain
    -- Bridges allow ground units to cross water/river/cliff
    if self:has_bridge() and self:bridge_is_passable() then
        return true
    end

    -- Check terrain type (if provided)
    -- Water, river, cliff are impassable without a bridge
    if terrain_type then
        local Terrain = require("src.map.terrain")
        if terrain_type == Terrain.TYPE.WATER or
           terrain_type == Terrain.TYPE.RIVER or
           terrain_type == Terrain.TYPE.CLIFF or
           terrain_type == Terrain.TYPE.ROCK then
            return false
        end
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

-- Check if cell has a wall
function Cell:has_wall()
    -- Wall overlay types are 1-5 (sandbag, chain link, concrete, barbed wire, wood)
    return self.overlay >= 1 and self.overlay <= 5
end

-- Get wall health (stored in overlay_data for walls)
function Cell:get_wall_health()
    if not self:has_wall() then
        return 0
    end
    return self.overlay_data or 0
end

-- Set wall health
function Cell:set_wall_health(health)
    if self:has_wall() then
        self.overlay_data = math.max(0, health)
        if self.overlay_data <= 0 then
            -- Wall destroyed
            self:destroy_wall()
        end
    end
end

-- Damage wall and return if destroyed
function Cell:damage_wall(damage)
    if not self:has_wall() then
        return false
    end

    local health = self:get_wall_health()
    health = health - damage
    self.overlay_data = math.max(0, health)

    if health <= 0 then
        self:destroy_wall()
        return true  -- Destroyed
    end
    return false
end

-- Destroy wall
function Cell:destroy_wall()
    local was_wall = self:has_wall()
    self.overlay = -1
    self.overlay_data = 0
    self:clear_flag(Cell.FLAG.WALL)
    return was_wall
end

-- Place wall on cell
function Cell:place_wall(wall_type, health)
    self.overlay = wall_type
    self.overlay_data = health or 100
    self.wall_frame = 0  -- Will be calculated by update_wall_connections
    self:set_flag(Cell.FLAG.WALL)
end

-- Wall neighbor bitmask (from original C&C - walls connect to adjacent walls)
-- Bit 0 (1) = North neighbor
-- Bit 1 (2) = East neighbor
-- Bit 2 (4) = South neighbor
-- Bit 3 (8) = West neighbor
-- Frame index = bitmask value (0-15)
Cell.WALL_NEIGHBOR = {
    NORTH = 1,
    EAST = 2,
    SOUTH = 4,
    WEST = 8
}

-- Get wall sprite frame based on neighbor connections
-- Returns frame index 0-15 based on which neighbors have walls
function Cell:get_wall_frame()
    return self.wall_frame or 0
end

-- Set wall frame directly
function Cell:set_wall_frame(frame)
    self.wall_frame = frame
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

-- Damage tiberium (explosions destroy tiberium)
function Cell:damage_tiberium(damage)
    if not self:has_tiberium() then
        return 0
    end

    local value_before = self:get_tiberium_value()
    local value_after = math.max(0, value_before - damage)

    if value_after <= 0 then
        self.overlay = -1
        self.overlay_data = 0
    else
        -- Reduce overlay level based on remaining value
        self.overlay = 5 + math.ceil(value_after / 10)
    end

    return value_before - value_after
end

-- Check if cell has a smudge (crater, scorch mark)
function Cell:has_smudge()
    return self.smudge >= 0
end

-- Smudge types (from original C&C SMUDGE.H)
-- 0-5: Craters (SC1-SC6)
-- 6-11: Bibs/scorches (BIB1-BIB3, etc)
Cell.SMUDGE = {
    CRATER1 = 0,
    CRATER2 = 1,
    CRATER3 = 2,
    CRATER4 = 3,
    CRATER5 = 4,
    CRATER6 = 5,
    SCORCH1 = 6,
    SCORCH2 = 7,
    SCORCH3 = 8,
    SCORCH4 = 9,
    SCORCH5 = 10,
    SCORCH6 = 11
}

-- Add a crater at this cell (from explosions)
function Cell:add_crater(size)
    -- Don't add craters on buildings, tiberium, or walls
    if self:has_flag_set(Cell.FLAG.BUILDING) or self:has_tiberium() or self:has_wall() then
        return false
    end

    -- Size determines crater type (0-5)
    size = size or 1
    local crater_type = math.min(5, math.max(0, size - 1))

    -- If already has a smudge, make it bigger (up to max)
    if self:has_smudge() and self.smudge <= 5 then
        -- Existing crater - upgrade it
        self.smudge = math.min(5, self.smudge + 1)
        self.smudge_data = (self.smudge_data or 0) + 1
    else
        -- New crater
        self.smudge = crater_type
        self.smudge_data = 1
    end

    return true
end

-- Add a scorch mark at this cell (from fire/laser)
function Cell:add_scorch(size)
    -- Don't add scorches on buildings or walls
    if self:has_flag_set(Cell.FLAG.BUILDING) or self:has_wall() then
        return false
    end

    -- Size determines scorch type (6-11)
    size = size or 1
    local scorch_type = 6 + math.min(5, math.max(0, size - 1))

    -- Fire can burn tiberium
    if self:has_tiberium() then
        self:damage_tiberium(20)
    end

    -- If already has a scorch, make it bigger
    if self:has_smudge() and self.smudge >= 6 then
        self.smudge = math.min(11, self.smudge + 1)
    else
        self.smudge = scorch_type
    end
    self.smudge_data = (self.smudge_data or 0) + 1

    return true
end

-- Clear smudge from cell
function Cell:clear_smudge()
    self.smudge = -1
    self.smudge_data = 0
end

-- Grow tiberium (for spread mechanics)
function Cell:grow_tiberium(amount)
    amount = amount or 1

    if self:has_tiberium() then
        -- Already has tiberium - increase level up to max (17)
        local current_value = self:get_tiberium_value()
        local new_value = math.min(120, current_value + amount * 10)  -- Max 120 value (overlay 17)
        self.overlay = 5 + math.ceil(new_value / 10)
        return true
    else
        -- No tiberium yet - check if this cell can have tiberium
        -- Don't grow on buildings, walls, or water
        if self:has_flag_set(Cell.FLAG.BUILDING) or self:has_wall() then
            return false
        end

        -- Start with minimum tiberium (overlay 6)
        self.overlay = 6
        self.overlay_data = 0
        return true
    end
end

-- Check if cell can receive tiberium spread
function Cell:can_receive_tiberium()
    -- Can't spread to buildings, walls, water, or cells already at max tiberium
    if self:has_flag_set(Cell.FLAG.BUILDING) or self:has_wall() then
        return false
    end

    -- Check if already at max tiberium
    if self:has_tiberium() and self.overlay >= 17 then
        return false
    end

    return true
end

--============================================================================
-- Object Retrieval Functions
-- Reference: CELL.H Cell_Occupier(), Cell_Building(), Cell_Unit(), etc.
-- These functions resolve TARGET values to actual objects via the Globals heap
--============================================================================

-- Lazy require to avoid circular dependency (Globals requires game object classes)
local _Globals = nil
local function get_Globals()
    if not _Globals then
        _Globals = require("src.heap.globals")
    end
    return _Globals
end

--[[
    Get the main occupying object in this cell.
    Port of Cell_Occupier() from CELL.CPP

    @return ObjectClass or nil
]]
function Cell:Cell_Occupier()
    if self.occupier == Target.TARGET_NONE or self.occupier == 0 then
        return nil
    end
    return get_Globals().Target_To_Object(self.occupier)
end

--[[
    Get the building in this cell.
    Port of Cell_Building() from CELL.CPP

    @return BuildingClass or nil
]]
function Cell:Cell_Building()
    -- Check occupier first
    local occupier = self:Cell_Occupier()
    if occupier and occupier:get_rtti() == Target.RTTI.BUILDING then
        return occupier
    end

    -- Check overlappers
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj and obj:get_rtti() == Target.RTTI.BUILDING then
                return obj
            end
        end
    end

    return nil
end

--[[
    Get the unit (vehicle) in this cell.
    Port of Cell_Unit() from CELL.CPP

    @return UnitClass or nil
]]
function Cell:Cell_Unit()
    -- Check occupier first
    local occupier = self:Cell_Occupier()
    if occupier and occupier:get_rtti() == Target.RTTI.UNIT then
        return occupier
    end

    -- Check overlappers
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj and obj:get_rtti() == Target.RTTI.UNIT then
                return obj
            end
        end
    end

    return nil
end

--[[
    Get infantry in this cell (optionally at specific subcell spot).
    Port of Cell_Infantry() from CELL.CPP

    @param spot - Optional FLAG.CENTER/NW/NE/SW/SE to get infantry at specific spot
    @return InfantryClass or nil
]]
function Cell:Cell_Infantry(spot)
    -- If spot specified, only check infantry at that spot
    -- (In original C&C, infantry are indexed by subcell position)

    -- Check overlappers for infantry
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj and obj:get_rtti() == Target.RTTI.INFANTRY then
                -- If specific spot requested, check if infantry is at that spot
                if spot then
                    -- Infantry have an Occupy field indicating their subcell
                    if obj.Occupy and obj.Occupy == spot then
                        return obj
                    end
                else
                    -- Return first infantry found
                    return obj
                end
            end
        end
    end

    return nil
end

--[[
    Get aircraft in this cell.
    Port of Cell_Aircraft() from original (though rarely used - aircraft are usually airborne)

    @return AircraftClass or nil
]]
function Cell:Cell_Aircraft()
    -- Check overlappers for aircraft
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj and obj:get_rtti() == Target.RTTI.AIRCRAFT then
                return obj
            end
        end
    end

    return nil
end

--[[
    Get first TechnoClass (combat-capable object) in this cell.
    Port of Cell_Techno() from CELL.CPP

    @return TechnoClass or nil (Infantry, Unit, Building, or Aircraft)
]]
function Cell:Cell_Techno()
    -- Check occupier first
    local occupier = self:Cell_Occupier()
    if occupier then
        local rtti = occupier:get_rtti()
        if rtti == Target.RTTI.BUILDING or rtti == Target.RTTI.UNIT or
           rtti == Target.RTTI.INFANTRY or rtti == Target.RTTI.AIRCRAFT then
            return occupier
        end
    end

    -- Check overlappers for any techno
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj then
                local rtti = obj:get_rtti()
                if rtti == Target.RTTI.BUILDING or rtti == Target.RTTI.UNIT or
                   rtti == Target.RTTI.INFANTRY or rtti == Target.RTTI.AIRCRAFT then
                    return obj
                end
            end
        end
    end

    return nil
end

--[[
    Find an object of specific RTTI type in this cell.
    Port of Cell_Find_Object() from CELL.CPP

    @param rtti - RTTI type to search for
    @return ObjectClass or nil
]]
function Cell:Cell_Find_Object(rtti)
    -- Check occupier first
    local occupier = self:Cell_Occupier()
    if occupier and occupier:get_rtti() == rtti then
        return occupier
    end

    -- Check overlappers
    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            local obj = get_Globals().Target_To_Object(target)
            if obj and obj:get_rtti() == rtti then
                return obj
            end
        end
    end

    return nil
end

--============================================================================
-- Occupy/Overlap Management
-- Reference: CELL.H Occupy_Down(), Occupy_Up(), Overlap_Down(), Overlap_Up()
--============================================================================

--[[
    Mark cell as occupied by an object.
    Port of Occupy_Down() from CELL.CPP

    Sets the appropriate flag based on object type and stores the object TARGET.

    @param object - ObjectClass to occupy this cell
]]
function Cell:Occupy_Down(object)
    if not object then return end

    local target = object:As_Target()
    local rtti = object:get_rtti()

    -- Set appropriate flag based on object type
    if rtti == Target.RTTI.BUILDING then
        self:set_flag(Cell.FLAG.BUILDING)
        self.occupier = target
        self.owner = object.House or -1

    elseif rtti == Target.RTTI.UNIT then
        self:set_flag(Cell.FLAG.VEHICLE)
        self.occupier = target

    elseif rtti == Target.RTTI.INFANTRY then
        -- Infantry occupy a subcell position
        local spot = object.Occupy or Cell.FLAG.CENTER
        self:set_flag(spot)
        -- Infantry are added as overlappers, not main occupier
        self:add_overlapper(target)

    elseif rtti == Target.RTTI.AIRCRAFT then
        -- Aircraft on ground (landed)
        self:add_overlapper(target)

    else
        -- Other object types go in overlappers
        self:add_overlapper(target)
    end
end

--[[
    Clear cell occupancy for an object.
    Port of Occupy_Up() from CELL.CPP

    @param object - ObjectClass leaving this cell
]]
function Cell:Occupy_Up(object)
    if not object then return end

    local target = object:As_Target()
    local rtti = object:get_rtti()

    -- Clear appropriate flag based on object type
    if rtti == Target.RTTI.BUILDING then
        self:clear_flag(Cell.FLAG.BUILDING)
        if self.occupier == target then
            self.occupier = Target.TARGET_NONE
        end

    elseif rtti == Target.RTTI.UNIT then
        self:clear_flag(Cell.FLAG.VEHICLE)
        if self.occupier == target then
            self.occupier = Target.TARGET_NONE
        end

    elseif rtti == Target.RTTI.INFANTRY then
        -- Infantry clear their subcell position
        local spot = object.Occupy or Cell.FLAG.CENTER
        self:clear_flag(spot)
        self:remove_overlapper(target)

    elseif rtti == Target.RTTI.AIRCRAFT then
        self:remove_overlapper(target)

    else
        self:remove_overlapper(target)
    end
end

--[[
    Add an object to the overlap list (for rendering/collision, not blocking).
    Port of Overlap_Down() from CELL.CPP

    Objects that render across cell boundaries use overlap.

    @param object - ObjectClass overlapping this cell
]]
function Cell:Overlap_Down(object)
    if not object then return end
    local target = object:As_Target()
    self:add_overlapper(target)
end

--[[
    Remove an object from the overlap list.
    Port of Overlap_Up() from CELL.CPP

    @param object - ObjectClass no longer overlapping this cell
]]
function Cell:Overlap_Up(object)
    if not object then return end
    local target = object:As_Target()
    self:remove_overlapper(target)
end

--============================================================================
-- Internal Overlapper Management (uses TARGET values)
--============================================================================

-- Add overlapper by TARGET value
function Cell:add_overlapper(target)
    if target == Target.TARGET_NONE or target == 0 then
        return
    end
    for _, t in ipairs(self.overlappers) do
        if t == target then
            return -- Already added
        end
    end
    table.insert(self.overlappers, target)
end

-- Remove overlapper by TARGET value
function Cell:remove_overlapper(target)
    for i, t in ipairs(self.overlappers) do
        if t == target then
            table.remove(self.overlappers, i)
            return
        end
    end
end

--[[
    Get all objects overlapping this cell.
    Returns iterator for all overlapping objects.

    @return iterator function
]]
function Cell:Iterate_Overlappers()
    local Globals = get_Globals()
    local i = 0
    local overlappers = self.overlappers

    return function()
        while true do
            i = i + 1
            if i > #overlappers then
                return nil
            end
            local target = overlappers[i]
            if target and target ~= Target.TARGET_NONE and target ~= 0 then
                local obj = Globals.Target_To_Object(target)
                if obj then
                    return obj
                end
            end
        end
    end
end

--[[
    Get count of objects in this cell (occupier + overlappers).
]]
function Cell:Object_Count()
    local count = 0

    if self.occupier ~= Target.TARGET_NONE and self.occupier ~= 0 then
        count = count + 1
    end

    for _, target in ipairs(self.overlappers) do
        if target ~= Target.TARGET_NONE and target ~= 0 then
            count = count + 1
        end
    end

    return count
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
-- Note: occupier and overlappers are TARGET values that can be serialized directly
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
        waypoint = self.waypoint,
        -- Object references (stored as TARGET values)
        occupier = self.occupier,
        overlappers = self.overlappers,
        infantry_type = self.infantry_type,
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
    self.is_bridge = data.is_bridge or false
    self.bridge_health = data.bridge_health or 0
    -- Object references (TARGET values are numbers, serializable directly)
    self.occupier = data.occupier or Target.TARGET_NONE
    self.overlappers = data.overlappers or {}
    self.infantry_type = data.infantry_type or -1
end

-- Bridge overlay types (from original C&C)
-- Bridges use overlay indices 18-23
Cell.OVERLAY_BRIDGE = {
    BRIDGE_START = 18,   -- First bridge overlay type
    BRIDGE_END = 23,     -- Last bridge overlay type
    WOOD_H = 18,         -- Wooden bridge horizontal
    WOOD_V = 19,         -- Wooden bridge vertical
    CONCRETE_H = 20,     -- Concrete bridge horizontal
    CONCRETE_V = 21,     -- Concrete bridge vertical
    DAMAGED_H = 22,      -- Damaged bridge horizontal
    DAMAGED_V = 23       -- Damaged bridge vertical
}

-- Bridge health values (from original C&C)
Cell.BRIDGE_HEALTH = {
    WOOD = 200,
    CONCRETE = 400
}

-- Check if cell has a bridge
function Cell:has_bridge()
    return self.is_bridge == true or
           (self.overlay >= Cell.OVERLAY_BRIDGE.BRIDGE_START and
            self.overlay <= Cell.OVERLAY_BRIDGE.BRIDGE_END)
end

-- Place a bridge on this cell
function Cell:place_bridge(bridge_type, health)
    bridge_type = bridge_type or Cell.OVERLAY_BRIDGE.WOOD_H
    self.overlay = bridge_type
    self.is_bridge = true

    -- Determine health based on bridge type
    if bridge_type == Cell.OVERLAY_BRIDGE.CONCRETE_H or
       bridge_type == Cell.OVERLAY_BRIDGE.CONCRETE_V then
        self.bridge_health = health or Cell.BRIDGE_HEALTH.CONCRETE
    else
        self.bridge_health = health or Cell.BRIDGE_HEALTH.WOOD
    end

    return true
end

-- Get bridge health
function Cell:get_bridge_health()
    if not self:has_bridge() then
        return 0
    end
    return self.bridge_health or 0
end

-- Damage bridge - returns true if destroyed
function Cell:damage_bridge(damage)
    if not self:has_bridge() then
        return false
    end

    self.bridge_health = (self.bridge_health or 0) - damage

    -- Check if bridge is damaged (show damaged sprite)
    if self.bridge_health <= 100 and self.bridge_health > 0 then
        -- Switch to damaged bridge sprite
        if self.overlay == Cell.OVERLAY_BRIDGE.WOOD_H or
           self.overlay == Cell.OVERLAY_BRIDGE.CONCRETE_H then
            self.overlay = Cell.OVERLAY_BRIDGE.DAMAGED_H
        elseif self.overlay == Cell.OVERLAY_BRIDGE.WOOD_V or
               self.overlay == Cell.OVERLAY_BRIDGE.CONCRETE_V then
            self.overlay = Cell.OVERLAY_BRIDGE.DAMAGED_V
        end
    end

    -- Check if bridge is destroyed
    if self.bridge_health <= 0 then
        self:destroy_bridge()
        return true
    end

    return false
end

-- Destroy bridge completely
function Cell:destroy_bridge()
    if not self:has_bridge() then
        return false
    end

    self.overlay = -1
    self.is_bridge = false
    self.bridge_health = 0

    -- Add debris/crater at former bridge location
    self:add_crater(2)

    return true
end

-- Check if bridge allows passage (intact or damaged but not destroyed)
function Cell:bridge_is_passable()
    return self:has_bridge() and self.bridge_health > 0
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of cell state.
    Reference: CELL.H Debug_Dump() pattern
]]
function Cell:Debug_Dump()
    print(string.format("CellClass: x=%d y=%d cell#=%d",
        self.x, self.y, self:get_cell_number()))
    print(string.format("  Terrain: template_type=%d template_icon=%d",
        self.template_type, self.template_icon))
    print(string.format("  Overlay: type=%d data=%d",
        self.overlay, self.overlay_data))
    print(string.format("  Smudge: type=%d data=%d",
        self.smudge, self.smudge_data))
    print(string.format("  Flags: 0x%04X owner=%d",
        self.flags, self.owner))

    -- Decode flags
    local flag_names = {}
    if self:has_flag_set(Cell.FLAG.CENTER) then table.insert(flag_names, "CENTER") end
    if self:has_flag_set(Cell.FLAG.NW) then table.insert(flag_names, "NW") end
    if self:has_flag_set(Cell.FLAG.NE) then table.insert(flag_names, "NE") end
    if self:has_flag_set(Cell.FLAG.SW) then table.insert(flag_names, "SW") end
    if self:has_flag_set(Cell.FLAG.SE) then table.insert(flag_names, "SE") end
    if self:has_flag_set(Cell.FLAG.VEHICLE) then table.insert(flag_names, "VEHICLE") end
    if self:has_flag_set(Cell.FLAG.MONOLITH) then table.insert(flag_names, "MONOLITH") end
    if self:has_flag_set(Cell.FLAG.BUILDING) then table.insert(flag_names, "BUILDING") end
    if self:has_flag_set(Cell.FLAG.WALL) then table.insert(flag_names, "WALL") end

    if #flag_names > 0 then
        print(string.format("  FlagNames: %s", table.concat(flag_names, ", ")))
    end

    -- Special states
    if self:has_tiberium() then
        print(string.format("  Tiberium: value=%d", self:get_tiberium_value()))
    end
    if self:has_wall() then
        print(string.format("  Wall: health=%d frame=%d", self:get_wall_health(), self:get_wall_frame()))
    end
    if self:has_bridge() then
        print(string.format("  Bridge: health=%d passable=%s", self:get_bridge_health(), tostring(self:bridge_is_passable())))
    end
    if self:has_smudge() then
        local smudge_name = self.smudge <= 5 and "CRATER" or "SCORCH"
        print(string.format("  Smudge: type=%s%d", smudge_name, (self.smudge % 6) + 1))
    end

    -- Object references (with TARGET resolution)
    if self.occupier and self.occupier ~= Target.TARGET_NONE and self.occupier ~= 0 then
        local rtti = Target.Get_RTTI(self.occupier)
        local id = Target.Get_ID(self.occupier)
        local rtti_name = Target.RTTI_NAME[rtti] or "?"
        local obj = self:Cell_Occupier()
        local obj_str = obj and tostring(obj) or "nil"
        print(string.format("  Occupier: TARGET=0x%08X (RTTI=%s ID=%d) -> %s",
            self.occupier, rtti_name, id, obj_str))
    end
    if #self.overlappers > 0 then
        print(string.format("  Overlappers: %d objects", #self.overlappers))
        for i, target in ipairs(self.overlappers) do
            if target ~= Target.TARGET_NONE and target ~= 0 then
                local rtti = Target.Get_RTTI(target)
                local id = Target.Get_ID(target)
                local rtti_name = Target.RTTI_NAME[rtti] or "?"
                local obj = get_Globals().Target_To_Object(target)
                local obj_str = obj and tostring(obj) or "nil"
                print(string.format("    [%d] TARGET=0x%08X (RTTI=%s ID=%d) -> %s",
                    i, target, rtti_name, id, obj_str))
            end
        end
    end
    if self.trigger then
        print(string.format("  Trigger: %s", tostring(self.trigger)))
    end
    if self.waypoint then
        print(string.format("  Waypoint: %s", tostring(self.waypoint)))
    end
end

return Cell
