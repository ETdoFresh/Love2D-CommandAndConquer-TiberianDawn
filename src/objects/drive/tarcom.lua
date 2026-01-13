--[[
    TarComClass - Targeting computer class for combat vehicles

    Port of TARCOM.H/CPP from the original C&C source.

    This class extends TurretClass to add targeting computer functionality:
    - Automatic target acquisition
    - Target tracking and engagement
    - Fire coordination with turret alignment

    TarComClass is the final movement specialization for combat vehicles
    before branching into UnitClass.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TARCOM.H
]]

local Class = require("src.objects.class")
local TurretClass = require("src.objects.drive.turret")
local Target = require("src.core.target")

-- Create TarComClass extending TurretClass
local TarComClass = Class.extend(TurretClass, "TarComClass")

--============================================================================
-- Constants
--============================================================================

-- Target scan interval in ticks
TarComClass.SCAN_INTERVAL = 15  -- 1 second at 15 FPS

-- Maximum engagement range multiplier
TarComClass.MAX_ENGAGEMENT_RANGE = 2  -- 2x weapon range

--============================================================================
-- Constructor
--============================================================================

function TarComClass:init(house)
    -- Call parent constructor
    TurretClass.init(self, house)

    --[[
        Timer for target scanning.
        When it reaches 0, scan for new targets.
    ]]
    self.ScanTimer = 0

    --[[
        Last known position of target.
        Used for tracking moving targets.
    ]]
    self.LastTargetCoord = 0

    --[[
        Flag indicating if actively engaging a target.
    ]]
    self.IsEngaging = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if currently engaging a target.
]]
function TarComClass:Is_Engaging()
    return self.IsEngaging and Target.Is_Valid(self.TarCom)
end

--[[
    Check if target is in engagement range.
]]
function TarComClass:Is_Target_In_Range()
    if not Target.Is_Valid(self.TarCom) then
        return false
    end

    -- Check if within maximum engagement range
    return self:In_Range(self.TarCom, 0)
end

--[[
    Get the threat level of a potential target.
    Higher values = higher priority target.

    @param target - TARGET to evaluate
    @return Threat level (0 = no threat)
]]
function TarComClass:Evaluate_Threat(target)
    if not Target.Is_Valid(target) then
        return 0
    end

    local threat = 0
    local obj = Target.As_Object(target)

    if not obj then
        return 0
    end

    -- Base threat from being a valid target
    threat = 10

    -- Increase threat for units attacking us
    if obj.TarCom and obj.TarCom == self:As_Target() then
        threat = threat + 50
    end

    -- Increase threat for damaged targets (easier kills)
    if obj.Strength and obj.MaxStrength then
        local health_ratio = obj.Strength / obj.MaxStrength
        if health_ratio < 0.5 then
            threat = threat + 20
        end
    end

    -- Decrease threat based on distance
    local range = self:Distance_To_Target(target)
    if range > 0 then
        threat = threat - math.floor(range / 256)  -- Reduce by distance in cells
    end

    return math.max(0, threat)
end

--============================================================================
-- Target Acquisition
--============================================================================

--[[
    Scan for and acquire a target.
    Uses Greatest_Threat from TechnoClass.

    @return true if target acquired
]]
function TarComClass:Acquire_Target()
    -- Don't acquire if already have valid target
    if Target.Is_Valid(self.TarCom) then
        return true
    end

    -- Use base class threat detection
    local threat = self:Greatest_Threat(0)  -- THREAT_NORMAL

    if Target.Is_Valid(threat) then
        self:Assign_Target(threat)
        self.IsEngaging = true
        return true
    end

    return false
end

--[[
    Validate current target is still valid.

    @return true if target still valid
]]
function TarComClass:Validate_Target()
    if not Target.Is_Valid(self.TarCom) then
        self.IsEngaging = false
        return false
    end

    local obj = Target.As_Object(self.TarCom)
    if not obj then
        -- Target is a coordinate, always valid
        return true
    end

    -- Check if target still exists and is alive
    if obj.Strength and obj.Strength <= 0 then
        self:Assign_Target(Target.TARGET_NONE)
        self.IsEngaging = false
        return false
    end

    -- Check if target still in range (with hysteresis)
    local range = self:Distance_To_Target(self.TarCom)
    local max_range = self:Weapon_Range(0) * TarComClass.MAX_ENGAGEMENT_RANGE

    if range > max_range then
        -- Target out of range
        self:Assign_Target(Target.TARGET_NONE)
        self.IsEngaging = false
        return false
    end

    -- Update last known position
    self.LastTargetCoord = obj:Center_Coord()

    return true
end

--============================================================================
-- Combat
--============================================================================

--[[
    Engage the current target.
    Handles turret alignment and firing.

    @return true if successfully fired
]]
function TarComClass:Engage_Target()
    if not self:Validate_Target() then
        return false
    end

    -- Track target with turret
    self:Track_Target(self.TarCom)

    -- Check if turret is aligned
    if self:Has_Turret() and self.IsTurretRotating then
        return false  -- Wait for turret alignment
    end

    -- Check if weapon is ready
    if self:Is_Reloading() then
        return false
    end

    -- Check range
    if not self:In_Range(self.TarCom, 0) then
        -- Move closer if not in range
        self:Approach_Target()
        return false
    end

    -- Fire!
    local bullet = self:Fire_At(self.TarCom, 0)
    return bullet ~= nil
end

--[[
    Override Fire_At for target tracking.
]]
function TarComClass:Fire_At(target, which)
    -- Update last target coord before firing
    local obj = Target.As_Object(target)
    if obj then
        self.LastTargetCoord = obj:Center_Coord()
    end

    return TurretClass.Fire_At(self, target, which)
end

--============================================================================
-- Mission Implementations
--============================================================================

--[[
    Override Mission_Attack for improved targeting.
]]
function TarComClass:Mission_Attack()
    -- Validate current target
    if not self:Validate_Target() then
        -- Try to acquire new target
        if not self:Acquire_Target() then
            self:Enter_Idle_Mode()
            return TarComClass.SCAN_INTERVAL
        end
    end

    -- Engage target
    self:Engage_Target()

    return 1  -- Process every tick while attacking
end

--[[
    Override Mission_Guard for automatic target acquisition.
]]
function TarComClass:Mission_Guard()
    -- Scan for targets periodically
    self.ScanTimer = self.ScanTimer - 1
    if self.ScanTimer <= 0 then
        self.ScanTimer = TarComClass.SCAN_INTERVAL

        if self:Acquire_Target() then
            self:Assign_Mission(self.MISSION.ATTACK)
            return 1
        end
    end

    return TarComClass.SCAN_INTERVAL
end

--[[
    Override Mission_Guard_Area for area defense.
]]
function TarComClass:Mission_Guard_Area()
    -- Similar to guard but stays in area
    return self:Mission_Guard()
end

--[[
    Override Mission_Hunt for aggressive targeting.
]]
function TarComClass:Mission_Hunt()
    -- Always try to acquire target
    if not self:Validate_Target() then
        if self:Acquire_Target() then
            self:Assign_Mission(self.MISSION.ATTACK)
            return 1
        end
    end

    -- Move toward enemy base if no targets
    -- (Simplified - would use pathfinding to enemy)

    return TarComClass.SCAN_INTERVAL
end

--============================================================================
-- AI Processing
--============================================================================

function TarComClass:AI()
    TurretClass.AI(self)

    -- Validate target each tick
    self:Validate_Target()

    -- If engaging and target valid, track with turret
    if self.IsEngaging and Target.Is_Valid(self.TarCom) then
        self:Track_Target(self.TarCom)
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function TarComClass:Code_Pointers()
    local data = TurretClass.Code_Pointers(self)

    data.ScanTimer = self.ScanTimer
    data.LastTargetCoord = self.LastTargetCoord
    data.IsEngaging = self.IsEngaging

    return data
end

function TarComClass:Decode_Pointers(data, heap_lookup)
    TurretClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.ScanTimer = data.ScanTimer or 0
        self.LastTargetCoord = data.LastTargetCoord or 0
        self.IsEngaging = data.IsEngaging or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

function TarComClass:Debug_Dump()
    TurretClass.Debug_Dump(self)

    print(string.format("TarComClass: ScanTimer=%d Engaging=%s LastCoord=%d",
        self.ScanTimer,
        tostring(self.IsEngaging),
        self.LastTargetCoord))
end

return TarComClass
