--[[
    BulletTypeClass - Type class for projectiles/bullets

    Port of TYPE.H BulletTypeClass from the original C&C source.

    This class extends ObjectTypeClass to add bullet-specific properties:
    - Flight characteristics (arcing, homing, dropping)
    - Warhead type for damage
    - Explosion animation on impact
    - Speed and rotation properties

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.H
]]

local Class = require("src.objects.class")
local ObjectTypeClass = require("src.objects.types.objecttype")

-- Create BulletTypeClass extending ObjectTypeClass
local BulletTypeClass = Class.extend(ObjectTypeClass, "BulletTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Bullet type identifiers (matches BulletType in DEFINES.H)
BulletTypeClass.BULLET = {
    NONE = -1,
    SNIPER = 0,         -- Sniper bullet
    BULLET = 1,         -- Small arms
    APDS = 2,           -- Armor piercing projectile
    HE = 3,             -- High explosive shell
    SSM = 4,            -- Surface to surface small missile
    SSM2 = 5,           -- MLRS missile
    SAM = 6,            -- Fast homing anti-aircraft missile
    TOW = 7,            -- TOW anti-vehicle short range missile
    FLAME = 8,          -- Flame thrower flame
    CHEMSPRAY = 9,      -- Chemical weapon spray
    NAPALM = 10,        -- Napalm bomblet
    GRENADE = 11,       -- Hand tossed grenade
    LASER = 12,         -- Laser beam from obelisk
    NUKE_UP = 13,       -- Nuclear missile ascending
    NUKE_DOWN = 14,     -- Nuclear missile descending
    HONEST_JOHN = 15,   -- SSM with napalm warhead
    SPREADFIRE = 16,    -- Chain gun bullets
    HEADBUTT = 17,      -- Dinosaur head butt
    TREXBITE = 18,      -- T-Rex bite
    COUNT = 19,
}

-- Warhead types (matches WarheadType in DEFINES.H)
BulletTypeClass.WARHEAD = {
    NONE = -1,
    SA = 0,             -- Small arms
    HE = 1,             -- High explosive
    AP = 2,             -- Armor piercing
    FIRE = 3,           -- Incendiary
    LASER = 4,          -- Laser
    PB = 5,             -- Particle beam
    FIST = 6,           -- Punching
    FOOT = 7,           -- Kicking
    HOLLOW_POINT = 8,   -- Sniper bullet
    SPORE = 9,          -- Blossom tree spores
    HEADBUTT = 10,      -- Dinosaur headbutt
    FEEDME = 11,        -- T-Rex bite
    COUNT = 12,
}

-- Animation types for explosions (subset)
BulletTypeClass.ANIM = {
    NONE = -1,
    FBALL1 = 0,
    GRENADE = 1,
    FRAG1 = 2,
    FRAG2 = 3,
    VEH_HIT1 = 4,
    VEH_HIT2 = 5,
    VEH_HIT3 = 6,
    ART_EXP1 = 7,
    NAPALM1 = 8,
    NAPALM2 = 9,
    NAPALM3 = 10,
    SMOKE_PUFF = 11,
    PIFF = 12,
    PIFFPIFF = 13,
}

-- Speed values
BulletTypeClass.MPH = {
    IMMOBILE = 0,
    VERY_SLOW = 5,
    SLOW = 10,
    MEDIUM = 20,
    FAST = 30,
    VERY_FAST = 40,
    BLAZING = 50,
    LIGHTSPEED = 100,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new BulletTypeClass.

    @param ini_name - The INI control name (e.g., "SNIPER")
    @param name - The full display name (e.g., "Sniper Bullet")
]]
function BulletTypeClass:init(ini_name, name)
    -- Call parent constructor
    ObjectTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Bullet Type Identifier
    --========================================================================

    --[[
        The specific bullet type.
    ]]
    self.Type = BulletTypeClass.BULLET.NONE

    --========================================================================
    -- Flight Characteristic Flags
    --========================================================================

    --[[
        Does this projectile fly at high altitude (over walls)?
    ]]
    self.IsHigh = false

    --[[
        Does this projectile follow a ballistic arc (grenades, artillery)?
    ]]
    self.IsArcing = false

    --[[
        Does this projectile home in on the target (missiles)?
    ]]
    self.IsHoming = false

    --[[
        Does this projectile fall from above (bombs)?
    ]]
    self.IsDropping = false

    --[[
        Is this projectile invisible (small bullets, beams)?
    ]]
    self.IsInvisible = false

    --[[
        Does this explode when near target, not just on hit?
    ]]
    self.IsProximityArmed = false

    --[[
        Does this leave a smoke trail (missiles)?
    ]]
    self.IsFlameEquipped = false

    --[[
        Does this track fuel consumption?
    ]]
    self.IsFueled = false

    --[[
        Does this have no facing-specific visuals?
    ]]
    self.IsFaceless = false

    --[[
        Is this inherently inaccurate (artillery)?
    ]]
    self.IsInaccurate = false

    --[[
        Uses translucent rendering?
    ]]
    self.IsTranslucent = false

    --[[
        Can be fired at aircraft?
    ]]
    self.IsAntiAircraft = false

    --========================================================================
    -- Combat Properties
    --========================================================================

    --[[
        Maximum projectile speed.
    ]]
    self.MaxSpeed = BulletTypeClass.MPH.FAST

    --[[
        Type of warhead (determines damage characteristics).
    ]]
    self.Warhead = BulletTypeClass.WARHEAD.NONE

    --[[
        Animation to play on impact.
    ]]
    self.Explosion = BulletTypeClass.ANIM.NONE

    --[[
        Rate of turn for homing projectiles (0-255).
    ]]
    self.ROT = 0

    --[[
        Distance/time before projectile can detonate.
    ]]
    self.Arming = 0

    --[[
        Override distance before auto-explosion.
    ]]
    self.Range = 0

    --========================================================================
    -- Default Properties
    --========================================================================

    -- Bullets are not selectable or targetable
    self.IsSelectable = false
    self.IsLegalTarget = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this bullet arcs through the air.
]]
function BulletTypeClass:Is_Arcing()
    return self.IsArcing
end

--[[
    Check if this bullet homes on target.
]]
function BulletTypeClass:Is_Homing()
    return self.IsHoming
end

--[[
    Check if this bullet is invisible.
]]
function BulletTypeClass:Is_Invisible()
    return self.IsInvisible
end

--[[
    Check if this is an anti-aircraft projectile.
]]
function BulletTypeClass:Is_Anti_Aircraft()
    return self.IsAntiAircraft
end

--[[
    Get the warhead type.
]]
function BulletTypeClass:Get_Warhead()
    return self.Warhead
end

--[[
    Get the explosion animation type.
]]
function BulletTypeClass:Get_Explosion()
    return self.Explosion
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined bullet type.

    @param type - BulletType enum value
    @return New BulletTypeClass instance
]]
function BulletTypeClass.Create(type)
    local bullet = nil

    if type == BulletTypeClass.BULLET.SNIPER then
        bullet = BulletTypeClass:new("SNIPER", "Sniper Bullet")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.LIGHTSPEED
        bullet.Warhead = BulletTypeClass.WARHEAD.HOLLOW_POINT
        bullet.Explosion = BulletTypeClass.ANIM.PIFF
        bullet.IsInvisible = true
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.BULLET then
        bullet = BulletTypeClass:new("BULLET", "Small Arms Bullet")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.LIGHTSPEED
        bullet.Warhead = BulletTypeClass.WARHEAD.SA
        bullet.Explosion = BulletTypeClass.ANIM.PIFF
        bullet.IsInvisible = true
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.APDS then
        bullet = BulletTypeClass:new("APDS", "Armor Piercing Shell")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.VERY_FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.AP
        bullet.Explosion = BulletTypeClass.ANIM.VEH_HIT1
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.HE then
        bullet = BulletTypeClass:new("HE", "High Explosive Shell")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.ART_EXP1
        bullet.IsArcing = true
        bullet.IsInaccurate = true
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.SSM then
        bullet = BulletTypeClass:new("SSM", "Surface to Surface Missile")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.FRAG1
        bullet.IsHoming = true
        bullet.IsFlameEquipped = true
        bullet.ROT = 5

    elseif type == BulletTypeClass.BULLET.SSM2 then
        bullet = BulletTypeClass:new("SSM2", "MLRS Missile")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.FRAG2
        bullet.IsHoming = true
        bullet.IsFlameEquipped = true
        bullet.ROT = 5

    elseif type == BulletTypeClass.BULLET.SAM then
        bullet = BulletTypeClass:new("SAM", "Surface to Air Missile")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.BLAZING
        bullet.Warhead = BulletTypeClass.WARHEAD.AP
        bullet.Explosion = BulletTypeClass.ANIM.VEH_HIT2
        bullet.IsHoming = true
        bullet.IsFlameEquipped = true
        bullet.IsAntiAircraft = true
        bullet.ROT = 10

    elseif type == BulletTypeClass.BULLET.TOW then
        bullet = BulletTypeClass:new("TOW", "TOW Missile")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.MEDIUM
        bullet.Warhead = BulletTypeClass.WARHEAD.AP
        bullet.Explosion = BulletTypeClass.ANIM.VEH_HIT1
        bullet.IsHoming = true
        bullet.IsFlameEquipped = true
        bullet.ROT = 5

    elseif type == BulletTypeClass.BULLET.FLAME then
        bullet = BulletTypeClass:new("FLAME", "Flame")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.MEDIUM
        bullet.Warhead = BulletTypeClass.WARHEAD.FIRE
        bullet.Explosion = BulletTypeClass.ANIM.NAPALM1
        bullet.IsFlameEquipped = false  -- Flame doesn't have smoke trail
        bullet.IsTranslucent = true

    elseif type == BulletTypeClass.BULLET.CHEMSPRAY then
        bullet = BulletTypeClass:new("CHEM", "Chemical Spray")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.MEDIUM
        bullet.Warhead = BulletTypeClass.WARHEAD.HE  -- Chem uses HE
        bullet.Explosion = BulletTypeClass.ANIM.NONE
        bullet.IsTranslucent = true

    elseif type == BulletTypeClass.BULLET.NAPALM then
        bullet = BulletTypeClass:new("NAPALM", "Napalm Bomb")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.FIRE
        bullet.Explosion = BulletTypeClass.ANIM.NAPALM3
        bullet.IsDropping = true
        bullet.IsArcing = true  -- Tumbles

    elseif type == BulletTypeClass.BULLET.GRENADE then
        bullet = BulletTypeClass:new("GRENADE", "Grenade")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.SLOW
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.GRENADE
        bullet.IsArcing = true
        bullet.IsInaccurate = true

    elseif type == BulletTypeClass.BULLET.LASER then
        bullet = BulletTypeClass:new("LASER", "Laser Beam")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.LIGHTSPEED
        bullet.Warhead = BulletTypeClass.WARHEAD.LASER
        bullet.Explosion = BulletTypeClass.ANIM.FBALL1
        bullet.IsInvisible = true  -- Beam is drawn separately
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.NUKE_UP then
        bullet = BulletTypeClass:new("NUKE_UP", "Nuclear Missile (Up)")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.NONE  -- Special handling
        bullet.IsFlameEquipped = true

    elseif type == BulletTypeClass.BULLET.NUKE_DOWN then
        bullet = BulletTypeClass:new("NUKE_DOWN", "Nuclear Missile (Down)")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.HE
        bullet.Explosion = BulletTypeClass.ANIM.NONE  -- Special: ATOM_BLAST
        bullet.IsFlameEquipped = true
        bullet.IsDropping = true

    elseif type == BulletTypeClass.BULLET.HONEST_JOHN then
        bullet = BulletTypeClass:new("HONEST_JOHN", "Honest John Rocket")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.FAST
        bullet.Warhead = BulletTypeClass.WARHEAD.FIRE
        bullet.Explosion = BulletTypeClass.ANIM.NAPALM3
        bullet.IsHoming = true
        bullet.IsFlameEquipped = true
        bullet.ROT = 3

    elseif type == BulletTypeClass.BULLET.SPREADFIRE then
        bullet = BulletTypeClass:new("SPREADFIRE", "Chaingun Bullet")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.LIGHTSPEED
        bullet.Warhead = BulletTypeClass.WARHEAD.SA
        bullet.Explosion = BulletTypeClass.ANIM.PIFFPIFF
        bullet.IsInvisible = true
        bullet.IsFaceless = true

    elseif type == BulletTypeClass.BULLET.HEADBUTT then
        bullet = BulletTypeClass:new("HEADBUTT", "Dinosaur Headbutt")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.IMMOBILE
        bullet.Warhead = BulletTypeClass.WARHEAD.HEADBUTT
        bullet.Explosion = BulletTypeClass.ANIM.NONE
        bullet.IsInvisible = true

    elseif type == BulletTypeClass.BULLET.TREXBITE then
        bullet = BulletTypeClass:new("TREXBITE", "T-Rex Bite")
        bullet.Type = type
        bullet.MaxSpeed = BulletTypeClass.MPH.IMMOBILE
        bullet.Warhead = BulletTypeClass.WARHEAD.FEEDME
        bullet.Explosion = BulletTypeClass.ANIM.NONE
        bullet.IsInvisible = true

    else
        -- Default/unknown type
        bullet = BulletTypeClass:new("BULLET", "Bullet")
        bullet.Type = type
    end

    return bullet
end

--============================================================================
-- Debug Support
--============================================================================

local WARHEAD_NAMES = {
    [-1] = "NONE",
    [0] = "SA",
    [1] = "HE",
    [2] = "AP",
    [3] = "FIRE",
    [4] = "LASER",
    [5] = "PB",
    [6] = "FIST",
    [7] = "FOOT",
    [8] = "HOLLOW_POINT",
    [9] = "SPORE",
    [10] = "HEADBUTT",
    [11] = "FEEDME",
}

function BulletTypeClass:Debug_Dump()
    ObjectTypeClass.Debug_Dump(self)

    print(string.format("BulletTypeClass: Type=%d Speed=%d Warhead=%s",
        self.Type,
        self.MaxSpeed,
        WARHEAD_NAMES[self.Warhead] or "?"))

    print(string.format("  Flags: Arcing=%s Homing=%s Invisible=%s AA=%s",
        tostring(self.IsArcing),
        tostring(self.IsHoming),
        tostring(self.IsInvisible),
        tostring(self.IsAntiAircraft)))
end

return BulletTypeClass
