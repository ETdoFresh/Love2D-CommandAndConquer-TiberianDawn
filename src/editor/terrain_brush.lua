--[[
    Terrain Brush - Tool for painting terrain in the editor
]]

local Constants = require("src.core.constants")

local TerrainBrush = {}
TerrainBrush.__index = TerrainBrush

-- Brush modes
TerrainBrush.MODE = {
    TERRAIN = "terrain",
    OVERLAY = "overlay",
    ERASE = "erase"
}

-- Terrain types
TerrainBrush.TERRAIN_TYPES = {
    {id = 0, name = "Clear", color = {0.4, 0.6, 0.3}},
    {id = 1, name = "Water", color = {0.2, 0.4, 0.8}},
    {id = 6, name = "Road", color = {0.5, 0.5, 0.5}},
    {id = 11, name = "Rock", color = {0.4, 0.4, 0.4}},
    {id = 21, name = "Cliff", color = {0.3, 0.25, 0.2}},
    {id = 31, name = "Rough", color = {0.45, 0.5, 0.3}}
}

-- Overlay types
TerrainBrush.OVERLAY_TYPES = {
    {id = -1, name = "None", color = {0, 0, 0, 0}},
    {id = 6, name = "Tiberium 1", color = {0.3, 0.8, 0.3}},
    {id = 7, name = "Tiberium 2", color = {0.35, 0.85, 0.35}},
    {id = 8, name = "Tiberium 3", color = {0.4, 0.9, 0.4}},
    {id = 1, name = "Sandbags", color = {0.6, 0.5, 0.3}},
    {id = 2, name = "Chain Link", color = {0.5, 0.5, 0.5}},
    {id = 3, name = "Concrete Wall", color = {0.4, 0.4, 0.4}},
    {id = 4, name = "Barbed Wire", color = {0.3, 0.3, 0.3}}
}

function TerrainBrush.new(grid)
    local self = setmetatable({}, TerrainBrush)

    self.grid = grid
    self.mode = TerrainBrush.MODE.TERRAIN
    self.size = 1  -- Brush size in cells

    self.selected_terrain = 0
    self.selected_overlay = -1

    self.is_painting = false
    self.last_cell_x = nil
    self.last_cell_y = nil

    return self
end

function TerrainBrush:set_mode(mode)
    self.mode = mode
end

function TerrainBrush:set_size(size)
    self.size = math.max(1, math.min(10, size))
end

function TerrainBrush:set_terrain(terrain_id)
    self.selected_terrain = terrain_id
    self.mode = TerrainBrush.MODE.TERRAIN
end

function TerrainBrush:set_overlay(overlay_id)
    self.selected_overlay = overlay_id
    self.mode = TerrainBrush.MODE.OVERLAY
end

function TerrainBrush:start_painting()
    self.is_painting = true
    self.last_cell_x = nil
    self.last_cell_y = nil
end

function TerrainBrush:stop_painting()
    self.is_painting = false
end

function TerrainBrush:paint_at(cell_x, cell_y)
    if not self.grid then
        return
    end

    -- Paint in a square based on brush size
    local half = math.floor((self.size - 1) / 2)

    for dy = -half, half + (self.size - 1) % 2 do
        for dx = -half, half + (self.size - 1) % 2 do
            local cx = cell_x + dx
            local cy = cell_y + dy

            local cell = self.grid:get_cell(cx, cy)
            if cell then
                if self.mode == TerrainBrush.MODE.TERRAIN then
                    cell.template_type = self.selected_terrain
                    cell.template_icon = 0
                elseif self.mode == TerrainBrush.MODE.OVERLAY then
                    cell.overlay = self.selected_overlay
                    cell.overlay_data = 0
                elseif self.mode == TerrainBrush.MODE.ERASE then
                    cell.overlay = -1
                    cell.overlay_data = 0
                end
            end
        end
    end

    self.last_cell_x = cell_x
    self.last_cell_y = cell_y
end

function TerrainBrush:paint_line(from_x, from_y, to_x, to_y)
    -- Bresenham's line algorithm
    local dx = math.abs(to_x - from_x)
    local dy = math.abs(to_y - from_y)
    local sx = from_x < to_x and 1 or -1
    local sy = from_y < to_y and 1 or -1
    local err = dx - dy

    local x, y = from_x, from_y

    while true do
        self:paint_at(x, y)

        if x == to_x and y == to_y then
            break
        end

        local e2 = 2 * err

        if e2 > -dy then
            err = err - dy
            x = x + sx
        end

        if e2 < dx then
            err = err + dx
            y = y + sy
        end
    end
end

function TerrainBrush:get_cursor_cells(cell_x, cell_y)
    local cells = {}
    local half = math.floor((self.size - 1) / 2)

    for dy = -half, half + (self.size - 1) % 2 do
        for dx = -half, half + (self.size - 1) % 2 do
            table.insert(cells, {
                x = cell_x + dx,
                y = cell_y + dy
            })
        end
    end

    return cells
end

function TerrainBrush:draw_cursor(render_system, cell_x, cell_y)
    love.graphics.push()
    love.graphics.scale(render_system.scale, render_system.scale)
    love.graphics.translate(-render_system.camera_x, -render_system.camera_y)

    local cells = self:get_cursor_cells(cell_x, cell_y)

    for _, c in ipairs(cells) do
        local px = c.x * Constants.CELL_PIXEL_W
        local py = c.y * Constants.CELL_PIXEL_H

        -- Draw cursor outline
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.rectangle("line", px, py,
            Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)

        -- Show what will be painted
        if self.mode == TerrainBrush.MODE.TERRAIN then
            local terrain = nil
            for _, t in ipairs(TerrainBrush.TERRAIN_TYPES) do
                if t.id == self.selected_terrain then
                    terrain = t
                    break
                end
            end
            if terrain then
                love.graphics.setColor(terrain.color[1], terrain.color[2], terrain.color[3], 0.3)
                love.graphics.rectangle("fill", px, py,
                    Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
            end
        elseif self.mode == TerrainBrush.MODE.OVERLAY then
            if self.selected_overlay >= 6 and self.selected_overlay <= 17 then
                -- Tiberium
                love.graphics.setColor(0.3, 0.8, 0.3, 0.3)
                love.graphics.rectangle("fill", px, py,
                    Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

return TerrainBrush
