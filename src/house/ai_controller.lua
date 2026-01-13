--[[
    AI Controller - Computer player decision making
    Implements original C&C AI behavior patterns
    Reference: HOUSE.CPP AI functions, MISSION.H, TEAM.H
]]

local Events = require("src.core.events")
local Constants = require("src.core.constants")

local AIController = {}
AIController.__index = AIController

-- AI difficulty settings
AIController.DIFFICULTY = {
    EASY = 1,
    NORMAL = 2,
    HARD = 3
}

-- AI states (based on original C&C)
AIController.STATE = {
    BUILDING = "building",      -- Building up base
    DEFENDING = "defending",    -- Under attack, rally defense
    ATTACKING = "attacking",    -- Launching coordinated attack
    HARVESTING = "harvesting",  -- Focus on economy
    RETREATING = "retreating",  -- Falling back after defeat
    REGROUPING = "regrouping"   -- Gathering forces for next attack
}

-- Build categories for prioritization
AIController.BUILD_CATEGORY = {
    POWER = "power",
    ECONOMY = "economy",
    INFANTRY = "infantry",
    VEHICLE = "vehicle",
    AIRCRAFT = "aircraft",
    DEFENSE = "defense",
    TECH = "tech",
    SUPERWEAPON = "superweapon"
}

-- GDI building types
AIController.GDI_BUILDINGS = {
    power = {"NUKE", "NUK2"},
    economy = {"PROC"},
    infantry = {"PYLE"},
    vehicle = {"WEAP"},
    aircraft = {"AFLD"},
    defense = {"GTWR", "GUN", "SAM"},
    tech = {"HQ", "EYE", "FIX"},
    superweapon = {"TMPL"}
}

-- Nod building types
AIController.NOD_BUILDINGS = {
    power = {"NUKE", "NUK2"},
    economy = {"PROC"},
    infantry = {"HAND"},
    vehicle = {"WEAP"},
    aircraft = {"AFLD"},
    defense = {"ATWR", "GUN", "SAM", "OBLI"},
    tech = {"HQ", "EYE", "FIX", "TMPL"},
    superweapon = {"TMPL"}
}

-- GDI unit build priorities
AIController.GDI_UNITS = {
    infantry = {
        {type = "E1", weight = 40},   -- Minigunner
        {type = "E2", weight = 30},   -- Grenadier
        {type = "E3", weight = 15},   -- Rocket soldier
        {type = "E6", weight = 10},   -- Engineer
        {type = "RMBO", weight = 5}   -- Commando
    },
    vehicle = {
        {type = "HTNK", weight = 35}, -- Mammoth
        {type = "MTNK", weight = 30}, -- Medium tank
        {type = "MSAM", weight = 15}, -- Rocket launcher
        {type = "APC", weight = 10},  -- APC
        {type = "JEEP", weight = 10}  -- Humvee
    },
    aircraft = {
        {type = "ORCA", weight = 100} -- Orca
    },
    harvester = {
        {type = "HARV", weight = 100}
    }
}

-- Nod unit build priorities
AIController.NOD_UNITS = {
    infantry = {
        {type = "E1", weight = 35},   -- Minigunner
        {type = "E3", weight = 25},   -- Rocket soldier
        {type = "E4", weight = 20},   -- Flamethrower
        {type = "E5", weight = 10},   -- Chem warrior
        {type = "E6", weight = 10}    -- Engineer
    },
    vehicle = {
        {type = "LTNK", weight = 35}, -- Light tank
        {type = "FTNK", weight = 20}, -- Flame tank
        {type = "STNK", weight = 15}, -- Stealth tank
        {type = "BIKE", weight = 15}, -- Recon bike
        {type = "BGGY", weight = 10}, -- Nod buggy
        {type = "APC", weight = 5}    -- APC
    },
    aircraft = {
        {type = "APCH", weight = 100} -- Apache
    },
    harvester = {
        {type = "HARV", weight = 100}
    }
}

function AIController.new(house)
    local self = setmetatable({}, AIController)

    -- Parent house
    self.house = house

    -- AI settings
    self.difficulty = AIController.DIFFICULTY.NORMAL
    self.enabled = true
    self.iq = 100  -- AI intelligence (0-200), affects decision quality

    -- Current state
    self.state = AIController.STATE.BUILDING

    -- Timers (in game ticks, 15 per second)
    self.think_timer = 0
    self.think_interval = 15  -- 1 second
    self.attack_timer = 0
    self.attack_interval = 15 * 120  -- 2 minutes
    self.production_timer = 0
    self.production_interval = 15  -- Check production every second

    -- Build queue management
    self.building_queue = {}
    self.unit_queue = {}
    self.current_building = nil
    self.current_unit = nil

    -- Attack management
    self.attack_force = {}
    self.min_attack_force = 5
    self.max_attack_force = 15
    self.attack_target = nil
    self.attack_waypoint = nil

    -- Defense tracking
    self.threat_level = 0
    self.threat_decay = 1
    self.last_attack_time = 0
    self.defense_radius = 10  -- Cells from base center

    -- Economy management
    self.desired_harvesters = 2
    self.max_harvesters = 4
    self.credits_reserve = 1000  -- Keep this much for emergencies
    self.low_credits_threshold = 500

    -- Team management
    self.teams = {}
    self.team_counter = 0

    -- Base expansion
    self.base_center_x = nil
    self.base_center_y = nil
    self.expansion_direction = nil

    -- Statistics
    self.stats = {
        buildings_built = 0,
        units_built = 0,
        attacks_launched = 0,
        times_attacked = 0
    }

    -- Difficulty-based adjustments
    self:set_difficulty(self.difficulty)

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function AIController:register_events()
    Events.on("ENTITY_ATTACKED", function(victim, attacker)
        if self.house and victim.owner and victim.owner.house == self.house then
            self:on_entity_attacked(victim, attacker)
        end
    end)

    Events.on("UNIT_BUILT", function(entity)
        if self.house and entity.owner and entity.owner.house == self.house then
            self:on_unit_built(entity)
        end
    end)

    Events.on("BUILDING_BUILT", function(entity)
        if self.house and entity.owner and entity.owner.house == self.house then
            self:on_building_built(entity)
        end
    end)

    Events.on("ENTITY_DESTROYED", function(entity)
        if self.house and entity.owner and entity.owner.house == self.house then
            self:on_entity_destroyed(entity)
        end
    end)

    Events.on("AI_FIND_TARGET", function(house)
        if house == self.house then
            local target = self:find_attack_target()
            self.attack_target = target
        end
    end)

    -- Handle production completion for AI houses
    Events.on("PRODUCTION_COMPLETE", function(house, item_type, item_name, category)
        if house == self.house then
            self:on_production_complete(item_type, item_name, category)
        end
    end)
end

-- Handle being attacked
function AIController:on_entity_attacked(victim, attacker)
    self.threat_level = math.min(100, self.threat_level + 15)
    self.stats.times_attacked = self.stats.times_attacked + 1

    -- High value target attacked - increase threat more
    if victim:has("building") then
        self.threat_level = math.min(100, self.threat_level + 25)
    end

    -- Remember attacker position for counterattack
    if attacker and attacker:has("transform") then
        local transform = attacker:get("transform")
        self.last_attack_direction = {
            x = transform.cell_x,
            y = transform.cell_y
        }
    end
end

-- Handle unit built
function AIController:on_unit_built(entity)
    self.stats.units_built = self.stats.units_built + 1

    -- Add combat units to attack force
    if entity:has("combat") then
        local unit_type = entity.unit_type or ""

        -- Don't add harvesters or MCVs to attack force
        if unit_type ~= "HARV" and unit_type ~= "MCV" then
            self:add_to_attack_force(entity)
        end
    end
end

-- Handle building built
function AIController:on_building_built(entity)
    self.stats.buildings_built = self.stats.buildings_built + 1

    -- Update base center
    self:update_base_center()
end

-- Handle entity destroyed
function AIController:on_entity_destroyed(entity)
    self:remove_from_attack_force(entity)
end

--[[
    Handle production completion.

    When a building or unit finishes production, the AI needs to:
    - For buildings: Find a valid placement location and place it
    - For units: They auto-spawn at factory, just track them

    @param item_type - The type identifier (e.g., "NUKE", "E1")
    @param item_name - Human readable name
    @param category - "building", "infantry", "vehicle", "aircraft"
]]
function AIController:on_production_complete(item_type, item_name, category)
    if category == "building" then
        -- Find location and place building
        local location = self:find_build_location(item_type)
        if location then
            -- Emit event for game to place building
            Events.emit("AI_PLACE_BUILDING", self.house, item_type, location.x, location.y)
            self.current_building = nil
        else
            -- Can't place, cancel and retry later
            self.current_building = nil
        end
    else
        -- Units auto-spawn at factory, clear queue slot
        self.current_unit = nil
    end
end

--[[
    Find a valid build location for a building type.

    Searches outward from the base center in a spiral pattern
    to find a valid placement cell that is:
    1. Adjacent to an existing friendly building
    2. Has enough clear space for the building footprint
    3. Not on water, rock, or tiberium

    Reference: Original C&C AI building placement logic

    @param building_type - The building type (e.g., "NUKE", "PROC")
    @return {x, y} cell coordinates or nil if no valid location
]]
function AIController:find_build_location(building_type)
    -- Get building size from data
    local size = self:get_building_size(building_type)
    if not size then
        return nil
    end

    -- Start from base center
    local center_x = self.base_center_x or 32
    local center_y = self.base_center_y or 32

    -- Search in expanding rings around base center
    -- Maximum search radius (cells)
    local max_radius = 15

    -- Spiral search pattern
    for radius = 1, max_radius do
        -- Check positions in this ring
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Only check cells on the perimeter of this ring
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local cell_x = center_x + dx
                    local cell_y = center_y + dy

                    if self:can_place_at(cell_x, cell_y, size.width, size.height, building_type) then
                        return {x = cell_x, y = cell_y}
                    end
                end
            end
        end
    end

    return nil
end

--[[
    Check if a building can be placed at the given cell.

    @param cell_x, cell_y - Cell coordinates
    @param width, height - Building footprint size
    @param building_type - Building type for special rules
    @return true if placement is valid
]]
function AIController:can_place_at(cell_x, cell_y, width, height, building_type)
    -- Need grid reference to check placement
    if not self.grid then
        return false
    end

    -- Construction Yards don't require adjacency (for MCV deployment)
    local require_adjacent = building_type ~= "FACT"

    local can_place, _ = self.grid:can_place_building(
        cell_x, cell_y, width, height,
        self.house, require_adjacent, building_type
    )

    return can_place
end

--[[
    Get building size from type data.

    @param building_type - Building type name
    @return {width, height} or nil
]]
function AIController:get_building_size(building_type)
    -- Common building sizes for C&C buildings
    local sizes = {
        -- Power
        NUKE = {width = 2, height = 2},  -- Power Plant
        NUK2 = {width = 2, height = 2},  -- Advanced Power
        -- Economy
        PROC = {width = 3, height = 2},  -- Refinery
        SILO = {width = 2, height = 1},  -- Tiberium Silo
        -- Production
        PYLE = {width = 2, height = 2},  -- Barracks
        HAND = {width = 2, height = 2},  -- Hand of Nod
        WEAP = {width = 3, height = 2},  -- Weapons Factory
        AFLD = {width = 2, height = 2},  -- Airfield
        HPAD = {width = 2, height = 2},  -- Helipad
        FACT = {width = 3, height = 2},  -- Construction Yard
        -- Defense
        GTWR = {width = 1, height = 1},  -- Guard Tower
        ATWR = {width = 1, height = 1},  -- Advanced Guard Tower
        GUN = {width = 1, height = 1},   -- Gun Turret
        SAM = {width = 2, height = 1},   -- SAM Site
        OBLI = {width = 1, height = 2},  -- Obelisk of Light
        -- Tech
        HQ = {width = 2, height = 2},    -- Communications Center
        EYE = {width = 2, height = 2},   -- Advanced Comm Center
        FIX = {width = 2, height = 3},   -- Repair Facility
        TMPL = {width = 2, height = 2},  -- Temple of Nod
        -- Walls
        SBAG = {width = 1, height = 1},  -- Sandbags
        CYCL = {width = 1, height = 1},  -- Chain Link
        BRIK = {width = 1, height = 1},  -- Concrete Wall
    }

    return sizes[building_type]
end

--[[
    Set grid reference for placement checks.

    @param grid - The map grid instance
]]
function AIController:set_grid(grid)
    self.grid = grid
end

-- Update AI (call each game tick)
function AIController:update(dt)
    if not self.enabled or not self.house then return end

    -- Update think timer
    self.think_timer = self.think_timer + 1
    if self.think_timer >= self.think_interval then
        self.think_timer = 0
        self:think()
    end

    -- Update attack timer
    self.attack_timer = self.attack_timer + 1

    -- Update production
    self.production_timer = self.production_timer + 1
    if self.production_timer >= self.production_interval then
        self.production_timer = 0
        self:manage_production()
    end

    -- Decay threat level
    if self.threat_level > 0 then
        self.threat_level = math.max(0, self.threat_level - self.threat_decay * dt)
    end
end

-- Main AI decision loop
function AIController:think()
    -- Update state based on situation
    self:update_state()

    -- Make decisions based on state
    if self.state == AIController.STATE.BUILDING then
        self:think_building()
    elseif self.state == AIController.STATE.DEFENDING then
        self:think_defending()
    elseif self.state == AIController.STATE.ATTACKING then
        self:think_attacking()
    elseif self.state == AIController.STATE.HARVESTING then
        self:think_harvesting()
    elseif self.state == AIController.STATE.REGROUPING then
        self:think_regrouping()
    end
end

-- Update AI state based on situation
function AIController:update_state()
    -- High threat = defend
    if self.threat_level > 60 then
        self.state = AIController.STATE.DEFENDING
        return
    end

    -- Attack ready
    if self.attack_timer >= self.attack_interval and
       #self.attack_force >= self.min_attack_force then
        self.state = AIController.STATE.ATTACKING
        return
    end

    -- Need more harvesters
    local harvester_count = self:count_unit_type("HARV")
    local refinery_count = self:count_building_type("PROC")

    if harvester_count < math.min(self.desired_harvesters, refinery_count) then
        self.state = AIController.STATE.HARVESTING
        return
    end

    -- Need more attack units
    if #self.attack_force < self.min_attack_force then
        self.state = AIController.STATE.REGROUPING
        return
    end

    -- Default to building
    self.state = AIController.STATE.BUILDING
end

-- Building phase logic - construct base infrastructure
function AIController:think_building()
    local buildings = self:get_building_list()
    local credits = self.house.credits or 0

    -- Priority 1: Power
    local power_balance = self:get_power_balance()
    if power_balance < 50 then
        self:try_build_building(buildings.power)
        return
    end

    -- Priority 2: Economy (Refinery)
    if self:count_building_type("PROC") < 2 then
        self:try_build_building(buildings.economy)
        return
    end

    -- Priority 3: Infantry production
    local barracks = self.house.side == "GDI" and "PYLE" or "HAND"
    if not self:has_building_type(barracks) then
        self:try_build_building(buildings.infantry)
        return
    end

    -- Priority 4: Vehicle production
    if not self:has_building_type("WEAP") then
        self:try_build_building(buildings.vehicle)
        return
    end

    -- Priority 5: Defenses
    local defense_count = self:count_defenses()
    if defense_count < 3 + self.difficulty then
        self:try_build_building(buildings.defense)
        return
    end

    -- Priority 6: Tech buildings
    if credits > 2000 then
        if not self:has_building_type("HQ") then
            self:try_build_building({"HQ"})
            return
        end
        if not self:has_building_type("EYE") then
            self:try_build_building({"EYE"})
            return
        end
    end

    -- Priority 7: Aircraft
    if credits > 3000 and not self:has_building_type("AFLD") then
        self:try_build_building(buildings.aircraft)
        return
    end

    -- Priority 8: Additional defenses
    if defense_count < 6 + self.difficulty * 2 then
        self:try_build_building(buildings.defense)
        return
    end

    -- Priority 9: More power for expansion
    if power_balance < 200 then
        self:try_build_building(buildings.power)
    end
end

-- Defense phase logic - rally units to defend base
function AIController:think_defending()
    local base_x, base_y = self:get_base_center()

    -- Rally all combat units to defend
    for _, unit in ipairs(self.attack_force) do
        if unit:is_alive() and unit:has("mission") then
            Events.emit("AI_ORDER_UNIT", unit, "guard_area", base_x, base_y)
        end
    end

    -- Build defensive units
    self:queue_unit_by_category("infantry")
    self:queue_unit_by_category("vehicle")

    -- If threat is decreasing, start building defenses
    if self.threat_level < 40 then
        local buildings = self:get_building_list()
        self:try_build_building(buildings.defense)
    end
end

-- Attack phase logic - coordinate attack on enemy
function AIController:think_attacking()
    -- Find target if not set
    if not self.attack_target then
        self.attack_target = self:find_attack_target()
    end

    if not self.attack_target then
        -- No targets found, go back to building
        self.state = AIController.STATE.BUILDING
        return
    end

    -- Get target position
    local target_x, target_y
    if self.attack_target:has("transform") then
        local transform = self.attack_target:get("transform")
        target_x = transform.x
        target_y = transform.y
    else
        self.attack_target = nil
        return
    end

    -- Send attack force
    local units_sent = 0
    for _, unit in ipairs(self.attack_force) do
        if unit:is_alive() then
            Events.emit("AI_ORDER_UNIT", unit, "attack_move", target_x, target_y)
            units_sent = units_sent + 1
        end
    end

    -- Log attack
    self.stats.attacks_launched = self.stats.attacks_launched + 1

    -- Reset for next attack
    self.attack_timer = 0
    self.attack_force = {}
    self.attack_target = nil

    -- Return to building state
    self.state = AIController.STATE.BUILDING
end

-- Harvesting focus logic - ensure economy
function AIController:think_harvesting()
    -- Build harvesters
    if self:has_building_type("WEAP") then
        self:queue_unit_build("HARV")
    end

    -- Also build refinery if we don't have enough
    local refinery_count = self:count_building_type("PROC")
    if refinery_count < 2 then
        self:try_build_building({"PROC"})
    end
end

-- Regrouping logic - build up attack force
function AIController:think_regrouping()
    -- Build balanced attack force
    local infantry_count = self:count_attack_force_type("infantry")
    local vehicle_count = self:count_attack_force_type("vehicle")

    -- Aim for 2:1 infantry to vehicle ratio
    if infantry_count < vehicle_count * 2 then
        self:queue_unit_by_category("infantry")
    else
        self:queue_unit_by_category("vehicle")
    end

    -- Also build some aircraft if available
    if self:has_building_type("AFLD") then
        self:queue_unit_by_category("aircraft")
    end
end

-- Manage unit production
function AIController:manage_production()
    local credits = self.house.credits or 0

    -- Don't produce if low on credits
    if credits < self.low_credits_threshold then
        return
    end

    -- Always maintain harvesters
    local harvester_count = self:count_unit_type("HARV")
    local refinery_count = self:count_building_type("PROC")

    if harvester_count < math.min(self.max_harvesters, refinery_count + 1) then
        self:queue_unit_build("HARV")
    end

    -- Build attack units based on state
    if self.state ~= AIController.STATE.DEFENDING then
        if #self.attack_force < self.max_attack_force then
            -- Mix of infantry and vehicles
            if math.random() < 0.4 then
                self:queue_unit_by_category("infantry")
            else
                self:queue_unit_by_category("vehicle")
            end
        end
    end
end

-- Try to build a building from a list
function AIController:try_build_building(building_types)
    if not building_types or #building_types == 0 then
        return false
    end

    local credits = self.house.credits or 0

    for _, building_type in ipairs(building_types) do
        -- Check if we can build it
        if self:can_build_building(building_type) then
            local cost = self:get_building_cost(building_type)
            if credits >= cost then
                self:queue_building(building_type)
                return true
            end
        end
    end

    return false
end

-- Queue a building for construction
function AIController:queue_building(building_type)
    -- Check if already building something
    if self.current_building then
        return false
    end

    Events.emit("AI_QUEUE_BUILD", self.house, building_type, "building")
    self.current_building = building_type
    return true
end

-- Queue a unit for production
function AIController:queue_unit_build(unit_type)
    Events.emit("AI_QUEUE_BUILD", self.house, unit_type, "unit")
end

-- Queue unit by category with weighted random selection
function AIController:queue_unit_by_category(category)
    local units = self:get_unit_list()
    local unit_pool = units[category]

    if not unit_pool or #unit_pool == 0 then
        return
    end

    -- Calculate total weight
    local total_weight = 0
    local available = {}

    for _, unit_def in ipairs(unit_pool) do
        if self:can_build_unit(unit_def.type) then
            total_weight = total_weight + unit_def.weight
            table.insert(available, unit_def)
        end
    end

    if total_weight == 0 then
        return
    end

    -- Weighted random selection
    local roll = math.random() * total_weight
    local cumulative = 0

    for _, unit_def in ipairs(available) do
        cumulative = cumulative + unit_def.weight
        if roll <= cumulative then
            self:queue_unit_build(unit_def.type)
            return
        end
    end
end

-- Get building list for faction
function AIController:get_building_list()
    if self.house.side == "GDI" then
        return AIController.GDI_BUILDINGS
    else
        return AIController.NOD_BUILDINGS
    end
end

-- Get unit list for faction
function AIController:get_unit_list()
    if self.house.side == "GDI" then
        return AIController.GDI_UNITS
    else
        return AIController.NOD_UNITS
    end
end

-- Check if can build a building
function AIController:can_build_building(building_type)
    if self.house.tech_tree then
        return self.house.tech_tree:can_build_building(building_type)
    end
    return true
end

-- Check if can build a unit
function AIController:can_build_unit(unit_type)
    if self.house.tech_tree then
        return self.house.tech_tree:can_build_unit(unit_type)
    end
    return true
end

-- Get building cost
function AIController:get_building_cost(building_type)
    -- Would look up from data files
    local costs = {
        NUKE = 300, NUK2 = 700,
        PROC = 2000,
        PYLE = 300, HAND = 300,
        WEAP = 2000,
        AFLD = 2000,
        GTWR = 500, ATWR = 600, GUN = 600, OBLI = 1500, SAM = 750,
        HQ = 1000, EYE = 2000, FIX = 1200,
        TMPL = 3000
    }
    return costs[building_type] or 1000
end

-- Check if house has building type
function AIController:has_building_type(building_type)
    if self.house.buildings then
        for _, building in ipairs(self.house.buildings) do
            if building.building_type == building_type then
                return true
            end
        end
    end
    return false
end

-- Count building type
function AIController:count_building_type(building_type)
    local count = 0
    if self.house.buildings then
        for _, building in ipairs(self.house.buildings) do
            if building.building_type == building_type then
                count = count + 1
            end
        end
    end
    return count
end

-- Count unit type
function AIController:count_unit_type(unit_type)
    local count = 0
    if self.house.units then
        for _, unit in ipairs(self.house.units) do
            if unit.unit_type == unit_type then
                count = count + 1
            end
        end
    end
    return count
end

-- Count defense buildings
function AIController:count_defenses()
    local count = 0
    local defense_types = {"GTWR", "ATWR", "GUN", "OBLI", "SAM"}

    if self.house.buildings then
        for _, building in ipairs(self.house.buildings) do
            for _, def_type in ipairs(defense_types) do
                if building.building_type == def_type then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

-- Count attack force by type
function AIController:count_attack_force_type(category)
    local count = 0
    for _, unit in ipairs(self.attack_force) do
        if unit:is_alive() then
            if category == "infantry" and unit:has("infantry") then
                count = count + 1
            elseif category == "vehicle" and unit:has("vehicle") then
                count = count + 1
            elseif category == "aircraft" and unit:has("aircraft") then
                count = count + 1
            end
        end
    end
    return count
end

-- Get power balance
function AIController:get_power_balance()
    if self.house.power then
        return self.house.power.produced - self.house.power.consumed
    end
    return 0
end

-- Update base center position
function AIController:update_base_center()
    local x, y, count = 0, 0, 0

    if self.house.buildings then
        for _, building in ipairs(self.house.buildings) do
            if building:has("transform") then
                local transform = building:get("transform")
                x = x + transform.cell_x
                y = y + transform.cell_y
                count = count + 1
            end
        end
    end

    if count > 0 then
        self.base_center_x = math.floor(x / count)
        self.base_center_y = math.floor(y / count)
    end
end

-- Get base center position
function AIController:get_base_center()
    if not self.base_center_x then
        self:update_base_center()
    end

    if self.base_center_x then
        return self.base_center_x * Constants.LEPTON_PER_CELL,
               self.base_center_y * Constants.LEPTON_PER_CELL
    end

    return 0, 0
end

-- Find attack target (enemy building or unit)
function AIController:find_attack_target()
    -- Priority: Harvesters > Construction Yard > War Factory > Refineries > Other
    local priority_targets = {"HARV", "FACT", "WEAP", "PROC", "NUKE", "NUK2"}

    -- Get all enemy entities
    local enemies = {}

    -- Would query world for enemy entities
    Events.emit("AI_GET_ENEMIES", self.house, function(entity_list)
        enemies = entity_list or {}
    end)

    -- Find highest priority target
    for _, target_type in ipairs(priority_targets) do
        for _, enemy in ipairs(enemies) do
            if enemy:is_alive() then
                local etype = enemy.unit_type or enemy.building_type
                if etype == target_type then
                    return enemy
                end
            end
        end
    end

    -- Fall back to any enemy
    for _, enemy in ipairs(enemies) do
        if enemy:is_alive() then
            return enemy
        end
    end

    return nil
end

-- Set attack target (called by game)
function AIController:set_attack_target(target)
    self.attack_target = target
end

-- Report threat (called when attacked)
function AIController:report_threat(attacker, target)
    self.threat_level = math.min(100, self.threat_level + 25)
    self.last_attack_time = love.timer.getTime()
end

-- Add unit to attack force
function AIController:add_to_attack_force(unit)
    -- Don't add duplicates
    for _, u in ipairs(self.attack_force) do
        if u == unit then
            return
        end
    end

    table.insert(self.attack_force, unit)
end

-- Remove unit from attack force
function AIController:remove_from_attack_force(unit)
    for i, u in ipairs(self.attack_force) do
        if u == unit then
            table.remove(self.attack_force, i)
            return
        end
    end
end

-- Set difficulty
function AIController:set_difficulty(difficulty)
    self.difficulty = difficulty

    -- Adjust parameters based on difficulty
    if difficulty == AIController.DIFFICULTY.EASY then
        self.think_interval = 30      -- Think every 2 seconds
        self.attack_interval = 15 * 180  -- Attack every 3 minutes
        self.min_attack_force = 3
        self.max_attack_force = 8
        self.iq = 50
        self.threat_decay = 2
        self.desired_harvesters = 1
        self.credits_reserve = 500
    elseif difficulty == AIController.DIFFICULTY.NORMAL then
        self.think_interval = 15      -- Think every second
        self.attack_interval = 15 * 120  -- Attack every 2 minutes
        self.min_attack_force = 5
        self.max_attack_force = 12
        self.iq = 100
        self.threat_decay = 1
        self.desired_harvesters = 2
        self.credits_reserve = 1000
    elseif difficulty == AIController.DIFFICULTY.HARD then
        self.think_interval = 8       -- Think twice per second
        self.attack_interval = 15 * 60   -- Attack every minute
        self.min_attack_force = 8
        self.max_attack_force = 20
        self.iq = 150
        self.threat_decay = 0.5
        self.desired_harvesters = 3
        self.credits_reserve = 500  -- More aggressive spending
    end
end

-- Create an attack team
function AIController:create_team(name, units)
    self.team_counter = self.team_counter + 1
    local team = {
        id = self.team_counter,
        name = name,
        units = units or {},
        mission = nil,
        target = nil
    }
    table.insert(self.teams, team)
    return team
end

-- Order team to attack
function AIController:order_team_attack(team, target)
    if not team or not target then return end

    team.mission = "attack"
    team.target = target

    local target_x, target_y
    if target:has("transform") then
        local t = target:get("transform")
        target_x = t.x
        target_y = t.y
    end

    for _, unit in ipairs(team.units) do
        if unit:is_alive() then
            Events.emit("AI_ORDER_UNIT", unit, "attack_move", target_x, target_y)
        end
    end
end

-- Order team to guard
function AIController:order_team_guard(team, x, y)
    if not team then return end

    team.mission = "guard"

    for _, unit in ipairs(team.units) do
        if unit:is_alive() then
            Events.emit("AI_ORDER_UNIT", unit, "guard_area", x, y)
        end
    end
end

-- Enable/disable AI
function AIController:set_enabled(enabled)
    self.enabled = enabled
end

-- Get current state
function AIController:get_state()
    return self.state
end

-- Get AI statistics
function AIController:get_stats()
    return {
        state = self.state,
        threat_level = self.threat_level,
        attack_force_size = #self.attack_force,
        attack_timer = self.attack_timer,
        buildings_built = self.stats.buildings_built,
        units_built = self.stats.units_built,
        attacks_launched = self.stats.attacks_launched
    }
end

--============================================================================
-- TeamSystem Integration
--============================================================================

--[[
    Set the team system reference for coordinated attacks.

    @param team_system - TeamSystem instance for creating attack teams
]]
function AIController:set_team_system(team_system)
    self.team_system = team_system
end

--[[
    Create an attack team from current attack force.

    Converts the accumulated attack_force into a proper TeamClass
    with coordinated movement and attack behavior.

    @param target_x, target_y - Target coordinates in leptons
    @return team ID or nil if team creation failed
]]
function AIController:create_attack_team(target_x, target_y)
    if not self.team_system then
        return nil
    end

    -- Need minimum force for a team
    if #self.attack_force < self.min_attack_force then
        return nil
    end

    -- Generate team name
    self.team_counter = self.team_counter + 1
    local team_name = string.format("AI_Attack_%d", self.team_counter)

    -- Build team composition from attack force
    local composition = {}
    local unit_counts = {}

    for _, unit in ipairs(self.attack_force) do
        if unit:is_alive() then
            local unit_type = "E1"  -- Default to minigunner
            if unit:has("unit_type") then
                unit_type = unit:get("unit_type").type_name or unit_type
            end

            unit_counts[unit_type] = (unit_counts[unit_type] or 0) + 1
        end
    end

    -- Convert to team member format
    for unit_type, count in pairs(unit_counts) do
        table.insert(composition, {
            type = unit_type,
            count = count
        })
    end

    -- Register dynamic team type
    local team_type = {
        name = team_name,
        house = self.house,
        members = composition,
        mission = "ATTACK_BASE",
        waypoints = {},  -- Direct attack, no waypoints
        roundabout = false,
        suicide = false,
        learning = true,  -- Can retreat if losing
        autocreate = false,
        prebuilt = false,
        reinforcable = false
    }

    -- Register with team system
    self.team_system:register_team_type(team_name, team_type)

    -- Create the team using existing units
    local team = self.team_system:create_team_from_units(team_name, self.attack_force)

    if team then
        -- Set attack target
        team.target_x = target_x
        team.target_y = target_y

        -- Store in our team tracking
        self.teams[team.id] = team

        -- Clear attack force (now managed by team)
        self.attack_force = {}

        return team.id
    end

    return nil
end

--[[
    Create a defense team from nearby units.

    Recruits idle units near the base to defend against attackers.

    @param threat_x, threat_y - Position of the threat
    @return team ID or nil
]]
function AIController:create_defense_team(threat_x, threat_y)
    if not self.team_system then
        return nil
    end

    -- Gather nearby idle units
    local defenders = {}
    local base_x = (self.base_center_x or 32) * 256  -- Convert cells to leptons
    local base_y = (self.base_center_y or 32) * 256

    -- Would iterate through house's units and find idle ones near base
    -- For now, emit event for game to handle
    Events.emit("AI_GATHER_DEFENDERS", self.house, base_x, base_y, self.defense_radius * 256)

    return nil  -- Defenders handled via event
end

--[[
    Update all managed teams.

    Called each AI tick to monitor team status and reassign
    units from disbanded teams.
]]
function AIController:update_teams()
    if not self.team_system then
        return
    end

    local teams_to_remove = {}

    for team_id, team in pairs(self.teams) do
        -- Check if team still exists in team system
        local team_data = self.team_system:get_team(team_id)

        if not team_data then
            -- Team disbanded, mark for removal
            table.insert(teams_to_remove, team_id)
        elseif team_data.formed == false then
            -- Team lost too many members
            table.insert(teams_to_remove, team_id)
        end
    end

    -- Clean up disbanded teams
    for _, team_id in ipairs(teams_to_remove) do
        self.teams[team_id] = nil
    end
end

--[[
    Check if we should create an attack team instead of direct attack.

    Returns true if TeamSystem is available and attack force is
    large enough to warrant coordinated team behavior.

    @return true if should use team-based attack
]]
function AIController:should_use_team_attack()
    if not self.team_system then
        return false
    end

    -- Use teams for larger attacks
    return #self.attack_force >= 8
end

return AIController
