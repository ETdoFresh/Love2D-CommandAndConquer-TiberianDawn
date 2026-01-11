--[[
    Grid - 2D grid of map cells
    Standard size: 64x64 cells
]]

local Constants = require("src.core.constants")
local Cell = require("src.map.cell")

local Grid = {}
Grid.__index = Grid

-- Create a new grid
function Grid.new(width, height)
    local self = setmetatable({}, Grid)

    self.width = width or Constants.MAP_CELL_W
    self.height = height or Constants.MAP_CELL_H
    self.cells = {}

    -- Initialize all cells
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local index = y * self.width + x
            self.cells[index] = Cell.new(x, y)
        end
    end

    return self
end

-- Initialize/resize the grid to new dimensions
function Grid:init(width, height)
    self.width = width or self.width
    self.height = height or self.height
    self.cells = {}

    -- Initialize all cells
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local index = y * self.width + x
            self.cells[index] = Cell.new(x, y)
        end
    end
end

-- Check if coordinates are valid
function Grid:is_valid(x, y)
    return x >= 0 and x < self.width and y >= 0 and y < self.height
end

-- Get cell at coordinates
function Grid:get_cell(x, y)
    if not self:is_valid(x, y) then
        return nil
    end
    local index = y * self.width + x
    return self.cells[index]
end

-- Get cell by cell number
function Grid:get_cell_by_number(cell_number)
    return self.cells[cell_number]
end

-- Convert lepton coordinates to cell coordinates
function Grid:lepton_to_cell(lx, ly)
    local cx = math.floor(lx / Constants.LEPTON_PER_CELL)
    local cy = math.floor(ly / Constants.LEPTON_PER_CELL)
    return cx, cy
end

-- Convert pixel coordinates to cell coordinates
function Grid:pixel_to_cell(px, py)
    local cx = math.floor(px / Constants.CELL_PIXEL_W)
    local cy = math.floor(py / Constants.CELL_PIXEL_H)
    return cx, cy
end

-- Convert cell coordinates to lepton coordinates (center of cell)
function Grid:cell_to_lepton(cx, cy)
    local lx = cx * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
    local ly = cy * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
    return lx, ly
end

-- Convert cell coordinates to pixel coordinates (top-left of cell)
function Grid:cell_to_pixel(cx, cy)
    return cx * Constants.CELL_PIXEL_W, cy * Constants.CELL_PIXEL_H
end

-- Get adjacent cell
function Grid:get_adjacent(x, y, direction)
    local offsets = {
        [0] = {0, -1},   -- N
        [1] = {1, -1},   -- NE
        [2] = {1, 0},    -- E
        [3] = {1, 1},    -- SE
        [4] = {0, 1},    -- S
        [5] = {-1, 1},   -- SW
        [6] = {-1, 0},   -- W
        [7] = {-1, -1}   -- NW
    }

    local offset = offsets[direction]
    if not offset then return nil end

    return self:get_cell(x + offset[1], y + offset[2])
end

-- Get all adjacent cells
function Grid:get_neighbors(x, y)
    local neighbors = {}
    for dir = 0, 7 do
        local cell = self:get_adjacent(x, y, dir)
        if cell then
            table.insert(neighbors, cell)
        end
    end
    return neighbors
end

-- Get cells in a rectangular region
function Grid:get_cells_in_rect(x1, y1, x2, y2)
    local cells = {}

    -- Normalize bounds
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end

    -- Clamp to grid bounds
    x1 = math.max(0, x1)
    y1 = math.max(0, y1)
    x2 = math.min(self.width - 1, x2)
    y2 = math.min(self.height - 1, y2)

    for y = y1, y2 do
        for x = x1, x2 do
            local cell = self:get_cell(x, y)
            if cell then
                table.insert(cells, cell)
            end
        end
    end

    return cells
end

-- Get cells in a circular region
function Grid:get_cells_in_radius(center_x, center_y, radius)
    local cells = {}
    local r_sq = radius * radius

    local x1 = math.floor(center_x - radius)
    local x2 = math.ceil(center_x + radius)
    local y1 = math.floor(center_y - radius)
    local y2 = math.ceil(center_y + radius)

    for y = y1, y2 do
        for x = x1, x2 do
            local dx = x - center_x
            local dy = y - center_y
            if dx * dx + dy * dy <= r_sq then
                local cell = self:get_cell(x, y)
                if cell then
                    table.insert(cells, cell)
                end
            end
        end
    end

    return cells
end

-- Set terrain for a cell
function Grid:set_terrain(x, y, template_type, template_icon)
    local cell = self:get_cell(x, y)
    if cell then
        cell.template_type = template_type
        cell.template_icon = template_icon
    end
end

-- Set overlay for a cell
function Grid:set_overlay(x, y, overlay_type, overlay_data)
    local cell = self:get_cell(x, y)
    if cell then
        cell.overlay = overlay_type
        cell.overlay_data = overlay_data or 0
    end
end

-- Clear all visibility for a house
function Grid:clear_visibility(house)
    for _, cell in pairs(self.cells) do
        cell:set_visible(house, false)
    end
end

-- Reveal area around a point
function Grid:reveal_area(center_x, center_y, radius, house)
    local cells = self:get_cells_in_radius(center_x, center_y, radius)
    for _, cell in ipairs(cells) do
        cell:set_visible(house, true)
    end
end

-- Check if a building can be placed
function Grid:can_place_building(x, y, width, height, house, require_adjacent)
    -- First check if all cells are clear
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            local cell = self:get_cell(x + dx, y + dy)
            if not cell then
                return false, "Out of bounds"
            end
            if cell:has_flag_set(Cell.FLAG.BUILDING) then
                return false, "Cell occupied by building"
            end
            if cell:has_flag_set(Cell.FLAG.VEHICLE) then
                return false, "Cell occupied by vehicle"
            end
            -- Check for tiberium (can't build on tiberium)
            if cell:has_tiberium() then
                return false, "Cannot build on Tiberium"
            end
        end
    end

    -- Check adjacency to friendly buildings (if required)
    if require_adjacent then
        local is_adjacent = false

        -- Check all cells around the building footprint
        for dy = -1, height do
            for dx = -1, width do
                -- Skip interior cells
                if dx >= 0 and dx < width and dy >= 0 and dy < height then
                    goto continue
                end

                local cell = self:get_cell(x + dx, y + dy)
                if cell and cell:has_flag_set(Cell.FLAG.BUILDING) then
                    -- Found adjacent building - check owner
                    if cell.owner == house or cell.owner == -1 then
                        is_adjacent = true
                        break
                    end
                end
                ::continue::
            end
            if is_adjacent then break end
        end

        if not is_adjacent then
            return false, "Must place adjacent to existing buildings"
        end
    end

    return true
end

-- Place a building (mark cells)
function Grid:place_building(x, y, width, height, entity_id, house)
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            local cell = self:get_cell(x + dx, y + dy)
            if cell then
                cell:set_flag(Cell.FLAG.BUILDING)
                cell.occupier = entity_id
                cell.owner = house or -1
            end
        end
    end
end

-- Remove a building (clear cells)
function Grid:remove_building(x, y, width, height)
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            local cell = self:get_cell(x + dx, y + dy)
            if cell then
                cell:clear_flag(Cell.FLAG.BUILDING)
                cell.occupier = nil
            end
        end
    end
end

-- Iterate over all cells
function Grid:iterate()
    local index = -1
    local max_index = self.width * self.height - 1

    return function()
        index = index + 1
        if index <= max_index then
            return self.cells[index]
        end
        return nil
    end
end

-- Serialize grid state
function Grid:serialize()
    local data = {
        width = self.width,
        height = self.height,
        cells = {}
    }

    for i, cell in pairs(self.cells) do
        data.cells[i] = cell:serialize()
    end

    return data
end

-- Deserialize grid state
function Grid:deserialize(data)
    self.width = data.width
    self.height = data.height

    for i, cell_data in pairs(data.cells) do
        local cell = self.cells[i]
        if cell then
            cell:deserialize(cell_data)
        end
    end
end

return Grid
