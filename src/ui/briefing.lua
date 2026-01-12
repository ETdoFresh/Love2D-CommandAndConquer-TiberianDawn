--[[
    Briefing - Mission briefing screen
    Displays mission objectives, EVA voice text, and plays intro videos
    Reference: Original C&C mission briefing screens
]]

local Events = require("src.core.events")

local Briefing = {}
Briefing.__index = Briefing

-- Briefing text data for missions (from original game)
-- These are the canonical briefing texts
Briefing.TEXTS = {
    -- GDI Campaign
    scg01ea = {
        title = "GDI Mission 1",
        location = "Estonia",
        objectives = {
            "Locate and rescue the Mobius scientists",
            "Move them to the extraction point"
        },
        text = "A Nod strike team has captured Dr. Mobius and his research staff. Your mission is to locate the scientists being held at a nearby Nod camp. Extract them to the evacuation point."
    },
    scg02ea = {
        title = "GDI Mission 2",
        location = "Latvia",
        objectives = {
            "Destroy all Nod forces in the area",
            "Establish a GDI base"
        },
        text = "Nod forces are attempting to establish a foothold in Latvia. Destroy all enemy forces and secure the region for GDI operations."
    },
    scg03ea = {
        title = "GDI Mission 3",
        location = "Lithuania",
        objectives = {
            "Destroy the Nod base",
            "Protect the village"
        },
        text = "A Nod base threatens a nearby village. Your objective is to destroy the enemy base while minimizing civilian casualties."
    },

    -- Nod Campaign
    scb01ea = {
        title = "Nod Mission 1",
        location = "Libya",
        objectives = {
            "Destroy the GDI base",
            "Establish Nod presence"
        },
        text = "The Brotherhood of Nod requires you to eliminate a small GDI outpost in Libya. Show them the power of Kane."
    },
    scb02ea = {
        title = "Nod Mission 2",
        location = "Egypt",
        objectives = {
            "Capture the GDI Communications Center",
            "Eliminate all GDI forces"
        },
        text = "GDI forces have established a communications center in Egypt. Capture it to disrupt their operations, then eliminate all remaining forces."
    },

    -- Default briefing for unmapped missions
    default = {
        title = "Mission Briefing",
        location = "Unknown",
        objectives = {
            "Complete primary objectives",
            "Eliminate enemy forces"
        },
        text = "Mission briefing data unavailable. Proceed with standard combat protocols."
    }
}

function Briefing.new()
    local self = setmetatable({}, Briefing)

    -- Current briefing state
    self.active = false
    self.mission_id = nil
    self.briefing_data = nil

    -- Display state
    self.text_progress = 0        -- Characters revealed (typewriter effect)
    self.text_speed = 30          -- Characters per second
    self.text_complete = false
    self.objective_reveal = 0     -- Objectives revealed
    self.objective_timer = 0

    -- Timing
    self.start_time = 0
    self.min_duration = 2.0       -- Minimum time before skip allowed

    -- UI Layout
    self.margin = 40
    self.panel_alpha = 0.85

    -- Callbacks
    self.on_complete = nil
    self.on_skip = nil

    -- EVA voice playback tracking
    self.eva_playing = false

    -- Fonts (will be set in init)
    self.title_font = nil
    self.text_font = nil
    self.objective_font = nil

    return self
end

function Briefing:init()
    -- Create fonts if love.graphics available
    if love and love.graphics then
        self.title_font = love.graphics.newFont(24)
        self.text_font = love.graphics.newFont(14)
        self.objective_font = love.graphics.newFont(16)
    end
end

-- Show briefing for a mission
function Briefing:show(mission_id, scenario_data)
    self.active = true
    self.mission_id = mission_id
    self.start_time = love.timer.getTime()

    -- Get briefing data from our table or scenario
    local briefing_key = mission_id:lower()
    self.briefing_data = Briefing.TEXTS[briefing_key] or Briefing.TEXTS.default

    -- Override with scenario data if provided
    if scenario_data then
        if scenario_data.name then
            self.briefing_data.title = scenario_data.name
        end
        if scenario_data.brief then
            self.briefing_data.text = scenario_data.brief
        end
        if scenario_data.objectives then
            self.briefing_data.objectives = scenario_data.objectives
        end
    end

    -- Reset display state
    self.text_progress = 0
    self.text_complete = false
    self.objective_reveal = 0
    self.objective_timer = 0

    -- Play EVA briefing voice
    Events.emit("EVA_SPEECH", "mission briefing", nil)
    self.eva_playing = true
end

-- Hide briefing
function Briefing:hide()
    self.active = false
    self.mission_id = nil
    self.briefing_data = nil
    self.eva_playing = false
end

-- Skip to end of text
function Briefing:skip_text()
    if self.briefing_data then
        self.text_progress = #self.briefing_data.text
        self.text_complete = true
        self.objective_reveal = #(self.briefing_data.objectives or {})
    end
end

-- Complete briefing and start mission
function Briefing:complete()
    if self.on_complete then
        self.on_complete(self.mission_id)
    end
    self:hide()
end

function Briefing:update(dt)
    if not self.active or not self.briefing_data then
        return
    end

    -- Typewriter effect for main text
    if not self.text_complete then
        self.text_progress = self.text_progress + self.text_speed * dt
        if self.text_progress >= #self.briefing_data.text then
            self.text_progress = #self.briefing_data.text
            self.text_complete = true
        end
    end

    -- Reveal objectives one by one after text is complete
    if self.text_complete and self.briefing_data.objectives then
        self.objective_timer = self.objective_timer + dt
        local objectives_count = #self.briefing_data.objectives
        local reveal_interval = 0.5  -- Time between objectives

        if self.objective_reveal < objectives_count then
            if self.objective_timer >= reveal_interval then
                self.objective_reveal = self.objective_reveal + 1
                self.objective_timer = 0
                -- Play objective reveal sound
                Events.emit("PLAY_SOUND", "button", 0, 0)
            end
        end
    end
end

function Briefing:draw()
    if not self.active or not self.briefing_data then
        return
    end

    local w, h = love.graphics.getDimensions()
    local margin = self.margin

    -- Draw darkened background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw main briefing panel
    local panel_x = margin
    local panel_y = margin
    local panel_w = w - margin * 2
    local panel_h = h - margin * 2

    -- Panel background with border
    love.graphics.setColor(0.1, 0.15, 0.1, self.panel_alpha)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h)

    -- Green military-style border
    love.graphics.setColor(0.2, 0.6, 0.2, 1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h)
    love.graphics.setLineWidth(1)

    -- Draw corner decorations
    local corner_size = 20
    love.graphics.setColor(0.3, 0.8, 0.3, 1)
    -- Top-left
    love.graphics.line(panel_x, panel_y + corner_size, panel_x, panel_y, panel_x + corner_size, panel_y)
    -- Top-right
    love.graphics.line(panel_x + panel_w - corner_size, panel_y, panel_x + panel_w, panel_y, panel_x + panel_w, panel_y + corner_size)
    -- Bottom-left
    love.graphics.line(panel_x, panel_y + panel_h - corner_size, panel_x, panel_y + panel_h, panel_x + corner_size, panel_y + panel_h)
    -- Bottom-right
    love.graphics.line(panel_x + panel_w - corner_size, panel_y + panel_h, panel_x + panel_w, panel_y + panel_h, panel_x + panel_w, panel_y + panel_h - corner_size)

    -- Content area
    local content_x = panel_x + 30
    local content_y = panel_y + 30
    local content_w = panel_w - 60

    -- Title
    local title_font = self.title_font or love.graphics.getFont()
    love.graphics.setFont(title_font)
    love.graphics.setColor(0.3, 1, 0.3, 1)
    love.graphics.print(self.briefing_data.title or "MISSION BRIEFING", content_x, content_y)
    content_y = content_y + title_font:getHeight() + 10

    -- Location
    if self.briefing_data.location then
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local text_font = self.text_font or love.graphics.getFont()
        love.graphics.setFont(text_font)
        love.graphics.print("Location: " .. self.briefing_data.location, content_x, content_y)
        content_y = content_y + text_font:getHeight() + 20
    end

    -- Horizontal divider
    love.graphics.setColor(0.2, 0.6, 0.2, 0.5)
    love.graphics.line(content_x, content_y, content_x + content_w, content_y)
    content_y = content_y + 15

    -- Main briefing text (with typewriter effect)
    local text_font = self.text_font or love.graphics.getFont()
    love.graphics.setFont(text_font)
    love.graphics.setColor(0.9, 0.9, 0.9, 1)

    local visible_text = string.sub(self.briefing_data.text or "", 1, math.floor(self.text_progress))
    local wrapped_text, lines = self:wrap_text(visible_text, text_font, content_w)

    for i, line in ipairs(lines) do
        love.graphics.print(line, content_x, content_y + (i - 1) * text_font:getHeight())
    end

    -- Blinking cursor at end of text
    if not self.text_complete then
        local cursor_x = content_x + text_font:getWidth(lines[#lines] or "")
        local cursor_y = content_y + (#lines - 1) * text_font:getHeight()
        if math.floor(love.timer.getTime() * 3) % 2 == 0 then
            love.graphics.setColor(0.3, 1, 0.3, 1)
            love.graphics.rectangle("fill", cursor_x, cursor_y, 8, text_font:getHeight())
        end
    end

    content_y = content_y + #lines * text_font:getHeight() + 30

    -- Objectives section
    if self.briefing_data.objectives and self.objective_reveal > 0 then
        love.graphics.setColor(0.2, 0.6, 0.2, 0.5)
        love.graphics.line(content_x, content_y, content_x + content_w, content_y)
        content_y = content_y + 15

        love.graphics.setColor(0.3, 1, 0.3, 1)
        local obj_font = self.objective_font or love.graphics.getFont()
        love.graphics.setFont(obj_font)
        love.graphics.print("OBJECTIVES:", content_x, content_y)
        content_y = content_y + obj_font:getHeight() + 10

        love.graphics.setColor(1, 0.9, 0.3, 1)  -- Yellow for objectives
        for i = 1, math.min(self.objective_reveal, #self.briefing_data.objectives) do
            local obj = self.briefing_data.objectives[i]
            love.graphics.print("• " .. obj, content_x + 20, content_y)
            content_y = content_y + obj_font:getHeight() + 5
        end
    end

    -- Instructions at bottom
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    local small_font = self.text_font or love.graphics.getFont()
    love.graphics.setFont(small_font)

    local elapsed = love.timer.getTime() - self.start_time
    local can_skip = elapsed >= self.min_duration

    local instructions
    if not self.text_complete then
        instructions = "Press SPACE to skip text..."
    elseif can_skip then
        instructions = "Press ENTER to begin mission"
    else
        instructions = "Please wait..."
    end

    local inst_width = small_font:getWidth(instructions)
    love.graphics.print(instructions, panel_x + panel_w / 2 - inst_width / 2, panel_y + panel_h - 40)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Word wrap text to fit width
function Briefing:wrap_text(text, font, max_width)
    local lines = {}
    local current_line = ""

    for word in text:gmatch("%S+") do
        local test_line = current_line == "" and word or (current_line .. " " .. word)
        if font:getWidth(test_line) <= max_width then
            current_line = test_line
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = word
        end
    end

    if current_line ~= "" then
        table.insert(lines, current_line)
    end

    if #lines == 0 then
        lines = {""}
    end

    return table.concat(lines, "\n"), lines
end

-- Handle key press
function Briefing:keypressed(key)
    if not self.active then
        return false
    end

    if key == "space" then
        if not self.text_complete then
            self:skip_text()
            return true
        end
    elseif key == "return" or key == "kpenter" then
        local elapsed = love.timer.getTime() - self.start_time
        if self.text_complete and elapsed >= self.min_duration then
            self:complete()
            return true
        end
    elseif key == "escape" then
        -- ESC skips entire briefing (with confirmation in real game)
        self:skip_text()
        self:complete()
        return true
    end

    return true  -- Consume all keys while briefing active
end

-- Check if briefing is active
function Briefing:is_active()
    return self.active
end

return Briefing
