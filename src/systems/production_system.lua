--[[
    Production System - Building units and structures
    Reference: FACTORY.H, HOUSE.H
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")
local Component = require("src.ecs.component")

local ProductionSystem = setmetatable({}, {__index = System})
ProductionSystem.__index = ProductionSystem

function ProductionSystem.new()
    local self = System.new("production", {"production"})
    setmetatable(self, ProductionSystem)

    -- Unit and building data
    self.unit_data = {}
    self.building_data = {}

    -- Production queues per house
    self.queues = {}  -- house_id -> {infantry = {}, vehicle = {}, aircraft = {}, building = {}}

    return self
end

function ProductionSystem:init()
    self:load_data()
end

function ProductionSystem:load_data()
    local Serialize = require("src.util.serialize")

    -- Load infantry
    local infantry = Serialize.load_json("data/units/infantry.json")
    if infantry then
        for name, data in pairs(infantry) do
            data.type = "infantry"
            self.unit_data[name] = data
        end
    end

    -- Load vehicles
    local vehicles = Serialize.load_json("data/units/vehicles.json")
    if vehicles then
        for name, data in pairs(vehicles) do
            data.type = "vehicle"
            self.unit_data[name] = data
        end
    end

    -- Load aircraft
    local aircraft = Serialize.load_json("data/units/aircraft.json")
    if aircraft then
        for name, data in pairs(aircraft) do
            data.type = "aircraft"
            self.unit_data[name] = data
        end
    end

    -- Load buildings
    local buildings = Serialize.load_json("data/buildings/structures.json")
    if buildings then
        for name, data in pairs(buildings) do
            data.type = "building"
            self.building_data[name] = data
        end
    end
end

function ProductionSystem:update(dt, entities)
    -- Update production for each producing entity
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end
end

function ProductionSystem:process_entity(dt, entity)
    local production = entity:get("production")

    -- Check if there's something in the queue
    if #production.queue == 0 then
        return
    end

    local item = production.queue[1]

    -- Update progress
    production.progress = production.progress + (100 / (item.build_time * Constants.TICKS_PER_SECOND))

    -- Check if complete
    if production.progress >= 100 then
        production.progress = 100

        -- For units, spawn the unit
        if item.factory_type ~= "building" then
            self:spawn_unit(entity, item)
        else
            -- For buildings, mark as ready to place
            production.ready_to_place = true
            production.placing_type = item.name
        end

        -- Remove from queue
        table.remove(production.queue, 1)

        -- Reset progress
        production.progress = 0

        -- Emit completion event
        self:emit(Events.EVENTS.PRODUCTION_COMPLETE, entity, item)
    end
end

function ProductionSystem:spawn_unit(factory, item)
    local factory_transform = factory:get("transform")
    local factory_owner = factory:get("owner")

    if not factory_transform or not factory_owner then
        return nil
    end

    -- Find spawn location (next to factory)
    local spawn_x = factory_transform.x + Constants.LEPTON_PER_CELL
    local spawn_y = factory_transform.y + Constants.LEPTON_PER_CELL

    -- Create the unit
    local unit = self:create_unit(item.name, factory_owner.house, spawn_x, spawn_y)

    if unit then
        self.world:add_entity(unit)
        return unit
    end

    return nil
end

-- Get color for a house/faction
function ProductionSystem:get_house_color(house)
    if house == Constants.HOUSE.GOOD then
        return {0.9, 0.8, 0.2, 1}  -- GDI Gold/Yellow
    elseif house == Constants.HOUSE.BAD then
        return {0.8, 0.2, 0.2, 1}  -- NOD Red
    elseif house == Constants.HOUSE.NEUTRAL then
        return {0.6, 0.6, 0.6, 1}  -- Neutral Gray
    elseif house == Constants.HOUSE.MULTI1 then
        return {0.2, 0.6, 0.9, 1}  -- Blue
    elseif house == Constants.HOUSE.MULTI2 then
        return {0.2, 0.8, 0.2, 1}  -- Green
    elseif house == Constants.HOUSE.MULTI3 then
        return {0.9, 0.5, 0.1, 1}  -- Orange
    elseif house == Constants.HOUSE.MULTI4 then
        return {0.6, 0.2, 0.8, 1}  -- Purple
    elseif house == Constants.HOUSE.MULTI5 then
        return {0.2, 0.8, 0.8, 1}  -- Cyan
    elseif house == Constants.HOUSE.MULTI6 then
        return {0.8, 0.4, 0.6, 1}  -- Pink
    else
        return {1, 1, 1, 1}  -- Default white
    end
end

function ProductionSystem:create_unit(unit_type, house, x, y)
    local data = self.unit_data[unit_type]
    if not data then
        print("WARNING: Unknown unit type: " .. tostring(unit_type))
        return nil
    end

    local entity = require("src.ecs.entity").new()

    -- Transform
    entity:add("transform", Component.create("transform", {
        x = x,
        y = y,
        cell_x = math.floor(x / Constants.LEPTON_PER_CELL),
        cell_y = math.floor(y / Constants.LEPTON_PER_CELL),
        facing = 0
    }))

    -- Renderable with house color
    local color = self:get_house_color(house)
    print(string.format("Creating unit %s for house %s, color: r=%.1f g=%.1f b=%.1f",
        unit_type, tostring(house), color[1], color[2], color[3]))
    entity:add("renderable", Component.create("renderable", {
        visible = true,
        layer = Constants.LAYER.GROUND,
        sprite = data.sprite,
        color = color
    }))

    -- Selectable
    entity:add("selectable", Component.create("selectable"))

    -- Health
    entity:add("health", Component.create("health", {
        hp = data.hitpoints,
        max_hp = data.hitpoints,
        armor = data.armor
    }))

    -- Owner
    entity:add("owner", Component.create("owner", {
        house = house
    }))

    -- Mobile (for units)
    if data.speed then
        entity:add("mobile", Component.create("mobile", {
            speed = data.speed,
            locomotor = data.type == "infantry" and "foot" or
                        (data.type == "aircraft" and "fly" or "track")
        }))
    end

    -- Combat
    if data.primary_weapon then
        entity:add("combat", Component.create("combat", {
            primary_weapon = data.primary_weapon,
            secondary_weapon = data.secondary_weapon,
            attack_range = data.sight or 4,
            ammo = data.ammo or -1
        }))
    end

    -- Mission (AI)
    entity:add("mission", Component.create("mission", {
        mission_type = Constants.MISSION.GUARD
    }))

    -- Type-specific components
    if data.type == "infantry" then
        entity:add("infantry", Component.create("infantry", {
            infantry_type = unit_type,
            can_capture = data.can_capture or false
        }))
        entity:add_tag("infantry")
    elseif data.type == "vehicle" then
        entity:add("vehicle", Component.create("vehicle", {
            vehicle_type = unit_type
        }))
        entity:add_tag("vehicle")

        if data.turret then
            entity:add("turret", Component.create("turret"))
        end

        if data.harvester then
            entity:add("harvester", Component.create("harvester"))
        end

        if data.transport then
            entity:add("cargo", Component.create("cargo", {
                capacity = data.passengers or 5
            }))
        end

        if data.cloakable then
            entity:add("cloakable", Component.create("cloakable"))
        end
    elseif data.type == "aircraft" then
        entity:add("aircraft", Component.create("aircraft", {
            aircraft_type = unit_type,
            ammo = data.ammo or -1
        }))
        entity:add_tag("aircraft")
    end

    entity:add_tag("unit")

    return entity
end

function ProductionSystem:create_building(building_type, house, cell_x, cell_y)
    local data = self.building_data[building_type]
    if not data then
        print("WARNING: Unknown building type: " .. tostring(building_type))
        return nil
    end
    local color = self:get_house_color(house)
    print(string.format("Creating building %s for house %s at (%d,%d), color: r=%.1f g=%.1f b=%.1f",
        building_type, tostring(house), cell_x, cell_y, color[1], color[2], color[3]))

    local entity = require("src.ecs.entity").new()

    local x = cell_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
    local y = cell_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2

    -- Transform
    entity:add("transform", Component.create("transform", {
        x = x,
        y = y,
        cell_x = cell_x,
        cell_y = cell_y,
        facing = 0
    }))

    -- Renderable with house color
    local color = self:get_house_color(house)
    entity:add("renderable", Component.create("renderable", {
        visible = true,
        layer = Constants.LAYER.GROUND,
        sprite = data.sprite,
        scale_x = data.size[1],
        scale_y = data.size[2],
        color = color
    }))

    -- Selectable
    entity:add("selectable", Component.create("selectable"))

    -- Health
    entity:add("health", Component.create("health", {
        hp = data.hitpoints,
        max_hp = data.hitpoints,
        armor = data.armor
    }))

    -- Owner
    entity:add("owner", Component.create("owner", {
        house = house
    }))

    -- Building specific
    entity:add("building", Component.create("building", {
        structure_type = building_type,
        size_x = data.size[1],
        size_y = data.size[2],
        bibbed = data.bibbed or false
    }))

    -- Power
    if data.power then
        entity:add("power", Component.create("power", {
            produces = data.power > 0 and data.power or 0,
            consumes = data.power < 0 and -data.power or 0
        }))
    end

    -- Production capability
    if data.factory then
        entity:add("production", Component.create("production", {
            factory_type = data.factory,
            is_primary = data.primary or false
        }))
    end

    -- Combat (for defensive structures)
    if data.primary_weapon then
        entity:add("combat", Component.create("combat", {
            primary_weapon = data.primary_weapon,
            attack_range = 5
        }))

        if data.turret then
            entity:add("turret", Component.create("turret"))
        end
    end

    entity:add_tag("building")

    return entity
end

-- Queue a unit for production
function ProductionSystem:queue_unit(factory, unit_type)
    if not factory:has("production") then
        return false, "Not a factory"
    end

    local production = factory:get("production")
    local factory_owner = factory:get("owner")

    local data = self.unit_data[unit_type]
    if not data then
        return false, "Unknown unit type"
    end

    -- Check if this factory can build this unit type
    if data.type ~= production.factory_type then
        return false, "Wrong factory type"
    end

    -- Check if house can build it
    if data.house then
        local house_name = factory_owner.house == Constants.HOUSE.GOOD and "GDI" or "NOD"
        local can_build = false
        for _, h in ipairs(data.house) do
            if h == house_name then
                can_build = true
                break
            end
        end
        if not can_build then
            return false, "House cannot build this unit"
        end
    end

    -- Add to queue (single-item queue in original)
    if #production.queue > 0 then
        return false, "Already building"
    end

    table.insert(production.queue, {
        name = unit_type,
        data = data,
        build_time = data.build_time,
        cost = data.cost,
        factory_type = production.factory_type
    })

    self:emit(Events.EVENTS.PRODUCTION_START, factory, unit_type)
    return true
end

-- Queue a building for production
function ProductionSystem:queue_building(construction_yard, building_type)
    if not construction_yard:has("production") then
        return false, "Not a construction yard"
    end

    local production = construction_yard:get("production")
    local owner = construction_yard:get("owner")

    local data = self.building_data[building_type]
    if not data then
        return false, "Unknown building type"
    end

    -- Check if house can build it
    if data.house then
        local house_name = owner.house == Constants.HOUSE.GOOD and "GDI" or "NOD"
        local can_build = false
        for _, h in ipairs(data.house) do
            if h == house_name then
                can_build = true
                break
            end
        end
        if not can_build then
            return false, "House cannot build this structure"
        end
    end

    -- Single item queue
    if #production.queue > 0 then
        return false, "Already building"
    end

    table.insert(production.queue, {
        name = building_type,
        data = data,
        build_time = data.build_time,
        cost = data.cost,
        factory_type = "building"
    })

    self:emit(Events.EVENTS.PRODUCTION_START, construction_yard, building_type)
    return true
end

-- Cancel production
function ProductionSystem:cancel_production(factory)
    if not factory:has("production") then
        return false
    end

    local production = factory:get("production")

    if #production.queue > 0 then
        local cancelled = table.remove(production.queue, 1)
        production.progress = 0
        production.ready_to_place = false
        production.placing_type = nil

        self:emit(Events.EVENTS.PRODUCTION_CANCEL, factory, cancelled)
        return true
    end

    return false
end

-- Place a building
function ProductionSystem:place_building(construction_yard, cell_x, cell_y, grid)
    if not construction_yard:has("production") then
        return nil, "Not a construction yard"
    end

    local production = construction_yard:get("production")
    local owner = construction_yard:get("owner")

    if not production.ready_to_place or not production.placing_type then
        return nil, "Nothing ready to place"
    end

    local building_type = production.placing_type
    local data = self.building_data[building_type]

    if not data then
        return nil, "Unknown building type"
    end

    -- Check placement validity
    if grid then
        local can_place, reason = grid:can_place_building(
            cell_x, cell_y,
            data.size[1], data.size[2],
            owner.house
        )
        if not can_place then
            return nil, reason
        end
    end

    -- Create the building
    local building = self:create_building(building_type, owner.house, cell_x, cell_y)

    if building then
        self.world:add_entity(building)

        -- Mark cells as occupied
        if grid then
            grid:place_building(cell_x, cell_y, data.size[1], data.size[2], building.id)
        end

        -- Clear production state
        production.ready_to_place = false
        production.placing_type = nil

        self:emit(Events.EVENTS.BUILDING_PLACED, building)

        return building
    end

    return nil, "Failed to create building"
end

-- Get production progress (0-100)
function ProductionSystem:get_progress(factory)
    if not factory:has("production") then
        return 0
    end
    return factory:get("production").progress
end

-- Get what's being built
function ProductionSystem:get_building_item(factory)
    if not factory:has("production") then
        return nil
    end

    local production = factory:get("production")
    if #production.queue > 0 then
        return production.queue[1]
    end
    return nil
end

-- Get available units for a factory
function ProductionSystem:get_available_units(factory)
    if not factory:has("production") or not factory:has("owner") then
        return {}
    end

    local production = factory:get("production")
    local owner = factory:get("owner")
    local house_name = owner.house == Constants.HOUSE.GOOD and "GDI" or "NOD"

    local available = {}

    for name, data in pairs(self.unit_data) do
        if data.type == production.factory_type then
            -- Check house
            if data.house then
                for _, h in ipairs(data.house) do
                    if h == house_name then
                        table.insert(available, {name = name, data = data})
                        break
                    end
                end
            end
        end
    end

    return available
end

-- Get available buildings for a construction yard
function ProductionSystem:get_available_buildings(construction_yard)
    if not construction_yard:has("owner") then
        return {}
    end

    local owner = construction_yard:get("owner")
    local house_name = owner.house == Constants.HOUSE.GOOD and "GDI" or "NOD"

    local available = {}

    for name, data in pairs(self.building_data) do
        -- Check house
        if data.house then
            for _, h in ipairs(data.house) do
                if h == house_name then
                    table.insert(available, {name = name, data = data})
                    break
                end
            end
        end
    end

    return available
end

return ProductionSystem
