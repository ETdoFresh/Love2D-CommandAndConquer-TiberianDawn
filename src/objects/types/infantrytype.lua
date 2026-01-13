--[[
    InfantryTypeClass - Type class for infantry units

    Port of TYPE.H InfantryTypeClass from the original C&C source.

    This class extends TechnoTypeClass to add infantry-specific properties:
    - Animation sequences (DoType actions)
    - Gender/civilian flags
    - Capture ability (engineers)
    - Fear responses

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TYPE.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/IDATA.CPP
]]

local Class = require("src.objects.class")
local TechnoTypeClass = require("src.objects.types.technotype")

-- Create InfantryTypeClass extending TechnoTypeClass
local InfantryTypeClass = Class.extend(TechnoTypeClass, "InfantryTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Infantry type identifiers
InfantryTypeClass.INFANTRY = {
    NONE = -1,
    E1 = 0,         -- Minigunner (M16)
    E2 = 1,         -- Grenadier
    E3 = 2,         -- Rocket Soldier (Bazooka)
    E4 = 3,         -- Flamethrower
    E5 = 4,         -- Chem Warrior
    E7 = 5,         -- Engineer
    RAMBO = 6,      -- Commando
    C1 = 7,         -- Civilian 1
    C2 = 8,         -- Civilian 2
    C3 = 9,         -- Civilian 3
    C4 = 10,        -- Civilian 4
    C5 = 11,        -- Civilian 5
    C6 = 12,        -- Civilian 6
    C7 = 13,        -- Civilian 7
    C8 = 14,        -- Civilian 8
    C9 = 15,        -- Civilian 9
    C10 = 16,       -- Nikoomba
    MOEBIUS = 17,   -- Dr. Moebius
    DELPHI = 18,    -- Agent Delphi
    CHAN = 19,      -- Dr. Chan
    COUNT = 20,
}

-- DoType - Animation action types (matches original DO_ enum)
InfantryTypeClass.DO = {
    NOTHING = 0,
    STAND_READY = 1,
    STAND_GUARD = 2,
    PRONE = 3,
    WALK = 4,
    FIRE_WEAPON = 5,
    LIE_DOWN = 6,
    CRAWL = 7,
    GET_UP = 8,
    FIRE_PRONE = 9,
    IDLE1 = 10,
    IDLE2 = 11,
    ON_GUARD = 12,
    FIGHT_READY = 13,
    PUNCH = 14,
    KICK = 15,
    PUNCH_HIT1 = 16,
    PUNCH_HIT2 = 17,
    PUNCH_DEATH = 18,
    KICK_HIT1 = 19,
    KICK_HIT2 = 20,
    KICK_DEATH = 21,
    READY_WEAPON = 22,
    GUN_DEATH = 23,
    EXPLOSION_DEATH = 24,
    EXPLOSION2_DEATH = 25,
    GRENADE_DEATH = 26,
    FIRE_DEATH = 27,
    GESTURE1 = 28,
    SALUTE1 = 29,
    GESTURE2 = 30,
    SALUTE2 = 31,
    PULL_GUN = 32,      -- Civilian only
    PLEAD = 33,         -- Civilian only
    PLEAD_DEATH = 34,   -- Civilian only
    COUNT = 35,
}

-- Infantry dimensions (fixed for all infantry)
InfantryTypeClass.INFANTRY_WIDTH = 12
InfantryTypeClass.INFANTRY_HEIGHT = 16

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new InfantryTypeClass.

    @param ini_name - The INI control name (e.g., "E1")
    @param name - The full display name (e.g., "Minigunner")
]]
function InfantryTypeClass:init(ini_name, name)
    -- Call parent constructor
    TechnoTypeClass.init(self, ini_name, name)

    --========================================================================
    -- Infantry Type Identifier
    --========================================================================

    --[[
        The specific infantry type.
    ]]
    self.Type = InfantryTypeClass.INFANTRY.NONE

    --========================================================================
    -- Infantry-Specific Boolean Flags
    --========================================================================

    --[[
        Is this a female character?
        Affects voice responses.
    ]]
    self.IsFemale = false

    --[[
        Has crawling animation (vs running while prone)?
    ]]
    self.IsCrawling = true

    --[[
        Can capture buildings? (Engineers)
    ]]
    self.IsCapture = false

    --[[
        Runs away when damaged? (Civilians, Flamethrowers)
    ]]
    self.IsFraidyCat = false

    --[[
        Is this a civilian unit?
    ]]
    self.IsCivilian = false

    --[[
        Avoids walking through Tiberium?
    ]]
    self.IsAvoidingTiberium = false

    --========================================================================
    -- Animation Data
    --========================================================================

    --[[
        Animation control data for each DoType action.
        Each entry has:
        - Frame: Starting frame
        - Count: Number of frames
        - Jump: Frames between facings (for 8 directions)
    ]]
    self.DoControls = {}
    for i = 0, InfantryTypeClass.DO.COUNT - 1 do
        self.DoControls[i] = {
            Frame = 0,
            Count = 1,
            Jump = 0,
        }
    end

    --[[
        Frame number when projectile is launched (standing).
    ]]
    self.FireLaunch = 0

    --[[
        Frame number when projectile is launched (prone).
    ]]
    self.ProneLaunch = 0

    --========================================================================
    -- Default Infantry Properties
    --========================================================================

    -- Infantry are always selectable
    self.IsSelectable = true
    self.IsLegalTarget = true

    -- Infantry always have ARMOR_NONE
    self.Armor = 0  -- ARMOR_NONE

    -- Default infantry sight range
    self.SightRange = 2

    -- Fixed dimensions for infantry
    self.Width = InfantryTypeClass.INFANTRY_WIDTH
    self.Height = InfantryTypeClass.INFANTRY_HEIGHT
end

--============================================================================
-- Animation Control
--============================================================================

--[[
    Set animation data for a specific DoType action.

    @param do_type - DoType action index
    @param frame - Starting frame
    @param count - Number of frames
    @param jump - Frames between facings
]]
function InfantryTypeClass:Set_Do_Control(do_type, frame, count, jump)
    if do_type >= 0 and do_type < InfantryTypeClass.DO.COUNT then
        self.DoControls[do_type] = {
            Frame = frame or 0,
            Count = count or 1,
            Jump = jump or 0,
        }
    end
end

--[[
    Get animation data for a specific DoType action.

    @param do_type - DoType action index
    @return Table with Frame, Count, Jump
]]
function InfantryTypeClass:Get_Do_Control(do_type)
    if do_type >= 0 and do_type < InfantryTypeClass.DO.COUNT then
        return self.DoControls[do_type]
    end
    return { Frame = 0, Count = 1, Jump = 0 }
end

--[[
    Get the starting frame for an action and facing.

    @param do_type - DoType action
    @param facing - Direction facing (0-7 for 8 directions)
    @return Starting frame number
]]
function InfantryTypeClass:Get_Action_Frame(do_type, facing)
    facing = facing or 0
    local control = self:Get_Do_Control(do_type)
    return control.Frame + (facing * control.Jump)
end

--[[
    Get the frame count for an action.

    @param do_type - DoType action
    @return Number of frames in the animation
]]
function InfantryTypeClass:Get_Action_Count(do_type)
    local control = self:Get_Do_Control(do_type)
    return control.Count
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this infantry type is a civilian.
]]
function InfantryTypeClass:Is_Civilian()
    return self.IsCivilian
end

--[[
    Check if this infantry can capture buildings.
]]
function InfantryTypeClass:Can_Capture()
    return self.IsCapture
end

--[[
    Check if this infantry is female.
]]
function InfantryTypeClass:Is_Female()
    return self.IsFemale
end

--[[
    Check if this is an engineer type.
]]
function InfantryTypeClass:Is_Engineer()
    return self.IsCapture
end

--[[
    Check if this infantry flees when damaged.
]]
function InfantryTypeClass:Is_Fraidy_Cat()
    return self.IsFraidyCat
end

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a predefined infantry type.

    @param type - InfantryType enum value
    @return New InfantryTypeClass instance
]]
function InfantryTypeClass.Create(type)
    local infantry = nil

    if type == InfantryTypeClass.INFANTRY.E1 then
        infantry = InfantryTypeClass:new("E1", "Minigunner")
        infantry.Type = type
        infantry.Cost = 100
        infantry.MaxStrength = 50
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        infantry.Risk = 1
        infantry.Reward = 2
        infantry.IsCrawling = true

    elseif type == InfantryTypeClass.INFANTRY.E2 then
        infantry = InfantryTypeClass:new("E2", "Grenadier")
        infantry.Type = type
        infantry.Cost = 160
        infantry.MaxStrength = 50
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.GRENADE
        infantry.Risk = 2
        infantry.Reward = 4
        infantry.IsCrawling = true

    elseif type == InfantryTypeClass.INFANTRY.E3 then
        infantry = InfantryTypeClass:new("E3", "Rocket Soldier")
        infantry.Type = type
        infantry.Cost = 300
        infantry.MaxStrength = 25
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.ROCKET
        infantry.Risk = 3
        infantry.Reward = 6
        infantry.IsCrawling = true

    elseif type == InfantryTypeClass.INFANTRY.E4 then
        infantry = InfantryTypeClass:new("E4", "Flamethrower")
        infantry.Type = type
        infantry.Cost = 200
        infantry.MaxStrength = 70
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.FLAMER
        infantry.Risk = 2
        infantry.Reward = 5
        infantry.IsCrawling = true
        infantry.IsFraidyCat = true

    elseif type == InfantryTypeClass.INFANTRY.E5 then
        infantry = InfantryTypeClass:new("E5", "Chem Warrior")
        infantry.Type = type
        infantry.Cost = 300
        infantry.MaxStrength = 70
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.FLAMER
        infantry.Risk = 2
        infantry.Reward = 5
        infantry.IsCrawling = true

    elseif type == InfantryTypeClass.INFANTRY.E7 then
        infantry = InfantryTypeClass:new("E7", "Engineer")
        infantry.Type = type
        infantry.Cost = 500
        infantry.MaxStrength = 25
        infantry.SightRange = 2
        infantry.MaxSpeed = TechnoTypeClass.MPH.SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.NONE
        infantry.Risk = 0
        infantry.Reward = 10
        infantry.IsCapture = true
        infantry.IsCrawling = true

    elseif type == InfantryTypeClass.INFANTRY.RAMBO then
        infantry = InfantryTypeClass:new("RMBO", "Commando")
        infantry.Type = type
        infantry.Cost = 1000
        infantry.MaxStrength = 80
        infantry.SightRange = 5
        infantry.MaxSpeed = TechnoTypeClass.MPH.MEDIUM_SLOW
        infantry.Primary = TechnoTypeClass.WEAPON.MACHINEGUN
        infantry.Risk = 5
        infantry.Reward = 20
        infantry.IsCrawling = true
        infantry.IsLeader = true

    else
        -- Default/unknown type
        infantry = InfantryTypeClass:new("E1", "Infantry")
        infantry.Type = type
    end

    return infantry
end

--============================================================================
-- Debug Support
--============================================================================

function InfantryTypeClass:Debug_Dump()
    TechnoTypeClass.Debug_Dump(self)

    print(string.format("InfantryTypeClass: Type=%d",
        self.Type))

    print(string.format("  Flags: Female=%s Crawling=%s Capture=%s FraidyCat=%s Civilian=%s",
        tostring(self.IsFemale),
        tostring(self.IsCrawling),
        tostring(self.IsCapture),
        tostring(self.IsFraidyCat),
        tostring(self.IsCivilian)))

    print(string.format("  Launch: Fire=%d Prone=%d",
        self.FireLaunch,
        self.ProneLaunch))
end

return InfantryTypeClass
