--[[
    SmudgeClass - Smudge objects (craters, scorch marks, bibs)

    Port of SMUDGE.H/CPP from the original C&C source.

    Smudges are transitory objects that exist only during creation.
    Once placed on the map, they become cell data (not independent objects).
    This class handles the placement process.

    Types:
    - Craters: Created by explosions, can stack up to 4 deep
    - Scorch marks: Created by fire/explosions, decorative only
    - Bibs: Building foundations, placed under structures

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/SMUDGE.H
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local SmudgeTypeClass = require("src.objects.types.smudgetype")
local Coord = require("src.core.coord")

-- Create SmudgeClass extending ObjectClass
local SmudgeClass = Class.extend(ObjectClass, "SmudgeClass")

--============================================================================
-- RTTI
--============================================================================

SmudgeClass.RTTI = 12  -- RTTI_SMUDGE

--============================================================================
-- Static Variables
--============================================================================

-- House to assign ownership when placed (for bibs)
SmudgeClass.ToOwn = -1  -- HOUSE_NONE

-- VTable pointer (for save/load compatibility)
SmudgeClass.VTable = nil

--============================================================================
-- Constructor
--============================================================================

function SmudgeClass:init(smudge_type, coord, house)
    -- Call parent constructor
    ObjectClass.init(self)

    -- Get type class
    if type(smudge_type) == "number" then
        self.Class = SmudgeTypeClass.Create(smudge_type)
        self.Type = smudge_type
    else
        self.Class = smudge_type
        self.Type = smudge_type and smudge_type.Type or SmudgeTypeClass.SMUDGE.NONE
    end

    -- Set owner house (for bibs)
    self.OwnerHouse = house or -1  -- HOUSE_NONE

    self.IsActive = true

    -- Place immediately if coordinate provided
    if coord and coord >= 0 then
        self:Unlimbo(coord, 0)
    end
end

--============================================================================
-- Identification
--============================================================================

function SmudgeClass:What_Am_I()
    return SmudgeClass.RTTI
end

function SmudgeClass:Class_Of()
    return self.Class
end

--============================================================================
-- Map Placement
--============================================================================

--[[
    Mark the smudge on the map.

    Unlike other objects, smudges are "stamped" into the cell data and
    then the SmudgeClass object is destroyed. This function handles
    the stamping process.

    @param mark_type - MARK.UP, MARK.DOWN, MARK.CHANGE
    @return true if successful
]]
function SmudgeClass:Mark(mark_type)
    if not self:Is_Active() then
        return false
    end

    if mark_type == ObjectClass.MARK.DOWN then
        local cell = Coord.Coord_Cell(self.Coord)

        if self.Class then
            -- Get the occupy list from type
            local occupy = self.Class:Occupy_List()

            -- Stamp smudge data into each cell
            for i, offset in ipairs(occupy) do
                local target_cell = cell + offset

                -- In full implementation, would modify cell data:
                -- local map_cell = Map[target_cell]
                --
                -- if self.Class.IsCrater then
                --     -- Craters stack: increment smudge data
                --     if map_cell.SmudgeType == SmudgeTypeClass.SMUDGE.NONE then
                --         map_cell.SmudgeType = self.Type
                --         map_cell.SmudgeData = 0
                --     elseif map_cell.SmudgeType == self.Type then
                --         -- Stack craters (max 4 deep)
                --         if map_cell.SmudgeData < 4 then
                --             map_cell.SmudgeData = map_cell.SmudgeData + 1
                --         end
                --     end
                -- else
                --     -- Non-craters just replace
                --     map_cell.SmudgeType = self.Type
                --     map_cell.SmudgeData = i - 1  -- Frame index
                -- end
                --
                -- -- Set owner for bibs
                -- if self.Class.IsBib and self.OwnerHouse >= 0 then
                --     map_cell.Owner = self.OwnerHouse
                -- end
                --
                -- -- Mark cell for redraw
                -- map_cell.Flag.IsRedraw = true
            end
        end

        -- Smudge is now stamped into cells - destroy the object
        self:Limbo()
        self.IsActive = false

        return true

    elseif mark_type == ObjectClass.MARK.UP then
        -- Smudges can't be removed via Mark
        -- They persist until the cell is modified
        return false
    end

    return false
end

--[[
    Draw the smudge (not used - smudges are cell data).
    @param x - Screen X position
    @param y - Screen Y position
    @param window - Window to draw in
]]
function SmudgeClass:Draw_It(x, y, window)
    -- Smudges are drawn as part of cell rendering, not as objects
end

--[[
    Disown smudge from a cell (remove ownership).
    @param cell - Cell to disown
]]
function SmudgeClass:Disown(cell)
    -- In full implementation:
    -- Map[cell].Owner = HOUSE_NONE
end

--============================================================================
-- File I/O
--============================================================================

--[[
    Serialize smudge for saving.
    @return table of save data
]]
function SmudgeClass:Save()
    return {
        Type = self.Type,
        Coord = self.Coord,
        OwnerHouse = self.OwnerHouse,
    }
end

--[[
    Load smudge from save data.
    @param file - File to load from
    @return true if successful
]]
function SmudgeClass:Load(file)
    -- Implementation would read binary save data
    return true
end

--[[
    Convert object pointers to indices for saving.
]]
function SmudgeClass:Code_Pointers()
    ObjectClass.Code_Pointers(self)
end

--[[
    Convert indices back to object pointers after loading.
]]
function SmudgeClass:Decode_Pointers()
    ObjectClass.Decode_Pointers(self)
end

--============================================================================
-- INI I/O
--============================================================================

--[[
    Read smudge objects from INI file.
    @param buffer - INI data
]]
function SmudgeClass.Read_INI(buffer)
    -- Would parse [SMUDGE] section
    -- Format: cell=SmudgeType,data
    -- Example: 1234=CR1,0
end

--[[
    Write smudge objects to INI file.
    @param buffer - INI buffer to write to
]]
function SmudgeClass.Write_INI(buffer)
    -- Would write [SMUDGE] section
end

--[[
    Get INI section name.
    @return "SMUDGE"
]]
function SmudgeClass.INI_Name()
    return "SMUDGE"
end

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the smudge system.
]]
function SmudgeClass.Init()
    -- Initialize type classes
    SmudgeTypeClass.Init()
end

--============================================================================
-- Factory Functions
--============================================================================

--[[
    Create a crater at a cell.
    Used by explosion code to create battle damage.

    @param cell - Cell to place crater at
    @return true if crater was placed
]]
function SmudgeClass.Create_Crater(cell)
    local crater_type = SmudgeTypeClass.Random_Crater()
    local coord = Coord.Cell_Coord(cell)

    local smudge = SmudgeClass:new(crater_type, coord)
    if smudge then
        smudge:Mark(ObjectClass.MARK.DOWN)
        return true
    end
    return false
end

--[[
    Create a scorch mark at a cell.
    Used by fire/explosion code to create battle damage.

    @param cell - Cell to place scorch at
    @return true if scorch was placed
]]
function SmudgeClass.Create_Scorch(cell)
    local scorch_type = SmudgeTypeClass.Random_Scorch()
    local coord = Coord.Cell_Coord(cell)

    local smudge = SmudgeClass:new(scorch_type, coord)
    if smudge then
        smudge:Mark(ObjectClass.MARK.DOWN)
        return true
    end
    return false
end

--[[
    Create a building bib at a cell.
    Used when buildings are placed.

    @param bib_type - BIB1, BIB2, or BIB3
    @param cell - Cell to place bib at
    @param house - Owning house
    @return true if bib was placed
]]
function SmudgeClass.Create_Bib(bib_type, cell, house)
    local coord = Coord.Cell_Coord(cell)

    SmudgeClass.ToOwn = house or -1
    local smudge = SmudgeClass:new(bib_type, coord, house)
    SmudgeClass.ToOwn = -1

    if smudge then
        smudge:Mark(ObjectClass.MARK.DOWN)
        return true
    end
    return false
end

--============================================================================
-- Debug Support
--============================================================================

function SmudgeClass:Debug_Dump()
    print("SmudgeClass:")
    print(string.format("  Type: %d (%s)", self.Type,
        self.Class and self.Class.Name or "unknown"))
    print(string.format("  Coord: 0x%08X", self.Coord or 0))
    print(string.format("  OwnerHouse: %d", self.OwnerHouse))

    if self.Class then
        print(string.format("  IsBib: %s  IsCrater: %s",
            tostring(self.Class.IsBib), tostring(self.Class.IsCrater)))
        print(string.format("  Dimensions: %dx%d", self.Class.Width, self.Class.Height))
    end

    -- Call parent
    ObjectClass.Debug_Dump(self)
end

--============================================================================
-- Validation
--============================================================================

--[[
    Validate the smudge object's integrity.
    @return Non-zero if valid
]]
function SmudgeClass:Validate()
    if not self.Class then
        return 0
    end
    if self.Type < 0 or self.Type >= SmudgeTypeClass.SMUDGE.COUNT then
        return 0
    end
    return 1
end

return SmudgeClass
