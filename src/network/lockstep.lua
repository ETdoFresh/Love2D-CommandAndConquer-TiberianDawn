--[[
    Lockstep - Deterministic lockstep synchronization for multiplayer
    Ensures all clients execute the same commands on the same frames
    Reference: Original C&C used per-frame CRC checks for desync detection
]]

local Protocol = require("src.network.protocol")
local CRC32 = require("src.util.crc")
local Events = require("src.core.events")

local Lockstep = {}
Lockstep.__index = Lockstep

-- Configuration
Lockstep.COMMAND_DELAY = 3     -- Frames of input delay (allows time for network)
Lockstep.SYNC_INTERVAL = 15    -- Frames between sync checks
Lockstep.MAX_FRAME_AHEAD = 10  -- Maximum frames ahead of slowest player
Lockstep.TIMEOUT_FRAMES = 90   -- Frames before considering player disconnected

function Lockstep.new(player_count)
    local self = setmetatable({}, Lockstep)

    self.player_count = player_count
    self.local_player_id = 1

    -- Current frame number
    self.current_frame = 0

    -- Command buffers per frame
    -- command_buffer[frame][player_id] = {commands}
    self.command_buffer = {}

    -- Last received frame per player
    self.player_frames = {}
    for i = 1, player_count do
        self.player_frames[i] = 0
    end

    -- Local command queue (pending send)
    self.local_commands = {}

    -- Sync checksums
    self.checksums = {}

    -- Desync detected
    self.desync = false
    self.desync_frame = nil

    -- Waiting for other players
    self.waiting = false
    self.waiting_for = {}

    -- Protocol instance
    self.protocol = Protocol.new()

    -- World reference for CRC calculation
    self.world = nil

    -- Desync tracking
    self.desync_info = {
        local_crc = 0,
        remote_crc = 0,
        mismatched_player = nil
    }

    -- Callbacks
    self.on_send = nil      -- function(data) - send data to network
    self.on_execute = nil   -- function(commands) - execute commands
    self.on_desync = nil    -- function(frame, local_crc, remote_crc) - desync callback

    return self
end

-- Set world reference for state CRC calculation
function Lockstep:set_world(world)
    self.world = world
end

-- Set local player ID
function Lockstep:set_local_player(player_id)
    self.local_player_id = player_id
end

-- Queue a local command
function Lockstep:queue_command(command)
    command.player_id = self.local_player_id

    -- Commands execute COMMAND_DELAY frames in the future
    local target_frame = self.current_frame + Lockstep.COMMAND_DELAY

    if not self.local_commands[target_frame] then
        self.local_commands[target_frame] = {}
    end

    table.insert(self.local_commands[target_frame], command)
end

-- Send pending commands for a frame
function Lockstep:send_commands(frame)
    local commands = self.local_commands[frame] or {}

    -- Create and send frame data packet
    local packet = self.protocol:create_frame_data(frame, commands)

    if self.on_send then
        self.on_send(packet)
    end

    -- Store in local buffer
    self:receive_commands(self.local_player_id, frame, commands)

    -- Clear sent commands
    self.local_commands[frame] = nil
end

-- Receive commands from a player
function Lockstep:receive_commands(player_id, frame, commands)
    if not self.command_buffer[frame] then
        self.command_buffer[frame] = {}
    end

    self.command_buffer[frame][player_id] = commands
    self.player_frames[player_id] = math.max(self.player_frames[player_id], frame)
end

-- Check if we have all commands for a frame
function Lockstep:has_all_commands(frame)
    if not self.command_buffer[frame] then
        return false
    end

    for player_id = 1, self.player_count do
        if not self.command_buffer[frame][player_id] then
            return false
        end
    end

    return true
end

-- Get commands for a frame (all players combined)
function Lockstep:get_frame_commands(frame)
    local all_commands = {}

    if self.command_buffer[frame] then
        for player_id = 1, self.player_count do
            local commands = self.command_buffer[frame][player_id]
            if commands then
                for _, cmd in ipairs(commands) do
                    table.insert(all_commands, cmd)
                end
            end
        end
    end

    -- Sort by player ID for determinism
    table.sort(all_commands, function(a, b)
        return a.player_id < b.player_id
    end)

    return all_commands
end

-- Advance simulation
function Lockstep:update()
    -- Check if we're waiting for other players
    self.waiting = false
    self.waiting_for = {}

    -- Send commands for future frame
    local send_frame = self.current_frame + Lockstep.COMMAND_DELAY
    self:send_commands(send_frame)

    -- Check if we're too far ahead
    local min_frame = math.huge
    for player_id = 1, self.player_count do
        min_frame = math.min(min_frame, self.player_frames[player_id])
    end

    if self.current_frame - min_frame >= Lockstep.MAX_FRAME_AHEAD then
        -- We're too far ahead, wait
        self.waiting = true
        for player_id = 1, self.player_count do
            if self.player_frames[player_id] < self.current_frame then
                table.insert(self.waiting_for, player_id)
            end
        end
        return false
    end

    -- Check if we have all commands for current frame
    if not self:has_all_commands(self.current_frame) then
        self.waiting = true
        for player_id = 1, self.player_count do
            if not self.command_buffer[self.current_frame] or
               not self.command_buffer[self.current_frame][player_id] then
                table.insert(self.waiting_for, player_id)
            end
        end
        return false
    end

    -- Execute frame
    local commands = self:get_frame_commands(self.current_frame)

    if self.on_execute then
        self.on_execute(commands)
    end

    -- Periodic sync check
    if self.current_frame % Lockstep.SYNC_INTERVAL == 0 then
        self:send_sync_check()
    end

    -- Clean up old command buffers
    self:cleanup_old_frames()

    -- Advance frame
    self.current_frame = self.current_frame + 1

    return true
end

-- Calculate current game state CRC
function Lockstep:calculate_state_crc()
    if not self.world then
        return 0
    end

    -- Use the CRC32 utility to compute deterministic game state hash
    return CRC32.quick_state(self.world, self.current_frame)
end

-- Send synchronization checksum
function Lockstep:send_sync_check()
    -- Calculate CRC of current game state
    local checksum = self:calculate_state_crc()

    self.checksums[self.current_frame] = {
        [self.local_player_id] = checksum
    }
    self.desync_info.local_crc = checksum

    local packet = self.protocol:create_sync_check(self.current_frame, checksum)
    if self.on_send then
        self.on_send(packet)
    end
end

-- Receive sync check from another player
function Lockstep:receive_sync_check(player_id, frame, checksum)
    if not self.checksums[frame] then
        self.checksums[frame] = {}
    end

    self.checksums[frame][player_id] = checksum

    -- Check if all players have submitted checksums
    local all_received = true
    for pid = 1, self.player_count do
        if not self.checksums[frame][pid] then
            all_received = false
            break
        end
    end

    if all_received then
        -- Verify all checksums match
        local reference = nil
        local reference_player = nil

        for pid, cs in pairs(self.checksums[frame]) do
            if reference == nil then
                reference = cs
                reference_player = pid
            elseif cs ~= reference then
                -- Desync detected!
                self.desync = true
                self.desync_frame = frame
                self.desync_info.local_crc = self.checksums[frame][self.local_player_id] or 0
                self.desync_info.remote_crc = cs
                self.desync_info.mismatched_player = pid

                -- Emit desync event
                Events.emit("MULTIPLAYER_DESYNC", {
                    frame = frame,
                    local_player = self.local_player_id,
                    local_crc = self.desync_info.local_crc,
                    remote_player = pid,
                    remote_crc = cs
                })

                -- Call desync callback if set
                if self.on_desync then
                    self.on_desync(frame, self.desync_info.local_crc, cs, pid)
                end

                return false
            end
        end
    end

    return true
end

-- Check if game is in desync state
function Lockstep:is_desynced()
    return self.desync
end

-- Get desync details
function Lockstep:get_desync_info()
    return {
        desynced = self.desync,
        frame = self.desync_frame,
        local_crc = self.desync_info.local_crc,
        remote_crc = self.desync_info.remote_crc,
        mismatched_player = self.desync_info.mismatched_player
    }
end

-- Clean up old frame data
function Lockstep:cleanup_old_frames()
    local cleanup_before = self.current_frame - 60  -- Keep last 60 frames

    for frame in pairs(self.command_buffer) do
        if frame < cleanup_before then
            self.command_buffer[frame] = nil
        end
    end

    for frame in pairs(self.checksums) do
        if frame < cleanup_before then
            self.checksums[frame] = nil
        end
    end
end

-- Reset for new game
function Lockstep:reset()
    self.current_frame = 0
    self.command_buffer = {}
    self.local_commands = {}
    self.checksums = {}
    self.desync = false
    self.desync_frame = nil
    self.waiting = false
    self.waiting_for = {}

    for i = 1, self.player_count do
        self.player_frames[i] = 0
    end
end

-- Get current state for debugging/UI
function Lockstep:get_state()
    return {
        current_frame = self.current_frame,
        player_frames = self.player_frames,
        waiting = self.waiting,
        waiting_for = self.waiting_for,
        desync = self.desync,
        desync_frame = self.desync_frame
    }
end

-- Create move command
function Lockstep:create_move_command(entity_ids, dest_x, dest_y)
    return {
        type = Protocol.PACKET.CMD_MOVE,
        entities = entity_ids,
        entity_count = #entity_ids,
        dest_x = dest_x,
        dest_y = dest_y
    }
end

-- Create attack command
function Lockstep:create_attack_command(attacker_id, target_id)
    return {
        type = Protocol.PACKET.CMD_ATTACK,
        attacker_id = attacker_id,
        target_id = target_id
    }
end

-- Create build command
function Lockstep:create_build_command(building_type, cell_x, cell_y)
    return {
        type = Protocol.PACKET.CMD_BUILD,
        building_type = building_type,
        cell_x = cell_x,
        cell_y = cell_y
    }
end

-- Create sell command
function Lockstep:create_sell_command(building_id)
    return {
        type = Protocol.PACKET.CMD_SELL,
        building_id = building_id
    }
end

return Lockstep
