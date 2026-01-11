--[[
    Unit Placer - Tool for placing units and buildings in the editor
]]

local Constants = require("src.core.constants")

local UnitPlacer = {}
UnitPlacer.__index = UnitPlacer

function UnitPlacer.new(world, production_system)
    local self = setmetatable({}, UnitPlacer)

    self.world = world
    self.production_system = production_system

    -- Currently selected item
    self.selected_type = nil
    self.selected_category = nil  -- "infantry", "vehicle", "aircraft", "building"
    self.selected_house = Constants.HOUSE.GOOD

    -- Placement preview
    self.preview_x = 0
    self.preview_y = 0
    self.can_place = false

    return self
end

function UnitPlacer:select_unit(unit_type, category)
    self.selected_type = unit_type
    self.selected_category = category
end

function UnitPlacer:select_building(building_type)
    self.selected_type = building_type
    self.selected_category = "building"
end

function UnitPlacer:set_house(house)
    self.selected_house = house
end

function UnitPlacer:clear_selection()
    self.selected_type = nil
    self.selected_category = nil
end

function UnitPlacer:update_preview(cell_x, cell_y, grid)
    self.preview_x = cell_x
    self.preview_y = cell_y

    -- Check if placement is valid
    self.can_place = self:check_placement(cell_x, cell_y, grid)
end

function UnitPlacer:check_placement(cell_x, cell_y, grid)
    if not self.selected_type then
        return false
    end

    if not grid then
        return true  -- Allow placement without grid check
    end

    local cell = grid:get_cell(cell_x, cell_y)
    if not cell then
        return false
    end

    if self.selected_category == "building" then
        -- Get building size
        local data = self.production_system and
                     self.production_system.building_data[self.selected_type]
        local size_x = data and data.size[1] or 1
        local size_y = data and data.size[2] or 1

        local can_place, _ = grid:can_place_building(
            cell_x, cell_y, size_x, size_y, self.selected_house)
        return can_place
    else
        -- Units can be placed on passable terrain
        return cell:is_passable("track")
    end
end

function UnitPlacer:place(cell_x, cell_y, grid)
    if not self.selected_type or not self.can_place then
        return nil
    end

    local entity = nil

    if self.selected_category == "building" then
        -- Place building
        if self.production_system then
            entity = self.production_system:create_building(
                self.selected_type,
                self.selected_house,
                cell_x, cell_y
            )

            if entity and grid then
                local data = self.production_system.building_data[self.selected_type]
                local size_x = data and data.size[1] or 1
                local size_y = data and data.size[2] or 1
                grid:place_building(cell_x, cell_y, size_x, size_y, entity.id)
            end
        end
    else
        -- Place unit
        if self.production_system then
            local x = cell_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
            local y = cell_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2

            entity = self.production_system:create_unit(
                self.selected_type,
                self.selected_house,
                x, y
            )
        end
    end

    if entity then
        self.world:add_entity(entity)
    end

    return entity
end

function UnitPlacer:draw_preview(render_system)
    if not self.selected_type then
        return
    end

    love.graphics.push()
    love.graphics.scale(render_system.scale, render_system.scale)
    love.graphics.translate(-render_system.camera_x, -render_system.camera_y)

    local px = self.preview_x * Constants.CELL_PIXEL_W
    local py = self.preview_y * Constants.CELL_PIXEL_H

    -- Get size
    local size_x = 1
    local size_y = 1

    if self.selected_category == "building" and self.production_system then
        local data = self.production_system.building_data[self.selected_type]
        if data then
            size_x = data.size[1]
            size_y = data.size[2]
        end
    end

    local w = size_x * Constants.CELL_PIXEL_W
    local h = size_y * Constants.CELL_PIXEL_H

    -- Draw placement preview
    if self.can_place then
        love.graphics.setColor(0, 1, 0, 0.3)
    else
        love.graphics.setColor(1, 0, 0, 0.3)
    end
    love.graphics.rectangle("fill", px, py, w, h)

    -- Draw outline
    if self.can_place then
        love.graphics.setColor(0, 1, 0, 1)
    else
        love.graphics.setColor(1, 0, 0, 1)
    end
    love.graphics.rectangle("line", px, py, w, h)

    -- Draw type name
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(self.selected_type, px + 2, py + 2)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Get available units for the palette
function UnitPlacer:get_available_units()
    if not self.production_system then
        return {}
    end

    local units = {}

    for name, data in pairs(self.production_system.unit_data) do
        table.insert(units, {
            name = name,
            type = data.type,
            cost = data.cost,
            house = data.house
        })
    end

    -- Sort by type then name
    table.sort(units, function(a, b)
        if a.type ~= b.type then
            return a.type < b.type
        end
        return a.name < b.name
    end)

    return units
end

-- Get available buildings for the palette
function UnitPlacer:get_available_buildings()
    if not self.production_system then
        return {}
    end

    local buildings = {}

    for name, data in pairs(self.production_system.building_data) do
        table.insert(buildings, {
            name = name,
            cost = data.cost,
            size = data.size,
            house = data.house
        })
    end

    -- Sort by name
    table.sort(buildings, function(a, b)
        return a.name < b.name
    end)

    return buildings
end

return UnitPlacer
