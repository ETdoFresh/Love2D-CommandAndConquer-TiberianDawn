--[[
    Main Menu - Full featured main menu system
    Handles campaign selection, multiplayer, options, etc.
]]

local Events = require("src.core.events")

local MainMenu = {}
MainMenu.__index = MainMenu

-- Menu states
MainMenu.STATE = {
    MAIN = "main",
    CAMPAIGN = "campaign",
    SKIRMISH = "skirmish",
    MULTIPLAYER = "multiplayer",
    OPTIONS = "options",
    CREDITS = "credits",
    EDITOR = "editor"
}

function MainMenu.new()
    local self = setmetatable({}, MainMenu)

    self.state = MainMenu.STATE.MAIN
    self.previous_state = nil

    -- Menu selection
    self.selected_index = 1

    -- Animation
    self.fade_alpha = 1
    self.fade_direction = -1  -- -1 = fading in

    -- Globe animation state
    self.globe_rotation = 0
    self.globe_pulse = 0
    self.stars = {}
    self:generate_stars(100)

    -- Tiberium growth effect
    self.tiberium_particles = {}
    self:generate_tiberium_particles(30)

    -- Main menu options
    self.main_options = {
        {label = "GDI CAMPAIGN", action = "gdi_campaign"},
        {label = "NOD CAMPAIGN", action = "nod_campaign"},
        {label = "SKIRMISH", action = "skirmish"},
        {label = "MULTIPLAYER", action = "multiplayer"},
        {label = "MAP EDITOR", action = "editor"},
        {label = "OPTIONS", action = "options"},
        {label = "CREDITS", action = "credits"},
        {label = "EXIT", action = "exit"}
    }

    -- Campaign mission lists
    self.gdi_missions = {
        {name = "X16-Y42", file = "gdi01", briefing = "Establish base and eliminate all Nod forces"},
        {name = "Liberation of Egypt", file = "gdi02", briefing = "Free the region from Nod control"},
        {name = "Air Supremacy", file = "gdi03", briefing = "Destroy Nod airfield"},
        -- Add more missions...
    }

    self.nod_missions = {
        {name = "Silencing Nikoomba", file = "nod01", briefing = "Eliminate the traitor Nikoomba"},
        {name = "Liberation of Seth", file = "nod02", briefing = "Free our commander"},
        {name = "Consolidation", file = "nod03", briefing = "Secure the region"},
        -- Add more missions...
    }

    -- Skirmish settings
    self.skirmish_settings = {
        map = "scg01ea",
        starting_credits = 5000,
        ai_difficulty = 2,  -- 1=Easy, 2=Normal, 3=Hard
        house = 1,  -- GDI
        opponent_count = 1
    }

    -- Options
    self.options = {
        {label = "Master Volume", type = "slider", value = 100, min = 0, max = 100, key = "master_volume"},
        {label = "Music Volume", type = "slider", value = 70, min = 0, max = 100, key = "music_volume"},
        {label = "SFX Volume", type = "slider", value = 100, min = 0, max = 100, key = "sfx_volume"},
        {label = "Game Speed", type = "slider", value = 3, min = 1, max = 6, key = "game_speed"},
        {label = "Fog of War", type = "toggle", value = true, key = "fog_of_war"},
        {label = "Shroud", type = "toggle", value = true, key = "shroud"},
        {label = "Screen Shake", type = "toggle", value = true, key = "screen_shake"}
    }

    -- Callbacks
    self.on_start_game = nil

    return self
end

-- Generate background stars
function MainMenu:generate_stars(count)
    local width, height = love.graphics.getDimensions()
    for _ = 1, count do
        table.insert(self.stars, {
            x = math.random(0, width),
            y = math.random(0, height),
            size = math.random() * 2 + 0.5,
            brightness = math.random() * 0.5 + 0.3,
            twinkle_speed = math.random() * 2 + 1
        })
    end
end

-- Generate tiberium particles around globe
function MainMenu:generate_tiberium_particles(count)
    for _ = 1, count do
        table.insert(self.tiberium_particles, {
            angle = math.random() * math.pi * 2,
            radius = math.random(80, 150),
            size = math.random(2, 6),
            speed = (math.random() - 0.5) * 0.3,
            pulse_offset = math.random() * math.pi * 2
        })
    end
end

-- Update menu
function MainMenu:update(dt)
    -- Update fade animation
    if self.fade_direction ~= 0 then
        self.fade_alpha = self.fade_alpha + self.fade_direction * dt * 2
        if self.fade_alpha <= 0 then
            self.fade_alpha = 0
            self.fade_direction = 0
        elseif self.fade_alpha >= 1 then
            self.fade_alpha = 1
            self.fade_direction = 0
        end
    end

    -- Update globe rotation (slow spin)
    self.globe_rotation = self.globe_rotation + dt * 0.1
    self.globe_pulse = self.globe_pulse + dt * 1.5

    -- Update tiberium particles
    for _, p in ipairs(self.tiberium_particles) do
        p.angle = p.angle + p.speed * dt
    end
end

-- Handle key press
function MainMenu:keypressed(key)
    if key == "up" then
        self:navigate(-1)
    elseif key == "down" then
        self:navigate(1)
    elseif key == "return" or key == "space" then
        self:select()
    elseif key == "escape" then
        self:back()
    elseif key == "left" then
        self:adjust(-1)
    elseif key == "right" then
        self:adjust(1)
    end
end

-- Navigate menu
function MainMenu:navigate(direction)
    local options = self:get_current_options()
    self.selected_index = self.selected_index + direction

    if self.selected_index < 1 then
        self.selected_index = #options
    elseif self.selected_index > #options then
        self.selected_index = 1
    end

    Events.emit("PLAY_SOUND", "button1")
end

-- Select current option
function MainMenu:select()
    local options = self:get_current_options()
    local option = options[self.selected_index]

    if not option then return end

    Events.emit("PLAY_SOUND", "button2")

    if self.state == MainMenu.STATE.MAIN then
        self:handle_main_selection(option.action)

    elseif self.state == MainMenu.STATE.CAMPAIGN then
        -- Start selected mission
        if self.on_start_game then
            self.on_start_game("campaign", option.file)
        end

    elseif self.state == MainMenu.STATE.SKIRMISH then
        -- Start skirmish
        if self.on_start_game then
            self.on_start_game("skirmish", self.skirmish_settings)
        end

    elseif self.state == MainMenu.STATE.OPTIONS then
        -- Toggle option if toggle type
        if option.type == "toggle" then
            option.value = not option.value
            Events.emit("OPTION_CHANGED", option.key, option.value)
        end
    end
end

-- Handle main menu selection
function MainMenu:handle_main_selection(action)
    if action == "gdi_campaign" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.CAMPAIGN
        self.campaign_side = "gdi"
        self.selected_index = 1

    elseif action == "nod_campaign" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.CAMPAIGN
        self.campaign_side = "nod"
        self.selected_index = 1

    elseif action == "skirmish" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.SKIRMISH
        self.selected_index = 1

    elseif action == "multiplayer" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.MULTIPLAYER
        self.selected_index = 1

    elseif action == "options" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.OPTIONS
        self.selected_index = 1

    elseif action == "credits" then
        self.previous_state = self.state
        self.state = MainMenu.STATE.CREDITS
        self.selected_index = 1

    elseif action == "editor" then
        -- Launch the map editor
        if self.on_start_game then
            self.on_start_game("editor", nil)
        end

    elseif action == "exit" then
        love.event.quit()
    end
end

-- Go back to previous menu
function MainMenu:back()
    if self.state ~= MainMenu.STATE.MAIN then
        self.state = self.previous_state or MainMenu.STATE.MAIN
        self.selected_index = 1
        Events.emit("PLAY_SOUND", "button1")
    end
end

-- Adjust slider/option value
function MainMenu:adjust(direction)
    if self.state == MainMenu.STATE.OPTIONS then
        local option = self.options[self.selected_index]
        if option and option.type == "slider" then
            option.value = math.max(option.min, math.min(option.max, option.value + direction))
            Events.emit("OPTION_CHANGED", option.key, option.value)
        end
    elseif self.state == MainMenu.STATE.SKIRMISH then
        -- Adjust skirmish settings
        -- (Implementation would go here)
    end
end

-- Get current menu options
function MainMenu:get_current_options()
    if self.state == MainMenu.STATE.MAIN then
        return self.main_options
    elseif self.state == MainMenu.STATE.CAMPAIGN then
        return self.campaign_side == "gdi" and self.gdi_missions or self.nod_missions
    elseif self.state == MainMenu.STATE.OPTIONS then
        return self.options
    elseif self.state == MainMenu.STATE.SKIRMISH then
        return {{label = "START GAME", action = "start"}}  -- Simplified
    end
    return {}
end

-- Draw menu
function MainMenu:draw()
    local width, height = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(0.02, 0.02, 0.06, 1)
    love.graphics.rectangle("fill", 0, 0, width, height)

    -- Draw animated background
    self:draw_animated_background(width, height)

    -- Title
    self:draw_title(width)

    -- Menu content based on state
    if self.state == MainMenu.STATE.MAIN then
        self:draw_main_menu(width, height)
    elseif self.state == MainMenu.STATE.CAMPAIGN then
        self:draw_campaign_menu(width, height)
    elseif self.state == MainMenu.STATE.OPTIONS then
        self:draw_options_menu(width, height)
    elseif self.state == MainMenu.STATE.SKIRMISH then
        self:draw_skirmish_menu(width, height)
    elseif self.state == MainMenu.STATE.CREDITS then
        self:draw_credits(width, height)
    end

    -- Fade overlay
    if self.fade_alpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, width, height)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw animated background with globe and stars
function MainMenu:draw_animated_background(width, height)
    local time = love.timer.getTime()

    -- Draw twinkling stars
    for _, star in ipairs(self.stars) do
        local twinkle = 0.5 + 0.5 * math.sin(time * star.twinkle_speed + star.x)
        local brightness = star.brightness * twinkle
        love.graphics.setColor(brightness, brightness, brightness * 1.1, 1)
        love.graphics.circle("fill", star.x, star.y, star.size)
    end

    -- Globe position (center-right of screen)
    local globe_x = width * 0.7
    local globe_y = height * 0.45
    local globe_radius = math.min(width, height) * 0.25

    -- Draw globe glow
    local glow_pulse = 0.3 + 0.1 * math.sin(self.globe_pulse)
    for i = 5, 1, -1 do
        local glow_r = globe_radius + i * 15
        local alpha = glow_pulse * (1 - i / 6)
        love.graphics.setColor(0.1, 0.4, 0.2, alpha)
        love.graphics.circle("fill", globe_x, globe_y, glow_r)
    end

    -- Draw globe base (dark blue for oceans)
    love.graphics.setColor(0.05, 0.1, 0.2, 1)
    love.graphics.circle("fill", globe_x, globe_y, globe_radius)

    -- Draw continents (simplified shapes rotating)
    love.graphics.setColor(0.15, 0.3, 0.15, 1)
    self:draw_rotating_continent(globe_x, globe_y, globe_radius, self.globe_rotation, 0)
    self:draw_rotating_continent(globe_x, globe_y, globe_radius, self.globe_rotation, math.pi)
    self:draw_rotating_continent(globe_x, globe_y, globe_radius, self.globe_rotation, math.pi * 0.5)

    -- Draw tiberium spread on globe
    love.graphics.setColor(0.2, 0.8, 0.3, 0.6)
    for _, p in ipairs(self.tiberium_particles) do
        local px = globe_x + math.cos(p.angle + self.globe_rotation) * p.radius * 0.6
        local py = globe_y + math.sin(p.angle + self.globe_rotation) * p.radius * 0.4
        -- Only draw if on visible side of globe
        if math.cos(p.angle + self.globe_rotation) > -0.3 then
            local depth = (math.cos(p.angle + self.globe_rotation) + 0.3) / 1.3
            local pulse = 0.7 + 0.3 * math.sin(time * 2 + p.pulse_offset)
            love.graphics.setColor(0.2 * depth, 0.8 * depth * pulse, 0.3 * depth, 0.7 * depth)
            love.graphics.circle("fill", px, py, p.size * depth)
        end
    end

    -- Draw globe highlight (atmosphere)
    love.graphics.setColor(0.3, 0.5, 0.8, 0.15)
    love.graphics.arc("fill", globe_x - globe_radius * 0.3, globe_y - globe_radius * 0.2,
                      globe_radius, -math.pi/3, math.pi/3)

    -- Draw globe rim
    love.graphics.setColor(0.2, 0.4, 0.3, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", globe_x, globe_y, globe_radius)
    love.graphics.setLineWidth(1)

    -- Draw floating tiberium crystals around the globe
    love.graphics.setColor(0.3, 0.9, 0.4, 0.8)
    for i = 1, 8 do
        local angle = (i / 8) * math.pi * 2 + self.globe_rotation * 0.5
        local orbit_radius = globe_radius + 30 + math.sin(time + i) * 10
        local cx = globe_x + math.cos(angle) * orbit_radius
        local cy = globe_y + math.sin(angle) * orbit_radius * 0.3  -- Elliptical orbit

        -- Crystal shape (diamond)
        local crystal_size = 4 + math.sin(time * 2 + i) * 2
        love.graphics.polygon("fill",
            cx, cy - crystal_size,
            cx + crystal_size * 0.6, cy,
            cx, cy + crystal_size,
            cx - crystal_size * 0.6, cy
        )
    end

    -- Draw subtle grid lines on globe (latitude/longitude)
    love.graphics.setColor(0.1, 0.2, 0.15, 0.3)
    for i = 1, 5 do
        local lat_y = globe_y + (i - 3) * globe_radius * 0.3
        local lat_width = math.sqrt(math.max(0, globe_radius^2 - (lat_y - globe_y)^2))
        if lat_width > 0 then
            love.graphics.ellipse("line", globe_x, lat_y, lat_width, lat_width * 0.1)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a simplified rotating continent shape
function MainMenu:draw_rotating_continent(cx, cy, radius, rotation, offset)
    local angle = rotation + offset
    local visible = math.cos(angle)

    if visible > -0.5 then
        local depth = (visible + 0.5) / 1.5
        local x = cx + math.sin(angle) * radius * 0.6
        local y = cy

        -- Draw continent as ellipse
        love.graphics.setColor(0.2 * depth, 0.35 * depth, 0.2 * depth, depth)
        love.graphics.ellipse("fill", x, y, radius * 0.3 * depth, radius * 0.4)
    end
end

-- Draw title
function MainMenu:draw_title(width)
    local time = love.timer.getTime()

    -- Title glow effect
    local glow = 0.8 + 0.2 * math.sin(time * 1.5)

    love.graphics.setColor(1 * glow, 0.8 * glow, 0, 1)
    love.graphics.printf("COMMAND & CONQUER", 0, 50, width, "center")

    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.printf("TIBERIAN DAWN", 0, 80, width, "center")

    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.printf("Love2D Port", 0, 110, width, "center")
end

-- Draw main menu
function MainMenu:draw_main_menu(width, height)
    local start_y = 180
    local spacing = 35

    for i, option in ipairs(self.main_options) do
        local y = start_y + (i - 1) * spacing

        if i == self.selected_index then
            -- Selected item
            love.graphics.setColor(0.2, 0.2, 0.3, 1)
            love.graphics.rectangle("fill", width/2 - 120, y - 5, 240, 30)
            love.graphics.setColor(1, 0.8, 0, 1)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
        end

        love.graphics.printf(option.label, 0, y, width, "center")
    end

    -- Footer
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.printf("Arrow keys to navigate, Enter to select, ESC to back",
        0, height - 30, width, "center")
end

-- Draw campaign menu
function MainMenu:draw_campaign_menu(width, height)
    local missions = self.campaign_side == "gdi" and self.gdi_missions or self.nod_missions
    local title = self.campaign_side == "gdi" and "GDI CAMPAIGN" or "NOD CAMPAIGN"

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf(title, 0, 150, width, "center")

    local start_y = 200
    local spacing = 40

    for i, mission in ipairs(missions) do
        local y = start_y + (i - 1) * spacing

        if i == self.selected_index then
            love.graphics.setColor(0.2, 0.2, 0.3, 1)
            love.graphics.rectangle("fill", width/2 - 200, y - 5, 400, 35)
            love.graphics.setColor(1, 0.8, 0, 1)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
        end

        love.graphics.printf("Mission " .. i .. ": " .. mission.name, 0, y, width, "center")
    end

    -- Show briefing for selected mission
    if missions[self.selected_index] then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.printf(missions[self.selected_index].briefing,
            50, height - 80, width - 100, "center")
    end
end

-- Draw options menu
function MainMenu:draw_options_menu(width, height)
    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("OPTIONS", 0, 150, width, "center")

    local start_y = 200
    local spacing = 40

    for i, option in ipairs(self.options) do
        local y = start_y + (i - 1) * spacing

        if i == self.selected_index then
            love.graphics.setColor(1, 0.8, 0, 1)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
        end

        -- Label
        love.graphics.print(option.label, width/2 - 150, y)

        -- Value
        if option.type == "slider" then
            -- Draw slider
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.rectangle("fill", width/2 + 50, y + 5, 100, 10)

            local fill_width = (option.value - option.min) / (option.max - option.min) * 100
            love.graphics.setColor(1, 0.8, 0, 1)
            love.graphics.rectangle("fill", width/2 + 50, y + 5, fill_width, 10)

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(tostring(option.value), width/2 + 160, y)

        elseif option.type == "toggle" then
            local text = option.value and "ON" or "OFF"
            local color = option.value and {0, 1, 0, 1} or {1, 0, 0, 1}
            love.graphics.setColor(color)
            love.graphics.print(text, width/2 + 50, y)
        end
    end
end

-- Draw skirmish menu
function MainMenu:draw_skirmish_menu(width, height)
    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("SKIRMISH", 0, 150, width, "center")

    local y = 200
    love.graphics.setColor(0.7, 0.7, 0.7, 1)

    love.graphics.print("Map: " .. self.skirmish_settings.map, width/2 - 100, y)
    love.graphics.print("Credits: " .. self.skirmish_settings.starting_credits, width/2 - 100, y + 30)
    love.graphics.print("AI: " .. ({"Easy", "Normal", "Hard"})[self.skirmish_settings.ai_difficulty], width/2 - 100, y + 60)
    love.graphics.print("Side: " .. (self.skirmish_settings.house == 1 and "GDI" or "NOD"), width/2 - 100, y + 90)

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("Press ENTER to start", 0, height - 100, width, "center")
end

-- Draw credits
function MainMenu:draw_credits(width, height)
    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("CREDITS", 0, 150, width, "center")

    local credits = {
        "",
        "Original Game by Westwood Studios",
        "",
        "Love2D Port by Claude",
        "",
        "Command & Conquer is a trademark of EA",
        "",
        "This is a fan project for educational purposes",
        "",
        "Press ESC to return"
    }

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    for i, line in ipairs(credits) do
        love.graphics.printf(line, 0, 180 + i * 25, width, "center")
    end
end

-- Handle mouse click
function MainMenu:mousepressed(x, y, button)
    if button == 1 then
        -- Check if click is on a menu item
        local options = self:get_current_options()
        local width = love.graphics.getWidth()
        local start_y = self.state == MainMenu.STATE.MAIN and 180 or 200
        local spacing = self.state == MainMenu.STATE.MAIN and 35 or 40

        for i, _ in ipairs(options) do
            local item_y = start_y + (i - 1) * spacing
            if y >= item_y - 5 and y <= item_y + 30 and
               x >= width/2 - 150 and x <= width/2 + 150 then
                self.selected_index = i
                self:select()
                return
            end
        end
    end
end

return MainMenu
