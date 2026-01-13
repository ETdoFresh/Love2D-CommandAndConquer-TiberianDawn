--[[
    TARGET encoding/decoding utilities

    TARGET is a packed value used to reference game objects or map locations.
    It encodes both the type (RTTI) and the specific instance/coordinate.

    Reference: TARGET.H from original C&C
]]

local Coord = require("src.core.coord")

-- LuaJIT bit operations
local bit = bit or bit32 or require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local Target = {}

--============================================================================
-- RTTI (Run-Time Type Information) - identifies object types
--============================================================================

-- RTTI values from DEFINES.H
Target.RTTI = {
    NONE = 0,
    INFANTRY = 1,
    UNIT = 2,
    AIRCRAFT = 3,
    BUILDING = 4,
    BULLET = 5,
    ANIM = 6,
    TRIGGER = 7,
    TEAM = 8,
    TEAMTYPE = 9,
    TERRAIN = 10,
    OVERLAY = 11,
    SMUDGE = 12,
    CELL = 13,       -- Map coordinate target
    SPECIAL = 14,    -- Special value (none, home, base, etc.)
}

-- Reverse lookup for debugging
Target.RTTI_NAME = {}
for k, v in pairs(Target.RTTI) do
    Target.RTTI_NAME[v] = k
end

--============================================================================
-- TARGET bit layout:
-- Bits 0-15:  Instance ID (heap index) or packed CELL value
-- Bits 16-23: RTTI type
-- Bit 24:     Valid flag (1 = valid target, 0 = invalid)
--============================================================================

Target.ID_MASK = 0xFFFF      -- 16 bits for ID
Target.RTTI_SHIFT = 16       -- RTTI starts at bit 16
Target.RTTI_MASK = 0xFF      -- 8 bits for RTTI
Target.VALID_BIT = 0x1000000 -- Bit 24

--[[
    Special TARGET values
]]
Target.TARGET_NONE = 0

--============================================================================
-- TARGET Creation
--============================================================================

--[[
    Create a TARGET from an RTTI type and heap index
]]
function Target.Build(rtti, id)
    if rtti == Target.RTTI.NONE or id == nil then
        return Target.TARGET_NONE
    end

    return bor(
        Target.VALID_BIT,
        lshift(band(rtti, Target.RTTI_MASK), Target.RTTI_SHIFT),
        band(id, Target.ID_MASK)
    )
end

--[[
    Create a TARGET from a CELL (map coordinate)
]]
function Target.As_Cell(cell)
    return bor(
        Target.VALID_BIT,
        lshift(Target.RTTI.CELL, Target.RTTI_SHIFT),
        band(cell, Target.ID_MASK)
    )
end

--[[
    Create a TARGET from a COORDINATE (converts to cell target)
]]
function Target.As_Coord(coord)
    local cell = Coord.Coord_Cell(coord)
    return Target.As_Cell(cell)
end

--[[
    Create a TARGET from an object
    Object must have: get_rtti() and get_heap_index() methods
]]
function Target.As_Target(object)
    if object == nil then
        return Target.TARGET_NONE
    end

    local rtti = object:get_rtti()
    local id = object:get_heap_index()

    if rtti == nil or id == nil then
        return Target.TARGET_NONE
    end

    return Target.Build(rtti, id)
end

--============================================================================
-- TARGET Extraction
--============================================================================

--[[
    Check if TARGET is valid
]]
function Target.Is_Valid(target)
    if target == nil or target == 0 then
        return false
    end
    return band(target, Target.VALID_BIT) ~= 0
end

--[[
    Get RTTI type from TARGET
]]
function Target.Get_RTTI(target)
    if not Target.Is_Valid(target) then
        return Target.RTTI.NONE
    end
    return band(rshift(target, Target.RTTI_SHIFT), Target.RTTI_MASK)
end

--[[
    Get instance ID (heap index) from TARGET
]]
function Target.Get_ID(target)
    if not Target.Is_Valid(target) then
        return -1
    end
    return band(target, Target.ID_MASK)
end

--[[
    Check if TARGET is a cell (map coordinate)
]]
function Target.Is_Cell(target)
    return Target.Get_RTTI(target) == Target.RTTI.CELL
end

--[[
    Check if TARGET is an object (not a cell)
]]
function Target.Is_Object(target)
    local rtti = Target.Get_RTTI(target)
    return rtti >= Target.RTTI.INFANTRY and rtti <= Target.RTTI.SMUDGE
end

--[[
    Check if TARGET is a specific type
]]
function Target.Is_Type(target, rtti)
    return Target.Get_RTTI(target) == rtti
end

--[[
    Get CELL value from a cell TARGET
]]
function Target.Target_Cell(target)
    if not Target.Is_Cell(target) then
        return -1
    end
    return Target.Get_ID(target)
end

--[[
    Convert any TARGET to COORDINATE
    For cell targets: returns cell center
    For object targets: requires object lookup (returns 0 if not found)
]]
function Target.As_Coordinate(target, heap_lookup)
    if not Target.Is_Valid(target) then
        return 0
    end

    local rtti = Target.Get_RTTI(target)

    if rtti == Target.RTTI.CELL then
        local cell = Target.Get_ID(target)
        return Coord.Cell_Coord(cell)
    end

    -- For object targets, we need to look up the object
    if heap_lookup then
        local obj = heap_lookup(rtti, Target.Get_ID(target))
        if obj and obj.Coord then
            return obj.Coord
        end
    end

    return 0
end

--============================================================================
-- TARGET Comparison
--============================================================================

--[[
    Check if two TARGETs are equal
]]
function Target.Equal(target1, target2)
    return target1 == target2
end

--[[
    Check if TARGET matches an object
]]
function Target.Match(target, object)
    if not Target.Is_Valid(target) or object == nil then
        return false
    end

    return Target.Get_RTTI(target) == object:get_rtti() and
           Target.Get_ID(target) == object:get_heap_index()
end

--============================================================================
-- Type-specific TARGET creation helpers
--============================================================================

function Target.Infantry(id)
    return Target.Build(Target.RTTI.INFANTRY, id)
end

function Target.Unit(id)
    return Target.Build(Target.RTTI.UNIT, id)
end

function Target.Aircraft(id)
    return Target.Build(Target.RTTI.AIRCRAFT, id)
end

function Target.Building(id)
    return Target.Build(Target.RTTI.BUILDING, id)
end

function Target.Bullet(id)
    return Target.Build(Target.RTTI.BULLET, id)
end

function Target.Anim(id)
    return Target.Build(Target.RTTI.ANIM, id)
end

function Target.Terrain(id)
    return Target.Build(Target.RTTI.TERRAIN, id)
end

--============================================================================
-- Debug Helpers
--============================================================================

--[[
    Format TARGET as string for debugging
]]
function Target.To_String(target)
    if not Target.Is_Valid(target) then
        return "TARGET_NONE"
    end

    local rtti = Target.Get_RTTI(target)
    local id = Target.Get_ID(target)
    local type_name = Target.RTTI_NAME[rtti] or "UNKNOWN"

    if rtti == Target.RTTI.CELL then
        local cell = id
        return string.format("CELL(%d,%d)", Coord.Cell_X(cell), Coord.Cell_Y(cell))
    end

    return string.format("%s[%d]", type_name, id)
end

return Target
