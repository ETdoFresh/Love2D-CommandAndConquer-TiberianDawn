--[[
    WeaponTypeClass - Weapon type definitions

    Port of weapon data from the original C&C source.

    Weapons define how units attack:
    - Bullet type (projectile spawned)
    - Damage value
    - Rate of fire (cooldown between shots)
    - Range
    - Sound and animation effects

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/CONST.CPP
]]

local Class = require("src.objects.class")
local BulletTypeClass = require("src.objects.types.bullettype")
local AnimTypeClass = require("src.objects.types.animtype")

-- Create WeaponTypeClass
local WeaponTypeClass = {}
WeaponTypeClass.__index = WeaponTypeClass

--============================================================================
-- Constants
--============================================================================

-- Weapon type identifiers (matches WeaponType in DEFINES.H)
WeaponTypeClass.WEAPON = {
    NONE = -1,
    RIFLE = 0,          -- Sniper rifle
    CHAIN_GUN = 1,      -- Spread fire chain gun
    PISTOL = 2,         -- Civilian pistol
    M16 = 3,            -- Standard rifle
    DRAGON = 4,         -- Dragon anti-tank missile
    FLAMETHROWER = 5,   -- Infantry flamethrower
    FLAME_TONGUE = 6,   -- Vehicle flamethrower
    CHEMSPRAY = 7,      -- Chemical sprayer
    GRENADE = 8,        -- Grenade launcher
    _75MM = 9,          -- 75mm cannon
    _105MM = 10,        -- 105mm cannon
    _120MM = 11,        -- 120mm cannon
    TURRET_GUN = 12,    -- Base turret gun
    MAMMOTH_TUSK = 13,  -- Mammoth tank missiles
    MLRS = 14,          -- MLRS rocket system
    _155MM = 15,        -- 155mm artillery
    M60MG = 16,         -- M60 machine gun
    TOMAHAWK = 17,      -- Tomahawk cruise missile
    TOW_TWO = 18,       -- TOW-2 missile
    NAPALM = 19,        -- Napalm bombs (aircraft)
    OBELISK_LASER = 20, -- Obelisk of Light laser
    NIKE = 21,          -- SAM site missiles
    HONEST_JOHN = 22,   -- Honest John rocket
    STEG = 23,          -- Stegosaurus attack
    TREX = 24,          -- T-Rex attack
    COUNT = 25,
}

-- Sound types (subset)
WeaponTypeClass.VOC = {
    NONE = -1,
    RIFLE = 0,
    MACHINEGUN = 1,
    CANNON = 2,
    ROCKET = 3,
    LASER = 4,
    FLAMER = 5,
    GRENADE = 6,
    SNIPER = 7,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new WeaponTypeClass.

    @param name - Name of weapon type
]]
function WeaponTypeClass:new(name)
    local obj = setmetatable({}, self)

    --[[
        Name of this weapon type.
    ]]
    obj.Name = name or "Unknown"

    --[[
        Type identifier.
    ]]
    obj.Type = WeaponTypeClass.WEAPON.NONE

    --[[
        The projectile type this weapon launches.
    ]]
    obj.Fires = BulletTypeClass.BULLET.NONE

    --[[
        Damage value of the projectile.
    ]]
    obj.Attack = 0

    --[[
        Rate of fire (countdown timer between shots).
        Lower = faster firing.
    ]]
    obj.ROF = 60

    --[[
        Maximum range in leptons (256 leptons = 1 cell).
    ]]
    obj.Range = 0x0400  -- 4 cells default

    --[[
        Sound effect when firing.
    ]]
    obj.Sound = WeaponTypeClass.VOC.NONE

    --[[
        Animation to display at firing coordinate.
    ]]
    obj.Anim = AnimTypeClass.ANIM.NONE

    return obj
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Get the range in cells.
]]
function WeaponTypeClass:Range_In_Cells()
    return math.floor(self.Range / 256)
end

--[[
    Get the bullet type this weapon fires.
]]
function WeaponTypeClass:Get_Bullet_Type()
    return self.Fires
end

--[[
    Check if this weapon is effective vs aircraft.
]]
function WeaponTypeClass:Is_Anti_Aircraft()
    local bullet_type = BulletTypeClass.Create(self.Fires)
    return bullet_type and bullet_type.IsAntiAircraft
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined weapon type.

    @param type - WeaponType enum value
    @return New WeaponTypeClass instance
]]
function WeaponTypeClass.Create(type)
    local weapon = WeaponTypeClass:new()

    if type == WeaponTypeClass.WEAPON.RIFLE then
        -- Sniper rifle
        weapon.Name = "Sniper Rifle"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SNIPER
        weapon.Attack = 125
        weapon.ROF = 40
        weapon.Range = 0x0580  -- 5.5 cells
        weapon.Sound = WeaponTypeClass.VOC.SNIPER
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.CHAIN_GUN then
        -- Chain gun
        weapon.Name = "Chain Gun"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SPREADFIRE
        weapon.Attack = 25
        weapon.ROF = 50
        weapon.Range = 0x0400  -- 4 cells
        weapon.Sound = WeaponTypeClass.VOC.MACHINEGUN
        weapon.Anim = AnimTypeClass.ANIM.GUN_N

    elseif type == WeaponTypeClass.WEAPON.PISTOL then
        -- Pistol
        weapon.Name = "Pistol"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.BULLET
        weapon.Attack = 1
        weapon.ROF = 7
        weapon.Range = 0x01C0  -- 1.75 cells
        weapon.Sound = WeaponTypeClass.VOC.RIFLE
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.M16 then
        -- M16 rifle
        weapon.Name = "M16"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.BULLET
        weapon.Attack = 15
        weapon.ROF = 20
        weapon.Range = 0x0200  -- 2 cells
        weapon.Sound = WeaponTypeClass.VOC.MACHINEGUN
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.DRAGON then
        -- Dragon missile
        weapon.Name = "Dragon"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.TOW
        weapon.Attack = 30
        weapon.ROF = 60
        weapon.Range = 0x0400  -- 4 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.FLAMETHROWER then
        -- Infantry flamethrower
        weapon.Name = "Flamethrower"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.FLAME
        weapon.Attack = 35
        weapon.ROF = 50
        weapon.Range = 0x0200  -- 2 cells
        weapon.Sound = WeaponTypeClass.VOC.FLAMER
        weapon.Anim = AnimTypeClass.ANIM.FLAME_N

    elseif type == WeaponTypeClass.WEAPON.FLAME_TONGUE then
        -- Vehicle flamethrower
        weapon.Name = "Flame Tongue"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.FLAME
        weapon.Attack = 50
        weapon.ROF = 50
        weapon.Range = 0x0200  -- 2 cells
        weapon.Sound = WeaponTypeClass.VOC.FLAMER
        weapon.Anim = AnimTypeClass.ANIM.FLAME_N

    elseif type == WeaponTypeClass.WEAPON.CHEMSPRAY then
        -- Chemical sprayer
        weapon.Name = "Chem Spray"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.CHEMSPRAY
        weapon.Attack = 80
        weapon.ROF = 70
        weapon.Range = 0x0200  -- 2 cells
        weapon.Sound = WeaponTypeClass.VOC.FLAMER
        weapon.Anim = AnimTypeClass.ANIM.CHEM_N

    elseif type == WeaponTypeClass.WEAPON.GRENADE then
        -- Grenade
        weapon.Name = "Grenade"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.GRENADE
        weapon.Attack = 50
        weapon.ROF = 60
        weapon.Range = 0x0340  -- 3.25 cells
        weapon.Sound = WeaponTypeClass.VOC.GRENADE
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON._75MM then
        -- 75mm cannon
        weapon.Name = "75mm"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.APDS
        weapon.Attack = 25
        weapon.ROF = 60
        weapon.Range = 0x0400  -- 4 cells
        weapon.Sound = WeaponTypeClass.VOC.CANNON
        weapon.Anim = AnimTypeClass.ANIM.MUZZLE_FLASH

    elseif type == WeaponTypeClass.WEAPON._105MM then
        -- 105mm cannon
        weapon.Name = "105mm"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.APDS
        weapon.Attack = 30
        weapon.ROF = 50
        weapon.Range = 0x04C0  -- 4.75 cells
        weapon.Sound = WeaponTypeClass.VOC.CANNON
        weapon.Anim = AnimTypeClass.ANIM.MUZZLE_FLASH

    elseif type == WeaponTypeClass.WEAPON._120MM then
        -- 120mm cannon
        weapon.Name = "120mm"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.APDS
        weapon.Attack = 40
        weapon.ROF = 80
        weapon.Range = 0x04C0  -- 4.75 cells
        weapon.Sound = WeaponTypeClass.VOC.CANNON
        weapon.Anim = AnimTypeClass.ANIM.MUZZLE_FLASH

    elseif type == WeaponTypeClass.WEAPON.TURRET_GUN then
        -- Base turret gun
        weapon.Name = "Turret Gun"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.APDS
        weapon.Attack = 40
        weapon.ROF = 60
        weapon.Range = 0x0600  -- 6 cells
        weapon.Sound = WeaponTypeClass.VOC.CANNON
        weapon.Anim = AnimTypeClass.ANIM.MUZZLE_FLASH

    elseif type == WeaponTypeClass.WEAPON.MAMMOTH_TUSK then
        -- Mammoth missiles
        weapon.Name = "Mammoth Tusk"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SSM
        weapon.Attack = 75
        weapon.ROF = 80
        weapon.Range = 0x0500  -- 5 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.MLRS then
        -- MLRS rockets
        weapon.Name = "MLRS"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SSM2
        weapon.Attack = 75
        weapon.ROF = 80
        weapon.Range = 0x0600  -- 6 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON._155MM then
        -- 155mm artillery
        weapon.Name = "155mm"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.HE
        weapon.Attack = 150
        weapon.ROF = 65
        weapon.Range = 0x0600  -- 6 cells
        weapon.Sound = WeaponTypeClass.VOC.CANNON
        weapon.Anim = AnimTypeClass.ANIM.MUZZLE_FLASH

    elseif type == WeaponTypeClass.WEAPON.M60MG then
        -- M60 machine gun
        weapon.Name = "M60"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.BULLET
        weapon.Attack = 15
        weapon.ROF = 30
        weapon.Range = 0x0400  -- 4 cells
        weapon.Sound = WeaponTypeClass.VOC.MACHINEGUN
        weapon.Anim = AnimTypeClass.ANIM.GUN_N

    elseif type == WeaponTypeClass.WEAPON.TOMAHAWK then
        -- Tomahawk missile
        weapon.Name = "Tomahawk"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SSM
        weapon.Attack = 60
        weapon.ROF = 35
        weapon.Range = 0x0780  -- 7.5 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.TOW_TWO then
        -- TOW-2 missile
        weapon.Name = "TOW-2"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SSM
        weapon.Attack = 60
        weapon.ROF = 40
        weapon.Range = 0x0680  -- 6.5 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.NAPALM then
        -- Napalm bombs
        weapon.Name = "Napalm"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.NAPALM
        weapon.Attack = 100
        weapon.ROF = 20
        weapon.Range = 0x0480  -- 4.5 cells
        weapon.Sound = WeaponTypeClass.VOC.NONE
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.OBELISK_LASER then
        -- Obelisk laser
        weapon.Name = "Obelisk Laser"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.LASER
        weapon.Attack = 200
        weapon.ROF = 90
        weapon.Range = 0x0780  -- 7.5 cells
        weapon.Sound = WeaponTypeClass.VOC.LASER
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.NIKE then
        -- SAM missiles
        weapon.Name = "Nike SAM"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.SAM
        weapon.Attack = 50
        weapon.ROF = 50
        weapon.Range = 0x0780  -- 7.5 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.HONEST_JOHN then
        -- Honest John rocket
        weapon.Name = "Honest John"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.HONEST_JOHN
        weapon.Attack = 100
        weapon.ROF = 200
        weapon.Range = 0x0A00  -- 10 cells
        weapon.Sound = WeaponTypeClass.VOC.ROCKET
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.STEG then
        -- Stegosaurus
        weapon.Name = "Stegosaurus"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.HEADBUTT
        weapon.Attack = 100
        weapon.ROF = 30
        weapon.Range = 0x0180  -- 1.5 cells
        weapon.Sound = WeaponTypeClass.VOC.NONE
        weapon.Anim = AnimTypeClass.ANIM.NONE

    elseif type == WeaponTypeClass.WEAPON.TREX then
        -- T-Rex
        weapon.Name = "T-Rex"
        weapon.Type = type
        weapon.Fires = BulletTypeClass.BULLET.TREXBITE
        weapon.Attack = 155
        weapon.ROF = 30
        weapon.Range = 0x0180  -- 1.5 cells
        weapon.Sound = WeaponTypeClass.VOC.NONE
        weapon.Anim = AnimTypeClass.ANIM.NONE

    else
        weapon.Name = "Unknown"
        weapon.Type = type
    end

    return weapon
end

--============================================================================
-- Global Weapon Table
--============================================================================

-- Pre-create all weapon types for lookup
WeaponTypeClass.Weapons = {}

function WeaponTypeClass.Init()
    for i = 0, WeaponTypeClass.WEAPON.COUNT - 1 do
        WeaponTypeClass.Weapons[i] = WeaponTypeClass.Create(i)
    end
end

--[[
    Get a weapon by type.

    @param type - WeaponType enum value
    @return WeaponTypeClass instance
]]
function WeaponTypeClass.Get(type)
    if not WeaponTypeClass.Weapons[0] then
        WeaponTypeClass.Init()
    end
    return WeaponTypeClass.Weapons[type]
end

--============================================================================
-- Debug Support
--============================================================================

function WeaponTypeClass:Debug_Dump()
    print(string.format("WeaponTypeClass: %s Type=%d",
        self.Name,
        self.Type))

    print(string.format("  Combat: Damage=%d ROF=%d Range=%d (%.1f cells)",
        self.Attack,
        self.ROF,
        self.Range,
        self.Range / 256))

    print(string.format("  Fires: BulletType=%d Sound=%d Anim=%d",
        self.Fires,
        self.Sound,
        self.Anim))
end

return WeaponTypeClass
