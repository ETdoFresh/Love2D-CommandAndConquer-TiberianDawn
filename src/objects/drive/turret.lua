--[[
    TurretClass - Turret-equipped vehicle class

    Port of TURRET.H/CPP from the original C&C source.

    This class extends DriveClass to add turret functionality:
    - Secondary facing for turret rotation
    - Reload timer management
    - Target tracking with turret

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TURRET.H
]]

local Class = require("src.objects.class")
local DriveClass = require("src.objects.drive.drive")

-- Create TurretClass extending DriveClass
local TurretClass = Class.extend(DriveClass, "TurretClass")

--============================================================================
-- Constants
--============================================================================

-- Default reload time in ticks
TurretClass.DEFAULT_RELOAD = 30

-- Default turret rotation rate (degrees per tick, as 0-255 facing)
TurretClass.DEFAULT_TURRET_ROT = 8

--============================================================================
-- Constructor
--============================================================================

function TurretClass:init(house)
    -- Call parent constructor
    DriveClass.init(self, house)

    --[[
        Reload timer for weapon firing.
        When non-zero, the weapon is reloading and cannot fire.
    ]]
    self.Reload = 0

    --[[
        Secondary facing for turret direction.
        Structure mirrors PrimaryFacing.
    ]]
    self.SecondaryFacing = {
        Current = 0,    -- Current turret facing (0-255)
        Desired = 0,    -- Desired turret facing
    }

    --[[
        Flag indicating if turret is currently rotating.
    ]]
    self.IsTurretRotating = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this unit has a turret.
    Override in UnitClass based on unit type.
]]
function TurretClass:Has_Turret()
    return true  -- Override in derived class to check type
end

--[[
    Check if turret can rotate (not locked down).
]]
function TurretClass:Can_Rotate_Turret()
    return not self.IsTurretLockedDown and self:Has_Turret()
end

--[[
    Get the current turret facing.
]]
function TurretClass:Turret_Facing()
    return self.SecondaryFacing.Current
end

--[[
    Get the fire facing for weapons.
    Returns turret facing if has turret, otherwise body facing.
]]
function TurretClass:Fire_Direction()
    if self:Has_Turret() then
        return self.SecondaryFacing.Current
    end
    return self.PrimaryFacing and self.PrimaryFacing.Current or 0
end

--[[
    Check if weapon is reloading.
]]
function TurretClass:Is_Reloading()
    return self.Reload > 0
end

--============================================================================
-- Turret Control
--============================================================================

--[[
    Set the desired turret facing.

    @param facing - Target facing (0-255)
]]
function TurretClass:Set_Turret_Facing(facing)
    if self:Can_Rotate_Turret() then
        self.SecondaryFacing.Desired = facing % 256
    end
end

--[[
    Point turret at a coordinate.

    @param coord - Target coordinate
]]
function TurretClass:Point_Turret_At(coord)
    if coord == 0 or not self:Can_Rotate_Turret() then
        return
    end

    local center = self:Center_Coord()
    local Coord = require("src.core.coord")

    local dx = Coord.Coord_X(coord) - Coord.Coord_X(center)
    local dy = Coord.Coord_Y(coord) - Coord.Coord_Y(center)

    if dx == 0 and dy == 0 then
        return
    end

    -- Calculate facing (0=N, 64=E, 128=S, 192=W)
    local facing = math.floor(math.atan2(dy, dx) * 128 / math.pi + 64) % 256
    self:Set_Turret_Facing(facing)
end

--[[
    Point turret at a target.

    @param target - TARGET value to track
]]
function TurretClass:Track_Target(target)
    local Target = require("src.core.target")

    if not Target.Is_Valid(target) then
        return
    end

    local coord
    local obj = Target.As_Object(target)
    if obj then
        coord = obj:Center_Coord()
    else
        coord = Target.As_Coord(target)
    end

    if coord ~= 0 then
        self:Point_Turret_At(coord)
    end
end

--[[
    Process turret rotation.
    Returns true when turret reaches desired facing.
]]
function TurretClass:Do_Turn_Turret()
    if not self:Has_Turret() or self.IsTurretLockedDown then
        return true
    end

    local current = self.SecondaryFacing.Current
    local desired = self.SecondaryFacing.Desired

    if current == desired then
        self.IsTurretRotating = false
        return true
    end

    -- Calculate difference
    local diff = (desired - current) % 256
    if diff > 128 then
        diff = diff - 256
    end

    -- Turret rotation rate (would come from unit type)
    local rot_rate = TurretClass.DEFAULT_TURRET_ROT

    if math.abs(diff) <= rot_rate then
        self.SecondaryFacing.Current = desired
        self.IsTurretRotating = false
        return true
    elseif diff > 0 then
        self.SecondaryFacing.Current = (current + rot_rate) % 256
    else
        self.SecondaryFacing.Current = (current - rot_rate + 256) % 256
    end

    self.IsTurretRotating = true
    return false
end

--[[
    Lock turret to body facing.
]]
function TurretClass:Lock_Turret()
    self.IsTurretLockedDown = true
    if self.PrimaryFacing and type(self.PrimaryFacing) == "table" then
        self.SecondaryFacing.Current = self.PrimaryFacing.Current
        self.SecondaryFacing.Desired = self.PrimaryFacing.Current
    end
end

--[[
    Unlock turret for independent rotation.
]]
function TurretClass:Unlock_Turret()
    self.IsTurretLockedDown = false
end

--============================================================================
-- Weapon Control
--============================================================================

--[[
    Start weapon reload timer.

    @param time - Reload time in ticks (default uses DEFAULT_RELOAD)
]]
function TurretClass:Start_Reload(time)
    self.Reload = time or TurretClass.DEFAULT_RELOAD
end

--[[
    Get remaining reload time.
]]
function TurretClass:Reload_Time()
    return self.Reload
end

--[[
    Process reload timer.
]]
function TurretClass:Process_Reload()
    if self.Reload > 0 then
        self.Reload = self.Reload - 1
    end
end

--[[
    Check if weapon is ready to fire.
]]
function TurretClass:Is_Weapon_Ready()
    return self.Reload <= 0
end

--[[
    Override Fire_At to track turret.
]]
function TurretClass:Fire_At(target, which)
    -- Track target with turret
    self:Track_Target(target)

    -- Check if turret is facing target
    if self:Has_Turret() and self.IsTurretRotating then
        return nil  -- Wait for turret to align
    end

    -- Call parent fire
    local result = DriveClass.Fire_At(self, target, which)

    if result then
        -- Start reload
        self:Start_Reload()
    end

    return result
end

--============================================================================
-- AI Processing
--============================================================================

function TurretClass:AI()
    DriveClass.AI(self)

    -- Process reload timer
    self:Process_Reload()

    -- Process turret rotation
    if self:Has_Turret() and not self.IsTurretLockedDown then
        -- If has target, track it
        local Target = require("src.core.target")
        if Target.Is_Valid(self.TarCom) then
            self:Track_Target(self.TarCom)
        elseif not self.IsDriving then
            -- No target and not moving, align turret to body
            if self.PrimaryFacing then
                self.SecondaryFacing.Desired = self.PrimaryFacing.Current
            end
        end

        self:Do_Turn_Turret()
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function TurretClass:Code_Pointers()
    local data = DriveClass.Code_Pointers(self)

    data.Reload = self.Reload
    data.SecondaryFacing = {
        Current = self.SecondaryFacing.Current,
        Desired = self.SecondaryFacing.Desired,
    }
    data.IsTurretRotating = self.IsTurretRotating

    return data
end

function TurretClass:Decode_Pointers(data, heap_lookup)
    DriveClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.Reload = data.Reload or 0

        if data.SecondaryFacing then
            self.SecondaryFacing.Current = data.SecondaryFacing.Current or 0
            self.SecondaryFacing.Desired = data.SecondaryFacing.Desired or 0
        end

        self.IsTurretRotating = data.IsTurretRotating or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

function TurretClass:Debug_Dump()
    DriveClass.Debug_Dump(self)

    print(string.format("TurretClass: TurretFacing=%d->%d Reload=%d",
        self.SecondaryFacing.Current,
        self.SecondaryFacing.Desired,
        self.Reload))

    print(string.format("  Flags: TurretRotating=%s TurretLocked=%s",
        tostring(self.IsTurretRotating),
        tostring(self.IsTurretLockedDown)))
end

return TurretClass
