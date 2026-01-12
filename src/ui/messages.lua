--[[
    Messages - In-game message display system
    Shows EVA speech text, game events, and player notifications
    Reference: Original C&C message bar at bottom of screen
]]

local Events = require("src.core.events")

local Messages = {}
Messages.__index = Messages

-- Message types with different colors
Messages.TYPE = {
    EVA = "eva",            -- EVA voice text (yellow)
    SYSTEM = "system",      -- System messages (white)
    ALERT = "alert",        -- Alert/warning (red)
    INFO = "info",          -- Info messages (green)
    PLAYER = "player",      -- Player chat (cyan)
    OBJECTIVE = "objective" -- Objective updates (gold)
}

-- Colors for each message type
Messages.COLORS = {
    eva = {1, 0.9, 0.2, 1},        -- Yellow
    system = {1, 1, 1, 1},          -- White
    alert = {1, 0.3, 0.3, 1},       -- Red
    info = {0.3, 1, 0.3, 1},        -- Green
    player = {0.3, 1, 1, 1},        -- Cyan
    objective = {1, 0.8, 0.2, 1}    -- Gold
}

function Messages.new()
    local self = setmetatable({}, Messages)

    -- Message queue
    self.messages = {}
    self.max_messages = 5          -- Max visible messages
    self.max_history = 50          -- Max stored messages

    -- Display settings
    self.x = 10
    self.y = 0                     -- Will be set to bottom of screen
    self.width = 400
    self.line_height = 18
    self.padding = 4
    self.background_alpha = 0.6

    -- Animation
    self.fade_duration = 5.0       -- Seconds before fade starts
    self.fade_time = 1.0           -- Fade out duration

    -- Font
    self.font = nil                -- Will use default

    -- Current speech subtitle
    self.current_subtitle = nil
    self.subtitle_timer = 0
    self.subtitle_duration = 3.0

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function Messages:register_events()
    -- EVA speech text display
    Events.on("SPEECH_TEXT", function(text)
        self:show_subtitle(text)
    end)

    Events.on("PLAY_SPEECH", function(text)
        self:show_subtitle(text)
    end)

    -- System messages
    Events.on("SYSTEM_MESSAGE", function(text)
        self:add(text, Messages.TYPE.SYSTEM)
    end)

    -- Alert messages
    Events.on("ALERT_MESSAGE", function(text)
        self:add(text, Messages.TYPE.ALERT)
    end)

    -- Game events that generate messages
    Events.on("BUILDING_CAPTURED", function()
        self:add("Building captured", Messages.TYPE.INFO)
    end)

    Events.on("LOW_POWER", function()
        self:add("Low power", Messages.TYPE.ALERT)
    end)

    Events.on("INSUFFICIENT_FUNDS", function()
        self:add("Insufficient funds", Messages.TYPE.ALERT)
    end)

    Events.on("SILOS_NEEDED", function()
        self:add("Silos needed", Messages.TYPE.ALERT)
    end)

    Events.on("UNIT_UNDER_ATTACK", function()
        self:add("Unit under attack", Messages.TYPE.ALERT)
    end)

    Events.on("BASE_UNDER_ATTACK", function()
        self:add("Our base is under attack", Messages.TYPE.ALERT)
    end)

    Events.on("HARVESTER_UNDER_ATTACK", function()
        self:add("Harvester under attack", Messages.TYPE.ALERT)
    end)

    Events.on("REINFORCEMENTS_ARRIVED", function()
        self:add("Reinforcements have arrived", Messages.TYPE.INFO)
    end)

    -- Construction messages
    Events.on(Events.EVENTS and Events.EVENTS.BUILDING_BUILT or "BUILDING_BUILT", function()
        self:add("Construction complete", Messages.TYPE.EVA)
    end)

    Events.on(Events.EVENTS and Events.EVENTS.UNIT_BUILT or "UNIT_BUILT", function()
        self:add("Unit ready", Messages.TYPE.EVA)
    end)

    -- Mission messages
    Events.on("MISSION_OBJECTIVE", function(text)
        self:add(text, Messages.TYPE.OBJECTIVE)
    end)

    Events.on(Events.EVENTS and Events.EVENTS.GAME_WIN or "GAME_WIN", function()
        self:add("Mission accomplished", Messages.TYPE.INFO)
    end)

    Events.on(Events.EVENTS and Events.EVENTS.GAME_LOSE or "GAME_LOSE", function()
        self:add("Mission failed", Messages.TYPE.ALERT)
    end)

    -- Special weapons
    Events.on("SPECIAL_WEAPON_READY", function(house, weapon_type)
        local weapon_name = weapon_type:gsub("_", " "):gsub("^%l", string.upper)
        self:add(weapon_name .. " ready", Messages.TYPE.EVA)
    end)

    -- Player chat (multiplayer)
    Events.on("PLAYER_CHAT", function(player_name, text)
        self:add(player_name .. ": " .. text, Messages.TYPE.PLAYER)
    end)
end

-- Add a message
function Messages:add(text, msg_type)
    msg_type = msg_type or Messages.TYPE.SYSTEM

    local message = {
        text = text,
        type = msg_type,
        color = Messages.COLORS[msg_type] or Messages.COLORS.system,
        time = love.timer.getTime(),
        alpha = 1.0
    }

    table.insert(self.messages, 1, message)  -- Add to front

    -- Limit stored messages
    while #self.messages > self.max_history do
        table.remove(self.messages)
    end

    Events.emit("MESSAGE_ADDED", text, msg_type)
end

-- Show subtitle (EVA speech text)
function Messages:show_subtitle(text)
    self.current_subtitle = text
    self.subtitle_timer = self.subtitle_duration
end

-- Update message timers
function Messages:update(dt)
    local current_time = love.timer.getTime()

    -- Update message alpha (fade out old messages)
    for i, msg in ipairs(self.messages) do
        local age = current_time - msg.time

        if age > self.fade_duration then
            local fade_progress = (age - self.fade_duration) / self.fade_time
            msg.alpha = math.max(0, 1 - fade_progress)
        end
    end

    -- Update subtitle timer
    if self.subtitle_timer > 0 then
        self.subtitle_timer = self.subtitle_timer - dt
        if self.subtitle_timer <= 0 then
            self.current_subtitle = nil
        end
    end
end

-- Draw messages
function Messages:draw()
    local screen_height = love.graphics.getHeight()

    -- Position at bottom of screen
    local base_y = screen_height - self.padding - (self.max_messages * self.line_height)

    -- Draw background for visible messages
    local visible_count = math.min(#self.messages, self.max_messages)
    if visible_count > 0 then
        love.graphics.setColor(0, 0, 0, self.background_alpha * 0.5)
        love.graphics.rectangle("fill",
            self.x - self.padding,
            base_y - self.padding,
            self.width + self.padding * 2,
            visible_count * self.line_height + self.padding * 2
        )
    end

    -- Draw messages (newest at bottom)
    local y = base_y + (self.max_messages - visible_count) * self.line_height

    for i = visible_count, 1, -1 do
        local msg = self.messages[i]

        if msg.alpha > 0 then
            love.graphics.setColor(msg.color[1], msg.color[2], msg.color[3], msg.alpha)
            love.graphics.print(msg.text, self.x, y)
        end

        y = y + self.line_height
    end

    -- Draw subtitle (centered at bottom)
    if self.current_subtitle then
        local subtitle_y = screen_height - 60
        local font = love.graphics.getFont()
        local text_width = font:getWidth(self.current_subtitle)
        local screen_width = love.graphics.getWidth()

        -- Background
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill",
            (screen_width - text_width) / 2 - 10,
            subtitle_y - 5,
            text_width + 20,
            self.line_height + 10
        )

        -- Border
        love.graphics.setColor(1, 0.9, 0.2, 0.8)
        love.graphics.rectangle("line",
            (screen_width - text_width) / 2 - 10,
            subtitle_y - 5,
            text_width + 20,
            self.line_height + 10
        )

        -- Text
        local alpha = 1.0
        if self.subtitle_timer < 0.5 then
            alpha = self.subtitle_timer / 0.5  -- Fade out
        end
        love.graphics.setColor(1, 0.9, 0.2, alpha)
        love.graphics.print(self.current_subtitle, (screen_width - text_width) / 2, subtitle_y)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Clear all messages
function Messages:clear()
    self.messages = {}
    self.current_subtitle = nil
    self.subtitle_timer = 0
end

-- Get message history
function Messages:get_history()
    return self.messages
end

-- Set display position
function Messages:set_position(x, y)
    self.x = x
    self.y = y
end

-- Set display width
function Messages:set_width(width)
    self.width = width
end

-- Set font
function Messages:set_font(font)
    self.font = font
end

-- Check if has recent messages
function Messages:has_recent_messages()
    if #self.messages == 0 then return false end

    local current_time = love.timer.getTime()
    local newest = self.messages[1]

    return (current_time - newest.time) < self.fade_duration
end

return Messages
