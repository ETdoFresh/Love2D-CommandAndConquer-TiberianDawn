--[[
    Hotkeys Adapter - Rebindable keyboard shortcuts

    This adapter allows players to customize keyboard bindings
    for all game actions.

    Original: Fixed key bindings
    This Port: Fully rebindable hotkeys

    Reference: PLAN.md "Intentional Deviations"
]]

local Hotkeys = {}

--============================================================================
-- Configuration
--============================================================================

Hotkeys.enabled = false

-- Default bindings (matches original C&C)
Hotkeys.defaults = {
    -- Unit control
    select_all = "e",
    stop = "s",
    guard = "g",
    scatter = "x",
    deploy = "d",

    -- Movement
    move = "m",
    attack = "a",
    force_attack = "ctrl+a",

    -- Groups
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

    -- Create groups
    create_group_1 = "ctrl+1",
    create_group_2 = "ctrl+2",
    create_group_3 = "ctrl+3",
    create_group_4 = "ctrl+4",
    create_group_5 = "ctrl+5",
    create_group_6 = "ctrl+6",
    create_group_7 = "ctrl+7",
    create_group_8 = "ctrl+8",
    create_group_9 = "ctrl+9",
    create_group_0 = "ctrl+0",

    -- Camera
    center_base = "h",
    bookmark_1 = "f1",
    bookmark_2 = "f2",
    bookmark_3 = "f3",
    bookmark_4 = "f4",
    set_bookmark_1 = "ctrl+f1",
    set_bookmark_2 = "ctrl+f2",
    set_bookmark_3 = "ctrl+f3",
    set_bookmark_4 = "ctrl+f4",

    -- Interface
    toggle_sidebar = "tab",
    options_menu = "escape",
    alliance = "a",  -- In diplomacy screen

    -- Production
    repeat_build = "r",
    cancel_build = "escape",

    -- Debug (development only)
    debug_dump = "f11",
    debug_money = "f12",
}

-- Current bindings (can be modified)
Hotkeys.bindings = {}

-- Reverse lookup (key -> action)
Hotkeys.key_to_action = {}

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the hotkeys adapter.
]]
function Hotkeys.init()
    Hotkeys.enabled = true

    -- Copy defaults to bindings
    for action, key in pairs(Hotkeys.defaults) do
        Hotkeys.bindings[action] = key
    end

    -- Load custom bindings from settings file
    Hotkeys.load_bindings()

    -- Build reverse lookup
    Hotkeys.rebuild_lookup()

    print("Hotkeys: Initialized with " .. Hotkeys.count_bindings() .. " bindings")
end

--============================================================================
-- Binding Management
--============================================================================

--[[
    Set a hotkey binding.
    @param action - Action name
    @param key - Key string (e.g., "a", "ctrl+a", "shift+f1")
    @return true if binding was set
]]
function Hotkeys.set_binding(action, key)
    if not Hotkeys.enabled then
        return false
    end

    -- Validate action exists
    if Hotkeys.defaults[action] == nil then
        print("Hotkeys: Unknown action - " .. action)
        return false
    end

    -- Check for conflicts
    local existing = Hotkeys.key_to_action[key]
    if existing and existing ~= action then
        -- Clear the existing binding
        print(string.format("Hotkeys: Unbinding %s from %s (conflict)", key, existing))
        Hotkeys.bindings[existing] = nil
    end

    Hotkeys.bindings[action] = key
    Hotkeys.rebuild_lookup()

    return true
end

--[[
    Get the key binding for an action.
    @param action - Action name
    @return Key string or nil
]]
function Hotkeys.get_binding(action)
    return Hotkeys.bindings[action]
end

--[[
    Reset a binding to default.
    @param action - Action name
]]
function Hotkeys.reset_binding(action)
    Hotkeys.bindings[action] = Hotkeys.defaults[action]
    Hotkeys.rebuild_lookup()
end

--[[
    Reset all bindings to defaults.
]]
function Hotkeys.reset_all()
    for action, key in pairs(Hotkeys.defaults) do
        Hotkeys.bindings[action] = key
    end
    Hotkeys.rebuild_lookup()
end

--============================================================================
-- Key Handling
--============================================================================

--[[
    Get the action for a key press.
    @param key - Key that was pressed
    @param modifiers - Table of active modifiers {ctrl, shift, alt}
    @return Action name or nil
]]
function Hotkeys.get_action(key, modifiers)
    if not Hotkeys.enabled then
        return nil
    end

    modifiers = modifiers or {}

    -- Build key string with modifiers
    local key_str = Hotkeys.build_key_string(key, modifiers)

    return Hotkeys.key_to_action[key_str]
end

--[[
    Check if a specific action's hotkey is pressed.
    @param action - Action name
    @param key - Key that was pressed
    @param modifiers - Active modifiers
    @return true if this key triggers the action
]]
function Hotkeys.is_action(action, key, modifiers)
    local pressed_action = Hotkeys.get_action(key, modifiers)
    return pressed_action == action
end

--============================================================================
-- Key String Helpers
--============================================================================

--[[
    Build a key string with modifiers.
    @param key - Base key
    @param modifiers - Modifier table
    @return Key string (e.g., "ctrl+shift+a")
]]
function Hotkeys.build_key_string(key, modifiers)
    local parts = {}

    if modifiers.ctrl then
        table.insert(parts, "ctrl")
    end
    if modifiers.shift then
        table.insert(parts, "shift")
    end
    if modifiers.alt then
        table.insert(parts, "alt")
    end

    table.insert(parts, key:lower())

    return table.concat(parts, "+")
end

--[[
    Parse a key string into key and modifiers.
    @param key_str - Key string (e.g., "ctrl+a")
    @return key, modifiers table
]]
function Hotkeys.parse_key_string(key_str)
    local modifiers = {ctrl = false, shift = false, alt = false}
    local key = key_str

    for mod in key_str:gmatch("([^+]+)") do
        mod = mod:lower()
        if mod == "ctrl" then
            modifiers.ctrl = true
        elseif mod == "shift" then
            modifiers.shift = true
        elseif mod == "alt" then
            modifiers.alt = true
        else
            key = mod
        end
    end

    return key, modifiers
end

--============================================================================
-- Internal Helpers
--============================================================================

--[[
    Rebuild the reverse lookup table.
]]
function Hotkeys.rebuild_lookup()
    Hotkeys.key_to_action = {}

    for action, key in pairs(Hotkeys.bindings) do
        if key then
            Hotkeys.key_to_action[key] = action
        end
    end
end

--[[
    Count total bindings.
    @return Number of bindings
]]
function Hotkeys.count_bindings()
    local count = 0
    for _ in pairs(Hotkeys.bindings) do
        count = count + 1
    end
    return count
end

--============================================================================
-- Persistence
--============================================================================

--[[
    Save bindings to file.
]]
function Hotkeys.save_bindings()
    if not love or not love.filesystem then
        return
    end

    local lines = {}
    for action, key in pairs(Hotkeys.bindings) do
        if key then
            table.insert(lines, string.format("%s=%s", action, key))
        end
    end

    love.filesystem.write("hotkeys.ini", table.concat(lines, "\n"))
end

--[[
    Load bindings from file.
]]
function Hotkeys.load_bindings()
    if not love or not love.filesystem then
        return
    end

    local content = love.filesystem.read("hotkeys.ini")
    if not content then
        return
    end

    for line in content:gmatch("[^\r\n]+") do
        local action, key = line:match("^(%w+)=(.+)$")
        if action and key and Hotkeys.defaults[action] then
            Hotkeys.bindings[action] = key
        end
    end
end

--============================================================================
-- Debug
--============================================================================

function Hotkeys.Debug_Dump()
    print("Hotkeys Adapter:")
    print(string.format("  Enabled: %s", tostring(Hotkeys.enabled)))
    print(string.format("  Total Bindings: %d", Hotkeys.count_bindings()))

    -- Show non-default bindings
    print("  Modified Bindings:")
    local modified = 0
    for action, key in pairs(Hotkeys.bindings) do
        if key ~= Hotkeys.defaults[action] then
            print(string.format("    %s: %s (default: %s)",
                action, key or "unbound", Hotkeys.defaults[action] or "unbound"))
            modified = modified + 1
        end
    end
    if modified == 0 then
        print("    (none)")
    end
end

return Hotkeys
