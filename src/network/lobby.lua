--[[
    Lobby - Multiplayer game lobby management
    Handles player connections, ready states, and game settings
]]

local Protocol = require("src.network.protocol")

local Lobby = {}
Lobby.__index = Lobby

-- Lobby states
Lobby.STATE = {
    IDLE = "idle",
    HOSTING = "hosting",
    JOINING = "joining",
    IN_LOBBY = "in_lobby",
    COUNTDOWN = "countdown",
    STARTING = "starting"
}

-- Maximum players
Lobby.MAX_PLAYERS = 4
Lobby.MAX_SPECTATORS = 4

function Lobby.new()
    local self = setmetatable({}, Lobby)

    self.state = Lobby.STATE.IDLE
    self.is_host = false

    -- Players in lobby
    self.players = {}
    self.spectators = {}

    -- Local player info
    self.local_player = {
        id = 0,
        name = "Player",
        house = 1,    -- GDI
        color = 1,    -- Gold
        ready = false
    }

    -- Game settings (host controls)
    self.settings = {
        scenario = "SCG01EA",
        starting_credits = 5000,
        build_speed = 1.0,
        unit_count = 0,         -- 0 = unlimited
        crates = false,
        bases = true,
        tiberium_growth = true,
        fog_of_war = true,
        shroud = true,
        game_speed = 3          -- 1-6
    }

    -- Countdown
    self.countdown_time = 0
    self.countdown_max = 5

    -- Chat history
    self.chat_messages = {}
    self.max_chat_messages = 100

    -- Protocol
    self.protocol = Protocol.new()

    -- Callbacks
    self.on_send = nil
    self.on_player_joined = nil
    self.on_player_left = nil
    self.on_chat = nil
    self.on_game_start = nil
    self.on_settings_changed = nil

    return self
end

-- Host a new game
function Lobby:host(player_name)
    self.state = Lobby.STATE.HOSTING
    self.is_host = true

    self.local_player.id = 1
    self.local_player.name = player_name

    self.players = {
        [1] = {
            id = 1,
            name = player_name,
            house = 1,
            color = 1,
            ready = false,
            ping = 0
        }
    }

    self.state = Lobby.STATE.IN_LOBBY
end

-- Join an existing game
function Lobby:join(host_address, player_name)
    self.state = Lobby.STATE.JOINING
    self.is_host = false
    self.local_player.name = player_name

    -- Send HELLO packet
    local packet = self.protocol:create_hello(player_name, "1.0.0")
    if self.on_send then
        self.on_send(host_address, packet)
    end
end

-- Handle incoming packet
function Lobby:receive_packet(from_address, data)
    local packet = self.protocol:decode(data)
    if not packet then return end

    if packet.type == Protocol.PACKET.HELLO then
        -- New player joining (host only)
        if self.is_host then
            self:handle_join_request(from_address, packet)
        end

    elseif packet.type == Protocol.PACKET.WELCOME then
        -- Connection accepted
        self.local_player.id = packet.player_id
        self.state = Lobby.STATE.IN_LOBBY

    elseif packet.type == Protocol.PACKET.REJECT then
        -- Connection rejected
        self.state = Lobby.STATE.IDLE
        -- Could trigger callback here

    elseif packet.type == Protocol.PACKET.LOBBY_STATE then
        self:handle_lobby_state(packet)

    elseif packet.type == Protocol.PACKET.PLAYER_JOIN then
        self:handle_player_join(packet)

    elseif packet.type == Protocol.PACKET.PLAYER_LEAVE then
        self:handle_player_leave(packet)

    elseif packet.type == Protocol.PACKET.CHAT_MESSAGE then
        self:handle_chat(packet)

    elseif packet.type == Protocol.PACKET.PLAYER_READY then
        self:handle_ready_change(packet)

    elseif packet.type == Protocol.PACKET.GAME_SETTINGS then
        self:handle_settings_change(packet)

    elseif packet.type == Protocol.PACKET.START_COUNTDOWN then
        self:start_countdown()

    elseif packet.type == Protocol.PACKET.CANCEL_COUNTDOWN then
        self:cancel_countdown()

    elseif packet.type == Protocol.PACKET.GAME_START then
        self:handle_game_start(packet)

    elseif packet.type == Protocol.PACKET.PING then
        -- Respond with PONG
        local pong = self.protocol:create_pong(packet.timestamp)
        if self.on_send then
            self.on_send(from_address, pong)
        end
    end
end

-- Handle join request (host only)
function Lobby:handle_join_request(from_address, packet)
    -- Check if room is full
    local player_count = 0
    for _ in pairs(self.players) do
        player_count = player_count + 1
    end

    if player_count >= Lobby.MAX_PLAYERS then
        local reject = self.protocol:create_reject("Game is full")
        if self.on_send then
            self.on_send(from_address, reject)
        end
        return
    end

    -- Assign player ID
    local new_id = 0
    for i = 1, Lobby.MAX_PLAYERS do
        if not self.players[i] then
            new_id = i
            break
        end
    end

    if new_id == 0 then
        local reject = self.protocol:create_reject("No slots available")
        if self.on_send then
            self.on_send(from_address, reject)
        end
        return
    end

    -- Add player
    local new_player = {
        id = new_id,
        name = packet.player_name,
        house = new_id,  -- Assign unique house
        color = new_id,  -- Assign unique color
        ready = false,
        address = from_address,
        ping = 0
    }

    self.players[new_id] = new_player

    -- Send WELCOME to new player
    local welcome = self.protocol:create_welcome(new_id, player_count + 1)
    if self.on_send then
        self.on_send(from_address, welcome)
    end

    -- Broadcast to other players
    self:broadcast_player_joined(new_player)

    -- Send full lobby state to new player
    self:send_lobby_state(from_address)

    if self.on_player_joined then
        self.on_player_joined(new_player)
    end
end

-- Handle player leaving
function Lobby:handle_player_leave(packet)
    local player_id = packet.player_id
    local player = self.players[player_id]

    if player then
        self.players[player_id] = nil

        if self.on_player_left then
            self.on_player_left(player)
        end
    end
end

-- Send chat message
function Lobby:send_chat(message)
    local chat_entry = {
        sender_id = self.local_player.id,
        sender_name = self.local_player.name,
        message = message,
        timestamp = os.time()
    }

    table.insert(self.chat_messages, chat_entry)
    if #self.chat_messages > self.max_chat_messages then
        table.remove(self.chat_messages, 1)
    end

    -- Broadcast
    local packet = self.protocol:create_chat(self.local_player.id, message)
    self:broadcast(packet)
end

-- Handle incoming chat
function Lobby:handle_chat(packet)
    local player = self.players[packet.sender_id]
    local sender_name = player and player.name or "Unknown"

    local chat_entry = {
        sender_id = packet.sender_id,
        sender_name = sender_name,
        message = packet.message,
        timestamp = os.time()
    }

    table.insert(self.chat_messages, chat_entry)
    if #self.chat_messages > self.max_chat_messages then
        table.remove(self.chat_messages, 1)
    end

    if self.on_chat then
        self.on_chat(chat_entry)
    end
end

-- Set local player ready state
function Lobby:set_ready(ready)
    self.local_player.ready = ready

    if self.players[self.local_player.id] then
        self.players[self.local_player.id].ready = ready
    end

    -- Broadcast ready state change
    -- (would create PLAYER_READY packet and broadcast)
end

-- Set local player house
function Lobby:set_house(house)
    self.local_player.house = house

    if self.players[self.local_player.id] then
        self.players[self.local_player.id].house = house
    end
end

-- Set local player color
function Lobby:set_color(color)
    self.local_player.color = color

    if self.players[self.local_player.id] then
        self.players[self.local_player.id].color = color
    end
end

-- Change game settings (host only)
function Lobby:set_settings(new_settings)
    if not self.is_host then return end

    for key, value in pairs(new_settings) do
        if self.settings[key] ~= nil then
            self.settings[key] = value
        end
    end

    -- Broadcast settings change
    if self.on_settings_changed then
        self.on_settings_changed(self.settings)
    end
end

-- Check if all players are ready
function Lobby:all_players_ready()
    local count = 0
    for _, player in pairs(self.players) do
        if not player.ready then
            return false
        end
        count = count + 1
    end
    return count >= 2  -- Need at least 2 players
end

-- Start countdown (host only)
function Lobby:start_countdown()
    if not self.is_host and self.state ~= Lobby.STATE.IN_LOBBY then
        return false
    end

    if not self:all_players_ready() then
        return false
    end

    self.state = Lobby.STATE.COUNTDOWN
    self.countdown_time = self.countdown_max

    return true
end

-- Cancel countdown
function Lobby:cancel_countdown()
    if self.state == Lobby.STATE.COUNTDOWN then
        self.state = Lobby.STATE.IN_LOBBY
        self.countdown_time = 0
    end
end

-- Update countdown
function Lobby:update(dt)
    if self.state == Lobby.STATE.COUNTDOWN then
        self.countdown_time = self.countdown_time - dt

        if self.countdown_time <= 0 then
            self:start_game()
        end
    end
end

-- Start the game
function Lobby:start_game()
    self.state = Lobby.STATE.STARTING

    -- Generate random seed for determinism
    local seed = os.time()

    -- Collect player houses
    local player_houses = {}
    for _, player in pairs(self.players) do
        table.insert(player_houses, {
            player_id = player.id,
            house = player.house,
            color = player.color
        })
    end

    if self.on_game_start then
        self.on_game_start(seed, self.settings.scenario, player_houses)
    end
end

-- Send full lobby state to a player
function Lobby:send_lobby_state(address)
    -- Would serialize full lobby state and send
end

-- Broadcast packet to all players
function Lobby:broadcast(packet)
    if self.on_send then
        for _, player in pairs(self.players) do
            if player.id ~= self.local_player.id and player.address then
                self.on_send(player.address, packet)
            end
        end
    end
end

-- Broadcast player joined
function Lobby:broadcast_player_joined(player)
    -- Would create PLAYER_JOIN packet and broadcast
end

-- Get player list for display
function Lobby:get_player_list()
    local list = {}
    for _, player in pairs(self.players) do
        table.insert(list, {
            id = player.id,
            name = player.name,
            house = player.house,
            color = player.color,
            ready = player.ready,
            is_host = player.id == 1,
            is_local = player.id == self.local_player.id
        })
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Leave the lobby
function Lobby:leave()
    -- Broadcast leave
    self.state = Lobby.STATE.IDLE
    self.players = {}
    self.spectators = {}
    self.chat_messages = {}
end

return Lobby
