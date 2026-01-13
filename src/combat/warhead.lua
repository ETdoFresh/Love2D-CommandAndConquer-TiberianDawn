--[[
    WarheadTypeClass - Warhead type definitions for damage calculations

    Port of warhead data from the original C&C source.

    Warheads define how damage is applied:
    - Armor modifiers (effectiveness vs each armor type)
    - Spread factor (damage falloff with distance)
    - Special effects (wall destruction, tiberium damage)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/CONST.CPP
]]

local Class = require("src.objects.class")

-- Create WarheadTypeClass
local WarheadTypeClass = {}
WarheadTypeClass.__index = WarheadTypeClass

--============================================================================
-- Constants
--============================================================================

-- Warhead type identifiers (matches WarheadType in DEFINES.H)
WarheadTypeClass.WARHEAD = {
    NONE = -1,
    SA = 0,             -- Small arms - good against infantry
    HE = 1,             -- High explosive - good against buildings & infantry
    AP = 2,             -- Armor piercing - good against armor
    FIRE = 3,           -- Incendiary - good against flammables
    LASER = 4,          -- Laser
    PB = 5,             -- Particle beam (neutron beam)
    FIST = 6,           -- Punching in hand-to-hand
    FOOT = 7,           -- Kicking in hand-to-hand
    HOLLOW_POINT = 8,   -- Sniper bullet
    SPORE = 9,          -- Blossom tree spores
    HEADBUTT = 10,      -- Dinosaur headbutt
    FEEDME = 11,        -- T-Rex bite
    COUNT = 12,
}

-- Armor types (matches ArmorType in DEFINES.H)
WarheadTypeClass.ARMOR = {
    NONE = 0,       -- Vulnerable to SA and HE
    WOOD = 1,       -- Vulnerable to HE and Fire
    ALUMINUM = 2,   -- Vulnerable to AP and SA
    STEEL = 3,      -- Vulnerable to AP
    CONCRETE = 4,   -- Vulnerable to HE and AP
    COUNT = 5,
}

-- Modifier value constants (fixed-point where 0x100 = 100%)
WarheadTypeClass.MOD = {
    FULL = 0x100,       -- 100%
    THREE_QUARTER = 0xC0, -- 75%
    HALF = 0x80,        -- 50%
    QUARTER = 0x40,     -- 25%
    EIGHTH = 0x20,      -- 12.5%
    SIXTEENTH = 0x10,   -- 6.25%
    TINY = 0x08,        -- 3.125%
    MINIMAL = 0x01,     -- ~0.4%
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new WarheadTypeClass.

    @param name - Name of warhead type
]]
function WarheadTypeClass:new(name)
    local obj = setmetatable({}, self)

    --[[
        Name of this warhead type.
    ]]
    obj.Name = name or "Unknown"

    --[[
        Type identifier.
    ]]
    obj.Type = WarheadTypeClass.WARHEAD.NONE

    --[[
        Spread factor - damage reduction over distance.
        Higher = less reduction (1 = fast falloff, 255 = no falloff).
    ]]
    obj.SpreadFactor = 4

    --[[
        Can destroy concrete walls?
    ]]
    obj.IsWallDestroyer = false

    --[[
        Can destroy wooden walls/fences?
    ]]
    obj.IsWoodDestroyer = false

    --[[
        Does this warhead damage tiberium?
    ]]
    obj.IsTiberiumDestroyer = false

    --[[
        Damage modifier per armor type.
        Values are fixed-point where 0x100 = 100% damage.
        Indexed by ARMOR type.
    ]]
    obj.Modifier = {
        [0] = 0x100,  -- ARMOR_NONE
        [1] = 0x100,  -- ARMOR_WOOD
        [2] = 0x100,  -- ARMOR_ALUMINUM
        [3] = 0x100,  -- ARMOR_STEEL
        [4] = 0x100,  -- ARMOR_CONCRETE
    }

    return obj
end

--============================================================================
-- Damage Calculation
--============================================================================

--[[
    Calculate modified damage vs an armor type.

    @param base_damage - Raw damage value
    @param armor - ArmorType enum value
    @return Modified damage value
]]
function WarheadTypeClass:Modify_Damage(base_damage, armor)
    armor = armor or 0
    if armor < 0 or armor >= WarheadTypeClass.ARMOR.COUNT then
        armor = 0
    end

    local modifier = self.Modifier[armor] or 0x100
    return math.floor((base_damage * modifier) / 0x100)
end

--[[
    Calculate damage at a distance from impact.

    @param base_damage - Raw damage value
    @param distance - Distance from impact in leptons
    @return Damage at that distance
]]
function WarheadTypeClass:Distance_Damage(base_damage, distance)
    if self.SpreadFactor >= 255 then
        return base_damage  -- No falloff
    end

    if distance <= 0 then
        return base_damage  -- At impact point
    end

    -- Linear falloff based on spread factor
    -- Higher spread = slower falloff
    local falloff = math.floor(distance / (self.SpreadFactor * 16))
    local damage = base_damage - falloff

    return math.max(0, damage)
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined warhead type.

    @param type - WarheadType enum value
    @return New WarheadTypeClass instance
]]
function WarheadTypeClass.Create(type)
    local warhead = WarheadTypeClass:new()

    if type == WarheadTypeClass.WARHEAD.SA then
        -- Small Arms - good against infantry, weak vs armor
        warhead.Name = "Small Arms"
        warhead.Type = type
        warhead.SpreadFactor = 2
        warhead.IsWallDestroyer = false
        warhead.IsWoodDestroyer = false
        warhead.IsTiberiumDestroyer = false
        warhead.Modifier = {
            [0] = 0x100,  -- NONE: 100%
            [1] = 0x80,   -- WOOD: 50%
            [2] = 0x90,   -- ALUMINUM: 56%
            [3] = 0x40,   -- STEEL: 25%
            [4] = 0x40,   -- CONCRETE: 25%
        }

    elseif type == WarheadTypeClass.WARHEAD.HE then
        -- High Explosive - good vs buildings and infantry
        warhead.Name = "High Explosive"
        warhead.Type = type
        warhead.SpreadFactor = 6
        warhead.IsWallDestroyer = true
        warhead.IsWoodDestroyer = true
        warhead.IsTiberiumDestroyer = true
        warhead.Modifier = {
            [0] = 0xE0,   -- NONE: 87%
            [1] = 0xC0,   -- WOOD: 75%
            [2] = 0x90,   -- ALUMINUM: 56%
            [3] = 0x40,   -- STEEL: 25%
            [4] = 0x100,  -- CONCRETE: 100%
        }

    elseif type == WarheadTypeClass.WARHEAD.AP then
        -- Armor Piercing - good vs armor
        warhead.Name = "Armor Piercing"
        warhead.Type = type
        warhead.SpreadFactor = 6
        warhead.IsWallDestroyer = true
        warhead.IsWoodDestroyer = true
        warhead.IsTiberiumDestroyer = false
        warhead.Modifier = {
            [0] = 0x40,   -- NONE: 25%
            [1] = 0xC0,   -- WOOD: 75%
            [2] = 0xC0,   -- ALUMINUM: 75%
            [3] = 0x100,  -- STEEL: 100%
            [4] = 0x80,   -- CONCRETE: 50%
        }

    elseif type == WarheadTypeClass.WARHEAD.FIRE then
        -- Fire/Incendiary - good vs flammables
        warhead.Name = "Fire"
        warhead.Type = type
        warhead.SpreadFactor = 8
        warhead.IsWallDestroyer = false
        warhead.IsWoodDestroyer = true
        warhead.IsTiberiumDestroyer = true
        warhead.Modifier = {
            [0] = 0xE0,   -- NONE: 87%
            [1] = 0x100,  -- WOOD: 100%
            [2] = 0xB0,   -- ALUMINUM: 69%
            [3] = 0x40,   -- STEEL: 25%
            [4] = 0x80,   -- CONCRETE: 50%
        }

    elseif type == WarheadTypeClass.WARHEAD.LASER then
        -- Laser - consistent damage
        warhead.Name = "Laser"
        warhead.Type = type
        warhead.SpreadFactor = 4
        warhead.IsWallDestroyer = false
        warhead.IsWoodDestroyer = false
        warhead.IsTiberiumDestroyer = false
        warhead.Modifier = {
            [0] = 0x100,  -- All 100%
            [1] = 0x100,
            [2] = 0x100,
            [3] = 0x100,
            [4] = 0x100,
        }

    elseif type == WarheadTypeClass.WARHEAD.PB then
        -- Particle Beam
        warhead.Name = "Particle Beam"
        warhead.Type = type
        warhead.SpreadFactor = 7
        warhead.IsWallDestroyer = true
        warhead.IsWoodDestroyer = true
        warhead.IsTiberiumDestroyer = true
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0x100,
            [2] = 0xC0,
            [3] = 0xC0,
            [4] = 0xC0,
        }

    elseif type == WarheadTypeClass.WARHEAD.FIST then
        -- Fist (melee)
        warhead.Name = "Fist"
        warhead.Type = type
        warhead.SpreadFactor = 4
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0x20,
            [2] = 0x20,
            [3] = 0x10,
            [4] = 0x10,
        }

    elseif type == WarheadTypeClass.WARHEAD.FOOT then
        -- Foot (melee)
        warhead.Name = "Foot"
        warhead.Type = type
        warhead.SpreadFactor = 4
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0x20,
            [2] = 0x20,
            [3] = 0x10,
            [4] = 0x10,
        }

    elseif type == WarheadTypeClass.WARHEAD.HOLLOW_POINT then
        -- Hollow Point (sniper)
        warhead.Name = "Hollow Point"
        warhead.Type = type
        warhead.SpreadFactor = 4
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0x08,
            [2] = 0x08,
            [3] = 0x08,
            [4] = 0x08,
        }

    elseif type == WarheadTypeClass.WARHEAD.SPORE then
        -- Spore (blossom tree)
        warhead.Name = "Spore"
        warhead.Type = type
        warhead.SpreadFactor = 255  -- No falloff
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0x01,
            [2] = 0x01,
            [3] = 0x01,
            [4] = 0x01,
        }

    elseif type == WarheadTypeClass.WARHEAD.HEADBUTT then
        -- Dinosaur headbutt
        warhead.Name = "Headbutt"
        warhead.Type = type
        warhead.SpreadFactor = 1
        warhead.IsWallDestroyer = true
        warhead.IsWoodDestroyer = true
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0xC0,
            [2] = 0x80,
            [3] = 0x20,
            [4] = 0x08,
        }

    elseif type == WarheadTypeClass.WARHEAD.FEEDME then
        -- T-Rex bite
        warhead.Name = "T-Rex Bite"
        warhead.Type = type
        warhead.SpreadFactor = 1
        warhead.IsWallDestroyer = true
        warhead.IsWoodDestroyer = true
        warhead.Modifier = {
            [0] = 0x100,
            [1] = 0xC0,
            [2] = 0x80,
            [3] = 0x20,
            [4] = 0x08,
        }

    else
        warhead.Name = "Unknown"
        warhead.Type = type
    end

    return warhead
end

--============================================================================
-- Global Warhead Table
--============================================================================

-- Pre-create all warhead types for lookup
WarheadTypeClass.Warheads = {}

function WarheadTypeClass.Init()
    for i = 0, WarheadTypeClass.WARHEAD.COUNT - 1 do
        WarheadTypeClass.Warheads[i] = WarheadTypeClass.Create(i)
    end
end

--[[
    Get a warhead by type.

    @param type - WarheadType enum value
    @return WarheadTypeClass instance
]]
function WarheadTypeClass.Get(type)
    if not WarheadTypeClass.Warheads[0] then
        WarheadTypeClass.Init()
    end
    return WarheadTypeClass.Warheads[type]
end

--============================================================================
-- Debug Support
--============================================================================

function WarheadTypeClass:Debug_Dump()
    print(string.format("WarheadTypeClass: %s Type=%d Spread=%d",
        self.Name,
        self.Type,
        self.SpreadFactor))

    print(string.format("  Destroys: Wall=%s Wood=%s Tiberium=%s",
        tostring(self.IsWallDestroyer),
        tostring(self.IsWoodDestroyer),
        tostring(self.IsTiberiumDestroyer)))

    print(string.format("  Modifiers: NONE=%d%% WOOD=%d%% ALUM=%d%% STEEL=%d%% CONCRETE=%d%%",
        math.floor(self.Modifier[0] * 100 / 0x100),
        math.floor(self.Modifier[1] * 100 / 0x100),
        math.floor(self.Modifier[2] * 100 / 0x100),
        math.floor(self.Modifier[3] * 100 / 0x100),
        math.floor(self.Modifier[4] * 100 / 0x100)))
end

return WarheadTypeClass
