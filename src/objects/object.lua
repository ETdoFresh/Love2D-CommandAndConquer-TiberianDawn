--[[
    ObjectClass - Base class for all map-visible game objects

    Port of OBJECT.H/CPP from the original C&C source.

    This class extends AbstractClass to add:
    - Map presence (IsDown, IsInLimbo)
    - Selection state
    - Health/strength tracking
    - Linked list support for cell occupancy
    - Trigger association
    - Rendering support
    - Combat support (damage, targeting)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/OBJECT.H
]]

local Class = require("src.objects.class")
local AbstractClass = require("src.objects.abstract")
local Coord = require("src.core.coord")
local Target = require("src.core.target")
local Constants = require("src.core.constants")

-- Lazy-loaded combat module
local WarheadTypeClass = nil

-- Create ObjectClass extending AbstractClass
local ObjectClass = Class.extend(AbstractClass, "ObjectClass")

--============================================================================
-- Constants
--============================================================================

-- Mark types for cell occupancy updates
ObjectClass.MARK = {
    UP = 0,           -- Remove from map
    DOWN = 1,         -- Place on map
    CHANGE = 2,       -- Change position (UP then DOWN)
    CHANGE_REDRAW = 3 -- Change position with forced redraw
}

-- Result types for Take_Damage
ObjectClass.RESULT = {
    NONE = 0,         -- No effect
    LIGHT = 1,        -- Light damage (no state change)
    HALF = 2,         -- Below half health
    DESTROYED = 3     -- Object destroyed
}

-- Layer types for rendering
ObjectClass.LAYER = Constants.LAYER

-- Action types for cursor/command
ObjectClass.ACTION = Constants.ACTION

--============================================================================
-- Constructor
--============================================================================

function ObjectClass:init()
    -- Call parent constructor
    AbstractClass.init(self)

    --[[
        The object can be in one of two states -- placed down on the map, or not.
        If the object is placed down on the map, then this flag will be true.
    ]]
    self.IsDown = false

    --[[
        This is a support flag that is only used while building a list of objects
        to be damaged by a proximity effect (explosion). When this flag is set,
        this object will not be added to the list of units to damage.
    ]]
    self.IsToDamage = false

    --[[
        Is this object flagged to be displayed during the next rendering process?
        This flag could be set by many different circumstances. It is automatically
        cleared when the object is rerendered.
    ]]
    self.IsToDisplay = false

    --[[
        An object in the game may be valid yet held in a state of "limbo".
        Units are in such a state if they are being transported or are otherwise
        "inside" another unit. They can also be in limbo if they have been created
        but are being held until the proper time for delivery.
    ]]
    self.IsInLimbo = true

    --[[
        When an object is "selected" it is given a floating bar graph or other
        graphic imagery to display this fact.
    ]]
    self.IsSelected = false

    --[[
        Selection mask for multiplayer (which players have this selected)
        Bit field where each bit represents a player
    ]]
    self.IsSelectedMask = 0

    --[[
        If an animation is attached to this object, then this flag will be true.
    ]]
    self.IsAnimAttached = false

    --[[
        Several objects could exist in the same cell list. This is a pointer to
        the next object in the cell list.
    ]]
    self.Next = nil

    --[[
        Every object can be assigned a trigger; the same trigger can be assigned
        to multiple objects.
    ]]
    self.Trigger = nil

    --[[
        This is the current strength (health) of this object.
    ]]
    self.Strength = 0
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Returns what RTTI type this object is (for type checking)
    Override in derived classes (InfantryClass, UnitClass, etc.)
]]
function ObjectClass:What_Am_I()
    return Target.RTTI.NONE
end

--[[
    Determines what action should be performed when interacting with another object
    Override in derived classes for specific behavior
]]
function ObjectClass:What_Action_Object(object)
    if object == nil then
        return ObjectClass.ACTION.NONE
    end
    return ObjectClass.ACTION.SELECT
end

--[[
    Determines what action should be performed when interacting with a cell
    Override in derived classes for specific behavior
]]
function ObjectClass:What_Action_Cell(cell)
    return ObjectClass.ACTION.MOVE
end

--[[
    Returns which render layer this object belongs to
    Override in derived classes (aircraft go in TOP, most go in GROUND)
]]
function ObjectClass:In_Which_Layer()
    return ObjectClass.LAYER.GROUND
end

--[[
    Is this object an infantry unit?
]]
function ObjectClass:Is_Infantry()
    return false
end

--[[
    Is this object a techno (combat-capable) object?
]]
function ObjectClass:Is_Techno()
    return false
end

--[[
    Returns bitmask of houses that can own this object type
    Override in type classes
]]
function ObjectClass:Get_Ownable()
    return 0xFF  -- All houses by default
end

--[[
    Returns the type class for this object (static data)
    Pure virtual - must be implemented by derived classes
]]
function ObjectClass:Class_Of()
    error("ObjectClass:Class_Of() must be overridden in derived class")
end

--[[
    Returns the full name ID for this object
]]
function ObjectClass:Full_Name()
    return 0
end

--[[
    Can this object be repaired?
]]
function ObjectClass:Can_Repair()
    return false
end

--[[
    Can this object be demolished (sold)?
]]
function ObjectClass:Can_Demolish()
    return false
end

--[[
    Can this object demolish a unit (bib)?
]]
function ObjectClass:Can_Demolish_Unit()
    return false
end

--[[
    Can this object be captured?
]]
function ObjectClass:Can_Capture()
    return false
end

--[[
    Can the player fire this object's weapon?
]]
function ObjectClass:Can_Player_Fire()
    return false
end

--[[
    Can the player move this object?
]]
function ObjectClass:Can_Player_Move()
    return false
end

--============================================================================
-- Coordinate Functions
--============================================================================

--[[
    Returns the docking coordinate for this object (where other units attach)
]]
function ObjectClass:Docking_Coord()
    return self:Center_Coord()
end

--[[
    Returns the coordinate used for rendering (top-left for buildings)
]]
function ObjectClass:Render_Coord()
    return self.Coord
end

--[[
    Returns the Y-sort coordinate for render ordering
    Objects with higher Y values are drawn on top
]]
function ObjectClass:Sort_Y()
    return self.Coord
end

--[[
    Returns fire coordinate and data for weapons
    @param which - which weapon (0 = primary, 1 = secondary)
]]
function ObjectClass:Fire_Data(which)
    return {
        coord = self:Center_Coord(),
        distance = 0
    }
end

--[[
    Returns the coordinate where projectiles originate
    @param which - which weapon
]]
function ObjectClass:Fire_Coord(which)
    return self:Center_Coord()
end

--============================================================================
-- Object Entry/Exit from Game
--============================================================================

--[[
    Put this object into limbo (remove from map but keep alive)
    Returns true if successful
]]
function ObjectClass:Limbo()
    if self.IsInLimbo then
        return false
    end

    -- Remove from map
    self:Mark(ObjectClass.MARK.UP)

    self.IsInLimbo = true
    self.IsSelected = false
    self.IsSelectedMask = 0

    return true
end

--[[
    Remove this object from limbo and place it on the map
    @param coord - COORDINATE to place at
    @param facing - Direction facing (optional)
    Returns true if successful
]]
function ObjectClass:Unlimbo(coord, facing)
    if not self.IsInLimbo then
        return false
    end

    self.Coord = coord
    self.IsInLimbo = false

    -- Place on map
    self:Mark(ObjectClass.MARK.DOWN)

    return true
end

--[[
    Detach from a specific target
    Called when target is being destroyed
]]
function ObjectClass:Detach(target, all)
    -- Override in derived classes
end

--[[
    Detach from all targets
]]
function ObjectClass:Detach_All(all)
    all = all == nil and true or all

    -- Clear trigger
    if self.Trigger then
        self.Trigger = nil
    end

    -- Clear next pointer
    self.Next = nil
end

--[[
    Record that this object killed something
    @param victim - The TechnoClass that was killed
]]
function ObjectClass:Record_The_Kill(victim)
    -- Override in derived classes for score tracking
end

--============================================================================
-- Display and Rendering
--============================================================================

--[[
    Apply shimmer effect (for cloaked units)
]]
function ObjectClass:Do_Shimmer()
    -- Override in TechnoClass
end

--[[
    Allow an object to exit from this object (e.g., unloading)
    @param object - TechnoClass trying to exit
    Returns exit code
]]
function ObjectClass:Exit_Object(object)
    return 0
end

--[[
    Render this object
    @param forced - Force redraw even if not flagged
    Returns true if something was drawn
]]
function ObjectClass:Render(forced)
    if not self.IsActive or self.IsInLimbo then
        return false
    end

    if forced or self.IsToDisplay then
        self.IsToDisplay = false
        -- Call Draw_It (to be implemented by derived classes)
        -- For now, just return true to indicate render was handled
        return true
    end

    return false
end

--[[
    Returns the occupy list (cells this object occupies)
    @param placement - If true, return placement preview cells
    Returns array of cell offsets
]]
function ObjectClass:Occupy_List(placement)
    return {}
end

--[[
    Returns the overlap list (cells this object visually overlaps)
    Returns array of cell offsets
]]
function ObjectClass:Overlap_List()
    return {}
end

--[[
    Returns health as a ratio (0-256 fixed point)
    256 = full health
]]
function ObjectClass:Health_Ratio()
    local type_class = self:Class_Of()
    if type_class and type_class.MaxStrength and type_class.MaxStrength > 0 then
        return math.floor((self.Strength * 256) / type_class.MaxStrength)
    end
    return 256
end

--[[
    Draw the object at screen coordinates
    Pure virtual - must be implemented by derived classes
    @param x - Screen X
    @param y - Screen Y
    @param window - Window to draw in
]]
function ObjectClass:Draw_It(x, y, window)
    -- Override in derived classes
end

--[[
    Called when object becomes hidden (leaves visible area)
]]
function ObjectClass:Hidden()
    -- Override in derived classes if needed
end

--[[
    Look around to update fog of war
    @param incremental - If true, only look at edges
]]
function ObjectClass:Look(incremental)
    -- Override in TechnoClass
end

--[[
    Update cell occupancy for this object
    @param mark_type - MARK.UP, MARK.DOWN, or MARK.CHANGE
    Returns true if successful
]]
function ObjectClass:Mark(mark_type)
    if not self.IsActive then
        return false
    end

    if self.IsInLimbo then
        return false
    end

    if mark_type == ObjectClass.MARK.UP then
        if self.IsDown then
            self.IsDown = false
            -- Remove from cell occupancy (to be implemented)
            return true
        end
    elseif mark_type == ObjectClass.MARK.DOWN then
        if not self.IsDown then
            self.IsDown = true
            -- Add to cell occupancy (to be implemented)
            return true
        end
    elseif mark_type == ObjectClass.MARK.CHANGE or mark_type == ObjectClass.MARK.CHANGE_REDRAW then
        self:Mark(ObjectClass.MARK.UP)
        self:Mark(ObjectClass.MARK.DOWN)
        if mark_type == ObjectClass.MARK.CHANGE_REDRAW then
            self:Mark_For_Redraw()
        end
        return true
    end

    return false
end

--[[
    Flag this object for redraw
]]
function ObjectClass:Mark_For_Redraw()
    self.IsToDisplay = true
end

--============================================================================
-- User I/O (Selection)
--============================================================================

--[[
    Handle click with action on another object
]]
function ObjectClass:Active_Click_With_Object(action, object)
    -- Override in derived classes
end

--[[
    Handle click with action on a cell
]]
function ObjectClass:Active_Click_With_Cell(action, cell)
    -- Override in derived classes
end

--[[
    Flash when clicked as a target
    @param house - House that clicked
    @param count - Flash count
]]
function ObjectClass:Clicked_As_Target(house, count)
    count = count or 7
    -- Override in TechnoClass
end

--[[
    Select this object
    @param allow_mixed - Allow mixed selection types
    Returns true if selected
]]
function ObjectClass:Select(allow_mixed)
    if self.IsInLimbo or not self.IsActive then
        return false
    end

    self.IsSelected = true
    return true
end

--[[
    Unselect this object
]]
function ObjectClass:Unselect()
    self.IsSelected = false
end

--[[
    Unselect for all players (multiplayer)
]]
function ObjectClass:Unselect_All_Players()
    self.IsSelected = false
    self.IsSelectedMask = 0
end

--[[
    Unselect for all players except owner
]]
function ObjectClass:Unselect_All_Players_Except_Owner()
    -- Override in TechnoClass where owner is known
    self.IsSelectedMask = 0
end

--[[
    Check if selected by a specific player
    @param player - HouseClass or nil for local player
]]
function ObjectClass:Is_Selected_By_Player(player)
    if player == nil then
        return self.IsSelected
    end
    -- Check bit in mask for player
    local bit_pos = player:get_heap_index()
    local bit = require("bit")
    return bit.band(self.IsSelectedMask, bit.lshift(1, bit_pos)) ~= 0
end

--[[
    Set selected by a specific player
]]
function ObjectClass:Set_Selected_By_Player(player)
    if player == nil then
        self.IsSelected = true
        return
    end
    local bit_pos = player:get_heap_index()
    local bit = require("bit")
    self.IsSelectedMask = bit.bor(self.IsSelectedMask, bit.lshift(1, bit_pos))
end

--[[
    Set unselected by a specific player
]]
function ObjectClass:Set_Unselected_By_Player(player)
    if player == nil then
        self.IsSelected = false
        return
    end
    local bit_pos = player:get_heap_index()
    local bitops = require("bit")
    self.IsSelectedMask = bitops.band(self.IsSelectedMask, bitops.bnot(bitops.lshift(1, bit_pos)))
end

--============================================================================
-- Combat
--============================================================================

--[[
    Check if target is in weapon range
    @param coord - Target coordinate
    @param which - Which weapon (0 or 1)
]]
function ObjectClass:In_Range(coord, which)
    return false
end

--[[
    Get weapon range
    @param which - Which weapon
]]
function ObjectClass:Weapon_Range(which)
    return 0
end

--[[
    Apply damage to this object
    @param damage - Amount of damage (modified by function)
    @param distance - Distance from explosion center
    @param warhead - Warhead type
    @param source - TechnoClass that caused damage (can be nil)
    Returns ResultType
]]
function ObjectClass:Take_Damage(damage, distance, warhead, source)
    if not self.IsActive or self.IsInLimbo then
        return ObjectClass.RESULT.NONE
    end

    -- Lazy load warhead module
    if not WarheadTypeClass then
        WarheadTypeClass = require("src.combat.warhead")
    end

    -- Get warhead definition
    local warhead_def = nil
    if warhead and warhead >= 0 then
        warhead_def = WarheadTypeClass.Get(warhead)
    end

    -- Apply warhead armor modifier
    local modified_damage = damage
    if warhead_def then
        -- Get this object's armor type
        local armor = self:Get_Armor()

        -- Modify damage by armor
        modified_damage = warhead_def:Modify_Damage(damage, armor)

        -- Apply distance falloff
        if distance and distance > 0 then
            modified_damage = warhead_def:Distance_Damage(modified_damage, distance)
        end
    end

    -- Ensure damage is at least 1 if original was > 0
    if damage > 0 and modified_damage < 1 then
        modified_damage = 1
    end

    local old_strength = self.Strength
    self.Strength = math.max(0, self.Strength - modified_damage)

    -- Handle destruction
    if self.Strength <= 0 then
        -- Record kill attribution
        if source then
            self:Record_The_Kill(source)
        end
        return ObjectClass.RESULT.DESTROYED
    elseif self.Strength < old_strength / 2 and old_strength >= old_strength / 2 then
        return ObjectClass.RESULT.HALF
    elseif modified_damage > 0 then
        return ObjectClass.RESULT.LIGHT
    end

    return ObjectClass.RESULT.NONE
end

--[[
    Get the armor type of this object.
    Override in derived classes.

    @return ArmorType enum value
]]
function ObjectClass:Get_Armor()
    -- Default to no armor
    return 0  -- ARMOR_NONE
end

--[[
    Record kill attribution.
    Called when this object is destroyed.

    @param killer - The object that killed us
]]
function ObjectClass:Record_The_Kill(killer)
    -- Override in TechnoClass for proper kill tracking
end

--[[
    Convert this object to a TARGET value
]]
function ObjectClass:As_Target()
    return Target.Build(self:What_Am_I(), self:get_heap_index())
end

--[[
    Scatter from a coordinate (dodge/flee)
    @param coord - Threat coordinate
    @param forced - Force scatter
    @param no_path - Don't use pathfinding
]]
function ObjectClass:Scatter(coord, forced, no_path)
    -- Override in FootClass
end

--[[
    Set object on fire
    Returns true if caught fire
]]
function ObjectClass:Catch_Fire()
    return false
end

--[[
    Extinguish fire
]]
function ObjectClass:Fire_Out()
    -- Override in derived classes
end

--[[
    Get the value of this object (for scoring/AI)
]]
function ObjectClass:Value()
    return 0
end

--[[
    Get current mission
]]
function ObjectClass:Get_Mission()
    return Constants.MISSION.NONE
end

--============================================================================
-- AI
--============================================================================

--[[
    Find a building that can build this object type
    @param intheory - If true, check if buildable in theory
    @param legal - If true, check legal placement
]]
function ObjectClass:Who_Can_Build_Me(intheory, legal)
    return nil
end

--[[
    Receive a radio message
    @param from - RadioClass sender
    @param message - Message type
    @param param - Message parameter
    Returns reply message
]]
function ObjectClass:Receive_Message(from, message, param)
    return 0  -- RADIO_STATIC
end

--[[
    Reveal this object to a house
    @param house - HouseClass to reveal to
    Returns true if newly revealed
]]
function ObjectClass:Revealed(house)
    return true
end

--[[
    Repair this object
    @param control - Control code
]]
function ObjectClass:Repair(control)
    -- Override in BuildingClass
end

--[[
    Sell this object back
    @param control - Control code
]]
function ObjectClass:Sell_Back(control)
    -- Override in derived classes
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

--[[
    Save object state
]]
function ObjectClass:Code_Pointers()
    local data = Class.super(self, "Code_Pointers") or {}

    data.IsDown = self.IsDown
    data.IsInLimbo = self.IsInLimbo
    data.IsSelected = self.IsSelected
    data.Strength = self.Strength
    -- Next pointer encoded as heap index
    data.Next = self.Next and self.Next:get_heap_index() or -1
    -- Trigger encoded as trigger index
    data.Trigger = self.Trigger and self.Trigger:get_heap_index() or -1

    return data
end

--[[
    Load object state
]]
function ObjectClass:Decode_Pointers(data, heap_lookup)
    Class.super(self, "Decode_Pointers", data)

    self.IsDown = data.IsDown or false
    self.IsInLimbo = data.IsInLimbo == nil and true or data.IsInLimbo
    self.IsSelected = data.IsSelected or false
    self.Strength = data.Strength or 0

    -- Next and Trigger are decoded later when all objects are loaded
    self._decode_next = data.Next
    self._decode_trigger = data.Trigger
end

--============================================================================
-- Debug Support
--============================================================================

function ObjectClass:Debug_Dump()
    Class.super(self, "Debug_Dump")
    print(string.format("ObjectClass: IsDown=%s IsInLimbo=%s IsSelected=%s Strength=%d",
        tostring(self.IsDown),
        tostring(self.IsInLimbo),
        tostring(self.IsSelected),
        self.Strength))
end

--[[
    Move object in a direction (debug/editor)
    @param facing - Direction to move
]]
function ObjectClass:Move(facing)
    local cell = Coord.Coord_Cell(self.Coord)
    local new_cell = Coord.Adjacent_Cell(cell, facing)
    if Coord.Cell_Is_Valid(new_cell) then
        self:Mark(ObjectClass.MARK.UP)
        self.Coord = Coord.Cell_Coord(new_cell)
        self:Mark(ObjectClass.MARK.DOWN)
    end
end

return ObjectClass
