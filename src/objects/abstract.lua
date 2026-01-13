--[[
    AbstractClass - Base class for all game objects

    Port of ABSTRACT.H/CPP from the original C&C source.

    This is the root of the game object hierarchy. It provides:
    - Coordinate storage (COORDINATE format)
    - Active/allocated state tracking
    - Basic coordinate query methods
    - Distance and direction calculations

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/ABSTRACT.H
]]

local Class = require("src.objects.class")
local Coord = require("src.core.coord")
local Target = require("src.core.target")
local Constants = require("src.core.constants")

-- Create AbstractClass
local AbstractClass = Class.new("AbstractClass")

--============================================================================
-- Constants
--============================================================================

-- House types (from DEFINES.H)
AbstractClass.HOUSE_NONE = Constants.HOUSE.NONE

--============================================================================
-- Constructor
--============================================================================

function AbstractClass:init()
    --[[
        The coordinate location of the unit. For vehicles, this is the center
        point. For buildings, it is the upper left corner.
    ]]
    self.Coord = 0

    --[[
        The actual object ram-space is located in arrays in the data segment.
        This flag is used to indicate which objects are free to be reused
        and which are currently in use by the game.
    ]]
    self.IsActive = false

    --[[
        A flag to indicate that this object was recently created. Since an
        object's allocation is just a matter of whether the IsActive flag is
        set, during a logic frame an object with a given ID could be 'deleted'
        then reallocated as a different type of object in a different location.
        This flag lets us know that this happened.
    ]]
    self.IsRecentlyCreated = false

    -- Heap index for TARGET encoding and object lookup
    self._heap_index = -1
end

--============================================================================
-- Activation
--============================================================================

--[[
    Set the new recently created flag every time the active flag is set.
    (From original: void Set_Active(void) {IsActive = true; IsRecentlyCreated = true;})
]]
function AbstractClass:Set_Active()
    self.IsActive = true
    self.IsRecentlyCreated = true
end

--[[
    Deactivate the object (return to pool)
]]
function AbstractClass:Clear_Active()
    self.IsActive = false
end

--[[
    Clear the recently created flag (called after first AI tick)
]]
function AbstractClass:Clear_Recently_Created()
    self.IsRecentlyCreated = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Returns the owner house of this object.
    Default implementation returns HOUSE_NONE.
    (Override in TechnoClass and BuildingClass)
]]
function AbstractClass:Owner()
    return AbstractClass.HOUSE_NONE
end

--============================================================================
-- Coordinate Query Support Functions
--============================================================================

--[[
    Returns the center coordinate of this object.
    (May be overridden in derived classes for buildings, etc.)
]]
function AbstractClass:Center_Coord()
    return self.Coord
end

--[[
    Returns the coordinate that should be used when targeting this object.
    (May be overridden - e.g., buildings might return a different point)
]]
function AbstractClass:Target_Coord()
    return self.Coord
end

--============================================================================
-- Direction Functions
--============================================================================

--[[
    Calculate direction to another object
    Returns 0-255 (256 directions, 0 = North)
]]
function AbstractClass:Direction_To_Object(object)
    return Coord.Direction256(self:Center_Coord(), object:Target_Coord())
end

--[[
    Calculate direction to a coordinate
]]
function AbstractClass:Direction_To_Coord(coord)
    return Coord.Direction256(self:Center_Coord(), coord)
end

--[[
    Calculate direction to a target (TARGET encoded value)
]]
function AbstractClass:Direction_To_Target(target, heap_lookup)
    local coord = Target.As_Coordinate(target, heap_lookup)
    return Coord.Direction256(self:Center_Coord(), coord)
end

--[[
    Calculate direction to a cell
]]
function AbstractClass:Direction_To_Cell(cell)
    local coord = Coord.Cell_Coord(cell)
    return Coord.Direction256(self:Center_Coord(), coord)
end

--[[
    Calculate 8-way direction to another object
    Returns 0-7 (N, NE, E, SE, S, SW, W, NW)
]]
function AbstractClass:Facing_To_Object(object)
    return Coord.Direction8(self:Center_Coord(), object:Target_Coord())
end

--============================================================================
-- Distance Functions
--============================================================================

--[[
    Calculate distance to a TARGET
    (Uses C&C approximation: max(dx,dy) + min(dx,dy)/2)
]]
function AbstractClass:Distance_To_Target(target, heap_lookup)
    local coord = Target.As_Coordinate(target, heap_lookup)
    return Coord.Distance(self:Center_Coord(), coord)
end

--[[
    Calculate distance to a coordinate (in leptons)
]]
function AbstractClass:Distance_To_Coord(coord)
    return Coord.Distance(self:Center_Coord(), coord)
end

--[[
    Calculate distance to a cell
]]
function AbstractClass:Distance_To_Cell(cell)
    local coord = Coord.Cell_Coord(cell)
    return Coord.Distance(self:Center_Coord(), coord)
end

--[[
    Calculate distance to another object
]]
function AbstractClass:Distance_To_Object(object)
    return Coord.Distance(self:Center_Coord(), object:Target_Coord())
end

--============================================================================
-- Cell Entry Check
--============================================================================

--[[
    Check if this object can enter the specified cell.
    Returns MoveType (MOVE_OK, MOVE_NO, etc.)

    Default implementation returns MOVE_OK.
    Override in derived classes for proper passability checks.

    @param cell - CELL to check
    @param facing - FacingType (optional, for directional checks)
]]
function AbstractClass:Can_Enter_Cell(cell, facing)
    return Constants.MOVE.OK
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    Main AI processing function, called each game tick.
    Default implementation does nothing.
    Override in derived classes for actual behavior.
]]
function AbstractClass:AI()
    -- Clear the recently created flag after first AI tick
    if self.IsRecentlyCreated then
        self.IsRecentlyCreated = false
    end
end

--============================================================================
-- Heap Management (for object pools)
--============================================================================

--[[
    Get the heap index for this object (used in TARGET encoding)
]]
function AbstractClass:get_heap_index()
    return self._heap_index
end

--[[
    Set the heap index (called by HeapClass on allocation)
]]
function AbstractClass:set_heap_index(index)
    self._heap_index = index
end

--[[
    Get the RTTI type for this object class
    Override in derived classes to return correct RTTI
]]
function AbstractClass:get_rtti()
    return Target.RTTI.NONE
end

--============================================================================
-- TARGET Support
--============================================================================

--[[
    Convert this object to a TARGET value
]]
function AbstractClass:As_Target()
    if not self.IsActive then
        return Target.TARGET_NONE
    end
    return Target.Build(self:get_rtti(), self:get_heap_index())
end

--============================================================================
-- Debug Support
--============================================================================

--[[
    Dump object state for debugging
]]
function AbstractClass:Debug_Dump()
    local coord_str = Coord.Coord_String(self.Coord)
    print(string.format("AbstractClass: Coord=%s Active=%s RecentlyCreated=%s HeapIdx=%d",
        coord_str,
        tostring(self.IsActive),
        tostring(self.IsRecentlyCreated),
        self._heap_index or -1))
end

--============================================================================
-- Serialization (Save/Load)
--============================================================================

--[[
    Save object state
]]
function AbstractClass:Code_Pointers()
    return {
        Coord = self.Coord,
        IsActive = self.IsActive,
        -- IsRecentlyCreated is not saved (always false on load)
    }
end

--[[
    Load object state
]]
function AbstractClass:Decode_Pointers(data)
    self.Coord = data.Coord or 0
    self.IsActive = data.IsActive or false
    self.IsRecentlyCreated = false
end

return AbstractClass
