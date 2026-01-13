--[[
    Combat System - Explosion and damage functions

    Port of COMBAT.CPP from the original C&C source.

    This module provides the core explosion damage functions:
    - Explosion_Damage(): Apply radius damage from explosions
    - Modify_Damage(): Calculate damage with armor modifiers

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/COMBAT.CPP
]]

local Combat = {}

-- Lazy-loaded dependencies
local Coord = nil
local Target = nil
local Globals = nil
local WarheadTypeClass = nil
local AnimClass = nil
local AnimTypeClass = nil

-- Constants from DEFINES.H
local ICON_LEPTON_W = 256  -- Leptons per cell width
local FACING_COUNT = 8     -- 8 directions

-- Direction offsets for adjacent cells
local ADJACENT_OFFSETS = {
    { 0, -1},   -- FACING_N
    { 1, -1},   -- FACING_NE
    { 1,  0},   -- FACING_E
    { 1,  1},   -- FACING_SE
    { 0,  1},   -- FACING_S
    {-1,  1},   -- FACING_SW
    {-1,  0},   -- FACING_W
    {-1, -1},   -- FACING_NW
}

--[[
    Initialize lazy-loaded dependencies.
]]
local function init_deps()
    if not Coord then
        Coord = require("src.core.coord")
        Target = require("src.core.target")
        Globals = require("src.heap.globals")
        WarheadTypeClass = require("src.combat.warhead")
    end
end

--[[
    Inflict explosion damage in a radius around a coordinate.
    Port of Explosion_Damage() from COMBAT.CPP

    This function:
    1. Scans the impact cell and all 8 adjacent cells
    2. Collects all objects that can be damaged
    3. Applies distance-based damage to each object

    @param coord - COORDINATE of explosion center (ground zero)
    @param strength - Raw damage points at ground zero
    @param source - TechnoClass that caused the explosion (for kill credit)
    @param warhead - WarheadType enum value
]]
function Combat.Explosion_Damage(coord, strength, source, warhead)
    init_deps()

    -- Early out if no damage or no warhead
    if not strength or strength <= 0 then return end
    if not warhead or warhead < 0 then return end

    -- Get warhead definition
    local whead = WarheadTypeClass.Get(warhead)
    if not whead then
        whead = WarheadTypeClass.Create(warhead)
    end

    -- Damage effect radius (1.5 cells in leptons)
    local range = ICON_LEPTON_W + math.floor(ICON_LEPTON_W / 2)

    -- Get the cell at impact point
    local cell = Coord.Coord_Cell(coord)
    local cell_x = Coord.Cell_X(cell)
    local cell_y = Coord.Cell_Y(cell)

    -- Collect objects to damage (max 32 per original)
    local objects = {}
    local count = 0
    local max_objects = 32

    -- Mark objects so we don't double-damage
    local damaged_set = {}

    -- Scan center cell and 8 adjacent cells
    local cells_to_scan = {
        {cell_x, cell_y}  -- Center cell first
    }

    -- Add adjacent cells
    for _, offset in ipairs(ADJACENT_OFFSETS) do
        table.insert(cells_to_scan, {cell_x + offset[1], cell_y + offset[2]})
    end

    -- Scan each cell for objects
    for _, cell_pos in ipairs(cells_to_scan) do
        if count >= max_objects then break end

        local cx, cy = cell_pos[1], cell_pos[2]

        -- Skip invalid cells (would check map bounds)
        if cx >= 0 and cy >= 0 and cx < 64 and cy < 64 then
            -- Scan all object heaps for objects at this cell
            local rtti_list = {
                Target.RTTI.INFANTRY,
                Target.RTTI.UNIT,
                Target.RTTI.BUILDING,
                Target.RTTI.AIRCRAFT,
            }

            for _, rtti in ipairs(rtti_list) do
                local heap = Globals.Get_Heap(rtti)
                if heap then
                    for i = 1, heap:Count() do
                        if count >= max_objects then break end

                        local obj = heap:Get(i)
                        if obj and obj.IsActive and not obj.IsInLimbo then
                            -- Check if object is in this cell
                            local obj_coord = obj:Center_Coord()
                            local obj_cell = Coord.Coord_Cell(obj_coord)
                            local obj_x = Coord.Cell_X(obj_cell)
                            local obj_y = Coord.Cell_Y(obj_cell)

                            if obj_x == cx and obj_y == cy then
                                -- Don't damage source or already-marked objects
                                local obj_id = tostring(obj)
                                if obj ~= source and not damaged_set[obj_id] then
                                    damaged_set[obj_id] = true
                                    table.insert(objects, obj)
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Apply damage to collected objects
    for _, obj in ipairs(objects) do
        -- Calculate distance from explosion center
        local obj_coord = obj:Center_Coord()
        local distance = Coord.Distance(coord, obj_coord)

        -- Apply damage with distance falloff
        if obj.Take_Damage then
            obj:Take_Damage(strength, distance, warhead, source)
        end
    end

    -- Handle special warhead effects
    if whead then
        -- Destroy tiberium at impact
        if whead.IsTiberiumDestroyer then
            Combat.Destroy_Tiberium(cell_x, cell_y)
        end

        -- Destroy walls at impact
        if whead.IsWallDestroyer or whead.IsWoodDestroyer then
            Combat.Destroy_Wall(cell_x, cell_y, whead.IsWallDestroyer)
        end
    end
end

--[[
    Destroy tiberium at a cell location.

    @param cell_x - Cell X coordinate
    @param cell_y - Cell Y coordinate
]]
function Combat.Destroy_Tiberium(cell_x, cell_y)
    -- Would remove tiberium overlay from cell
    -- TODO: Integrate with OverlayClass and CellClass
end

--[[
    Destroy wall at a cell location.

    @param cell_x - Cell X coordinate
    @param cell_y - Cell Y coordinate
    @param concrete - Can destroy concrete walls
]]
function Combat.Destroy_Wall(cell_x, cell_y, concrete)
    -- Would damage/destroy wall overlay at cell
    -- TODO: Integrate with OverlayClass and CellClass
end

--[[
    Create an explosion animation and deal damage.
    Convenience function that spawns anim and applies damage.

    @param coord - COORDINATE of explosion
    @param strength - Raw damage points
    @param source - Source of damage (for kill credit)
    @param warhead - WarheadType enum value
    @param anim_type - AnimType for explosion visual (optional)
]]
function Combat.Do_Explosion(coord, strength, source, warhead, anim_type)
    init_deps()

    -- Spawn explosion animation
    if anim_type and anim_type >= 0 then
        if not AnimClass then
            AnimClass = require("src.objects.anim")
            AnimTypeClass = require("src.objects.types.animtype")
        end

        -- Create animation at impact point
        local anim = AnimClass:new(anim_type)
        if anim then
            anim:Unlimbo(coord, 0)
        end
    end

    -- Apply explosion damage
    Combat.Explosion_Damage(coord, strength, source, warhead)
end

--[[
    Calculate the damage value at a specific distance from the explosion.
    Port of Modify_Damage distance calculation from COMBAT.CPP

    @param damage - Base damage value
    @param distance - Distance from impact in leptons
    @param warhead - WarheadType for spread factor
    @return Modified damage value
]]
function Combat.Distance_Modify(damage, distance, warhead)
    init_deps()

    if damage <= 0 then return 0 end
    if distance <= 0 then return damage end

    local whead = WarheadTypeClass.Get(warhead)
    if not whead then return damage end

    -- Use warhead's spread factor for falloff
    -- Higher spread = slower falloff
    local spread = whead.SpreadFactor or 4
    local shifted_dist = math.floor(distance / math.pow(2, spread))
    shifted_dist = math.min(shifted_dist, 16)  -- Cap at 16

    -- Right-shift damage by shifted distance
    damage = math.floor(damage / math.pow(2, shifted_dist))

    return damage
end

return Combat
