--[[
    TerrainClass - Terrain objects (trees, rocks)

    Port of TERRAIN.H/CPP from the original C&C source.

    Terrain objects are large sprites that sit on the map and can be
    interacted with. They differ from overlays in that they have depth
    and can take damage.

    Features:
    - Trees: Can catch fire, burn, and crumble when destroyed
    - Blossom Trees: Transform and spawn tiberium
    - Rocks: Indestructible obstacles

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TERRAIN.H
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local StageClass = require("src.objects.mixins.stage")
local TerrainTypeClass = require("src.objects.types.terraintype")
local Coord = require("src.core.coord")
local Target = require("src.core.target")

-- Create TerrainClass extending ObjectClass with StageClass mixin
local TerrainClass = Class.extend(ObjectClass, "TerrainClass")
Class.include(TerrainClass, StageClass)

--============================================================================
-- RTTI
--============================================================================

TerrainClass.RTTI = 10  -- RTTI_TERRAIN

--============================================================================
-- Static Variables
--============================================================================

-- VTable pointer (for save/load compatibility)
TerrainClass.VTable = nil

--============================================================================
-- Constructor
--============================================================================

function TerrainClass:init(terrain_type, cell)
    -- Call parent constructor
    ObjectClass.init(self)

    -- Initialize StageClass mixin
    StageClass.init(self)

    -- Get type class
    if type(terrain_type) == "number" then
        self.Class = TerrainTypeClass.Create(terrain_type)
        self.Type = terrain_type
    else
        self.Class = terrain_type
        self.Type = terrain_type and terrain_type.Type or TerrainTypeClass.TERRAIN.NONE
    end

    -- Initialize state flags
    self.IsOnFire = false       -- Currently burning
    self.IsCrumbling = false    -- Crumble animation in progress
    self.IsBlossoming = false   -- Transforming into blossom tree
    self.IsBarnacled = false    -- Has tiberium growth
    self.IsSporing = false      -- Spawning tiberium spores

    -- Set initial strength from type
    if self.Class then
        self.Strength = self.Class.MaxStrength
    else
        self.Strength = 1
    end

    self.IsActive = true

    -- Place on map if cell provided
    if cell and cell >= 0 then
        local coord = Coord.Cell_Coord(cell)
        self:Unlimbo(coord, 0)  -- DIR_N
    end
end

--============================================================================
-- Identification
--============================================================================

function TerrainClass:What_Am_I()
    return TerrainClass.RTTI
end

function TerrainClass:Class_Of()
    return self.Class
end

--============================================================================
-- Coordinate Functions
--============================================================================

--[[
    Get the center coordinate of this terrain object.
    @return COORDINATE of center
]]
function TerrainClass:Center_Coord()
    return self.Coord
end

--[[
    Get the render coordinate (upper left corner).
    @return COORDINATE for rendering
]]
function TerrainClass:Render_Coord()
    return self.Coord
end

--[[
    Get the Y-sorting coordinate.
    Uses the CenterBase offset from the type to determine render order.
    @return COORDINATE for sorting
]]
function TerrainClass:Sort_Y()
    if self.Class and self.Class.CenterBase then
        return Coord.Coord_Add(self.Coord, self.Class.CenterBase)
    end
    return self.Coord
end

--[[
    Get the target coordinate (for AI targeting).
    @return COORDINATE
]]
function TerrainClass:Target_Coord()
    return self:Sort_Y()
end

--============================================================================
-- Map Presence
--============================================================================

--[[
    Place terrain object on the map.
    @param coord - Coordinate to place at
    @param dir - Facing direction (unused for terrain)
    @return true if successful
]]
function TerrainClass:Unlimbo(coord, dir)
    -- Fix coordinate to cell alignment
    if self.Class then
        coord = self.Class:Coord_Fixup(coord)
    end

    if not ObjectClass.Unlimbo(self, coord, dir or 0) then
        return false
    end

    -- Terrain is always on GROUND layer
    self.Layer = ObjectClass.LAYER.GROUND

    return true
end

--[[
    Remove terrain object from the map.
    @return true if successful
]]
function TerrainClass:Limbo()
    return ObjectClass.Limbo(self)
end

--[[
    Mark terrain for cell occupancy.
    @param mark_type - MARK.UP, MARK.DOWN, MARK.CHANGE
    @return true if successful
]]
function TerrainClass:Mark(mark_type)
    if not self:Is_Active() or self.IsInLimbo then
        return false
    end

    if not ObjectClass.Mark(self, mark_type) then
        return false
    end

    -- Get occupy list from type
    local occupy = self.Class and self.Class:Occupy_List() or {0}
    local cell = Coord.Coord_Cell(self.Coord)

    for _, offset in ipairs(occupy) do
        local target_cell = cell + offset

        if mark_type == ObjectClass.MARK.DOWN then
            -- Mark cell as occupied by terrain
            -- In full implementation: Map[target_cell].Flag.IsOccupied = true
            -- Map[target_cell].Occupy_Terrain(self)
        elseif mark_type == ObjectClass.MARK.UP then
            -- Clear cell occupation
            -- In full implementation: Map[target_cell].Flag.IsOccupied = false
            -- Map[target_cell].Release_Terrain(self)
        end
    end

    return true
end

--[[
    Check if terrain can enter a cell (always false - terrain doesn't move).
    @param cell - Target cell
    @param facing - Movement direction
    @return MOVE_NO
]]
function TerrainClass:Can_Enter_Cell(cell, facing)
    return 0  -- MOVE_NO - terrain doesn't move
end

--============================================================================
-- Combat
--============================================================================

--[[
    Handle damage to the terrain.
    @param damage - Amount of damage (modified in place)
    @param distance - Distance from explosion center
    @param warhead - Warhead type
    @param source - Attacking unit (TechnoClass)
    @return ResultType (NONE, LIGHT, HALF, DESTROYED)
]]
function TerrainClass:Take_Damage(damage, distance, warhead, source)
    -- Check if this terrain can be damaged
    if not self.Class or not self.Class.IsDestroyable then
        return ObjectClass.RESULT.NONE
    end

    -- Can't damage what's already crumbling
    if self.IsCrumbling then
        return ObjectClass.RESULT.NONE
    end

    -- Apply damage through parent
    local result = ObjectClass.Take_Damage(self, damage, distance, warhead, source)

    -- Check for fire
    if result ~= ObjectClass.RESULT.NONE then
        if self.Class.IsFlammable and not self.IsOnFire then
            -- Chance to catch fire based on damage
            if math.random(0, 3) == 0 then
                self:Catch_Fire()
            end
        end

        -- Check for destruction
        if result == ObjectClass.RESULT.DESTROYED or self.Strength <= 0 then
            self:Start_To_Crumble()
            return ObjectClass.RESULT.DESTROYED
        end
    end

    return result
end

--[[
    Make the terrain catch fire.
    @return true if fire started
]]
function TerrainClass:Catch_Fire()
    if not self.Class or not self.Class.IsFlammable then
        return false
    end

    if self.IsOnFire then
        return false
    end

    self.IsOnFire = true

    -- Start fire animation
    -- In full implementation: would spawn fire AnimClass attached to this object
    -- AnimClass.new(ANIM_BURN, self:Target_Coord())

    return true
end

--[[
    Fire has burned out.
]]
function TerrainClass:Fire_Out()
    self.IsOnFire = false

    -- If fire burned it down, start crumbling
    if self.Strength <= 0 and self.Class and self.Class.IsDestroyable then
        self:Start_To_Crumble()
    end
end

--[[
    Start the crumbling/falling animation.
]]
function TerrainClass:Start_To_Crumble()
    if self.IsCrumbling then
        return
    end

    self.IsCrumbling = true

    -- Start crumble animation
    self:Set_Rate(2)  -- Fast animation
    self:Set_Stage(0)

    -- Mark for redraw
    self.IsToDisplay = true
end

--[[
    Convert terrain to a TARGET value.
    @return TARGET value
]]
function TerrainClass:As_Target()
    return Target.Build_Target(TerrainClass.RTTI, self)
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for terrain each game tick.
]]
function TerrainClass:AI()
    -- Call parent AI
    ObjectClass.AI(self)

    -- Process stage animation
    if StageClass.Graphic_Logic(self) then
        self.IsToDisplay = true
    end

    -- Handle crumbling animation
    if self.IsCrumbling then
        -- Check if crumble animation is complete
        local max_stage = 6  -- Typical crumble animation length
        if self:Fetch_Stage() >= max_stage then
            -- Destroy the terrain object
            self:Limbo()
            self.IsActive = false
            return
        end
    end

    -- Handle fire damage over time
    if self.IsOnFire then
        -- Fire does damage each tick
        local fire_damage = 1
        self.Strength = self.Strength - fire_damage
        if self.Strength <= 0 then
            self:Fire_Out()
        end
    end

    -- Handle tiberium spawning (blossom trees)
    if self.Class and self.Class.IsTiberiumSpawn and self.IsBarnacled then
        -- Would spawn tiberium in adjacent cells
        -- This is handled by the tiberium growth system
    end
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Draw the terrain object.
    @param x - Screen X position
    @param y - Screen Y position
    @param window - Window to draw in
]]
function TerrainClass:Draw_It(x, y, window)
    if not self.Class then
        return
    end

    local frame = 0

    if self.IsCrumbling then
        -- Use crumble animation frame
        frame = self:Fetch_Stage() + 1  -- Frame 0 is normal, 1+ is crumbling
    elseif self.IsBlossoming then
        -- Use blossom animation frame
        frame = self:Fetch_Stage()
    end

    -- In full implementation: would draw the sprite
    -- Shape_Draw(self.Class.ShapeFile, frame, x, y, window)
end

--[[
    Get radar icon for this terrain at a specific cell.
    @param cell - Cell to get icon for
    @return Radar color data or nil
]]
function TerrainClass:Radar_Icon(cell)
    -- Terrain shows as dark green on radar (trees) or gray (rocks)
    if self.Class then
        if self.Class.IsFlammable then
            return {0, 0.4, 0}  -- Dark green for trees
        else
            return {0.5, 0.5, 0.5}  -- Gray for rocks
        end
    end
    return nil
end

--============================================================================
-- User Actions
--============================================================================

--[[
    Called when terrain is clicked as a target.
    @param house - House that clicked
    @param count - Click count
]]
function TerrainClass:Clicked_As_Target(house, count)
    -- Terrain doesn't respond to being targeted
end

--============================================================================
-- File I/O
--============================================================================

--[[
    Serialize terrain for saving.
    @return table of save data
]]
function TerrainClass:Save()
    return {
        Type = self.Type,
        Coord = self.Coord,
        Strength = self.Strength,
        IsOnFire = self.IsOnFire,
        IsCrumbling = self.IsCrumbling,
        IsBlossoming = self.IsBlossoming,
        IsBarnacled = self.IsBarnacled,
        IsSporing = self.IsSporing,
        Stage = self:Fetch_Stage(),
        StageTimer = self.StageTimer,
        Rate = self.Rate,
    }
end

--[[
    Load terrain from save data.
    @param file - File to load from
    @return true if successful
]]
function TerrainClass:Load(file)
    -- Implementation would read binary save data
    return true
end

--[[
    Convert object pointers to indices for saving.
]]
function TerrainClass:Code_Pointers()
    ObjectClass.Code_Pointers(self)
    StageClass.Code_Pointers_Stage(self)
end

--[[
    Convert indices back to object pointers after loading.
]]
function TerrainClass:Decode_Pointers()
    ObjectClass.Decode_Pointers(self)
end

--============================================================================
-- INI I/O
--============================================================================

--[[
    Read terrain objects from INI file.
    @param buffer - INI data
]]
function TerrainClass.Read_INI(buffer)
    -- Would parse [TERRAIN] section
    -- Format: cell=TerrainType
    -- Example: 1234=T01
end

--[[
    Write terrain objects to INI file.
    @param buffer - INI buffer to write to
]]
function TerrainClass.Write_INI(buffer)
    -- Would write [TERRAIN] section
end

--[[
    Get INI section name.
    @return "TERRAIN"
]]
function TerrainClass.INI_Name()
    return "TERRAIN"
end

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the terrain system.
]]
function TerrainClass.Init()
    -- Initialize type classes
    TerrainTypeClass.Init()
end

--============================================================================
-- Debug Support
--============================================================================

function TerrainClass:Debug_Dump()
    print("TerrainClass:")
    print(string.format("  Type: %d (%s)", self.Type,
        self.Class and self.Class.Name or "unknown"))
    print(string.format("  Coord: 0x%08X", self.Coord or 0))
    print(string.format("  Strength: %d/%d", self.Strength,
        self.Class and self.Class.MaxStrength or 0))
    print(string.format("  IsOnFire: %s  IsCrumbling: %s",
        tostring(self.IsOnFire), tostring(self.IsCrumbling)))
    print(string.format("  IsBlossoming: %s  IsBarnacled: %s  IsSporing: %s",
        tostring(self.IsBlossoming), tostring(self.IsBarnacled), tostring(self.IsSporing)))

    -- Call mixin debug
    StageClass.Debug_Dump_Stage(self)

    -- Call parent
    ObjectClass.Debug_Dump(self)
end

--============================================================================
-- Validation
--============================================================================

--[[
    Validate the terrain object's integrity.
    @return Non-zero if valid
]]
function TerrainClass:Validate()
    if not self.Class then
        return 0
    end
    if self.Type < 0 or self.Type >= TerrainTypeClass.TERRAIN.COUNT then
        return 0
    end
    return 1
end

return TerrainClass
