--[[
    Network Protocol - Packet definitions and serialization for multiplayer
    Based on original C&C deterministic lockstep networking
]]

local Protocol = {}
Protocol.__index = Protocol

-- Protocol version for compatibility checking
Protocol.VERSION = 1

-- Packet types
Protocol.PACKET = {
    -- Connection
    HELLO = 0x01,           -- Initial connection request
    WELCOME = 0x02,         -- Connection accepted
    REJECT = 0x03,          -- Connection rejected
    DISCONNECT = 0x04,      -- Clean disconnect
    PING = 0x05,            -- Latency check
    PONG = 0x06,            -- Latency response

    -- Lobby
    LOBBY_STATE = 0x10,     -- Full lobby state
    PLAYER_JOIN = 0x11,     -- Player joined lobby
    PLAYER_LEAVE = 0x12,    -- Player left lobby
    CHAT_MESSAGE = 0x13,    -- Chat message
    PLAYER_READY = 0x14,    -- Player ready status
    GAME_SETTINGS = 0x15,   -- Game settings changed
    START_COUNTDOWN = 0x16, -- Game starting countdown
    CANCEL_COUNTDOWN = 0x17,-- Countdown cancelled

    -- Game sync
    GAME_START = 0x20,      -- Game is starting
    SYNC_SEED = 0x21,       -- Random seed synchronization
    FRAME_DATA = 0x22,      -- Frame commands
    FRAME_ACK = 0x23,       -- Frame acknowledgment
    SYNC_CHECK = 0x24,      -- Synchronization checksum
    DESYNC_DETECTED = 0x25, -- Desync error
    PAUSE_REQUEST = 0x26,   -- Request game pause
    RESUME_REQUEST = 0x27,  -- Request game resume

    -- Commands (sent within FRAME_DATA)
    CMD_MOVE = 0x30,        -- Unit move command
    CMD_ATTACK = 0x31,      -- Attack command
    CMD_STOP = 0x32,        -- Stop command
    CMD_DEPLOY = 0x33,      -- Deploy command
    CMD_GUARD = 0x34,       -- Guard command
    CMD_SCATTER = 0x35,     -- Scatter command
    CMD_BUILD = 0x36,       -- Build unit/structure
    CMD_SELL = 0x37,        -- Sell structure
    CMD_REPAIR = 0x38,      -- Repair structure
    CMD_SPECIAL = 0x39,     -- Special weapon
    CMD_WAYPOINT = 0x3A,    -- Set waypoint
    CMD_TEAM = 0x3B,        -- Team/formation command
    CMD_ALLIANCE = 0x3C,    -- Alliance change

    -- Spectator
    SPECTATOR_JOIN = 0x40,  -- Spectator joining
    SPECTATOR_DATA = 0x41,  -- Game state for spectator
    SPECTATOR_CHAT = 0x42   -- Spectator chat
}

-- Create protocol instance
function Protocol.new()
    local self = setmetatable({}, Protocol)
    self.sequence = 0
    return self
end

-- Get next sequence number
function Protocol:next_sequence()
    self.sequence = (self.sequence + 1) % 65536
    return self.sequence
end

-- Encode packet header
function Protocol:encode_header(packet_type, payload_length)
    local header = string.char(
        Protocol.VERSION,
        packet_type,
        bit.band(payload_length, 0xFF),
        bit.rshift(payload_length, 8)
    )
    return header
end

-- Decode packet header
function Protocol:decode_header(data)
    if #data < 4 then
        return nil, "Header too short"
    end

    local version = string.byte(data, 1)
    local packet_type = string.byte(data, 2)
    local length_low = string.byte(data, 3)
    local length_high = string.byte(data, 4)
    local payload_length = length_low + length_high * 256

    if version ~= Protocol.VERSION then
        return nil, "Version mismatch"
    end

    return {
        version = version,
        type = packet_type,
        payload_length = payload_length
    }
end

-- Encode integer (little endian)
function Protocol:encode_int(value, bytes)
    bytes = bytes or 4
    local result = {}
    for _ = 1, bytes do
        table.insert(result, string.char(bit.band(value, 0xFF)))
        value = bit.rshift(value, 8)
    end
    return table.concat(result)
end

-- Decode integer (little endian)
function Protocol:decode_int(data, offset, bytes)
    bytes = bytes or 4
    offset = offset or 1
    local value = 0
    for i = 0, bytes - 1 do
        value = value + string.byte(data, offset + i) * (256 ^ i)
    end
    return value
end

-- Encode string (length-prefixed)
function Protocol:encode_string(str)
    local len = #str
    return self:encode_int(len, 2) .. str
end

-- Decode string (length-prefixed)
function Protocol:decode_string(data, offset)
    offset = offset or 1
    local len = self:decode_int(data, offset, 2)
    local str = string.sub(data, offset + 2, offset + 1 + len)
    return str, offset + 2 + len
end

-- Create HELLO packet
function Protocol:create_hello(player_name, game_version)
    local payload = self:encode_string(player_name) ..
                    self:encode_string(game_version)
    return self:encode_header(Protocol.PACKET.HELLO, #payload) .. payload
end

-- Create WELCOME packet
function Protocol:create_welcome(player_id, player_count)
    local payload = self:encode_int(player_id, 1) ..
                    self:encode_int(player_count, 1)
    return self:encode_header(Protocol.PACKET.WELCOME, #payload) .. payload
end

-- Create REJECT packet
function Protocol:create_reject(reason)
    local payload = self:encode_string(reason)
    return self:encode_header(Protocol.PACKET.REJECT, #payload) .. payload
end

-- Create PING packet
function Protocol:create_ping(timestamp)
    local payload = self:encode_int(timestamp, 4)
    return self:encode_header(Protocol.PACKET.PING, #payload) .. payload
end

-- Create PONG packet
function Protocol:create_pong(timestamp)
    local payload = self:encode_int(timestamp, 4)
    return self:encode_header(Protocol.PACKET.PONG, #payload) .. payload
end

-- Create CHAT_MESSAGE packet
function Protocol:create_chat(sender_id, message)
    local payload = self:encode_int(sender_id, 1) ..
                    self:encode_string(message)
    return self:encode_header(Protocol.PACKET.CHAT_MESSAGE, #payload) .. payload
end

-- Create FRAME_DATA packet
function Protocol:create_frame_data(frame_number, commands)
    local payload = self:encode_int(frame_number, 4) ..
                    self:encode_int(#commands, 2)

    for _, cmd in ipairs(commands) do
        payload = payload .. self:encode_command(cmd)
    end

    return self:encode_header(Protocol.PACKET.FRAME_DATA, #payload) .. payload
end

-- Encode a single command
function Protocol:encode_command(cmd)
    local data = string.char(cmd.type) ..
                 self:encode_int(cmd.player_id, 1)

    if cmd.type == Protocol.PACKET.CMD_MOVE then
        data = data .. self:encode_int(cmd.entity_count, 2)
        for _, id in ipairs(cmd.entities) do
            data = data .. self:encode_int(id, 4)
        end
        data = data .. self:encode_int(cmd.dest_x, 4) ..
                       self:encode_int(cmd.dest_y, 4)

    elseif cmd.type == Protocol.PACKET.CMD_ATTACK then
        data = data .. self:encode_int(cmd.attacker_id, 4) ..
                       self:encode_int(cmd.target_id, 4)

    elseif cmd.type == Protocol.PACKET.CMD_BUILD then
        data = data .. self:encode_int(cmd.building_type, 2) ..
                       self:encode_int(cmd.cell_x, 2) ..
                       self:encode_int(cmd.cell_y, 2)

    elseif cmd.type == Protocol.PACKET.CMD_SELL then
        data = data .. self:encode_int(cmd.building_id, 4)

    elseif cmd.type == Protocol.PACKET.CMD_SPECIAL then
        data = data .. self:encode_int(cmd.weapon_type, 1) ..
                       self:encode_int(cmd.target_x, 4) ..
                       self:encode_int(cmd.target_y, 4)
    end

    return data
end

-- Create SYNC_CHECK packet
function Protocol:create_sync_check(frame_number, checksum)
    local payload = self:encode_int(frame_number, 4) ..
                    self:encode_int(checksum, 4)
    return self:encode_header(Protocol.PACKET.SYNC_CHECK, #payload) .. payload
end

-- Create GAME_START packet
function Protocol:create_game_start(seed, scenario_name, player_houses)
    local payload = self:encode_int(seed, 4) ..
                    self:encode_string(scenario_name) ..
                    self:encode_int(#player_houses, 1)

    for _, house in ipairs(player_houses) do
        payload = payload .. self:encode_int(house.player_id, 1) ..
                             self:encode_int(house.house, 1) ..
                             self:encode_int(house.color, 1)
    end

    return self:encode_header(Protocol.PACKET.GAME_START, #payload) .. payload
end

-- Decode any packet
function Protocol:decode(data)
    local header, err = self:decode_header(data)
    if not header then
        return nil, err
    end

    local payload = string.sub(data, 5, 4 + header.payload_length)
    local packet = { type = header.type }

    if header.type == Protocol.PACKET.HELLO then
        packet.player_name, _ = self:decode_string(payload, 1)
        packet.game_version, _ = self:decode_string(payload, 3 + #packet.player_name)

    elseif header.type == Protocol.PACKET.WELCOME then
        packet.player_id = self:decode_int(payload, 1, 1)
        packet.player_count = self:decode_int(payload, 2, 1)

    elseif header.type == Protocol.PACKET.REJECT then
        packet.reason, _ = self:decode_string(payload, 1)

    elseif header.type == Protocol.PACKET.PING or
           header.type == Protocol.PACKET.PONG then
        packet.timestamp = self:decode_int(payload, 1, 4)

    elseif header.type == Protocol.PACKET.CHAT_MESSAGE then
        packet.sender_id = self:decode_int(payload, 1, 1)
        packet.message, _ = self:decode_string(payload, 2)

    elseif header.type == Protocol.PACKET.FRAME_DATA then
        packet.frame_number = self:decode_int(payload, 1, 4)
        packet.command_count = self:decode_int(payload, 5, 2)
        packet.commands = {}
        -- Command decoding would go here

    elseif header.type == Protocol.PACKET.SYNC_CHECK then
        packet.frame_number = self:decode_int(payload, 1, 4)
        packet.checksum = self:decode_int(payload, 5, 4)
    end

    return packet
end

-- Calculate checksum for sync verification
function Protocol:calculate_checksum(world)
    local checksum = 0

    -- Hash entity positions and states
    local entities = world:get_all_entities()
    for _, entity in ipairs(entities) do
        local transform = entity:get("transform")
        if transform then
            checksum = bit.bxor(checksum, transform.x or 0)
            checksum = bit.bxor(checksum, transform.y or 0)
        end

        local health = entity:get("health")
        if health then
            checksum = bit.bxor(checksum, health.hp or 0)
        end
    end

    return checksum
end

return Protocol
