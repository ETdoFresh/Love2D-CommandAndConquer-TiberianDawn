--[[
    TechnoTypeClass - Type class for combat/producible objects

    Port of TYPE.H TechnoTypeClass from the original C&C source.

    This class extends ObjectTypeClass to add:
    - Production properties (cost, prerequisites, build time)
    - Combat properties (weapons, ammo, sight range)
    - Ownership (which houses can build/own this)
    - Special capabilities (turret, transporter, crew, etc.)

    TechnoTypeClass is the parent for:
    - BuildingTypeClass
    - UnitTypeClass
    - InfantryTypeClass
    - AircraftTypeClass

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
]]

local Class = require("src.objects.class")
local ObjectTypeClass = require("src.objects.types.objecttype")

-- Create TechnoTypeClass extending ObjectTypeClass
local TechnoTypeClass = Class.extend(ObjectTypeClass, "TechnoTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Weapon types (simplified for now)
TechnoTypeClass.WEAPON = {
    NONE = -1,
    MACHINEGUN = 0,
    CHAINGUN = 1,
    CANNON = 2,
    MISSILE = 3,
    ROCKET = 4,
    LASER = 5,
    FLAMER = 6,
    GRENADE = 7,
    OBELISK = 8,
    -- Add more as needed
}

-- Speed types (MPH = Map units Per Hour equivalent)
TechnoTypeClass.MPH = {
    IMMOBILE = 0,
    VERY_SLOW = 5,
    SLOW = 10,
    MEDIUM_SLOW = 15,
    MEDIUM = 20,
    MEDIUM_FAST = 25,
    FAST = 30,
    VERY_FAST = 40,
    BLAZING = 50,
}

-- Building prerequisites (bitfield)
TechnoTypeClass.PREREQ = {
    NONE = 0x0000,
    POWER = 0x0001,        -- Power plant required
    BARRACKS = 0x0002,     -- Barracks required
    FACTORY = 0x0004,      -- War factory required
    RADAR = 0x0008,        -- Radar required
    TECH = 0x0010,         -- Tech center required
    HELIPAD = 0x0020,      -- Helipad required
    REFINERY = 0x0040,     -- Refinery required
    REPAIR = 0x0080,       -- Repair bay required
    ADVANCED_POWER = 0x0100,  -- Advanced power required
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new TechnoTypeClass.

    @param ini_name - The INI control name
    @param name - The full display name
]]
function TechnoTypeClass:init(ini_name, name)
    -- Call parent constructor
    ObjectTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Combat Capability Flags
    --========================================================================

    --[[
        Is this a good leader for groups?
        AI prefers these units to lead teams.
    ]]
    self.IsLeader = false

    --[[
        Can this unit detect cloaked enemies?
    ]]
    self.IsScanner = false

    --[[
        Does this use a proper name (e.g., "Nod Buggy") rather
        than generic ("Light Tank")?
    ]]
    self.IsNominal = false

    --[[
        Does this have a rotating turret?
    ]]
    self.IsTurretEquipped = false

    --[[
        Does this fire two shots in quick succession?
    ]]
    self.IsTwoShooter = false

    --[[
        Can this be repaired at repair bay?
    ]]
    self.IsRepairable = false

    --[[
        Can this be built normally (appears in sidebar)?
    ]]
    self.IsBuildable = true

    --[[
        Does this contain a crew (may eject infantry on death)?
    ]]
    self.IsCrew = false

    --[[
        Is this a transport (can carry other units)?
    ]]
    self.IsTransporter = false

    --[[
        Is this cloakable?
    ]]
    self.IsCloakable = false

    --[[
        Is this invisible to radar?
    ]]
    self.IsInvisible = false

    --[[
        Uses theater-specific artwork?
    ]]
    self.IsTheater = false

    --========================================================================
    -- Production Properties
    --========================================================================

    --[[
        Production cost in credits.
    ]]
    self.Cost = 0

    --[[
        First scenario this becomes available (1-15).
        0 means available from start.
    ]]
    self.Scenario = 0

    --[[
        Tech level required to build this (1-10).
    ]]
    self.Level = 1

    --[[
        Building prerequisites (bitfield of PREREQ).
    ]]
    self.Prerequisites = TechnoTypeClass.PREREQ.NONE

    --[[
        Bitfield of which houses can own this.
        Each bit corresponds to a house (0=GDI, 1=NOD, etc.)
    ]]
    self.Ownable = 0xFFFF  -- All houses by default

    --========================================================================
    -- Combat Properties
    --========================================================================

    --[[
        Sight range in cells.
    ]]
    self.SightRange = 2

    --[[
        Maximum speed.
    ]]
    self.MaxSpeed = TechnoTypeClass.MPH.IMMOBILE

    --[[
        Maximum ammo (-1 = unlimited).
    ]]
    self.MaxAmmo = -1

    --[[
        Primary weapon type.
    ]]
    self.Primary = TechnoTypeClass.WEAPON.NONE

    --[[
        Secondary weapon type.
    ]]
    self.Secondary = TechnoTypeClass.WEAPON.NONE

    --========================================================================
    -- AI Properties
    --========================================================================

    --[[
        Risk value for AI pathfinding.
        Higher = more risky to attack.
    ]]
    self.Risk = 0

    --[[
        Reward value for AI targeting.
        Higher = more valuable to destroy.
    ]]
    self.Reward = 0

    --========================================================================
    -- Visual Properties
    --========================================================================

    --[[
        Cameo (small icon) for sidebar display.
    ]]
    self.CameoData = nil

    --[[
        Rate of turn (ROT) for rotation speed.
        Higher = faster turning.
    ]]
    self.ROT = 5

    --[[
        Number of frames in firing animation.
    ]]
    self.FireFrames = 0
end

--============================================================================
-- Production
--============================================================================

--[[
    Get the raw base cost before house modifiers.
]]
function TechnoTypeClass:Raw_Cost()
    return self.Cost
end

--[[
    Get the production cost (may be modified by house).
]]
function TechnoTypeClass:Cost_Of()
    return self.Cost
end

--[[
    Set the production cost.

    @param cost - Cost in credits
]]
function TechnoTypeClass:Set_Cost(cost)
    self.Cost = math.max(0, cost or 0)
end

--[[
    Get the build time in ticks.
    Formula: Cost / 5 (roughly)

    @param house - HousesType for house-specific modifiers
    @return Build time in game ticks
]]
function TechnoTypeClass:Time_To_Build(house)
    -- Base formula: cost / 5
    local time = math.floor(self.Cost / 5)

    -- Minimum build time
    return math.max(15, time)
end

--[[
    Check if this can be built with current prerequisites.

    @param prereqs_met - Bitfield of met prerequisites
    @return true if can be built
]]
function TechnoTypeClass:Can_Build(prereqs_met)
    if not self.IsBuildable then
        return false
    end

    return bit.band(self.Prerequisites, prereqs_met) == self.Prerequisites
end

--============================================================================
-- Ownership
--============================================================================

--[[
    Get which houses can own this type.
]]
function TechnoTypeClass:Get_Ownable()
    return self.Ownable
end

--[[
    Set which houses can own this type.

    @param ownable - Bitfield of allowed houses
]]
function TechnoTypeClass:Set_Ownable(ownable)
    self.Ownable = ownable or 0xFFFF
end

--============================================================================
-- Combat Properties
--============================================================================

--[[
    Get sight range in cells.
]]
function TechnoTypeClass:Get_Sight_Range()
    return self.SightRange
end

--[[
    Set sight range.

    @param range - Range in cells
]]
function TechnoTypeClass:Set_Sight_Range(range)
    self.SightRange = math.max(0, range or 0)
end

--[[
    Get maximum speed.
]]
function TechnoTypeClass:Get_Max_Speed()
    return self.MaxSpeed
end

--[[
    Set maximum speed.

    @param speed - Speed value
]]
function TechnoTypeClass:Set_Max_Speed(speed)
    self.MaxSpeed = speed or TechnoTypeClass.MPH.IMMOBILE
end

--[[
    Get primary weapon type.
]]
function TechnoTypeClass:Get_Primary_Weapon()
    return self.Primary
end

--[[
    Get secondary weapon type.
]]
function TechnoTypeClass:Get_Secondary_Weapon()
    return self.Secondary
end

--[[
    Check if this has any weapons.
]]
function TechnoTypeClass:Is_Armed()
    return self.Primary ~= TechnoTypeClass.WEAPON.NONE or
           self.Secondary ~= TechnoTypeClass.WEAPON.NONE
end

--============================================================================
-- Transport
--============================================================================

--[[
    Get maximum passengers (for transports).
    Override in derived classes.
]]
function TechnoTypeClass:Max_Passengers()
    if self.IsTransporter then
        return 5  -- Default capacity
    end
    return 0
end

--============================================================================
-- Repair
--============================================================================

--[[
    Get the repair cost per step.
    Default is 1/3 of original cost for full repair.
]]
function TechnoTypeClass:Repair_Cost()
    return math.floor(self.Cost / (3 * self:Repair_Step()))
end

--[[
    Get the repair step (health restored per repair tick).
]]
function TechnoTypeClass:Repair_Step()
    -- About 10 steps to full repair
    return math.max(1, math.floor(self.MaxStrength / 10))
end

--============================================================================
-- Cameo
--============================================================================

--[[
    Get the cameo (sidebar icon) data.
]]
function TechnoTypeClass:Get_Cameo_Data()
    return self.CameoData
end

--[[
    Set the cameo data.

    @param data - Cameo image data/path
]]
function TechnoTypeClass:Set_Cameo_Data(data)
    self.CameoData = data
end

--============================================================================
-- Debug Support
--============================================================================

function TechnoTypeClass:Debug_Dump()
    ObjectTypeClass.Debug_Dump(self)

    print(string.format("TechnoTypeClass: Cost=%d Speed=%d Sight=%d",
        self.Cost,
        self.MaxSpeed,
        self.SightRange))

    print(string.format("  Weapons: Primary=%d Secondary=%d Ammo=%d",
        self.Primary,
        self.Secondary,
        self.MaxAmmo))

    print(string.format("  Flags: Turret=%s Transport=%s Crew=%s Scanner=%s",
        tostring(self.IsTurretEquipped),
        tostring(self.IsTransporter),
        tostring(self.IsCrew),
        tostring(self.IsScanner)))

    print(string.format("  Build: Level=%d Scenario=%d Prereqs=0x%04X Ownable=0x%04X",
        self.Level,
        self.Scenario,
        self.Prerequisites,
        self.Ownable))
end

return TechnoTypeClass
