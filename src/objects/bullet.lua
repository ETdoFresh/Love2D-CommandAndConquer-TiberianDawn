--[[
    BulletClass - Projectile game object

    Port of BULLET.H/CPP from the original C&C source.

    BulletClass extends ObjectClass and incorporates FlyClass mixin
    to handle projectile movement and physics.

    Features:
    - Ballistic trajectory (arcing projectiles)
    - Homing behavior (guided missiles)
    - Fuse/detonation system
    - Target tracking
    - Impact handling and explosion spawning

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.CPP
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local FlyClass = require("src.objects.drive.fly")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create BulletClass extending ObjectClass
local BulletClass = Class.extend(ObjectClass, "BulletClass")

-- Include FlyClass mixin for flight physics
Class.include(BulletClass, FlyClass)

--============================================================================
-- Constants
--============================================================================

-- Gravity constant for arcing projectiles (leptons per tick^2)
BulletClass.GRAVITY = 3

-- Minimum arcing speed
BulletClass.MIN_ARC_SPEED = 25

-- Anti-aircraft damage bonus (50% extra, 33% for TOW)
BulletClass.AA_DAMAGE_BONUS = 0.50
BulletClass.TOW_AA_DAMAGE_BONUS = 0.33

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new BulletClass.

    @param bullet_type - BulletTypeClass instance (optional)
]]
function BulletClass:init(bullet_type)
    -- Call parent constructor
    ObjectClass.init(self)

    -- Initialize FlyClass mixin
    FlyClass.init(self)

    --========================================================================
    -- Type Reference
    --========================================================================

    --[[
        Pointer to static type data for this bullet type.
    ]]
    self.Class = bullet_type

    --========================================================================
    -- Ownership/Attribution
    --========================================================================

    --[[
        The entity that fired this projectile (for kill attribution).
    ]]
    self.Payback = nil

    --========================================================================
    -- Facing/Direction
    --========================================================================

    --[[
        The direction the projectile is travelling.
    ]]
    self.PrimaryFacing = 0  -- 0-255 direction

    --========================================================================
    -- Accuracy
    --========================================================================

    --[[
        Flag indicating forced inaccuracy (e.g., tank firing while moving).
    ]]
    self.IsInaccurate = false

    --========================================================================
    -- Animation
    --========================================================================

    --[[
        Crude animation toggle flag (for tumbling projectiles).
    ]]
    self.IsToAnimate = false

    --========================================================================
    -- Altitude/Arc
    --========================================================================

    --[[
        Vertical height of projectile (for arcing/ballistic flight).
    ]]
    self.ArcAltitude = 0

    --[[
        Altitude change modifier per tick (rises then falls).
    ]]
    self.Riser = 0

    --========================================================================
    -- Targeting
    --========================================================================

    --[[
        Target the projectile is aimed at (especially for homing missiles).
    ]]
    self.TarCom = nil

    --[[
        Whether missile is allowed to come from out of bounds.
    ]]
    self.IsLocked = false

    --========================================================================
    -- Fuse System
    --========================================================================

    --[[
        Countdown to forced detonation (range in frames).
    ]]
    self.FuseTimer = 0

    --[[
        Countdown before detonation can occur (arming delay).
    ]]
    self.ArmingTimer = 0

    --[[
        Target coordinate for proximity detection.
    ]]
    self.FuseTarget = nil

    --[[
        Distance tracking for proximity detonation.
    ]]
    self.ProximityDistance = 0

    --[[
        Previous proximity distance (for approaching detection).
    ]]
    self.LastProximityDistance = 0

    --========================================================================
    -- Default state
    --========================================================================

    -- Bullets start in limbo until Unlimbo'd
    self.IsInLimbo = true

    -- Apply type properties if provided
    if bullet_type then
        self.Strength = 1  -- Bullets have minimal health
        self.SpeedAdd = bullet_type.MaxSpeed or 30
    end
end

--============================================================================
-- Type Identification
--============================================================================

--[[
    Returns what RTTI type this object is.
]]
function BulletClass:What_Am_I()
    return Target.RTTI.BULLET
end

--[[
    Get the bullet type class.
]]
function BulletClass:Get_Type()
    return self.Class
end

--============================================================================
-- Fuse System
--============================================================================

--[[
    Arm the fuse for detonation.

    @param target_coord - Target coordinate for proximity detection
    @param range - Maximum range before forced detonation
    @param arming - Arming delay before detonation can occur
]]
function BulletClass:Arm_Fuse(target_coord, range, arming)
    self.FuseTarget = target_coord
    self.FuseTimer = range or 255
    self.ArmingTimer = arming or 0
    self.ProximityDistance = 0x7FFFFFFF  -- Max int
    self.LastProximityDistance = 0x7FFFFFFF
end

--[[
    Check if the fuse has triggered.
    Returns true if the bullet should detonate.
]]
function BulletClass:Fuse_Checkup()
    -- Decrement arming timer
    if self.ArmingTimer > 0 then
        self.ArmingTimer = self.ArmingTimer - 1
        return false
    end

    -- Decrement fuse timer
    if self.FuseTimer > 0 then
        self.FuseTimer = self.FuseTimer - 1
        if self.FuseTimer == 0 then
            return true  -- Timer expired
        end
    end

    -- Proximity detection
    if self.FuseTarget and self.Class and self.Class.IsProximityArmed then
        local my_coord = self:Center_Coord()
        local distance = Coord.Distance(my_coord, self.FuseTarget)

        self.LastProximityDistance = self.ProximityDistance
        self.ProximityDistance = distance

        -- Detonate if we're close and getting farther (passed the target)
        if distance < 128 then  -- Half a cell
            return true
        end

        if self.ProximityDistance > self.LastProximityDistance then
            -- We passed the closest point
            return true
        end
    end

    return false
end

--============================================================================
-- Unlimbo - Spawn the bullet
--============================================================================

--[[
    Place the bullet on the map and set it in motion.

    @param coord - Starting coordinate
    @param facing - Initial facing direction (0-255)
    @param target - Target coordinate or object
    @return true if successful
]]
function BulletClass:Unlimbo(coord, facing, target)
    if not ObjectClass.Unlimbo(self, coord, facing) then
        return false
    end

    -- Store target
    if target then
        if type(target) == "table" and target.Center_Coord then
            self.TarCom = target
            self.FuseTarget = target:Center_Coord()
        else
            self.FuseTarget = target
        end
    end

    -- Calculate direction to target
    if self.FuseTarget and self.Class then
        if not self.Class.IsHoming and not self.Class.IsDropping then
            self.PrimaryFacing = Coord.Direction_To(coord, self.FuseTarget)
        else
            self.PrimaryFacing = facing or 0
        end
    else
        self.PrimaryFacing = facing or 0
    end

    -- Apply inaccuracy if needed
    if self.IsInaccurate or (self.Class and self.Class.IsInaccurate) then
        self:Apply_Inaccuracy()
    end

    -- Calculate range (flight time in frames)
    local range = 255
    if self.FuseTarget then
        local distance = Coord.Distance(coord, self.FuseTarget)
        local speed = self.SpeedAdd
        if speed > 0 then
            range = math.floor(distance / speed) + 10
        end
    end

    -- Setup arcing projectiles
    if self.Class and self.Class.IsArcing then
        -- Calculate initial riser for ballistic arc
        local distance = 128  -- Default
        if self.FuseTarget then
            distance = Coord.Distance(coord, self.FuseTarget)
        end
        -- Rise = distance / 8 for nice arc
        self.Riser = math.floor(distance / 8)
        self.ArcAltitude = 0
    end

    -- Arm the fuse
    local arming = 0
    if self.Class then
        arming = self.Class.Arming or 0
    end
    self:Arm_Fuse(self.FuseTarget, range, arming)

    return true
end

--============================================================================
-- Inaccuracy
--============================================================================

--[[
    Apply inaccuracy scatter to the target.
]]
function BulletClass:Apply_Inaccuracy()
    if not self.FuseTarget then return end

    -- Random scatter within CEP (Circular Error Probability)
    local scatter = 64  -- Half cell max scatter

    if self.Class and self.Class.IsHoming then
        scatter = 32  -- Less scatter for guided
    end

    -- Random offset
    local angle = math.random() * math.pi * 2
    local dist = math.random() * scatter

    local offset_x = math.cos(angle) * dist
    local offset_y = math.sin(angle) * dist

    local fx, fy = Coord.From_Lepton(self.FuseTarget)
    self.FuseTarget = Coord.To_Lepton(fx + offset_x, fy + offset_y)
end

--============================================================================
-- AI - Main Logic
--============================================================================

--[[
    Main bullet logic called every game tick.
]]
function BulletClass:AI()
    ObjectClass.AI(self)

    if self.IsInLimbo then return end

    -- Handle arcing projectiles (gravity)
    if self.Class and self.Class.IsArcing then
        self.ArcAltitude = self.ArcAltitude + self.Riser
        self.Riser = self.Riser - BulletClass.GRAVITY

        -- Hit ground check
        if self.ArcAltitude < 0 then
            self.ArcAltitude = 0
            self:Detonate()
            return
        end
    end

    -- Homing behavior
    if self.Class and self.Class.IsHoming and self.TarCom then
        local target_coord = nil
        if type(self.TarCom) == "table" and self.TarCom.Center_Coord then
            target_coord = self.TarCom:Center_Coord()
        else
            target_coord = self.TarCom
        end

        if target_coord then
            local desired = Coord.Direction_To(self:Center_Coord(), target_coord)
            local rot = self.Class.ROT or 5

            -- Gradually turn toward target
            local diff = desired - self.PrimaryFacing
            if diff > 128 then diff = diff - 256 end
            if diff < -128 then diff = diff + 256 end

            if math.abs(diff) <= rot then
                self.PrimaryFacing = desired
            elseif diff > 0 then
                self.PrimaryFacing = (self.PrimaryFacing + rot) % 256
            else
                self.PrimaryFacing = (self.PrimaryFacing - rot) % 256
            end
        end
    end

    -- Flame trail (smoke puffs)
    if self.Class and self.Class.IsFlameEquipped then
        -- Would spawn ANIM_SMOKE_PUFF here
        -- For now, just mark for animation
        self.IsToAnimate = not self.IsToAnimate
    end

    -- Physics movement
    local impact = self:Physics()

    -- Check for impact
    if impact ~= FlyClass.IMPACT.NONE then
        self:Detonate()
        return
    end

    -- Check fuse
    if self:Fuse_Checkup() then
        self:Detonate()
        return
    end
end

--============================================================================
-- Physics - Movement
--============================================================================

--[[
    Move the bullet based on speed and facing.
    Uses FlyClass accumulator for smooth movement.

    @return Impact type if collision occurred
]]
function BulletClass:Physics()
    -- Use FlyClass physics
    self.SpeedAccum = self.SpeedAccum + self.SpeedAdd

    -- Convert accumulated speed to movement
    local move_amount = math.floor(self.SpeedAccum / 16)
    if move_amount > 0 then
        self.SpeedAccum = self.SpeedAccum % 16

        -- Calculate movement vector from facing
        local angle = (self.PrimaryFacing / 256) * math.pi * 2
        local dx = math.sin(angle) * move_amount
        local dy = -math.cos(angle) * move_amount

        -- Move the bullet
        local old_coord = self.Coord
        local fx, fy = Coord.From_Lepton(old_coord)
        local new_coord = Coord.To_Lepton(fx + dx, fy + dy)

        -- Update position
        self:Mark(ObjectClass.MARK.UP)
        self.Coord = new_coord
        self:Mark(ObjectClass.MARK.DOWN)

        -- Check for map edge
        local cell = Coord.To_Cell(new_coord)
        if cell < 0 or cell >= 64 * 64 then
            return FlyClass.IMPACT.GROUND
        end
    end

    return FlyClass.IMPACT.NONE
end

--============================================================================
-- Detonation
--============================================================================

--[[
    Explode the bullet, dealing damage and spawning effects.
]]
function BulletClass:Detonate()
    if self.IsInLimbo then return end

    local impact_coord = self:Center_Coord()

    -- Calculate damage
    local damage = 0
    if self.Payback and self.Payback.Class then
        -- Would get damage from weapon type
        damage = 25  -- Default damage
    end

    -- Apply anti-aircraft bonus
    -- (Would check if target is aircraft)

    -- Spawn explosion animation
    if self.Class and self.Class.Explosion >= 0 then
        -- Would spawn AnimClass here
        -- AnimClass:new(self.Class.Explosion, impact_coord)
    end

    -- Deal damage to nearby objects
    -- Would call Explosion_Damage() here

    -- Remove bullet from game
    self:Limbo()
    self.IsActive = false
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Render the bullet.
]]
function BulletClass:Draw_It(x, y)
    -- Invisible bullets don't draw
    if self.Class and self.Class.IsInvisible then
        return
    end

    -- Would draw bullet sprite here
    -- Handle altitude offset for arcing projectiles
    local draw_y = y
    if self.ArcAltitude > 0 then
        -- Convert lepton altitude to pixel offset
        draw_y = y - math.floor(self.ArcAltitude / 10)
    end

    -- Would also draw shadow for elevated bullets
end

--============================================================================
-- Target Handling
--============================================================================

--[[
    Called when target object is destroyed.
]]
function BulletClass:Detach(target)
    if self.TarCom == target then
        self.TarCom = nil
    end
    if self.Payback == target then
        self.Payback = nil
    end
end

--============================================================================
-- Layer
--============================================================================

--[[
    Return which render layer this bullet is in.
]]
function BulletClass:In_Which_Layer()
    -- Bullets are always in the air layer
    return ObjectClass.LAYER.AIR
end

--============================================================================
-- Debug Support
--============================================================================

function BulletClass:Debug_Dump()
    ObjectClass.Debug_Dump(self)

    print(string.format("BulletClass: Type=%s Facing=%d Speed=%d",
        self.Class and self.Class.IniName or "none",
        self.PrimaryFacing,
        self.SpeedAdd))

    print(string.format("  Arc: Altitude=%d Riser=%d",
        self.ArcAltitude,
        self.Riser))

    print(string.format("  Fuse: Timer=%d Arming=%d Proximity=%d",
        self.FuseTimer,
        self.ArmingTimer,
        self.ProximityDistance))
end

return BulletClass
