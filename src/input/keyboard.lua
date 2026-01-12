--[[
    Keyboard Input - Fully rebindable hotkey system
    Based on original C&C keybindings with modern rebinding support
    Reference: Original C&C keyboard controls
]]

local Events = require("src.core.events")

local Keyboard = {}
Keyboard.__index = Keyboard

-- Default keybindings (matches original C&C where applicable)
Keyboard.DEFAULT_BINDINGS = {
    -- Unit commands
    move = "m",
    attack = "a",
    force_attack = "ctrl+a",
    stop = "s",
    guard = "g",
    scatter = "x",
    deploy = "d",

    -- Selection
    select_all = "ctrl+a",
    select_same_type = "t",

    -- Control groups (1-9)
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

    -- Assign control groups
    assign_group_1 = "ctrl+1",
    assign_group_2 = "ctrl+2",
    assign_group_3 = "ctrl+3",
    assign_group_4 = "ctrl+4",
    assign_group_5 = "ctrl+5",
    assign_group_6 = "ctrl+6",
    assign_group_7 = "ctrl+7",
    assign_group_8 = "ctrl+8",
    assign_group_9 = "ctrl+9",
    assign_group_0 = "ctrl+0",

    -- Add to control groups
    add_group_1 = "shift+1",
    add_group_2 = "shift+2",
    add_group_3 = "shift+3",
    add_group_4 = "shift+4",
    add_group_5 = "shift+5",
    add_group_6 = "shift+6",
    add_group_7 = "shift+7",
    add_group_8 = "shift+8",
    add_group_9 = "shift+9",
    add_group_0 = "shift+0",

    -- Camera
    camera_up = "up",
    camera_down = "down",
    camera_left = "left",
    camera_right = "right",
    center_on_selection = "home",
    center_on_base = "h",

    -- Sidebar
    sidebar_toggle = "tab",
    repair_mode = "r",
    sell_mode = "backspace",

    -- Special weapons
    ion_cannon = "i",
    nuke = "n",
    airstrike = "f",

    -- Game controls
    pause = "p",
    menu = "escape",
    objectives = "o",
    diplomacy = "f3",
    options = "f1",

    -- Debug/misc
    screenshot = "f12",
    toggle_fog = "f5",
    toggle_shroud = "f6",

    -- Queue modifiers (hold while clicking sidebar)
    queue_5 = "shift",
    queue_all = "ctrl"
}

-- Modifier keys
Keyboard.MODIFIERS = {
    ctrl = false,
    shift = false,
    alt = false
}

function Keyboard.new()
    local self = setmetatable({}, Keyboard)

    -- Current bindings (copy of defaults, can be modified)
    self.bindings = {}
    for action, key in pairs(Keyboard.DEFAULT_BINDINGS) do
        self.bindings[action] = key
    end

    -- Reverse lookup (key -> action)
    self.key_to_action = {}
    self:rebuild_key_lookup()

    -- Key states for edge detection
    self.key_states = {}

    -- Held keys for continuous actions (like camera pan)
    self.held_keys = {}

    -- Callbacks
    self.on_action = nil

    -- Rebinding mode
    self.rebinding = false
    self.rebind_action = nil
    self.on_rebind_complete = nil

    return self
end

-- Rebuild reverse lookup table
function Keyboard:rebuild_key_lookup()
    self.key_to_action = {}

    for action, binding in pairs(self.bindings) do
        -- Handle modifier combinations
        if binding:find("+") then
            -- Complex binding with modifier
            self.key_to_action[binding] = action
        else
            -- Simple key binding
            if not self.key_to_action[binding] then
                self.key_to_action[binding] = action
            end
        end
    end
end

-- Get current modifier string
function Keyboard:get_modifier_string()
    local mods = {}
    if Keyboard.MODIFIERS.ctrl then table.insert(mods, "ctrl") end
    if Keyboard.MODIFIERS.shift then table.insert(mods, "shift") end
    if Keyboard.MODIFIERS.alt then table.insert(mods, "alt") end

    if #mods > 0 then
        return table.concat(mods, "+") .. "+"
    end
    return ""
end

-- Handle key press
function Keyboard:keypressed(key, scancode, isrepeat)
    -- Update modifier states
    if key == "lctrl" or key == "rctrl" then
        Keyboard.MODIFIERS.ctrl = true
        return
    elseif key == "lshift" or key == "rshift" then
        Keyboard.MODIFIERS.shift = true
        return
    elseif key == "lalt" or key == "ralt" then
        Keyboard.MODIFIERS.alt = true
        return
    end

    -- Rebinding mode
    if self.rebinding then
        self:complete_rebind(key)
        return
    end

    -- Skip repeated keys for most actions
    if isrepeat then
        -- Allow repeat for camera movement
        if key == "up" or key == "down" or key == "left" or key == "right" then
            -- Continue, allow repeat
        else
            return
        end
    end

    -- Build full key string with modifiers
    local full_key = self:get_modifier_string() .. key

    -- Try full key with modifiers first
    local action = self.key_to_action[full_key]

    -- Fall back to plain key if no modifier match
    if not action and not (Keyboard.MODIFIERS.ctrl or Keyboard.MODIFIERS.shift or Keyboard.MODIFIERS.alt) then
        action = self.key_to_action[key]
    end

    if action then
        self:execute_action(action, true)
    end

    -- Track key state
    self.key_states[key] = true
    self.held_keys[key] = true
end

-- Handle key release
function Keyboard:keyreleased(key)
    -- Update modifier states
    if key == "lctrl" or key == "rctrl" then
        Keyboard.MODIFIERS.ctrl = false
        return
    elseif key == "lshift" or key == "rshift" then
        Keyboard.MODIFIERS.shift = false
        return
    elseif key == "lalt" or key == "ralt" then
        Keyboard.MODIFIERS.alt = false
        return
    end

    -- Track key state
    self.key_states[key] = false
    self.held_keys[key] = false

    -- Emit release event for continuous actions
    local action = self.key_to_action[key]
    if action then
        self:execute_action(action, false)
    end
end

-- Execute an action
function Keyboard:execute_action(action, pressed)
    if self.on_action then
        self.on_action(action, pressed)
    end

    Events.emit("KEYBOARD_ACTION", action, pressed)
end

-- Check if a key is currently held
function Keyboard:is_key_held(key)
    return self.held_keys[key] or false
end

-- Check if an action's key is currently held
function Keyboard:is_action_held(action)
    local binding = self.bindings[action]
    if binding then
        -- For simple bindings, check the key
        if not binding:find("+") then
            return self.held_keys[binding] or false
        else
            -- For modifier bindings, check both modifier and key
            local parts = {}
            for part in binding:gmatch("[^+]+") do
                table.insert(parts, part)
            end

            local key = parts[#parts]
            local mods_match = true

            for i = 1, #parts - 1 do
                local mod = parts[i]
                if mod == "ctrl" and not Keyboard.MODIFIERS.ctrl then
                    mods_match = false
                elseif mod == "shift" and not Keyboard.MODIFIERS.shift then
                    mods_match = false
                elseif mod == "alt" and not Keyboard.MODIFIERS.alt then
                    mods_match = false
                end
            end

            return mods_match and (self.held_keys[key] or false)
        end
    end
    return false
end

-- Check modifier states
function Keyboard:is_ctrl_held()
    return Keyboard.MODIFIERS.ctrl
end

function Keyboard:is_shift_held()
    return Keyboard.MODIFIERS.shift
end

function Keyboard:is_alt_held()
    return Keyboard.MODIFIERS.alt
end

-- Get camera movement from arrow keys
function Keyboard:get_camera_movement(speed)
    local dx, dy = 0, 0
    speed = speed or 1

    if self.held_keys["up"] or self.held_keys["w"] then dy = -speed end
    if self.held_keys["down"] or self.held_keys["s"] then dy = speed end
    if self.held_keys["left"] or self.held_keys["a"] then dx = -speed end
    if self.held_keys["right"] or self.held_keys["d"] then dx = speed end

    return dx, dy
end

-- Rebinding system
function Keyboard:start_rebind(action, callback)
    if not self.bindings[action] then
        return false
    end

    self.rebinding = true
    self.rebind_action = action
    self.on_rebind_complete = callback

    Events.emit("REBIND_STARTED", action)
    return true
end

function Keyboard:complete_rebind(key)
    if not self.rebinding or not self.rebind_action then
        return
    end

    -- Cancel rebind on escape
    if key == "escape" then
        self.rebinding = false
        self.rebind_action = nil
        Events.emit("REBIND_CANCELLED")
        return
    end

    -- Build binding string
    local binding = self:get_modifier_string() .. key

    -- Check if binding conflicts with another action
    local conflict = nil
    for action, existing_binding in pairs(self.bindings) do
        if existing_binding == binding and action ~= self.rebind_action then
            conflict = action
            break
        end
    end

    -- Set new binding
    local old_binding = self.bindings[self.rebind_action]
    self.bindings[self.rebind_action] = binding
    self:rebuild_key_lookup()

    -- Notify
    if self.on_rebind_complete then
        self.on_rebind_complete(self.rebind_action, binding, conflict)
    end

    Events.emit("REBIND_COMPLETE", self.rebind_action, binding, old_binding, conflict)

    self.rebinding = false
    self.rebind_action = nil
    self.on_rebind_complete = nil
end

function Keyboard:cancel_rebind()
    if self.rebinding then
        self.rebinding = false
        self.rebind_action = nil
        self.on_rebind_complete = nil
        Events.emit("REBIND_CANCELLED")
    end
end

-- Get binding for action
function Keyboard:get_binding(action)
    return self.bindings[action]
end

-- Set binding for action
function Keyboard:set_binding(action, binding)
    if self.bindings[action] ~= nil then
        self.bindings[action] = binding
        self:rebuild_key_lookup()
        return true
    end
    return false
end

-- Reset all bindings to defaults
function Keyboard:reset_bindings()
    for action, key in pairs(Keyboard.DEFAULT_BINDINGS) do
        self.bindings[action] = key
    end
    self:rebuild_key_lookup()
    Events.emit("BINDINGS_RESET")
end

-- Save bindings to table (for serialization)
function Keyboard:save_bindings()
    local data = {}
    for action, binding in pairs(self.bindings) do
        -- Only save non-default bindings
        if binding ~= Keyboard.DEFAULT_BINDINGS[action] then
            data[action] = binding
        end
    end
    return data
end

-- Load bindings from table
function Keyboard:load_bindings(data)
    -- Start with defaults
    for action, key in pairs(Keyboard.DEFAULT_BINDINGS) do
        self.bindings[action] = key
    end

    -- Apply custom bindings
    if data then
        for action, binding in pairs(data) do
            if self.bindings[action] ~= nil then
                self.bindings[action] = binding
            end
        end
    end

    self:rebuild_key_lookup()
end

-- Get friendly name for a binding
function Keyboard:get_binding_display(binding)
    if not binding then return "None" end

    -- Convert to uppercase and replace + with space
    local display = binding:upper():gsub("+", " + ")

    -- Replace common key names
    display = display:gsub("LCTRL", "CTRL")
    display = display:gsub("RCTRL", "CTRL")
    display = display:gsub("LSHIFT", "SHIFT")
    display = display:gsub("RSHIFT", "SHIFT")
    display = display:gsub("LALT", "ALT")
    display = display:gsub("RALT", "ALT")
    display = display:gsub("BACKSPACE", "BKSP")
    display = display:gsub("ESCAPE", "ESC")

    return display
end

-- Get all actions in a category
function Keyboard:get_actions_by_category()
    return {
        unit_commands = {"move", "attack", "force_attack", "stop", "guard", "scatter", "deploy"},
        selection = {"select_all", "select_same_type"},
        control_groups = {"group_1", "group_2", "group_3", "group_4", "group_5",
                         "group_6", "group_7", "group_8", "group_9", "group_0"},
        assign_groups = {"assign_group_1", "assign_group_2", "assign_group_3", "assign_group_4", "assign_group_5",
                        "assign_group_6", "assign_group_7", "assign_group_8", "assign_group_9", "assign_group_0"},
        camera = {"camera_up", "camera_down", "camera_left", "camera_right",
                 "center_on_selection", "center_on_base"},
        sidebar = {"sidebar_toggle", "repair_mode", "sell_mode"},
        special_weapons = {"ion_cannon", "nuke", "airstrike"},
        game = {"pause", "menu", "objectives", "diplomacy", "options"}
    }
end

return Keyboard
