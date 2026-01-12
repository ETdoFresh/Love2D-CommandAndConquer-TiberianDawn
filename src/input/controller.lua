--[[
    Controller Input - Gamepad/controller support
    Maps controller buttons to game actions
]]

local Events = require("src.core.events")

local Controller = {}
Controller.__index = Controller

-- Controller button mappings
Controller.BUTTONS = {
    -- D-pad / Left stick: Camera pan
    -- Right stick: Cursor movement

    -- Face buttons
    a = "select",           -- Select unit / Confirm
    b = "cancel",           -- Cancel / Deselect
    x = "attack",           -- Force attack
    y = "special",          -- Special action / Guard

    -- Shoulder buttons
    leftshoulder = "prev_group",    -- Previous control group
    rightshoulder = "next_group",   -- Next control group
    lefttrigger = "zoom_out",
    righttrigger = "zoom_in",

    -- Other
    back = "menu",          -- Open menu
    start = "pause",        -- Pause game
    leftstick = "center",   -- Center on selection
    rightstick = "cycle"    -- Cycle through units
}

-- Stick dead zone
Controller.DEADZONE = 0.2

-- Cursor speed (pixels per second)
Controller.CURSOR_SPEED = 400
Controller.CAMERA_SPEED = 300

function Controller.new()
    local self = setmetatable({}, Controller)

    -- Active gamepad
    self.gamepad = nil

    -- Virtual cursor position
    self.cursor_x = 400
    self.cursor_y = 300

    -- Button states (for edge detection)
    self.button_states = {}

    -- Stick values
    self.left_stick_x = 0
    self.left_stick_y = 0
    self.right_stick_x = 0
    self.right_stick_y = 0

    -- Control mode
    self.mode = "cursor"  -- "cursor" or "camera"

    -- Callbacks
    self.on_action = nil

    -- Detect connected gamepads
    self:detect_gamepads()

    return self
end

-- Detect connected gamepads
function Controller:detect_gamepads()
    local joysticks = love.joystick.getJoysticks()

    for _, joystick in ipairs(joysticks) do
        if joystick:isGamepad() then
            self.gamepad = joystick
            print("Controller detected: " .. joystick:getName())
            return
        end
    end
end

-- Check if controller is connected
function Controller:is_connected()
    return self.gamepad ~= nil and self.gamepad:isConnected()
end

-- Update controller state
function Controller:update(dt)
    if not self:is_connected() then
        self:detect_gamepads()
        return
    end

    -- Read stick values
    self.left_stick_x = self:apply_deadzone(self.gamepad:getGamepadAxis("leftx"))
    self.left_stick_y = self:apply_deadzone(self.gamepad:getGamepadAxis("lefty"))
    self.right_stick_x = self:apply_deadzone(self.gamepad:getGamepadAxis("rightx"))
    self.right_stick_y = self:apply_deadzone(self.gamepad:getGamepadAxis("righty"))

    -- Update cursor position based on right stick
    self.cursor_x = self.cursor_x + self.right_stick_x * Controller.CURSOR_SPEED * dt
    self.cursor_y = self.cursor_y + self.right_stick_y * Controller.CURSOR_SPEED * dt

    -- Clamp cursor to screen
    local width, height = love.graphics.getDimensions()
    self.cursor_x = math.max(0, math.min(width, self.cursor_x))
    self.cursor_y = math.max(0, math.min(height, self.cursor_y))

    -- Check button presses
    self:update_buttons()
end

-- Apply deadzone to stick value
function Controller:apply_deadzone(value)
    if math.abs(value) < Controller.DEADZONE then
        return 0
    end

    -- Rescale to 0-1 range after deadzone
    local sign = value > 0 and 1 or -1
    return sign * (math.abs(value) - Controller.DEADZONE) / (1 - Controller.DEADZONE)
end

-- Update button states and detect presses
function Controller:update_buttons()
    for button, action in pairs(Controller.BUTTONS) do
        local pressed = self.gamepad:isGamepadDown(button)
        local was_pressed = self.button_states[button] or false

        if pressed and not was_pressed then
            -- Button just pressed
            self:on_button_pressed(action)
        elseif not pressed and was_pressed then
            -- Button just released
            self:on_button_released(action)
        end

        self.button_states[button] = pressed
    end

    -- Handle triggers as analog
    local left_trigger = self.gamepad:getGamepadAxis("triggerleft")
    local right_trigger = self.gamepad:getGamepadAxis("triggerright")

    if left_trigger > 0.5 and (self.button_states["lefttrigger_analog"] or 0) <= 0.5 then
        self:on_button_pressed("zoom_out")
    end
    if right_trigger > 0.5 and (self.button_states["righttrigger_analog"] or 0) <= 0.5 then
        self:on_button_pressed("zoom_in")
    end

    self.button_states["lefttrigger_analog"] = left_trigger
    self.button_states["righttrigger_analog"] = right_trigger
end

-- Handle button press
function Controller:on_button_pressed(action)
    if self.on_action then
        self.on_action(action, true)
    end

    Events.emit("CONTROLLER_ACTION", action, true)
end

-- Handle button release
function Controller:on_button_released(action)
    if self.on_action then
        self.on_action(action, false)
    end

    Events.emit("CONTROLLER_ACTION", action, false)
end

-- Get camera movement from left stick
function Controller:get_camera_movement()
    return self.left_stick_x * Controller.CAMERA_SPEED,
           self.left_stick_y * Controller.CAMERA_SPEED
end

-- Get cursor position
function Controller:get_cursor_position()
    return self.cursor_x, self.cursor_y
end

-- Set cursor position (for when mouse moves)
function Controller:set_cursor_position(x, y)
    self.cursor_x = x
    self.cursor_y = y
end

-- Check if a specific action is currently held
function Controller:is_action_held(action)
    for button, btn_action in pairs(Controller.BUTTONS) do
        if btn_action == action and self.button_states[button] then
            return true
        end
    end
    return false
end

-- Draw controller cursor
function Controller:draw_cursor()
    if not self:is_connected() then return end

    -- Draw custom cursor
    love.graphics.setColor(1, 1, 0, 1)

    -- Crosshair style cursor
    local size = 10
    love.graphics.line(
        self.cursor_x - size, self.cursor_y,
        self.cursor_x + size, self.cursor_y
    )
    love.graphics.line(
        self.cursor_x, self.cursor_y - size,
        self.cursor_x, self.cursor_y + size
    )

    -- Circle outline
    love.graphics.circle("line", self.cursor_x, self.cursor_y, size)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Vibrate controller (if supported)
function Controller:vibrate(left_intensity, right_intensity, duration)
    if self.gamepad and self.gamepad.setVibration then
        self.gamepad:setVibration(left_intensity, right_intensity, duration)
    end
end

-- Stop vibration
function Controller:stop_vibration()
    if self.gamepad and self.gamepad.setVibration then
        self.gamepad:setVibration(0, 0)
    end
end

-- Handle gamepad added callback
function Controller:gamepadAdded(joystick)
    if joystick:isGamepad() and not self.gamepad then
        self.gamepad = joystick
        print("Controller connected: " .. joystick:getName())
        Events.emit("CONTROLLER_CONNECTED")
    end
end

-- Handle gamepad removed callback
function Controller:gamepadRemoved(joystick)
    if joystick == self.gamepad then
        self.gamepad = nil
        self.button_states = {}
        print("Controller disconnected")
        Events.emit("CONTROLLER_DISCONNECTED")
    end
end

-- Radial Menu System for controller commands
Controller.RADIAL_MENU = {
    items = {
        {name = "Move", action = "move", angle = 0, icon = "M"},
        {name = "Attack", action = "attack", angle = 45, icon = "A"},
        {name = "Force Attack", action = "force_attack", angle = 90, icon = "F"},
        {name = "Guard", action = "guard", angle = 135, icon = "G"},
        {name = "Stop", action = "stop", angle = 180, icon = "S"},
        {name = "Scatter", action = "scatter", angle = 225, icon = "X"},
        {name = "Deploy", action = "deploy", angle = 270, icon = "D"},
        {name = "Cancel", action = "cancel", angle = 315, icon = "C"}
    },
    radius = 80,
    item_radius = 25,
    active = false,
    selected_index = 0,
    center_x = 0,
    center_y = 0
}

-- Open radial menu at current cursor position
function Controller:open_radial_menu()
    local menu = Controller.RADIAL_MENU
    menu.active = true
    menu.center_x = self.cursor_x
    menu.center_y = self.cursor_y
    menu.selected_index = 0
    Events.emit("RADIAL_MENU_OPENED")
end

-- Close radial menu and execute selected action
function Controller:close_radial_menu(execute)
    local menu = Controller.RADIAL_MENU
    if not menu.active then return nil end

    local selected_action = nil
    if execute and menu.selected_index > 0 then
        selected_action = menu.items[menu.selected_index].action
        Events.emit("RADIAL_MENU_ACTION", selected_action)
    end

    menu.active = false
    Events.emit("RADIAL_MENU_CLOSED")
    return selected_action
end

-- Update radial menu selection based on stick direction
function Controller:update_radial_menu()
    local menu = Controller.RADIAL_MENU
    if not menu.active then return end

    -- Get stick direction
    local stick_x = self.right_stick_x
    local stick_y = self.right_stick_y

    -- Check if stick is deflected enough to select
    local magnitude = math.sqrt(stick_x * stick_x + stick_y * stick_y)
    if magnitude < 0.3 then
        -- Return to center (no selection)
        menu.selected_index = 0
        return
    end

    -- Calculate angle from stick direction (0 = right, clockwise)
    local angle = math.deg(math.atan2(stick_y, stick_x))
    if angle < 0 then angle = angle + 360 end

    -- Find closest menu item
    local closest_index = 0
    local closest_diff = 999

    for i, item in ipairs(menu.items) do
        local diff = math.abs(angle - item.angle)
        if diff > 180 then diff = 360 - diff end

        if diff < closest_diff and diff < 45 then  -- 45 degree tolerance
            closest_diff = diff
            closest_index = i
        end
    end

    menu.selected_index = closest_index
end

-- Draw radial menu
function Controller:draw_radial_menu()
    local menu = Controller.RADIAL_MENU
    if not menu.active then return end

    local cx, cy = menu.center_x, menu.center_y

    -- Draw semi-transparent background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.circle("fill", cx, cy, menu.radius + 40)

    -- Draw center circle
    love.graphics.setColor(0.2, 0.2, 0.3, 0.9)
    love.graphics.circle("fill", cx, cy, 30)
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.circle("line", cx, cy, 30)

    -- Draw menu items
    for i, item in ipairs(menu.items) do
        local angle_rad = math.rad(item.angle)
        local ix = cx + math.cos(angle_rad) * menu.radius
        local iy = cy + math.sin(angle_rad) * menu.radius

        local is_selected = (i == menu.selected_index)

        -- Item background
        if is_selected then
            love.graphics.setColor(0.8, 0.6, 0.1, 0.9)
        else
            love.graphics.setColor(0.3, 0.3, 0.4, 0.8)
        end
        love.graphics.circle("fill", ix, iy, menu.item_radius)

        -- Item border
        if is_selected then
            love.graphics.setColor(1, 0.9, 0.3, 1)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(0.5, 0.5, 0.6, 1)
            love.graphics.setLineWidth(1)
        end
        love.graphics.circle("line", ix, iy, menu.item_radius)

        -- Icon letter
        love.graphics.setColor(1, 1, 1, 1)
        local font = love.graphics.getFont()
        local icon_w = font:getWidth(item.icon)
        love.graphics.print(item.icon, ix - icon_w/2, iy - 8)

        -- Item name (only for selected)
        if is_selected then
            love.graphics.setColor(1, 1, 1, 1)
            local name_w = font:getWidth(item.name)
            love.graphics.print(item.name, cx - name_w/2, cy - 8)
        end

        love.graphics.setLineWidth(1)
    end

    -- Draw direction indicator from center to selected item
    if menu.selected_index > 0 then
        local item = menu.items[menu.selected_index]
        local angle_rad = math.rad(item.angle)
        local end_x = cx + math.cos(angle_rad) * (menu.radius - menu.item_radius - 5)
        local end_y = cy + math.sin(angle_rad) * (menu.radius - menu.item_radius - 5)

        love.graphics.setColor(1, 0.8, 0.2, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.line(cx, cy, end_x, end_y)
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Check if radial menu is open
function Controller:is_radial_menu_open()
    return Controller.RADIAL_MENU.active
end

-- Get selected radial menu action
function Controller:get_radial_selection()
    local menu = Controller.RADIAL_MENU
    if menu.selected_index > 0 then
        return menu.items[menu.selected_index].action
    end
    return nil
end

return Controller
