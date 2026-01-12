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

-- Unit limits from original C&C (DEFINES.H)
-- UNIT_MAX = 500, EACH_UNIT_MAX = 500/4 = 125
-- BUILDING_MAX = 500, EACH_BUILDING_MAX = 500/4 = 125
ProductionSystem.DEFAULT_MAX_UNITS = 125
ProductionSystem.DEFAULT_MAX_BUILDINGS = 125
ProductionSystem.DEFAULT_MAX_INFANTRY = 125  -- From RA AI extension
ProductionSystem.DEFAULT_MAX_AIRCRAFT = 100

function ProductionSystem.new()
    local self = System.new("production", {"production"})
    setmetatable(self, ProductionSystem)

    -- Unit and building data
    self.unit_data = {}
    self.building_data = {}
    self.weapon_data = {}  -- Weapon data for attack range lookup

    -- Production queues per house
    self.queues = {}  -- house_id -> {infantry = {}, vehicle = {}, aircraft = {}, building = {}}

    -- Primary factory tracking per house per factory type (original C&C behavior)
    -- Units spawn from primary factory, others can queue but don't spawn
    self.primary_factories = {}  -- house_id -> {infantry = entity_id, vehicle = entity_id, aircraft = entity_id}

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

    -- Load weapon data for attack range lookup
    local weapons = Serialize.load_json("data/weapons/weapons.json")
    if weapons then
        self.weapon_data = weapons
    end
end

-- Get attack range for a unit based on its primary weapon
function ProductionSystem:get_weapon_range(weapon_name)
    if weapon_name and self.weapon_data[weapon_name] then
        -- Weapon range is in cells, convert to leptons (256 leptons per cell)
        return (self.weapon_data[weapon_name].range or 4) * Constants.LEPTON_PER_CELL
    end
    return 4 * Constants.LEPTON_PER_CELL  -- Default 4 cell range
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

    -- Get power multiplier (low power slows production)
    local power_multiplier = 1.0
    if entity:has("owner") then
        local owner = entity:get("owner")
        local power_system = self.world:get_system("power")
        if power_system then
            power_multiplier = power_system:get_production_multiplier(owner.house)
        end
    end

    -- Update progress (apply power multiplier)
    local progress_rate = (100 / (item.build_time * Constants.TICKS_PER_SECOND)) * power_multiplier
    production.progress = production.progress + progress_rate

    -- Check if complete
    if production.progress >= 100 then
        production.progress = 100

        -- For units, spawn from primary factory only (original C&C behavior)
        if item.factory_type ~= "building" then
            -- Only spawn if this is the primary factory for this type
            local owner = entity:get("owner")
            local primary = self:get_primary_factory(owner.house, item.factory_type)

            if primary and primary.id == entity.id then
                self:spawn_unit(entity, item)
                -- Remove from queue and reset
                table.remove(production.queue, 1)
                production.progress = 0
            else
                -- Not primary - unit is ready but won't spawn until we become primary
                -- or the item is manually moved to primary factory's queue
                production.waiting_for_primary = true
            end
        else
            -- For buildings, mark as ready to place
            production.ready_to_place = true
            production.placing_type = item.name
            -- Remove from queue
            table.remove(production.queue, 1)
            production.progress = 0
        end

        -- Emit completion event
        self:emit(Events.EVENTS.PRODUCTION_COMPLETE, entity, item)

        -- Emit specific event for audio system
        if item.factory_type == "building" then
            self:emit(Events.EVENTS.BUILDING_BUILT, entity, item.name)
        else
            self:emit(Events.EVENTS.UNIT_BUILT, entity, item.name)
        end
    end
end

function ProductionSystem:spawn_unit(factory, item)
    local factory_transform = factory:get("transform")
    local factory_owner = factory:get("owner")

    if not factory_transform or not factory_owner then
        return nil
    end

    -- Find valid spawn location around factory
    local spawn_x, spawn_y = self:find_spawn_location(factory, item)

    if not spawn_x then
        -- No valid spawn location, queue for later
        print("WARNING: No valid spawn location for " .. tostring(item.name))
        return nil
    end

    -- Create the unit
    local unit = self:create_unit(item.name, factory_owner.house, spawn_x, spawn_y)

    if unit then
        self.world:add_entity(unit)
        return unit
    end

    return nil
end

-- Find a valid spawn location around a factory
function ProductionSystem:find_spawn_location(factory, item)
    local transform = factory:get("transform")
    local building = factory:get("building")

    if not transform then return nil, nil end

    -- Get factory size in cells (default 2x2 for weapons factory)
    local factory_w = building and building.width or 2
    local factory_h = building and building.height or 2

    local factory_cell_x = transform.cell_x
    local factory_cell_y = transform.cell_y

    -- Check spawn locations in priority order:
    -- 1. Right side (east exit)
    -- 2. Bottom side (south exit)
    -- 3. Left side (west)
    -- 4. Top side (north)
    local spawn_offsets = {
        -- Right side (east exit - primary for vehicles)
        {x = factory_w, y = 0},
        {x = factory_w, y = 1},
        {x = factory_w, y = factory_h - 1},
        -- Bottom side (south exit)
        {x = 0, y = factory_h},
        {x = 1, y = factory_h},
        {x = factory_w - 1, y = factory_h},
        -- Left side
        {x = -1, y = 0},
        {x = -1, y = 1},
        -- Top side
        {x = 0, y = -1},
        {x = 1, y = -1},
    }

    local grid = self.world and self.world.grid

    for _, offset in ipairs(spawn_offsets) do
        local cell_x = factory_cell_x + offset.x
        local cell_y = factory_cell_y + offset.y

        -- Check if cell is valid for spawning
        if self:is_spawn_cell_valid(cell_x, cell_y, item, grid) then
            -- Convert to leptons (center of cell)
            local spawn_x = (cell_x * Constants.LEPTON_PER_CELL) + (Constants.LEPTON_PER_CELL / 2)
            local spawn_y = (cell_y * Constants.LEPTON_PER_CELL) + (Constants.LEPTON_PER_CELL / 2)
            return spawn_x, spawn_y
        end
    end

    -- No valid location found
    return nil, nil
end

-- Check if a cell is valid for spawning a unit
function ProductionSystem:is_spawn_cell_valid(cell_x, cell_y, item, grid)
    if not grid then
        -- No grid, assume valid
        return true
    end

    local cell = grid:get_cell(cell_x, cell_y)
    if not cell then
        return false
    end

    -- Check if cell is passable
    if not cell:is_passable() then
        return false
    end

    -- Check if cell is occupied by a building
    local Cell = require("src.map.cell")
    if cell:has_flag_set(Cell.FLAG.BUILDING) then
        return false
    end

    -- Check if cell already has a unit
    if cell:has_flag_set(Cell.FLAG.UNIT) then
        return false
    end

    return true
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
            rot = data.rot or 5,  -- Rotation speed in degrees per tick (default 5)
            locomotor = data.type == "infantry" and "foot" or
                        (data.type == "aircraft" and "fly" or "track")
        }))
    end

    -- Combat
    if data.primary_weapon then
        -- Get attack range from weapon data (in leptons)
        local attack_range = self:get_weapon_range(data.primary_weapon)
        entity:add("combat", Component.create("combat", {
            primary_weapon = data.primary_weapon,
            secondary_weapon = data.secondary_weapon,
            attack_range = attack_range,
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
            can_capture = data.can_capture or false,
            immune_tiberium = data.immune_tiberium or false,
            crushable = data.crushable ~= false  -- Default to true unless explicitly false
        }))
        entity:add_tag("infantry")
    elseif data.type == "vehicle" then
        entity:add("vehicle", Component.create("vehicle", {
            vehicle_type = unit_type,
            crusher = data.crusher or false
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

        -- Deployable (MCV -> Construction Yard)
        if data.deploys_to then
            entity:add("deployable", Component.create("deployable", {
                deploys_to = data.deploys_to
            }))
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
        -- Get attack range from weapon data (in leptons)
        local attack_range = self:get_weapon_range(data.primary_weapon)
        entity:add("combat", Component.create("combat", {
            primary_weapon = data.primary_weapon,
            attack_range = attack_range,
            ammo = -1  -- Buildings have unlimited ammo
        }))

        if data.turret then
            entity:add("turret", Component.create("turret"))
        end

        -- Add mission component for AI targeting (defensive buildings use GUARD)
        entity:add("mission", Component.create("mission", {
            mission_type = Constants.MISSION.GUARD
        }))
    end

    -- Anti-air buildings can only target aircraft
    if data.antiair then
        local combat = entity:get("combat")
        if combat then
            combat.antiair_only = true
        end
    end

    entity:add_tag("building")

    return entity
end

-- Count entities of a specific type owned by a house
function ProductionSystem:count_units(house, unit_type_filter)
    local count = 0
    local entities = self.world:get_entities_with("owner")

    for _, entity in ipairs(entities) do
        if entity:is_alive() then
            local owner = entity:get("owner")
            if owner.house == house then
                -- Count based on filter
                if unit_type_filter == "infantry" and entity:has("infantry") then
                    count = count + 1
                elseif unit_type_filter == "vehicle" and entity:has("vehicle") then
                    count = count + 1
                elseif unit_type_filter == "aircraft" and entity:has("aircraft") then
                    count = count + 1
                elseif unit_type_filter == "unit" and entity:has_tag("unit") then
                    count = count + 1
                elseif unit_type_filter == "building" and entity:has("building") then
                    count = count + 1
                end
            end
        end
    end

    return count
end

-- Check if house is at unit limit for a specific type
function ProductionSystem:is_at_unit_limit(house, unit_type)
    local count = self:count_units(house, unit_type)
    local limit

    if unit_type == "infantry" then
        limit = self.max_infantry or ProductionSystem.DEFAULT_MAX_INFANTRY
    elseif unit_type == "vehicle" then
        limit = self.max_units or ProductionSystem.DEFAULT_MAX_UNITS
    elseif unit_type == "aircraft" then
        limit = self.max_aircraft or ProductionSystem.DEFAULT_MAX_AIRCRAFT
    elseif unit_type == "building" then
        limit = self.max_buildings or ProductionSystem.DEFAULT_MAX_BUILDINGS
    else
        limit = self.max_units or ProductionSystem.DEFAULT_MAX_UNITS
    end

    return count >= limit, count, limit
end

-- Set unit limits (can be overridden by scenario settings)
function ProductionSystem:set_unit_limits(max_units, max_buildings, max_infantry, max_aircraft)
    self.max_units = max_units or ProductionSystem.DEFAULT_MAX_UNITS
    self.max_buildings = max_buildings or ProductionSystem.DEFAULT_MAX_BUILDINGS
    self.max_infantry = max_infantry or ProductionSystem.DEFAULT_MAX_INFANTRY
    self.max_aircraft = max_aircraft or ProductionSystem.DEFAULT_MAX_AIRCRAFT
end

-- Primary Factory Management (original C&C FACTORY.CPP behavior)
-- Each house can have one primary factory per type (infantry, vehicle, aircraft)
-- Units spawn from primary factory; if destroyed, auto-assigns next oldest factory

function ProductionSystem:get_primary_factory(house, factory_type)
    if not self.primary_factories[house] then
        self.primary_factories[house] = {}
    end

    local primary_id = self.primary_factories[house][factory_type]
    if primary_id then
        local factory = self.world:get_entity(primary_id)
        if factory and factory:is_alive() then
            return factory
        end
        -- Primary is dead, clear and auto-assign
        self.primary_factories[house][factory_type] = nil
    end

    -- Auto-assign primary if none exists
    local factory = self:find_factory_of_type(house, factory_type)
    if factory then
        self:set_primary_factory(factory)
        return factory
    end

    return nil
end

function ProductionSystem:set_primary_factory(factory)
    if not factory:has("production") or not factory:has("owner") then
        return false
    end

    local production = factory:get("production")
    local owner = factory:get("owner")

    if not self.primary_factories[owner.house] then
        self.primary_factories[owner.house] = {}
    end

    -- Clear previous primary's flag
    local old_primary_id = self.primary_factories[owner.house][production.factory_type]
    if old_primary_id then
        local old_factory = self.world:get_entity(old_primary_id)
        if old_factory and old_factory:is_alive() and old_factory:has("production") then
            old_factory:get("production").is_primary = false
        end
    end

    -- Set new primary
    self.primary_factories[owner.house][production.factory_type] = factory.id
    production.is_primary = true

    Events.emit("PRIMARY_FACTORY_SET", factory, owner.house, production.factory_type)
    return true
end

function ProductionSystem:find_factory_of_type(house, factory_type)
    local factories = self.world:get_entities_with("production", "owner")
    local oldest_factory = nil
    local oldest_id = math.huge

    for _, factory in ipairs(factories) do
        local production = factory:get("production")
        local owner = factory:get("owner")

        if owner.house == house and production.factory_type == factory_type and factory:is_alive() then
            -- Use entity ID as creation order (lower = older)
            if factory.id < oldest_id then
                oldest_id = factory.id
                oldest_factory = factory
            end
        end
    end

    return oldest_factory
end

-- Check if factory is primary for its type
function ProductionSystem:is_primary_factory(factory)
    if not factory:has("production") or not factory:has("owner") then
        return false
    end

    local production = factory:get("production")
    local owner = factory:get("owner")

    if not self.primary_factories[owner.house] then
        return false
    end

    return self.primary_factories[owner.house][production.factory_type] == factory.id
end

-- Called when a factory building is destroyed - reassigns primary
function ProductionSystem:on_factory_destroyed(factory)
    if not factory:has("production") or not factory:has("owner") then
        return
    end

    local production = factory:get("production")
    local owner = factory:get("owner")

    -- Check if this was the primary factory
    if self:is_primary_factory(factory) then
        -- Clear current primary
        self.primary_factories[owner.house][production.factory_type] = nil

        -- Auto-assign new primary
        local new_primary = self:find_factory_of_type(owner.house, production.factory_type)
        if new_primary then
            self:set_primary_factory(new_primary)
        end
    end
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

    -- Check unit limits
    local at_limit, count, limit = self:is_at_unit_limit(factory_owner.house, data.type)
    if at_limit then
        return false, string.format("Unit limit reached (%d/%d)", count, limit)
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

    -- Check prerequisites (OR logic - need any of the factory buildings)
    if data.prerequisite then
        local has_prereqs, missing = self:has_prerequisites(factory_owner.house, data.prerequisite, true)
        if not has_prereqs then
            return false, missing
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

-- Check if a house has required prerequisites for a building/unit
-- For buildings: AND logic (all prerequisites required)
-- For units: OR logic (any prerequisite factory is sufficient)
function ProductionSystem:has_prerequisites(house, prerequisites, is_unit)
    if not prerequisites or #prerequisites == 0 then
        return true
    end

    -- Get all buildings owned by this house
    local owned_buildings = {}
    local buildings = self.world:get_entities_with("building", "owner")
    for _, building in ipairs(buildings) do
        local building_owner = building:get("owner")
        if building_owner.house == house then
            local building_data = building:get("building")
            owned_buildings[building_data.structure_type] = true
        end
    end

    if is_unit then
        -- OR logic for units - having ANY prerequisite is sufficient
        -- e.g., E1 needs PYLE OR HAND (either Barracks or Hand of Nod)
        for _, prereq in ipairs(prerequisites) do
            if owned_buildings[prereq] then
                return true
            end
        end
        return false, "Requires " .. table.concat(prerequisites, " or ")
    else
        -- AND logic for buildings - ALL prerequisites required
        for _, prereq in ipairs(prerequisites) do
            if not owned_buildings[prereq] then
                return false, "Requires " .. prereq
            end
        end
        return true
    end
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

    -- Check building limits
    local at_limit, count, limit = self:is_at_unit_limit(owner.house, "building")
    if at_limit then
        return false, string.format("Building limit reached (%d/%d)", count, limit)
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

    -- Check prerequisites (AND logic - all buildings must be present)
    if data.prerequisite then
        local has_prereqs, missing = self:has_prerequisites(owner.house, data.prerequisite, false)
        if not has_prereqs then
            return false, missing
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

    -- Check placement validity (require adjacency to existing base buildings)
    if grid then
        -- Most buildings require adjacency (except MCV-deployed Construction Yard)
        local require_adjacent = building_type ~= "FACT"
        local can_place, reason = grid:can_place_building(
            cell_x, cell_y,
            data.size[1], data.size[2],
            owner.house,
            require_adjacent,
            building_type
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

        -- Spawn free unit if building provides one (e.g., Refinery -> Harvester)
        if data.free_unit then
            self:spawn_free_unit(building, data.free_unit, owner.house, cell_x, cell_y, data.size)
        end

        -- Clear production state
        production.ready_to_place = false
        production.placing_type = nil

        self:emit(Events.EVENTS.BUILDING_PLACED, building)

        return building
    end

    return nil, "Failed to create building"
end

-- Spawn a free unit when a building is placed (e.g., Harvester from Refinery)
function ProductionSystem:spawn_free_unit(building, unit_type, house, building_cell_x, building_cell_y, building_size)
    -- Find spawn position adjacent to building
    local spawn_x, spawn_y = self:find_unit_spawn_position(building_cell_x, building_cell_y, building_size)

    if spawn_x and spawn_y then
        -- Convert cell to lepton coordinates (center of cell)
        local x = spawn_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
        local y = spawn_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2

        local unit = self:create_unit(unit_type, house, x, y)
        if unit then
            self.world:add_entity(unit)

            -- If this is a harvester, assign it to the refinery
            if unit:has("harvester") then
                local harvester = unit:get("harvester")
                harvester.assigned_refinery = building.id
            end

            -- Emit event for free unit spawned
            self:emit("FREE_UNIT_SPAWNED", unit, building)

            print(string.format("Spawned free %s at cell (%d, %d) for %s",
                unit_type, spawn_x, spawn_y,
                building:has("building") and building:get("building").structure_type or "building"))

            return unit
        end
    else
        print(string.format("WARNING: Could not find spawn position for free %s near building at (%d, %d)",
            unit_type, building_cell_x, building_cell_y))
    end

    return nil
end

-- Find a valid spawn position for a unit adjacent to a building
function ProductionSystem:find_unit_spawn_position(building_cell_x, building_cell_y, building_size)
    local grid = self.world and self.world.grid

    -- Search positions around the building, prioritizing south (exit direction)
    local size_x = building_size[1] or 1
    local size_y = building_size[2] or 1

    -- Try positions in this order: south, east, west, north
    local search_order = {}

    -- South edge (preferred for vehicle exit)
    for dx = 0, size_x - 1 do
        table.insert(search_order, {building_cell_x + dx, building_cell_y + size_y})
    end

    -- East edge
    for dy = 0, size_y - 1 do
        table.insert(search_order, {building_cell_x + size_x, building_cell_y + dy})
    end

    -- West edge
    for dy = 0, size_y - 1 do
        table.insert(search_order, {building_cell_x - 1, building_cell_y + dy})
    end

    -- North edge
    for dx = 0, size_x - 1 do
        table.insert(search_order, {building_cell_x + dx, building_cell_y - 1})
    end

    for _, pos in ipairs(search_order) do
        local cx, cy = pos[1], pos[2]

        -- Check if position is valid
        if grid then
            local cell = grid:get_cell(cx, cy)
            if cell and cell:is_passable("drive") then
                return cx, cy
            end
        else
            -- No grid, just return first position
            return cx, cy
        end
    end

    return nil, nil
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

-- Get all buildable items for a house with prerequisite status
function ProductionSystem:get_buildable_items(house, item_type)
    local house_name = house == Constants.HOUSE.GOOD and "GDI" or "NOD"
    local items = {}

    local data_source = item_type == "building" and self.building_data or self.unit_data
    local is_unit = item_type ~= "building"

    for name, data in pairs(data_source) do
        -- Check house ownership
        local can_own = false
        if data.house then
            for _, h in ipairs(data.house) do
                if h == house_name then
                    can_own = true
                    break
                end
            end
        else
            can_own = true  -- No house restriction
        end

        if can_own then
            local has_prereqs, prereq_reason = self:has_prerequisites(house, data.prerequisites, is_unit)
            table.insert(items, {
                name = name,
                icon = data.name or name,
                cost = data.cost or 0,
                type = data.type or "unknown",
                available = has_prereqs,
                prereq_reason = prereq_reason,
                data = data
            })
        end
    end

    -- Sort by cost
    table.sort(items, function(a, b) return a.cost < b.cost end)

    return items
end

-- Deploy a unit (MCV -> Construction Yard)
-- Returns the building entity if successful, nil and error message if not
function ProductionSystem:deploy_unit(unit, grid)
    if not unit:has("deployable") then
        return nil, "Unit cannot deploy"
    end

    local deployable = unit:get("deployable")
    local transform = unit:get("transform")
    local owner = unit:get("owner")

    if not deployable.deploys_to then
        return nil, "No deployment target"
    end

    local building_type = deployable.deploys_to
    local data = self.building_data[building_type]

    if not data then
        return nil, "Unknown building type: " .. building_type
    end

    -- Calculate building placement position (centered on unit)
    local cell_x = transform.cell_x - math.floor((data.size[1] - 1) / 2)
    local cell_y = transform.cell_y - math.floor((data.size[2] - 1) / 2)

    -- Check if we can place the building
    if grid then
        local can_place, reason = grid:can_place_building(
            cell_x, cell_y,
            data.size[1], data.size[2],
            owner.house,
            true  -- Skip adjacency check for deployment
        )
        if not can_place then
            return nil, reason or "Cannot deploy here"
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

        -- Remove the MCV
        self.world:destroy_entity(unit)

        -- Emit deployment event
        self:emit(Events.EVENTS.UNIT_DEPLOYED, unit, building)

        return building
    end

    return nil, "Failed to create building"
end

-- Check if a unit can deploy at current location
function ProductionSystem:can_deploy(unit, grid)
    if not unit:has("deployable") then
        return false, "Unit cannot deploy"
    end

    local deployable = unit:get("deployable")
    local transform = unit:get("transform")
    local owner = unit:get("owner")

    if not deployable.deploys_to then
        return false, "No deployment target"
    end

    local building_type = deployable.deploys_to
    local data = self.building_data[building_type]

    if not data then
        return false, "Unknown building type"
    end

    local cell_x = transform.cell_x - math.floor((data.size[1] - 1) / 2)
    local cell_y = transform.cell_y - math.floor((data.size[2] - 1) / 2)

    if grid then
        return grid:can_place_building(
            cell_x, cell_y,
            data.size[1], data.size[2],
            owner.house,
            true  -- Skip adjacency for deployment
        )
    end

    return true
end

-- Sell a building - returns credits refunded
function ProductionSystem:sell_building(building, grid)
    if not building:has("building") then
        return 0, "Not a building"
    end

    local building_data = building:get("building")
    local owner = building:get("owner")
    local transform = building:get("transform")

    local data = self.building_data[building_data.structure_type]
    if not data then
        return 0, "Unknown building type"
    end

    -- Calculate refund (50% of cost, like original)
    local refund = math.floor((data.cost or 0) * 0.5)

    -- Add credits to owner
    local harvest_system = self.world:get_system("harvest")
    if harvest_system then
        harvest_system:add_credits(owner.house, refund)
    end

    -- Clear cells
    if grid then
        grid:remove_building(
            transform.cell_x,
            transform.cell_y,
            data.size[1],
            data.size[2]
        )
    end

    -- Emit sell event
    self:emit(Events.EVENTS.BUILDING_SOLD, building, refund)

    -- Destroy the building
    self.world:destroy_entity(building)

    return refund
end

-- Start repairing a building
function ProductionSystem:start_repair(building)
    if not building:has("building") or not building:has("health") then
        return false, "Cannot repair"
    end

    local building_comp = building:get("building")
    local health = building:get("health")

    -- Already at full health
    if health.hp >= health.max_hp then
        return false, "Already at full health"
    end

    -- Start repairing
    building_comp.repairing = true
    building_comp.repair_timer = 0

    return true
end

-- Stop repairing a building
function ProductionSystem:stop_repair(building)
    if not building:has("building") then
        return false
    end

    local building_comp = building:get("building")
    building_comp.repairing = false
    building_comp.repair_timer = 0

    return true
end

-- Process repair for a building (called each tick)
-- Repair costs credits and heals over time
function ProductionSystem:process_repair(building, dt)
    if not building:has("building") or not building:has("health") or not building:has("owner") then
        return
    end

    local building_comp = building:get("building")
    local health = building:get("health")
    local owner = building:get("owner")

    if not building_comp.repairing then
        return
    end

    -- Check if fully healed
    if health.hp >= health.max_hp then
        building_comp.repairing = false
        return
    end

    -- Repair every few ticks (like original)
    building_comp.repair_timer = building_comp.repair_timer + 1
    if building_comp.repair_timer < 8 then  -- Repair every 8 ticks
        return
    end
    building_comp.repair_timer = 0

    -- Calculate repair cost and amount
    local data = self.building_data[building_comp.structure_type]
    if not data then return end

    -- Repair 1% of max health per cycle, costs proportional credits
    local repair_amount = math.ceil(health.max_hp * 0.01)
    local repair_cost = math.ceil((data.cost or 0) * 0.01 * 0.5)  -- Half price for repairs

    -- Check if we can afford it
    local harvest_system = self.world:get_system("harvest")
    if harvest_system then
        local credits = harvest_system:get_credits(owner.house)
        if credits < repair_cost then
            -- Can't afford repair, stop
            building_comp.repairing = false
            return
        end

        -- Deduct credits
        harvest_system:spend_credits(owner.house, repair_cost)
    end

    -- Apply repair
    health.hp = math.min(health.hp + repair_amount, health.max_hp)

    -- Check if done
    if health.hp >= health.max_hp then
        building_comp.repairing = false
    end
end

return ProductionSystem
