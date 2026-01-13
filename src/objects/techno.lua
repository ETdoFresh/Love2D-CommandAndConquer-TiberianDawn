--[[
    TechnoClass - Combat entity base class

    Port of TECHNO.H/CPP from the original C&C source.

    This class extends RadioClass and incorporates multiple mixins to provide
    the base functionality for all combat-capable game objects:
    - Buildings
    - Infantry
    - Vehicles (Units)
    - Aircraft

    TechnoClass inherits from:
        RadioClass (→ MissionClass → ObjectClass → AbstractClass)

    TechnoClass incorporates mixins:
        FlasherClass - Damage flash visual effect
        StageClass   - Animation frame staging
        CargoClass   - Transport cargo management
        DoorClass    - Door animation state
        CrewClass    - Kill tracking and survivor generation

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TECHNO.H
]]

local Class = require("src.objects.class")
local RadioClass = require("src.objects.radio")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Combat classes (lazy loaded to avoid circular deps)
local BulletClass = nil
local BulletTypeClass = nil
local WeaponTypeClass = nil
local AnimClass = nil
local AnimTypeClass = nil

-- Import mixins
local FlasherClass = require("src.objects.mixins.flasher")
local StageClass = require("src.objects.mixins.stage")
local CargoClass = require("src.objects.mixins.cargo")
local DoorClass = require("src.objects.mixins.door")
local CrewClass = require("src.objects.mixins.crew")

-- Create TechnoClass extending RadioClass
local TechnoClass = Class.extend(RadioClass, "TechnoClass")

-- Include all mixins
Class.include(TechnoClass, FlasherClass)
Class.include(TechnoClass, StageClass)
Class.include(TechnoClass, CargoClass)
Class.include(TechnoClass, DoorClass)
Class.include(TechnoClass, CrewClass)

--============================================================================
-- Constants
--============================================================================

-- Cloak states
TechnoClass.CLOAK = {
    UNCLOAKED = 0,      -- Not cloaked, fully visible
    CLOAKING = 1,       -- In process of cloaking
    CLOAKED = 2,        -- Fully cloaked, invisible
    UNCLOAKING = 3,     -- In process of uncloaking
}

-- Visual states (for rendering)
TechnoClass.VISUAL = {
    NORMAL = 0,
    INDISTINCT = 1,     -- Partially visible (cloaking/uncloaking)
    DARKEN = 2,         -- Darkened (friendly cloaked unit)
    SHADOWY = 3,        -- Shadow only (enemy cloaked unit)
    RIPPLE = 4,         -- Ripple effect (cloaked but detected)
    HIDDEN = 5,         -- Completely invisible
}

-- Fire error types
TechnoClass.FIRE_ERROR = {
    OK = 0,             -- Can fire
    AMMO = 1,           -- Out of ammo
    RANGE = 2,          -- Target out of range
    ILLEGAL = 3,        -- Cannot fire at this target type
    BUSY = 4,           -- Currently doing something else
    CLOAKED = 5,        -- Cannot fire while cloaked
    MOVING = 6,         -- Cannot fire while moving
    REARM = 7,          -- Still rearming
    ROTATING = 8,       -- Still rotating to face target
    FACING = 9,         -- Wrong facing
    NO_TARGET = 10,     -- No target specified
}

-- Body shape translation (fixes 45 degree angle rendering)
TechnoClass.BODY_SHAPE = {
    0, 1, 2, 3, 4, 5, 6, 7,
    8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23,
    24, 25, 26, 27, 28, 29, 30, 31,
}

-- Threat type flags (from DEFINES.H)
TechnoClass.THREAT = {
    NORMAL = 0x0000,        -- Any distance threat scan
    RANGE = 0x0001,         -- Limit scan to weapon range
    AREA = 0x0002,          -- Limit scan to general area (twice weapon range)
    AIR = 0x0004,           -- Scan for air units
    INFANTRY = 0x0008,      -- Scan for infantry units
    VEHICLES = 0x0010,      -- Scan for vehicles
    BUILDINGS = 0x0020,     -- Scan for buildings
    TIBERIUM = 0x0040,      -- Limit scan to Tiberium processing objects
    BOATS = 0x0080,         -- Scan for gunboats
    CIVILIANS = 0x0100,     -- Consider civilians to be primary target
    CAPTURE = 0x0200,       -- Consider capturable buildings only
}
-- Combined threat types
TechnoClass.THREAT.GROUND = bit.bor(
    TechnoClass.THREAT.VEHICLES,
    TechnoClass.THREAT.BUILDINGS,
    TechnoClass.THREAT.INFANTRY
)

--============================================================================
-- Constructor
--============================================================================

function TechnoClass:init(house)
    -- Call parent constructor
    RadioClass.init(self)

    -- Initialize all mixins
    FlasherClass.init(self)
    StageClass.init(self)
    CargoClass.init(self)
    DoorClass.init(self)
    CrewClass.init(self)

    --[[
        This flag will be true if the object has been damaged with malice.
        Damage received due to friendly fire or wear and tear does not count.
        The computer is not allowed to sell a building unless it has been
        damaged with malice.
    ]]
    self.IsTickedOff = false

    --[[
        If this object has inherited the ability to cloak, then this bit will
        be set to true.
    ]]
    self.IsCloakable = false

    --[[
        If this object is designated as special then this flag will be true. For
        buildings, this means that it is the primary factory. For units, it means
        that the unit is the team leader.
    ]]
    self.IsLeader = false

    --[[
        Certain units are flagged as "loaners". These units are typically transports
        that are created solely for the purpose of delivering reinforcements. Such
        "loaner" units are not owned by the player and thus cannot be directly
        controlled. These units will leave the game as soon as they have fulfilled
        their purpose.
    ]]
    self.IsALoaner = false

    --[[
        Once a unit enters the map, then this flag is set. This flag is used to make
        sure that a unit doesn't leave the map once it enters the map.
    ]]
    self.IsLocked = false

    --[[
        Buildings and units with turrets usually have a recoil animation when they
        fire. If this flag is true, then the next rendering of the object will be
        in the "recoil state". The flag will then be cleared pending the next
        firing event.
    ]]
    self.IsInRecoilState = false

    --[[
        If this unit is "loosely attached" to another unit it is given special
        processing. A unit is in such a condition when it is in the process of
        unloading from a transport type object. During the unloading process
        the transport object must stay still until the unit is free and clear.
        At that time it radios the transport object and the "tether" is broken -
        freeing both the unit and the transport object.
    ]]
    self.IsTethered = false

    --[[
        Is this object owned by the player? If not, then it is owned by the computer
        or remote opponent. This flag facilitates the many logic differences when
        dealing with player's or computer's units or buildings.
    ]]
    self.IsOwnedByPlayer = false

    --[[
        The more sophisticated game objects must keep track of whether they are
        discovered or not. This is because the state of discovery can often control
        how the object behaves. In addition, this fact is used in radar and user
        I/O processing.
    ]]
    self.IsDiscoveredByPlayer = false

    --[[
        This is used to control the computer recognizing this object.
    ]]
    self.IsDiscoveredByComputer = false

    --[[
        Some game objects can be of the "lemon" variety. This means that they take
        damage even when everything is ok. This adds a little variety to the game.
    ]]
    self.IsALemon = false

    --[[
        This flag is used to control second shot processing for those units or
        buildings that fire two shots in quick succession. When this flag is true,
        it indicates that the second shot is ready to fire. After this shot is
        fired, regular rearm timing is used rather than the short rearm time.
    ]]
    self.IsSecondShot = false

    --[[
        For units in area guard mode, this is the recorded home position. The
        guarding unit will try to stay near this location in the course of its
        maneuvers. This is also used to record a pending transport for those
        passengers that are waiting for the transport to become available. It is
        also used by harvesters so that they know where to head back to after
        unloading.
    ]]
    self.ArchiveTarget = Target.TARGET_NONE

    --[[
        This is the house that the unit belongs to.
    ]]
    self.House = nil

    -- Set house from parameter
    if house then
        self.House = house
        -- Determine if owned by player based on house
        -- This would check against PlayerPtr in the original
    end

    --[[
        This records the current cloak state for this vehicle.
    ]]
    self.Cloak = TechnoClass.CLOAK.UNCLOAKED

    --[[
        Cloaking device animation stage.
    ]]
    self.CloakStage = 0
    self.CloakTimer = 0

    --[[
        (Targeting Computer)
        This is the target value for the item that this vehicle should ATTACK.
        If this is a vehicle with a turret, then it may differ from its movement
        destination.
    ]]
    self.TarCom = Target.TARGET_NONE
    self.SuspendedTarCom = Target.TARGET_NONE

    --[[
        This is the visible facing for the unit or building.
        Stored as 0-255 direction value.
    ]]
    self.PrimaryFacing = 0

    --[[
        This is the arming countdown. It represents the time necessary
        to reload the weapon.
    ]]
    self.Arm = 0

    --[[
        The number of shots this object can fire before running out of ammo.
        If this value is zero, then firing is not allowed.
        If -1, then there is no ammunition limit.
    ]]
    self.Ammo = -1

    --[[
        Obelisk laser line data.
    ]]
    self.Lines = {}
    self.LineCount = 0
    self.LineFrame = 0
    self.LineMaxFrames = 0

    --[[
        This is the amount of money spent to produce this object.
    ]]
    self.PurchasePrice = 0

    --[[
        Per-player view of whether a techno object is discovered.
        One bit for each house type.
    ]]
    self.IsDiscoveredByPlayerMask = 0
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Get the refund amount for selling this object.
]]
function TechnoClass:Refund_Amount()
    -- Default is half the purchase price
    if self.PurchasePrice > 0 then
        return math.floor(self.PurchasePrice / 2)
    end

    -- If no purchase price recorded, use type cost
    local type_class = self:Techno_Type_Class()
    if type_class and type_class.Cost then
        return math.floor(type_class.Cost / 2)
    end

    return 0
end

--[[
    Get the TechnoTypeClass for this object.
    Override in derived classes.
]]
function TechnoClass:Techno_Type_Class()
    -- Override in derived classes
    return nil
end

--[[
    Get the armor type of this object.
    Returns ArmorType enum from warhead.lua

    @return ArmorType value
]]
function TechnoClass:Get_Armor()
    local type_class = self:Techno_Type_Class()
    if type_class and type_class.Armor then
        return type_class.Armor
    end
    return 0  -- ARMOR_NONE
end

--[[
    Check if this object is weapon equipped.
]]
function TechnoClass:Is_Weapon_Equipped()
    local type_class = self:Techno_Type_Class()
    return type_class and type_class.PrimaryWeapon ~= nil
end

--[[
    Check if this object can be repaired.
]]
function TechnoClass:Can_Repair()
    -- Default: not repairable
    return false
end

--[[
    Check if this is a TechnoClass (always true for this and derived).
]]
function TechnoClass:Is_Techno()
    return true
end

--[[
    Get the owner house type.
]]
function TechnoClass:Owner()
    if self.House then
        return self.House:Get_Type()
    end
    return 0
end

--[[
    Get the risk value (AI evaluation).
]]
function TechnoClass:Risk()
    local type_class = self:Techno_Type_Class()
    if type_class and type_class.Risk then
        return type_class.Risk
    end
    return 0
end

--[[
    Get the value (AI evaluation).
]]
function TechnoClass:Value()
    local type_class = self:Techno_Type_Class()
    if type_class and type_class.Reward then
        return type_class.Reward
    end
    return 0
end

--[[
    Get the rearm delay for weapons.

    @param second - If true, get delay for second weapon
]]
function TechnoClass:Rearm_Delay(second)
    local type_class = self:Techno_Type_Class()
    if type_class then
        if second and type_class.SecondaryWeapon then
            return type_class.SecondaryWeapon.ROF or 15
        elseif type_class.PrimaryWeapon then
            return type_class.PrimaryWeapon.ROF or 15
        end
    end
    return 15  -- Default 1 second at 15 FPS
end

--[[
    Get the tiberium load (for harvesters).
]]
function TechnoClass:Tiberium_Load()
    return 0  -- Override in UnitClass for harvesters
end

--[[
    Get pip count for display (cargo pips).
]]
function TechnoClass:Pip_Count()
    return self:How_Many()  -- From CargoClass mixin
end

--[[
    Get the fire direction.
]]
function TechnoClass:Fire_Direction()
    return self.PrimaryFacing
end

--============================================================================
-- User I/O
--============================================================================

--[[
    Called when this object is clicked as a target.

    @param house - House that clicked
    @param count - Flash count (default 7)
]]
function TechnoClass:Clicked_As_Target(house, count)
    count = count or 7
    self:Start_Flash(count)

    -- Per-player flash for multiplayer
    if house then
        self:Start_Flash_For_Player(house, count)
    end
end

--[[
    Select this object (add to selection).

    @param allow_mixed - Allow mixed unit types in selection
]]
function TechnoClass:Select(allow_mixed)
    -- Call parent select
    local result = RadioClass.Select(self)

    if result then
        self:Response_Select()
    end

    return result
end

--[[
    Voice response for selection.
    Override in derived classes.
]]
function TechnoClass:Response_Select()
    -- Override in derived classes
end

--[[
    Voice response for move command.
    Override in derived classes.
]]
function TechnoClass:Response_Move()
    -- Override in derived classes
end

--[[
    Voice response for attack command.
    Override in derived classes.
]]
function TechnoClass:Response_Attack()
    -- Override in derived classes
end

--[[
    Assign a mission from the player.

    @param order - MissionType
    @param target - Attack target
    @param destination - Movement destination
]]
function TechnoClass:Player_Assign_Mission(order, target, destination)
    target = target or Target.TARGET_NONE
    destination = destination or Target.TARGET_NONE

    -- Clear tether when receiving new orders
    if self.IsTethered then
        -- Would break contact with transport here
    end

    self:Assign_Mission(order)

    if Target.Is_Valid(target) then
        self:Assign_Target(target)
    end

    if Target.Is_Valid(destination) then
        self:Assign_Destination(destination)
    end
end

--============================================================================
-- Combat Functions
--============================================================================

--[[
    Notify base that it's being attacked.
    Used for AI responses.

    @param enemy - Attacking TechnoClass
]]
function TechnoClass:Base_Is_Attacked(enemy)
    if self.House then
        -- self.House:Base_Is_Attacked(enemy)
    end
end

--[[
    Kill all cargo when transport is destroyed.

    @param source - What killed us
]]
function TechnoClass:Kill_Cargo(source)
    while self:Is_Something_Attached() do
        local cargo = self:Detach_Object()
        if cargo then
            -- Kill the cargo
            if cargo.Take_Damage then
                local damage = 10000  -- Instant kill
                cargo:Take_Damage(damage, 0, 0, source)
            end
        end
    end
end

--[[
    Record this object being killed.

    @param source - Who killed us
]]
function TechnoClass:Record_The_Kill(source)
    if source and source.Made_A_Kill then
        source:Made_A_Kill()
    end

    if self.House then
        -- self.House:Tracking_Remove(self)
    end
end

--[[
    Check if target is in range.

    @param target - TARGET or COORDINATE or ObjectClass
    @param which - Weapon index (0=primary, 1=secondary)
]]
function TechnoClass:In_Range(target, which)
    which = which or 0

    local range = self:Weapon_Range(which)
    if range <= 0 then
        return false
    end

    local target_coord
    if type(target) == "number" then
        -- TARGET value
        if Target.Is_Valid(target) then
            local obj = Target.As_Object(target)
            if obj and obj.Center_Coord then
                target_coord = obj:Center_Coord()
            end
        else
            -- Assume it's a COORDINATE
            target_coord = target
        end
    elseif type(target) == "table" then
        -- ObjectClass
        if target.Target_Coord then
            target_coord = target:Target_Coord()
        elseif target.Center_Coord then
            target_coord = target:Center_Coord()
        end
    end

    if not target_coord then
        return false
    end

    local distance = self:Distance(target_coord)
    return distance <= range
end

--[[
    Check if we can fire at a target.

    @param target - TARGET to fire at
    @param which - Weapon index
    @return FireErrorType
]]
function TechnoClass:Can_Fire(target, which)
    which = which or 0

    -- No target
    if not Target.Is_Valid(target) then
        return TechnoClass.FIRE_ERROR.NO_TARGET
    end

    -- Check if we have a weapon
    if not self:Is_Weapon_Equipped() then
        return TechnoClass.FIRE_ERROR.ILLEGAL
    end

    -- Check ammo
    if self.Ammo == 0 then
        return TechnoClass.FIRE_ERROR.AMMO
    end

    -- Check arming
    if self.Arm > 0 then
        return TechnoClass.FIRE_ERROR.REARM
    end

    -- Check cloak state
    if self.Cloak == TechnoClass.CLOAK.CLOAKED then
        return TechnoClass.FIRE_ERROR.CLOAKED
    end

    -- Check range
    if not self:In_Range(target, which) then
        return TechnoClass.FIRE_ERROR.RANGE
    end

    return TechnoClass.FIRE_ERROR.OK
end

--[[
    Find the greatest threat in range.
    Port of TechnoClass::Greatest_Threat from TECHNO.CPP

    @param method - ThreatType flags
    @return TARGET of greatest threat, or TARGET_NONE
]]
function TechnoClass:Greatest_Threat(method)
    local Globals = require("src.heap.globals")
    local bit = bit or require("bit")

    local bestobject = nil
    local bestval = -1

    -- Build RTTI mask based on threat method
    local mask = 0
    if bit.band(method, TechnoClass.THREAT.CIVILIANS) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.BUILDING))
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.INFANTRY))
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.UNIT))
    end
    if bit.band(method, TechnoClass.THREAT.AIR) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.AIRCRAFT))
    end
    if bit.band(method, TechnoClass.THREAT.CAPTURE) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.BUILDING))
    end
    if bit.band(method, TechnoClass.THREAT.BUILDINGS) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.BUILDING))
    end
    if bit.band(method, TechnoClass.THREAT.INFANTRY) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.INFANTRY))
    end
    if bit.band(method, TechnoClass.THREAT.VEHICLES) ~= 0 then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.UNIT))
    end

    -- If method is NORMAL (0), scan for all ground threats
    if method == TechnoClass.THREAT.NORMAL then
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.BUILDING))
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.INFANTRY))
        mask = bit.bor(mask, bit.lshift(1, Target.RTTI.UNIT))
    end

    -- Determine scan range
    local range
    if bit.band(method, bit.bor(TechnoClass.THREAT.AREA, TechnoClass.THREAT.RANGE)) ~= 0 then
        range = self:Threat_Range(bit.band(method, TechnoClass.THREAT.RANGE) == 0 and 1 or 0)
    else
        -- Default: use weapon range
        range = math.max(self:Weapon_Range(0), self:Weapon_Range(1))
    end

    -- Convert range to cells (256 leptons per cell)
    local crange = math.floor(range / 256)
    if crange < 1 then crange = 5 end  -- Minimum scan radius
    if crange > 20 then crange = 20 end  -- Maximum scan radius

    local my_coord = self:Center_Coord()
    local my_cell = Coord.Coord_Cell(my_coord)
    local my_x = Coord.Cell_X(my_cell)
    local my_y = Coord.Cell_Y(my_cell)

    -- Scan object heaps for threats
    local rtti_list = {}
    if bit.band(mask, bit.lshift(1, Target.RTTI.INFANTRY)) ~= 0 then
        table.insert(rtti_list, Target.RTTI.INFANTRY)
    end
    if bit.band(mask, bit.lshift(1, Target.RTTI.UNIT)) ~= 0 then
        table.insert(rtti_list, Target.RTTI.UNIT)
    end
    if bit.band(mask, bit.lshift(1, Target.RTTI.BUILDING)) ~= 0 then
        table.insert(rtti_list, Target.RTTI.BUILDING)
    end
    if bit.band(mask, bit.lshift(1, Target.RTTI.AIRCRAFT)) ~= 0 then
        table.insert(rtti_list, Target.RTTI.AIRCRAFT)
    end

    -- Iterate through heaps and evaluate objects
    for _, rtti in ipairs(rtti_list) do
        local heap = Globals.Get_Heap(rtti)
        if heap then
            for i = 1, heap:Count() do
                local object = heap:Get(i)
                if object and object.IsActive and not object.IsInLimbo then
                    -- Check if enemy
                    if self:Is_Enemy(object) then
                        -- Get object location
                        local obj_coord = object:Center_Coord()
                        local obj_cell = Coord.Coord_Cell(obj_coord)
                        local obj_x = Coord.Cell_X(obj_cell)
                        local obj_y = Coord.Cell_Y(obj_cell)

                        -- Check distance in cells
                        local dx = math.abs(obj_x - my_x)
                        local dy = math.abs(obj_y - my_y)
                        local dist = math.max(dx, dy)

                        if dist <= crange then
                            -- Evaluate threat value
                            local value = self:Evaluate_Object(method, object, range)
                            if value > bestval then
                                bestobject = object
                                bestval = value
                            end
                        end
                    end
                end
            end
        end
    end

    if bestobject then
        return bestobject:As_Target()
    end
    return Target.TARGET_NONE
end

--[[
    Check if another object is an enemy.
    @param object - Object to check
    @return true if enemy
]]
function TechnoClass:Is_Enemy(object)
    if not object or not object.House then
        return false
    end
    if not self.House then
        return false
    end
    -- Different houses are enemies unless allied
    if object.House ~= self.House then
        -- Check alliance (simplified - would check House.Is_Ally)
        return true
    end
    return false
end

--[[
    Evaluate a potential target object.
    @param method - ThreatType flags
    @param object - Object to evaluate
    @param range - Maximum range
    @return Value (higher = better target)
]]
function TechnoClass:Evaluate_Object(method, object, range)
    if not object or not object.IsActive or object.IsInLimbo then
        return -1
    end

    -- Base value on distance (closer = higher value)
    local my_coord = self:Center_Coord()
    local obj_coord = object:Center_Coord()
    local dist = Coord.Distance(my_coord, obj_coord)

    -- Value inversely proportional to distance
    local value = math.max(0, range - dist)

    -- Bonus for damaged targets (easier to finish off)
    if object.Strength and object.Class and object.Class.MaxStrength then
        local health_pct = object.Strength / object.Class.MaxStrength
        if health_pct < 0.5 then
            value = value + 100  -- Bonus for half-dead targets
        end
    end

    -- Bonus for high-value targets
    local rtti = object:What_Am_I()
    if rtti == Target.RTTI.BUILDING then
        value = value + 50  -- Buildings are valuable targets
    end

    return value
end

--[[
    Get the threat scanning range.
    @param ctrl - 0=weapon range, 1=area range (2x weapon)
    @return Range in leptons
]]
function TechnoClass:Threat_Range(ctrl)
    local range = math.max(self:Weapon_Range(0), self:Weapon_Range(1))
    if ctrl == 1 then
        range = range * 2
    end
    -- Clamp range
    if range < 256 then range = 256 end
    if range > 5120 then range = 5120 end
    return range
end

--[[
    Try to target something nearby.
    Port of TechnoClass::Target_Something_Nearby from TECHNO.CPP

    @param method - ThreatType flags
    @return true if target was found and assigned
]]
function TechnoClass:Target_Something_Nearby(method)
    local threat = self:Greatest_Threat(method)
    if Target.Is_Valid(threat) then
        self:Assign_Target(threat)
        return true
    end
    return false
end

--[[
    Assign a target for attack.

    @param target - TARGET to attack
]]
function TechnoClass:Assign_Target(target)
    self.TarCom = target or Target.TARGET_NONE
end

--[[
    Override the current mission.

    @param mission - New mission
    @param tarcom - New attack target
    @param navcom - New navigation target (for FootClass)
]]
function TechnoClass:Override_Mission(mission, tarcom, navcom)
    -- Suspend current target
    self.SuspendedTarCom = self.TarCom

    -- Set new target
    if tarcom then
        self.TarCom = tarcom
    end

    -- Call parent override
    RadioClass.Override_Mission(self, mission)
end

--[[
    Restore the previous mission.
]]
function TechnoClass:Restore_Mission()
    -- Restore suspended target
    self.TarCom = self.SuspendedTarCom
    self.SuspendedTarCom = Target.TARGET_NONE

    -- Call parent restore
    return RadioClass.Restore_Mission(self)
end

--[[
    Fire at a target.

    @param target - TARGET to fire at
    @param which - Weapon index (0=primary)
    @return BulletClass or nil
]]
function TechnoClass:Fire_At(target, which)
    which = which or 0

    -- Check if we can fire
    local error = self:Can_Fire(target, which)
    if error ~= TechnoClass.FIRE_ERROR.OK then
        return nil
    end

    -- Lazy load combat classes to avoid circular dependencies
    if not BulletClass then
        BulletClass = require("src.objects.bullet")
        BulletTypeClass = require("src.objects.types.bullettype")
        WeaponTypeClass = require("src.combat.weapon")
        AnimClass = require("src.objects.anim")
        AnimTypeClass = require("src.objects.types.animtype")
    end

    -- Consume ammo
    if self.Ammo > 0 then
        self.Ammo = self.Ammo - 1
    end

    -- Start rearm timer
    self.Arm = self:Rearm_Delay(which > 0)

    -- Set recoil state
    self.IsInRecoilState = true

    -- Uncloak when firing
    if self.Cloak ~= TechnoClass.CLOAK.UNCLOAKED then
        self:Do_Uncloak()
    end

    -- Get weapon from type class
    local type_class = self:Techno_Type_Class()
    if not type_class then
        return nil
    end

    local weapon_type = nil
    if which == 0 then
        weapon_type = type_class.Primary
    else
        weapon_type = type_class.Secondary
    end

    if not weapon_type or weapon_type < 0 then
        return nil
    end

    -- Get weapon definition
    local weapon = WeaponTypeClass.Get(weapon_type)
    if not weapon then
        return nil
    end

    -- Get bullet type from weapon
    local bullet_type = BulletTypeClass.Create(weapon.Fires)
    if not bullet_type then
        return nil
    end

    -- Create bullet
    local bullet = BulletClass:new(bullet_type)
    bullet.Payback = self  -- Attribute kills to firer

    -- Get fire position (muzzle)
    local fire_coord = self:Fire_Coord(which)

    -- Get target coordinate
    local target_coord = nil
    if type(target) == "table" and target.Center_Coord then
        target_coord = target:Center_Coord()
        bullet.TarCom = target
    elseif Target.Is_Valid(target) then
        local obj = Target.As_Object(target)
        if obj then
            target_coord = obj:Center_Coord()
            bullet.TarCom = obj
        else
            target_coord = Target.As_Coord(target)
        end
    else
        target_coord = target  -- Assume it's a coordinate
    end

    -- Calculate facing to target
    local facing = 0
    if fire_coord and target_coord then
        facing = Coord.Direction_To(fire_coord, target_coord)
    end

    -- Inherit inaccuracy
    if self.IsInaccurate or (type_class and type_class.IsInaccurate) then
        bullet.IsInaccurate = true
    end

    -- Spawn the bullet
    if bullet:Unlimbo(fire_coord, facing, target_coord) then
        -- Spawn muzzle flash animation
        if weapon.Anim >= 0 then
            local anim_type = AnimTypeClass.Create(weapon.Anim)
            if anim_type then
                local anim = AnimClass:new(anim_type, fire_coord, 0, 1, false)
                anim.OwnerHouse = self.House
            end
        end

        -- Play firing sound
        -- (would call Sound.Play here)

        return bullet
    end

    return nil
end

--[[
    Get the weapon range.

    @param which - Weapon index
    @return Range in leptons
]]
function TechnoClass:Weapon_Range(which)
    local type_class = self:Techno_Type_Class()
    if type_class then
        local weapon
        if which > 0 and type_class.SecondaryWeapon then
            weapon = type_class.SecondaryWeapon
        else
            weapon = type_class.PrimaryWeapon
        end

        if weapon and weapon.Range then
            return weapon.Range
        end
    end

    return 0
end

--[[
    Handle being captured by another house.

    @param newowner - New HouseClass
    @return true if captured successfully
]]
function TechnoClass:Captured(newowner)
    if newowner == nil then
        return false
    end

    -- Change ownership
    local oldowner = self.House
    self.House = newowner

    -- Update player ownership flag
    self.IsOwnedByPlayer = newowner:Is_Player_Control()

    return true
end

--[[
    Take damage from an attack.

    @param damage - Damage amount (reference - may be modified)
    @param distance - Distance from explosion center
    @param warhead - WarheadType
    @param source - Attacking TechnoClass
    @return ResultType (0=none, 1=light, 2=heavy, 3=destroyed)
]]
function TechnoClass:Take_Damage(damage, distance, warhead, source)
    -- Call parent take damage
    local result = RadioClass.Take_Damage(self, damage, distance, warhead, source)

    -- Mark as ticked off if damaged by enemy
    if damage > 0 and source and source.House ~= self.House then
        self.IsTickedOff = true
    end

    -- Flash when hit
    if damage > 0 then
        self:Start_Flash(3)
    end

    return result
end

--============================================================================
-- Cloaking
--============================================================================

--[[
    Check if this object appears cloaked to a house.

    @param house - House checking (HouseClass or HousesType)
]]
function TechnoClass:Is_Cloaked(house)
    if self.Cloak == TechnoClass.CLOAK.UNCLOAKED then
        return false
    end

    -- Own units are never fully cloaked
    if self.House == house then
        return false
    end

    return self.Cloak == TechnoClass.CLOAK.CLOAKED
end

--[[
    Start cloaking process.
]]
function TechnoClass:Do_Cloak()
    if not self.IsCloakable then
        return
    end

    if self.Cloak == TechnoClass.CLOAK.UNCLOAKED then
        self.Cloak = TechnoClass.CLOAK.CLOAKING
        self.CloakStage = 0
        self.CloakTimer = 1
    end
end

--[[
    Start uncloaking process.
]]
function TechnoClass:Do_Uncloak()
    if self.Cloak == TechnoClass.CLOAK.CLOAKED then
        self.Cloak = TechnoClass.CLOAK.UNCLOAKING
        self.CloakStage = 38  -- Full cloak stages
        self.CloakTimer = 1
    elseif self.Cloak == TechnoClass.CLOAK.CLOAKING then
        self.Cloak = TechnoClass.CLOAK.UNCLOAKING
        -- CloakStage keeps current value
        self.CloakTimer = 1
    end
end

--[[
    Shimmer effect (briefly visible while cloaked).
]]
function TechnoClass:Do_Shimmer()
    if self.Cloak == TechnoClass.CLOAK.CLOAKED then
        -- Temporarily make visible
        self.CloakTimer = 4
    end
end

--[[
    Get the visual rendering type based on cloak state.

    @param raw - If true, return raw visual without modifications
]]
function TechnoClass:Visual_Character(raw)
    if raw then
        return TechnoClass.VISUAL.NORMAL
    end

    if self.Cloak == TechnoClass.CLOAK.CLOAKED then
        return TechnoClass.VISUAL.HIDDEN
    elseif self.Cloak == TechnoClass.CLOAK.CLOAKING or
           self.Cloak == TechnoClass.CLOAK.UNCLOAKING then
        return TechnoClass.VISUAL.INDISTINCT
    end

    return TechnoClass.VISUAL.NORMAL
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for TechnoClass.
    Called every game tick.
]]
function TechnoClass:AI()
    -- Call parent AI
    RadioClass.AI(self)

    -- Process flasher
    self:Process()

    -- Process animation stage
    self:Graphic_Logic()

    -- Process door
    self:AI_Door()

    -- Process arming countdown
    if self.Arm > 0 then
        self.Arm = self.Arm - 1
    end

    -- Clear recoil state after one frame
    self.IsInRecoilState = false

    -- Process cloaking
    if self.Cloak == TechnoClass.CLOAK.CLOAKING then
        self.CloakTimer = self.CloakTimer - 1
        if self.CloakTimer <= 0 then
            self.CloakTimer = 1
            self.CloakStage = self.CloakStage + 1
            if self.CloakStage >= 38 then
                self.Cloak = TechnoClass.CLOAK.CLOAKED
            end
        end

    elseif self.Cloak == TechnoClass.CLOAK.UNCLOAKING then
        self.CloakTimer = self.CloakTimer - 1
        if self.CloakTimer <= 0 then
            self.CloakTimer = 1
            self.CloakStage = self.CloakStage - 1
            if self.CloakStage <= 0 then
                self.Cloak = TechnoClass.CLOAK.UNCLOAKED
            end
        end
    end
end

--[[
    Reveal this object to a house.

    @param house - HouseClass to reveal to
    @return true if newly revealed
]]
function TechnoClass:Revealed(house)
    if house == nil then
        return false
    end

    -- Set discovery bit
    local house_type = house:Get_Type()
    local bit = 2 ^ house_type
    if (self.IsDiscoveredByPlayerMask % (bit * 2)) >= bit then
        return false  -- Already discovered
    end

    self.IsDiscoveredByPlayerMask = self.IsDiscoveredByPlayerMask + bit
    return true
end

--============================================================================
-- Map Entry/Exit
--============================================================================

--[[
    Place object on the map.

    @param coord - COORDINATE to place at
    @param facing - Initial facing direction
    @return true if successfully placed
]]
function TechnoClass:Unlimbo(coord, facing)
    if facing then
        self.PrimaryFacing = facing
    end

    -- Call parent unlimbo
    return RadioClass.Unlimbo(self, coord, facing)
end

--[[
    Remove target references when target is removed.

    @param target - TARGET being removed
    @param all - If true, remove all references
]]
function TechnoClass:Detach(target, all)
    -- Clear TarCom if it matches
    if self.TarCom == target then
        self.TarCom = Target.TARGET_NONE
    end

    if self.SuspendedTarCom == target then
        self.SuspendedTarCom = Target.TARGET_NONE
    end

    if self.ArchiveTarget == target then
        self.ArchiveTarget = Target.TARGET_NONE
    end

    -- Call parent detach
    RadioClass.Detach(self, target, all)
end

--============================================================================
-- Movement Stubs (Override in FootClass)
--============================================================================

--[[
    Assign a movement destination.
    Override in FootClass.
]]
function TechnoClass:Assign_Destination(target)
    -- Override in FootClass
end

--[[
    Scatter from position.
    Override in FootClass.
]]
function TechnoClass:Scatter(source, forced, nokidding)
    -- Override in FootClass
end

--[[
    Enter idle mode.
    Override in derived classes.
]]
function TechnoClass:Enter_Idle_Mode(initial)
    self:Assign_Mission(self.MISSION.GUARD)
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function TechnoClass:Code_Pointers()
    local data = RadioClass.Code_Pointers(self)

    -- Flags
    data.IsTickedOff = self.IsTickedOff
    data.IsCloakable = self.IsCloakable
    data.IsLeader = self.IsLeader
    data.IsALoaner = self.IsALoaner
    data.IsLocked = self.IsLocked
    data.IsTethered = self.IsTethered
    data.IsOwnedByPlayer = self.IsOwnedByPlayer
    data.IsDiscoveredByPlayer = self.IsDiscoveredByPlayer
    data.IsDiscoveredByComputer = self.IsDiscoveredByComputer
    data.IsALemon = self.IsALemon
    data.IsSecondShot = self.IsSecondShot

    -- Targets
    data.ArchiveTarget = self.ArchiveTarget
    data.TarCom = self.TarCom
    data.SuspendedTarCom = self.SuspendedTarCom

    -- House (encode as type)
    if self.House then
        data.HouseType = self.House:Get_Type()
    end

    -- Combat state
    data.Cloak = self.Cloak
    data.CloakStage = self.CloakStage
    data.PrimaryFacing = self.PrimaryFacing
    data.Arm = self.Arm
    data.Ammo = self.Ammo
    data.PurchasePrice = self.PurchasePrice
    data.IsDiscoveredByPlayerMask = self.IsDiscoveredByPlayerMask

    -- Mixin data
    data.Flasher = self:Code_Pointers_Flasher()
    data.Stage = self:Code_Pointers_Stage()
    data.Cargo = self:Code_Pointers_Cargo()
    data.Door = self:Code_Pointers_Door()
    data.Crew = self:Code_Pointers_Crew()

    return data
end

function TechnoClass:Decode_Pointers(data, heap_lookup)
    RadioClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        -- Flags
        self.IsTickedOff = data.IsTickedOff or false
        self.IsCloakable = data.IsCloakable or false
        self.IsLeader = data.IsLeader or false
        self.IsALoaner = data.IsALoaner or false
        self.IsLocked = data.IsLocked or false
        self.IsTethered = data.IsTethered or false
        self.IsOwnedByPlayer = data.IsOwnedByPlayer or false
        self.IsDiscoveredByPlayer = data.IsDiscoveredByPlayer or false
        self.IsDiscoveredByComputer = data.IsDiscoveredByComputer or false
        self.IsALemon = data.IsALemon or false
        self.IsSecondShot = data.IsSecondShot or false

        -- Targets
        self.ArchiveTarget = data.ArchiveTarget or Target.TARGET_NONE
        self.TarCom = data.TarCom or Target.TARGET_NONE
        self.SuspendedTarCom = data.SuspendedTarCom or Target.TARGET_NONE

        -- House type (resolve later)
        self._decode_house_type = data.HouseType

        -- Combat state
        self.Cloak = data.Cloak or TechnoClass.CLOAK.UNCLOAKED
        self.CloakStage = data.CloakStage or 0
        self.PrimaryFacing = data.PrimaryFacing or 0
        self.Arm = data.Arm or 0
        self.Ammo = data.Ammo or -1
        self.PurchasePrice = data.PurchasePrice or 0
        self.IsDiscoveredByPlayerMask = data.IsDiscoveredByPlayerMask or 0

        -- Mixin data
        if data.Flasher then self:Decode_Pointers_Flasher(data.Flasher) end
        if data.Stage then self:Decode_Pointers_Stage(data.Stage) end
        if data.Cargo then self:Decode_Pointers_Cargo(data.Cargo) end
        if data.Door then self:Decode_Pointers_Door(data.Door) end
        if data.Crew then self:Decode_Pointers_Crew(data.Crew) end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function TechnoClass:Debug_Dump()
    RadioClass.Debug_Dump(self)

    local house_name = self.House and self.House:Get_Name() or "none"
    print(string.format("TechnoClass: House=%s Cloak=%d TarCom=%s",
        house_name,
        self.Cloak,
        Target.Target_As_String(self.TarCom)))

    print(string.format("  Arm=%d Ammo=%d Facing=%d",
        self.Arm,
        self.Ammo,
        self.PrimaryFacing))

    print(string.format("  Flags: TickedOff=%s Cloakable=%s Leader=%s Loaner=%s",
        tostring(self.IsTickedOff),
        tostring(self.IsCloakable),
        tostring(self.IsLeader),
        tostring(self.IsALoaner)))

    -- Dump mixin state
    self:Debug_Dump_Flasher()
    self:Debug_Dump_Stage()
    self:Debug_Dump_Cargo()
    self:Debug_Dump_Door()
    self:Debug_Dump_Crew()
end

return TechnoClass
