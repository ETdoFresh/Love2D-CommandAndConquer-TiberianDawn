--[[
    ObjectTypeClass - Object type base class

    Port of TYPE.H ObjectTypeClass from the original C&C source.

    This class extends AbstractTypeClass to add:
    - Physical properties (armor, health)
    - Visual properties (image data, radar icon)
    - Behavior flags (crushable, selectable, etc.)
    - Dimension and occupancy information

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
]]

local Class = require("src.objects.class")
local AbstractTypeClass = require("src.objects.types.abstracttype")

-- Create ObjectTypeClass extending AbstractTypeClass
local ObjectTypeClass = Class.extend(AbstractTypeClass, "ObjectTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Armor types
ObjectTypeClass.ARMOR = {
    NONE = 0,       -- No armor (most infantry)
    WOOD = 1,       -- Wood armor
    LIGHT = 2,      -- Light armor (light vehicles)
    HEAVY = 3,      -- Heavy armor (tanks)
    CONCRETE = 4,   -- Concrete (buildings)
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new ObjectTypeClass.

    @param ini_name - The INI control name
    @param name - The full display name
]]
function ObjectTypeClass:init(ini_name, name)
    -- Call parent constructor
    AbstractTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Behavior Flags (1-bit booleans)
    --========================================================================

    --[[
        Can be destroyed by heavy vehicles running over it.
    ]]
    self.IsCrushable = false

    --[[
        Is this object hidden from radar scans?
    ]]
    self.IsStealthy = false

    --[[
        Can be selected by the player?
    ]]
    self.IsSelectable = false

    --[[
        Is this a legal target for attack commands?
    ]]
    self.IsLegalTarget = true

    --[[
        Is this object insignificant (no announcement on destruction)?
    ]]
    self.IsInsignificant = false

    --[[
        Is immune to normal combat damage?
    ]]
    self.IsImmune = false

    --[[
        Does this object animate when active (like rotating radar)?
    ]]
    self.IsAnimating = false

    --[[
        Can catch fire from flame weapons?
    ]]
    self.IsFlammable = false

    --[[
        Has AI logic processing (is sentient)?
    ]]
    self.IsSentient = false

    --[[
        Uses theater-specific artwork?
    ]]
    self.IsTheater = false

    --========================================================================
    -- Physical Properties
    --========================================================================

    --[[
        Armor type determines damage modification.
    ]]
    self.Armor = ObjectTypeClass.ARMOR.NONE

    --[[
        Maximum strength (hit points) when at full health.
    ]]
    self.MaxStrength = 1

    --========================================================================
    -- Visual Properties
    --========================================================================

    --[[
        Shape imagery data (sprite/shape file).
        In Lua this will be a path or image reference.
    ]]
    self.ImageData = nil

    --[[
        Radar icon imagery.
    ]]
    self.RadarIcon = nil

    --[[
        Number of facings in the shape (for units that rotate).
        Common values: 1, 8, 16, 32
    ]]
    self.Facings = 1

    --[[
        Building/unit dimensions in cells.
    ]]
    self.Width = 1
    self.Height = 1
end

--============================================================================
-- Dimension Queries
--============================================================================

--[[
    Get the object dimensions.

    @return width, height in cells
]]
function ObjectTypeClass:Dimensions()
    return self.Width, self.Height
end

--[[
    Set the object dimensions.

    @param width - Width in cells
    @param height - Height in cells
]]
function ObjectTypeClass:Set_Dimensions(width, height)
    self.Width = width or 1
    self.Height = height or 1
end

--============================================================================
-- Health
--============================================================================

--[[
    Get maximum strength.
]]
function ObjectTypeClass:Get_Max_Strength()
    return self.MaxStrength
end

--[[
    Set maximum strength.

    @param strength - Maximum hit points
]]
function ObjectTypeClass:Set_Max_Strength(strength)
    self.MaxStrength = math.max(1, strength or 1)
end

--============================================================================
-- Armor
--============================================================================

--[[
    Get armor type.
]]
function ObjectTypeClass:Get_Armor()
    return self.Armor
end

--[[
    Set armor type.

    @param armor - ArmorType enum value
]]
function ObjectTypeClass:Set_Armor(armor)
    self.Armor = armor or ObjectTypeClass.ARMOR.NONE
end

--============================================================================
-- Image Data
--============================================================================

--[[
    Get the shape imagery data.
]]
function ObjectTypeClass:Get_Image_Data()
    return self.ImageData
end

--[[
    Set the shape imagery data.

    @param data - Image data/path
]]
function ObjectTypeClass:Set_Image_Data(data)
    self.ImageData = data
end

--[[
    Get the radar icon data.
]]
function ObjectTypeClass:Get_Radar_Data()
    return self.RadarIcon
end

--[[
    Set the radar icon data.

    @param data - Radar icon data/path
]]
function ObjectTypeClass:Set_Radar_Data(data)
    self.RadarIcon = data
end

--============================================================================
-- Pip Display
--============================================================================

--[[
    Get maximum display pips (health bars, cargo indicators).
    Default is based on dimensions.
]]
function ObjectTypeClass:Max_Pips()
    return math.max(self.Width, self.Height)
end

--============================================================================
-- Occupancy Lists
--============================================================================

--[[
    Get the list of cells occupied by this object.
    Returns a list of cell offsets from the origin cell.

    @return List of cell offsets (empty for 1x1)
]]
function ObjectTypeClass:Occupy_List()
    -- Default 1x1 occupies only its own cell
    if self.Width == 1 and self.Height == 1 then
        return {}
    end

    -- Generate list for larger objects
    local list = {}
    for y = 0, self.Height - 1 do
        for x = 0, self.Width - 1 do
            if x ~= 0 or y ~= 0 then
                -- Offset from origin
                local offset = y * 64 + x  -- 64 cells per row (map width)
                table.insert(list, offset)
            end
        end
    end
    return list
end

--[[
    Get the list of cells visually overlapped by this object.
    Used for rendering objects that extend beyond their footprint.

    @return List of cell offsets
]]
function ObjectTypeClass:Overlap_List()
    -- Default: no overlap
    return {}
end

--============================================================================
-- Creation (Pure Virtual - Override in Derived)
--============================================================================

--[[
    Create and place an instance of this object type.

    @param cell - CELL to place at
    @param house - HousesType owner
    @return Created object or nil on failure
]]
function ObjectTypeClass:Create_And_Place(cell, house)
    -- Override in derived classes
    return nil
end

--[[
    Create one instance of this object type.

    @param house - HouseClass owner
    @return Created object or nil on failure
]]
function ObjectTypeClass:Create_One_Of(house)
    -- Override in derived classes
    return nil
end

--============================================================================
-- Cost and Build Time
--============================================================================

--[[
    Get the production cost.
    Override in derived classes.
]]
function ObjectTypeClass:Cost_Of()
    return 0
end

--[[
    Get the build time in ticks.

    @param house - HousesType for house-specific modifiers
    @return Build time in game ticks
]]
function ObjectTypeClass:Time_To_Build(house)
    return 0
end

--[[
    Get which building can produce this object.
    Override in derived classes.

    @return BuildingTypeClass or nil
]]
function ObjectTypeClass:Who_Can_Build_Me()
    return nil
end

--============================================================================
-- Cameo (Sidebar Icon)
--============================================================================

--[[
    Get the cameo (small icon) data for sidebar display.
]]
function ObjectTypeClass:Get_Cameo_Data()
    return nil  -- Override in TechnoTypeClass
end

--============================================================================
-- Debug Support
--============================================================================

function ObjectTypeClass:Debug_Dump()
    AbstractTypeClass.Debug_Dump(self)

    print(string.format("ObjectTypeClass: Armor=%d MaxHP=%d Size=%dx%d",
        self.Armor,
        self.MaxStrength,
        self.Width,
        self.Height))

    print(string.format("  Flags: Crushable=%s Selectable=%s LegalTarget=%s Sentient=%s",
        tostring(self.IsCrushable),
        tostring(self.IsSelectable),
        tostring(self.IsLegalTarget),
        tostring(self.IsSentient)))
end

return ObjectTypeClass
