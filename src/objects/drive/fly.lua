--[[
    FlyClass - Aircraft flight physics class

    Port of FLY.H/CPP from the original C&C source.

    This is a MIXIN class (not in the inheritance chain) that provides
    flight physics for aircraft. It handles:
    - Speed accumulation for smooth movement
    - Flight physics calculations
    - Landing and takeoff logic
    - Altitude management

    In the original C++, FlyClass is used as a component mixed into
    AircraftClass, separate from the DriveClass hierarchy.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/FLY.H
]]

local Class = require("src.objects.class")

-- Create FlyClass as a mixin (not inheriting from anything)
local FlyClass = Class.mixin("FlyClass")

--============================================================================
-- Constants
--============================================================================

-- Flight altitude levels (in leptons above ground)
FlyClass.ALTITUDE = {
    GROUND = 0,      -- On the ground
    LOW = 128,       -- Nap-of-earth flight
    MEDIUM = 256,    -- Standard flight altitude
    HIGH = 512,      -- High altitude
}

-- Flight states
FlyClass.FLIGHT_STATE = {
    GROUNDED = 0,    -- On ground
    TAKING_OFF = 1,  -- Rising to flight altitude
    FLYING = 2,      -- In flight
    LANDING = 3,     -- Descending to land
    HOVERING = 4,    -- Stationary in air
}

-- Speed type enumeration (MPH = Map units Per Hour equivalent)
FlyClass.MPH = {
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

-- Impact types for physics results
FlyClass.IMPACT = {
    NONE = 0,        -- No impact, continue flying
    GROUND = 1,      -- Hit ground
    WATER = 2,       -- Hit water
    BUILDING = 3,    -- Hit building
    UNIT = 4,        -- Hit unit
}

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize flight state.
    Called automatically when mixed into a class.
]]
function FlyClass:init()
    --[[
        Speed accumulator. This holds fractional movement value
        that accumulates until it reaches full movement units.
        Similar to Bresenham line algorithm accumulator.
    ]]
    self.SpeedAccum = 0

    --[[
        Current speed setting. This is added to the accumulator
        each tick. Higher values = faster movement.
    ]]
    self.SpeedAdd = FlyClass.MPH.MEDIUM

    --[[
        Current altitude above ground in leptons.
    ]]
    self.Altitude = FlyClass.ALTITUDE.GROUND

    --[[
        Target altitude to reach.
    ]]
    self.TargetAltitude = FlyClass.ALTITUDE.MEDIUM

    --[[
        Current flight state.
    ]]
    self.FlightState = FlyClass.FLIGHT_STATE.GROUNDED

    --[[
        Rate of altitude change per tick.
    ]]
    self.ClimbRate = 4

    --[[
        If true, aircraft is in VTOL mode (can hover).
    ]]
    self.IsVTOL = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if aircraft is airborne (not on ground).
]]
function FlyClass:Is_Airborne()
    return self.Altitude > 0
end

--[[
    Check if aircraft is on the ground.
]]
function FlyClass:Is_Grounded()
    return self.Altitude == 0 and self.FlightState == FlyClass.FLIGHT_STATE.GROUNDED
end

--[[
    Check if aircraft is taking off.
]]
function FlyClass:Is_Taking_Off()
    return self.FlightState == FlyClass.FLIGHT_STATE.TAKING_OFF
end

--[[
    Check if aircraft is landing.
]]
function FlyClass:Is_Landing()
    return self.FlightState == FlyClass.FLIGHT_STATE.LANDING
end

--[[
    Check if aircraft is hovering.
]]
function FlyClass:Is_Hovering()
    return self.FlightState == FlyClass.FLIGHT_STATE.HOVERING
end

--[[
    Get current flight speed.
]]
function FlyClass:Flight_Speed()
    return self.SpeedAdd
end

--[[
    Get current altitude.
]]
function FlyClass:Get_Altitude()
    return self.Altitude
end

--============================================================================
-- Speed Control
--============================================================================

--[[
    Set the flight speed.

    @param speed - Target speed (0-255 throttle)
    @param maximum - Maximum speed from unit type
]]
function FlyClass:Fly_Speed(speed, maximum)
    -- Convert throttle (0-255) to actual speed based on maximum
    if speed <= 0 then
        self.SpeedAdd = 0
    else
        -- Scale speed setting to actual MPH
        self.SpeedAdd = math.floor((speed / 255) * maximum)
    end
end

--[[
    Set maximum speed (full throttle).

    @param maximum - Maximum speed from unit type
]]
function FlyClass:Set_Max_Speed(maximum)
    self:Fly_Speed(255, maximum)
end

--[[
    Stop (zero speed).
]]
function FlyClass:Stop_Flight()
    self.SpeedAdd = 0
    self.SpeedAccum = 0
end

--============================================================================
-- Altitude Control
--============================================================================

--[[
    Set target altitude.

    @param altitude - Target altitude in leptons
]]
function FlyClass:Set_Altitude(altitude)
    self.TargetAltitude = altitude

    -- Update flight state
    if altitude > self.Altitude then
        if self.FlightState == FlyClass.FLIGHT_STATE.GROUNDED then
            self.FlightState = FlyClass.FLIGHT_STATE.TAKING_OFF
        end
    elseif altitude < self.Altitude then
        if altitude == 0 then
            self.FlightState = FlyClass.FLIGHT_STATE.LANDING
        end
    end
end

--[[
    Start takeoff sequence.
]]
function FlyClass:Take_Off()
    if self.FlightState == FlyClass.FLIGHT_STATE.GROUNDED then
        self.FlightState = FlyClass.FLIGHT_STATE.TAKING_OFF
        self.TargetAltitude = FlyClass.ALTITUDE.MEDIUM
    end
end

--[[
    Start landing sequence.
]]
function FlyClass:Land()
    if self:Is_Airborne() then
        self.FlightState = FlyClass.FLIGHT_STATE.LANDING
        self.TargetAltitude = FlyClass.ALTITUDE.GROUND
    end
end

--[[
    Enter hover mode (VTOL aircraft only).
]]
function FlyClass:Hover()
    if self.IsVTOL and self:Is_Airborne() then
        self.FlightState = FlyClass.FLIGHT_STATE.HOVERING
        self.SpeedAdd = 0
    end
end

--============================================================================
-- Physics
--============================================================================

--[[
    Process flight physics for one tick.
    Updates position based on speed and facing.

    @param coord - Current coordinate (modified in place)
    @param facing - Current facing direction (0-255)
    @return ImpactType if collision, coordinate otherwise
]]
function FlyClass:Physics(coord, facing)
    local Coord = require("src.core.coord")

    -- Process altitude changes
    self:Process_Altitude()

    -- If grounded, no horizontal movement
    if self.FlightState == FlyClass.FLIGHT_STATE.GROUNDED then
        return coord
    end

    -- Accumulate speed
    self.SpeedAccum = self.SpeedAccum + self.SpeedAdd

    -- Convert accumulated speed to movement
    local movement = math.floor(self.SpeedAccum / 16)
    if movement <= 0 then
        return coord  -- Not enough accumulated for movement
    end

    -- Remove used accumulator
    self.SpeedAccum = self.SpeedAccum - (movement * 16)

    -- Calculate direction vector from facing
    local angle = (facing / 256) * math.pi * 2
    local dx = math.floor(math.sin(angle) * movement)
    local dy = math.floor(-math.cos(angle) * movement)

    -- Apply movement
    local new_x = Coord.Coord_X(coord) + dx
    local new_y = Coord.Coord_Y(coord) + dy

    -- Bounds checking (simplified - would check map bounds)
    if new_x < 0 then new_x = 0 end
    if new_y < 0 then new_y = 0 end

    -- Create new coordinate
    local new_coord = Coord.XY_Coord(new_x, new_y)

    -- Check for collisions (simplified)
    local impact = self:Check_Collision(new_coord)
    if impact ~= FlyClass.IMPACT.NONE then
        return impact
    end

    return new_coord
end

--[[
    Process altitude changes toward target.
]]
function FlyClass:Process_Altitude()
    if self.Altitude == self.TargetAltitude then
        -- Altitude reached
        if self.FlightState == FlyClass.FLIGHT_STATE.TAKING_OFF then
            self.FlightState = FlyClass.FLIGHT_STATE.FLYING
        elseif self.FlightState == FlyClass.FLIGHT_STATE.LANDING then
            if self.Altitude == 0 then
                self.FlightState = FlyClass.FLIGHT_STATE.GROUNDED
                self:Stop_Flight()
            end
        end
        return
    end

    -- Move toward target altitude
    if self.Altitude < self.TargetAltitude then
        self.Altitude = math.min(self.Altitude + self.ClimbRate, self.TargetAltitude)
    else
        self.Altitude = math.max(self.Altitude - self.ClimbRate, self.TargetAltitude)
    end
end

--[[
    Check for collision at coordinate.
    Simplified implementation - would check terrain, buildings, etc.

    @param coord - Coordinate to check
    @return ImpactType
]]
function FlyClass:Check_Collision(coord)
    -- Simplified - no collision detection
    -- Full implementation would check:
    -- - Map boundaries
    -- - Tall buildings
    -- - Other aircraft
    -- - Ground if altitude too low

    return FlyClass.IMPACT.NONE
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for flight.
    Should be called from the main AI() each game tick.
]]
function FlyClass:AI_Fly()
    -- Process altitude
    self:Process_Altitude()

    -- If hovering VTOL, maintain position
    if self.FlightState == FlyClass.FLIGHT_STATE.HOVERING then
        -- Would add slight drift/wobble here
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function FlyClass:Code_Pointers_Fly()
    return {
        SpeedAccum = self.SpeedAccum,
        SpeedAdd = self.SpeedAdd,
        Altitude = self.Altitude,
        TargetAltitude = self.TargetAltitude,
        FlightState = self.FlightState,
        ClimbRate = self.ClimbRate,
        IsVTOL = self.IsVTOL,
    }
end

function FlyClass:Decode_Pointers_Fly(data)
    if data then
        self.SpeedAccum = data.SpeedAccum or 0
        self.SpeedAdd = data.SpeedAdd or FlyClass.MPH.MEDIUM
        self.Altitude = data.Altitude or FlyClass.ALTITUDE.GROUND
        self.TargetAltitude = data.TargetAltitude or FlyClass.ALTITUDE.MEDIUM
        self.FlightState = data.FlightState or FlyClass.FLIGHT_STATE.GROUNDED
        self.ClimbRate = data.ClimbRate or 4
        self.IsVTOL = data.IsVTOL or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

local STATE_NAMES = {
    [0] = "GROUNDED",
    [1] = "TAKING_OFF",
    [2] = "FLYING",
    [3] = "LANDING",
    [4] = "HOVERING",
}

function FlyClass:Debug_Dump_Fly()
    print(string.format("FlyClass: State=%s Altitude=%d->%d Speed=%d Accum=%d",
        STATE_NAMES[self.FlightState] or "?",
        self.Altitude,
        self.TargetAltitude,
        self.SpeedAdd,
        self.SpeedAccum))

    print(string.format("  VTOL=%s ClimbRate=%d",
        tostring(self.IsVTOL),
        self.ClimbRate))
end

return FlyClass
