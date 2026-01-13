--[[
    TerrainTypeClass - Static data for terrain objects (trees, rocks)

    Port of TerrainTypeClass from TYPE.H/TDATA.CPP in the original C&C source.

    Terrain objects are large sprite objects that exist on the map and can
    take damage. Trees can catch fire, burn down, and be destroyed.
    Blossom trees spawn tiberium.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H (line 1360)
]]

local Class = require("src.objects.class")
local ObjectTypeClass = require("src.objects.types.objecttype")
local Coord = require("src.core.coord")

-- Create TerrainTypeClass extending ObjectTypeClass
local TerrainTypeClass = Class.extend(ObjectTypeClass, "TerrainTypeClass")

--============================================================================
-- RTTI
--============================================================================

TerrainTypeClass.RTTI = 22  -- RTTI_TERRAINTYPE

--============================================================================
-- TerrainType Enum
-- Matches DEFINES.H TerrainType enumeration
--============================================================================

TerrainTypeClass.TERRAIN = {
    NONE = -1,
    TREE1 = 0,        -- T01
    TREE2 = 1,        -- T02
    TREE3 = 2,        -- T03
    TREE4 = 3,        -- T04
    TREE5 = 4,        -- T05
    TREE6 = 5,        -- T06
    TREE7 = 6,        -- T07
    TREE8 = 7,        -- T08
    TREE9 = 8,        -- T09
    TREE10 = 9,       -- T10
    TREE11 = 10,      -- T11
    TREE12 = 11,      -- T12
    TREE13 = 12,      -- T13
    TREE14 = 13,      -- T14
    TREE15 = 14,      -- T15
    TREE16 = 15,      -- T16
    TREE17 = 16,      -- T17
    TREE18 = 17,      -- T18
    BLOSSOMTREE1 = 18,-- SPLIT2
    BLOSSOMTREE2 = 19,-- SPLIT3
    CLUMP1 = 20,      -- TC01
    CLUMP2 = 21,      -- TC02
    CLUMP3 = 22,      -- TC03
    CLUMP4 = 23,      -- TC04
    CLUMP5 = 24,      -- TC05
    ROCK1 = 25,       -- ROCK1
    ROCK2 = 26,       -- ROCK2
    ROCK3 = 27,       -- ROCK3
    ROCK4 = 28,       -- ROCK4
    ROCK5 = 29,       -- ROCK5
    ROCK6 = 30,       -- ROCK6
    ROCK7 = 31,       -- ROCK7
    COUNT = 32,
    FIRST = 0,
}

--============================================================================
-- Theater Flags
--============================================================================

TerrainTypeClass.THEATER = {
    TEMPERATE = 0x01,
    DESERT = 0x02,
    WINTER = 0x04,
    ALL = 0x07,
    -- Combined flags for convenience (since Lua 5.1 lacks bitwise OR)
    TEMPERATE_WINTER = 0x05,  -- TEMPERATE | WINTER
}

--============================================================================
-- Constructor
--============================================================================

function TerrainTypeClass:init(terrain_type, ini_name, full_name, armor, strength,
                                is_destroyable, is_transformable, is_tiberium_spawn,
                                is_flammable, is_crushable, center_base, theater, occupy, overlap)
    -- Call parent constructor
    ObjectTypeClass.init(self, ini_name, full_name)

    -- Set terrain type ID
    self.Type = terrain_type

    -- Type-specific properties
    self.Armor = armor or 0  -- ARMOR_WOOD typically
    self.MaxStrength = strength or 800

    -- Behavior flags
    self.IsDestroyable = is_destroyable or false  -- Can be destroyed (trees crumble)
    self.IsTransformable = is_transformable or false  -- Can transform (blossom tree)
    self.IsTiberiumSpawn = is_tiberium_spawn or false  -- Spawns tiberium (blossom tree)
    self.IsFlammable = is_flammable or false  -- Can catch fire
    self.IsCrushable = is_crushable or false  -- Can be crushed by vehicles

    -- Center base coordinate offset for sorting
    -- This is the base of the trunk for trees, used for Y-sorting
    self.CenterBase = center_base or 0

    -- Theater availability (bit flags)
    self.Theater = theater or TerrainTypeClass.THEATER.ALL

    -- Cell occupancy lists
    self.OccupyList = occupy or {0}  -- Default: single cell at 0,0
    self.OverlapList = overlap or {}  -- Cells that sprite overlaps but doesn't block
end

--============================================================================
-- Identification
--============================================================================

function TerrainTypeClass:What_Am_I()
    return TerrainTypeClass.RTTI
end

--============================================================================
-- Theater Support
--============================================================================

--[[
    Check if this terrain type is valid for the given theater.
    @param theater_type - Theater enum value
    @return true if valid for this theater
]]
function TerrainTypeClass:Is_Valid_For_Theater(theater_type)
    -- Use bit library for LuaJIT compatibility
    local bit = bit or require("bit")
    local theater_bit = bit.lshift(1, theater_type)
    return bit.band(self.Theater, theater_bit) ~= 0
end

--============================================================================
-- Cell Lists
--============================================================================

--[[
    Get list of cells this terrain occupies (blocks movement/building).
    @param placement - true if checking for placement (includes overlap)
    @return table of cell offsets
]]
function TerrainTypeClass:Occupy_List(placement)
    if placement then
        -- Include overlap cells for placement checking
        local combined = {}
        for _, v in ipairs(self.OccupyList) do
            table.insert(combined, v)
        end
        for _, v in ipairs(self.OverlapList) do
            table.insert(combined, v)
        end
        return combined
    end
    return self.OccupyList
end

--[[
    Get list of cells this terrain overlaps (sprite extends into but doesn't block).
    @return table of cell offsets
]]
function TerrainTypeClass:Overlap_List()
    return self.OverlapList
end

--============================================================================
-- Coordinate Helpers
--============================================================================

--[[
    Fix coordinate to cell alignment for terrain placement.
    @param coord - Raw coordinate
    @return Aligned coordinate (snapped to cell corner)
]]
function TerrainTypeClass:Coord_Fixup(coord)
    -- Snap to cell corners (remove lepton offset)
    return Coord.Cell_Coord(Coord.Coord_Cell(coord))
end

--============================================================================
-- Factory Methods
--============================================================================

-- Type registry
TerrainTypeClass.Types = {}

--[[
    Create or retrieve a terrain type by ID.
    @param terrain_type - TerrainType enum value
    @return TerrainTypeClass instance
]]
function TerrainTypeClass.Create(terrain_type)
    if terrain_type == TerrainTypeClass.TERRAIN.NONE then
        return nil
    end

    -- Return cached type if exists
    if TerrainTypeClass.Types[terrain_type] then
        return TerrainTypeClass.Types[terrain_type]
    end

    local terrain = nil
    local T = TerrainTypeClass.TERRAIN
    local TH = TerrainTypeClass.THEATER

    -- Tree data from TDATA.CPP
    -- Trees (destroyable, flammable)
    if terrain_type == T.TREE1 then
        terrain = TerrainTypeClass:new(T.TREE1, "T01", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(11, 41), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE2 then
        terrain = TerrainTypeClass:new(T.TREE2, "T02", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(11, 44), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE3 then
        terrain = TerrainTypeClass:new(T.TREE3, "T03", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(12, 45), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE4 then
        terrain = TerrainTypeClass:new(T.TREE4, "T04", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(11, 41), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE5 then
        terrain = TerrainTypeClass:new(T.TREE5, "T05", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(13, 39), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE6 then
        terrain = TerrainTypeClass:new(T.TREE6, "T06", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(13, 39), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE7 then
        terrain = TerrainTypeClass:new(T.TREE7, "T07", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(15, 40), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE8 then
        terrain = TerrainTypeClass:new(T.TREE8, "T08", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(12, 37), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE9 then
        terrain = TerrainTypeClass:new(T.TREE9, "T09", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(12, 37), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE10 then
        terrain = TerrainTypeClass:new(T.TREE10, "T10", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 36), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE11 then
        terrain = TerrainTypeClass:new(T.TREE11, "T11", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(15, 48), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE12 then
        terrain = TerrainTypeClass:new(T.TREE12, "T12", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(15, 48), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE13 then
        terrain = TerrainTypeClass:new(T.TREE13, "T13", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE14 then
        terrain = TerrainTypeClass:new(T.TREE14, "T14", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE15 then
        terrain = TerrainTypeClass:new(T.TREE15, "T15", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.TEMPERATE_WINTER, {0}, {})
    elseif terrain_type == T.TREE16 then
        terrain = TerrainTypeClass:new(T.TREE16, "T16", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.DESERT, {0}, {})  -- Desert only
    elseif terrain_type == T.TREE17 then
        terrain = TerrainTypeClass:new(T.TREE17, "T17", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.DESERT, {0}, {})  -- Desert only
    elseif terrain_type == T.TREE18 then
        terrain = TerrainTypeClass:new(T.TREE18, "T18", "Tree", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(14, 42), TH.ALL, {0}, {})

    -- Blossom trees (transformable, spawn tiberium)
    elseif terrain_type == T.BLOSSOMTREE1 then
        terrain = TerrainTypeClass:new(T.BLOSSOMTREE1, "SPLIT2", "Blossom Tree", 0, 800, true, true, true, false, false,
            Coord.XY_Coord(18, 44), TH.ALL, {0}, {})
    elseif terrain_type == T.BLOSSOMTREE2 then
        terrain = TerrainTypeClass:new(T.BLOSSOMTREE2, "SPLIT3", "Blossom Tree", 0, 800, true, true, true, false, false,
            Coord.XY_Coord(18, 44), TH.ALL, {0}, {})

    -- Tree clumps (larger, multiple cells)
    elseif terrain_type == T.CLUMP1 then
        terrain = TerrainTypeClass:new(T.CLUMP1, "TC01", "Tree Clump", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(28, 41), TH.TEMPERATE_WINTER, {0, 1}, {-64})  -- 2 cells wide
    elseif terrain_type == T.CLUMP2 then
        terrain = TerrainTypeClass:new(T.CLUMP2, "TC02", "Tree Clump", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(38, 41), TH.TEMPERATE_WINTER, {0, 1, 64, 65}, {-64, -63})  -- 2x2
    elseif terrain_type == T.CLUMP3 then
        terrain = TerrainTypeClass:new(T.CLUMP3, "TC03", "Tree Clump", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(28, 41), TH.TEMPERATE_WINTER, {0, 1}, {-64})
    elseif terrain_type == T.CLUMP4 then
        terrain = TerrainTypeClass:new(T.CLUMP4, "TC04", "Tree Clump", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(38, 41), TH.TEMPERATE_WINTER, {0, 1, 64, 65}, {-64, -63})
    elseif terrain_type == T.CLUMP5 then
        terrain = TerrainTypeClass:new(T.CLUMP5, "TC05", "Tree Clump", 1, 800, true, false, false, true, false,
            Coord.XY_Coord(38, 41), TH.TEMPERATE_WINTER, {0, 1, 64, 65}, {-64, -63})

    -- Rocks (not flammable, not destroyable by normal weapons)
    elseif terrain_type == T.ROCK1 then
        terrain = TerrainTypeClass:new(T.ROCK1, "ROCK1", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(11, 18), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK2 then
        terrain = TerrainTypeClass:new(T.ROCK2, "ROCK2", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(14, 22), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK3 then
        terrain = TerrainTypeClass:new(T.ROCK3, "ROCK3", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(15, 20), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK4 then
        terrain = TerrainTypeClass:new(T.ROCK4, "ROCK4", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(11, 11), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK5 then
        terrain = TerrainTypeClass:new(T.ROCK5, "ROCK5", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(14, 14), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK6 then
        terrain = TerrainTypeClass:new(T.ROCK6, "ROCK6", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(17, 19), TH.ALL, {0}, {})
    elseif terrain_type == T.ROCK7 then
        terrain = TerrainTypeClass:new(T.ROCK7, "ROCK7", "Rock", 2, 2000, false, false, false, false, false,
            Coord.XY_Coord(20, 22), TH.ALL, {0}, {})
    end

    -- Cache and return
    if terrain then
        TerrainTypeClass.Types[terrain_type] = terrain
    end

    return terrain
end

--[[
    Get terrain type from name.
    @param name - INI name (e.g., "T01", "ROCK1")
    @return TerrainType enum value or TERRAIN.NONE
]]
function TerrainTypeClass.From_Name(name)
    if not name then return TerrainTypeClass.TERRAIN.NONE end

    name = name:upper()

    -- Check all types
    for type_id = 0, TerrainTypeClass.TERRAIN.COUNT - 1 do
        local terrain_type = TerrainTypeClass.Create(type_id)
        if terrain_type and terrain_type.Name:upper() == name then
            return type_id
        end
    end

    return TerrainTypeClass.TERRAIN.NONE
end

--[[
    Get reference to terrain type by ID.
    @param terrain_type - TerrainType enum value
    @return TerrainTypeClass instance
]]
function TerrainTypeClass.As_Reference(terrain_type)
    return TerrainTypeClass.Create(terrain_type)
end

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize all terrain types for a theater.
    @param theater - Theater type (0=Temperate, 1=Desert, 2=Winter)
]]
function TerrainTypeClass.Init(theater)
    theater = theater or 0

    -- Pre-create all terrain types
    for type_id = 0, TerrainTypeClass.TERRAIN.COUNT - 1 do
        TerrainTypeClass.Create(type_id)
    end
end

--============================================================================
-- Debug
--============================================================================

function TerrainTypeClass:Debug_Dump()
    print("TerrainTypeClass:")
    print(string.format("  Type: %d (%s)", self.Type, self.Name))
    print(string.format("  FullName: %s", self.FullName))
    print(string.format("  Armor: %d  Strength: %d", self.Armor, self.MaxStrength))
    print(string.format("  IsDestroyable: %s  IsFlammable: %s",
        tostring(self.IsDestroyable), tostring(self.IsFlammable)))
    print(string.format("  IsTiberiumSpawn: %s  IsTransformable: %s",
        tostring(self.IsTiberiumSpawn), tostring(self.IsTransformable)))
    print(string.format("  Theater: 0x%02X", self.Theater))

    -- Call parent
    ObjectTypeClass.Debug_Dump(self)
end

return TerrainTypeClass
