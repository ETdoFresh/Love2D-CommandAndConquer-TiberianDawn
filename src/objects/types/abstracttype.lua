--[[
    AbstractTypeClass - Base type class for all game objects

    Port of TYPE.H AbstractTypeClass from the original C&C source.

    This is the root of the type class hierarchy. It provides:
    - INI name for scenario file identification
    - Localized display name
    - RTTI type identification

    Type classes hold STATIC data that is initialized once and never
    changes during gameplay. Instance classes use type classes to
    get their properties.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
]]

local Class = require("src.objects.class")
local Target = require("src.core.target")

-- Create AbstractTypeClass as a base class
local AbstractTypeClass = Class.create("AbstractTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Maximum length of INI name
AbstractTypeClass.MAX_INI_NAME = 8

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new AbstractTypeClass.

    @param ini_name - The INI control name (8 chars max)
    @param name - The full display name text ID
]]
function AbstractTypeClass:init(ini_name, name)
    --[[
        This is the internal control name for this object type.
        It is the name used in scenario files (INI files) to identify
        the object. Maximum 8 characters.
    ]]
    self.IniName = ini_name or ""

    --[[
        This is the text ID for the full name of this object type.
        It is used for localized display names.
        In our Lua version, this is the actual string name.
    ]]
    self.Name = name or ""

    --[[
        RTTI type for this object type.
        Set by derived classes.
    ]]
    self.RTTI = Target.RTTI.NONE
end

--============================================================================
-- RTTI Support
--============================================================================

--[[
    Get the RTTI type for this object.
]]
function AbstractTypeClass:What_Am_I()
    return self.RTTI
end

--============================================================================
-- Name Access
--============================================================================

--[[
    Get the internal INI name.
]]
function AbstractTypeClass:Get_Name()
    return self.IniName
end

--[[
    Set the INI name.
    Truncates to MAX_INI_NAME characters.

    @param name - New INI name
]]
function AbstractTypeClass:Set_Name(name)
    if name then
        self.IniName = name:sub(1, AbstractTypeClass.MAX_INI_NAME)
    end
end

--[[
    Get the full display name.
]]
function AbstractTypeClass:Full_Name()
    return self.Name
end

--[[
    Set the full display name.

    @param name - New display name
]]
function AbstractTypeClass:Set_Full_Name(name)
    self.Name = name or ""
end

--============================================================================
-- Coordinate Support
--============================================================================

--[[
    Adjust a coordinate for this object type.
    Default does no adjustment.

    @param coord - COORDINATE to adjust
    @return Adjusted COORDINATE
]]
function AbstractTypeClass:Coord_Fixup(coord)
    return coord
end

--============================================================================
-- Ownership
--============================================================================

--[[
    Get which houses can own this type.
    Returns a bitfield of allowed houses.
    Default: all houses allowed (0xFFFF).
]]
function AbstractTypeClass:Get_Ownable()
    return 0xFFFF
end

--[[
    Check if a specific house can own this type.

    @param house - HouseType to check
    @return true if house can own this type
]]
function AbstractTypeClass:Can_House_Own(house)
    if house < 0 or house > 15 then
        return false
    end
    local mask = bit.lshift(1, house)
    return bit.band(self:Get_Ownable(), mask) ~= 0
end

--============================================================================
-- Debug Support
--============================================================================

function AbstractTypeClass:Debug_Dump()
    print(string.format("AbstractTypeClass: INI='%s' Name='%s' RTTI=%d",
        self.IniName,
        self.Name,
        self.RTTI))
end

return AbstractTypeClass
