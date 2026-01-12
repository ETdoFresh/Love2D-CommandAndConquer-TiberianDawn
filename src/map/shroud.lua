--[[
    Shroud - Fog of war and shroud rendering
    Handles visibility state per cell with proper edge blending
    Reference: Original C&C fog of war system (MAP.CPP)
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")

local Shroud = {}
Shroud.__index = Shroud

-- Visibility states
Shroud.STATE = {
    HIDDEN = 0,      -- Never seen (black)
    FOGGED = 1,      -- Previously seen (darkened)
    VISIBLE = 2      -- Currently visible (clear)
}

-- Edge patterns for smooth shroud edges (bitflags)
-- Each bit represents a direction: N, NE, E, SE, S, SW, W, NW
Shroud.EDGE = {
    N = 1,
    NE = 2,
    E = 4,
    SE = 8,
    S = 16,
    SW = 32,
    W = 64,
    NW = 128
}

function Shroud.new(width, height)
    local self = setmetatable({}, Shroud)

    -- Map dimensions
    self.width = width or 64
    self.height = height or 64

    -- Visibility state per cell
    self.cells = {}
    for y = 0, self.height - 1 do
        self.cells[y] = {}
        for x = 0, self.width - 1 do
            self.cells[y][x] = Shroud.STATE.HIDDEN
        end
    end

    -- Previous visibility for detecting changes
    self.prev_visible = {}

    -- Cell size in pixels
    self.cell_size = Constants.CELL_SIZE or 24

    -- Shroud image/canvas for efficient rendering
    self.canvas = nil
    self.dirty = true  -- Need to rebuild canvas

    -- Edge sprites for smooth transitions
    self.edge_sprites = {}

    -- Colors
    self.colors = {
        hidden = {0, 0, 0, 1},         -- Full black
        fogged = {0, 0, 0, 0.5},       -- Semi-transparent black
        visible = {0, 0, 0, 0}         -- Transparent
    }

    -- Enable/disable
    self.enabled = true

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function Shroud:register_events()
    Events.on("REVEAL_MAP", function(house)
        self:reveal_all()
    end)

    Events.on("REVEAL_ZONE", function(house, zone_id)
        -- Would need zone definitions to implement
    end)
end

-- Initialize from grid
function Shroud:init_from_grid(grid)
    self.width = grid.width or 64
    self.height = grid.height or 64

    self.cells = {}
    for y = 0, self.height - 1 do
        self.cells[y] = {}
        for x = 0, self.width - 1 do
            self.cells[y][x] = Shroud.STATE.HIDDEN
        end
    end

    self.dirty = true
end

-- Get visibility state of a cell
function Shroud:get_state(x, y)
    if x < 0 or x >= self.width or y < 0 or y >= self.height then
        return Shroud.STATE.HIDDEN
    end

    return self.cells[y][x]
end

-- Set visibility state of a cell
function Shroud:set_state(x, y, state)
    if x < 0 or x >= self.width or y < 0 or y >= self.height then
        return
    end

    local old_state = self.cells[y][x]
    if old_state ~= state then
        self.cells[y][x] = state
        self.dirty = true

        if state == Shroud.STATE.VISIBLE and old_state == Shroud.STATE.HIDDEN then
            Events.emit("CELL_REVEALED", x, y)
        end
    end
end

-- Check if a cell is visible
function Shroud:is_visible(x, y)
    return self:get_state(x, y) == Shroud.STATE.VISIBLE
end

-- Check if a cell has been seen (fogged or visible)
function Shroud:is_revealed(x, y)
    return self:get_state(x, y) ~= Shroud.STATE.HIDDEN
end

-- Reveal a cell (make visible)
function Shroud:reveal(x, y)
    self:set_state(x, y, Shroud.STATE.VISIBLE)
end

-- Fog a cell (previously visible, now not in sight range)
function Shroud:fog(x, y)
    if self:get_state(x, y) == Shroud.STATE.VISIBLE then
        self:set_state(x, y, Shroud.STATE.FOGGED)
    end
end

-- Hide a cell completely (for special cases)
function Shroud:hide(x, y)
    self:set_state(x, y, Shroud.STATE.HIDDEN)
end

-- Reveal cells in a radius around a point
function Shroud:reveal_radius(center_x, center_y, radius)
    local start_x = math.max(0, center_x - radius)
    local end_x = math.min(self.width - 1, center_x + radius)
    local start_y = math.max(0, center_y - radius)
    local end_y = math.min(self.height - 1, center_y + radius)

    local radius_sq = radius * radius

    for y = start_y, end_y do
        for x = start_x, end_x do
            local dx = x - center_x
            local dy = y - center_y
            if dx * dx + dy * dy <= radius_sq then
                self:reveal(x, y)
            end
        end
    end
end

-- Update visibility based on unit sight ranges
-- Call this each frame with current visible cells
function Shroud:begin_visibility_update()
    -- Store current visible cells
    self.prev_visible = {}

    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            if self.cells[y][x] == Shroud.STATE.VISIBLE then
                self.prev_visible[y * self.width + x] = true
                -- Move to fogged state
                self.cells[y][x] = Shroud.STATE.FOGGED
            end
        end
    end
end

function Shroud:end_visibility_update()
    -- Any cell that was visible and is now fogged needs marking dirty
    self.dirty = true
end

-- Mark a cell as currently visible (call during visibility update)
function Shroud:mark_visible(x, y)
    if x >= 0 and x < self.width and y >= 0 and y < self.height then
        if self.cells[y][x] ~= Shroud.STATE.VISIBLE then
            self.cells[y][x] = Shroud.STATE.VISIBLE
            self.dirty = true
        end
    end
end

-- Reveal entire map
function Shroud:reveal_all()
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            self.cells[y][x] = Shroud.STATE.VISIBLE
        end
    end
    self.dirty = true
    Events.emit("MAP_REVEALED")
end

-- Reset to all hidden
function Shroud:reset()
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            self.cells[y][x] = Shroud.STATE.HIDDEN
        end
    end
    self.dirty = true
end

-- Get edge pattern for a cell (for smooth edge rendering)
function Shroud:get_edge_pattern(x, y, state)
    local pattern = 0

    -- Check all 8 neighbors
    local neighbors = {
        {0, -1, Shroud.EDGE.N},
        {1, -1, Shroud.EDGE.NE},
        {1, 0, Shroud.EDGE.E},
        {1, 1, Shroud.EDGE.SE},
        {0, 1, Shroud.EDGE.S},
        {-1, 1, Shroud.EDGE.SW},
        {-1, 0, Shroud.EDGE.W},
        {-1, -1, Shroud.EDGE.NW}
    }

    for _, n in ipairs(neighbors) do
        local nx, ny, bit = x + n[1], y + n[2], n[3]
        local neighbor_state = self:get_state(nx, ny)

        -- Set bit if neighbor is more visible than this cell
        if neighbor_state > state then
            pattern = pattern + bit
        end
    end

    return pattern
end

-- Build canvas for efficient rendering
function Shroud:build_canvas()
    if not self.dirty then return end

    -- Create canvas if needed
    local canvas_width = self.width * self.cell_size
    local canvas_height = self.height * self.cell_size

    if not self.canvas or
       self.canvas:getWidth() ~= canvas_width or
       self.canvas:getHeight() ~= canvas_height then
        self.canvas = love.graphics.newCanvas(canvas_width, canvas_height)
    end

    -- Render shroud to canvas
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 0)

    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local state = self.cells[y][x]
            local px = x * self.cell_size
            local py = y * self.cell_size

            if state == Shroud.STATE.HIDDEN then
                love.graphics.setColor(self.colors.hidden)
                love.graphics.rectangle("fill", px, py, self.cell_size, self.cell_size)
            elseif state == Shroud.STATE.FOGGED then
                love.graphics.setColor(self.colors.fogged)
                love.graphics.rectangle("fill", px, py, self.cell_size, self.cell_size)
            end
            -- VISIBLE cells are transparent, nothing to draw
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    self.dirty = false
end

-- Draw shroud overlay
function Shroud:draw(camera_x, camera_y, scale)
    if not self.enabled then return end

    camera_x = camera_x or 0
    camera_y = camera_y or 0
    scale = scale or 1

    -- Rebuild canvas if dirty
    self:build_canvas()

    if self.canvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.canvas, -camera_x * scale, -camera_y * scale, 0, scale, scale)
    end
end

-- Draw shroud directly (without canvas, for debugging)
function Shroud:draw_direct(camera_x, camera_y, scale)
    if not self.enabled then return end

    camera_x = camera_x or 0
    camera_y = camera_y or 0
    scale = scale or 1

    -- Calculate visible range
    local screen_w, screen_h = love.graphics.getDimensions()
    local start_x = math.max(0, math.floor(camera_x / self.cell_size))
    local start_y = math.max(0, math.floor(camera_y / self.cell_size))
    local end_x = math.min(self.width - 1, math.ceil((camera_x + screen_w / scale) / self.cell_size))
    local end_y = math.min(self.height - 1, math.ceil((camera_y + screen_h / scale) / self.cell_size))

    for y = start_y, end_y do
        for x = start_x, end_x do
            local state = self.cells[y][x]
            local px = (x * self.cell_size - camera_x) * scale
            local py = (y * self.cell_size - camera_y) * scale
            local size = self.cell_size * scale

            if state == Shroud.STATE.HIDDEN then
                love.graphics.setColor(self.colors.hidden)
                love.graphics.rectangle("fill", px, py, size, size)
            elseif state == Shroud.STATE.FOGGED then
                love.graphics.setColor(self.colors.fogged)
                love.graphics.rectangle("fill", px, py, size, size)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw minimap shroud
function Shroud:draw_minimap(x, y, width, height)
    if not self.enabled then return end

    local scale_x = width / self.width
    local scale_y = height / self.height

    for cy = 0, self.height - 1 do
        for cx = 0, self.width - 1 do
            local state = self.cells[cy][cx]

            if state == Shroud.STATE.HIDDEN then
                love.graphics.setColor(0, 0, 0, 1)
                love.graphics.rectangle("fill",
                    x + cx * scale_x,
                    y + cy * scale_y,
                    math.ceil(scale_x),
                    math.ceil(scale_y)
                )
            elseif state == Shroud.STATE.FOGGED then
                love.graphics.setColor(0, 0, 0, 0.5)
                love.graphics.rectangle("fill",
                    x + cx * scale_x,
                    y + cy * scale_y,
                    math.ceil(scale_x),
                    math.ceil(scale_y)
                )
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Set fog color
function Shroud:set_fog_alpha(alpha)
    self.colors.fogged[4] = alpha
    self.dirty = true
end

-- Enable/disable shroud
function Shroud:set_enabled(enabled)
    self.enabled = enabled
end

-- Serialize for save/load
function Shroud:serialize()
    local data = {
        width = self.width,
        height = self.height,
        cells = {}
    }

    -- Store only non-hidden cells to save space
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local state = self.cells[y][x]
            if state ~= Shroud.STATE.HIDDEN then
                table.insert(data.cells, {x = x, y = y, state = state})
            end
        end
    end

    return data
end

-- Deserialize
function Shroud:deserialize(data)
    self.width = data.width
    self.height = data.height

    -- Reset all to hidden
    self.cells = {}
    for y = 0, self.height - 1 do
        self.cells[y] = {}
        for x = 0, self.width - 1 do
            self.cells[y][x] = Shroud.STATE.HIDDEN
        end
    end

    -- Restore saved states
    for _, cell in ipairs(data.cells) do
        self.cells[cell.y][cell.x] = cell.state
    end

    self.dirty = true
end

-- Get statistics
function Shroud:get_stats()
    local hidden = 0
    local fogged = 0
    local visible = 0

    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local state = self.cells[y][x]
            if state == Shroud.STATE.HIDDEN then
                hidden = hidden + 1
            elseif state == Shroud.STATE.FOGGED then
                fogged = fogged + 1
            else
                visible = visible + 1
            end
        end
    end

    return {
        hidden = hidden,
        fogged = fogged,
        visible = visible,
        total = self.width * self.height,
        explored_percent = math.floor((fogged + visible) / (self.width * self.height) * 100)
    }
end

return Shroud
