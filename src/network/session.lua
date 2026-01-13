--[[
    SessionClass - Multiplayer session management

    This class contains variables and routines specifically related to
    multiplayer games. It manages player connections, game options,
    synchronization settings, and messaging.

    Reference: SESSION.H from original C&C source
]]

local Events = require("src.core.events")

local SessionClass = {}
SessionClass.__index = SessionClass

--============================================================================
-- Constants
--============================================================================

-- Maximum players (original limit)
SessionClass.MAX_PLAYERS = 6

-- Maximum build level in multiplayer
SessionClass.MPLAYER_BUILD_LEVEL_MAX = 7

-- Maximum colors available
SessionClass.MAX_MPLAYER_COLORS = 6

-- Player name max length
SessionClass.MPLAYER_NAME_MAX = 12

-- Frame synchronization defaults
SessionClass.MODEM_MIN_MAX_AHEAD = 5
SessionClass.NETWORK_MIN_MAX_AHEAD = 2
SessionClass.DEFAULT_FRAME_SEND_RATE = 3

--============================================================================
-- Game Types
--============================================================================

SessionClass.GAME_TYPE = {
    NORMAL = 0,             -- Not multiplayer (single player)
    MODEM = 1,              -- Modem game
    NULL_MODEM = 2,         -- Serial/null modem
    IPX = 3,                -- IPX network (LAN)
    INTERNET = 4,           -- Internet/TCP game
    GLYPHX = 5,             -- Remastered multiplayer
}

--============================================================================
-- Network Commands
--============================================================================

SessionClass.NET_COMMAND = {
    QUERY_GAME = 0,         -- What games are available?
    ANSWER_GAME = 1,        -- Here's my game info
    QUERY_PLAYER = 2,       -- Who's in this game?
    ANSWER_PLAYER = 3,      -- I'm in that game
    CHAT_ANNOUNCE = 4,      -- I'm at the chat screen
    CHAT_REQUEST = 5,       -- Request chat announce
    QUERY_JOIN = 6,         -- Can I join?
    CONFIRM_JOIN = 7,       -- Yes, you can join
    REJECT_JOIN = 8,        -- No, you can't join
    GAME_OPTIONS = 9,       -- Game options update
    SIGN_OFF = 10,          -- Player leaving
    GO = 11,                -- Start the game
    MESSAGE = 12,           -- Chat message
    PING = 13,              -- Ping for latency
    LOADGAME = 14,          -- Start from saved game
}

--============================================================================
-- Constructor
--============================================================================

function SessionClass.new()
    local self = setmetatable({}, SessionClass)

    -- Session type
    self.Type = SessionClass.GAME_TYPE.NORMAL

    -- Communication protocol (set by lobby)
    self.CommProtocol = nil

    -- Game options
    self.Options = {
        ScenarioIndex = 0,
        Bases = true,           -- Bases allowed
        Credits = 5000,         -- Starting credits
        Tiberium = true,        -- Tiberium on map
        Goodies = true,         -- Crate goodies
        Ghosts = false,         -- Ghost units (spectate dead)
        UnitCount = 10,         -- Starting units
        BuildLevel = 7,         -- Tech/build level
        GameSpeed = 3,          -- Speed setting (1-5)
    }

    -- Unique workstation ID
    self.UniqueID = SessionClass.compute_unique_id()

    -- Local player settings
    self.Handle = "Player"      -- Player name
    self.PrefColor = 0          -- Preferred color index
    self.ColorIdx = 0           -- Actual color index (assigned)
    self.House = 0              -- GDI or NOD
    self.Blitz = false          -- AI blitz mode
    self.ObiWan = false         -- Can see all (cheat)
    self.Solo = false           -- Can play alone

    -- Player counts
    self.MaxPlayers = SessionClass.MAX_PLAYERS
    self.NumPlayers = 0

    -- Frame synchronization
    self.MaxAhead = SessionClass.NETWORK_MIN_MAX_AHEAD
    self.FrameSendRate = SessionClass.DEFAULT_FRAME_SEND_RATE
    self.FrameRateDelay = 0

    -- State flags
    self.LoadGame = false       -- Loading a saved game
    self.EmergencySave = false  -- Emergency save on disconnect

    -- Scenario list
    self.Scenarios = {}
    self.Filenum = {}

    -- Messaging
    self.Messages = {}
    self.LastMessage = ""
    self.WWChat = false

    -- Score tracking
    self.Score = {}
    self.GamesPlayed = 0
    self.NumScores = 0
    self.Winner = -1
    self.CurGame = 0

    -- Network state
    self.IsBridge = false
    self.NetStealth = false     -- Invisible to queries
    self.NetProtect = false     -- Block messages
    self.NetOpen = false        -- Game open for joining
    self.GameName = ""

    -- Player lists
    self.Games = {}             -- Available games
    self.Players = {}           -- Players in current game
    self.Chat = {}              -- Chat participants

    -- Recording/playback
    self.Record = false
    self.Play = false
    self.Attract = false
    self.RecordFile = nil

    -- Sync debugging
    self.TrapFrame = -1
    self.TrapObjType = nil
    self.TrapObject = nil
    self.TrapCoord = nil
    self.TrapThis = nil
    self.TrapCell = nil
    self.TrapCheckHeap = false

    return self
end

--============================================================================
-- Initialization
--============================================================================

--[[
    One-time initialization.
]]
function SessionClass:One_Time()
    -- Initialize static data
    self:Read_Scenario_Descriptions()
end

--[[
    Per-session initialization.
]]
function SessionClass:Init()
    -- Reset to defaults
    self.NumPlayers = 0
    self.LoadGame = false
    self.EmergencySave = false
    self.Winner = -1
    self.Games = {}
    self.Players = {}
    self.Messages = {}
end

--============================================================================
-- Settings I/O
--============================================================================

--[[
    Read multiplayer settings from INI.
]]
function SessionClass:Read_MultiPlayer_Settings()
    -- Load from game settings if available
    local settings = love.filesystem.read("multiplayer.ini")
    if settings then
        -- Parse INI format
        for line in settings:gmatch("[^\r\n]+") do
            local key, value = line:match("^(%w+)%s*=%s*(.+)$")
            if key and value then
                if key == "Handle" then
                    self.Handle = value:sub(1, SessionClass.MPLAYER_NAME_MAX)
                elseif key == "PrefColor" then
                    self.PrefColor = tonumber(value) or 0
                elseif key == "House" then
                    self.House = tonumber(value) or 0
                end
            end
        end
    end
end

--[[
    Write multiplayer settings to INI.
]]
function SessionClass:Write_MultiPlayer_Settings()
    local content = string.format(
        "Handle=%s\nPrefColor=%d\nHouse=%d\n",
        self.Handle, self.PrefColor, self.House
    )
    love.filesystem.write("multiplayer.ini", content)
end

--[[
    Read available scenario descriptions.
]]
function SessionClass:Read_Scenario_Descriptions()
    self.Scenarios = {}
    self.Filenum = {}

    -- Scan for multiplayer scenarios
    local files = love.filesystem.getDirectoryItems("data/scenarios/multiplayer")
    for i, file in ipairs(files) do
        if file:match("%.ini$") or file:match("%.json$") then
            local name = file:gsub("%.[^.]+$", "")
            table.insert(self.Scenarios, name)
            table.insert(self.Filenum, i)
        end
    end
end

--[[
    Free scenario descriptions.
]]
function SessionClass:Free_Scenario_Descriptions()
    self.Scenarios = {}
    self.Filenum = {}
end

--============================================================================
-- Connection Management
--============================================================================

--[[
    Create connections for all players.
    @return Number of connections created
]]
function SessionClass:Create_Connections()
    local connections = 0

    for i, player in ipairs(self.Players) do
        if player and player.ID ~= self.UniqueID then
            -- Create connection to this player
            -- (Implementation depends on network layer)
            connections = connections + 1
        end
    end

    return connections
end

--[[
    Check if this session is the master (host).
    @return true if we're the host
]]
function SessionClass:Am_I_Master()
    if self.Type == SessionClass.GAME_TYPE.NORMAL then
        return true
    end

    -- In multiplayer, first player is master
    if #self.Players > 0 then
        return self.Players[1].ID == self.UniqueID
    end

    return true
end

--[[
    Compute a unique ID for this workstation.
    @return Unique ID number
]]
function SessionClass.compute_unique_id()
    -- Combine time, random, and system info for uniqueness
    local id = os.time()

    -- Add some randomness
    id = id * 31 + math.random(0, 65535)

    -- Incorporate machine-specific data if available
    if love and love.system then
        local os_type = love.system.getOS()
        for i = 1, #os_type do
            id = id * 31 + os_type:byte(i)
        end
    end

    return id % 0x7FFFFFFF  -- Keep it positive
end

--============================================================================
-- Player Management
--============================================================================

--[[
    Add a player to the session.
    @param name Player name
    @param house Player's house (GDI/NOD)
    @param color Player's color index
    @return Player info table, or nil if full
]]
function SessionClass:Add_Player(name, house, color)
    if self.NumPlayers >= self.MaxPlayers then
        return nil
    end

    local player = {
        Name = name:sub(1, SessionClass.MPLAYER_NAME_MAX),
        House = house,
        Color = color,
        ID = SessionClass.compute_unique_id(),
        Ready = false,
    }

    table.insert(self.Players, player)
    self.NumPlayers = #self.Players

    Events.emit("PLAYER_JOINED", player)
    return player
end

--[[
    Remove a player from the session.
    @param id Player's unique ID
    @return true if removed
]]
function SessionClass:Remove_Player(id)
    for i, player in ipairs(self.Players) do
        if player.ID == id then
            table.remove(self.Players, i)
            self.NumPlayers = #self.Players
            Events.emit("PLAYER_LEFT", player)
            return true
        end
    end
    return false
end

--[[
    Get player by ID.
    @param id Player's unique ID
    @return Player info table or nil
]]
function SessionClass:Get_Player(id)
    for _, player in ipairs(self.Players) do
        if player.ID == id then
            return player
        end
    end
    return nil
end

--============================================================================
-- Game Discovery
--============================================================================

--[[
    Add a game to the available games list.
    @param name Game name
    @param is_open Whether game is accepting players
    @return Game info table
]]
function SessionClass:Add_Game(name, is_open)
    local game = {
        Name = name:sub(1, SessionClass.MPLAYER_NAME_MAX),
        IsOpen = is_open,
        LastTime = os.time(),
    }

    table.insert(self.Games, game)
    return game
end

--[[
    Remove stale games from the list.
    @param timeout Seconds before considering a game stale
]]
function SessionClass:Cleanup_Games(timeout)
    timeout = timeout or 30  -- 30 second default

    local now = os.time()
    local i = 1

    while i <= #self.Games do
        if now - self.Games[i].LastTime > timeout then
            table.remove(self.Games, i)
        else
            i = i + 1
        end
    end
end

--============================================================================
-- Messaging
--============================================================================

--[[
    Send a message to all players.
    @param message Message text
]]
function SessionClass:Send_Message(message)
    self.LastMessage = message

    table.insert(self.Messages, {
        Text = message,
        Color = self.ColorIdx,
        Time = os.time(),
    })

    Events.emit("SESSION_MESSAGE", message, self.Handle, self.ColorIdx)
end

--[[
    Receive a message from a player.
    @param message Message text
    @param sender Sender name
    @param color Sender color
]]
function SessionClass:Receive_Message(message, sender, color)
    table.insert(self.Messages, {
        Text = message,
        Sender = sender,
        Color = color,
        Time = os.time(),
    })

    Events.emit("SESSION_MESSAGE_RECEIVED", message, sender, color)
end

--============================================================================
-- Save/Load
--============================================================================

--[[
    Save session state.
    @return Table of session data
]]
function SessionClass:Save()
    return {
        Type = self.Type,
        Options = self.Options,
        Handle = self.Handle,
        House = self.House,
        ColorIdx = self.ColorIdx,
        NumPlayers = self.NumPlayers,
        MaxAhead = self.MaxAhead,
        FrameSendRate = self.FrameSendRate,
        Players = self.Players,
    }
end

--[[
    Load session state.
    @param data Saved session data
]]
function SessionClass:Load(data)
    if not data then return end

    self.Type = data.Type or SessionClass.GAME_TYPE.NORMAL
    self.Options = data.Options or self.Options
    self.Handle = data.Handle or "Player"
    self.House = data.House or 0
    self.ColorIdx = data.ColorIdx or 0
    self.NumPlayers = data.NumPlayers or 0
    self.MaxAhead = data.MaxAhead or SessionClass.NETWORK_MIN_MAX_AHEAD
    self.FrameSendRate = data.FrameSendRate or SessionClass.DEFAULT_FRAME_SEND_RATE
    self.Players = data.Players or {}
end

--============================================================================
-- Sync Debugging
--============================================================================

--[[
    Set up object trapping for sync debugging.
    @param frame Frame to trap on
    @param rtti Object type to trap
    @param coord Coordinate to trap
]]
function SessionClass:Set_Trap(frame, rtti, coord)
    self.TrapFrame = frame
    self.TrapObjType = rtti
    self.TrapCoord = coord
    self.TrapCheckHeap = true
end

--[[
    Check if trap conditions are met.
    Called each frame during gameplay.
]]
function SessionClass:Trap_Object()
    -- Implementation would check if trap conditions are met
    -- and log debug information
end

--============================================================================
-- Color Management
--============================================================================

-- Standard multiplayer colors (GDI colors for remapping)
SessionClass.COLORS = {
    {1.0, 0.84, 0.0},    -- Gold (default GDI)
    {0.8, 0.0, 0.0},     -- Red (default NOD)
    {0.4, 0.6, 1.0},     -- Light Blue
    {1.0, 0.5, 0.0},     -- Orange
    {0.0, 0.8, 0.0},     -- Green
    {0.0, 0.0, 0.8},     -- Blue
}

--[[
    Get RGB color for a color index.
    @param index Color index (0-5)
    @return {r, g, b} table
]]
function SessionClass.Get_Color(index)
    index = (index % SessionClass.MAX_MPLAYER_COLORS) + 1
    return SessionClass.COLORS[index] or {1, 1, 1}
end

--============================================================================
-- Debug
--============================================================================

function SessionClass:Debug_Dump()
    print("SessionClass:")
    print(string.format("  Type: %d", self.Type))
    print(string.format("  UniqueID: %d (0x%08X)", self.UniqueID, self.UniqueID))
    print(string.format("  Handle: %s", self.Handle))
    print(string.format("  House: %d  Color: %d", self.House, self.ColorIdx))
    print(string.format("  Players: %d/%d", self.NumPlayers, self.MaxPlayers))
    print(string.format("  MaxAhead: %d  FrameSendRate: %d", self.MaxAhead, self.FrameSendRate))

    print("  Options:")
    print(string.format("    Credits: %d  BuildLevel: %d  UnitCount: %d",
        self.Options.Credits, self.Options.BuildLevel, self.Options.UnitCount))
    print(string.format("    Bases: %s  Tiberium: %s  Goodies: %s",
        tostring(self.Options.Bases), tostring(self.Options.Tiberium),
        tostring(self.Options.Goodies)))

    if #self.Players > 0 then
        print("  Players:")
        for i, player in ipairs(self.Players) do
            print(string.format("    [%d] %s - House %d, Color %d, Ready: %s",
                i, player.Name, player.House, player.Color, tostring(player.Ready)))
        end
    end

    if #self.Games > 0 then
        print(string.format("  Available Games: %d", #self.Games))
    end

    print(string.format("  Recording: %s  Playing: %s",
        tostring(self.Record), tostring(self.Play)))
end

--============================================================================
-- Global Session Instance
--============================================================================

-- Create global session instance (like original's Session global)
SessionClass.Session = SessionClass.new()

return SessionClass
