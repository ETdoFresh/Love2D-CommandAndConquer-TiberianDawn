--[[
    InfantryClass - Infantry unit implementation

    Port of INFANTRY.H/CPP from the original C&C source.

    Infantry are foot soldiers that can:
    - Move in 8 directions with smooth animation
    - Go prone when frightened or ordered
    - Panic and flee when fear is high
    - Enter buildings and transports
    - Be crushed by vehicles

    Key systems:
    - Fear: Infantry accumulate fear from combat, affecting behavior
    - DoType: Animation states for various actions
    - Occupier bits: Track which sub-cell positions infantry occupy

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/INFANTRY.H/CPP
]]

local Class = require("src.objects.class")
local FootClass = require("src.objects.foot")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create InfantryClass extending FootClass
local InfantryClass = Class.extend(FootClass, "InfantryClass")

--============================================================================
-- Constants
--============================================================================

-- Fear levels - higher values mean more afraid
InfantryClass.FEAR = {
    NONE = 0,           -- Not afraid at all
    ANXIOUS = 10,       -- Starting to worry
    SCARED = 100,       -- Getting scared
    PANIC = 200,        -- Panicking - will run
    MAXIMUM = 255,      -- Maximum fear level
}

-- Fear adjustment rates
InfantryClass.FEAR_DECAY = 1        -- Fear decreases by this per tick
InfantryClass.FEAR_ATTACK = 50      -- Fear increase when taking fire
InfantryClass.FEAR_EXPLOSION = 100  -- Fear increase from nearby explosion

-- DoType - Animation states for infantry
InfantryClass.DO = {
    NOTHING = 0,        -- No special animation
    STAND_GUARD = 1,    -- Standing guard animation
    STAND_READY = 2,    -- Standing ready (looking around)
    GUARD = 3,          -- Guard pose
    PRONE = 4,          -- Lying prone
    WALK = 5,           -- Walking animation
    FIRE_WEAPON = 6,    -- Firing primary weapon (standing)
    LIE_DOWN = 7,       -- Transition to prone
    CRAWL = 8,          -- Crawling while prone
    GET_UP = 9,         -- Getting up from prone
    FIRE_PRONE = 10,    -- Firing while prone
    IDLE1 = 11,         -- First idle animation
    IDLE2 = 12,         -- Second idle animation
    DIE1 = 13,          -- Death animation 1
    DIE2 = 14,          -- Death animation 2 (more violent)
    DIE3 = 15,          -- Death animation 3 (burned)
    DIE4 = 16,          -- Death animation 4 (crushed)
    DIE5 = 17,          -- Death animation 5 (special)
    SALUTE1 = 18,       -- Salute animation
    SALUTE2 = 19,       -- Alternative salute
    GESTURE1 = 20,      -- Gesture 1
    GESTURE2 = 21,      -- Gesture 2
}

-- StopType - What the infantry is currently stopped doing
InfantryClass.STOP = {
    NONE = 0,
    STANDING = 1,
    PRONE = 2,
    CRAWLING = 3,
    WALKING = 4,
}

-- Sub-cell positions for infantry (5 positions per cell)
InfantryClass.SUBCELL = {
    CENTER = 0,     -- Cell center (used by non-infantry)
    UPPER_LEFT = 1,
    UPPER_RIGHT = 2,
    LOWER_LEFT = 3,
    LOWER_RIGHT = 4,
}

-- Infantry movement constants
InfantryClass.INFANTRY_SPEED = 3    -- Base movement speed in leptons/tick

--============================================================================
-- RTTI (Runtime Type Information)
--============================================================================

--[[
    Get the RTTI type for InfantryClass.
    Used for TARGET encoding and heap lookup.
]]
function InfantryClass:get_rtti()
    return Target.RTTI.INFANTRY
end

--[[
    Get the object type identifier (same as RTTI for classes).
]]
function InfantryClass:What_Am_I()
    return Target.RTTI.INFANTRY
end

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new InfantryClass.

    @param type - InfantryTypeClass defining this infantry
    @param house - HouseClass owner
]]
function InfantryClass:init(type, house)
    -- Call parent constructor
    FootClass.init(self, house)

    -- Store type reference
    self.Class = type

    --[[
        Current fear level. Fear causes infantry to seek cover,
        go prone, or flee in panic.
    ]]
    self.Fear = InfantryClass.FEAR.NONE

    --[[
        Current animation action being performed.
    ]]
    self.Doing = InfantryClass.DO.NOTHING

    --[[
        Current stopped state (what pose while not moving).
    ]]
    self.Stop = InfantryClass.STOP.STANDING

    --[[
        Is this infantry currently prone?
        Prone infantry have better defense but move slower.
    ]]
    self.IsProne = false

    --[[
        Is this infantry a technician?
        Technicians can repair buildings.
    ]]
    self.IsTechnician = false

    --[[
        Has this infantry been "stoked" (morale boost)?
    ]]
    self.IsStoked = false

    --[[
        Is this infantry in a boxing match?
        (Easter egg combat mode)
    ]]
    self.IsBoxing = false

    --[[
        The sub-cell position this infantry occupies within a cell.
        Infantry can share cells by occupying different sub-positions.
    ]]
    self.Occupy = InfantryClass.SUBCELL.CENTER

    --[[
        Target sub-cell position when moving within a cell.
    ]]
    self.ToSubCell = InfantryClass.SUBCELL.CENTER

    --[[
        Timer for various animations.
    ]]
    self.IdleTimer = 0

    --[[
        Comment timer for voice responses.
    ]]
    self.Comment = 0

    -- Set initial type-based properties
    if type then
        self.Ammo = type.MaxAmmo or -1
        self.IsTechnician = type.IsTechnician or false
    end
end

--============================================================================
-- Type Access
--============================================================================

--[[
    Get the InfantryTypeClass for this infantry.
]]
function InfantryClass:Techno_Type_Class()
    return self.Class
end

--[[
    Get the infantry type class (alias).
]]
function InfantryClass:Class_Of()
    return self.Class
end

--============================================================================
-- Fear System
--============================================================================

--[[
    Get current fear level.
]]
function InfantryClass:Get_Fear()
    return self.Fear
end

--[[
    Add fear to this infantry.

    @param amount - Amount of fear to add
]]
function InfantryClass:Add_Fear(amount)
    self.Fear = math.min(InfantryClass.FEAR.MAXIMUM,
                         self.Fear + (amount or 0))

    -- Check if fear level triggers behavior change
    if self.Fear >= InfantryClass.FEAR.PANIC then
        -- Might cause infantry to panic and flee
        self:Response_Panic()
    end
end

--[[
    Reduce fear over time.
]]
function InfantryClass:Reduce_Fear()
    if self.Fear > 0 then
        self.Fear = math.max(0, self.Fear - InfantryClass.FEAR_DECAY)
    end
end

--[[
    Check if infantry is panicking.
]]
function InfantryClass:Is_Panicking()
    return self.Fear >= InfantryClass.FEAR.PANIC
end

--[[
    Check if infantry is scared but not panicking.
]]
function InfantryClass:Is_Scared()
    return self.Fear >= InfantryClass.FEAR.SCARED and
           self.Fear < InfantryClass.FEAR.PANIC
end

--[[
    Response to fear reaching panic level.
]]
function InfantryClass:Response_Panic()
    -- Override current orders and flee
    -- Derived classes may handle this differently (e.g., engineers don't flee)
end

--============================================================================
-- Prone System
--============================================================================

--[[
    Check if infantry is prone.
]]
function InfantryClass:Is_Prone()
    return self.IsProne
end

--[[
    Make infantry go prone.
]]
function InfantryClass:Go_Prone()
    if not self.IsProne then
        self.IsProne = true
        self.Stop = InfantryClass.STOP.PRONE

        -- Start lie down animation
        self:Do_Action(InfantryClass.DO.LIE_DOWN)
    end
end

--[[
    Make infantry get up from prone position.
]]
function InfantryClass:Get_Up()
    if self.IsProne then
        -- Start get up animation
        self:Do_Action(InfantryClass.DO.GET_UP)

        -- The actual flag is cleared when animation completes
    end
end

--[[
    Clear prone state (called when animation completes).
]]
function InfantryClass:Clear_Prone()
    self.IsProne = false
    self.Stop = InfantryClass.STOP.STANDING
end

--============================================================================
-- Animation Actions
--============================================================================

--[[
    Perform an action (animation).

    @param action - DoType to perform
    @param force - Force action even if busy
    @return true if action was started
]]
function InfantryClass:Do_Action(action, force)
    -- Check if we can change action
    if not force and self.Doing ~= InfantryClass.DO.NOTHING then
        -- Check if current action can be interrupted
        if self.Doing == InfantryClass.DO.FIRE_WEAPON or
           self.Doing == InfantryClass.DO.FIRE_PRONE or
           self.Doing == InfantryClass.DO.LIE_DOWN or
           self.Doing == InfantryClass.DO.GET_UP then
            return false  -- Can't interrupt these
        end
    end

    self.Doing = action

    -- Reset animation frame
    self:Set_Stage(0)

    return true
end

--[[
    Get the current action being performed.
]]
function InfantryClass:Get_Action()
    return self.Doing
end

--[[
    Clear the current action (animation completed).
]]
function InfantryClass:Clear_Action()
    -- Handle action completion
    if self.Doing == InfantryClass.DO.LIE_DOWN then
        -- Now fully prone
        self.IsProne = true
        self.Doing = InfantryClass.DO.PRONE
    elseif self.Doing == InfantryClass.DO.GET_UP then
        -- Now standing
        self:Clear_Prone()
        self.Doing = InfantryClass.DO.NOTHING
    else
        self.Doing = InfantryClass.DO.NOTHING
    end
end

--============================================================================
-- Sub-Cell Occupancy
--============================================================================

--[[
    Get the current sub-cell position.
]]
function InfantryClass:Get_Occupy()
    return self.Occupy
end

--[[
    Set the sub-cell position.

    @param subcell - SUBCELL value
]]
function InfantryClass:Set_Occupy(subcell)
    self.Occupy = subcell or InfantryClass.SUBCELL.CENTER
end

--[[
    Set the cell's occupier bit for this infantry.
    This marks the sub-cell as occupied.

    @param cell - CELL to mark
]]
function InfantryClass:Set_Occupy_Bit(cell)
    -- Would mark the cell's occupancy bitmap
    -- Full implementation requires CellClass integration
end

--[[
    Clear the cell's occupier bit for this infantry.

    @param cell - CELL to clear
]]
function InfantryClass:Clear_Occupy_Bit(cell)
    -- Would clear the cell's occupancy bitmap
    -- Full implementation requires CellClass integration
end

--[[
    Find a free sub-cell in the given cell.

    @param cell - CELL to check
    @return SUBCELL value or -1 if no free spot
]]
function InfantryClass:Find_Free_Subcell(cell)
    -- Simplified - full implementation checks cell occupancy
    return InfantryClass.SUBCELL.CENTER
end

--============================================================================
-- Movement
--============================================================================

--[[
    Start moving to a coordinate.
    Infantry have special movement handling.

    @param headto - COORDINATE to move to
    @return true if movement started
]]
function InfantryClass:Start_Driver(headto)
    local result = FootClass.Start_Driver(self, headto)

    if result then
        -- Start walking animation
        if self.IsProne then
            self:Do_Action(InfantryClass.DO.CRAWL)
        else
            self:Do_Action(InfantryClass.DO.WALK)
        end
    end

    return result
end

--[[
    Stop movement.
]]
function InfantryClass:Stop_Driver()
    FootClass.Stop_Driver(self)

    -- Stop walking animation
    self:Do_Action(InfantryClass.DO.NOTHING)
end

--[[
    Called when infantry enters the center of a cell.
]]
function InfantryClass:Per_Cell_Process(center)
    FootClass.Per_Cell_Process(self, center)

    if center then
        -- Update occupancy
        local cell = Coord.Coord_Cell(self:Center_Coord())
        self:Set_Occupy_Bit(cell)
    end
end

--[[
    Calculate movement speed.
    Prone infantry move slower.
]]
function InfantryClass:Get_Speed()
    local speed = InfantryClass.INFANTRY_SPEED

    -- Prone infantry move at half speed
    if self.IsProne then
        speed = math.floor(speed / 2)
    end

    -- Apply type speed modifier
    if self.Class and self.Class.MaxSpeed then
        speed = math.floor(speed * self.Class.MaxSpeed / 100)
    end

    return math.max(1, speed)
end

--============================================================================
-- Combat
--============================================================================

--[[
    Fire at a target.
    Infantry use different animations when prone.
]]
function InfantryClass:Fire_At(target, which)
    -- Start firing animation
    if self.IsProne then
        self:Do_Action(InfantryClass.DO.FIRE_PRONE)
    else
        self:Do_Action(InfantryClass.DO.FIRE_WEAPON)
    end

    return FootClass.Fire_At(self, target, which)
end

--[[
    Take damage.
    Infantry react to damage with fear and may go prone.
]]
function InfantryClass:Take_Damage(damage, distance, warhead, source)
    -- Add fear from being attacked
    if damage > 0 then
        self:Add_Fear(InfantryClass.FEAR_ATTACK)

        -- Chance to go prone when taking fire
        if not self.IsProne and self.Fear >= InfantryClass.FEAR.SCARED then
            if math.random() < 0.5 then
                self:Go_Prone()
            end
        end
    end

    return FootClass.Take_Damage(self, damage, distance, warhead, source)
end

--[[
    Scatter from a threat.
    Infantry scatter more readily than vehicles.
]]
function InfantryClass:Scatter(source, forced, nokidding)
    -- Add fear from nearby threat
    if source then
        self:Add_Fear(InfantryClass.FEAR_EXPLOSION)
    end

    -- If panicking, get up and run
    if self.IsProne and self:Is_Panicking() then
        self:Get_Up()
    end

    FootClass.Scatter(self, source, forced, nokidding)
end

--============================================================================
-- Mission Implementations
--============================================================================

--[[
    Attack mission - infantry-specific attack behavior.
    Port of InfantryClass::Mission_Attack from INFANTRY.CPP

    Special case: Engineers (E7) will capture buildings instead of attacking them.
    All other infantry use the standard FootClass attack behavior.
]]
function InfantryClass:Mission_Attack()
    -- Check if we're an engineer attacking a building
    if self.Class and self.Class.IsCapture then
        -- Check if target is a building
        if Target.Is_Valid(self.TarCom) then
            local target_rtti = Target.Get_RTTI(self.TarCom)
            if target_rtti == Target.RTTI.BUILDING then
                -- Engineer attacking building - switch to capture mission
                self:Assign_Destination(self.TarCom)
                self:Assign_Mission(self.MISSION.CAPTURE)
                return 1  -- Immediate return (process next tick)
            end
        end
    end

    -- Not an engineer or not targeting building - use standard attack
    return FootClass.Mission_Attack(self)
end

--[[
    Guard mission - infantry look around while guarding.
]]
function InfantryClass:Mission_Guard()
    -- Reduce fear while idle
    self:Reduce_Fear()

    -- Random idle animations
    self.IdleTimer = self.IdleTimer - 1
    if self.IdleTimer <= 0 then
        self.IdleTimer = 30 + math.random(60)  -- 2-6 seconds

        -- Play idle animation
        if math.random() < 0.3 then
            local idle = math.random() < 0.5 and
                         InfantryClass.DO.IDLE1 or InfantryClass.DO.IDLE2
            self:Do_Action(idle)
        end
    end

    return FootClass.Mission_Guard(self)
end

--[[
    Capture mission - for engineers capturing buildings.
]]
function InfantryClass:Mission_Capture()
    if not Target.Is_Valid(self.NavCom) then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Move toward target building
    return self:Mission_Move()
end

--[[
    Enter mission - infantry entering buildings/transports.
]]
function InfantryClass:Mission_Enter()
    return FootClass.Mission_Enter(self)
end

--============================================================================
-- Death
--============================================================================

--[[
    Select death animation based on damage type.

    @param warhead - WarheadType that killed us
    @return DoType for death animation
]]
function InfantryClass:Select_Death_Animation(warhead)
    -- Select death animation based on damage type
    warhead = warhead or 0

    -- Simplified - would check warhead type
    local death = InfantryClass.DO.DIE1

    -- Random variation
    if math.random() < 0.3 then
        death = InfantryClass.DO.DIE2
    end

    return death
end

--[[
    Kill this infantry.

    @param source - What killed us
]]
function InfantryClass:Kill(source, warhead)
    -- Play death animation
    local death_anim = self:Select_Death_Animation(warhead)
    self:Do_Action(death_anim, true)  -- Force death animation

    -- Call parent kill logic
    -- FootClass.Kill(self, source)
end

--============================================================================
-- Voice Responses
--============================================================================

--[[
    Voice response when selected.
]]
function InfantryClass:Response_Select()
    -- Would play selection voice
end

--[[
    Voice response when given move order.
]]
function InfantryClass:Response_Move()
    -- Would play movement acknowledgment
end

--[[
    Voice response when given attack order.
]]
function InfantryClass:Response_Attack()
    -- Would play attack acknowledgment
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for infantry.
]]
function InfantryClass:AI()
    -- Call parent AI
    FootClass.AI(self)

    -- Reduce fear over time
    self:Reduce_Fear()

    -- Handle panic behavior
    if self:Is_Panicking() and not self.IsDriving then
        -- Panicking infantry run to safety
        -- Would pick random scatter destination
    end

    -- Comment cooldown
    if self.Comment > 0 then
        self.Comment = self.Comment - 1
    end
end

--============================================================================
-- Coordinate Functions
--============================================================================

--[[
    Get the coordinate for this infantry within its cell.
    Infantry use sub-cell positions.
]]
function InfantryClass:Center_Coord()
    local coord = FootClass.Center_Coord(self)

    -- Adjust for sub-cell position
    -- Full implementation would offset based on Occupy value

    return coord
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function InfantryClass:Code_Pointers()
    local data = FootClass.Code_Pointers(self)

    -- Infantry specific
    data.Fear = self.Fear
    data.Doing = self.Doing
    data.Stop = self.Stop
    data.IsProne = self.IsProne
    data.IsTechnician = self.IsTechnician
    data.IsStoked = self.IsStoked
    data.IsBoxing = self.IsBoxing
    data.Occupy = self.Occupy
    data.ToSubCell = self.ToSubCell
    data.IdleTimer = self.IdleTimer

    -- Type (store as name for lookup)
    if self.Class then
        data.TypeName = self.Class.IniName
    end

    return data
end

function InfantryClass:Decode_Pointers(data, heap_lookup)
    FootClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.Fear = data.Fear or 0
        self.Doing = data.Doing or InfantryClass.DO.NOTHING
        self.Stop = data.Stop or InfantryClass.STOP.STANDING
        self.IsProne = data.IsProne or false
        self.IsTechnician = data.IsTechnician or false
        self.IsStoked = data.IsStoked or false
        self.IsBoxing = data.IsBoxing or false
        self.Occupy = data.Occupy or InfantryClass.SUBCELL.CENTER
        self.ToSubCell = data.ToSubCell or InfantryClass.SUBCELL.CENTER
        self.IdleTimer = data.IdleTimer or 0

        -- Type lookup would happen later
        self._decode_type_name = data.TypeName
    end
end

--============================================================================
-- Debug Support
--============================================================================

function InfantryClass:Debug_Dump()
    FootClass.Debug_Dump(self)

    print(string.format("InfantryClass: Fear=%d Doing=%d Stop=%d",
        self.Fear,
        self.Doing,
        self.Stop))

    print(string.format("  Flags: Prone=%s Technician=%s Stoked=%s Boxing=%s",
        tostring(self.IsProne),
        tostring(self.IsTechnician),
        tostring(self.IsStoked),
        tostring(self.IsBoxing)))

    print(string.format("  SubCell: Occupy=%d ToSubCell=%d",
        self.Occupy,
        self.ToSubCell))
end

return InfantryClass
