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

-- Camera control state
function Spectator:init_camera()
    self.camera = {
        x = 0,
        y = 0,
        target_x = 0,
        target_y = 0,
        follow_entity = nil,
        scroll_speed = 500,       -- Pixels per second
        smooth_factor = 5,        -- Camera smoothing
        zoom = 1.0,
        min_zoom = 0.5,
        max_zoom = 2.0
    }
end

-- Set camera position
function Spectator:set_camera_position(x, y)
    self.camera.target_x = x
    self.camera.target_y = y
end

-- Get camera for rendering
function Spectator:get_camera()
    return self.camera
end

-- Follow a specific entity
function Spectator:follow_entity(entity)
    self.camera.follow_entity = entity
end

-- Update camera (call in update loop)
function Spectator:update_camera(dt, world)
    if not self.camera then
        self:init_camera()
    end

    -- Follow player's view if set
    if self.viewing_player > 0 then
        local player = self.players[self.viewing_player]
        if player then
            -- Find player's first building or unit to center on
            if world then
                local entities = world:get_entities_with("owner", "transform")
                for _, entity in ipairs(entities) do
                    local owner = entity:get("owner")
                    if owner.house == player.house then
                        local transform = entity:get("transform")
                        self.camera.target_x = transform.x
                        self.camera.target_y = transform.y
                        break
                    end
                end
            end
        end
    elseif self.camera.follow_entity then
        -- Follow specific entity
        if self.camera.follow_entity:is_alive() and self.camera.follow_entity:has("transform") then
            local transform = self.camera.follow_entity:get("transform")
            self.camera.target_x = transform.x
            self.camera.target_y = transform.y
        else
            self.camera.follow_entity = nil
        end
    end

    -- Smooth camera movement
    local dx = self.camera.target_x - self.camera.x
    local dy = self.camera.target_y - self.camera.y
    local factor = self.camera.smooth_factor * dt

    self.camera.x = self.camera.x + dx * factor
    self.camera.y = self.camera.y + dy * factor
end

-- Handle keyboard input for free camera
function Spectator:handle_camera_input(dt, keys)
    if self.viewing_player ~= 0 then
        return -- Only free camera in player 0 mode
    end

    local speed = self.camera.scroll_speed * dt

    if keys.up or keys.w then
        self.camera.target_y = self.camera.target_y - speed
    end
    if keys.down or keys.s then
        self.camera.target_y = self.camera.target_y + speed
    end
    if keys.left or keys.a then
        self.camera.target_x = self.camera.target_x - speed
    end
    if keys.right or keys.d then
        self.camera.target_x = self.camera.target_x + speed
    end
end

-- Zoom camera
function Spectator:zoom_camera(delta)
    self.camera.zoom = math.max(
        self.camera.min_zoom,
        math.min(self.camera.max_zoom, self.camera.zoom + delta * 0.1)
    )
end

-- Toggle fog of war view
function Spectator:toggle_fog()
    self.fog_disabled = not self.fog_disabled
end

-- Previous player (reverse cycle)
function Spectator:prev_player()
    if self.viewing_player == 0 then
        -- Go to last player
        local max_id = 0
        for _, player in pairs(self.players) do
            max_id = math.max(max_id, player.id)
        end
        self.viewing_player = max_id
    else
        self.viewing_player = self.viewing_player - 1
    end
end

-- Draw spectator HUD
function Spectator:draw_hud()
    local w, h = love.graphics.getDimensions()

    -- Top bar with player info
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, 40)

    -- "SPECTATING" label
    love.graphics.setColor(1, 0.8, 0.2, 1)
    love.graphics.print("SPECTATING", 10, 10)

    -- Current view mode
    local view_text
    if self.viewing_player == 0 then
        view_text = "Free Camera"
    else
        local player = self.players[self.viewing_player]
        if player then
            view_text = player.name or ("Player " .. self.viewing_player)
        else
            view_text = "Player " .. self.viewing_player
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("View: " .. view_text, 150, 10)

    -- Player list
    local px = 350
    for id, player in pairs(self.players) do
        local color = player.color or {1, 1, 1}
        love.graphics.setColor(color[1], color[2], color[3], 1)
        local marker = (id == self.viewing_player) and "> " or "  "
        love.graphics.print(marker .. (player.name or "P" .. id), px, 10)
        px = px + 100
    end

    -- Fog toggle indicator
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local fog_text = self.fog_disabled and "Fog: OFF" or "Fog: ON"
    love.graphics.print(fog_text, w - 100, 10)

    -- Bottom bar with controls
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, h - 30, w, 30)

    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    local controls = "Tab: Next Player | Shift+Tab: Prev | F: Toggle Fog | Arrow Keys: Pan Camera | ESC: Exit"
    love.graphics.printf(controls, 0, h - 22, w, "center")

    -- Buffer health indicator
    local buffer_health = self.stats.buffer_health or 0
    local bar_width = 100
    local bar_height = 8
    local bar_x = w - bar_width - 10
    local bar_y = h - 20

    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height)

    local health_color = buffer_health > 0.5 and {0, 1, 0} or (buffer_health > 0.25 and {1, 1, 0} or {1, 0, 0})
    love.graphics.setColor(health_color[1], health_color[2], health_color[3], 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_width * buffer_health, bar_height)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Handle key press for spectator controls
function Spectator:keypressed(key, scancode, isrepeat)
    if key == "tab" then
        if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
            self:prev_player()
        else
            self:next_player()
        end
        return true

    elseif key == "f" then
        self:toggle_fog()
        return true

    elseif key == "=" or key == "kp+" then
        self:zoom_camera(1)
        return true

    elseif key == "-" or key == "kp-" then
        self:zoom_camera(-1)
        return true

    elseif key == "1" then
        self:set_viewing_player(1)
        return true

    elseif key == "2" then
        self:set_viewing_player(2)
        return true

    elseif key == "3" then
        self:set_viewing_player(3)
        return true

    elseif key == "4" then
        self:set_viewing_player(4)
        return true

    elseif key == "5" then
        self:set_viewing_player(5)
        return true

    elseif key == "6" then
        self:set_viewing_player(6)
        return true

    elseif key == "0" then
        self:set_viewing_player(0)  -- Free camera
        return true
    end

    return false
end

return Spectator
