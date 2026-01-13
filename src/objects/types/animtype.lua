--[[
    AnimTypeClass - Type class for animations/visual effects

    Port of TYPE.H AnimTypeClass from the original C&C source.

    This class extends ObjectTypeClass to add animation-specific properties:
    - Frame control (start, stages, loops)
    - Special effects (scorch marks, craters)
    - Damage application
    - Chaining to other animations

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/ANIM.H
]]

local Class = require("src.objects.class")
local ObjectTypeClass = require("src.objects.types.objecttype")

-- Create AnimTypeClass extending ObjectTypeClass
local AnimTypeClass = Class.extend(ObjectTypeClass, "AnimTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Animation type identifiers (matches AnimType in DEFINES.H)
AnimTypeClass.ANIM = {
    NONE = -1,
    FBALL1 = 0,         -- Large fireball explosion
    GRENADE = 1,        -- Grenade explosion
    FRAG1 = 2,          -- Medium fragment explosion (short decay)
    FRAG2 = 3,          -- Medium fragment explosion (long decay)
    VEH_HIT1 = 4,       -- Small fireball explosion
    VEH_HIT2 = 5,       -- Small fragment explosion (sparkles)
    VEH_HIT3 = 6,       -- Small fragment explosion (burn/exp mix)
    ART_EXP1 = 7,       -- Large fragment explosion
    NAPALM1 = 8,        -- Small napalm burn
    NAPALM2 = 9,        -- Medium napalm burn
    NAPALM3 = 10,       -- Large napalm burn
    SMOKE_PUFF = 11,    -- Rocket smoke trail puff
    PIFF = 12,          -- Machine gun impact
    PIFFPIFF = 13,      -- Chaingun impact
    -- Directional flame (8 directions)
    FLAME_N = 14,
    FLAME_NE = 15,
    FLAME_E = 16,
    FLAME_SE = 17,
    FLAME_S = 18,
    FLAME_SW = 19,
    FLAME_W = 20,
    FLAME_NW = 21,
    -- Directional chem spray (8 directions)
    CHEM_N = 22,
    CHEM_NE = 23,
    CHEM_E = 24,
    CHEM_SE = 25,
    CHEM_S = 26,
    CHEM_SW = 27,
    CHEM_W = 28,
    CHEM_NW = 29,
    -- Fires
    FIRE_SMALL = 30,
    FIRE_MED = 31,
    FIRE_MED2 = 32,
    FIRE_TINY = 33,
    MUZZLE_FLASH = 34,
    -- Infantry death animations
    E1_ROT_FIRE = 35,
    E1_ROT_GRENADE = 36,
    E1_ROT_GUN = 37,
    E1_ROT_EXP = 38,
    -- More deaths...
    SMOKE_M = 51,
    BURN_SMALL = 52,
    BURN_MED = 53,
    BURN_BIG = 54,
    ON_FIRE_SMALL = 55,
    ON_FIRE_MED = 56,
    ON_FIRE_BIG = 57,
    -- SAM site firing (8 directions)
    SAM_N = 58,
    SAM_NE = 59,
    SAM_E = 60,
    SAM_SE = 61,
    SAM_S = 62,
    SAM_SW = 63,
    SAM_W = 64,
    SAM_NW = 65,
    -- Gun firing (8 directions)
    GUN_N = 66,
    GUN_NE = 67,
    GUN_E = 68,
    GUN_SE = 69,
    GUN_S = 70,
    GUN_SW = 71,
    GUN_W = 72,
    GUN_NW = 73,
    -- Special effects
    LZ_SMOKE = 74,
    ION_CANNON = 75,
    ATOM_BLAST = 76,
    -- Crate effects
    CRATE_DEVIATOR = 77,
    CRATE_DOLLAR = 78,
    CRATE_EARTH = 79,
    CRATE_EMPULSE = 80,
    CRATE_INVUN = 81,
    CRATE_MINE = 82,
    CRATE_RAPID = 83,
    CRATE_STEALTH = 84,
    CRATE_MISSILE = 85,
    -- More
    ATOM_DOOR = 86,
    MOVE_FLASH = 87,
    OILFIELD_BURN = 88,
    -- Dinosaur deaths
    TRIC_DIE = 89,
    TREX_DIE = 90,
    STEG_DIE = 91,
    RAPT_DIE = 92,
    CHEM_BALL = 93,
    FLAG = 94,
    BEACON = 95,
    COUNT = 96,
}

-- Sound types for animations (subset)
AnimTypeClass.VOC = {
    NONE = -1,
    CRUMBLE = 0,
    EXPLODE = 1,
    BURN = 2,
    SQUISH = 3,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new AnimTypeClass.

    @param ini_name - The INI control name (e.g., "FBALL1")
    @param name - The full display name (e.g., "Fireball")
]]
function AnimTypeClass:init(ini_name, name)
    -- Call parent constructor
    ObjectTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Animation Type Identifier
    --========================================================================

    --[[
        The specific animation type.
    ]]
    self.Type = AnimTypeClass.ANIM.NONE

    --========================================================================
    -- Animation Flags
    --========================================================================

    --[[
        Run at constant rate regardless of game speed?
    ]]
    self.IsNormalized = false

    --[[
        Rendered and sorted with ground units?
    ]]
    self.IsGroundLayer = false

    --[[
        Uses translucent rendering (reds/greys)?
    ]]
    self.IsTranslucent = false

    --[[
        Uses white translucent table?
    ]]
    self.IsWhiteTrans = false

    --[[
        Special flame thrower behavior?
    ]]
    self.IsFlameThrower = false

    --[[
        Leaves scorch marks on ground?
    ]]
    self.IsScorcher = false

    --[[
        Leaves craters (removes Tiberium)?
    ]]
    self.IsCraterForming = false

    --[[
        Attaches to units at same location?
    ]]
    self.IsSticky = false

    --========================================================================
    -- Frame Control
    --========================================================================

    --[[
        Maximum dimension for cell refresh list.
    ]]
    self.Size = 1

    --[[
        Frame where animation is largest (hides ground effects).
    ]]
    self.Biggest = 0

    --[[
        Frame delay between animation stages.
    ]]
    self.Delay = 1

    --[[
        Starting frame number.
    ]]
    self.Start = 0

    --[[
        Frame to start looping from.
    ]]
    self.LoopStart = 0

    --[[
        Frame where loops end.
    ]]
    self.LoopEnd = 0

    --[[
        Total number of animation stages.
    ]]
    self.Stages = 1

    --[[
        Normal loop count.
    ]]
    self.Loops = 1

    --========================================================================
    -- Effects
    --========================================================================

    --[[
        Fixed-point damage per tick to attached objects.
        (256 = 1 point of damage)
    ]]
    self.Damage = 0

    --[[
        Sound effect played when animation starts.
    ]]
    self.Sound = AnimTypeClass.VOC.NONE

    --[[
        Animation to transition into after completion.
    ]]
    self.ChainTo = AnimTypeClass.ANIM.NONE

    --========================================================================
    -- Default Properties
    --========================================================================

    -- Animations are not selectable or targetable
    self.IsSelectable = false
    self.IsLegalTarget = false
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this animation leaves scorch marks.
]]
function AnimTypeClass:Is_Scorcher()
    return self.IsScorcher
end

--[[
    Check if this animation creates craters.
]]
function AnimTypeClass:Is_Crater_Forming()
    return self.IsCraterForming
end

--[[
    Check if this animation sticks to objects.
]]
function AnimTypeClass:Is_Sticky()
    return self.IsSticky
end

--[[
    Get the number of stages in the animation.
]]
function AnimTypeClass:Get_Stages()
    return self.Stages
end

--[[
    Get the chain target animation.
]]
function AnimTypeClass:Get_Chain_To()
    return self.ChainTo
end

--[[
    Get the damage value (fixed-point, 256 = 1 HP).
]]
function AnimTypeClass:Get_Damage()
    return self.Damage
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined animation type.

    @param type - AnimType enum value
    @return New AnimTypeClass instance
]]
function AnimTypeClass.Create(type)
    local anim = nil

    if type == AnimTypeClass.ANIM.FBALL1 then
        anim = AnimTypeClass:new("FBALL1", "Large Fireball")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 2
        anim.Biggest = 7
        anim.IsScorcher = true
        anim.IsCraterForming = true
        anim.Sound = AnimTypeClass.VOC.EXPLODE

    elseif type == AnimTypeClass.ANIM.GRENADE then
        anim = AnimTypeClass:new("GRENADE", "Grenade Explosion")
        anim.Type = type
        anim.Stages = 22
        anim.Size = 2
        anim.Biggest = 11
        anim.IsScorcher = true
        anim.IsCraterForming = true

    elseif type == AnimTypeClass.ANIM.FRAG1 then
        anim = AnimTypeClass:new("FRAG1", "Fragment Explosion 1")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 2
        anim.Biggest = 7
        anim.Delay = 1

    elseif type == AnimTypeClass.ANIM.FRAG2 then
        anim = AnimTypeClass:new("FRAG2", "Fragment Explosion 2")
        anim.Type = type
        anim.Stages = 22
        anim.Size = 2
        anim.Biggest = 11
        anim.Delay = 2

    elseif type == AnimTypeClass.ANIM.VEH_HIT1 then
        anim = AnimTypeClass:new("VEH_HIT1", "Vehicle Hit 1")
        anim.Type = type
        anim.Stages = 7
        anim.Size = 1
        anim.Biggest = 3

    elseif type == AnimTypeClass.ANIM.VEH_HIT2 then
        anim = AnimTypeClass:new("VEH_HIT2", "Vehicle Hit 2")
        anim.Type = type
        anim.Stages = 7
        anim.Size = 1
        anim.Biggest = 3

    elseif type == AnimTypeClass.ANIM.VEH_HIT3 then
        anim = AnimTypeClass:new("VEH_HIT3", "Vehicle Hit 3")
        anim.Type = type
        anim.Stages = 11
        anim.Size = 1
        anim.Biggest = 5

    elseif type == AnimTypeClass.ANIM.ART_EXP1 then
        anim = AnimTypeClass:new("ART_EXP1", "Artillery Explosion")
        anim.Type = type
        anim.Stages = 22
        anim.Size = 2
        anim.Biggest = 11
        anim.IsScorcher = true
        anim.IsCraterForming = true

    elseif type == AnimTypeClass.ANIM.NAPALM1 then
        anim = AnimTypeClass:new("NAPALM1", "Small Napalm")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 1
        anim.Biggest = 7
        anim.Damage = 2  -- Per tick damage
        anim.IsSticky = true
        anim.IsScorcher = true

    elseif type == AnimTypeClass.ANIM.NAPALM2 then
        anim = AnimTypeClass:new("NAPALM2", "Medium Napalm")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 2
        anim.Biggest = 7
        anim.Damage = 3
        anim.IsSticky = true
        anim.IsScorcher = true

    elseif type == AnimTypeClass.ANIM.NAPALM3 then
        anim = AnimTypeClass:new("NAPALM3", "Large Napalm")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 3
        anim.Biggest = 7
        anim.Damage = 5
        anim.IsSticky = true
        anim.IsScorcher = true
        anim.IsCraterForming = true

    elseif type == AnimTypeClass.ANIM.SMOKE_PUFF then
        anim = AnimTypeClass:new("SMOKE_PUFF", "Smoke Puff")
        anim.Type = type
        anim.Stages = 8
        anim.Size = 1
        anim.IsTranslucent = true

    elseif type == AnimTypeClass.ANIM.PIFF then
        anim = AnimTypeClass:new("PIFF", "Piff")
        anim.Type = type
        anim.Stages = 4
        anim.Size = 1

    elseif type == AnimTypeClass.ANIM.PIFFPIFF then
        anim = AnimTypeClass:new("PIFFPIFF", "Piff Piff")
        anim.Type = type
        anim.Stages = 6
        anim.Size = 1

    elseif type == AnimTypeClass.ANIM.FIRE_SMALL then
        anim = AnimTypeClass:new("FIRE_SMALL", "Small Fire")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 1
        anim.Loops = 2
        anim.LoopStart = 0
        anim.LoopEnd = 14
        anim.Damage = 1
        anim.IsSticky = true

    elseif type == AnimTypeClass.ANIM.FIRE_MED then
        anim = AnimTypeClass:new("FIRE_MED", "Medium Fire")
        anim.Type = type
        anim.Stages = 14
        anim.Size = 2
        anim.Loops = 3
        anim.LoopStart = 0
        anim.LoopEnd = 14
        anim.Damage = 2
        anim.IsSticky = true

    elseif type == AnimTypeClass.ANIM.MUZZLE_FLASH then
        anim = AnimTypeClass:new("MUZZLE_FLASH", "Muzzle Flash")
        anim.Type = type
        anim.Stages = 5
        anim.Size = 1
        anim.IsTranslucent = true
        anim.IsNormalized = true

    elseif type == AnimTypeClass.ANIM.SMOKE_M then
        anim = AnimTypeClass:new("SMOKE_M", "Smoke")
        anim.Type = type
        anim.Stages = 22
        anim.Size = 2
        anim.Loops = 3
        anim.IsTranslucent = true

    elseif type == AnimTypeClass.ANIM.ION_CANNON then
        anim = AnimTypeClass:new("ION_CANNON", "Ion Cannon")
        anim.Type = type
        anim.Stages = 15
        anim.Size = 3
        anim.Biggest = 7
        anim.IsScorcher = true
        anim.IsCraterForming = true
        anim.Sound = AnimTypeClass.VOC.EXPLODE

    elseif type == AnimTypeClass.ANIM.ATOM_BLAST then
        anim = AnimTypeClass:new("ATOM_BLAST", "Nuclear Blast")
        anim.Type = type
        anim.Stages = 25
        anim.Size = 5
        anim.Biggest = 12
        anim.IsScorcher = true
        anim.IsCraterForming = true
        anim.Sound = AnimTypeClass.VOC.EXPLODE

    elseif type == AnimTypeClass.ANIM.LZ_SMOKE then
        anim = AnimTypeClass:new("LZ_SMOKE", "Landing Zone Smoke")
        anim.Type = type
        anim.Stages = 8
        anim.Size = 1
        anim.Loops = -1  -- Loop forever
        anim.IsTranslucent = true
        anim.IsGroundLayer = true

    elseif type == AnimTypeClass.ANIM.FLAG then
        anim = AnimTypeClass:new("FLAG", "Flag")
        anim.Type = type
        anim.Stages = 8
        anim.Size = 1
        anim.Loops = -1
        anim.IsGroundLayer = true

    elseif type == AnimTypeClass.ANIM.BEACON then
        anim = AnimTypeClass:new("BEACON", "Beacon")
        anim.Type = type
        anim.Stages = 8
        anim.Size = 1
        anim.Loops = -1

    else
        -- Default/unknown type
        anim = AnimTypeClass:new("ANIM", "Animation")
        anim.Type = type
    end

    return anim
end

--============================================================================
-- Debug Support
--============================================================================

function AnimTypeClass:Debug_Dump()
    ObjectTypeClass.Debug_Dump(self)

    print(string.format("AnimTypeClass: Type=%d Stages=%d Loops=%d",
        self.Type,
        self.Stages,
        self.Loops))

    print(string.format("  Frame: Start=%d LoopStart=%d LoopEnd=%d Delay=%d",
        self.Start,
        self.LoopStart,
        self.LoopEnd,
        self.Delay))

    print(string.format("  Effects: Scorcher=%s Crater=%s Sticky=%s Damage=%d",
        tostring(self.IsScorcher),
        tostring(self.IsCraterForming),
        tostring(self.IsSticky),
        self.Damage))
end

return AnimTypeClass
