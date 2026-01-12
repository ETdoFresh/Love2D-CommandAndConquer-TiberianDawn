--[[
    Selection Box - Visual selection rectangle UI
    Draws the drag selection box and handles selection logic
    Reference: Original C&C selection rectangle
]]

local Events = require("src.core.events")

local SelectionBox = {}
SelectionBox.__index = SelectionBox

function SelectionBox.new()
    local self = setmetatable({}, SelectionBox)

    -- Box state
    self.active = false
    self.start_x = 0
    self.start_y = 0
    self.end_x = 0
    self.end_y = 0

    -- Visual settings
    self.fill_color = {0.2, 0.8, 0.2, 0.15}
    self.border_color = {0.2, 1.0, 0.2, 0.8}
    self.border_width = 1

    -- Animation
    self.pulse_timer = 0
    self.pulse_speed = 4

    return self
end

-- Start selection box
function SelectionBox:start(x, y)
    self.active = true
    self.start_x = x
    self.start_y = y
    self.end_x = x
    self.end_y = y
    Events.emit("SELECTION_BOX_START", x, y)
end

-- Update selection box end position
function SelectionBox:update_position(x, y)
    if self.active then
        self.end_x = x
        self.end_y = y
    end
end

-- End selection box and return bounds
function SelectionBox:finish()
    if not self.active then return nil end

    self.active = false
    local bounds = self:get_bounds()

    Events.emit("SELECTION_BOX_END", bounds.x1, bounds.y1, bounds.x2, bounds.y2)

    return bounds
end

-- Cancel selection without selecting
function SelectionBox:cancel()
    self.active = false
    Events.emit("SELECTION_BOX_CANCEL")
end

-- Check if selection box is active
function SelectionBox:is_active()
    return self.active
end

-- Get normalized bounds (x1 < x2, y1 < y2)
function SelectionBox:get_bounds()
    return {
        x1 = math.min(self.start_x, self.end_x),
        y1 = math.min(self.start_y, self.end_y),
        x2 = math.max(self.start_x, self.end_x),
        y2 = math.max(self.start_y, self.end_y)
    }
end

-- Get width and height
function SelectionBox:get_size()
    local bounds = self:get_bounds()
    return bounds.x2 - bounds.x1, bounds.y2 - bounds.y1
end

-- Check if a point is inside the selection box
function SelectionBox:contains_point(x, y)
    if not self.active then return false end

    local bounds = self:get_bounds()
    return x >= bounds.x1 and x <= bounds.x2 and
           y >= bounds.y1 and y <= bounds.y2
end

-- Check if a rectangle intersects the selection box
function SelectionBox:intersects_rect(rx, ry, rw, rh)
    if not self.active then return false end

    local bounds = self:get_bounds()

    return not (rx > bounds.x2 or
                rx + rw < bounds.x1 or
                ry > bounds.y2 or
                ry + rh < bounds.y1)
end

-- Check if a circle intersects the selection box
function SelectionBox:intersects_circle(cx, cy, radius)
    if not self.active then return false end

    local bounds = self:get_bounds()

    -- Find closest point on box to circle center
    local closest_x = math.max(bounds.x1, math.min(cx, bounds.x2))
    local closest_y = math.max(bounds.y1, math.min(cy, bounds.y2))

    -- Check distance
    local dx = cx - closest_x
    local dy = cy - closest_y
    return (dx * dx + dy * dy) <= (radius * radius)
end

-- Update animation
function SelectionBox:update(dt)
    if self.active then
        self.pulse_timer = self.pulse_timer + dt * self.pulse_speed
    end
end

-- Draw selection box
function SelectionBox:draw()
    if not self.active then return end

    local bounds = self:get_bounds()
    local width = bounds.x2 - bounds.x1
    local height = bounds.y2 - bounds.y1

    -- Skip if too small
    if width < 2 and height < 2 then return end

    -- Pulse effect
    local pulse = 0.5 + 0.5 * math.sin(self.pulse_timer)

    -- Draw filled rectangle
    local fill = self.fill_color
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] * (0.7 + 0.3 * pulse))
    love.graphics.rectangle("fill", bounds.x1, bounds.y1, width, height)

    -- Draw border
    local border = self.border_color
    love.graphics.setColor(border[1], border[2], border[3], border[4])
    love.graphics.setLineWidth(self.border_width)
    love.graphics.rectangle("line", bounds.x1, bounds.y1, width, height)

    -- Draw corner markers
    local corner_size = 4
    love.graphics.setColor(border[1], border[2], border[3], 1)

    -- Top-left
    love.graphics.line(bounds.x1, bounds.y1, bounds.x1 + corner_size, bounds.y1)
    love.graphics.line(bounds.x1, bounds.y1, bounds.x1, bounds.y1 + corner_size)

    -- Top-right
    love.graphics.line(bounds.x2, bounds.y1, bounds.x2 - corner_size, bounds.y1)
    love.graphics.line(bounds.x2, bounds.y1, bounds.x2, bounds.y1 + corner_size)

    -- Bottom-left
    love.graphics.line(bounds.x1, bounds.y2, bounds.x1 + corner_size, bounds.y2)
    love.graphics.line(bounds.x1, bounds.y2, bounds.x1, bounds.y2 - corner_size)

    -- Bottom-right
    love.graphics.line(bounds.x2, bounds.y2, bounds.x2 - corner_size, bounds.y2)
    love.graphics.line(bounds.x2, bounds.y2, bounds.x2, bounds.y2 - corner_size)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Set colors
function SelectionBox:set_fill_color(r, g, b, a)
    self.fill_color = {r, g, b, a or 0.15}
end

function SelectionBox:set_border_color(r, g, b, a)
    self.border_color = {r, g, b, a or 0.8}
end

-- Select entities within box
function SelectionBox:select_entities(entities, add_to_selection)
    if not self.active then return {} end

    local bounds = self:get_bounds()
    local selected = {}

    for _, entity in ipairs(entities) do
        -- Check if entity is within bounds
        local ex = entity.x or 0
        local ey = entity.y or 0
        local ew = entity.width or 24
        local eh = entity.height or 24

        if self:intersects_rect(ex - ew/2, ey - eh/2, ew, eh) then
            -- Check if selectable
            if entity.selectable ~= false then
                table.insert(selected, entity)
            end
        end
    end

    return selected
end

return SelectionBox
