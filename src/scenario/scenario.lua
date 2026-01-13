--[[
    ScenarioClass - Scenario metadata and game state management

    Manages scenario-wide state including:
    - Scenario identification (name, number, variant)
    - Campaign progression
    - Victory/defeat conditions
    - Special global flags
    - Scenario timer
    - Briefing and mission text

    In the original C++, scenario data was stored in global variables.
    This class encapsulates that state in a more organized way.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H
               temp/CnC_Remastered_Collection/TIBERIANDAWN/GLOBALS.CPP
]]

local Events = require("src.core.events")

local ScenarioClass = {}
ScenarioClass.__index = ScenarioClass

--============================================================================
-- Scenario Player Types (from DEFINES.H)
--============================================================================

ScenarioClass.PLAYER = {
    NONE = -1,
    GDI = 0,
    NOD = 1,
    JP = 2,       -- Jurassic Park / Funpark
    PLAYER2 = 3,  -- 2-player network/modem
    MPLAYER = 4,  -- Multiplayer (>2 players)
    COUNT = 5,
}

--============================================================================
-- Scenario Direction Types (from DEFINES.H)
--============================================================================

ScenarioClass.DIR = {
    NONE = -1,
    EAST = 0,
    WEST = 1,
    COUNT = 2,
}

--============================================================================
-- Scenario Variant Types (from DEFINES.H)
--============================================================================

ScenarioClass.VAR = {
    NONE = -1,
    A = 0,
    B = 1,
    C = 2,
    D = 3,
    COUNT = 4,
    LOSE = 5,  -- Lose variant
}

--============================================================================
-- Theater Types
--============================================================================

ScenarioClass.THEATER = {
    NONE = -1,
    DESERT = 0,
    TEMPERATE = 1,
    WINTER = 2,
    COUNT = 3,
}

ScenarioClass.THEATER_NAMES = {
    [ScenarioClass.THEATER.DESERT] = "DESERT",
    [ScenarioClass.THEATER.TEMPERATE] = "TEMPERATE",
    [ScenarioClass.THEATER.WINTER] = "WINTER",
}

--============================================================================
-- Victory/Defeat Conditions
--============================================================================

ScenarioClass.WIN_CONDITION = {
    NONE = 0,
    DESTROY_ALL = 1,      -- Destroy all enemy units/buildings
    CAPTURE_FLAG = 2,     -- Capture the flag (multiplayer)
    DESTROY_BUILDINGS = 3, -- Destroy all enemy buildings
    TIME_LIMIT = 4,       -- Time limit victory
    TRIGGER = 5,          -- Victory triggered by trigger
}

ScenarioClass.LOSE_CONDITION = {
    NONE = 0,
    ALL_DESTROYED = 1,    -- All player units/buildings destroyed
    TIME_LIMIT = 2,       -- Time limit exceeded
    BUILDING_DESTROYED = 3, -- Key building destroyed
    TRIGGER = 4,          -- Defeat triggered by trigger
}

--============================================================================
-- Constructor
--============================================================================

function ScenarioClass.new()
    local self = setmetatable({}, ScenarioClass)

    --========================================================================
    -- Scenario Identification
    --========================================================================

    --[[
        Scenario number (1-15 for campaign missions).
    ]]
    self.Number = 0

    --[[
        Scenario player type (GDI, NOD, multiplayer, etc.).
    ]]
    self.Player = ScenarioClass.PLAYER.NONE

    --[[
        Scenario direction (East or West approach).
    ]]
    self.Direction = ScenarioClass.DIR.NONE

    --[[
        Scenario variant (A, B, C, D for randomization).
    ]]
    self.Variant = ScenarioClass.VAR.NONE

    --[[
        Scenario filename without extension.
    ]]
    self.Name = ""

    --[[
        Full scenario name for display.
    ]]
    self.Description = ""

    --[[
        Scenario CRC for multiplayer verification.
    ]]
    self.CRC = 0

    --========================================================================
    -- Theater and Map
    --========================================================================

    --[[
        Theater type (Desert, Temperate, Winter).
    ]]
    self.Theater = ScenarioClass.THEATER.TEMPERATE

    --[[
        Map dimensions in cells.
    ]]
    self.MapWidth = 64
    self.MapHeight = 64

    --[[
        Visible map bounds (for camera limits).
    ]]
    self.MapX = 0
    self.MapY = 0
    self.MapCellWidth = 64
    self.MapCellHeight = 64

    --========================================================================
    -- Victory/Defeat
    --========================================================================

    --[[
        Victory conditions.
    ]]
    self.WinCondition = ScenarioClass.WIN_CONDITION.DESTROY_ALL

    --[[
        Defeat conditions.
    ]]
    self.LoseCondition = ScenarioClass.LOSE_CONDITION.ALL_DESTROYED

    --[[
        Has the scenario ended?
    ]]
    self.IsEnded = false

    --[[
        Did the player win?
    ]]
    self.IsPlayerWinner = false

    --[[
        Ending movie to play.
    ]]
    self.WinMovie = nil
    self.LoseMovie = nil

    --========================================================================
    -- Briefing
    --========================================================================

    --[[
        Briefing text displayed before mission.
    ]]
    self.BriefingText = ""

    --[[
        Action movie played at briefing start.
    ]]
    self.BriefMovie = nil

    --[[
        Win/lose text for end screen.
    ]]
    self.WinText = ""
    self.LoseText = ""

    --========================================================================
    -- Game State
    --========================================================================

    --[[
        Scenario timer in game ticks.
    ]]
    self.Timer = 0

    --[[
        Is the timer counting down (vs counting up)?
    ]]
    self.IsTimerCountdown = false

    --[[
        Mission timer limit (for timed missions).
    ]]
    self.TimerLimit = 0

    --[[
        Global flags (32 available, used by triggers).
    ]]
    self.GlobalFlags = {}
    for i = 0, 31 do
        self.GlobalFlags[i] = false
    end

    --[[
        Is the scenario currently being initialized?
    ]]
    self.IsInitializing = true

    --[[
        Has the intro been played?
    ]]
    self.IsIntroPlayed = false

    --[[
        Current game difficulty.
    ]]
    self.Difficulty = 1  -- 0=Easy, 1=Normal, 2=Hard

    --========================================================================
    -- Multiplayer
    --========================================================================

    --[[
        Is this a multiplayer scenario?
    ]]
    self.IsMultiplayer = false

    --[[
        Number of human players.
    ]]
    self.NumPlayers = 1

    --[[
        Player starting credits.
    ]]
    self.StartingCredits = 0

    --[[
        Tech level limit.
    ]]
    self.TechLevel = 10

    --[[
        Build speed multiplier.
    ]]
    self.BuildSpeedBias = 1.0

    --========================================================================
    -- Campaign
    --========================================================================

    --[[
        Next scenario to play after victory.
    ]]
    self.NextScenario = nil

    --[[
        Is this the last mission in the campaign?
    ]]
    self.IsFinalMission = false

    --[[
        Carryover money from previous mission.
    ]]
    self.CarryoverMoney = 0

    --========================================================================
    -- Special
    --========================================================================

    --[[
        Special weapons available (ion cannon, nuke, airstrike).
    ]]
    self.IsIonCannonEnabled = false
    self.IsNukeEnabled = false
    self.IsAirstrikeEnabled = false

    --[[
        One-time only triggers fired tracker.
    ]]
    self.FiredTriggers = {}

    return self
end

--============================================================================
-- Singleton Instance
--============================================================================

local current_scenario = nil

--[[
    Get the current scenario instance.
    Creates a new one if none exists.

    @return ScenarioClass instance
]]
function ScenarioClass.Get()
    if not current_scenario then
        current_scenario = ScenarioClass.new()
    end
    return current_scenario
end

--[[
    Reset the scenario (for new game).
]]
function ScenarioClass.Reset()
    current_scenario = ScenarioClass.new()
    return current_scenario
end

--============================================================================
-- Instance Methods
--============================================================================

--[[
    Initialize the scenario from loaded data.

    @param data - Scenario data table from loader
]]
function ScenarioClass:Initialize(data)
    self.IsInitializing = true

    -- Scenario identification
    self.Name = data.name or data.Name or ""
    self.Description = data.description or data.Description or self.Name
    self.Number = data.number or data.Number or 0

    -- Parse player type
    if data.player then
        if data.player == "GDI" then
            self.Player = ScenarioClass.PLAYER.GDI
        elseif data.player == "NOD" then
            self.Player = ScenarioClass.PLAYER.NOD
        elseif data.player == "JP" then
            self.Player = ScenarioClass.PLAYER.JP
        elseif data.player == "MULTI" then
            self.Player = ScenarioClass.PLAYER.MPLAYER
        end
    end

    -- Parse theater
    if data.theater then
        local theater_upper = data.theater:upper()
        if theater_upper == "DESERT" then
            self.Theater = ScenarioClass.THEATER.DESERT
        elseif theater_upper == "TEMPERATE" then
            self.Theater = ScenarioClass.THEATER.TEMPERATE
        elseif theater_upper == "WINTER" then
            self.Theater = ScenarioClass.THEATER.WINTER
        end
    end

    -- Map bounds
    self.MapWidth = data.map_width or data.MapWidth or 64
    self.MapHeight = data.map_height or data.MapHeight or 64
    self.MapX = data.map_x or data.MapX or 0
    self.MapY = data.map_y or data.MapY or 0
    self.MapCellWidth = data.map_cell_width or data.MapCellWidth or self.MapWidth
    self.MapCellHeight = data.map_cell_height or data.MapCellHeight or self.MapHeight

    -- Briefing
    self.BriefingText = data.briefing or data.BriefingText or ""
    self.BriefMovie = data.brief_movie or data.BriefMovie
    self.WinMovie = data.win_movie or data.WinMovie
    self.LoseMovie = data.lose_movie or data.LoseMovie
    self.WinText = data.win_text or data.WinText or "Mission Accomplished"
    self.LoseText = data.lose_text or data.LoseText or "Mission Failed"

    -- Game settings
    self.Difficulty = data.difficulty or data.Difficulty or 1
    self.TechLevel = data.tech_level or data.TechLevel or 10
    self.StartingCredits = data.starting_credits or data.StartingCredits or 0
    self.BuildSpeedBias = data.build_speed or data.BuildSpeedBias or 1.0

    -- Timer
    if data.timer_limit or data.TimerLimit then
        self.TimerLimit = data.timer_limit or data.TimerLimit
        self.IsTimerCountdown = true
        self.Timer = self.TimerLimit
    end

    -- Campaign
    self.NextScenario = data.next_scenario or data.NextScenario
    self.IsFinalMission = data.is_final or data.IsFinalMission or false
    self.CarryoverMoney = data.carryover or data.CarryoverMoney or 0

    -- Special weapons
    self.IsIonCannonEnabled = data.ion_cannon or data.IsIonCannonEnabled or false
    self.IsNukeEnabled = data.nuke or data.IsNukeEnabled or false
    self.IsAirstrikeEnabled = data.airstrike or data.IsAirstrikeEnabled or false

    -- Multiplayer
    self.IsMultiplayer = data.multiplayer or data.IsMultiplayer or false
    self.NumPlayers = data.num_players or data.NumPlayers or 1

    -- Reset state
    self.IsEnded = false
    self.IsPlayerWinner = false
    self.FiredTriggers = {}

    self.IsInitializing = false

    -- Emit initialization event
    Events.emit("SCENARIO_INITIALIZED", self)
end

--[[
    Start the scenario (after initialization complete).
]]
function ScenarioClass:Start()
    self.IsInitializing = false
    self.IsIntroPlayed = true

    Events.emit("SCENARIO_STARTED", self)
end

--[[
    Update the scenario timer.

    @param dt - Delta time in seconds
]]
function ScenarioClass:Update(dt)
    if self.IsEnded then return end

    -- Update timer
    local ticks = 15  -- TICKS_PER_SECOND
    if self.IsTimerCountdown then
        self.Timer = self.Timer - ticks * dt
        if self.Timer <= 0 then
            self.Timer = 0
            Events.emit("TIMER_EXPIRED")
        end
    else
        self.Timer = self.Timer + ticks * dt
    end
end

--[[
    Set a global flag.

    @param index - Flag index (0-31)
    @param value - Boolean value
]]
function ScenarioClass:Set_Global(index, value)
    if index >= 0 and index <= 31 then
        self.GlobalFlags[index] = value
        Events.emit("GLOBAL_SET", index, value)
    end
end

--[[
    Get a global flag.

    @param index - Flag index (0-31)
    @return Boolean value
]]
function ScenarioClass:Get_Global(index)
    if index >= 0 and index <= 31 then
        return self.GlobalFlags[index] or false
    end
    return false
end

--[[
    Clear a global flag.

    @param index - Flag index (0-31)
]]
function ScenarioClass:Clear_Global(index)
    self:Set_Global(index, false)
end

--[[
    Trigger player victory.

    @param movie - Optional victory movie to play
]]
function ScenarioClass:Player_Wins(movie)
    if self.IsEnded then return end

    self.IsEnded = true
    self.IsPlayerWinner = true

    local win_movie = movie or self.WinMovie

    Events.emit("SCENARIO_WIN", self, win_movie)
end

--[[
    Trigger player defeat.

    @param movie - Optional defeat movie to play
]]
function ScenarioClass:Player_Loses(movie)
    if self.IsEnded then return end

    self.IsEnded = true
    self.IsPlayerWinner = false

    local lose_movie = movie or self.LoseMovie

    Events.emit("SCENARIO_LOSE", self, lose_movie)
end

--[[
    Check if scenario has ended.

    @return true if ended
]]
function ScenarioClass:Has_Ended()
    return self.IsEnded
end

--[[
    Check if player won.

    @return true if player won
]]
function ScenarioClass:Did_Win()
    return self.IsEnded and self.IsPlayerWinner
end

--[[
    Get formatted timer string.

    @return Timer string (MM:SS)
]]
function ScenarioClass:Get_Timer_String()
    local total_seconds = math.floor(self.Timer / 15)  -- Convert ticks to seconds
    local minutes = math.floor(total_seconds / 60)
    local seconds = total_seconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

--[[
    Get theater name.

    @return Theater name string
]]
function ScenarioClass:Get_Theater_Name()
    return ScenarioClass.THEATER_NAMES[self.Theater] or "TEMPERATE"
end

--[[
    Build scenario filename from components.

    @return Scenario filename (without extension)
]]
function ScenarioClass:Build_Filename()
    local player_char = "G"
    if self.Player == ScenarioClass.PLAYER.NOD then
        player_char = "B"
    elseif self.Player == ScenarioClass.PLAYER.JP then
        player_char = "J"
    elseif self.Player == ScenarioClass.PLAYER.MPLAYER then
        player_char = "M"
    end

    local dir_char = ""
    if self.Direction == ScenarioClass.DIR.EAST then
        dir_char = "E"
    elseif self.Direction == ScenarioClass.DIR.WEST then
        dir_char = "W"
    end

    local var_char = ""
    if self.Variant >= ScenarioClass.VAR.A and self.Variant <= ScenarioClass.VAR.D then
        var_char = string.char(string.byte("A") + self.Variant)
    end

    return string.format("SC%s%02d%s%s", player_char, self.Number, dir_char, var_char)
end

--[[
    Record that a one-time trigger has fired.

    @param trigger_name - Name of the trigger
]]
function ScenarioClass:Record_Trigger_Fired(trigger_name)
    self.FiredTriggers[trigger_name] = true
end

--[[
    Check if a one-time trigger has already fired.

    @param trigger_name - Name of the trigger
    @return true if already fired
]]
function ScenarioClass:Has_Trigger_Fired(trigger_name)
    return self.FiredTriggers[trigger_name] or false
end

--[[
    Debug dump of scenario state.
]]
function ScenarioClass:Debug_Dump()
    print(string.format("ScenarioClass: %s", self.Name))
    print(string.format("  Number=%d Player=%d Direction=%d Variant=%d",
        self.Number, self.Player, self.Direction, self.Variant))
    print(string.format("  Theater=%s Map=%dx%d",
        self:Get_Theater_Name(), self.MapWidth, self.MapHeight))
    print(string.format("  Timer=%s (countdown=%s limit=%d)",
        self:Get_Timer_String(), tostring(self.IsTimerCountdown), self.TimerLimit))
    print(string.format("  Ended=%s Winner=%s",
        tostring(self.IsEnded), tostring(self.IsPlayerWinner)))
    print(string.format("  TechLevel=%d Credits=%d Difficulty=%d",
        self.TechLevel, self.StartingCredits, self.Difficulty))

    -- Print global flags that are set
    local flags = {}
    for i = 0, 31 do
        if self.GlobalFlags[i] then
            table.insert(flags, tostring(i))
        end
    end
    if #flags > 0 then
        print(string.format("  GlobalFlags: %s", table.concat(flags, ", ")))
    end
end

--============================================================================
-- Serialization
--============================================================================

--[[
    Save scenario state.

    @return Table of saveable data
]]
function ScenarioClass:Save()
    return {
        number = self.Number,
        player = self.Player,
        direction = self.Direction,
        variant = self.Variant,
        name = self.Name,
        description = self.Description,
        crc = self.CRC,
        theater = self.Theater,
        map_width = self.MapWidth,
        map_height = self.MapHeight,
        map_x = self.MapX,
        map_y = self.MapY,
        map_cell_width = self.MapCellWidth,
        map_cell_height = self.MapCellHeight,
        win_condition = self.WinCondition,
        lose_condition = self.LoseCondition,
        is_ended = self.IsEnded,
        is_player_winner = self.IsPlayerWinner,
        win_movie = self.WinMovie,
        lose_movie = self.LoseMovie,
        briefing_text = self.BriefingText,
        brief_movie = self.BriefMovie,
        win_text = self.WinText,
        lose_text = self.LoseText,
        timer = self.Timer,
        is_timer_countdown = self.IsTimerCountdown,
        timer_limit = self.TimerLimit,
        global_flags = self.GlobalFlags,
        difficulty = self.Difficulty,
        is_multiplayer = self.IsMultiplayer,
        num_players = self.NumPlayers,
        starting_credits = self.StartingCredits,
        tech_level = self.TechLevel,
        build_speed_bias = self.BuildSpeedBias,
        next_scenario = self.NextScenario,
        is_final_mission = self.IsFinalMission,
        carryover_money = self.CarryoverMoney,
        is_ion_cannon_enabled = self.IsIonCannonEnabled,
        is_nuke_enabled = self.IsNukeEnabled,
        is_airstrike_enabled = self.IsAirstrikeEnabled,
        fired_triggers = self.FiredTriggers,
    }
end

--[[
    Load scenario from saved data.

    @param data - Saved data table
]]
function ScenarioClass:Load(data)
    self.Number = data.number or 0
    self.Player = data.player or ScenarioClass.PLAYER.NONE
    self.Direction = data.direction or ScenarioClass.DIR.NONE
    self.Variant = data.variant or ScenarioClass.VAR.NONE
    self.Name = data.name or ""
    self.Description = data.description or ""
    self.CRC = data.crc or 0
    self.Theater = data.theater or ScenarioClass.THEATER.TEMPERATE
    self.MapWidth = data.map_width or 64
    self.MapHeight = data.map_height or 64
    self.MapX = data.map_x or 0
    self.MapY = data.map_y or 0
    self.MapCellWidth = data.map_cell_width or self.MapWidth
    self.MapCellHeight = data.map_cell_height or self.MapHeight
    self.WinCondition = data.win_condition or ScenarioClass.WIN_CONDITION.DESTROY_ALL
    self.LoseCondition = data.lose_condition or ScenarioClass.LOSE_CONDITION.ALL_DESTROYED
    self.IsEnded = data.is_ended or false
    self.IsPlayerWinner = data.is_player_winner or false
    self.WinMovie = data.win_movie
    self.LoseMovie = data.lose_movie
    self.BriefingText = data.briefing_text or ""
    self.BriefMovie = data.brief_movie
    self.WinText = data.win_text or "Mission Accomplished"
    self.LoseText = data.lose_text or "Mission Failed"
    self.Timer = data.timer or 0
    self.IsTimerCountdown = data.is_timer_countdown or false
    self.TimerLimit = data.timer_limit or 0
    self.GlobalFlags = data.global_flags or {}
    self.Difficulty = data.difficulty or 1
    self.IsMultiplayer = data.is_multiplayer or false
    self.NumPlayers = data.num_players or 1
    self.StartingCredits = data.starting_credits or 0
    self.TechLevel = data.tech_level or 10
    self.BuildSpeedBias = data.build_speed_bias or 1.0
    self.NextScenario = data.next_scenario
    self.IsFinalMission = data.is_final_mission or false
    self.CarryoverMoney = data.carryover_money or 0
    self.IsIonCannonEnabled = data.is_ion_cannon_enabled or false
    self.IsNukeEnabled = data.is_nuke_enabled or false
    self.IsAirstrikeEnabled = data.is_airstrike_enabled or false
    self.FiredTriggers = data.fired_triggers or {}

    self.IsInitializing = false
end

return ScenarioClass
