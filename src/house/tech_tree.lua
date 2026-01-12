--[[
    Tech Tree - Building prerequisites and unlock system
    Manages what can be built based on owned structures
    Reference: Original C&C tech tree from data files
]]

local Events = require("src.core.events")

local TechTree = {}
TechTree.__index = TechTree

function TechTree.new(house)
    local self = setmetatable({}, TechTree)

    -- Parent house
    self.house = house

    -- Loaded tech tree data
    self.buildings = {}
    self.units = {}
    self.infantry = {}

    -- Available items (meets prerequisites)
    self.available_buildings = {}
    self.available_units = {}
    self.available_infantry = {}

    -- Side restrictions
    self.side = house and house.side or "GDI"

    return self
end

-- Load tech tree data from JSON files
function TechTree:load_data(buildings_data, units_data, infantry_data)
    self.buildings = buildings_data or {}
    self.units = units_data or {}
    self.infantry = infantry_data or {}

    self:update_available()
end

-- Update available items based on current buildings
function TechTree:update_available()
    self.available_buildings = {}
    self.available_units = {}
    self.available_infantry = {}

    -- Get owned building types
    local owned = {}
    if self.house then
        owned = self.house.owned_building_types
    end

    -- Check buildings
    for building_type, data in pairs(self.buildings) do
        if self:can_build_item(data, owned) then
            self.available_buildings[building_type] = true
        end
    end

    -- Check units
    for unit_type, data in pairs(self.units) do
        if self:can_build_item(data, owned) then
            self.available_units[unit_type] = true
        end
    end

    -- Check infantry
    for infantry_type, data in pairs(self.infantry) do
        if self:can_build_item(data, owned) then
            self.available_infantry[infantry_type] = true
        end
    end

    Events.emit("TECH_TREE_UPDATED", self.house)
end

-- Check if an item can be built
function TechTree:can_build_item(data, owned)
    -- Check side/house restrictions
    if data.house then
        local can_build = false
        for _, allowed_house in ipairs(data.house) do
            if allowed_house == self.side or allowed_house == "GDI" or allowed_house == "NOD" then
                -- Check if this side matches
                if allowed_house == self.side then
                    can_build = true
                    break
                end
                -- GDI units for GDI side
                if allowed_house == "GDI" and self.side == "GDI" then
                    can_build = true
                    break
                end
                -- NOD units for NOD side
                if allowed_house == "NOD" and self.side == "NOD" then
                    can_build = true
                    break
                end
            end
        end
        if not can_build then
            return false
        end
    end

    -- Check tech level
    local tech_level = self.house and self.house.tech_level or 1
    if data.techlevel and data.techlevel > tech_level then
        return false
    end

    -- Check prerequisites
    if data.prerequisite then
        for _, prereq in ipairs(data.prerequisite) do
            if not owned[prereq] or owned[prereq] <= 0 then
                return false
            end
        end
    end

    return true
end

-- Check if a specific building can be built
function TechTree:can_build_building(building_type)
    return self.available_buildings[building_type] == true
end

-- Check if a specific unit can be built
function TechTree:can_build_unit(unit_type)
    return self.available_units[unit_type] == true
end

-- Check if a specific infantry can be built
function TechTree:can_build_infantry(infantry_type)
    return self.available_infantry[infantry_type] == true
end

-- Get all available buildings
function TechTree:get_available_buildings()
    local result = {}
    for building_type, _ in pairs(self.available_buildings) do
        table.insert(result, building_type)
    end
    return result
end

-- Get all available units
function TechTree:get_available_units()
    local result = {}
    for unit_type, _ in pairs(self.available_units) do
        table.insert(result, unit_type)
    end
    return result
end

-- Get all available infantry
function TechTree:get_available_infantry()
    local result = {}
    for infantry_type, _ in pairs(self.available_infantry) do
        table.insert(result, infantry_type)
    end
    return result
end

-- Get building data
function TechTree:get_building_data(building_type)
    return self.buildings[building_type]
end

-- Get unit data
function TechTree:get_unit_data(unit_type)
    return self.units[unit_type]
end

-- Get infantry data
function TechTree:get_infantry_data(infantry_type)
    return self.infantry[infantry_type]
end

-- Get prerequisites for an item
function TechTree:get_prerequisites(item_type)
    local data = self.buildings[item_type] or self.units[item_type] or self.infantry[item_type]
    if data then
        return data.prerequisite or {}
    end
    return {}
end

-- Get missing prerequisites for an item
function TechTree:get_missing_prerequisites(item_type)
    local prereqs = self:get_prerequisites(item_type)
    local missing = {}

    local owned = self.house and self.house.owned_building_types or {}

    for _, prereq in ipairs(prereqs) do
        if not owned[prereq] or owned[prereq] <= 0 then
            table.insert(missing, prereq)
        end
    end

    return missing
end

-- Get cost for an item
function TechTree:get_cost(item_type)
    local data = self.buildings[item_type] or self.units[item_type] or self.infantry[item_type]
    if data then
        return data.cost or 0
    end
    return 0
end

-- Get build time for an item
function TechTree:get_build_time(item_type)
    local data = self.buildings[item_type] or self.units[item_type] or self.infantry[item_type]
    if data then
        return data.build_time or 0
    end
    return 0
end

-- Set side (GDI or NOD)
function TechTree:set_side(side)
    self.side = side
    self:update_available()
end

-- Set tech level
function TechTree:set_tech_level(level)
    if self.house then
        self.house.tech_level = level
    end
    self:update_available()
end

-- Called when a building is added/removed
function TechTree:on_building_changed()
    self:update_available()
end

return TechTree
