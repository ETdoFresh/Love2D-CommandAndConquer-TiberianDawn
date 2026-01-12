--[[
    Options Menu - Full settings screen
    Handles graphics, audio, controls, and gameplay settings
    Reference: Original C&C options menu layout
]]

local Events = require("src.core.events")

local Options = {}
Options.__index = Options

-- Option categories
Options.CATEGORY = {
    GRAPHICS = 1,
    AUDIO = 2,
    CONTROLS = 3,
    GAMEPLAY = 4
}

-- Default keybindings (original C&C layout)
Options.DEFAULT_KEYBINDS = {
    -- Selection
    select_all = "a",
    select_next_unit = "n",
    select_prev_unit = "p",
    -- Control groups
    group_1 = "1",
    group_2 = "2",
    group_3 = "3",
    group_4 = "4",
    group_5 = "5",
    group_6 = "6",
    group_7 = "7",
    group_8 = "8",
    group_9 = "9",
    group_0 = "0",
    -- Commands
    stop = "s",
    guard = "g",
    scatter = "x",
    deploy = "d",
    -- Camera
    center_base = "h",
    follow_unit = "f",
    -- Building
    sell_mode = "z",
    repair_mode = "r",
    -- Special
    alliance = "tab",
    diplomacy = "f9",
    options_menu = "escape",
    -- Sidebar
    sidebar_up = "pageup",
    sidebar_down = "pagedown"
}

-- Keybind display names
Options.KEYBIND_LABELS = {
    select_all = "Select All Units",
    select_next_unit = "Select Next Unit",
    select_prev_unit = "Select Previous Unit",
    group_1 = "Control Group 1",
    group_2 = "Control Group 2",
    group_3 = "Control Group 3",
    group_4 = "Control Group 4",
    group_5 = "Control Group 5",
    group_6 = "Control Group 6",
    group_7 = "Control Group 7",
    group_8 = "Control Group 8",
    group_9 = "Control Group 9",
    group_0 = "Control Group 0",
    stop = "Stop",
    guard = "Guard Mode",
    scatter = "Scatter",
    deploy = "Deploy",
    center_base = "Center on Base",
    follow_unit = "Follow Unit",
    sell_mode = "Sell Mode",
    repair_mode = "Repair Mode",
    alliance = "Alliance Menu",
    diplomacy = "Diplomacy",
    options_menu = "Options Menu",
    sidebar_up = "Sidebar Up",
    sidebar_down = "Sidebar Down"
}

function Options.new()
    local self = setmetatable({}, Options)

    -- Current state
    self.active = false
    self.category = Options.CATEGORY.GRAPHICS
    self.selected_index = 1
    self.scroll_offset = 0
    self.max_visible = 10

    -- Rebinding state
    self.rebinding = false
    self.rebind_action = nil

    -- Settings (loaded from save or defaults)
    self.settings = {
        -- Graphics
        graphics_mode = "classic",  -- "classic" or "hd"
        resolution = "1280x720",
        fullscreen = false,
        vsync = true,
        show_health_bars = true,
        show_unit_shadows = true,
        screen_shake = true,

        -- Audio
        audio_mode = "classic",  -- "classic" or "remastered"
        master_volume = 100,
        music_volume = 70,
        sfx_volume = 100,
        speech_volume = 100,
        eva_enabled = true,

        -- Gameplay
        game_speed = 3,  -- 1-6 (Slowest to Fastest)
        fog_of_war = true,
        shroud = true,
        scroll_speed = 5,
        drag_select = "modern",  -- "classic" or "modern"

        -- Controls (keybinds)
        keybinds = {}
    }

    -- Copy default keybinds
    for action, key in pairs(Options.DEFAULT_KEYBINDS) do
        self.settings.keybinds[action] = key
    end

    -- UI layout
    self.margin = 40
    self.panel_alpha = 0.9

    -- Category labels
    self.category_labels = {
        [Options.CATEGORY.GRAPHICS] = "GRAPHICS",
        [Options.CATEGORY.AUDIO] = "AUDIO",
        [Options.CATEGORY.CONTROLS] = "CONTROLS",
        [Options.CATEGORY.GAMEPLAY] = "GAMEPLAY"
    }

    -- Callbacks
    self.on_close = nil
    self.on_settings_changed = nil

    return self
end

-- Get options for current category
function Options:get_category_options()
    if self.category == Options.CATEGORY.GRAPHICS then
        return {
            {label = "Graphics Mode", key = "graphics_mode", type = "choice", choices = {"classic", "hd"}, display = {"Classic (320x200)", "HD Remastered"}},
            {label = "Resolution", key = "resolution", type = "choice", choices = {"640x480", "800x600", "1024x768", "1280x720", "1920x1080"}, display = {"640x480", "800x600", "1024x768", "1280x720", "1920x1080"}},
            {label = "Fullscreen", key = "fullscreen", type = "toggle"},
            {label = "VSync", key = "vsync", type = "toggle"},
            {label = "Health Bars", key = "show_health_bars", type = "toggle"},
            {label = "Unit Shadows", key = "show_unit_shadows", type = "toggle"},
            {label = "Screen Shake", key = "screen_shake", type = "toggle"}
        }
    elseif self.category == Options.CATEGORY.AUDIO then
        return {
            {label = "Audio Mode", key = "audio_mode", type = "choice", choices = {"classic", "remastered"}, display = {"Classic", "Remastered"}},
            {label = "Master Volume", key = "master_volume", type = "slider", min = 0, max = 100},
            {label = "Music Volume", key = "music_volume", type = "slider", min = 0, max = 100},
            {label = "SFX Volume", key = "sfx_volume", type = "slider", min = 0, max = 100},
            {label = "Speech Volume", key = "speech_volume", type = "slider", min = 0, max = 100},
            {label = "EVA Voice", key = "eva_enabled", type = "toggle"}
        }
    elseif self.category == Options.CATEGORY.CONTROLS then
        -- Build keybind options
        local options = {}
        local actions_order = {
            "select_all", "select_next_unit", "select_prev_unit",
            "stop", "guard", "scatter", "deploy",
            "center_base", "follow_unit", "sell_mode", "repair_mode",
            "group_1", "group_2", "group_3", "group_4", "group_5",
            "group_6", "group_7", "group_8", "group_9", "group_0",
            "sidebar_up", "sidebar_down"
        }
        for _, action in ipairs(actions_order) do
            table.insert(options, {
                label = Options.KEYBIND_LABELS[action] or action,
                key = action,
                type = "keybind"
            })
        end
        table.insert(options, {label = "Reset to Defaults", type = "action", action = "reset_keybinds"})
        return options
    elseif self.category == Options.CATEGORY.GAMEPLAY then
        return {
            {label = "Game Speed", key = "game_speed", type = "slider", min = 1, max = 6, display = {"Slowest", "Slower", "Normal", "Faster", "Fastest", "Turbo"}},
            {label = "Fog of War", key = "fog_of_war", type = "toggle"},
            {label = "Shroud", key = "shroud", type = "toggle"},
            {label = "Scroll Speed", key = "scroll_speed", type = "slider", min = 1, max = 10},
            {label = "Drag Select", key = "drag_select", type = "choice", choices = {"classic", "modern"}, display = {"Classic", "Modern"}}
        }
    end
    return {}
end

-- Show options menu
function Options:show()
    self.active = true
    self.category = Options.CATEGORY.GRAPHICS
    self.selected_index = 1
    self.scroll_offset = 0
    self.rebinding = false
end

-- Hide options menu
function Options:hide()
    self.active = false
    self.rebinding = false
    if self.on_close then
        self.on_close()
    end
end

-- Apply settings changes
function Options:apply_settings()
    -- Emit events for systems to react
    Events.emit("SETTINGS_CHANGED", self.settings)

    -- Apply graphics mode
    if self.settings.graphics_mode == "hd" then
        Events.emit("GRAPHICS_MODE", "hd")
    else
        Events.emit("GRAPHICS_MODE", "classic")
    end

    -- Apply audio mode
    Events.emit("AUDIO_MODE", self.settings.audio_mode)

    -- Apply volumes
    Events.emit("SET_MASTER_VOLUME", self.settings.master_volume / 100)
    Events.emit("SET_MUSIC_VOLUME", self.settings.music_volume / 100)
    Events.emit("SET_SFX_VOLUME", self.settings.sfx_volume / 100)

    if self.on_settings_changed then
        self.on_settings_changed(self.settings)
    end
end

-- Save settings to file
function Options:save()
    local json = require("src.util.json") -- Assuming json utility exists
    local data = {}

    -- Serialize all settings
    for k, v in pairs(self.settings) do
        if type(v) == "table" then
            data[k] = {}
            for k2, v2 in pairs(v) do
                data[k][k2] = v2
            end
        else
            data[k] = v
        end
    end

    -- Save to file
    local success, err = love.filesystem.write("settings.json", json.encode(data))
    if not success then
        print("Failed to save settings: " .. tostring(err))
    end

    return success
end

-- Load settings from file
function Options:load()
    if not love.filesystem.getInfo("settings.json") then
        return false
    end

    local json = require("src.util.json")
    local content = love.filesystem.read("settings.json")
    if not content then
        return false
    end

    local success, data = pcall(json.decode, content)
    if not success or not data then
        return false
    end

    -- Apply loaded settings
    for k, v in pairs(data) do
        if type(v) == "table" and type(self.settings[k]) == "table" then
            for k2, v2 in pairs(v) do
                self.settings[k][k2] = v2
            end
        else
            self.settings[k] = v
        end
    end

    return true
end

function Options:update(dt)
    -- Nothing to update unless we add animations
end

function Options:draw()
    if not self.active then
        return
    end

    local w, h = love.graphics.getDimensions()

    -- Darken background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw main panel
    local panel_x = self.margin
    local panel_y = self.margin
    local panel_w = w - self.margin * 2
    local panel_h = h - self.margin * 2

    love.graphics.setColor(0.1, 0.1, 0.15, self.panel_alpha)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h)

    -- Border
    love.graphics.setColor(0.3, 0.6, 0.3, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h)

    -- Title
    love.graphics.setColor(0.3, 1, 0.3, 1)
    local title_font = love.graphics.getFont()
    love.graphics.printf("OPTIONS", panel_x, panel_y + 15, panel_w, "center")

    -- Draw category tabs
    local tab_y = panel_y + 50
    local tab_width = panel_w / 4
    for i = 1, 4 do
        local tab_x = panel_x + (i - 1) * tab_width
        local is_selected = self.category == i

        if is_selected then
            love.graphics.setColor(0.2, 0.4, 0.2, 1)
            love.graphics.rectangle("fill", tab_x + 5, tab_y, tab_width - 10, 30)
            love.graphics.setColor(0.3, 1, 0.3, 1)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 1)
            love.graphics.rectangle("fill", tab_x + 5, tab_y, tab_width - 10, 30)
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
        end

        love.graphics.printf(self.category_labels[i], tab_x + 5, tab_y + 8, tab_width - 10, "center")
    end

    -- Draw options
    local options = self:get_category_options()
    local opt_y = tab_y + 50
    local opt_spacing = 35
    local visible_start = self.scroll_offset + 1
    local visible_end = math.min(#options, self.scroll_offset + self.max_visible)

    for i = visible_start, visible_end do
        local option = options[i]
        local y = opt_y + (i - visible_start) * opt_spacing
        local is_selected = i == self.selected_index

        -- Selection highlight
        if is_selected then
            love.graphics.setColor(0.2, 0.3, 0.2, 0.5)
            love.graphics.rectangle("fill", panel_x + 20, y - 5, panel_w - 40, 30)
            love.graphics.setColor(1, 0.9, 0.3, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
        end

        -- Label
        love.graphics.print(option.label, panel_x + 40, y)

        -- Value
        local value_x = panel_x + panel_w - 250

        if option.type == "toggle" then
            local value = self.settings[option.key]
            local text = value and "ON" or "OFF"
            local color = value and {0.3, 1, 0.3, 1} or {1, 0.3, 0.3, 1}
            love.graphics.setColor(color)
            love.graphics.print(text, value_x, y)

        elseif option.type == "slider" then
            local value = self.settings[option.key]
            -- Draw slider track
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.rectangle("fill", value_x, y + 5, 120, 10)
            -- Draw filled portion
            local fill = (value - option.min) / (option.max - option.min) * 120
            love.graphics.setColor(0.3, 0.8, 0.3, 1)
            love.graphics.rectangle("fill", value_x, y + 5, fill, 10)
            -- Draw value text
            love.graphics.setColor(1, 1, 1, 1)
            if option.display then
                love.graphics.print(option.display[value] or tostring(value), value_x + 130, y)
            else
                love.graphics.print(tostring(value), value_x + 130, y)
            end

        elseif option.type == "choice" then
            local value = self.settings[option.key]
            local display_idx = 1
            for idx, choice in ipairs(option.choices) do
                if choice == value then
                    display_idx = idx
                    break
                end
            end
            love.graphics.setColor(0.3, 0.8, 0.3, 1)
            love.graphics.print("< " .. (option.display[display_idx] or value) .. " >", value_x, y)

        elseif option.type == "keybind" then
            local key = self.settings.keybinds[option.key]
            if self.rebinding and self.rebind_action == option.key then
                love.graphics.setColor(1, 1, 0.3, 1)
                love.graphics.print("Press a key...", value_x, y)
            else
                love.graphics.setColor(0.3, 0.8, 0.3, 1)
                love.graphics.print("[" .. (key or "???") .. "]", value_x, y)
            end

        elseif option.type == "action" then
            love.graphics.setColor(0.8, 0.6, 0.2, 1)
            love.graphics.print("[ Execute ]", value_x, y)
        end
    end

    -- Scroll indicators
    if self.scroll_offset > 0 then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.printf("^ More ^", panel_x, opt_y - 20, panel_w, "center")
    end
    if visible_end < #options then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.printf("v More v", panel_x, opt_y + self.max_visible * opt_spacing, panel_w, "center")
    end

    -- Instructions
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    local inst_y = panel_y + panel_h - 40
    if self.rebinding then
        love.graphics.printf("Press a key to bind, or ESC to cancel", panel_x, inst_y, panel_w, "center")
    else
        love.graphics.printf("Arrow Keys: Navigate | Enter: Select | Tab: Category | ESC: Close", panel_x, inst_y, panel_w, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function Options:keypressed(key)
    if not self.active then
        return false
    end

    -- Handle rebinding mode
    if self.rebinding then
        if key == "escape" then
            self.rebinding = false
            self.rebind_action = nil
        else
            -- Bind the key
            self.settings.keybinds[self.rebind_action] = key
            self.rebinding = false
            self.rebind_action = nil
            self:apply_settings()
        end
        return true
    end

    local options = self:get_category_options()

    if key == "escape" then
        self:hide()
        return true

    elseif key == "tab" then
        -- Cycle categories
        self.category = (self.category % 4) + 1
        self.selected_index = 1
        self.scroll_offset = 0
        return true

    elseif key == "up" then
        self.selected_index = self.selected_index - 1
        if self.selected_index < 1 then
            self.selected_index = #options
            self.scroll_offset = math.max(0, #options - self.max_visible)
        elseif self.selected_index <= self.scroll_offset then
            self.scroll_offset = self.selected_index - 1
        end
        return true

    elseif key == "down" then
        self.selected_index = self.selected_index + 1
        if self.selected_index > #options then
            self.selected_index = 1
            self.scroll_offset = 0
        elseif self.selected_index > self.scroll_offset + self.max_visible then
            self.scroll_offset = self.selected_index - self.max_visible
        end
        return true

    elseif key == "left" or key == "right" then
        local option = options[self.selected_index]
        if option then
            local delta = key == "right" and 1 or -1

            if option.type == "slider" then
                local value = self.settings[option.key] + delta
                value = math.max(option.min, math.min(option.max, value))
                self.settings[option.key] = value
                self:apply_settings()

            elseif option.type == "choice" then
                local current_idx = 1
                for i, choice in ipairs(option.choices) do
                    if choice == self.settings[option.key] then
                        current_idx = i
                        break
                    end
                end
                current_idx = current_idx + delta
                if current_idx < 1 then current_idx = #option.choices end
                if current_idx > #option.choices then current_idx = 1 end
                self.settings[option.key] = option.choices[current_idx]
                self:apply_settings()
            end
        end
        return true

    elseif key == "return" or key == "kpenter" or key == "space" then
        local option = options[self.selected_index]
        if option then
            if option.type == "toggle" then
                self.settings[option.key] = not self.settings[option.key]
                self:apply_settings()

            elseif option.type == "keybind" then
                self.rebinding = true
                self.rebind_action = option.key

            elseif option.type == "action" then
                if option.action == "reset_keybinds" then
                    for action, key in pairs(Options.DEFAULT_KEYBINDS) do
                        self.settings.keybinds[action] = key
                    end
                    self:apply_settings()
                end
            end
        end
        return true
    end

    return true
end

-- Get current keybind for an action
function Options:get_keybind(action)
    return self.settings.keybinds[action] or Options.DEFAULT_KEYBINDS[action]
end

-- Check if a key matches an action
function Options:is_action_key(key, action)
    local bound_key = self:get_keybind(action)
    return key == bound_key
end

-- Get all settings
function Options:get_settings()
    return self.settings
end

-- Check if active
function Options:is_active()
    return self.active
end

return Options
