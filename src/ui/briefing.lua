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

    -- Map reveal animation state
    self.map_reveal = {
        enabled = false,
        grid = nil,              -- Reference to map grid for reveal
        reveal_points = {},      -- Points to reveal in sequence
        current_point = 0,
        reveal_timer = 0,
        reveal_interval = 0.5,   -- Time between reveal points
        reveal_radius = 8,       -- Cells to reveal per point
        cells_revealed = {},     -- Track which cells are revealed
        animation_complete = false
    }

    -- Mini-map display state (for showing map during briefing)
    self.minimap = {
        enabled = false,
        x = 0,
        y = 0,
        width = 200,
        height = 150,
        scale = 1,
        shroud_alpha = 1.0       -- Full shroud initially
    }

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

-- Setup map reveal animation for a mission
-- reveal_points: list of {x, y} cell coordinates to reveal in sequence
-- grid: reference to the map grid
function Briefing:setup_map_reveal(grid, reveal_points, minimap_rect)
    self.map_reveal.enabled = true
    self.map_reveal.grid = grid
    self.map_reveal.reveal_points = reveal_points or {}
    self.map_reveal.current_point = 0
    self.map_reveal.reveal_timer = 0
    self.map_reveal.cells_revealed = {}
    self.map_reveal.animation_complete = false

    -- Setup minimap display area
    if minimap_rect then
        self.minimap.enabled = true
        self.minimap.x = minimap_rect.x or 0
        self.minimap.y = minimap_rect.y or 0
        self.minimap.width = minimap_rect.width or 200
        self.minimap.height = minimap_rect.height or 150
    end

    -- Calculate scale to fit grid in minimap
    if grid then
        local grid_w = grid.width or 64
        local grid_h = grid.height or 64
        self.minimap.scale = math.min(
            self.minimap.width / grid_w,
            self.minimap.height / grid_h
        )
    end
end

-- Add reveal points from scenario waypoints
function Briefing:add_reveal_waypoints(waypoints)
    if not waypoints then return end

    for _, wp in pairs(waypoints) do
        if wp.x and wp.y then
            table.insert(self.map_reveal.reveal_points, {
                x = wp.x,
                y = wp.y,
                name = wp.name or ""
            })
        end
    end
end

-- Reveal cells around a point (circular reveal)
function Briefing:reveal_around_point(center_x, center_y, radius)
    local revealed = {}
    for dy = -radius, radius do
        for dx = -radius, radius do
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= radius then
                local cx, cy = center_x + dx, center_y + dy
                local key = cx .. "," .. cy
                if not self.map_reveal.cells_revealed[key] then
                    self.map_reveal.cells_revealed[key] = true
                    table.insert(revealed, {x = cx, y = cy})
                end
            end
        end
    end
    return revealed
end

-- Update map reveal animation
function Briefing:update_map_reveal(dt)
    if not self.map_reveal.enabled or self.map_reveal.animation_complete then
        return
    end

    self.map_reveal.reveal_timer = self.map_reveal.reveal_timer + dt

    if self.map_reveal.reveal_timer >= self.map_reveal.reveal_interval then
        self.map_reveal.reveal_timer = 0
        self.map_reveal.current_point = self.map_reveal.current_point + 1

        if self.map_reveal.current_point <= #self.map_reveal.reveal_points then
            local point = self.map_reveal.reveal_points[self.map_reveal.current_point]
            self:reveal_around_point(point.x, point.y, self.map_reveal.reveal_radius)

            -- Play reveal sound
            Events.emit("PLAY_SOUND", "radar_on", 0, 0)
        else
            self.map_reveal.animation_complete = true
        end
    end

    -- Gradually reduce shroud alpha as more is revealed
    local total_points = #self.map_reveal.reveal_points
    if total_points > 0 then
        local progress = self.map_reveal.current_point / total_points
        self.minimap.shroud_alpha = math.max(0, 1 - progress)
    end
end

-- Draw minimap with reveal animation
function Briefing:draw_minimap()
    if not self.minimap.enabled or not self.map_reveal.grid then
        return
    end

    local mx = self.minimap.x
    local my = self.minimap.y
    local mw = self.minimap.width
    local mh = self.minimap.height
    local scale = self.minimap.scale

    -- Draw minimap background
    love.graphics.setColor(0.1, 0.15, 0.1, 0.9)
    love.graphics.rectangle("fill", mx - 2, my - 2, mw + 4, mh + 4)

    -- Border
    love.graphics.setColor(0.2, 0.6, 0.2, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", mx - 2, my - 2, mw + 4, mh + 4)

    -- Draw terrain (simplified)
    local grid = self.map_reveal.grid
    for cy = 0, (grid.height or 64) - 1 do
        for cx = 0, (grid.width or 64) - 1 do
            local px = mx + cx * scale
            local py = my + cy * scale

            -- Check if cell is revealed
            local key = cx .. "," .. cy
            local is_revealed = self.map_reveal.cells_revealed[key]

            if is_revealed then
                -- Get cell data
                local cell = grid:get_cell(cx, cy)
                if cell then
                    -- Color based on terrain type
                    if cell.terrain == "water" then
                        love.graphics.setColor(0.1, 0.2, 0.4, 1)
                    elseif cell.terrain == "rock" then
                        love.graphics.setColor(0.3, 0.25, 0.2, 1)
                    elseif cell:has_tiberium() then
                        love.graphics.setColor(0.2, 0.8, 0.2, 1)
                    else
                        love.graphics.setColor(0.35, 0.3, 0.25, 1)
                    end
                else
                    love.graphics.setColor(0.3, 0.3, 0.2, 1)
                end
                love.graphics.rectangle("fill", px, py, scale, scale)
            else
                -- Shrouded
                love.graphics.setColor(0, 0, 0, self.minimap.shroud_alpha)
                love.graphics.rectangle("fill", px, py, scale, scale)
            end
        end
    end

    -- Draw reveal points that have been reached
    for i = 1, self.map_reveal.current_point do
        local point = self.map_reveal.reveal_points[i]
        if point then
            local px = mx + point.x * scale
            local py = my + point.y * scale

            -- Pulsing marker
            local pulse = math.sin(love.timer.getTime() * 4) * 0.3 + 0.7
            love.graphics.setColor(1, 0.8, 0.2, pulse)
            love.graphics.circle("fill", px, py, 4)

            -- Point name if present
            if point.name and point.name ~= "" then
                love.graphics.setColor(1, 1, 1, 0.8)
                love.graphics.print(point.name, px + 6, py - 6)
            end
        end
    end

    -- Draw current reveal animation (expanding circle)
    if self.map_reveal.current_point > 0 and not self.map_reveal.animation_complete then
        local point = self.map_reveal.reveal_points[self.map_reveal.current_point]
        if point then
            local px = mx + point.x * scale
            local py = my + point.y * scale
            local t = self.map_reveal.reveal_timer / self.map_reveal.reveal_interval
            local radius = t * self.map_reveal.reveal_radius * scale

            love.graphics.setColor(0.3, 1, 0.3, 0.3 * (1 - t))
            love.graphics.circle("line", px, py, radius)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
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

    -- Update map reveal animation
    self:update_map_reveal(dt)
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

    -- Draw minimap with reveal animation (positioned in top-right of panel)
    if self.minimap.enabled then
        -- Position minimap in top-right corner of the panel
        self.minimap.x = panel_x + panel_w - self.minimap.width - 30
        self.minimap.y = panel_y + 60
        self:draw_minimap()
    end

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
