--[[
    OverlayClass - Overlay objects (tiberium, walls, crates)

    Port of OVERLAY.H/CPP from the original C&C source.

    Overlays are flat objects that sit on top of terrain cells.
    They have no depth and control the icon rendered as the
    cell's bottommost layer.

    Types of overlays:
    - Tiberium (12 growth stages)
    - Walls (sandbags, chain-link, concrete, barbed wire, wooden)
    - Crates (wooden, steel - contain goodies)
    - Roads and concrete
    - Decorative fields

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/OVERLAY.H
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local OverlayTypeClass = require("src.objects.types.overlaytype")
local Coord = require("src.core.coord")

-- Create OverlayClass extending ObjectClass
local OverlayClass = Class.extend(ObjectClass, "OverlayClass")

--============================================================================
-- RTTI
--============================================================================

OverlayClass.RTTI = 8  -- RTTI_OVERLAY

--============================================================================
-- Static Variables
--============================================================================

-- House to assign ownership when placed
OverlayClass.ToOwn = -1  -- HOUSE_NONE

--============================================================================
-- Constructor
--============================================================================

function OverlayClass:init(overlay_type, cell, house)
    -- Call parent constructor
    ObjectClass.init(self)

    -- Get type class
    if type(overlay_type) == "number" then
        self.Class = OverlayTypeClass.Create(overlay_type)
        self.Type = overlay_type
    else
        self.Class = overlay_type
        self.Type = overlay_type and overlay_type.Type or OverlayTypeClass.OVERLAY.NONE
    end

    -- Set owner house
    self.OwnerHouse = house or -1  -- HOUSE_NONE

    -- Initialize state
    self.Strength = 1
    self.IsActive = true

    -- Place on map if cell provided
    if cell and cell >= 0 then
        local x, y = Coord.Cell_X(cell), Coord.Cell_Y(cell)
        local coord = Coord.XY_Coord(x * 256 + 128, y * 256 + 128)  -- Center of cell
        self:Unlimbo(coord, 0)
    end
end

--============================================================================
-- Identification
--============================================================================

function OverlayClass:What_Am_I()
    return OverlayClass.RTTI
end

function OverlayClass:Class_Of()
    return self.Class
end

--============================================================================
-- Type Helpers
--============================================================================

--[[
    Check if this is tiberium.
]]
function OverlayClass:Is_Tiberium()
    return self.Class and self.Class.IsTiberium
end

--[[
    Check if this is a wall.
]]
function OverlayClass:Is_Wall()
    return self.Class and self.Class.IsWall
end

--[[
    Check if this is a crate.
]]
function OverlayClass:Is_Crate()
    return self.Class and self.Class.IsCrate
end

--[[
    Get the tiberium value of this overlay.
]]
function OverlayClass:Tiberium_Value()
    if not self:Is_Tiberium() then
        return 0
    end
    return OverlayTypeClass.Tiberium_Value(self.Type)
end

--============================================================================
-- Map Placement
--============================================================================

--[[
    Mark the overlay on the map.

    @param mark_type - MARK.UP, MARK.DOWN, MARK.CHANGE
    @return true if successful
]]
function OverlayClass:Mark(mark_type)
    if not ObjectClass.Mark(self, mark_type) then
        return false
    end

    local cell = Coord.Coord_Cell(self.Coord)

    if mark_type == ObjectClass.MARK.DOWN then
        -- Place overlay on map
        -- In full implementation, would update cell overlay data
        -- Map[cell].Overlay = self.Type
        -- Map[cell].OverlayData = 0  -- Frame/stage

        -- Assign ownership if needed
        if OverlayClass.ToOwn >= 0 and self:Is_Wall() then
            -- Map[cell].Owner = OverlayClass.ToOwn
        end

    elseif mark_type == ObjectClass.MARK.UP then
        -- Remove overlay from map
        -- Map[cell].Overlay = OVERLAY_NONE
        -- Map[cell].OverlayData = 0
    end

    return true
end

--[[
    Remove from the map and enter limbo.
]]
function OverlayClass:Limbo()
    if not self.IsInLimbo then
        self:Mark(ObjectClass.MARK.UP)
    end
    return ObjectClass.Limbo(self)
end

--[[
    Place on the map from limbo.

    @param coord - COORDINATE to place at
    @param facing - Initial facing direction (unused for overlays)
    @return true if successful
]]
function OverlayClass:Unlimbo(coord, facing)
    if ObjectClass.Unlimbo(self, coord, facing) then
        self:Mark(ObjectClass.MARK.DOWN)
        return true
    end
    return false
end

--============================================================================
-- Rendering
--============================================================================

function OverlayClass:Draw_It(x, y, window)
    -- Overlays don't draw themselves - the cell draws them
    -- This is intentionally empty per the original
end

--============================================================================
-- Wall Damage
--============================================================================

--[[
    Apply damage to a wall overlay.

    @param damage - Amount of damage
    @param warhead - Warhead type (unused)
    @return true if wall was destroyed
]]
function OverlayClass:Take_Wall_Damage(damage)
    if not self:Is_Wall() then
        return false
    end

    local type_class = self.Class
    if not type_class then
        return false
    end

    -- Check if damage exceeds damage points threshold
    if damage < type_class.DamagePoints then
        return false
    end

    -- Reduce strength
    self.Strength = self.Strength - 1

    if self.Strength <= 0 then
        -- Wall destroyed
        self:Limbo()
        return true
    end

    -- Wall damaged but not destroyed
    -- In full implementation, would update visual frame
    return false
end

--============================================================================
-- Tiberium Operations
--============================================================================

--[[
    Grow tiberium to next stage.

    @return New OverlayType or nil if at max
]]
function OverlayClass:Grow_Tiberium()
    if not self:Is_Tiberium() then
        return nil
    end

    local O = OverlayTypeClass.OVERLAY
    if self.Type < O.TIBERIUM12 then
        self.Type = self.Type + 1
        self.Class = OverlayTypeClass.Create(self.Type)
        return self.Type
    end

    return nil  -- Already at max
end

--[[
    Harvest tiberium from this cell.

    @return Value harvested, or 0 if not tiberium
]]
function OverlayClass:Harvest_Tiberium()
    if not self:Is_Tiberium() then
        return 0
    end

    local value = self:Tiberium_Value()

    -- Remove the tiberium
    self:Limbo()

    return value
end

--============================================================================
-- Crate Operations
--============================================================================

--[[
    Open a crate and get contents.

    @param opener - Unit/infantry that opened the crate
    @return Crate contents type and value
]]
function OverlayClass:Open_Crate(opener)
    if not self:Is_Crate() then
        return nil, 0
    end

    -- Remove crate
    self:Limbo()

    -- Determine contents (randomized in full implementation)
    -- Possible contents: money, unit, cloaking, armor, speed, etc.
    local O = OverlayTypeClass.OVERLAY
    if self.Type == O.STEEL_CRATE then
        -- Steel crates give better rewards
        return "MONEY", 2000
    else
        -- Wood crates give standard rewards
        return "MONEY", 500
    end
end

--============================================================================
-- Wall Shape
--============================================================================

--[[
    Calculate wall shape based on adjacent walls.
    Walls connect to adjacent walls of the same type.

    @return Shape frame index (0-15 for 4-direction connectivity)
]]
function OverlayClass:Wall_Shape()
    if not self:Is_Wall() then
        return 0
    end

    -- In full implementation, check adjacent cells for matching walls
    -- and compute bitmask: N=1, E=2, S=4, W=8
    -- For now, return standalone wall shape
    return 0
end

--============================================================================
-- Save/Load
--============================================================================

function OverlayClass:Code_Pointers()
    local data = ObjectClass.Code_Pointers(self)
    data.Type = self.Type
    data.OwnerHouse = self.OwnerHouse
    return data
end

function OverlayClass:Decode_Pointers(data)
    ObjectClass.Decode_Pointers(self, data)
    if data then
        self.Type = data.Type or OverlayTypeClass.OVERLAY.NONE
        self.Class = OverlayTypeClass.Create(self.Type)
        self.OwnerHouse = data.OwnerHouse or -1
    end
end

--============================================================================
-- Debug
--============================================================================

function OverlayClass:Debug_Dump()
    local type_name = self.Class and self.Class.Name or "unknown"
    print(string.format("OverlayClass: Type=%s(%d) Tiberium=%s Wall=%s Crate=%s",
        type_name,
        self.Type,
        tostring(self:Is_Tiberium()),
        tostring(self:Is_Wall()),
        tostring(self:Is_Crate())
    ))
    ObjectClass.Debug_Dump(self)
end

return OverlayClass
