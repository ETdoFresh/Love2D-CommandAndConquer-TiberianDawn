--[[
    SmudgeTypeClass - Static data for smudge objects (craters, scorch marks)

    Port of SmudgeTypeClass from TYPE.H/SDATA.CPP in the original C&C source.

    Smudges are transparent decals drawn on the terrain to show battle damage.
    They include:
    - Craters (from explosions, can stack)
    - Scorch marks (from fire/explosions)
    - Bibs (building foundations)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H (line 1952)
]]

local Class = require("src.objects.class")
local ObjectTypeClass = require("src.objects.types.objecttype")

-- Create SmudgeTypeClass extending ObjectTypeClass
local SmudgeTypeClass = Class.extend(ObjectTypeClass, "SmudgeTypeClass")

--============================================================================
-- RTTI
--============================================================================

SmudgeTypeClass.RTTI = 24  -- RTTI_SMUDGETYPE

--============================================================================
-- SmudgeType Enum
-- Matches DEFINES.H SmudgeType enumeration
--============================================================================

SmudgeTypeClass.SMUDGE = {
    NONE = -1,
    CRATER1 = 0,      -- CR1 - Small crater
    CRATER2 = 1,      -- CR2
    CRATER3 = 2,      -- CR3
    CRATER4 = 3,      -- CR4
    CRATER5 = 4,      -- CR5
    CRATER6 = 5,      -- CR6 - Large crater
    SCORCH1 = 6,      -- SC1 - Small scorch
    SCORCH2 = 7,      -- SC2
    SCORCH3 = 8,      -- SC3
    SCORCH4 = 9,      -- SC4
    SCORCH5 = 10,     -- SC5
    SCORCH6 = 11,     -- SC6 - Large scorch
    BIB1 = 12,        -- BIB1 - 4x2 building foundation
    BIB2 = 13,        -- BIB2 - 3x2 building foundation
    BIB3 = 14,        -- BIB3 - 2x2 building foundation
    COUNT = 15,
    FIRST = 0,
}

--============================================================================
-- Constructor
--============================================================================

function SmudgeTypeClass:init(smudge_type, ini_name, full_name, width, height, is_bib, is_crater)
    -- Call parent constructor
    ObjectTypeClass.init(self, ini_name, full_name)

    -- Set smudge type ID
    self.Type = smudge_type

    -- Dimensions (in cells)
    self.Width = width or 1
    self.Height = height or 1

    -- Type flags
    self.IsBib = is_bib or false      -- Is a building foundation bib
    self.IsCrater = is_crater or false -- Is a crater (can stack)
end

--============================================================================
-- Identification
--============================================================================

function SmudgeTypeClass:What_Am_I()
    return SmudgeTypeClass.RTTI
end

--============================================================================
-- Cell Lists
--============================================================================

--[[
    Get list of cells this smudge occupies.
    @param placement - true if checking for placement
    @return table of cell offsets
]]
function SmudgeTypeClass:Occupy_List(placement)
    local cells = {}

    -- Generate cell list based on dimensions
    for y = 0, self.Height - 1 do
        for x = 0, self.Width - 1 do
            -- Cell offset: x + (y * MAP_WIDTH)
            -- Using 64 as standard map width for offset calculation
            table.insert(cells, x + y * 64)
        end
    end

    return cells
end

--[[
    Get overlap list (same as occupy for smudges).
    @return table of cell offsets
]]
function SmudgeTypeClass:Overlap_List()
    return self:Occupy_List()
end

--============================================================================
-- Drawing
--============================================================================

--[[
    Draw the smudge type.
    @param x - Screen X position
    @param y - Screen Y position
    @param data - Frame/stage data
]]
function SmudgeTypeClass:Draw_It(x, y, data)
    -- In full implementation: would draw the smudge shape
    -- Shape_Draw(self.ShapeFile, data or 0, x, y, WINDOW_TACTICAL)
end

--============================================================================
-- Factory Methods
--============================================================================

-- Type registry
SmudgeTypeClass.Types = {}

--[[
    Create or retrieve a smudge type by ID.
    @param smudge_type - SmudgeType enum value
    @return SmudgeTypeClass instance
]]
function SmudgeTypeClass.Create(smudge_type)
    if smudge_type == SmudgeTypeClass.SMUDGE.NONE then
        return nil
    end

    -- Return cached type if exists
    if SmudgeTypeClass.Types[smudge_type] then
        return SmudgeTypeClass.Types[smudge_type]
    end

    local smudge = nil
    local S = SmudgeTypeClass.SMUDGE

    -- Smudge data from SDATA.CPP
    -- Craters (1x1, stackable)
    if smudge_type == S.CRATER1 then
        smudge = SmudgeTypeClass:new(S.CRATER1, "CR1", "Crater", 1, 1, false, true)
    elseif smudge_type == S.CRATER2 then
        smudge = SmudgeTypeClass:new(S.CRATER2, "CR2", "Crater", 1, 1, false, true)
    elseif smudge_type == S.CRATER3 then
        smudge = SmudgeTypeClass:new(S.CRATER3, "CR3", "Crater", 1, 1, false, true)
    elseif smudge_type == S.CRATER4 then
        smudge = SmudgeTypeClass:new(S.CRATER4, "CR4", "Crater", 1, 1, false, true)
    elseif smudge_type == S.CRATER5 then
        smudge = SmudgeTypeClass:new(S.CRATER5, "CR5", "Crater", 1, 1, false, true)
    elseif smudge_type == S.CRATER6 then
        smudge = SmudgeTypeClass:new(S.CRATER6, "CR6", "Crater", 1, 1, false, true)

    -- Scorch marks (1x1, not stackable)
    elseif smudge_type == S.SCORCH1 then
        smudge = SmudgeTypeClass:new(S.SCORCH1, "SC1", "Scorch Mark", 1, 1, false, false)
    elseif smudge_type == S.SCORCH2 then
        smudge = SmudgeTypeClass:new(S.SCORCH2, "SC2", "Scorch Mark", 1, 1, false, false)
    elseif smudge_type == S.SCORCH3 then
        smudge = SmudgeTypeClass:new(S.SCORCH3, "SC3", "Scorch Mark", 1, 1, false, false)
    elseif smudge_type == S.SCORCH4 then
        smudge = SmudgeTypeClass:new(S.SCORCH4, "SC4", "Scorch Mark", 1, 1, false, false)
    elseif smudge_type == S.SCORCH5 then
        smudge = SmudgeTypeClass:new(S.SCORCH5, "SC5", "Scorch Mark", 1, 1, false, false)
    elseif smudge_type == S.SCORCH6 then
        smudge = SmudgeTypeClass:new(S.SCORCH6, "SC6", "Scorch Mark", 1, 1, false, false)

    -- Building foundations (bibs)
    elseif smudge_type == S.BIB1 then
        smudge = SmudgeTypeClass:new(S.BIB1, "BIB1", "Bib", 4, 2, true, false)
    elseif smudge_type == S.BIB2 then
        smudge = SmudgeTypeClass:new(S.BIB2, "BIB2", "Bib", 3, 2, true, false)
    elseif smudge_type == S.BIB3 then
        smudge = SmudgeTypeClass:new(S.BIB3, "BIB3", "Bib", 2, 2, true, false)
    end

    -- Cache and return
    if smudge then
        SmudgeTypeClass.Types[smudge_type] = smudge
    end

    return smudge
end

--[[
    Get smudge type from name.
    @param name - INI name (e.g., "CR1", "SC1", "BIB1")
    @return SmudgeType enum value or SMUDGE.NONE
]]
function SmudgeTypeClass.From_Name(name)
    if not name then return SmudgeTypeClass.SMUDGE.NONE end

    name = name:upper()

    -- Check all types
    for type_id = 0, SmudgeTypeClass.SMUDGE.COUNT - 1 do
        local smudge_type = SmudgeTypeClass.Create(type_id)
        if smudge_type and smudge_type.Name:upper() == name then
            return type_id
        end
    end

    return SmudgeTypeClass.SMUDGE.NONE
end

--[[
    Get reference to smudge type by ID.
    @param smudge_type - SmudgeType enum value
    @return SmudgeTypeClass instance
]]
function SmudgeTypeClass.As_Reference(smudge_type)
    return SmudgeTypeClass.Create(smudge_type)
end

--============================================================================
-- Random Smudge Selection
--============================================================================

--[[
    Get a random crater type for explosion effects.
    @return SmudgeType enum value
]]
function SmudgeTypeClass.Random_Crater()
    -- CRATER1 through CRATER6
    return math.random(SmudgeTypeClass.SMUDGE.CRATER1, SmudgeTypeClass.SMUDGE.CRATER6)
end

--[[
    Get a random scorch type for fire/explosion effects.
    @return SmudgeType enum value
]]
function SmudgeTypeClass.Random_Scorch()
    -- SCORCH1 through SCORCH6
    return math.random(SmudgeTypeClass.SMUDGE.SCORCH1, SmudgeTypeClass.SMUDGE.SCORCH6)
end

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize all smudge types for a theater.
    @param theater - Theater type
]]
function SmudgeTypeClass.Init(theater)
    -- Pre-create all smudge types
    for type_id = 0, SmudgeTypeClass.SMUDGE.COUNT - 1 do
        SmudgeTypeClass.Create(type_id)
    end
end

--[[
    One-time initialization.
]]
function SmudgeTypeClass.One_Time()
    -- Load shape files for smudges
end

--[[
    Prepare for map editor add.
]]
function SmudgeTypeClass.Prep_For_Add()
    -- Populate editor list with available smudges
end

--============================================================================
-- Debug
--============================================================================

function SmudgeTypeClass:Debug_Dump()
    print("SmudgeTypeClass:")
    print(string.format("  Type: %d (%s)", self.Type, self.Name))
    print(string.format("  FullName: %s", self.FullName))
    print(string.format("  Width: %d  Height: %d", self.Width, self.Height))
    print(string.format("  IsBib: %s  IsCrater: %s",
        tostring(self.IsBib), tostring(self.IsCrater)))

    -- Call parent
    ObjectTypeClass.Debug_Dump(self)
end

return SmudgeTypeClass
