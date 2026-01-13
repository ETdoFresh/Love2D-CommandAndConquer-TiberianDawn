--[[
    UnitTypeClass - Type class for ground vehicles

    Port of TYPE.H UnitTypeClass from the original C&C source.

    This class extends TechnoTypeClass to add unit-specific properties:
    - Speed type (tracked, wheeled, hover)
    - Harvester properties
    - Crusher ability
    - Turret offset
    - MCV deployment

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/UDATA.CPP
]]

local Class = require("src.objects.class")
local TechnoTypeClass = require("src.objects.types.technotype")

-- Create UnitTypeClass extending TechnoTypeClass
local UnitTypeClass = Class.extend(TechnoTypeClass, "UnitTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Unit type identifiers
UnitTypeClass.UNIT = {
    NONE = -1,
    HTANK = 0,      -- Mammoth Tank
    MTANK = 1,      -- Medium Tank
    LTANK = 2,      -- Light Tank
    STANK = 3,      -- Stealth Tank
    FTANK = 4,      -- Flame Tank
    VICE = 5,       -- Viceroid
    APC = 6,        -- Armored Personnel Carrier
    MLRS = 7,       -- Mobile Rocket Launcher
    JEEP = 8,       -- Hum-Vee
    BUGGY = 9,      -- Nod Buggy
    HARVESTER = 10, -- Tiberium Harvester
    ARTY = 11,      -- Artillery
    MSAM = 12,      -- Mobile SAM
    HOVER = 13,     -- Hovercraft
    MHQ = 14,       -- Mobile HQ
    GUNBOAT = 15,   -- Gunboat
    MCV = 16,       -- Mobile Construction Vehicle
    BIKE = 17,      -- Recon Bike
    TRIC = 18,      -- Triceratops
    TREX = 19,      -- Tyrannosaurus Rex
    RAPT = 20,      -- Velociraptor
    STEG = 21,      -- Stegosaurus
    COUNT = 22,
}

-- Speed types (affects pathfinding and terrain crossing)
UnitTypeClass.SPEED = {
    FOOT = 0,       -- Infantry (not used here)
    TRACKED = 1,    -- Tanks, APCs
    WHEELED = 2,    -- Light vehicles (faster on roads)
    WINGED = 3,     -- Aircraft (not used here)
    HOVER = 4,      -- Hovercraft (can cross water)
    FLOAT = 5,      -- Boats
}

-- Unit dimensions (standard for most units)
UnitTypeClass.UNIT_SIZE = {
    WIDTH = 24,
    HEIGHT = 24,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new UnitTypeClass.

    @param ini_name - The INI control name (e.g., "MTANK")
    @param name - The full display name (e.g., "Medium Tank")
]]
function UnitTypeClass:init(ini_name, name)
    -- Call parent constructor
    TechnoTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Unit Type Identifier
    --========================================================================

    --[[
        The specific unit type.
    ]]
    self.Type = UnitTypeClass.UNIT.NONE

    --========================================================================
    -- Movement Properties
    --========================================================================

    --[[
        Speed type determines pathfinding and terrain interaction.
    ]]
    self.SpeedType = UnitTypeClass.SPEED.TRACKED

    --[[
        Can this unit crush infantry and fences?
    ]]
    self.IsCrusher = false

    --[[
        Can this unit harvest tiberium?
    ]]
    self.IsHarvester = false

    --[[
        Does this unit have radar (shows on minimap)?
    ]]
    self.IsRadar = false

    --[[
        Can this unit rotate in place?
    ]]
    self.IsRotatingTurret = false

    --[[
        Can this unit be selected for auto-fire?
    ]]
    self.IsFireAnim = false

    --[[
        Is this a gigundo (large) unit?
    ]]
    self.IsGigundo = false

    --[[
        Does this unit use a constant animation?
    ]]
    self.IsAnimating = false

    --[[
        Can this unit be jammed (radar interference)?
    ]]
    self.IsJammable = false

    --[[
        Can this unit see invisible units?
    ]]
    self.IsNoFireWhileMoving = false

    --========================================================================
    -- Turret Properties
    --========================================================================

    --[[
        Offset from center for turret rendering (x, y pixels).
    ]]
    self.TurretOffset = { x = 0, y = 0 }

    --[[
        Number of turret animation frames.
    ]]
    self.TurretFrames = 0

    --========================================================================
    -- MCV/Deployment Properties
    --========================================================================

    --[[
        Can this unit deploy into a building?
    ]]
    self.IsDeployable = false

    --[[
        Building type to deploy into (for MCV).
    ]]
    self.DeployBuilding = nil

    --========================================================================
    -- Visual Properties
    --========================================================================

    --[[
        Number of body rotation frames (typically 32).
    ]]
    self.BodyFrames = 32

    --[[
        Frame rate for animated units.
    ]]
    self.AnimationRate = 0

    --========================================================================
    -- Default Unit Properties
    --========================================================================

    -- Units are always selectable
    self.IsSelectable = true
    self.IsLegalTarget = true

    -- Default unit sight range
    self.SightRange = 2

    -- Fixed dimensions for units
    self.Width = UnitTypeClass.UNIT_SIZE.WIDTH
    self.Height = UnitTypeClass.UNIT_SIZE.HEIGHT

    -- Units are usually repairable
    self.IsRepairable = true

    -- Units typically have crew
    self.IsCrew = true
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this is a harvester unit.
]]
function UnitTypeClass:Is_Harvester()
    return self.IsHarvester
end

--[[
    Check if this can crush infantry.
]]
function UnitTypeClass:Can_Crush()
    return self.IsCrusher
end

--[[
    Check if this can deploy.
]]
function UnitTypeClass:Can_Deploy()
    return self.IsDeployable
end

--[[
    Check if this is a wheeled vehicle.
]]
function UnitTypeClass:Is_Wheeled()
    return self.SpeedType == UnitTypeClass.SPEED.WHEELED
end

--[[
    Check if this is a tracked vehicle.
]]
function UnitTypeClass:Is_Tracked()
    return self.SpeedType == UnitTypeClass.SPEED.TRACKED
end

--[[
    Check if this can traverse water.
]]
function UnitTypeClass:Can_Hover()
    return self.SpeedType == UnitTypeClass.SPEED.HOVER
end

--[[
    Get the speed type for pathfinding.
]]
function UnitTypeClass:Get_Speed_Type()
    return self.SpeedType
end

--[[
    Get the turret offset for rendering.
]]
function UnitTypeClass:Get_Turret_Offset()
    return self.TurretOffset
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined unit type.

    @param type - UnitType enum value
    @return New UnitTypeClass instance
]]
function UnitTypeClass.Create(type)
    local unit = nil

    if type == UnitTypeClass.UNIT.HTANK then
        unit = UnitTypeClass:new("HTNK", "Mammoth Tank")
        unit.Type = type
        unit.Cost = 1500
        unit.MaxStrength = 600
        unit.SightRange = 4
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM_SLOW
        unit.Primary = TechnoTypeClass.WEAPON.CANNON
        unit.Secondary = TechnoTypeClass.WEAPON.MISSILE
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsCrusher = true
        unit.IsTurretEquipped = true
        unit.IsTwoShooter = true
        unit.Risk = 10
        unit.Reward = 30
        unit.ROT = 2
        unit.Armor = 3  -- ARMOR_STEEL

    elseif type == UnitTypeClass.UNIT.MTANK then
        unit = UnitTypeClass:new("MTNK", "Medium Tank")
        unit.Type = type
        unit.Cost = 800
        unit.MaxStrength = 400
        unit.SightRange = 3
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM
        unit.Primary = TechnoTypeClass.WEAPON.CANNON
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsCrusher = true
        unit.IsTurretEquipped = true
        unit.Risk = 6
        unit.Reward = 16
        unit.ROT = 3
        unit.Armor = 3  -- ARMOR_STEEL

    elseif type == UnitTypeClass.UNIT.LTANK then
        unit = UnitTypeClass:new("LTNK", "Light Tank")
        unit.Type = type
        unit.Cost = 600
        unit.MaxStrength = 300
        unit.SightRange = 3
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM_FAST
        unit.Primary = TechnoTypeClass.WEAPON.CANNON
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsCrusher = true
        unit.IsTurretEquipped = true
        unit.Risk = 5
        unit.Reward = 12
        unit.ROT = 4
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.STANK then
        unit = UnitTypeClass:new("STNK", "Stealth Tank")
        unit.Type = type
        unit.Cost = 900
        unit.MaxStrength = 110
        unit.SightRange = 4
        unit.MaxSpeed = TechnoTypeClass.MPH.FAST
        unit.Primary = TechnoTypeClass.WEAPON.ROCKET
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsCloakable = true
        unit.IsTwoShooter = true
        unit.Risk = 8
        unit.Reward = 24
        unit.ROT = 5
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.FTANK then
        unit = UnitTypeClass:new("FTNK", "Flame Tank")
        unit.Type = type
        unit.Cost = 800
        unit.MaxStrength = 300
        unit.SightRange = 3
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM
        unit.Primary = TechnoTypeClass.WEAPON.FLAMER
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsCrusher = true
        unit.Risk = 6
        unit.Reward = 16
        unit.ROT = 3
        unit.Armor = 3  -- ARMOR_STEEL

    elseif type == UnitTypeClass.UNIT.APC then
        unit = UnitTypeClass:new("APC", "APC")
        unit.Type = type
        unit.Cost = 700
        unit.MaxStrength = 200
        unit.SightRange = 3
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM_FAST
        unit.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsTransporter = true
        unit.IsCrusher = true
        unit.Risk = 4
        unit.Reward = 10
        unit.ROT = 4
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.MLRS then
        unit = UnitTypeClass:new("MSAM", "MLRS")
        unit.Type = type
        unit.Cost = 800
        unit.MaxStrength = 100
        unit.SightRange = 4
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM
        unit.Primary = TechnoTypeClass.WEAPON.ROCKET
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsTurretEquipped = true
        unit.IsTwoShooter = true
        unit.Risk = 7
        unit.Reward = 18
        unit.ROT = 5
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.JEEP then
        unit = UnitTypeClass:new("JEEP", "Hum-Vee")
        unit.Type = type
        unit.Cost = 400
        unit.MaxStrength = 150
        unit.SightRange = 2
        unit.MaxSpeed = TechnoTypeClass.MPH.FAST
        unit.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        unit.SpeedType = UnitTypeClass.SPEED.WHEELED
        unit.IsTurretEquipped = true
        unit.Risk = 3
        unit.Reward = 8
        unit.ROT = 5
        unit.Armor = 1  -- ARMOR_WOOD

    elseif type == UnitTypeClass.UNIT.BUGGY then
        unit = UnitTypeClass:new("BGGY", "Nod Buggy")
        unit.Type = type
        unit.Cost = 300
        unit.MaxStrength = 140
        unit.SightRange = 2
        unit.MaxSpeed = TechnoTypeClass.MPH.FAST
        unit.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        unit.SpeedType = UnitTypeClass.SPEED.WHEELED
        unit.Risk = 2
        unit.Reward = 6
        unit.ROT = 6
        unit.Armor = 1  -- ARMOR_WOOD

    elseif type == UnitTypeClass.UNIT.HARVESTER then
        unit = UnitTypeClass:new("HARV", "Harvester")
        unit.Type = type
        unit.Cost = 1400
        unit.MaxStrength = 600
        unit.SightRange = 2
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM_SLOW
        unit.Primary = TechnoTypeClass.WEAPON.NONE
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsHarvester = true
        unit.IsCrusher = true
        unit.Risk = 0
        unit.Reward = 20
        unit.ROT = 2
        unit.Armor = 3  -- ARMOR_STEEL

    elseif type == UnitTypeClass.UNIT.ARTY then
        unit = UnitTypeClass:new("ARTY", "Artillery")
        unit.Type = type
        unit.Cost = 450
        unit.MaxStrength = 75
        unit.SightRange = 4
        unit.MaxSpeed = TechnoTypeClass.MPH.SLOW
        unit.Primary = TechnoTypeClass.WEAPON.CANNON
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsNoFireWhileMoving = true
        unit.Risk = 6
        unit.Reward = 12
        unit.ROT = 3
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.MSAM then
        unit = UnitTypeClass:new("SAM", "Mobile SAM")
        unit.Type = type
        unit.Cost = 750
        unit.MaxStrength = 110
        unit.SightRange = 5
        unit.MaxSpeed = TechnoTypeClass.MPH.MEDIUM
        unit.Primary = TechnoTypeClass.WEAPON.MISSILE
        unit.SpeedType = UnitTypeClass.SPEED.WHEELED
        unit.IsTurretEquipped = true
        unit.IsTwoShooter = true
        unit.Risk = 6
        unit.Reward = 14
        unit.ROT = 5
        unit.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == UnitTypeClass.UNIT.MCV then
        unit = UnitTypeClass:new("MCV", "MCV")
        unit.Type = type
        unit.Cost = 5000
        unit.MaxStrength = 600
        unit.SightRange = 2
        unit.MaxSpeed = TechnoTypeClass.MPH.SLOW
        unit.Primary = TechnoTypeClass.WEAPON.NONE
        unit.SpeedType = UnitTypeClass.SPEED.TRACKED
        unit.IsDeployable = true
        unit.IsCrusher = true
        unit.Risk = 0
        unit.Reward = 50
        unit.ROT = 2
        unit.Armor = 3  -- ARMOR_STEEL

    elseif type == UnitTypeClass.UNIT.BIKE then
        unit = UnitTypeClass:new("BIKE", "Recon Bike")
        unit.Type = type
        unit.Cost = 500
        unit.MaxStrength = 160
        unit.SightRange = 3
        unit.MaxSpeed = TechnoTypeClass.MPH.VERY_FAST
        unit.Primary = TechnoTypeClass.WEAPON.ROCKET
        unit.SpeedType = UnitTypeClass.SPEED.WHEELED
        unit.IsTwoShooter = true
        unit.Risk = 4
        unit.Reward = 10
        unit.ROT = 6
        unit.Armor = 1  -- ARMOR_WOOD

    else
        -- Default/unknown type
        unit = UnitTypeClass:new("UNIT", "Unit")
        unit.Type = type
    end

    return unit
end

--============================================================================
-- Debug Support
--============================================================================

local SPEED_NAMES = {
    [0] = "FOOT",
    [1] = "TRACKED",
    [2] = "WHEELED",
    [3] = "WINGED",
    [4] = "HOVER",
    [5] = "FLOAT",
}

function UnitTypeClass:Debug_Dump()
    TechnoTypeClass.Debug_Dump(self)

    print(string.format("UnitTypeClass: Type=%d SpeedType=%s",
        self.Type,
        SPEED_NAMES[self.SpeedType] or "?"))

    print(string.format("  Flags: Crusher=%s Harvester=%s Deployable=%s Cloakable=%s",
        tostring(self.IsCrusher),
        tostring(self.IsHarvester),
        tostring(self.IsDeployable),
        tostring(self.IsCloakable)))

    print(string.format("  Turret: Offset=(%d,%d) Frames=%d",
        self.TurretOffset.x,
        self.TurretOffset.y,
        self.TurretFrames))
end

return UnitTypeClass
