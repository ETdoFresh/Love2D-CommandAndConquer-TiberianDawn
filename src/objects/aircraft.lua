--[[
    AircraftClass - Aircraft unit implementation

    Port of AIRCRAFT.H/CPP from the original C&C source.

    Aircraft are flying units that include:
    - Helicopters (Apache, Chinook, Orca)
    - Transport helicopters
    - A-10 Warthog bomber

    Key systems:
    - Flight physics (via FlyClass mixin)
    - Landing/Takeoff at helipads
    - Ammo/reloading at helipad
    - Transport cargo loading

    AircraftClass extends FootClass and incorporates FlyClass mixin.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/AIRCRAFT.H/CPP
]]

local Class = require("src.objects.class")
local FootClass = require("src.objects.foot")
local FlyClass = require("src.objects.drive.fly")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create AircraftClass extending FootClass
local AircraftClass = Class.extend(FootClass, "AircraftClass")

-- Include FlyClass mixin for flight physics
Class.include(AircraftClass, FlyClass)

--============================================================================
-- Constants
--============================================================================

-- Aircraft types (for identification)
AircraftClass.AIRCRAFT = {
    NONE = -1,
    TRANSPORT = 0,  -- Chinook transport helicopter
    A10 = 1,        -- A-10 Warthog attack plane
    HELICOPTER = 2, -- Attack helicopter (Apache/Orca)
    CARGO = 3,      -- Cargo plane (drops reinforcements)
}

-- Flight altitude for combat
AircraftClass.FLIGHT_LEVEL = 24  -- Leptons * 256 = standard altitude

-- Landing states
AircraftClass.LAND_STATE = {
    NONE = 0,       -- Not landing
    APPROACH = 1,   -- Approaching landing site
    DESCEND = 2,    -- Descending
    TOUCHDOWN = 3,  -- Touching down
    LANDED = 4,     -- Landed
}

-- Aircraft speed constants
AircraftClass.AIRCRAFT_SPEED = {
    SLOW = 3,       -- Transports
    MEDIUM = 5,     -- Helicopters
    FAST = 8,       -- Attack planes
}

--============================================================================
-- RTTI (Runtime Type Information)
--============================================================================

function AircraftClass:get_rtti()
    return Target.RTTI.AIRCRAFT
end

function AircraftClass:What_Am_I()
    return Target.RTTI.AIRCRAFT
end

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new AircraftClass.

    @param type - AircraftTypeClass defining this aircraft
    @param house - HouseClass owner
]]
function AircraftClass:init(type, house)
    -- Call parent constructor
    FootClass.init(self, house)

    -- Initialize FlyClass mixin
    FlyClass.init(self)

    -- Store type reference
    self.Class = type

    --[[
        Is this aircraft currently landing?
    ]]
    self.IsLanding = false

    --[[
        Is this aircraft currently taking off?
    ]]
    self.IsTakingOff = false

    --[[
        Current landing state for complex landing sequences.
    ]]
    self.LandState = AircraftClass.LAND_STATE.NONE

    --[[
        Target building (helipad) for landing.
    ]]
    self.LandingTarget = Target.TARGET_NONE

    --[[
        Ammunition carried (for attack aircraft).
    ]]
    self.Ammo = -1

    --[[
        Maximum ammunition from type.
    ]]
    self.MaxAmmo = -1

    --[[
        Fuel remaining (affects how long can stay airborne).
    ]]
    self.Fuel = 255

    --[[
        Timer for various aircraft operations.
    ]]
    self.AttackTimer = 0

    --[[
        Strafe run count for attack passes.
    ]]
    self.StrafeCount = 0

    --[[
        Body/rotor animation frame.
    ]]
    self.BodyFrame = 0

    -- Set initial type-based properties
    if type then
        self.MaxAmmo = type.MaxAmmo or -1
        self.Ammo = self.MaxAmmo

        -- Set VTOL capability for helicopters
        if type.IsVTOL then
            self.IsVTOL = true
        end

        -- Set initial flight speed from type
        if type.MaxSpeed then
            self:Fly_Speed(255, type.MaxSpeed)
        end
    end
end

--============================================================================
-- Type Access
--============================================================================

--[[
    Get the AircraftTypeClass for this aircraft.
]]
function AircraftClass:Techno_Type_Class()
    return self.Class
end

--[[
    Get the aircraft type class (alias).
]]
function AircraftClass:Class_Of()
    return self.Class
end

--============================================================================
-- Flight Control
--============================================================================

--[[
    Start takeoff from current position.
]]
function AircraftClass:Start_Takeoff()
    if not self:Is_Grounded() then
        return false
    end

    self.IsTakingOff = true
    self.IsLanding = false
    self.LandState = AircraftClass.LAND_STATE.NONE

    -- Start FlyClass takeoff
    self:Take_Off()

    return true
end

--[[
    Start landing at a target (helipad or position).

    @param target - TARGET to land at
]]
function AircraftClass:Start_Landing(target)
    if self:Is_Grounded() then
        return false
    end

    target = target or Target.TARGET_NONE

    self.IsLanding = true
    self.IsTakingOff = false
    self.LandingTarget = target
    self.LandState = AircraftClass.LAND_STATE.APPROACH

    -- Set target altitude to ground
    self:Set_Altitude(FlyClass.ALTITUDE.GROUND)

    return true
end

--[[
    Complete landing sequence.
]]
function AircraftClass:Complete_Landing()
    self.IsLanding = false
    self.LandState = AircraftClass.LAND_STATE.LANDED

    -- Stop flight
    self:Stop_Flight()

    -- Reload ammo if at helipad
    if Target.Is_Valid(self.LandingTarget) then
        local helipad = Target.As_Object(self.LandingTarget)
        if helipad then
            self:Reload_Ammo()
        end
    end
end

--[[
    Reload ammunition to maximum.
]]
function AircraftClass:Reload_Ammo()
    if self.MaxAmmo > 0 then
        self.Ammo = self.MaxAmmo
    end
end

--[[
    Check if aircraft needs to return to base (low ammo/fuel).
]]
function AircraftClass:Should_Return_To_Base()
    -- Out of ammo
    if self.MaxAmmo > 0 and self.Ammo <= 0 then
        return true
    end

    -- Low fuel
    if self.Fuel < 30 then
        return true
    end

    return false
end

--[[
    Find and return to nearest helipad.
]]
function AircraftClass:Return_To_Base()
    if not self.House then
        return false
    end

    -- Would search for nearest helipad
    -- local helipad = self.House:Find_Helipad()
    -- if helipad then
    --     self.LandingTarget = helipad:As_Target()
    --     self:Assign_Destination(self.LandingTarget)
    --     self:Assign_Mission(self.MISSION.ENTER)
    --     return true
    -- end

    return false
end

--============================================================================
-- Movement
--============================================================================

--[[
    Override movement for flight physics.

    @param headto - COORDINATE to move to
    @return true if movement started
]]
function AircraftClass:Start_Driver(headto)
    -- Aircraft must be airborne to move
    if self:Is_Grounded() then
        self:Start_Takeoff()
        return false  -- Can't start moving until airborne
    end

    return FootClass.Start_Driver(self, headto)
end

--[[
    Process per-cell entry for aircraft.
]]
function AircraftClass:Per_Cell_Process(center)
    -- Aircraft don't trigger normal cell processing
    -- They fly over everything

    if center then
        -- Fuel consumption
        if self.Fuel > 0 then
            self.Fuel = self.Fuel - 1
        end
    end
end

--[[
    Get the flight coordinate (includes altitude).
]]
function AircraftClass:Center_Coord()
    local coord = FootClass.Center_Coord(self)

    -- Add altitude to Z component
    -- (In 2D game, altitude affects rendering order)

    return coord
end

--[[
    Get the sort Y for rendering (accounts for altitude).
]]
function AircraftClass:Sort_Y()
    local y = FootClass.Sort_Y(self)

    -- Flying aircraft render above ground units
    if self:Is_Airborne() then
        y = y - self:Get_Altitude()
    end

    return y
end

--============================================================================
-- Combat
--============================================================================

--[[
    Check if can fire (must be airborne).
]]
function AircraftClass:Can_Fire(target, which)
    -- Must be airborne to fire (except for some VTOL)
    if not self:Is_Airborne() and not self.IsVTOL then
        return self.FIRE_ERROR.BUSY
    end

    return FootClass.Can_Fire(self, target, which)
end

--[[
    Fire at target.
]]
function AircraftClass:Fire_At(target, which)
    -- Consume ammo
    if self.Ammo > 0 then
        self.Ammo = self.Ammo - 1
    end

    return FootClass.Fire_At(self, target, which)
end

--[[
    Take damage - aircraft may crash when destroyed.
]]
function AircraftClass:Take_Damage(damage, distance, warhead, source)
    local result = FootClass.Take_Damage(self, damage, distance, warhead, source)

    -- If destroyed while airborne, crash
    if self.Strength <= 0 and self:Is_Airborne() then
        self:Crash()
    end

    return result
end

--[[
    Aircraft crash (destroyed while airborne).
]]
function AircraftClass:Crash()
    -- Would spawn crash animation
    -- and debris falling

    -- Kill cargo if transport
    if self:How_Many() > 0 then
        self:Kill_Cargo(nil)
    end
end

--============================================================================
-- Mission Implementations
--============================================================================

--[[
    Mission_Move - Flight movement.
]]
function AircraftClass:Mission_Move()
    -- Ensure airborne
    if self:Is_Grounded() then
        self:Start_Takeoff()
        return 1
    end

    -- If still taking off, wait
    if self:Is_Taking_Off() then
        return 1
    end

    return FootClass.Mission_Move(self)
end

--[[
    Mission_Attack - Attack run behavior.
]]
function AircraftClass:Mission_Attack()
    -- Check ammo
    if self.MaxAmmo > 0 and self.Ammo <= 0 then
        self:Return_To_Base()
        return 15
    end

    -- Ensure airborne
    if not self:Is_Airborne() then
        self:Start_Takeoff()
        return 1
    end

    -- Validate target
    if not Target.Is_Valid(self.TarCom) then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Move toward target if not in range
    if not self:In_Range(self.TarCom, 0) then
        self:Approach_Target()
        return 1
    end

    -- Fire at target
    self:Fire_At(self.TarCom, 0)

    return self:Rearm_Delay(false)
end

--[[
    Mission_Guard - Patrol area while guarding.
]]
function AircraftClass:Mission_Guard()
    -- Return to base if low on resources
    if self:Should_Return_To_Base() then
        self:Return_To_Base()
        return 15
    end

    -- Look for threats
    local threat = self:Greatest_Threat(0)
    if Target.Is_Valid(threat) then
        self:Assign_Target(threat)
        self:Assign_Mission(self.MISSION.ATTACK)
        return 1
    end

    -- Stay in orbit over current position
    -- (Would circle patrol pattern)

    return 15
end

--[[
    Mission_Enter - Land at helipad/building.
]]
function AircraftClass:Mission_Enter()
    if not Target.Is_Valid(self.NavCom) then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Get target coordinate
    local obj = Target.As_Object(self.NavCom)
    if not obj then
        self:Enter_Idle_Mode()
        return 15
    end

    local target_coord = obj:Center_Coord()
    local my_coord = self:Center_Coord()

    -- Check if we're above the landing pad
    local dist = Coord.Distance(my_coord, target_coord)
    if dist < 128 then  -- Close enough to land
        if not self.IsLanding then
            self:Start_Landing(self.NavCom)
        end

        -- Process landing state
        if self:Is_Grounded() then
            self:Complete_Landing()
            self:Enter_Idle_Mode()
        end

        return 1
    end

    -- Move toward landing pad
    return self:Mission_Move()
end

--[[
    Mission_Hunt - Actively seek enemies.
]]
function AircraftClass:Mission_Hunt()
    -- Check resources
    if self:Should_Return_To_Base() then
        self:Return_To_Base()
        return 15
    end

    -- Find targets
    local threat = self:Greatest_Threat(0)
    if Target.Is_Valid(threat) then
        self:Assign_Target(threat)
        self:Assign_Mission(self.MISSION.ATTACK)
        return 1
    end

    -- Move toward enemy base if no targets
    -- (Would need enemy base tracking)

    return 15
end

--============================================================================
-- Idle Mode
--============================================================================

--[[
    Enter idle mode.
]]
function AircraftClass:Enter_Idle_Mode(initial)
    -- Aircraft should return to base when idle
    if self:Is_Airborne() then
        self:Return_To_Base()
    else
        FootClass.Enter_Idle_Mode(self, initial)
    end
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for aircraft.
]]
function AircraftClass:AI()
    -- Call parent AI
    FootClass.AI(self)

    -- Process flight physics
    self:AI_Fly()

    -- Process takeoff completion
    if self.IsTakingOff then
        if self.FlightState == FlyClass.FLIGHT_STATE.FLYING then
            self.IsTakingOff = false
        end
    end

    -- Process landing completion
    if self.IsLanding then
        if self.FlightState == FlyClass.FLIGHT_STATE.GROUNDED then
            self:Complete_Landing()
        end
    end

    -- Attack timer
    if self.AttackTimer > 0 then
        self.AttackTimer = self.AttackTimer - 1
    end

    -- Rotor animation
    if self:Is_Airborne() then
        self.BodyFrame = (self.BodyFrame + 1) % 8
    end
end

--============================================================================
-- Voice Responses
--============================================================================

--[[
    Voice response when selected.
]]
function AircraftClass:Response_Select()
    -- Would play selection voice
end

--[[
    Voice response when given move order.
]]
function AircraftClass:Response_Move()
    -- Would play movement acknowledgment
end

--[[
    Voice response when given attack order.
]]
function AircraftClass:Response_Attack()
    -- Would play attack acknowledgment
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function AircraftClass:Code_Pointers()
    local data = FootClass.Code_Pointers(self)

    -- Aircraft specific
    data.IsLanding = self.IsLanding
    data.IsTakingOff = self.IsTakingOff
    data.LandState = self.LandState
    data.LandingTarget = self.LandingTarget
    data.Ammo = self.Ammo
    data.MaxAmmo = self.MaxAmmo
    data.Fuel = self.Fuel
    data.AttackTimer = self.AttackTimer
    data.StrafeCount = self.StrafeCount
    data.BodyFrame = self.BodyFrame

    -- Flight data from mixin
    data.Fly = self:Code_Pointers_Fly()

    -- Type (store as name for lookup)
    if self.Class then
        data.TypeName = self.Class.IniName
    end

    return data
end

function AircraftClass:Decode_Pointers(data, heap_lookup)
    FootClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.IsLanding = data.IsLanding or false
        self.IsTakingOff = data.IsTakingOff or false
        self.LandState = data.LandState or AircraftClass.LAND_STATE.NONE
        self.LandingTarget = data.LandingTarget or Target.TARGET_NONE
        self.Ammo = data.Ammo or -1
        self.MaxAmmo = data.MaxAmmo or -1
        self.Fuel = data.Fuel or 255
        self.AttackTimer = data.AttackTimer or 0
        self.StrafeCount = data.StrafeCount or 0
        self.BodyFrame = data.BodyFrame or 0

        -- Flight data
        if data.Fly then
            self:Decode_Pointers_Fly(data.Fly)
        end

        -- Type lookup would happen later
        self._decode_type_name = data.TypeName
    end
end

--============================================================================
-- Debug Support
--============================================================================

local LAND_STATE_NAMES = {
    [0] = "NONE",
    [1] = "APPROACH",
    [2] = "DESCEND",
    [3] = "TOUCHDOWN",
    [4] = "LANDED",
}

function AircraftClass:Debug_Dump()
    FootClass.Debug_Dump(self)

    print(string.format("AircraftClass: Ammo=%d/%d Fuel=%d",
        self.Ammo,
        self.MaxAmmo,
        self.Fuel))

    print(string.format("  Landing=%s TakingOff=%s LandState=%s",
        tostring(self.IsLanding),
        tostring(self.IsTakingOff),
        LAND_STATE_NAMES[self.LandState] or "?"))

    print(string.format("  AttackTimer=%d StrafeCount=%d BodyFrame=%d",
        self.AttackTimer,
        self.StrafeCount,
        self.BodyFrame))

    -- Dump flight mixin state
    self:Debug_Dump_Fly()
end

return AircraftClass
