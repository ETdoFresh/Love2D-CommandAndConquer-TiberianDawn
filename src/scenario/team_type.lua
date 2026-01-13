--[[
    TeamTypeClass - Static data for team definitions

    Port of TeamTypeClass from TEAMTYPE.H/TEAMTYPE.CPP

    Team types define the composition and behavior of AI teams.
    They specify what units to include, what missions to perform,
    and various behavior flags.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/TEAMTYPE.H
]]

local AbstractTypeClass = require("src.objects.types.abstracttype")
local Class = require("src.objects.class")
local Target = require("src.core.target")

-- Create TeamTypeClass extending AbstractTypeClass
local TeamTypeClass = Class.extend(AbstractTypeClass, "TeamTypeClass")

--============================================================================
-- Constants
--============================================================================

-- Maximum number of different unit classes in a team
TeamTypeClass.MAX_TEAM_CLASSCOUNT = 5

-- Maximum number of missions in a team's mission list
TeamTypeClass.MAX_TEAM_MISSIONS = 20

--============================================================================
-- Team Mission Types (from TEAMTYPE.H)
--============================================================================

TeamTypeClass.TMISSION = {
    NONE = -1,
    ATTACKBASE = 0,         -- Attack nearest enemy base
    ATTACKUNITS = 1,        -- Attack all enemy units
    ATTACKCIVILIANS = 2,    -- Attack all civilians
    RAMPAGE = 3,            -- Attack & destroy anything not mine
    DEFENDBASE = 4,         -- Protect my base
    MOVE = 5,               -- Move to waypoint specified
    MOVECELL = 6,           -- Move to cell # specified
    RETREAT = 7,            -- Order given by superior team
    GUARD = 8,              -- Works like infantry guard mission
    LOOP = 9,               -- Loop back to start of mission list
    ATTACKTARCOM = 10,      -- Attack tarcom
    UNLOAD = 11,            -- Unload at current location
    COUNT = 12,
}

-- Mission name strings for INI parsing
TeamTypeClass.MISSION_NAMES = {
    [TeamTypeClass.TMISSION.ATTACKBASE] = "Attack Base",
    [TeamTypeClass.TMISSION.ATTACKUNITS] = "Attack Units",
    [TeamTypeClass.TMISSION.ATTACKCIVILIANS] = "Attack Civilians",
    [TeamTypeClass.TMISSION.RAMPAGE] = "Rampage",
    [TeamTypeClass.TMISSION.DEFENDBASE] = "Defend Base",
    [TeamTypeClass.TMISSION.MOVE] = "Move",
    [TeamTypeClass.TMISSION.MOVECELL] = "Move to Cell",
    [TeamTypeClass.TMISSION.RETREAT] = "Retreat",
    [TeamTypeClass.TMISSION.GUARD] = "Guard",
    [TeamTypeClass.TMISSION.LOOP] = "Loop",
    [TeamTypeClass.TMISSION.ATTACKTARCOM] = "Attack Tarcom",
    [TeamTypeClass.TMISSION.UNLOAD] = "Unload",
}

--============================================================================
-- Constructor
--============================================================================

function TeamTypeClass:init(ini_name)
    -- Call parent constructor
    AbstractTypeClass.init(self, ini_name, ini_name)

    -- RTTI type
    self.RTTI = Target.RTTI.TEAMTYPE

    --========================================================================
    -- Flags (bit flags in original, boolean in Lua)
    --========================================================================

    --[[
        If this teamtype object is active, then this flag will be true.
        TeamType objects that are not active are either not yet created or have
        been deleted after fulfilling their action.
    ]]
    self.IsActive = true

    --[[
        If RoundAbout, the team avoids high-threat areas.
    ]]
    self.IsRoundAbout = false

    --[[
        If Learning, the team learns from mistakes.
    ]]
    self.IsLearning = false

    --[[
        If Suicide, the team won't stop until it achieves its mission or dies.
    ]]
    self.IsSuicide = false

    --[[
        Is this team type allowed to be created automatically by the computer
        when the appropriate trigger indicates?
    ]]
    self.IsAutocreate = false

    --[[
        Mercenaries will change sides if they start to lose.
    ]]
    self.IsMercenary = false

    --[[
        This flag tells the computer that it should build members to fill
        a team of this type regardless of whether there actually is a team
        of this type active.
    ]]
    self.IsPrebuilt = false

    --[[
        If this team should allow recruitment of new members, then this flag
        will be true. A false value results in a team that fights until it
        is dead. This is similar to IsSuicide, but they will defend themselves.
    ]]
    self.IsReinforcable = false

    --[[
        A transient team type was created exclusively to bring on reinforcements
        as a result of some special event. As soon as there are no teams
        existing of this type, then this team type should be deleted.
    ]]
    self.IsTransient = false

    --========================================================================
    -- Numeric Properties
    --========================================================================

    --[[
        Priority given the team for recruiting purposes; higher priority means
        it can steal members from other teams (scale: 0 - 15).
    ]]
    self.RecruitPriority = 7

    --[[
        Initial # of this type of team.
    ]]
    self.InitNum = 0

    --[[
        Max # of this type of team allowed at one time.
    ]]
    self.MaxAllowed = 0

    --[[
        Fear level of this team (0-255).
    ]]
    self.Fear = 0

    --[[
        House the team belongs to (HousesType).
    ]]
    self.House = 0  -- HOUSE_NONE

    --========================================================================
    -- Mission List
    --========================================================================

    --[[
        Number of missions in the mission list.
    ]]
    self.MissionCount = 0

    --[[
        The mission list for this team.
        Each entry is {Mission = TeamMissionType, Argument = int}.
    ]]
    self.MissionList = {}

    --========================================================================
    -- Team Composition
    --========================================================================

    --[[
        Number of different classes in the team.
    ]]
    self.ClassCount = 0

    --[[
        Array of TechnoTypeClass objects comprising the team.
    ]]
    self.Class = {}

    --[[
        Desired # of each type of object comprising the team.
    ]]
    self.DesiredNum = {}

    --========================================================================
    -- Runtime Tracking
    --========================================================================

    --[[
        Number of teams of this type currently active.
    ]]
    self.ActiveCount = 0
end

--============================================================================
-- Static Data
--============================================================================

-- Registry of all team types by name
local team_type_registry = {}

--============================================================================
-- Factory Methods
--============================================================================

--[[
    Create a new team type with the given name.

    @param ini_name - INI name for the team type
    @return TeamTypeClass instance
]]
function TeamTypeClass.Create(ini_name)
    if team_type_registry[ini_name] then
        return team_type_registry[ini_name]
    end

    local instance = TeamTypeClass:new(ini_name)
    team_type_registry[ini_name] = instance
    return instance
end

--[[
    Get an existing team type by name.

    @param name - Name of the team type
    @return TeamTypeClass instance or nil
]]
function TeamTypeClass.As_Pointer(name)
    return team_type_registry[name]
end

--[[
    Get all registered team types.

    @return Table of all team types
]]
function TeamTypeClass.Get_All()
    local result = {}
    for name, team_type in pairs(team_type_registry) do
        table.insert(result, team_type)
    end
    return result
end

--[[
    Clear all team types (for new scenario).
]]
function TeamTypeClass.Init()
    team_type_registry = {}
end

--============================================================================
-- Instance Methods
--============================================================================

--[[
    Fill in team type data from scenario data table.

    @param data - Table with team type properties
]]
function TeamTypeClass:Fill_In(data)
    -- Flags
    self.IsRoundAbout = data.roundabout or data.IsRoundAbout or false
    self.IsLearning = data.learning or data.IsLearning or false
    self.IsSuicide = data.suicide or data.IsSuicide or false
    self.IsAutocreate = data.autocreate or data.IsAutocreate or false
    self.IsMercenary = data.mercenary or data.IsMercenary or false
    self.IsPrebuilt = data.prebuild or data.IsPrebuilt or false
    self.IsReinforcable = data.reinforce or data.IsReinforcable or false
    self.IsTransient = data.transient or data.IsTransient or false

    -- Numeric properties
    self.RecruitPriority = data.priority or data.RecruitPriority or 7
    self.InitNum = data.init_num or data.InitNum or 0
    self.MaxAllowed = data.max_allowed or data.MaxAllowed or 0
    self.Fear = data.fear or data.Fear or 0
    self.House = data.house or data.House or 0

    -- Mission list
    if data.missions then
        self.MissionCount = #data.missions
        self.MissionList = {}
        for i, m in ipairs(data.missions) do
            self.MissionList[i] = {
                Mission = m.mission or m.Mission or TeamTypeClass.TMISSION.NONE,
                Argument = m.argument or m.Argument or 0
            }
        end
    end

    -- Team composition
    if data.members or data.units then
        local members = data.members or data.units or {}
        self.ClassCount = #members
        self.Class = {}
        self.DesiredNum = {}
        for i, member in ipairs(members) do
            self.Class[i] = member.type or member.Class
            self.DesiredNum[i] = member.count or member.num or member.DesiredNum or 1
        end
    end

    -- Waypoints (if provided)
    if data.waypoints then
        self.Waypoints = data.waypoints
    end
end

--[[
    Create a team instance from this type.
    This returns the data needed to create a TeamClass instance.

    @return Table with team initialization data
]]
function TeamTypeClass:Create_One_Of()
    if self.MaxAllowed > 0 and self.ActiveCount >= self.MaxAllowed then
        return nil  -- Too many teams of this type
    end

    self.ActiveCount = self.ActiveCount + 1

    return {
        type_class = self,
        house = self.House,
        mission_list = self.MissionList,
        mission_count = self.MissionCount,
        is_roundabout = self.IsRoundAbout,
        is_suicide = self.IsSuicide,
        is_learning = self.IsLearning,
        is_mercenary = self.IsMercenary,
        is_reinforcable = self.IsReinforcable,
        fear = self.Fear,
        class = self.Class,
        desired_num = self.DesiredNum,
        class_count = self.ClassCount,
    }
end

--[[
    Called when a team of this type is destroyed.
]]
function TeamTypeClass:Team_Destroyed()
    self.ActiveCount = math.max(0, self.ActiveCount - 1)

    -- If transient and no more teams, remove this type
    if self.IsTransient and self.ActiveCount == 0 then
        self:Remove()
    end
end

--[[
    Remove this team type from the registry.
]]
function TeamTypeClass:Remove()
    self.IsActive = false
    team_type_registry[self.IniName] = nil
end

--[[
    Get total number of units needed for this team.

    @return Total unit count
]]
function TeamTypeClass:Get_Total_Units()
    local total = 0
    for i = 1, self.ClassCount do
        total = total + (self.DesiredNum[i] or 0)
    end
    return total
end

--[[
    Check if a unit type is part of this team.

    @param unit_type - Unit type to check (type name or class)
    @return true if unit type is part of team
]]
function TeamTypeClass:Contains_Unit_Type(unit_type)
    for i = 1, self.ClassCount do
        if self.Class[i] == unit_type then
            return true
        end
    end
    return false
end

--[[
    Get mission name from mission type.

    @param mission - TeamMissionType
    @return Mission name string
]]
function TeamTypeClass.Name_From_Mission(mission)
    return TeamTypeClass.MISSION_NAMES[mission] or "Unknown"
end

--[[
    Get mission type from name.

    @param name - Mission name string
    @return TeamMissionType
]]
function TeamTypeClass.Mission_From_Name(name)
    for mission, mission_name in pairs(TeamTypeClass.MISSION_NAMES) do
        if mission_name:lower() == name:lower() then
            return mission
        end
    end
    return TeamTypeClass.TMISSION.NONE
end

--[[
    Get team type as a targeting value.

    @return TARGET value
]]
function TeamTypeClass:As_Target()
    return Target.Build(Target.RTTI.TEAMTYPE, self.IniName)
end

--[[
    Validate team type data for debugging.

    @return true if valid
]]
function TeamTypeClass:Validate()
    if not self.IniName or self.IniName == "" then
        return false
    end
    if self.ClassCount > TeamTypeClass.MAX_TEAM_CLASSCOUNT then
        return false
    end
    if self.MissionCount > TeamTypeClass.MAX_TEAM_MISSIONS then
        return false
    end
    return true
end

--[[
    Debug dump of team type.
]]
function TeamTypeClass:Debug_Dump()
    print(string.format("TeamTypeClass: %s", self.IniName))
    print(string.format("  House=%d Active=%s Autocreate=%s Suicide=%s",
        self.House,
        tostring(self.IsActive),
        tostring(self.IsAutocreate),
        tostring(self.IsSuicide)))
    print(string.format("  Priority=%d InitNum=%d MaxAllowed=%d Fear=%d",
        self.RecruitPriority,
        self.InitNum,
        self.MaxAllowed,
        self.Fear))
    print(string.format("  ClassCount=%d MissionCount=%d ActiveCount=%d",
        self.ClassCount,
        self.MissionCount,
        self.ActiveCount))

    -- Print composition
    for i = 1, self.ClassCount do
        print(string.format("    Class[%d]: %s x%d",
            i, tostring(self.Class[i]), self.DesiredNum[i] or 0))
    end

    -- Print missions
    for i = 1, self.MissionCount do
        local m = self.MissionList[i]
        print(string.format("    Mission[%d]: %s (%d)",
            i, TeamTypeClass.Name_From_Mission(m.Mission), m.Argument or 0))
    end
end

--============================================================================
-- Serialization
--============================================================================

--[[
    Encode pointers for save.
]]
function TeamTypeClass:Code_Pointers()
    -- Convert Class type references to type names
    local encoded_class = {}
    for i = 1, self.ClassCount do
        local class = self.Class[i]
        if type(class) == "table" and class.IniName then
            encoded_class[i] = class.IniName
        else
            encoded_class[i] = class
        end
    end
    self._encoded_class = encoded_class
end

--[[
    Decode pointers after load.
]]
function TeamTypeClass:Decode_Pointers()
    -- Restore Class type references from names
    if self._encoded_class then
        for i = 1, self.ClassCount do
            local class_name = self._encoded_class[i]
            -- Would need to resolve type name to actual type class
            self.Class[i] = class_name
        end
        self._encoded_class = nil
    end
end

--[[
    Save team type data.

    @return Table of saveable data
]]
function TeamTypeClass:Save()
    self:Code_Pointers()

    return {
        ini_name = self.IniName,
        name = self.Name,
        is_active = self.IsActive,
        is_roundabout = self.IsRoundAbout,
        is_learning = self.IsLearning,
        is_suicide = self.IsSuicide,
        is_autocreate = self.IsAutocreate,
        is_mercenary = self.IsMercenary,
        is_prebuilt = self.IsPrebuilt,
        is_reinforcable = self.IsReinforcable,
        is_transient = self.IsTransient,
        recruit_priority = self.RecruitPriority,
        init_num = self.InitNum,
        max_allowed = self.MaxAllowed,
        fear = self.Fear,
        house = self.House,
        mission_count = self.MissionCount,
        mission_list = self.MissionList,
        class_count = self.ClassCount,
        class = self._encoded_class or self.Class,
        desired_num = self.DesiredNum,
        active_count = self.ActiveCount,
    }
end

--[[
    Load team type from saved data.

    @param data - Saved data table
    @return TeamTypeClass instance
]]
function TeamTypeClass.Load(data)
    local instance = TeamTypeClass.Create(data.ini_name)

    instance.Name = data.name or data.ini_name
    instance.IsActive = data.is_active
    instance.IsRoundAbout = data.is_roundabout
    instance.IsLearning = data.is_learning
    instance.IsSuicide = data.is_suicide
    instance.IsAutocreate = data.is_autocreate
    instance.IsMercenary = data.is_mercenary
    instance.IsPrebuilt = data.is_prebuilt
    instance.IsReinforcable = data.is_reinforcable
    instance.IsTransient = data.is_transient
    instance.RecruitPriority = data.recruit_priority
    instance.InitNum = data.init_num
    instance.MaxAllowed = data.max_allowed
    instance.Fear = data.fear
    instance.House = data.house
    instance.MissionCount = data.mission_count
    instance.MissionList = data.mission_list
    instance.ClassCount = data.class_count
    instance.Class = data.class
    instance.DesiredNum = data.desired_num
    instance.ActiveCount = data.active_count or 0

    instance:Decode_Pointers()

    return instance
end

return TeamTypeClass
