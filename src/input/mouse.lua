--[[
    Mouse Input - Mouse handling for unit selection, commands, and UI
    Based on original C&C mouse behavior with selection box and cursor modes
    Reference: Original C&C mouse controls
]]

local Events = require("src.core.events")

local Mouse = {}
Mouse.__index = Mouse

-- Cursor modes
Mouse.MODE = {
    NORMAL = "normal",          -- Default arrow
    MOVE = "move",              -- Move order cursor
    ATTACK = "attack",          -- Attack cursor
    FORCE_ATTACK = "force_attack", -- Force attack (ctrl+click)
    SELECT = "select",          -- Selection rectangle active
    DEPLOY = "deploy",          -- Deploy building placement
    SELL = "sell",              -- Sell mode
    REPAIR = "repair",          -- Repair mode
    ION_CANNON = "ion_cannon",  -- Ion cannon targeting
    NUKE = "nuke",              -- Nuclear strike targeting
    AIRSTRIKE = "airstrike",    -- Airstrike targeting
    UNAVAILABLE = "unavailable" -- Can't perform action
}

-- Mouse button constants
Mouse.BUTTON = {
    LEFT = 1,
    RIGHT = 2,
    MIDDLE = 3
}

function Mouse.new()
    local self = setmetatable({}, Mouse)

    -- Current position
    self.x = 0
    self.y = 0

    -- World position (after camera transform)
    self.world_x = 0
    self.world_y = 0

    -- Button states
    self.button_states = {
        [Mouse.BUTTON.LEFT] = false,
        [Mouse.BUTTON.RIGHT] = false,
        [Mouse.BUTTON.MIDDLE] = false
    }

    -- Button press positions (for drag detection)
    self.press_x = {
        [Mouse.BUTTON.LEFT] = 0,
        [Mouse.BUTTON.RIGHT] = 0,
        [Mouse.BUTTON.MIDDLE] = 0
    }
    self.press_y = {
        [Mouse.BUTTON.LEFT] = 0,
        [Mouse.BUTTON.RIGHT] = 0,
        [Mouse.BUTTON.MIDDLE] = 0
    }

    -- Selection box
    self.selection_box = {
        active = false,
        start_x = 0,
        start_y = 0,
        end_x = 0,
        end_y = 0
    }

    -- Drag threshold (pixels before considered a drag)
    self.drag_threshold = 4

    -- Current cursor mode
    self.mode = Mouse.MODE.NORMAL

    -- Cursor hotspot override
    self.cursor_hotspot_x = 0
    self.cursor_hotspot_y = 0

    -- Double-click detection
    self.last_click_time = 0
    self.last_click_x = 0
    self.last_click_y = 0
    self.double_click_threshold = 0.3  -- seconds
    self.double_click_distance = 10    -- pixels

    -- Camera reference (set externally)
    self.camera = nil

    -- Callbacks
    self.on_click = nil
    self.on_double_click = nil
    self.on_drag_start = nil
    self.on_drag = nil
    self.on_drag_end = nil
    self.on_selection_box = nil
    self.on_scroll = nil

    return self
end

-- Set camera reference for world coordinate conversion
function Mouse:set_camera(camera)
    self.camera = camera
end

-- Update mouse position
function Mouse:update(dt)
    self.x, self.y = love.mouse.getPosition()

    -- Convert to world coordinates if camera is set
    if self.camera then
        self.world_x = self.x / self.camera.zoom + self.camera.x
        self.world_y = self.y / self.camera.zoom + self.camera.y
    else
        self.world_x = self.x
        self.world_y = self.y
    end

    -- Update selection box if active
    if self.selection_box.active then
        self.selection_box.end_x = self.world_x
        self.selection_box.end_y = self.world_y

        if self.on_drag then
            self.on_drag(self.x, self.y, Mouse.BUTTON.LEFT)
        end
    end
end

-- Handle mouse press
function Mouse:mousepressed(x, y, button, istouch, presses)
    self.button_states[button] = true
    self.press_x[button] = x
    self.press_y[button] = y

    -- Left click - start potential selection box
    if button == Mouse.BUTTON.LEFT then
        -- Check for double-click
        local current_time = love.timer.getTime()
        local time_diff = current_time - self.last_click_time
        local dist = math.sqrt((x - self.last_click_x)^2 + (y - self.last_click_y)^2)

        if time_diff < self.double_click_threshold and dist < self.double_click_distance then
            -- Double-click detected
            if self.on_double_click then
                self.on_double_click(self.world_x, self.world_y, button)
            end
            Events.emit("MOUSE_DOUBLE_CLICK", self.world_x, self.world_y, button)
            self.last_click_time = 0  -- Reset to prevent triple-click
        else
            self.last_click_time = current_time
            self.last_click_x = x
            self.last_click_y = y
        end

        -- Start selection box tracking
        self.selection_box.start_x = self.world_x
        self.selection_box.start_y = self.world_y
        self.selection_box.end_x = self.world_x
        self.selection_box.end_y = self.world_y
    end

    Events.emit("MOUSE_PRESSED", self.world_x, self.world_y, button)
end

-- Handle mouse release
function Mouse:mousereleased(x, y, button, istouch, presses)
    local was_pressed = self.button_states[button]
    self.button_states[button] = false

    if not was_pressed then return end

    -- Calculate drag distance
    local drag_dist = math.sqrt(
        (x - self.press_x[button])^2 +
        (y - self.press_y[button])^2
    )

    local was_drag = drag_dist >= self.drag_threshold

    if button == Mouse.BUTTON.LEFT then
        if self.selection_box.active then
            -- End selection box
            self.selection_box.active = false

            -- Emit selection box event
            local box = self:get_selection_box_normalized()
            if self.on_selection_box then
                self.on_selection_box(box.x1, box.y1, box.x2, box.y2)
            end
            Events.emit("SELECTION_BOX", box.x1, box.y1, box.x2, box.y2)

            if self.on_drag_end then
                self.on_drag_end(self.world_x, self.world_y, button)
            end
        elseif not was_drag then
            -- Single click (not a drag)
            if self.on_click then
                self.on_click(self.world_x, self.world_y, button, self.mode)
            end
            Events.emit("MOUSE_CLICK", self.world_x, self.world_y, button, self.mode)
        end
    elseif button == Mouse.BUTTON.RIGHT then
        if not was_drag then
            -- Right click command
            if self.on_click then
                self.on_click(self.world_x, self.world_y, button, self.mode)
            end
            Events.emit("MOUSE_CLICK", self.world_x, self.world_y, button, self.mode)
        end
    end

    Events.emit("MOUSE_RELEASED", self.world_x, self.world_y, button)
end

-- Handle mouse movement
function Mouse:mousemoved(x, y, dx, dy, istouch)
    -- Check if starting a drag
    if self.button_states[Mouse.BUTTON.LEFT] and not self.selection_box.active then
        local drag_dist = math.sqrt(
            (x - self.press_x[Mouse.BUTTON.LEFT])^2 +
            (y - self.press_y[Mouse.BUTTON.LEFT])^2
        )

        if drag_dist >= self.drag_threshold then
            -- Start selection box
            self.selection_box.active = true

            if self.on_drag_start then
                self.on_drag_start(
                    self.selection_box.start_x,
                    self.selection_box.start_y,
                    Mouse.BUTTON.LEFT
                )
            end
            Events.emit("DRAG_START", self.selection_box.start_x, self.selection_box.start_y)
        end
    end

    Events.emit("MOUSE_MOVED", self.world_x, self.world_y, dx, dy)
end

-- Handle mouse wheel
function Mouse:wheelmoved(x, y)
    if self.on_scroll then
        self.on_scroll(x, y)
    end
    Events.emit("MOUSE_WHEEL", x, y)
end

-- Get selection box normalized (x1 < x2, y1 < y2)
function Mouse:get_selection_box_normalized()
    local box = self.selection_box
    return {
        x1 = math.min(box.start_x, box.end_x),
        y1 = math.min(box.start_y, box.end_y),
        x2 = math.max(box.start_x, box.end_x),
        y2 = math.max(box.start_y, box.end_y)
    }
end

-- Check if selection box is active
function Mouse:is_selecting()
    return self.selection_box.active
end

-- Get selection box dimensions
function Mouse:get_selection_box()
    if not self.selection_box.active then
        return nil
    end
    return self:get_selection_box_normalized()
end

-- Set cursor mode
function Mouse:set_mode(mode)
    if self.mode ~= mode then
        self.mode = mode
        Events.emit("CURSOR_MODE_CHANGED", mode)
    end
end

-- Get current cursor mode
function Mouse:get_mode()
    return self.mode
end

-- Reset cursor to normal
function Mouse:reset_mode()
    self:set_mode(Mouse.MODE.NORMAL)
end

-- Check if a button is currently held
function Mouse:is_button_held(button)
    return self.button_states[button] or false
end

-- Get current position
function Mouse:get_position()
    return self.x, self.y
end

-- Get world position
function Mouse:get_world_position()
    return self.world_x, self.world_y
end

-- Get cell at current mouse position
function Mouse:get_cell(cell_size)
    cell_size = cell_size or 24
    local cell_x = math.floor(self.world_x / cell_size)
    local cell_y = math.floor(self.world_y / cell_size)
    return cell_x, cell_y
end

-- Check if mouse is within a rectangle
function Mouse:is_within(x, y, width, height)
    return self.x >= x and self.x <= x + width and
           self.y >= y and self.y <= y + height
end

-- Check if world position is within a rectangle
function Mouse:is_world_within(x, y, width, height)
    return self.world_x >= x and self.world_x <= x + width and
           self.world_y >= y and self.world_y <= y + height
end

-- Draw selection box (call from game's draw function)
function Mouse:draw_selection_box()
    if not self.selection_box.active then return end

    local box = self:get_selection_box_normalized()
    local width = box.x2 - box.x1
    local height = box.y2 - box.y1

    -- Draw filled rectangle with transparency
    love.graphics.setColor(0.2, 0.8, 0.2, 0.2)
    love.graphics.rectangle("fill", box.x1, box.y1, width, height)

    -- Draw outline
    love.graphics.setColor(0.2, 1.0, 0.2, 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", box.x1, box.y1, width, height)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Screen edge scrolling (returns camera movement direction)
function Mouse:get_edge_scroll(edge_size, speed)
    edge_size = edge_size or 20
    speed = speed or 1

    local width, height = love.graphics.getDimensions()
    local dx, dy = 0, 0

    if self.x < edge_size then
        dx = -speed * (1 - self.x / edge_size)
    elseif self.x > width - edge_size then
        dx = speed * (1 - (width - self.x) / edge_size)
    end

    if self.y < edge_size then
        dy = -speed * (1 - self.y / edge_size)
    elseif self.y > height - edge_size then
        dy = speed * (1 - (height - self.y) / edge_size)
    end

    return dx, dy
end

-- Hide system cursor
function Mouse:hide_cursor()
    love.mouse.setVisible(false)
end

-- Show system cursor
function Mouse:show_cursor()
    love.mouse.setVisible(true)
end

-- Set cursor visibility
function Mouse:set_cursor_visible(visible)
    love.mouse.setVisible(visible)
end

return Mouse
