--[[
    AircraftTypeClass - Type class for aircraft units

    Port of TYPE.H AircraftTypeClass from the original C&C source.

    This class extends TechnoTypeClass to add aircraft-specific properties:
    - Flight properties (rotor, fixed wing)
    - Landing capability
    - Ammunition
    - Rate of turn in flight

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/ADATA.CPP
]]

local Class = require("src.objects.class")
local TechnoTypeClass = require("src.objects.types.technotype")

-- Create AircraftTypeClass extending TechnoTypeClass
local AircraftTypeClass = Class.extend(TechnoTypeClass, "AircraftTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Aircraft type identifiers
AircraftTypeClass.AIRCRAFT = {
    NONE = -1,
    TRANSPORT = 0,  -- Chinook transport helicopter
    A10 = 1,        -- A-10 Warthog attack plane
    HELICOPTER = 2, -- Attack helicopter (Apache for GDI, Orca for Nod later)
    CARGO = 3,      -- Cargo plane (drops reinforcements)
    ORCA = 4,       -- Orca VTOL attack craft
    COUNT = 5,
}

-- Landing behavior types
AircraftTypeClass.LANDING = {
    NONE = 0,       -- Cannot land
    HELIPAD = 1,    -- Lands on helipad only
    RUNWAY = 2,     -- Requires runway (fixed wing)
    ANYWHERE = 3,   -- Can land anywhere (VTOL)
}

-- Aircraft dimensions
AircraftTypeClass.AIRCRAFT_SIZE = {
    WIDTH = 24,
    HEIGHT = 24,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new AircraftTypeClass.

    @param ini_name - The INI control name (e.g., "HELI")
    @param name - The full display name (e.g., "Apache")
]]
function AircraftTypeClass:init(ini_name, name)
    -- Call parent constructor
    TechnoTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Aircraft Type Identifier
    --========================================================================

    --[[
        The specific aircraft type.
    ]]
    self.Type = AircraftTypeClass.AIRCRAFT.NONE

    --========================================================================
    -- Flight Properties
    --========================================================================

    --[[
        Is this a fixed-wing aircraft (vs rotorcraft)?
        Fixed wing cannot hover, must maintain forward movement.
    ]]
    self.IsFixedWing = false

    --[[
        Does this have a visible rotor?
        Affects animation.
    ]]
    self.IsRotorEquipped = true

    --[[
        Can this aircraft land on helipads/buildings?
    ]]
    self.IsLandable = true

    --[[
        Is this a VTOL (Vertical Take-Off and Landing) aircraft?
        VTOLs can hover and land anywhere.
    ]]
    self.IsVTOL = true

    --[[
        Can this aircraft transport units?
    ]]
    self.IsTransportAircraft = false

    --[[
        Landing type for this aircraft.
    ]]
    self.LandingType = AircraftTypeClass.LANDING.HELIPAD

    --========================================================================
    -- Combat Properties
    --========================================================================

    --[[
        Maximum ammunition carried.
        -1 = unlimited
    ]]
    -- MaxAmmo already defined in TechnoTypeClass

    --[[
        Rate of turn in the air (higher = faster).
    ]]
    self.FlightROT = 5

    --[[
        Cruising altitude in leptons.
    ]]
    self.CruiseAltitude = 256

    --[[
        Strafing run count (for attack passes).
    ]]
    self.StrafeRuns = 1

    --========================================================================
    -- Visual Properties
    --========================================================================

    --[[
        Number of body rotation frames (typically 32).
    ]]
    self.BodyFrames = 32

    --[[
        Number of rotor animation frames.
    ]]
    self.RotorFrames = 4

    --========================================================================
    -- Default Aircraft Properties
    --========================================================================

    -- Aircraft are always selectable
    self.IsSelectable = true
    self.IsLegalTarget = true

    -- Default aircraft sight range (higher for recon)
    self.SightRange = 4

    -- Fixed dimensions for aircraft
    self.Width = AircraftTypeClass.AIRCRAFT_SIZE.WIDTH
    self.Height = AircraftTypeClass.AIRCRAFT_SIZE.HEIGHT

    -- Default flight speed
    self.MaxSpeed = TechnoTypeClass.MPH.FAST
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this is a fixed-wing aircraft.
]]
function AircraftTypeClass:Is_Fixed_Wing()
    return self.IsFixedWing
end

--[[
    Check if this has rotor animation.
]]
function AircraftTypeClass:Is_Rotor_Equipped()
    return self.IsRotorEquipped
end

--[[
    Check if this can land.
]]
function AircraftTypeClass:Can_Land()
    return self.IsLandable
end

--[[
    Check if this is VTOL capable.
]]
function AircraftTypeClass:Is_VTOL()
    return self.IsVTOL
end

--[[
    Check if this can transport units.
]]
function AircraftTypeClass:Can_Transport()
    return self.IsTransportAircraft
end

--[[
    Get the landing type.
]]
function AircraftTypeClass:Get_Landing_Type()
    return self.LandingType
end

--[[
    Get the flight rate of turn.
]]
function AircraftTypeClass:Get_Flight_ROT()
    return self.FlightROT
end

--[[
    Get the cruising altitude.
]]
function AircraftTypeClass:Get_Cruise_Altitude()
    return self.CruiseAltitude
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined aircraft type.

    @param type - AircraftType enum value
    @return New AircraftTypeClass instance
]]
function AircraftTypeClass.Create(type)
    local aircraft = nil

    if type == AircraftTypeClass.AIRCRAFT.TRANSPORT then
        aircraft = AircraftTypeClass:new("TRAN", "Chinook")
        aircraft.Type = type
        aircraft.Cost = 1500
        aircraft.MaxStrength = 127
        aircraft.SightRange = 4
        aircraft.MaxSpeed = TechnoTypeClass.MPH.MEDIUM
        aircraft.Primary = TechnoTypeClass.WEAPON.NONE
        aircraft.IsRotorEquipped = true
        aircraft.IsTransportAircraft = true
        aircraft.IsTransporter = true
        aircraft.LandingType = AircraftTypeClass.LANDING.HELIPAD
        aircraft.FlightROT = 5
        aircraft.CruiseAltitude = 256
        aircraft.MaxAmmo = -1
        aircraft.Risk = 0
        aircraft.Reward = 15
        aircraft.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == AircraftTypeClass.AIRCRAFT.A10 then
        aircraft = AircraftTypeClass:new("A10", "A-10")
        aircraft.Type = type
        aircraft.Cost = 0  -- Not buildable
        aircraft.MaxStrength = 50
        aircraft.SightRange = 5
        aircraft.MaxSpeed = TechnoTypeClass.MPH.BLAZING
        aircraft.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        aircraft.IsFixedWing = true
        aircraft.IsRotorEquipped = false
        aircraft.IsLandable = false
        aircraft.IsVTOL = false
        aircraft.LandingType = AircraftTypeClass.LANDING.NONE
        aircraft.FlightROT = 8
        aircraft.CruiseAltitude = 384
        aircraft.StrafeRuns = 3
        aircraft.MaxAmmo = 9
        aircraft.IsBuildable = false
        aircraft.Risk = 0
        aircraft.Reward = 0
        aircraft.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == AircraftTypeClass.AIRCRAFT.HELICOPTER then
        aircraft = AircraftTypeClass:new("HELI", "Apache")
        aircraft.Type = type
        aircraft.Cost = 1200
        aircraft.MaxStrength = 125
        aircraft.SightRange = 4
        aircraft.MaxSpeed = TechnoTypeClass.MPH.FAST
        aircraft.Primary = TechnoTypeClass.WEAPON.CHAINGUN
        aircraft.IsRotorEquipped = true
        aircraft.LandingType = AircraftTypeClass.LANDING.HELIPAD
        aircraft.FlightROT = 6
        aircraft.CruiseAltitude = 256
        aircraft.MaxAmmo = 15
        aircraft.Risk = 7
        aircraft.Reward = 20
        aircraft.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == AircraftTypeClass.AIRCRAFT.CARGO then
        aircraft = AircraftTypeClass:new("C17", "C-17")
        aircraft.Type = type
        aircraft.Cost = 0  -- Not buildable
        aircraft.MaxStrength = 25
        aircraft.SightRange = 0
        aircraft.MaxSpeed = TechnoTypeClass.MPH.BLAZING
        aircraft.Primary = TechnoTypeClass.WEAPON.NONE
        aircraft.IsFixedWing = true
        aircraft.IsRotorEquipped = false
        aircraft.IsLandable = false
        aircraft.IsVTOL = false
        aircraft.IsTransportAircraft = true
        aircraft.LandingType = AircraftTypeClass.LANDING.NONE
        aircraft.FlightROT = 4
        aircraft.CruiseAltitude = 512
        aircraft.MaxAmmo = -1
        aircraft.IsBuildable = false
        aircraft.Risk = 0
        aircraft.Reward = 0
        aircraft.Armor = 2  -- ARMOR_ALUMINUM

    elseif type == AircraftTypeClass.AIRCRAFT.ORCA then
        aircraft = AircraftTypeClass:new("ORCA", "Orca")
        aircraft.Type = type
        aircraft.Cost = 1200
        aircraft.MaxStrength = 125
        aircraft.SightRange = 4
        aircraft.MaxSpeed = TechnoTypeClass.MPH.FAST
        aircraft.Primary = TechnoTypeClass.WEAPON.ROCKET
        aircraft.IsRotorEquipped = false  -- VTOL, no rotor graphics
        aircraft.LandingType = AircraftTypeClass.LANDING.HELIPAD
        aircraft.FlightROT = 6
        aircraft.CruiseAltitude = 256
        aircraft.IsTwoShooter = true
        aircraft.MaxAmmo = 6
        aircraft.Risk = 7
        aircraft.Reward = 20
        aircraft.Armor = 2  -- ARMOR_ALUMINUM

    else
        -- Default/unknown type
        aircraft = AircraftTypeClass:new("AIR", "Aircraft")
        aircraft.Type = type
    end

    return aircraft
end

--============================================================================
-- Debug Support
--============================================================================

local LANDING_NAMES = {
    [0] = "NONE",
    [1] = "HELIPAD",
    [2] = "RUNWAY",
    [3] = "ANYWHERE",
}

function AircraftTypeClass:Debug_Dump()
    TechnoTypeClass.Debug_Dump(self)

    print(string.format("AircraftTypeClass: Type=%d LandingType=%s",
        self.Type,
        LANDING_NAMES[self.LandingType] or "?"))

    print(string.format("  Flight: FixedWing=%s Rotor=%s VTOL=%s Landable=%s",
        tostring(self.IsFixedWing),
        tostring(self.IsRotorEquipped),
        tostring(self.IsVTOL),
        tostring(self.IsLandable)))

    print(string.format("  FlightROT=%d CruiseAlt=%d StrafeRuns=%d",
        self.FlightROT,
        self.CruiseAltitude,
        self.StrafeRuns))
end

return AircraftTypeClass
