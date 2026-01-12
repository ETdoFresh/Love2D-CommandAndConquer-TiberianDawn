--[[
    Cursor System - Mouse cursor graphics and hotspots
    Displays context-sensitive cursors based on mouse mode
    Reference: Original C&C cursor system
]]

local Events = require("src.core.events")

local Cursor = {}
Cursor.__index = Cursor

-- Cursor types matching original C&C
Cursor.TYPE = {
    NORMAL = "normal",          -- Default arrow
    MOVE = "move",              -- Green move cursor
    NOMOVE = "nomove",          -- Red can't move cursor
    SELECT = "select",          -- Crosshair selection
    ATTACK = "attack",          -- Red crosshair attack
    CANT_ATTACK = "cant_attack", -- Can't attack target
    GUARD = "guard",            -- Guard/patrol cursor
    ENTER = "enter",            -- Enter transport
    DEPLOY = "deploy",          -- Deploy cursor
    SELL = "sell",              -- Sell building cursor
    REPAIR = "repair",          -- Repair cursor
    HARVEST = "harvest",        -- Harvest tiberium
    ION_CANNON = "ion_cannon",  -- Ion cannon targeting
    NUKE = "nuke",              -- Nuke targeting
    AIRSTRIKE = "airstrike",    -- Airstrike targeting
    SCROLL_N = "scroll_n",      -- Edge scroll north
    SCROLL_NE = "scroll_ne",
    SCROLL_E = "scroll_e",
    SCROLL_SE = "scroll_se",
    SCROLL_S = "scroll_s",
    SCROLL_SW = "scroll_sw",
    SCROLL_W = "scroll_w",
    SCROLL_NW = "scroll_nw",
    WAIT = "wait"               -- Hourglass/loading
}

-- Hotspot positions (relative to cursor image)
Cursor.HOTSPOTS = {
    normal = {0, 0},
    move = {12, 12},
    nomove = {12, 12},
    select = {12, 12},
    attack = {12, 12},
    cant_attack = {12, 12},
    guard = {12, 12},
    enter = {12, 12},
    deploy = {12, 12},
    sell = {12, 12},
    repair = {12, 12},
    harvest = {12, 12},
    ion_cannon = {12, 12},
    nuke = {12, 12},
    airstrike = {12, 12},
    scroll_n = {12, 0},
    scroll_ne = {23, 0},
    scroll_e = {23, 12},
    scroll_se = {23, 23},
    scroll_s = {12, 23},
    scroll_sw = {0, 23},
    scroll_w = {0, 12},
    scroll_nw = {0, 0},
    wait = {12, 12}
}

function Cursor.new()
    local self = setmetatable({}, Cursor)

    -- Current cursor type
    self.current_type = Cursor.TYPE.NORMAL

    -- Cursor images
    self.images = {}

    -- Animation state
    self.frame = 1
    self.frame_timer = 0
    self.frame_duration = 0.1

    -- Visibility
    self.visible = true
    self.use_system_cursor = false

    -- Custom cursor size
    self.scale = 1

    -- Generate default cursors (colored shapes)
    self:generate_default_cursors()

    return self
end

-- Generate simple colored cursor shapes
function Cursor:generate_default_cursors()
    local size = 24

    -- Create canvas for each cursor type
    for cursor_type, _ in pairs(Cursor.TYPE) do
        local canvas = love.graphics.newCanvas(size, size)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)

        self:draw_cursor_shape(cursor_type, size)

        love.graphics.setCanvas()
        self.images[cursor_type] = canvas
    end
end

-- Draw cursor shape on canvas
function Cursor:draw_cursor_shape(cursor_type, size)
    local half = size / 2

    if cursor_type == "normal" then
        -- Arrow cursor
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.polygon("fill",
            0, 0,
            0, size * 0.8,
            size * 0.2, size * 0.6,
            size * 0.4, size * 0.8,
            size * 0.5, size * 0.7,
            size * 0.3, size * 0.5,
            size * 0.5, size * 0.5
        )
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.setLineWidth(1)
        love.graphics.polygon("line",
            0, 0,
            0, size * 0.8,
            size * 0.2, size * 0.6,
            size * 0.4, size * 0.8,
            size * 0.5, size * 0.7,
            size * 0.3, size * 0.5,
            size * 0.5, size * 0.5
        )

    elseif cursor_type == "move" then
        -- Green move cursor
        love.graphics.setColor(0, 0.8, 0, 1)
        love.graphics.circle("line", half, half, half - 2)
        love.graphics.line(half, 2, half, size - 2)
        love.graphics.line(2, half, size - 2, half)

    elseif cursor_type == "nomove" then
        -- Red X cursor
        love.graphics.setColor(0.8, 0, 0, 1)
        love.graphics.setLineWidth(3)
        love.graphics.line(4, 4, size - 4, size - 4)
        love.graphics.line(4, size - 4, size - 4, 4)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "select" then
        -- Selection crosshair
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.line(half, 0, half, half - 4)
        love.graphics.line(half, half + 4, half, size)
        love.graphics.line(0, half, half - 4, half)
        love.graphics.line(half + 4, half, size, half)
        love.graphics.circle("line", half, half, 4)

    elseif cursor_type == "attack" then
        -- Red attack crosshair
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(half, 0, half, half - 4)
        love.graphics.line(half, half + 4, half, size)
        love.graphics.line(0, half, half - 4, half)
        love.graphics.line(half + 4, half, size, half)
        love.graphics.circle("line", half, half, 6)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "cant_attack" then
        -- Red circle with line
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", half, half, half - 2)
        love.graphics.line(4, size - 4, size - 4, 4)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "guard" then
        -- Shield shape
        love.graphics.setColor(0, 0.6, 1, 1)
        love.graphics.polygon("line",
            half, 2,
            size - 2, half - 4,
            size - 2, half + 2,
            half, size - 2,
            2, half + 2,
            2, half - 4
        )

    elseif cursor_type == "enter" then
        -- Enter/transport cursor
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.rectangle("line", 4, 4, size - 8, size - 8)
        -- Arrow pointing in
        love.graphics.polygon("fill",
            half, half + 4,
            half - 4, half - 2,
            half + 4, half - 2
        )

    elseif cursor_type == "deploy" then
        -- Deploy cursor
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.rectangle("line", 4, 4, size - 8, size - 8)
        love.graphics.setColor(0, 0.6, 0, 1)
        love.graphics.rectangle("fill", 6, 6, size - 12, size - 12)

    elseif cursor_type == "sell" then
        -- Dollar sign
        love.graphics.setColor(1, 0.8, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(half, 2, half, size - 2)
        love.graphics.arc("line", "open", half, half - 3, 5, math.pi, math.pi * 2)
        love.graphics.arc("line", "open", half, half + 3, 5, 0, math.pi)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "repair" then
        -- Wrench
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.setLineWidth(3)
        love.graphics.line(4, size - 4, size - 4, 4)
        love.graphics.circle("fill", 6, size - 6, 4)
        love.graphics.circle("fill", size - 6, 6, 4)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "harvest" then
        -- Harvest cursor (Tiberium crystal)
        love.graphics.setColor(0, 1, 0.3, 1)
        love.graphics.polygon("fill",
            half, 2,
            size - 4, half,
            half, size - 2,
            4, half
        )
        love.graphics.setColor(0.2, 0.8, 0.4, 1)
        love.graphics.polygon("line",
            half, 2,
            size - 4, half,
            half, size - 2,
            4, half
        )

    elseif cursor_type == "ion_cannon" then
        -- Ion cannon targeting
        love.graphics.setColor(0, 0.8, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", half, half, half - 2)
        love.graphics.circle("line", half, half, half - 6)
        love.graphics.line(half, 0, half, size)
        love.graphics.line(0, half, size, half)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "nuke" then
        -- Nuclear targeting
        love.graphics.setColor(1, 0.5, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", half, half, half - 2)
        love.graphics.setColor(1, 0, 0, 1)
        -- Radiation symbol
        love.graphics.arc("fill", half, half, 6, 0, math.pi * 2 / 3)
        love.graphics.arc("fill", half, half, 6, math.pi * 2 / 3, math.pi * 4 / 3)
        love.graphics.arc("fill", half, half, 6, math.pi * 4 / 3, math.pi * 2)
        love.graphics.setLineWidth(1)

    elseif cursor_type == "airstrike" then
        -- Airstrike targeting
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", half, half, half - 2)
        -- Airplane shape
        love.graphics.polygon("fill",
            half, 4,
            half + 6, half,
            half, half + 4,
            half - 6, half
        )
        love.graphics.setLineWidth(1)

    elseif cursor_type:find("scroll_") then
        -- Scroll arrows
        love.graphics.setColor(1, 1, 1, 1)
        local dir = cursor_type:gsub("scroll_", "")

        if dir == "n" then
            love.graphics.polygon("fill", half, 2, half - 8, 14, half + 8, 14)
        elseif dir == "ne" then
            love.graphics.polygon("fill", size - 2, 2, size - 14, 2, size - 2, 14)
        elseif dir == "e" then
            love.graphics.polygon("fill", size - 2, half, size - 14, half - 8, size - 14, half + 8)
        elseif dir == "se" then
            love.graphics.polygon("fill", size - 2, size - 2, size - 2, size - 14, size - 14, size - 2)
        elseif dir == "s" then
            love.graphics.polygon("fill", half, size - 2, half - 8, size - 14, half + 8, size - 14)
        elseif dir == "sw" then
            love.graphics.polygon("fill", 2, size - 2, 14, size - 2, 2, size - 14)
        elseif dir == "w" then
            love.graphics.polygon("fill", 2, half, 14, half - 8, 14, half + 8)
        elseif dir == "nw" then
            love.graphics.polygon("fill", 2, 2, 2, 14, 14, 2)
        end

    elseif cursor_type == "wait" then
        -- Hourglass
        love.graphics.setColor(1, 0.8, 0, 1)
        love.graphics.polygon("line",
            4, 2,
            size - 4, 2,
            half, half,
            size - 4, size - 2,
            4, size - 2,
            half, half
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Load cursor images from files
function Cursor:load_images(path)
    -- Load cursor spritesheets/images from assets
    -- This would be implemented based on actual asset format
end

-- Set current cursor type
function Cursor:set_type(cursor_type)
    if self.current_type ~= cursor_type then
        self.current_type = cursor_type
        self.frame = 1
        self.frame_timer = 0
        Events.emit("CURSOR_CHANGED", cursor_type)
    end
end

-- Get current cursor type
function Cursor:get_type()
    return self.current_type
end

-- Update cursor animation
function Cursor:update(dt)
    self.frame_timer = self.frame_timer + dt
    if self.frame_timer >= self.frame_duration then
        self.frame_timer = 0
        self.frame = self.frame + 1
        -- Loop animation (if multi-frame)
        -- For now, single frame cursors
        self.frame = 1
    end
end

-- Draw cursor at position
function Cursor:draw(x, y)
    if not self.visible then return end
    if self.use_system_cursor then return end

    local image = self.images[self.current_type]
    if not image then
        image = self.images[Cursor.TYPE.NORMAL]
    end

    if image then
        local hotspot = Cursor.HOTSPOTS[self.current_type] or {0, 0}

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image,
            x - hotspot[1] * self.scale,
            y - hotspot[2] * self.scale,
            0,
            self.scale,
            self.scale
        )
    end
end

-- Draw at mouse position
function Cursor:draw_at_mouse()
    local x, y = love.mouse.getPosition()
    self:draw(x, y)
end

-- Set visibility
function Cursor:set_visible(visible)
    self.visible = visible
    love.mouse.setVisible(not visible or self.use_system_cursor)
end

-- Use system cursor instead of custom
function Cursor:set_use_system_cursor(use_system)
    self.use_system_cursor = use_system
    love.mouse.setVisible(use_system)
end

-- Set cursor scale
function Cursor:set_scale(scale)
    self.scale = scale
end

-- Get hotspot for current cursor
function Cursor:get_hotspot()
    return Cursor.HOTSPOTS[self.current_type] or {0, 0}
end

-- Determine cursor based on context
function Cursor:determine_cursor(target, selected_units, mode)
    -- Special modes take priority
    if mode == "sell" then
        return Cursor.TYPE.SELL
    elseif mode == "repair" then
        return Cursor.TYPE.REPAIR
    elseif mode == "ion_cannon" then
        return Cursor.TYPE.ION_CANNON
    elseif mode == "nuke" then
        return Cursor.TYPE.NUKE
    elseif mode == "airstrike" then
        return Cursor.TYPE.AIRSTRIKE
    end

    -- No selection = normal cursor
    if not selected_units or #selected_units == 0 then
        return Cursor.TYPE.NORMAL
    end

    -- Check target
    if target then
        if target.is_enemy then
            return Cursor.TYPE.ATTACK
        elseif target.is_transport and target.has_space then
            return Cursor.TYPE.ENTER
        elseif target.can_be_harvested then
            return Cursor.TYPE.HARVEST
        end
    end

    -- Default to move cursor for selected units
    return Cursor.TYPE.MOVE
end

return Cursor
