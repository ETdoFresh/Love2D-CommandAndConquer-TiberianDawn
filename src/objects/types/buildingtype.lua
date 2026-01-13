--[[
    BuildingTypeClass - Type class for buildings/structures

    Port of TYPE.H BuildingTypeClass from the original C&C source.

    This class extends TechnoTypeClass to add building-specific properties:
    - Size and foundation
    - Power generation/consumption
    - Tiberium storage capacity
    - Factory production (what it can build)
    - Exit/entrance coordinates
    - Animation sequences (BState)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/BDATA.CPP
]]

local Class = require("src.objects.class")
local TechnoTypeClass = require("src.objects.types.technotype")

-- Create BuildingTypeClass extending TechnoTypeClass
local BuildingTypeClass = Class.extend(TechnoTypeClass, "BuildingTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Building type identifiers (matches STRUCTTYPE in DEFINES.H)
BuildingTypeClass.STRUCT = {
    NONE = -1,
    WEAP = 0,       -- Weapons Factory
    GTWR = 1,       -- Guard Tower
    ATWR = 2,       -- Advanced Guard Tower
    OBELISK = 3,    -- Obelisk of Light
    RADAR = 4,      -- Radar (both sides)
    TURRET = 5,     -- Gun Turret
    CONST = 6,      -- Construction Yard
    REFINERY = 7,   -- Tiberium Refinery
    STORAGE = 8,    -- Tiberium Silo
    HELIPAD = 9,    -- Helipad
    SAM = 10,       -- SAM Site
    AIRSTRIP = 11,  -- Airstrip (Nod)
    POWER = 12,     -- Power Plant
    ADVANCED_POWER = 13,  -- Advanced Power Plant
    HOSPITAL = 14,  -- Hospital
    BARRACKS = 15,  -- Barracks (GDI)
    TANKER = 16,    -- Tanker (never used?)
    REPAIR = 17,    -- Repair Bay
    BIO = 18,       -- Bio Research Lab
    HAND = 19,      -- Hand of Nod (Nod barracks)
    TEMPLE = 20,    -- Temple of Nod
    EYE = 21,       -- Eye (Communications Center)
    MISSION = 22,   -- Tech Center
    V01 = 23,       -- Civilian building 1
    V02 = 24,       -- Civilian building 2
    -- ... more civilian buildings
    COUNT = 40,
}

-- Building sizes (in cells)
BuildingTypeClass.SIZE = {
    ["1x1"] = { width = 1, height = 1 },
    ["2x1"] = { width = 2, height = 1 },
    ["1x2"] = { width = 1, height = 2 },
    ["2x2"] = { width = 2, height = 2 },
    ["3x2"] = { width = 3, height = 2 },
    ["2x3"] = { width = 2, height = 3 },
    ["3x3"] = { width = 3, height = 3 },
    ["4x2"] = { width = 4, height = 2 },
}

-- Factory types (what this building produces)
BuildingTypeClass.FACTORY = {
    NONE = 0,
    INFANTRY = 1,   -- Barracks, Hand of Nod
    UNIT = 2,       -- Weapons Factory
    AIRCRAFT = 3,   -- Helipad, Airstrip
    BUILDING = 4,   -- Construction Yard
}

-- BState animation types
BuildingTypeClass.BSTATE = {
    CONSTRUCTION = 0,
    IDLE = 1,
    ACTIVE = 2,
    FULL = 3,
    AUX1 = 4,
    AUX2 = 5,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new BuildingTypeClass.

    @param ini_name - The INI control name (e.g., "WEAP")
    @param name - The full display name (e.g., "Weapons Factory")
]]
function BuildingTypeClass:init(ini_name, name)
    -- Call parent constructor
    TechnoTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Building Type Identifier
    --========================================================================

    --[[
        The specific building type.
    ]]
    self.Type = BuildingTypeClass.STRUCT.NONE

    --========================================================================
    -- Size and Foundation
    --========================================================================

    --[[
        Size in cells (width x height).
    ]]
    self.SizeWidth = 1
    self.SizeHeight = 1

    --[[
        Foundation type (affects pathability).
    ]]
    self.FoundationType = "1x1"

    --[[
        Bib (concrete foundation) around building.
    ]]
    self.HasBib = false

    --========================================================================
    -- Power System
    --========================================================================

    --[[
        Power generated at full health.
        Positive = generation, Negative = consumption.
    ]]
    self.PowerOutput = 0

    --[[
        Power consumed (drain) at full health.
        This is the power this building needs.
    ]]
    self.PowerDrain = 0

    --========================================================================
    -- Storage
    --========================================================================

    --[[
        Tiberium storage capacity in credits.
    ]]
    self.TiberiumCapacity = 0

    --========================================================================
    -- Factory Production
    --========================================================================

    --[[
        Type of factory (what can be built here).
    ]]
    self.FactoryType = BuildingTypeClass.FACTORY.NONE

    --[[
        List of buildable type identifiers.
    ]]
    self.ToBuild = {}

    --========================================================================
    -- Entrance/Exit
    --========================================================================

    --[[
        Exit cell offset for produced units.
        Relative to building origin.
    ]]
    self.ExitCoord = { x = 0, y = 0 }

    --[[
        Rally point offset (where units gather).
    ]]
    self.RallyPoint = { x = 0, y = 0 }

    --========================================================================
    -- Building Flags
    --========================================================================

    --[[
        Can this building be captured by engineers?
    ]]
    self.IsCapturable = true

    --[[
        Is this a base defense (turret, SAM, etc.)?
    ]]
    self.IsBaseDefense = false

    --[[
        Can this building be sold?
    ]]
    self.IsSellable = true

    --[[
        Does this building have a rotating turret?
    ]]
    -- IsTurretEquipped already defined in TechnoTypeClass

    --[[
        Does this building require power to function?
    ]]
    self.RequiresPower = true

    --[[
        Is this a civilian building (not buildable)?
    ]]
    self.IsCivilian = false

    --[[
        Is this building unseen to enemy radar?
    ]]
    self.IsStealthable = false

    --[[
        Can aircraft land on this building?
    ]]
    self.IsHelipad = false

    --[[
        Does this provide radar capability?
    ]]
    self.IsRadar = false

    --========================================================================
    -- Animation Control
    --========================================================================

    --[[
        Animation data for each BState.
        Each entry has:
        - Start: Starting frame
        - Count: Number of frames
        - Rate: Animation rate
    ]]
    self.AnimControls = {}
    for i = 0, 5 do
        self.AnimControls[i] = {
            Start = 0,
            Count = 1,
            Rate = 0,
        }
    end

    --========================================================================
    -- Default Building Properties
    --========================================================================

    -- Buildings are always selectable and targetable
    self.IsSelectable = true
    self.IsLegalTarget = true

    -- Buildings are immobile
    self.MaxSpeed = TechnoTypeClass.MPH.IMMOBILE

    -- Default building sight range
    self.SightRange = 3

    -- Buildings are usually repairable
    self.IsRepairable = true
end

--============================================================================
-- Size Functions
--============================================================================

--[[
    Get building size in cells.
    @return width, height
]]
function BuildingTypeClass:Get_Size()
    return self.SizeWidth, self.SizeHeight
end

--[[
    Set building size.
    @param width - Width in cells
    @param height - Height in cells
]]
function BuildingTypeClass:Set_Size(width, height)
    self.SizeWidth = width or 1
    self.SizeHeight = height or 1
    self.FoundationType = string.format("%dx%d", self.SizeWidth, self.SizeHeight)
end

--[[
    Get the foundation list (list of occupied cells).
    @return Table of {x, y} offsets from origin
]]
function BuildingTypeClass:Get_Foundation()
    local foundation = {}
    for y = 0, self.SizeHeight - 1 do
        for x = 0, self.SizeWidth - 1 do
            table.insert(foundation, { x = x, y = y })
        end
    end
    return foundation
end

--============================================================================
-- Power Functions
--============================================================================

--[[
    Get power output at full health.
]]
function BuildingTypeClass:Get_Power_Output()
    return self.PowerOutput
end

--[[
    Get power drain (consumption).
]]
function BuildingTypeClass:Get_Power_Drain()
    return self.PowerDrain
end

--[[
    Check if this is a power plant.
]]
function BuildingTypeClass:Is_Power_Plant()
    return self.PowerOutput > 0
end

--============================================================================
-- Factory Functions
--============================================================================

--[[
    Get what factory type this is.
]]
function BuildingTypeClass:Get_Factory_Type()
    return self.FactoryType
end

--[[
    Check if this is a factory.
]]
function BuildingTypeClass:Is_Factory()
    return self.FactoryType ~= BuildingTypeClass.FACTORY.NONE
end

--[[
    Check if this can build infantry.
]]
function BuildingTypeClass:Can_Build_Infantry()
    return self.FactoryType == BuildingTypeClass.FACTORY.INFANTRY
end

--[[
    Check if this can build units.
]]
function BuildingTypeClass:Can_Build_Units()
    return self.FactoryType == BuildingTypeClass.FACTORY.UNIT
end

--[[
    Check if this can build aircraft.
]]
function BuildingTypeClass:Can_Build_Aircraft()
    return self.FactoryType == BuildingTypeClass.FACTORY.AIRCRAFT
end

--[[
    Check if this can build buildings.
]]
function BuildingTypeClass:Can_Build_Buildings()
    return self.FactoryType == BuildingTypeClass.FACTORY.BUILDING
end

--============================================================================
-- Animation Control
--============================================================================

--[[
    Set animation data for a BState.
    @param bstate - BState index
    @param start - Starting frame
    @param count - Number of frames
    @param rate - Animation rate
]]
function BuildingTypeClass:Set_Anim_Control(bstate, start, count, rate)
    if bstate >= 0 and bstate <= 5 then
        self.AnimControls[bstate] = {
            Start = start or 0,
            Count = count or 1,
            Rate = rate or 0,
        }
    end
end

--[[
    Get animation data for a BState.
    @param bstate - BState index
    @return Table with Start, Count, Rate
]]
function BuildingTypeClass:Get_Anim_Control(bstate)
    if bstate >= 0 and bstate <= 5 then
        return self.AnimControls[bstate]
    end
    return { Start = 0, Count = 1, Rate = 0 }
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined building type.

    @param type - StructType enum value
    @return New BuildingTypeClass instance
]]
function BuildingTypeClass.Create(type)
    local building = nil

    if type == BuildingTypeClass.STRUCT.CONST then
        building = BuildingTypeClass:new("FACT", "Construction Yard")
        building.Type = type
        building.Cost = 5000
        building.MaxStrength = 400
        building.SightRange = 3
        building:Set_Size(3, 3)
        building.HasBib = true
        building.PowerDrain = 15
        building.FactoryType = BuildingTypeClass.FACTORY.BUILDING
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 50
        building.Armor = 3  -- ARMOR_STEEL

    elseif type == BuildingTypeClass.STRUCT.POWER then
        building = BuildingTypeClass:new("NUKE", "Power Plant")
        building.Type = type
        building.Cost = 300
        building.MaxStrength = 200
        building.SightRange = 2
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerOutput = 100
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 10
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.ADVANCED_POWER then
        building = BuildingTypeClass:new("NUK2", "Advanced Power Plant")
        building.Type = type
        building.Cost = 700
        building.MaxStrength = 300
        building.SightRange = 2
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerOutput = 200
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.REFINERY then
        building = BuildingTypeClass:new("PROC", "Tiberium Refinery")
        building.Type = type
        building.Cost = 2000
        building.MaxStrength = 450
        building.SightRange = 4
        building:Set_Size(3, 2)
        building.HasBib = true
        building.PowerDrain = 40
        building.TiberiumCapacity = 1000
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 25
        building.Armor = 3  -- ARMOR_STEEL

    elseif type == BuildingTypeClass.STRUCT.STORAGE then
        building = BuildingTypeClass:new("SILO", "Tiberium Silo")
        building.Type = type
        building.Cost = 150
        building.MaxStrength = 150
        building.SightRange = 2
        building:Set_Size(1, 1)
        building.PowerDrain = 10
        building.TiberiumCapacity = 1500
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 5
        building.Armor = 1  -- ARMOR_WOOD

    elseif type == BuildingTypeClass.STRUCT.BARRACKS then
        building = BuildingTypeClass:new("PYLE", "Barracks")
        building.Type = type
        building.Cost = 300
        building.MaxStrength = 400
        building.SightRange = 3
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerDrain = 20
        building.FactoryType = BuildingTypeClass.FACTORY.INFANTRY
        building.IsCapturable = true
        building.ExitCoord = { x = 2, y = 1 }
        building.Risk = 0
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.HAND then
        building = BuildingTypeClass:new("HAND", "Hand of Nod")
        building.Type = type
        building.Cost = 300
        building.MaxStrength = 400
        building.SightRange = 3
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerDrain = 20
        building.FactoryType = BuildingTypeClass.FACTORY.INFANTRY
        building.IsCapturable = true
        building.ExitCoord = { x = 2, y = 1 }
        building.Risk = 0
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.WEAP then
        building = BuildingTypeClass:new("WEAP", "Weapons Factory")
        building.Type = type
        building.Cost = 2000
        building.MaxStrength = 200
        building.SightRange = 3
        building:Set_Size(3, 2)
        building.HasBib = true
        building.PowerDrain = 30
        building.FactoryType = BuildingTypeClass.FACTORY.UNIT
        building.IsCapturable = true
        building.ExitCoord = { x = 3, y = 1 }
        building.Risk = 0
        building.Reward = 30
        building.Armor = 3  -- ARMOR_STEEL

    elseif type == BuildingTypeClass.STRUCT.HELIPAD then
        building = BuildingTypeClass:new("HPAD", "Helipad")
        building.Type = type
        building.Cost = 1500
        building.MaxStrength = 400
        building.SightRange = 3
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerDrain = 10
        building.FactoryType = BuildingTypeClass.FACTORY.AIRCRAFT
        building.IsHelipad = true
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 20
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.AIRSTRIP then
        building = BuildingTypeClass:new("AFLD", "Airstrip")
        building.Type = type
        building.Cost = 2000
        building.MaxStrength = 500
        building.SightRange = 5
        building:Set_Size(4, 2)
        building.HasBib = true
        building.PowerDrain = 30
        building.FactoryType = BuildingTypeClass.FACTORY.AIRCRAFT
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 30
        building.Armor = 3  -- ARMOR_STEEL

    elseif type == BuildingTypeClass.STRUCT.RADAR then
        building = BuildingTypeClass:new("HQ", "Communications Center")
        building.Type = type
        building.Cost = 1000
        building.MaxStrength = 500
        building.SightRange = 10
        building:Set_Size(2, 2)
        building.HasBib = true
        building.PowerDrain = 40
        building.IsRadar = true
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 20
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.REPAIR then
        building = BuildingTypeClass:new("FIX", "Repair Bay")
        building.Type = type
        building.Cost = 1200
        building.MaxStrength = 400
        building.SightRange = 3
        building:Set_Size(3, 2)
        building.HasBib = true
        building.PowerDrain = 30
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.GTWR then
        building = BuildingTypeClass:new("GTWR", "Guard Tower")
        building.Type = type
        building.Cost = 500
        building.MaxStrength = 200
        building.SightRange = 3
        building:Set_Size(1, 1)
        building.PowerDrain = 10
        building.Primary = TechnoTypeClass.WEAPON.CHAINGUN
        building.IsBaseDefense = true
        building.IsCapturable = false
        building.IsSellable = true
        building.Risk = 3
        building.Reward = 10
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.ATWR then
        building = BuildingTypeClass:new("ATWR", "Advanced Guard Tower")
        building.Type = type
        building.Cost = 1000
        building.MaxStrength = 300
        building.SightRange = 4
        building:Set_Size(1, 2)
        building.PowerDrain = 20
        building.Primary = TechnoTypeClass.WEAPON.ROCKET
        building.IsBaseDefense = true
        building.IsCapturable = false
        building.Risk = 5
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.TURRET then
        building = BuildingTypeClass:new("GUN", "Gun Turret")
        building.Type = type
        building.Cost = 600
        building.MaxStrength = 200
        building.SightRange = 5
        building:Set_Size(1, 1)
        building.PowerDrain = 20
        building.Primary = TechnoTypeClass.WEAPON.CANNON
        building.IsBaseDefense = true
        building.IsTurretEquipped = true
        building.IsCapturable = false
        building.Risk = 4
        building.Reward = 12
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.OBELISK then
        building = BuildingTypeClass:new("OBLI", "Obelisk of Light")
        building.Type = type
        building.Cost = 1500
        building.MaxStrength = 200
        building.SightRange = 5
        building:Set_Size(1, 2)
        building.PowerDrain = 150
        building.Primary = TechnoTypeClass.WEAPON.OBELISK
        building.IsBaseDefense = true
        building.IsCapturable = false
        building.Risk = 8
        building.Reward = 20
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.SAM then
        building = BuildingTypeClass:new("SAM", "SAM Site")
        building.Type = type
        building.Cost = 750
        building.MaxStrength = 200
        building.SightRange = 5
        building:Set_Size(2, 1)
        building.PowerDrain = 20
        building.Primary = TechnoTypeClass.WEAPON.MISSILE
        building.IsBaseDefense = true
        building.IsTwoShooter = true
        building.IsCapturable = false
        building.Risk = 5
        building.Reward = 15
        building.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == BuildingTypeClass.STRUCT.TEMPLE then
        building = BuildingTypeClass:new("TMPL", "Temple of Nod")
        building.Type = type
        building.Cost = 3000
        building.MaxStrength = 1000
        building.SightRange = 5
        building:Set_Size(3, 3)
        building.HasBib = true
        building.PowerDrain = 200
        building.IsCapturable = true
        building.Risk = 0
        building.Reward = 50
        building.Armor = 3  -- ARMOR_STEEL

    else
        -- Default/unknown type
        building = BuildingTypeClass:new("BLDG", "Building")
        building.Type = type
    end

    return building
end

--============================================================================
-- Debug Support
--============================================================================

local FACTORY_NAMES = {
    [0] = "NONE",
    [1] = "INFANTRY",
    [2] = "UNIT",
    [3] = "AIRCRAFT",
    [4] = "BUILDING",
}

function BuildingTypeClass:Debug_Dump()
    TechnoTypeClass.Debug_Dump(self)

    print(string.format("BuildingTypeClass: Type=%d Size=%dx%d",
        self.Type,
        self.SizeWidth,
        self.SizeHeight))

    print(string.format("  Power: Output=%d Drain=%d",
        self.PowerOutput,
        self.PowerDrain))

    print(string.format("  Factory: Type=%s Capacity=%d",
        FACTORY_NAMES[self.FactoryType] or "?",
        self.TiberiumCapacity))

    print(string.format("  Flags: Capturable=%s Defense=%s Sellable=%s Helipad=%s",
        tostring(self.IsCapturable),
        tostring(self.IsBaseDefense),
        tostring(self.IsSellable),
        tostring(self.IsHelipad)))
end

return BuildingTypeClass
