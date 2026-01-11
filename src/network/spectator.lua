--[[
    Spectator - Spectator mode for watching multiplayer games
    Receives game state updates without participating in lockstep
]]

local Protocol = require("src.network.protocol")

local Spectator = {}
Spectator.__index = Spectator

-- Spectator states
Spectator.STATE = {
    DISCONNECTED = "disconnected",
    CONNECTING = "connecting",
    WATCHING = "watching",
    BUFFERING = "buffering"
}

function Spectator.new()
    local self = setmetatable({}, Spectator)

    self.state = Spectator.STATE.DISCONNECTED

    -- Game state from server
    self.game_frame = 0
    self.players = {}

    -- Buffered frames for smooth playback
    self.frame_buffer = {}
    self.buffer_size = 30     -- Buffer 2 seconds at 15 FPS
    self.playback_delay = 15  -- 1 second behind live

    -- Camera can view any player
    self.viewing_player = 0   -- 0 = free camera, 1+ = lock to player
    self.fog_disabled = true  -- Spectators see everything

    -- Statistics
    self.stats = {
        packets_received = 0,
        bytes_received = 0,
        buffer_health = 0
    }

    -- Protocol
    self.protocol = Protocol.new()

    -- Callbacks
    self.on_send = nil
    self.on_frame_ready = nil
    self.on_game_end = nil

    return self
end

-- Connect to a game as spectator
function Spectator:connect(host_address, name)
    self.state = Spectator.STATE.CONNECTING
    self.host_address = host_address
    self.name = name

    -- Would send SPECTATOR_JOIN packet
end

-- Handle incoming spectator data
function Spectator:receive_packet(data)
    local packet = self.protocol:decode(data)
    if not packet then return end

    self.stats.packets_received = self.stats.packets_received + 1
    self.stats.bytes_received = self.stats.bytes_received + #data

    if packet.type == Protocol.PACKET.WELCOME then
        self.state = Spectator.STATE.BUFFERING

    elseif packet.type == Protocol.PACKET.SPECTATOR_DATA then
        self:handle_spectator_data(packet)

    elseif packet.type == Protocol.PACKET.FRAME_DATA then
        self:buffer_frame(packet)

    elseif packet.type == Protocol.PACKET.SPECTATOR_CHAT then
        -- Handle spectator chat
    end
end

-- Handle full game state update
function Spectator:handle_spectator_data(packet)
    -- Would deserialize full game state
    -- Used for initial sync and periodic full updates
end

-- Buffer incoming frame for playback
function Spectator:buffer_frame(packet)
    local frame = packet.frame_number

    self.frame_buffer[frame] = {
        frame_number = frame,
        commands = packet.commands,
        received_at = love.timer.getTime()
    }

    -- Update game frame tracking
    if frame > self.game_frame then
        self.game_frame = frame
    end

    -- Check buffer health
    local buffered = 0
    for _ in pairs(self.frame_buffer) do
        buffered = buffered + 1
    end
    self.stats.buffer_health = buffered / self.buffer_size

    -- Transition to watching when buffer is ready
    if self.state == Spectator.STATE.BUFFERING then
        if buffered >= self.playback_delay then
            self.state = Spectator.STATE.WATCHING
        end
    end
end

-- Get next frame for playback
function Spectator:get_playback_frame()
    if self.state ~= Spectator.STATE.WATCHING then
        return nil
    end

    -- We play back delayed from live
    local playback_frame = self.game_frame - self.playback_delay

    local frame_data = self.frame_buffer[playback_frame]
    if frame_data then
        -- Remove from buffer
        self.frame_buffer[playback_frame] = nil
        return frame_data
    end

    return nil
end

-- Clean up old buffered frames
function Spectator:cleanup_buffer()
    local min_frame = self.game_frame - self.buffer_size * 2

    for frame in pairs(self.frame_buffer) do
        if frame < min_frame then
            self.frame_buffer[frame] = nil
        end
    end
end

-- Update spectator state
function Spectator:update(dt)
    if self.state == Spectator.STATE.WATCHING then
        self:cleanup_buffer()

        -- Get and process playback frame
        local frame = self:get_playback_frame()
        if frame and self.on_frame_ready then
            self.on_frame_ready(frame)
        end
    end
end

-- Set which player's view to follow
function Spectator:set_viewing_player(player_id)
    self.viewing_player = player_id
end

-- Cycle through players
function Spectator:next_player()
    local max_id = 0
    for _, player in pairs(self.players) do
        max_id = math.max(max_id, player.id)
    end

    self.viewing_player = self.viewing_player + 1
    if self.viewing_player > max_id then
        self.viewing_player = 0  -- Free camera
    end
end

-- Send spectator chat
function Spectator:send_chat(message)
    -- Would create and send SPECTATOR_CHAT packet
end

-- Get player info for UI
function Spectator:get_player_info()
    return self.players
end

-- Get connection statistics
function Spectator:get_stats()
    return {
        state = self.state,
        game_frame = self.game_frame,
        packets_received = self.stats.packets_received,
        bytes_received = self.stats.bytes_received,
        buffer_health = self.stats.buffer_health,
        viewing = self.viewing_player
    }
end

-- Disconnect from spectating
function Spectator:disconnect()
    self.state = Spectator.STATE.DISCONNECTED
    self.frame_buffer = {}
    self.players = {}
end

return Spectator
