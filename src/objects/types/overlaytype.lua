--[[
    OverlayTypeClass - Static data for overlay types

    Port of OverlayTypeClass from TYPE.H/ODATA.CPP

    Overlays are placed on top of terrain cells and include:
    - Walls (sandbags, chain-link, concrete, barbed wire, wooden)
    - Tiberium (12 growth stages)
    - Roads
    - Crates (wooden, steel)
    - Decorative farm fields

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
]]

local ObjectTypeClass = require("src.objects.types.objecttype")
local Class = require("src.objects.class")

-- Create OverlayTypeClass extending ObjectTypeClass
local OverlayTypeClass = Class.extend(ObjectTypeClass, "OverlayTypeClass")

--============================================================================
-- Overlay Type Enum
--============================================================================

OverlayTypeClass.OVERLAY = {
    NONE = -1,
    CONCRETE = 0,
    SANDBAG_WALL = 1,
    CYCLONE_WALL = 2,
    BRICK_WALL = 3,
    BARBWIRE_WALL = 4,
    WOOD_WALL = 5,
    TIBERIUM1 = 6,
    TIBERIUM2 = 7,
    TIBERIUM3 = 8,
    TIBERIUM4 = 9,
    TIBERIUM5 = 10,
    TIBERIUM6 = 11,
    TIBERIUM7 = 12,
    TIBERIUM8 = 13,
    TIBERIUM9 = 14,
    TIBERIUM10 = 15,
    TIBERIUM11 = 16,
    TIBERIUM12 = 17,
    ROAD = 18,
    SQUISH = 19,
    V12 = 20,           -- Haystacks
    V13 = 21,           -- Haystack
    V14 = 22,           -- Wheat field
    V15 = 23,           -- Fallow field
    V16 = 24,           -- Corn field
    V17 = 25,           -- Celery field
    V18 = 26,           -- Potato field
    FLAG_SPOT = 27,
    WOOD_CRATE = 28,
    STEEL_CRATE = 29,
    COUNT = 30,
}

-- Land type for passability
OverlayTypeClass.LAND = {
    CLEAR = 0,
    ROAD = 1,
    WATER = 2,
    ROCK = 3,
    WALL = 4,
    TIBERIUM = 5,
    BEACH = 6,
}

--============================================================================
-- Constructor
--============================================================================

function OverlayTypeClass:init(overlay_type, ini_name, full_name, land, damage_levels,
                                damage_points, is_radar_invisible, is_wall, is_high,
                                is_tiberium, is_wooden, is_crate, is_theater)
    -- Call parent constructor with ini_name as both Name and IniName
    ObjectTypeClass.init(self, ini_name, ini_name)

    self.Type = overlay_type
    self.FullName = full_name or ini_name
    self.Land = land or OverlayTypeClass.LAND.CLEAR

    -- Wall properties
    self.DamageLevels = damage_levels or 1
    self.DamagePoints = damage_points or 0

    -- Flags
    self.IsTheater = is_theater or false
    self.IsWall = is_wall or false
    self.IsHigh = is_high or false
    self.IsTiberium = is_tiberium or false
    self.IsWooden = is_wooden or false
    self.IsCrate = is_crate or false
    self.IsRadarVisible = not is_radar_invisible

    -- RTTI
    self.RTTI = 10  -- RTTI_OVERLAYTYPE
end

--============================================================================
-- Static Data
--============================================================================

-- Cache for created types
local overlay_types = {}

--[[
    Get or create an overlay type by enum value.
]]
function OverlayTypeClass.Create(overlay_type)
    if overlay_types[overlay_type] then
        return overlay_types[overlay_type]
    end

    local type_data = OverlayTypeClass.TYPE_DATA[overlay_type]
    if type_data then
        local instance = OverlayTypeClass:new(
            overlay_type,
            type_data.ini_name,
            type_data.full_name,
            type_data.land,
            type_data.damage_levels,
            type_data.damage_points,
            type_data.is_radar_invisible,
            type_data.is_wall,
            type_data.is_high,
            type_data.is_tiberium,
            type_data.is_wooden,
            type_data.is_crate,
            type_data.is_theater
        )
        overlay_types[overlay_type] = instance
        return instance
    end

    return nil
end

--[[
    Get overlay type by name.
]]
function OverlayTypeClass.From_Name(name)
    for type_id, data in pairs(OverlayTypeClass.TYPE_DATA) do
        if data.ini_name == name then
            return OverlayTypeClass.Create(type_id)
        end
    end
    return nil
end

--============================================================================
-- Type Data (from ODATA.CPP)
--============================================================================

local O = OverlayTypeClass.OVERLAY
local L = OverlayTypeClass.LAND

OverlayTypeClass.TYPE_DATA = {
    [O.CONCRETE] = {
        ini_name = "CONC",
        full_name = "Concrete",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.SANDBAG_WALL] = {
        ini_name = "SBAG",
        full_name = "Sandbag Wall",
        land = L.WALL,
        damage_levels = 2,
        damage_points = 20,
        is_radar_invisible = false,
        is_wall = true,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.CYCLONE_WALL] = {
        ini_name = "CYCL",
        full_name = "Chain Link",
        land = L.WALL,
        damage_levels = 2,
        damage_points = 10,
        is_radar_invisible = false,
        is_wall = true,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.BRICK_WALL] = {
        ini_name = "BRIK",
        full_name = "Concrete Wall",
        land = L.WALL,
        damage_levels = 4,
        damage_points = 70,
        is_radar_invisible = false,
        is_wall = true,
        is_high = true,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.BARBWIRE_WALL] = {
        ini_name = "BARB",
        full_name = "Barbed Wire",
        land = L.WALL,
        damage_levels = 2,
        damage_points = 2,
        is_radar_invisible = false,
        is_wall = true,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.WOOD_WALL] = {
        ini_name = "WOOD",
        full_name = "Wood Fence",
        land = L.WALL,
        damage_levels = 2,
        damage_points = 2,
        is_radar_invisible = false,
        is_wall = true,
        is_high = false,
        is_tiberium = false,
        is_wooden = true,
        is_crate = false,
        is_theater = false,
    },
    [O.TIBERIUM1] = {
        ini_name = "TI1",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM2] = {
        ini_name = "TI2",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM3] = {
        ini_name = "TI3",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM4] = {
        ini_name = "TI4",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM5] = {
        ini_name = "TI5",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM6] = {
        ini_name = "TI6",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM7] = {
        ini_name = "TI7",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM8] = {
        ini_name = "TI8",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM9] = {
        ini_name = "TI9",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM10] = {
        ini_name = "TI10",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM11] = {
        ini_name = "TI11",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.TIBERIUM12] = {
        ini_name = "TI12",
        full_name = "Tiberium",
        land = L.TIBERIUM,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = true,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.ROAD] = {
        ini_name = "ROAD",
        full_name = "Road",
        land = L.ROAD,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.SQUISH] = {
        ini_name = "SQUISH",
        full_name = "Squish Mark",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.V12] = {
        ini_name = "V12",
        full_name = "Haystacks",
        land = L.ROCK,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V13] = {
        ini_name = "V13",
        full_name = "Haystack",
        land = L.ROCK,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V14] = {
        ini_name = "V14",
        full_name = "Wheat Field",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V15] = {
        ini_name = "V15",
        full_name = "Fallow Field",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V16] = {
        ini_name = "V16",
        full_name = "Corn Field",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V17] = {
        ini_name = "V17",
        full_name = "Celery Field",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.V18] = {
        ini_name = "V18",
        full_name = "Potato Field",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = true,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = true,
    },
    [O.FLAG_SPOT] = {
        ini_name = "FPLS",
        full_name = "Flag Location",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = false,
        is_theater = false,
    },
    [O.WOOD_CRATE] = {
        ini_name = "WCRATE",
        full_name = "Wooden Crate",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = true,
        is_theater = false,
    },
    [O.STEEL_CRATE] = {
        ini_name = "SCRATE",
        full_name = "Steel Crate",
        land = L.CLEAR,
        damage_levels = 1,
        damage_points = 0,
        is_radar_invisible = false,
        is_wall = false,
        is_high = false,
        is_tiberium = false,
        is_wooden = false,
        is_crate = true,
        is_theater = false,
    },
}

--============================================================================
-- Helper Functions
--============================================================================

--[[
    Check if an overlay type is tiberium.
]]
function OverlayTypeClass.Is_Tiberium(overlay_type)
    return overlay_type >= O.TIBERIUM1 and overlay_type <= O.TIBERIUM12
end

--[[
    Check if an overlay type is a wall.
]]
function OverlayTypeClass.Is_Wall(overlay_type)
    return overlay_type >= O.SANDBAG_WALL and overlay_type <= O.WOOD_WALL
end

--[[
    Check if an overlay type is a crate.
]]
function OverlayTypeClass.Is_Crate(overlay_type)
    return overlay_type == O.WOOD_CRATE or overlay_type == O.STEEL_CRATE
end

--[[
    Get tiberium value for a specific tiberium overlay stage.
    Higher stages = more tiberium value.
]]
function OverlayTypeClass.Tiberium_Value(overlay_type)
    if not OverlayTypeClass.Is_Tiberium(overlay_type) then
        return 0
    end
    -- Tiberium value scales with stage (TI1=25, TI12=300)
    local stage = overlay_type - O.TIBERIUM1 + 1
    return stage * 25
end

return OverlayTypeClass
