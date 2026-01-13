--[[
    Controller Adapter - Gamepad/controller support

    This adapter provides full controller support with:
    - Virtual cursor control via analog sticks
    - Radial menus for unit commands
    - Context-sensitive button mappings
    - Vibration feedback

    Original: Keyboard/mouse only
    This Port: Full controller support

    Reference: PLAN.md "Intentional Deviations"
]]

local Controller = {}

--============================================================================
-- Configuration
--============================================================================

Controller.enabled = false
Controller.connected = false
Controller.joystick = nil

-- Virtual cursor state
Controller.cursor = {
    x = 160,  -- Center of 320x200
    y = 100,
    speed = 200,  -- Pixels per second
}

-- Button mappings (can be customized)
Controller.bindings = {
    -- Face buttons
    a = "select",           -- Select/confirm
    b = "cancel",           -- Cancel/deselect
    x = "attack",           -- Attack command
    y = "stop",             -- Stop command

    -- Shoulders
    leftshoulder = "prev_unit",   -- Previous unit/building
    rightshoulder = "next_unit",  -- Next unit/building

    -- Triggers
    lefttrigger = "scroll_speed_slow",
    righttrigger = "scroll_speed_fast",

    -- D-pad
    dpup = "scroll_up",
    dpdown = "scroll_down",
    dpleft = "scroll_left",
    dpright = "scroll_right",

    -- Sticks
    leftstick = "move_cursor",
    rightstick = "scroll_map",

    -- Other
    start = "pause_menu",
    back = "sidebar_toggle",
}

-- Radial menu state
Controller.radial_menu = {
    active = false,
    items = {},
    selected = 0,
}

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the controller adapter.
]]
function Controller.init()
    Controller.enabled = true

    -- Check for connected controllers
    if love and love.joystick then
        local joysticks = love.joystick.getJoysticks()
        for _, js in ipairs(joysticks) do
            if js:isGamepad() then
                Controller.joystick = js
                Controller.connected = true
                print("Controller: Found gamepad - " .. js:getName())
                break
            end
        end
    end

    if not Controller.connected then
        print("Controller: No gamepad found, adapter on standby")
    end
end

--============================================================================
-- Update
--============================================================================

--[[
    Update controller state.
    @param dt - Delta time
]]
function Controller.update(dt)
    if not Controller.enabled or not Controller.connected then
        return
    end

    local js = Controller.joystick
    if not js or not js:isConnected() then
        Controller.connected = false
        return
    end

    -- Update virtual cursor from left stick
    local lx = js:getGamepadAxis("leftx")
    local ly = js:getGamepadAxis("lefty")

    -- Apply deadzone
    local deadzone = 0.2
    if math.abs(lx) < deadzone then lx = 0 end
    if math.abs(ly) < deadzone then ly = 0 end

    -- Move cursor
    Controller.cursor.x = Controller.cursor.x + lx * Controller.cursor.speed * dt
    Controller.cursor.y = Controller.cursor.y + ly * Controller.cursor.speed * dt

    -- Clamp to screen
    Controller.cursor.x = math.max(0, math.min(320, Controller.cursor.x))
    Controller.cursor.y = math.max(0, math.min(200, Controller.cursor.y))

    -- Update scroll from right stick
    local rx = js:getGamepadAxis("rightx")
    local ry = js:getGamepadAxis("righty")

    if math.abs(rx) < deadzone then rx = 0 end
    if math.abs(ry) < deadzone then ry = 0 end

    -- Would emit scroll events here
    if rx ~= 0 or ry ~= 0 then
        -- Events.emit("CONTROLLER_SCROLL", rx, ry)
    end
end

--============================================================================
-- Input Handling
--============================================================================

--[[
    Handle gamepad button press.
    @param button - Button name
    @return Action string or nil
]]
function Controller.button_pressed(button)
    if not Controller.enabled then
        return nil
    end

    local action = Controller.bindings[button]
    if action then
        return action
    end

    return nil
end

--[[
    Handle gamepad button release.
    @param button - Button name
    @return Action string or nil
]]
function Controller.button_released(button)
    if not Controller.enabled then
        return nil
    end

    -- Close radial menu on release
    if button == "rightshoulder" and Controller.radial_menu.active then
        Controller.close_radial_menu()
    end

    return nil
end

--============================================================================
-- Virtual Cursor
--============================================================================

--[[
    Get the current virtual cursor position.
    @return x, y in game coordinates
]]
function Controller.get_cursor()
    return Controller.cursor.x, Controller.cursor.y
end

--[[
    Set the virtual cursor position.
    @param x - X position
    @param y - Y position
]]
function Controller.set_cursor(x, y)
    Controller.cursor.x = x
    Controller.cursor.y = y
end

--[[
    Check if virtual cursor is over a screen region.
    @param x1 - Left bound
    @param y1 - Top bound
    @param x2 - Right bound
    @param y2 - Bottom bound
    @return true if cursor is in region
]]
function Controller.cursor_in_region(x1, y1, x2, y2)
    return Controller.cursor.x >= x1 and Controller.cursor.x <= x2 and
           Controller.cursor.y >= y1 and Controller.cursor.y <= y2
end

--============================================================================
-- Radial Menu
--============================================================================

--[[
    Open a radial menu with the given items.
    @param items - Table of {name, action, icon} entries
]]
function Controller.open_radial_menu(items)
    Controller.radial_menu.active = true
    Controller.radial_menu.items = items or {}
    Controller.radial_menu.selected = 0
end

--[[
    Close the radial menu and execute selected action.
    @return Selected action or nil
]]
function Controller.close_radial_menu()
    if not Controller.radial_menu.active then
        return nil
    end

    Controller.radial_menu.active = false

    local selected = Controller.radial_menu.selected
    if selected > 0 and selected <= #Controller.radial_menu.items then
        return Controller.radial_menu.items[selected].action
    end

    return nil
end

--[[
    Update radial menu selection based on stick direction.
    @param angle - Angle in radians from stick
]]
function Controller.update_radial_selection(angle)
    if not Controller.radial_menu.active then
        return
    end

    local count = #Controller.radial_menu.items
    if count == 0 then
        return
    end

    -- Convert angle to selection index
    local segment = (2 * math.pi) / count
    local selection = math.floor((angle + math.pi + segment / 2) / segment) % count + 1
    Controller.radial_menu.selected = selection
end

--============================================================================
-- Vibration
--============================================================================

--[[
    Trigger controller vibration.
    @param left - Left motor intensity (0-1)
    @param right - Right motor intensity (0-1)
    @param duration - Duration in seconds
]]
function Controller.vibrate(left, right, duration)
    if not Controller.enabled or not Controller.connected then
        return
    end

    if Controller.joystick and Controller.joystick.setVibration then
        Controller.joystick:setVibration(left, right, duration)
    end
end

--============================================================================
-- Settings
--============================================================================

--[[
    Set a button binding.
    @param button - Button name
    @param action - Action string
]]
function Controller.set_binding(button, action)
    Controller.bindings[button] = action
end

--[[
    Get the action for a button.
    @param button - Button name
    @return Action string or nil
]]
function Controller.get_binding(button)
    return Controller.bindings[button]
end

--[[
    Set cursor movement speed.
    @param speed - Pixels per second
]]
function Controller.set_cursor_speed(speed)
    Controller.cursor.speed = math.max(50, math.min(500, speed))
end

--============================================================================
-- Debug
--============================================================================

function Controller.Debug_Dump()
    print("Controller Adapter:")
    print(string.format("  Enabled: %s", tostring(Controller.enabled)))
    print(string.format("  Connected: %s", tostring(Controller.connected)))
    if Controller.joystick then
        print(string.format("  Joystick: %s", Controller.joystick:getName()))
    end
    print(string.format("  Cursor: (%.1f, %.1f)", Controller.cursor.x, Controller.cursor.y))
    print(string.format("  Cursor Speed: %.0f", Controller.cursor.speed))
    print(string.format("  Radial Menu Active: %s", tostring(Controller.radial_menu.active)))
end

return Controller
