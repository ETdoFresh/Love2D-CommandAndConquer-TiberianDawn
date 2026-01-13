--[[
    MissionClass - AI mission state machine for game objects

    Port of MISSION.H/CPP from the original C&C source.

    This class extends ObjectClass to add:
    - Mission (order) assignment and tracking
    - Mission queue for delayed execution
    - Suspended mission support
    - Mission-specific AI handlers
    - Timer for mission processing rate

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/MISSION.H
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local Constants = require("src.core.constants")

-- Create MissionClass extending ObjectClass
local MissionClass = Class.extend(ObjectClass, "MissionClass")

--============================================================================
-- Constants
--============================================================================

-- Mission types (imported from Constants)
MissionClass.MISSION = Constants.MISSION

-- Mission names for debugging and serialization
MissionClass.MISSION_NAMES = {
    [Constants.MISSION.NONE] = "None",
    [Constants.MISSION.SLEEP] = "Sleep",
    [Constants.MISSION.ATTACK] = "Attack",
    [Constants.MISSION.MOVE] = "Move",
    [Constants.MISSION.RETREAT] = "Retreat",
    [Constants.MISSION.GUARD] = "Guard",
    [Constants.MISSION.STICKY] = "Sticky",
    [Constants.MISSION.ENTER] = "Enter",
    [Constants.MISSION.CAPTURE] = "Capture",
    [Constants.MISSION.HARVEST] = "Harvest",
    [Constants.MISSION.GUARD_AREA] = "Guard_Area",
    [Constants.MISSION.RETURN] = "Return",
    [Constants.MISSION.STOP] = "Stop",
    [Constants.MISSION.AMBUSH] = "Ambush",
    [Constants.MISSION.HUNT] = "Hunt",
    [Constants.MISSION.TIMED_HUNT] = "Timed_Hunt",
    [Constants.MISSION.UNLOAD] = "Unload",
    [Constants.MISSION.SABOTAGE] = "Sabotage",
    [Constants.MISSION.CONSTRUCTION] = "Construction",
    [Constants.MISSION.DECONSTRUCTION] = "Deconstruction",
    [Constants.MISSION.REPAIR] = "Repair",
    [Constants.MISSION.RESCUE] = "Rescue",
    [Constants.MISSION.MISSILE] = "Missile",
}

--============================================================================
-- Constructor
--============================================================================

function MissionClass:init()
    -- Call parent constructor
    ObjectClass.init(self)

    --[[
        This is the tactical strategy to use. It is used by the unit script.
        This is a general guide for unit AI processing.
    ]]
    self.Mission = MissionClass.MISSION.NONE
    self.SuspendedMission = MissionClass.MISSION.NONE

    --[[
        The order queue is used for orders that should take effect when the
        vehicle has reached the center point of a cell. The queued order number
        is +1 when stored here so that 0 will indicate there is no queued order.
    ]]
    self.MissionQueue = MissionClass.MISSION.NONE

    --[[
        Status value for mission processing state machine
    ]]
    self.Status = 0

    --[[
        This is the thread processing timer. When this value counts down to zero,
        then more script processing may occur.
    ]]
    self.Timer = 0
end

--============================================================================
-- Mission Query
--============================================================================

--[[
    Get the current mission
]]
function MissionClass:Get_Mission()
    return self.Mission
end

--[[
    Get mission name as string (for debugging)
]]
function MissionClass:Mission_Name(mission)
    mission = mission or self.Mission
    return MissionClass.MISSION_NAMES[mission] or "Unknown"
end

--[[
    Convert mission name string to mission type
]]
function MissionClass.Mission_From_Name(name)
    for mission, mission_name in pairs(MissionClass.MISSION_NAMES) do
        if mission_name:lower() == name:lower() then
            return mission
        end
    end
    return MissionClass.MISSION.NONE
end

--============================================================================
-- Mission Assignment
--============================================================================

--[[
    Assign a new mission to this object.
    The mission will be queued if the object is in the middle of a move.

    @param mission - MissionType to assign
]]
function MissionClass:Assign_Mission(mission)
    -- Don't assign if already doing this mission
    if mission == self.Mission then
        return
    end

    -- Queue the mission for later execution
    self.MissionQueue = mission

    -- If we can start immediately, do so
    if self:Commence() then
        self.MissionQueue = MissionClass.MISSION.NONE
    end
end

--[[
    Set the mission directly without queuing.
    Used internally when mission actually starts.

    @param mission - MissionType to set
]]
function MissionClass:Set_Mission(mission)
    self.Mission = mission
    self.Status = 0
end

--[[
    Commence the queued mission if possible.
    Returns true if mission was started.
]]
function MissionClass:Commence()
    -- Check if there's a queued mission
    if self.MissionQueue == MissionClass.MISSION.NONE then
        return false
    end

    -- Check if we can start the mission now
    -- (Override in derived classes for additional checks)
    if self:Can_Commence_Mission() then
        self:Set_Mission(self.MissionQueue)
        self.MissionQueue = MissionClass.MISSION.NONE
        self.Timer = 0  -- Reset timer so AI runs immediately
        return true
    end

    return false
end

--[[
    Check if a new mission can be started.
    Override in derived classes for additional logic.
]]
function MissionClass:Can_Commence_Mission()
    return true
end

--[[
    Override the current mission temporarily.
    The current mission is suspended and can be restored.

    @param mission - New mission to run
    @param tarcom - Target for the mission
    @param navcom - Navigation target
]]
function MissionClass:Override_Mission(mission, tarcom, navcom)
    -- Save current mission if not already suspended
    if self.SuspendedMission == MissionClass.MISSION.NONE then
        self.SuspendedMission = self.Mission
    end

    -- Set new mission directly
    self:Set_Mission(mission)
end

--[[
    Restore the suspended mission.
    Returns true if a mission was restored.
]]
function MissionClass:Restore_Mission()
    if self.SuspendedMission == MissionClass.MISSION.NONE then
        return false
    end

    -- Restore the suspended mission
    self:Set_Mission(self.SuspendedMission)
    self.SuspendedMission = MissionClass.MISSION.NONE
    return true
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    Main AI processing function, called each game tick.
    Handles mission timing and dispatch.
]]
function MissionClass:AI()
    -- Call parent AI
    Class.super(self, "AI")

    -- Skip if not active or in limbo
    if not self.IsActive or self.IsInLimbo then
        return
    end

    -- Check if timer has expired
    if self.Timer > 0 then
        self.Timer = self.Timer - 1
        return
    end

    -- Try to commence queued mission
    self:Commence()

    -- Process current mission
    local delay = self:Process_Mission()

    -- Set timer for next processing
    self.Timer = delay or 0
end

--[[
    Process the current mission and return delay until next processing.
    Dispatches to Mission_X() handlers.
]]
function MissionClass:Process_Mission()
    local mission = self.Mission

    if mission == MissionClass.MISSION.SLEEP then
        return self:Mission_Sleep()
    elseif mission == MissionClass.MISSION.ATTACK then
        return self:Mission_Attack()
    elseif mission == MissionClass.MISSION.MOVE then
        return self:Mission_Move()
    elseif mission == MissionClass.MISSION.RETREAT then
        return self:Mission_Retreat()
    elseif mission == MissionClass.MISSION.GUARD then
        return self:Mission_Guard()
    elseif mission == MissionClass.MISSION.STICKY then
        return self:Mission_Guard()  -- Sticky is like guard but doesn't respond
    elseif mission == MissionClass.MISSION.ENTER then
        return self:Mission_Enter()
    elseif mission == MissionClass.MISSION.CAPTURE then
        return self:Mission_Capture()
    elseif mission == MissionClass.MISSION.HARVEST then
        return self:Mission_Harvest()
    elseif mission == MissionClass.MISSION.GUARD_AREA then
        return self:Mission_Guard_Area()
    elseif mission == MissionClass.MISSION.RETURN then
        return self:Mission_Return()
    elseif mission == MissionClass.MISSION.STOP then
        return self:Mission_Stop()
    elseif mission == MissionClass.MISSION.AMBUSH then
        return self:Mission_Ambush()
    elseif mission == MissionClass.MISSION.HUNT then
        return self:Mission_Hunt()
    elseif mission == MissionClass.MISSION.TIMED_HUNT then
        return self:Mission_Timed_Hunt()
    elseif mission == MissionClass.MISSION.UNLOAD then
        return self:Mission_Unload()
    elseif mission == MissionClass.MISSION.CONSTRUCTION then
        return self:Mission_Construction()
    elseif mission == MissionClass.MISSION.DECONSTRUCTION then
        return self:Mission_Deconstruction()
    elseif mission == MissionClass.MISSION.REPAIR then
        return self:Mission_Repair()
    elseif mission == MissionClass.MISSION.MISSILE then
        return self:Mission_Missile()
    end

    -- Unknown or NONE mission - sleep
    return self:Mission_Sleep()
end

--============================================================================
-- Mission Handlers
-- These are virtual functions - override in derived classes for actual behavior
-- Return value is the delay (in ticks) until next AI processing
--============================================================================

--[[
    Sleep mission - do nothing
]]
function MissionClass:Mission_Sleep()
    return Constants.TICKS_PER_SECOND  -- Check again in 1 second
end

--[[
    Ambush mission - wait hidden until enemy approaches
]]
function MissionClass:Mission_Ambush()
    return Constants.TICKS_PER_SECOND
end

--[[
    Attack mission - engage and destroy target
]]
function MissionClass:Mission_Attack()
    return 1  -- Process every tick during combat
end

--[[
    Capture mission - move to and capture enemy building
]]
function MissionClass:Mission_Capture()
    return 1
end

--[[
    Guard mission - stay in place, attack enemies that come close
]]
function MissionClass:Mission_Guard()
    return Constants.TICKS_PER_SECOND / 2  -- Check twice per second
end

--[[
    Guard area mission - patrol and protect an area
]]
function MissionClass:Mission_Guard_Area()
    return Constants.TICKS_PER_SECOND / 2
end

--[[
    Harvest mission - collect tiberium
]]
function MissionClass:Mission_Harvest()
    return 1
end

--[[
    Hunt mission - seek out and destroy enemies
]]
function MissionClass:Mission_Hunt()
    return Constants.TICKS_PER_SECOND / 2
end

--[[
    Timed hunt mission - hunt with time limit
]]
function MissionClass:Mission_Timed_Hunt()
    return Constants.TICKS_PER_SECOND / 2
end

--[[
    Move mission - move to destination
]]
function MissionClass:Mission_Move()
    return 1
end

--[[
    Retreat mission - flee from combat
]]
function MissionClass:Mission_Retreat()
    return 1
end

--[[
    Return mission - return to base
]]
function MissionClass:Mission_Return()
    return 1
end

--[[
    Stop mission - halt all activity
]]
function MissionClass:Mission_Stop()
    return Constants.TICKS_PER_SECOND
end

--[[
    Unload mission - unload passengers/cargo
]]
function MissionClass:Mission_Unload()
    return 1
end

--[[
    Enter mission - enter a building or transport
]]
function MissionClass:Mission_Enter()
    return 1
end

--[[
    Construction mission - build structure (for construction yard)
]]
function MissionClass:Mission_Construction()
    return 1
end

--[[
    Deconstruction mission - sell/demolish structure
]]
function MissionClass:Mission_Deconstruction()
    return 1
end

--[[
    Repair mission - repair structure (for engineer or repair vehicle)
]]
function MissionClass:Mission_Repair()
    return 1
end

--[[
    Missile mission - launch missile (for Temple of Nod)
]]
function MissionClass:Mission_Missile()
    return 1
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

--[[
    Save object state
]]
function MissionClass:Code_Pointers()
    local data = Class.super(self, "Code_Pointers") or {}

    data.Mission = self.Mission
    data.SuspendedMission = self.SuspendedMission
    data.MissionQueue = self.MissionQueue
    data.Status = self.Status
    data.Timer = self.Timer

    return data
end

--[[
    Load object state
]]
function MissionClass:Decode_Pointers(data, heap_lookup)
    Class.super(self, "Decode_Pointers", data, heap_lookup)

    self.Mission = data.Mission or MissionClass.MISSION.NONE
    self.SuspendedMission = data.SuspendedMission or MissionClass.MISSION.NONE
    self.MissionQueue = data.MissionQueue or MissionClass.MISSION.NONE
    self.Status = data.Status or 0
    self.Timer = data.Timer or 0
end

--============================================================================
-- Debug Support
--============================================================================

function MissionClass:Debug_Dump()
    Class.super(self, "Debug_Dump")
    print(string.format("MissionClass: Mission=%s Suspended=%s Queue=%s Status=%d Timer=%d",
        self:Mission_Name(self.Mission),
        self:Mission_Name(self.SuspendedMission),
        self:Mission_Name(self.MissionQueue),
        self.Status,
        self.Timer))
end

return MissionClass
