--[[
    FootClass - Mobile units base class

    Port of FOOT.H/CPP from the original C&C source.

    This class extends TechnoClass to provide mobility for:
    - Infantry
    - Vehicles (Units)
    - Aircraft

    FootClass provides:
    - Navigation/destination handling (NavCom)
    - Path storage and following
    - Team membership
    - Group assignment
    - Movement flags and state

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/FOOT.H
]]

local Class = require("src.objects.class")
local TechnoClass = require("src.objects.techno")
local Target = require("src.core.target")
local Coord = require("src.core.coord")
local FindPath = require("src.pathfinding.findpath")

-- Create FootClass extending TechnoClass
local FootClass = Class.extend(TechnoClass, "FootClass")

--============================================================================
-- Constants
--============================================================================

-- Path constants
FootClass.CONQUER_PATH_MAX = 24  -- Maximum path length
FootClass.PATH_DELAY = 15        -- Delay before retry after failure
FootClass.PATH_RETRY = 10        -- Number of retry attempts

-- Shared pathfinder instance (lazy initialized)
FootClass._pathfinder = nil

-- Facing types (for path)
FootClass.FACING = {
    NONE = -1,
    N = 0,
    NE = 1,
    E = 2,
    SE = 3,
    S = 4,
    SW = 5,
    W = 6,
    NW = 7,
}

-- Move result types
FootClass.MOVE = {
    OK = 0,             -- Can move to cell
    CLOAK = 1,          -- Can move but need to uncloak
    MOVING = 2,         -- Cell is occupied by moving unit
    DESTROYABLE = 3,    -- Cell has destroyable object blocking
    TEMP = 4,           -- Temporary blockage
    NO = 5,             -- Cannot move to cell
}

-- Group number range (player-assignable groups 1-9, plus 0 for no group)
FootClass.GROUP_NONE = 255

--============================================================================
-- Constructor
--============================================================================

function FootClass:init(house)
    -- Call parent constructor
    TechnoClass.init(self, house)

    --[[
        If this unit has officially joined the team's group, then this flag is
        true. A newly assigned unit to a team is not considered part of the
        team until it actually reaches the location where the team is. By
        using this flag, it allows a team to continue to intelligently attack
        a target without falling back to regroup the moment a distant member
        joins.
    ]]
    self.IsInitiated = false

    --[[
        When the player gives this object a navigation target AND that target
        does not result in any movement of the unit, then a beep should be
        sounded. This typically occurs when selecting an invalid location for
        movement. This flag is cleared if any movement was able to be performed.
        It never gets set for computer controlled units.
    ]]
    self.IsNewNavCom = false

    --[[
        There are certain cases where a unit should perform a full scan rather than
        the more efficient "ring scan". This situation occurs when a unit first
        appears on the map or when it finishes a multiple cell movement track.
    ]]
    self.IsPlanningToLook = false

    --[[
        Certain units have the ability to metamorphize into a building. When this
        operation begins, certain processes must occur. During these operations,
        this flag will be true. This ensures that any necessary special case code
        gets properly executed for this unit.
    ]]
    self.IsDeploying = false

    --[[
        This flag tells the system that the unit is doing a firing animation.
        This is critical to the firing logic.
    ]]
    self.IsFiring = false

    --[[
        This unit could be either rotating its body or rotating its turret. During
        the process of rotation, this flag is set. By examining this flag,
        unnecessary logic can be avoided.
    ]]
    self.IsRotating = false

    --[[
        If this object is current driving to a short range destination, this flag
        is true. A short range destination is either the next cell or the end of
        the current "curvy" track. An object that is driving is not allowed to do
        anything else until it reaches its destination. The exception is when
        infantry wish to head to a different destination, they are allowed to
        start immediately.
    ]]
    self.IsDriving = false

    --[[
        If this object is unloading from a hover transport, then this flag will be
        set to true. This handles the unusual case of an object disembarking from
        the hover lander yet not necessarily tethered but still located in an
        overlapping position. This flag will be cleared automatically when the
        object moves to the center of a cell.
    ]]
    self.IsUnloading = false

    --[[
        This is the "throttle setting" of the unit. It is a fractional value with
        0 = stop and 255 = full speed.
    ]]
    self.Speed = 255

    --[[
        This is the desired destination of the unit. The unit will attempt to head
        toward this target (avoiding intervening obstacles).
    ]]
    self.NavCom = Target.TARGET_NONE
    self.SuspendedNavCom = Target.TARGET_NONE

    --[[
        This points to the team that "owns" this object. This pointer is used to
        quickly process the team when this object is the source of the change. An
        example would be if this object were to be destroyed, it would inform the
        team of this fact by using this pointer.
    ]]
    self.Team = nil

    --[[
        If this object is part of a pseudo-team that the player is managing, then
        this will be set to the team number (0 - 9). If it is not part of any
        pseudo-team, then the number will be -1 (GROUP_NONE).
    ]]
    self.Group = FootClass.GROUP_NONE

    --[[
        This points to the next member in the team that this object is part of.
        This is used to quickly process each team member when the team class is
        the source of the change. An example would be if the team decided that
        everyone is going to move to a new location, it would inform each of the
        objects by chaining through this pointer.
    ]]
    self.Member = nil

    --[[
        Since all objects derived from this class move according to a path list.
        This is the path list. It specifies, as a simple list of facings, the
        path that the object should follow in order to reach its destination.
        This path list is limited in size, so it might require several generations
        of path lists before the ultimate destination is reached. The game logic
        handles regenerating the path list as necessary.
    ]]
    self.Path = {}
    for i = 1, FootClass.CONQUER_PATH_MAX do
        self.Path[i] = FootClass.FACING.NONE
    end

    --[[
        When there is a complete findpath failure, this timer is initialized so
        that a findpath won't be calculated until this timer expires.
    ]]
    self.PathDelay = 0
    self.TryTryAgain = FootClass.PATH_RETRY

    --[[
        If the object has recently attacked a base, then this timer will not
        have expired yet. It is used so a building does not keep calling
        for help from the same attacker.
    ]]
    self.BaseAttackTimer = 0

    --[[
        This is the coordinate that the unit is heading to as an immediate
        destination. This coordinate is never further than one cell (or track)
        from the unit's location. When this coordinate is reached, then the next
        location in the path list becomes the next HeadTo coordinate.
    ]]
    self.HeadToCoord = 0
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Get the coordinate this unit is immediately heading to.
]]
function FootClass:Head_To_Coord()
    return self.HeadToCoord
end

--[[
    Get the sort Y coordinate for rendering.
    Moving units use their center coord for sorting.
]]
function FootClass:Sort_Y()
    local coord = self:Center_Coord()
    return Coord.Coord_Y(coord)
end

--[[
    Get the likely coordinate (where unit will be).
    Used for targeting prediction.
]]
function FootClass:Likely_Coord()
    if self.HeadToCoord ~= 0 then
        return self.HeadToCoord
    end
    return self:Center_Coord()
end

--[[
    Check if unit can be demolished (sold back).
]]
function FootClass:Can_Demolish()
    -- Units can only be sold if near a repair bay
    -- Simplified: check if not moving
    return not self.IsDriving
end

--============================================================================
-- Navigation
--============================================================================

--[[
    Assign a movement destination.

    @param target - TARGET to move to
]]
function FootClass:Assign_Destination(target)
    target = target or Target.TARGET_NONE

    -- If this is a new destination from the player
    if self.IsOwnedByPlayer and target ~= self.NavCom then
        self.IsNewNavCom = true
    end

    self.NavCom = target

    -- Clear path when destination changes
    if target ~= Target.TARGET_NONE then
        self:Clear_Path()
        self.PathDelay = 0
    end
end

--[[
    Clear the current path.
]]
function FootClass:Clear_Path()
    for i = 1, FootClass.CONQUER_PATH_MAX do
        self.Path[i] = FootClass.FACING.NONE
    end
end

--[[
    Get the next facing from the path.
]]
function FootClass:Get_Next_Path_Facing()
    local facing = self.Path[1]
    if facing ~= FootClass.FACING.NONE then
        -- Shift path entries down
        for i = 1, FootClass.CONQUER_PATH_MAX - 1 do
            self.Path[i] = self.Path[i + 1]
        end
        self.Path[FootClass.CONQUER_PATH_MAX] = FootClass.FACING.NONE
    end
    return facing
end

--[[
    Calculate a basic path to the destination.
    Returns true if path was successfully calculated.
]]
function FootClass:Basic_Path()
    if not Target.Is_Valid(self.NavCom) then
        return false
    end

    -- Get destination coordinate
    local dest_coord
    local rtti = Target.Get_RTTI(self.NavCom)

    if rtti == Target.RTTI.CELL or rtti == Target.RTTI.COORD then
        -- It's a cell or coordinate target
        dest_coord = Target.As_Coordinate(self.NavCom)
    else
        -- It's an object target - would need heap lookup
        -- For now, try to get as coordinate
        dest_coord = Target.As_Coordinate(self.NavCom)
    end

    if dest_coord == 0 then
        return false
    end

    -- Get current position
    local src_coord = self:Center_Coord()
    local src_cell = Coord.Coord_Cell(src_coord)
    local dest_cell = Coord.Coord_Cell(dest_coord)

    -- If already at destination
    if src_cell == dest_cell then
        return true
    end

    -- Clear existing path
    self:Clear_Path()

    -- Use FindPath for proper LOS + edge-following pathfinding
    -- Lazy initialize pathfinder
    if not FootClass._pathfinder then
        FootClass._pathfinder = FindPath.new(nil)  -- nil map for now, uses passable_callback
    end

    local pathfinder = FootClass._pathfinder

    -- Set up passability callback based on unit type
    pathfinder.passable_callback = function(cell, facing)
        -- Default passability check
        -- In full implementation, this would call self:Can_Enter_Cell()
        return FindPath.MOVE.OK
    end

    -- Find path using LOS + edge-following algorithm
    local path = pathfinder:find_path(src_cell, dest_cell, FootClass.CONQUER_PATH_MAX)

    if not path or path.Length == 0 then
        -- Path failed, try simple straight line as fallback
        local dx = Coord.Cell_X(dest_cell) - Coord.Cell_X(src_cell)
        local dy = Coord.Cell_Y(dest_cell) - Coord.Cell_Y(src_cell)

        local facing = FootClass.FACING.NONE

        if dx > 0 and dy < 0 then
            facing = FootClass.FACING.NE
        elseif dx > 0 and dy > 0 then
            facing = FootClass.FACING.SE
        elseif dx < 0 and dy < 0 then
            facing = FootClass.FACING.NW
        elseif dx < 0 and dy > 0 then
            facing = FootClass.FACING.SW
        elseif dx > 0 then
            facing = FootClass.FACING.E
        elseif dx < 0 then
            facing = FootClass.FACING.W
        elseif dy > 0 then
            facing = FootClass.FACING.S
        elseif dy < 0 then
            facing = FootClass.FACING.N
        end

        if facing ~= FootClass.FACING.NONE then
            self.Path[1] = facing
            return true
        end
        return false
    end

    -- Copy path commands to unit's Path array
    -- Limited to CONQUER_PATH_MAX entries
    local count = math.min(path.Length, FootClass.CONQUER_PATH_MAX)
    for i = 1, count do
        local dir = path.Command[i]
        if dir == FindPath.FACING.END or dir < 0 then
            break
        end
        self.Path[i] = dir
    end

    return true
end

--============================================================================
-- Driver Control
--============================================================================

--[[
    Start driving toward a coordinate.

    @param headto - COORDINATE to drive to
    @return true if successfully started driving
]]
function FootClass:Start_Driver(headto)
    if self.IsDriving then
        return false  -- Already driving
    end

    self.HeadToCoord = headto
    self.IsDriving = true

    -- Clear the "new navcom" flag since we're moving
    self.IsNewNavCom = false

    return true
end

--[[
    Stop driving.

    @return true if successfully stopped
]]
function FootClass:Stop_Driver()
    self.IsDriving = false
    self.HeadToCoord = 0

    return true
end

--[[
    Check if this unit can enter a cell.

    @param cell - CELL to check
    @param facing - Direction entering from
    @return MoveType (OK, NO, etc.)
]]
function FootClass:Can_Enter_Cell(cell, facing)
    -- Simplified implementation
    -- Full implementation would check occupancy, terrain, etc.

    if cell < 0 then
        return FootClass.MOVE.NO
    end

    -- Check map bounds (64x64 map)
    local x = Coord.Cell_X(cell)
    local y = Coord.Cell_Y(cell)
    if x < 0 or x >= 64 or y < 0 or y >= 64 then
        return FootClass.MOVE.NO
    end

    return FootClass.MOVE.OK
end

--[[
    Set the speed of this unit.

    @param speed - Speed value (0-255)
]]
function FootClass:Set_Speed(speed)
    self.Speed = math.max(0, math.min(255, speed))
end

--============================================================================
-- Mission Implementations
-- Ported from FOOT.CPP
--============================================================================

-- TICKS_PER_SECOND constant (from DEFINES.H)
local TICKS_PER_SECOND = 15

--[[
    Mission_Move - AI process for moving a vehicle to its destination.
    Port of FootClass::Mission_Move from FOOT.CPP

    This simple AI script handles moving the vehicle to its desired destination.
    Since simple movement is handled directly by the engine, this routine merely
    waits until the unit has reached its destination, and then causes the unit
    to enter idle mode.
]]
function FootClass:Mission_Move()
    -- If no valid destination and not driving and no queued mission, go idle
    if not Target.Is_Valid(self.NavCom) and not self.IsDriving and
       self.MissionQueue == self.MISSION.NONE then
        self:Enter_Idle_Mode()
    end

    -- If no attack target and not human controlled, look for threats while moving
    if not Target.Is_Valid(self.TarCom) and self.House and not self.House.IsHuman then
        self:Target_Something_Nearby(TechnoClass.THREAT.RANGE)
    end

    return TICKS_PER_SECOND + 3
end

--[[
    Mission_Attack - AI for heading towards and firing upon target.
    Port of FootClass::Mission_Attack from FOOT.CPP

    This AI routine handles heading to within range of the target and then
    firing upon it until it is destroyed. If the target is destroyed, then
    the unit will change missions to match its "idle mode" of operation.
]]
function FootClass:Mission_Attack()
    if Target.Is_Valid(self.TarCom) then
        self:Approach_Target()
    else
        self:Enter_Idle_Mode()
    end
    return TICKS_PER_SECOND + 2
end

--[[
    Mission_Guard - Handles the AI for guarding in place.
    Port of FootClass::Mission_Guard from FOOT.CPP

    Units that are performing stationary guard duty use this AI process.
    They will sit still and target any enemies that get within range.
]]
function FootClass:Mission_Guard()
    if not self:Target_Something_Nearby(TechnoClass.THREAT.RANGE) then
        self:Random_Animate()
    end
    return TICKS_PER_SECOND + math.random(0, 4)
end

--[[
    Mission_Guard_Area - Causes unit to guard an area about twice weapon range.
    Port of FootClass::Mission_Guard_Area from FOOT.CPP

    Similar to guard but uses area range instead of weapon range.
]]
function FootClass:Mission_Guard_Area()
    if not self:Target_Something_Nearby(TechnoClass.THREAT.AREA) then
        self:Random_Animate()
    end
    return TICKS_PER_SECOND + math.random(0, 4)
end

--[[
    Mission_Hunt - Handles the default hunt order.
    Port of FootClass::Mission_Hunt from FOOT.CPP

    This routine is the default hunt order for game objects. It handles
    searching for a nearby object and heading toward it. The act of
    targeting will cause it to attack the target it selects.
]]
function FootClass:Mission_Hunt()
    if not self:Target_Something_Nearby(TechnoClass.THREAT.NORMAL) then
        self:Random_Animate()
    else
        -- Special case: Engineers capture instead of attack
        local rtti = self:What_Am_I()
        if rtti == Target.RTTI.INFANTRY then
            -- Check if this is an engineer (Type E7)
            local type_class = self.Class
            if type_class and type_class.Type == 6 then  -- INFANTRY_E7 = Engineer
                self:Assign_Destination(self.TarCom)
                self:Assign_Mission(self.MISSION.CAPTURE)
            else
                self:Approach_Target()
            end
        else
            self:Approach_Target()
        end
    end
    return TICKS_PER_SECOND + 5
end

--[[
    Mission_Timed_Hunt - AI process for multiplayer computer units.
    Port of FootClass::Mission_Timed_Hunt from FOOT.CPP

    For multiplayer games, the computer AI can't just blitz the human players;
    the humans need a little time to set up their base. This state just waits
    for a certain period of time, then goes into hunt mode.
]]
function FootClass:Mission_Timed_Hunt()
    local changed = false

    if self.House and not self.House.IsHuman then
        -- Jump into HUNT mode if time has elapsed or house has lost units
        if self.House.BlitzTime and self.House.BlitzTime <= 0 then
            self:Assign_Mission(self.MISSION.HUNT)
            changed = true
        end

        -- Random chance to snap out and start hunting
        if math.random(0, 5000) == 1 then
            self:Assign_Mission(self.MISSION.HUNT)
            changed = true
        end

        -- If still in timed hunt, act like guard area
        if not changed then
            self:Mission_Guard_Area()
        end
    end

    return TICKS_PER_SECOND + math.random(0, 4)
end

--[[
    Mission_Capture - Handles the capture mission.
    Port of FootClass::Mission_Capture from FOOT.CPP

    Capture missions are nearly the same as normal movement missions.
    The only difference is that the final destination is handled in a
    special way so that it is not marked as impassable.
]]
function FootClass:Mission_Capture()
    if not Target.Is_Valid(self.NavCom) and not self:In_Radio_Contact() then
        self:Enter_Idle_Mode()
        -- Would scatter if standing on a building
    end
    return TICKS_PER_SECOND - 2
end

--[[
    Mission_Enter - Enter (cooperatively) mission handler.
    Port of FootClass::Mission_Enter from FOOT.CPP

    Move to target and enter it (transport or building).
]]
function FootClass:Mission_Enter()
    if not Target.Is_Valid(self.NavCom) then
        self:Enter_Idle_Mode()
        return TICKS_PER_SECOND
    end

    return self:Mission_Move()
end

--[[
    Random_Animate - Perform random idle animation.
    Called when unit has nothing better to do.
]]
function FootClass:Random_Animate()
    -- Override in derived classes for specific animations
    -- Infantry: fidget, look around
    -- Vehicles: small turret movements
end

--[[
    Approach the current target.
    Port of FootClass::Approach_Target from FOOT.CPP

    Determines if the target is within weapon range.
    If in range, fires. If not, moves closer.
]]
function FootClass:Approach_Target()
    -- Early out if no valid target
    if not Target.Is_Valid(self.TarCom) then
        return
    end

    -- Check if already in range of target
    local in_range_primary = self:In_Range(self.TarCom, 0)
    local in_range_secondary = self:In_Range(self.TarCom, 1)

    if in_range_primary or in_range_secondary then
        -- In range - attempt to fire
        local weapon = in_range_primary and 0 or 1
        local fire_error = self:Can_Fire(self.TarCom, weapon)

        if fire_error == TechnoClass.FIRE_ERROR.OK then
            self:Fire_At(self.TarCom, weapon)
        end
        return
    end

    -- Not in range - need to move closer
    -- Don't reassign destination if we already have one
    if Target.Is_Valid(self.NavCom) then
        return
    end

    -- Calculate max weapon range
    local maxrange = math.max(self:Weapon_Range(0), self:Weapon_Range(1))

    -- Adjust range for safety margin
    maxrange = maxrange - 0x00B7  -- ~183 leptons (~0.7 cells)
    maxrange = math.max(maxrange, 0)

    -- Get target coordinate
    local target_coord = Target.As_Coord(self.TarCom)
    if not target_coord or target_coord == 0 then
        -- Fall back to assigning target directly as destination
        self:Assign_Destination(self.TarCom)
        return
    end

    -- Calculate direction from target to us
    local my_coord = self:Center_Coord()
    local dir = Coord.Direction256(target_coord, my_coord)

    -- Try to find an intermediate cell within weapon range
    local found = false
    local try_coord = nil

    -- Sweep through positions at different angles
    local angles = {0, 8, -8, 16, -16, 24, -24, 32, -32, 48, -48, 64, -64}

    for range = maxrange, 0x0080, -0x0100 do
        for _, angle in ipairs(angles) do
            local test_dir = (dir + angle) % 256
            local test_coord = Coord.Coord_Move_Dir(target_coord, test_dir, range)

            -- Check if this position is within range of target
            local dist_to_target = Coord.Distance(test_coord, target_coord)
            if dist_to_target < range then
                -- Check if we can enter this cell
                local test_cell = Coord.Coord_Cell(test_coord)
                local move_type = self:Can_Enter_Cell(test_cell, 0)

                if move_type == FootClass.MOVE.OK or move_type == FootClass.MOVE.MOVING_BLOCK then
                    try_coord = test_coord
                    found = true
                    break
                end
            end
        end
        if found then break end
    end

    -- Assign destination
    if found and try_coord then
        -- Move to the calculated position
        local cell = Coord.Coord_Cell(try_coord)
        self:Assign_Destination(Target.As_Cell(cell))
    else
        -- Couldn't find intermediate - head directly toward target
        self:Assign_Destination(self.TarCom)
    end
end

--============================================================================
-- Override Mission
--============================================================================

--[[
    Override the current mission.

    @param mission - New mission
    @param tarcom - New attack target
    @param navcom - New navigation target
]]
function FootClass:Override_Mission(mission, tarcom, navcom)
    -- Suspend current navcom
    self.SuspendedNavCom = self.NavCom

    -- Set new navcom
    if navcom then
        self.NavCom = navcom
    end

    -- Call parent override
    TechnoClass.Override_Mission(self, mission, tarcom, navcom)
end

--[[
    Restore the previous mission.
]]
function FootClass:Restore_Mission()
    -- Restore suspended navcom
    self.NavCom = self.SuspendedNavCom
    self.SuspendedNavCom = Target.TARGET_NONE

    -- Call parent restore
    return TechnoClass.Restore_Mission(self)
end

--[[
    Assign a new mission.
]]
function FootClass:Assign_Mission(order)
    TechnoClass.Assign_Mission(self, order)

    -- Clear path when mission changes
    self:Clear_Path()
end

--============================================================================
-- Combat
--============================================================================

--[[
    Called when unit is stunned.
]]
function FootClass:Stun()
    TechnoClass.Stun(self)

    -- Stop movement
    self:Stop_Driver()
    self.NavCom = Target.TARGET_NONE
end

--[[
    Take damage.
]]
function FootClass:Take_Damage(damage, distance, warhead, source)
    local result = TechnoClass.Take_Damage(self, damage, distance, warhead, source)

    -- Scatter if taking significant damage
    if damage > 0 and source then
        self:Scatter(source:Center_Coord(), false, false)
    end

    return result
end

--[[
    Death announcement.
    Override in derived classes.
]]
function FootClass:Death_Announcement(source)
    -- Override in derived classes
end

--[[
    Scatter from a threat.

    @param source - COORDINATE to scatter from
    @param forced - Force scatter even if not appropriate
    @param nokidding - Really force it
]]
function FootClass:Scatter(source, forced, nokidding)
    if not forced and self.IsDriving then
        return  -- Don't interrupt movement
    end

    -- Pick a random direction away from source
    -- Simplified implementation
end

--============================================================================
-- Team Support
--============================================================================

--[[
    Detach from team and other references.
]]
function FootClass:Detach(target, all)
    if self.Team and self.Team == target then
        self.Team = nil
    end

    -- Clear NavCom if it matches
    if self.NavCom == target then
        self.NavCom = Target.TARGET_NONE
    end

    if self.SuspendedNavCom == target then
        self.SuspendedNavCom = Target.TARGET_NONE
    end

    TechnoClass.Detach(self, target, all)
end

--[[
    Detach from all references.
]]
function FootClass:Detach_All(all)
    if self.Team then
        -- Would notify team here
        self.Team = nil
    end
    self.Member = nil

    TechnoClass.Detach(self, nil, all)
end

--============================================================================
-- Sell Support
--============================================================================

--[[
    Sell back this unit.

    @param control - 0=cancel, 1=immediate sell
]]
function FootClass:Sell_Back(control)
    if control > 0 and self.House then
        -- Give credits
        local refund = self:Refund_Amount()
        -- self.House:Credits = self.House:Credits + refund

        -- Remove from map
        self:Limbo()
    end
end

--[[
    Offload a bail of tiberium (for harvesters).
]]
function FootClass:Offload_Tiberium_Bail()
    -- Override in UnitClass
    return 0
end

--============================================================================
-- Map Operations
--============================================================================

--[[
    Limbo (remove from map).
]]
function FootClass:Limbo()
    -- Stop any movement
    self:Stop_Driver()

    -- Leave team
    if self.Team then
        -- Would notify team here
        self.Team = nil
    end

    return TechnoClass.Limbo(self)
end

--[[
    Unlimbo (place on map).
]]
function FootClass:Unlimbo(coord, dir)
    self.IsPlanningToLook = true
    return TechnoClass.Unlimbo(self, coord, dir)
end

--[[
    Mark for redraw.
]]
function FootClass:Mark(mark)
    return TechnoClass.Mark(self, mark)
end

--============================================================================
-- Per-Cell Processing
--============================================================================

--[[
    Called when unit enters the center of a cell.

    @param center - true if at cell center
]]
function FootClass:Per_Cell_Process(center)
    if center then
        -- Clear unloading flag when at cell center
        self.IsUnloading = false

        -- Planning to look?
        if self.IsPlanningToLook then
            self.IsPlanningToLook = false
            -- Would do visibility scan here
        end
    end
end

--============================================================================
-- User Interaction
--============================================================================

--[[
    Handle click with action on an object.

    @param action - ActionType
    @param object - Target ObjectClass
]]
function FootClass:Active_Click_With(action, object)
    -- Default: assign as target or destination based on action
    if action then
        if object then
            local target = object:As_Target()
            self:Assign_Target(target)
            self:Assign_Destination(target)
        end
    end
end

--============================================================================
-- Radio Communication
--============================================================================

--[[
    Receive a radio message.
]]
function FootClass:Receive_Message(from, message, param)
    local RADIO = self.RADIO

    -- Handle special messages
    if message == RADIO.HOLD_STILL then
        -- Transport is telling us to wait
        self.IsTethered = true
        return RADIO.ROGER
    end

    if message == RADIO.OVER_OUT then
        -- Contact broken
        self.IsTethered = false
    end

    return TechnoClass.Receive_Message(self, from, message, param)
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function FootClass:Code_Pointers()
    local data = TechnoClass.Code_Pointers(self)

    -- Flags
    data.IsInitiated = self.IsInitiated
    data.IsNewNavCom = self.IsNewNavCom
    data.IsPlanningToLook = self.IsPlanningToLook
    data.IsDeploying = self.IsDeploying
    data.IsFiring = self.IsFiring
    data.IsRotating = self.IsRotating
    data.IsDriving = self.IsDriving
    data.IsUnloading = self.IsUnloading

    -- Movement state
    data.Speed = self.Speed
    data.NavCom = self.NavCom
    data.SuspendedNavCom = self.SuspendedNavCom
    data.Group = self.Group
    data.HeadToCoord = self.HeadToCoord

    -- Path
    data.Path = {}
    for i = 1, FootClass.CONQUER_PATH_MAX do
        data.Path[i] = self.Path[i]
    end

    data.PathDelay = self.PathDelay
    data.TryTryAgain = self.TryTryAgain
    data.BaseAttackTimer = self.BaseAttackTimer

    -- Team encoded as TARGET
    if self.Team then
        data.Team = self.Team:As_Target()
    end

    return data
end

function FootClass:Decode_Pointers(data, heap_lookup)
    TechnoClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        -- Flags
        self.IsInitiated = data.IsInitiated or false
        self.IsNewNavCom = data.IsNewNavCom or false
        self.IsPlanningToLook = data.IsPlanningToLook or false
        self.IsDeploying = data.IsDeploying or false
        self.IsFiring = data.IsFiring or false
        self.IsRotating = data.IsRotating or false
        self.IsDriving = data.IsDriving or false
        self.IsUnloading = data.IsUnloading or false

        -- Movement state
        self.Speed = data.Speed or 255
        self.NavCom = data.NavCom or Target.TARGET_NONE
        self.SuspendedNavCom = data.SuspendedNavCom or Target.TARGET_NONE
        self.Group = data.Group or FootClass.GROUP_NONE
        self.HeadToCoord = data.HeadToCoord or 0

        -- Path
        if data.Path then
            for i = 1, FootClass.CONQUER_PATH_MAX do
                self.Path[i] = data.Path[i] or FootClass.FACING.NONE
            end
        end

        self.PathDelay = data.PathDelay or 0
        self.TryTryAgain = data.TryTryAgain or FootClass.PATH_RETRY
        self.BaseAttackTimer = data.BaseAttackTimer or 0

        -- Team (resolve later)
        self._decode_team = data.Team
    end
end

--============================================================================
-- Debug Support
--============================================================================

function FootClass:Debug_Dump()
    TechnoClass.Debug_Dump(self)

    print(string.format("FootClass: NavCom=%s Speed=%d Group=%d",
        Target.Target_As_String(self.NavCom),
        self.Speed,
        self.Group))

    print(string.format("  Flags: Initiated=%s Driving=%s Rotating=%s Firing=%s",
        tostring(self.IsInitiated),
        tostring(self.IsDriving),
        tostring(self.IsRotating),
        tostring(self.IsFiring)))

    -- Print path
    local path_str = "Path: "
    for i = 1, FootClass.CONQUER_PATH_MAX do
        if self.Path[i] == FootClass.FACING.NONE then
            break
        end
        path_str = path_str .. self.Path[i] .. " "
    end
    print("  " .. path_str)
end

return FootClass
