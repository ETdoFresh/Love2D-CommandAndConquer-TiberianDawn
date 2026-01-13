--[[
    House - Faction/player class managing economy, units, and buildings
    Reference: HOUSE.H, HOUSE.CPP from original C&C source
]]

local Events = require("src.core.events")

-- Lazy load FactoryClass to avoid circular dependency
local FactoryClass = nil

local House = {}
House.__index = House

-- House types matching original (from DEFINES.H)
House.TYPE = {
    GOOD = 0,       -- GDI
    BAD = 1,        -- NOD
    NEUTRAL = 2,    -- Civilians
    JP = 3,         -- Special/Jurassic Park
    MULTI1 = 4,
    MULTI2 = 5,
    MULTI3 = 6,
    MULTI4 = 7,
    MULTI5 = 8,
    MULTI6 = 9
}

-- Side/faction affiliation
House.SIDE = {
    GDI = "GDI",
    NOD = "NOD",
    NEUTRAL = "NEUTRAL",
    SPECIAL = "SPECIAL"
}

-- House colors (remap indices)
House.COLORS = {
    GOLD = 0,
    RED = 1,
    LTBLUE = 2,
    ORANGE = 3,
    GREEN = 4,
    BLUE = 5
}

function House.new(house_type, name)
    local self = setmetatable({}, House)

    -- Identity
    self.type = house_type
    self.name = name or House.get_name_for_type(house_type)
    self.side = House.get_side_for_type(house_type)

    -- Economy
    self.credits = 0
    self.credits_capacity = 0  -- Silos + refineries
    self.tiberium = 0          -- Raw tiberium count (for refinery processing)

    -- Power
    self.power_output = 0
    self.power_drain = 0

    -- Unit/building limits
    self.max_units = 50
    self.max_buildings = 50
    self.unit_count = 0
    self.building_count = 0

    -- Entity tracking
    self.units = {}           -- All owned units
    self.buildings = {}       -- All owned buildings
    self.aircraft = {}        -- All owned aircraft

    -- Production
    self.factories = {
        infantry = nil,       -- Primary barracks
        vehicle = nil,        -- Primary war factory
        aircraft = nil,       -- Primary helipad/airfield
        building = nil        -- Primary construction yard
    }
    self.build_queue = {}

    -- Factory objects (FactoryClass instances for active production)
    self.infantry_factory = nil   -- Current infantry production
    self.unit_factory = nil       -- Current vehicle production
    self.aircraft_factory = nil   -- Current aircraft production
    self.building_factory = nil   -- Current building production

    -- Factory counts (for production acceleration)
    self.infantry_factories = 0
    self.unit_factories = 0
    self.aircraft_factories = 0
    self.building_factories = 0

    -- Cost/speed modifiers
    self.cost_bias = 1.0          -- Cost multiplier (difficulty)
    self.build_time_bias = 1.0    -- Build speed multiplier

    -- Tech level and prerequisites
    self.tech_level = 1
    self.owned_building_types = {}  -- Set of building types owned

    -- Special weapons
    self.special_weapons = {
        ion_cannon = {available = false, ready = false, charge = 0, max_charge = 600},
        nuke = {available = false, ready = false, charge = 0, max_charge = 900},
        airstrike = {available = false, ready = false, charge = 0, max_charge = 450}
    }

    -- Diplomacy
    self.allies = {}           -- House types we're allied with
    self.enemies = {}          -- House types we're at war with
    self.is_defeated = false
    self.is_player = false
    self.is_human = false

    -- AI state
    self.ai_difficulty = 2     -- 1=Easy, 2=Normal, 3=Hard
    self.iq = 0                -- AI intelligence level

    -- Visibility
    self.radar_active = false
    self.has_power = true

    -- Statistics
    self.stats = {
        units_built = 0,
        units_lost = 0,
        units_killed = 0,
        buildings_built = 0,
        buildings_lost = 0,
        buildings_destroyed = 0,
        credits_harvested = 0,
        credits_spent = 0
    }

    -- Color (for rendering)
    self.color = House.get_default_color(house_type)
    self.color_remap = House.COLORS.GOLD

    return self
end

-- Get name for house type
function House.get_name_for_type(house_type)
    local names = {
        [House.TYPE.GOOD] = "GDI",
        [House.TYPE.BAD] = "NOD",
        [House.TYPE.NEUTRAL] = "Civilian",
        [House.TYPE.JP] = "Special",
        [House.TYPE.MULTI1] = "Player 1",
        [House.TYPE.MULTI2] = "Player 2",
        [House.TYPE.MULTI3] = "Player 3",
        [House.TYPE.MULTI4] = "Player 4",
        [House.TYPE.MULTI5] = "Player 5",
        [House.TYPE.MULTI6] = "Player 6"
    }
    return names[house_type] or "Unknown"
end

-- Get side for house type
function House.get_side_for_type(house_type)
    if house_type == House.TYPE.GOOD then
        return House.SIDE.GDI
    elseif house_type == House.TYPE.BAD then
        return House.SIDE.NOD
    elseif house_type == House.TYPE.NEUTRAL then
        return House.SIDE.NEUTRAL
    elseif house_type == House.TYPE.JP then
        return House.SIDE.SPECIAL
    else
        -- Multiplayer houses default to GDI side (can be changed)
        return House.SIDE.GDI
    end
end

-- Get default color for house type
function House.get_default_color(house_type)
    local colors = {
        [House.TYPE.GOOD] = {1, 0.8, 0},      -- Gold
        [House.TYPE.BAD] = {0.8, 0, 0},       -- Red
        [House.TYPE.NEUTRAL] = {0.8, 0.8, 0}, -- Yellow
        [House.TYPE.JP] = {0, 0.8, 0.8},      -- Cyan
        [House.TYPE.MULTI1] = {1, 0.8, 0},    -- Gold
        [House.TYPE.MULTI2] = {0.8, 0, 0},    -- Red
        [House.TYPE.MULTI3] = {0, 0.8, 0},    -- Green
        [House.TYPE.MULTI4] = {0, 0, 0.8},    -- Blue
        [House.TYPE.MULTI5] = {1, 0.5, 0},    -- Orange
        [House.TYPE.MULTI6] = {0.8, 0, 0.8}   -- Purple
    }
    return colors[house_type] or {1, 1, 1}
end

-- Credit management
function House:add_credits(amount)
    local old_credits = self.credits
    self.credits = self.credits + amount

    -- Cap at capacity if set
    if self.credits_capacity > 0 and self.credits > self.credits_capacity then
        self.credits = self.credits_capacity
    end

    if amount > 0 then
        self.stats.credits_harvested = self.stats.credits_harvested + amount
    end

    Events.emit("CREDITS_CHANGED", self, old_credits, self.credits)
    return self.credits
end

function House:spend_credits(amount)
    if self.credits >= amount then
        self.credits = self.credits - amount
        self.stats.credits_spent = self.stats.credits_spent + amount
        Events.emit("CREDITS_CHANGED", self, self.credits + amount, self.credits)
        return true
    end
    return false
end

function House:can_afford(cost)
    return self.credits >= cost
end

function House:get_credits()
    return self.credits
end

function House:available_money()
    return self.credits
end

-- Capacity management
function House:update_capacity()
    local capacity = 0

    for _, building in ipairs(self.buildings) do
        local building_data = building.building_data
        if building_data then
            capacity = capacity + (building_data.storage or 0)
        end
    end

    self.credits_capacity = capacity
    return capacity
end

-- Power management
function House:update_power()
    local output = 0
    local drain = 0

    for _, building in ipairs(self.buildings) do
        local building_data = building.building_data
        if building_data then
            output = output + (building_data.power_output or 0)
            drain = drain + (building_data.power_drain or 0)
        end
    end

    self.power_output = output
    self.power_drain = drain
    self.has_power = output >= drain

    Events.emit("POWER_CHANGED", self, output, drain)
    return output, drain
end

function House:get_power_ratio()
    if self.power_drain == 0 then return 1 end
    return math.min(1, self.power_output / self.power_drain)
end

function House:is_low_power()
    return not self.has_power
end

-- Entity management
function House:add_unit(entity)
    table.insert(self.units, entity)
    self.unit_count = #self.units
    self.stats.units_built = self.stats.units_built + 1
    Events.emit("UNIT_ADDED", self, entity)
end

function House:remove_unit(entity)
    for i, unit in ipairs(self.units) do
        if unit == entity then
            table.remove(self.units, i)
            self.unit_count = #self.units
            self.stats.units_lost = self.stats.units_lost + 1
            Events.emit("UNIT_REMOVED", self, entity)
            return true
        end
    end
    return false
end

function House:add_building(entity)
    table.insert(self.buildings, entity)
    self.building_count = #self.buildings

    -- Track building type for prerequisites
    local building_type = entity.building_type
    if building_type then
        self.owned_building_types[building_type] = (self.owned_building_types[building_type] or 0) + 1
    end

    self.stats.buildings_built = self.stats.buildings_built + 1

    -- Update power and capacity
    self:update_power()
    self:update_capacity()

    -- Check for special buildings
    self:check_special_buildings(entity, true)

    -- Update factory counts
    self:update_factory_counts()

    Events.emit("BUILDING_ADDED", self, entity)
end

function House:remove_building(entity)
    for i, building in ipairs(self.buildings) do
        if building == entity then
            table.remove(self.buildings, i)
            self.building_count = #self.buildings

            -- Update building type count
            local building_type = entity.building_type
            if building_type and self.owned_building_types[building_type] then
                self.owned_building_types[building_type] = self.owned_building_types[building_type] - 1
                if self.owned_building_types[building_type] <= 0 then
                    self.owned_building_types[building_type] = nil
                end
            end

            self.stats.buildings_lost = self.stats.buildings_lost + 1

            -- Update power and capacity
            self:update_power()
            self:update_capacity()

            -- Check special buildings
            self:check_special_buildings(entity, false)

            -- Update factory counts
            self:update_factory_counts()

            Events.emit("BUILDING_REMOVED", self, entity)
            return true
        end
    end
    return false
end

-- Check for special buildings (radar, super weapons, etc.)
function House:check_special_buildings(entity, added)
    local building_type = entity.building_type

    -- Radar/Communications Center
    if building_type == "HQ" or building_type == "COMM" then
        self:update_radar()
    end

    -- Ion Cannon (Advanced Comm Center)
    if building_type == "EYE" then
        self.special_weapons.ion_cannon.available = added
        if not added then
            self.special_weapons.ion_cannon.ready = false
        end
    end

    -- Temple of Nod (Nuke)
    if building_type == "TMPL" then
        self.special_weapons.nuke.available = added
        if not added then
            self.special_weapons.nuke.ready = false
        end
    end

    -- Airstrip (Airstrike capability)
    if building_type == "AFLD" then
        self.special_weapons.airstrike.available = added
        if not added then
            self.special_weapons.airstrike.ready = false
        end
    end

    -- Update primary factories
    self:update_primary_factories()
end

-- Update radar status
function House:update_radar()
    local has_radar = false

    for _, building in ipairs(self.buildings) do
        local bt = building.building_type
        if bt == "HQ" or bt == "COMM" or bt == "EYE" then
            has_radar = true
            break
        end
    end

    self.radar_active = has_radar and self.has_power
    Events.emit("RADAR_CHANGED", self, self.radar_active)
end

-- Update primary factories
function House:update_primary_factories()
    -- Reset primaries if they're gone
    for factory_type, factory in pairs(self.factories) do
        if factory then
            local found = false
            for _, building in ipairs(self.buildings) do
                if building == factory then
                    found = true
                    break
                end
            end
            if not found then
                self.factories[factory_type] = nil
            end
        end
    end

    -- Auto-assign primaries if not set
    for _, building in ipairs(self.buildings) do
        local bt = building.building_type

        -- Infantry production
        if (bt == "PYLE" or bt == "HAND") and not self.factories.infantry then
            self.factories.infantry = building
        end

        -- Vehicle production
        if bt == "WEAP" and not self.factories.vehicle then
            self.factories.vehicle = building
        end

        -- Aircraft production
        if (bt == "AFLD" or bt == "HPAD") and not self.factories.aircraft then
            self.factories.aircraft = building
        end

        -- Building production
        if bt == "FACT" and not self.factories.building then
            self.factories.building = building
        end
    end
end

-- Set primary factory
function House:set_primary_factory(factory_type, building)
    self.factories[factory_type] = building
    Events.emit("PRIMARY_FACTORY_SET", self, factory_type, building)
end

-- Check if we have a building type
function House:has_building_type(building_type)
    return (self.owned_building_types[building_type] or 0) > 0
end

-- Check prerequisites for building/unit
function House:meets_prerequisites(prerequisites)
    -- Handle nil or 0 (PREREQ.NONE)
    if not prerequisites or prerequisites == 0 then
        return true
    end

    -- Handle table of building type names (legacy)
    if type(prerequisites) == "table" then
        if #prerequisites == 0 then
            return true
        end
        for _, prereq in ipairs(prerequisites) do
            if not self:has_building_type(prereq) then
                return false
            end
        end
        return true
    end

    -- Handle bitfield prerequisites (from TechnoTypeClass)
    -- For now, allow production if we have the factory - full prerequisite
    -- checking will be done when tech tree is properly integrated
    return true
end

-- Special weapon management
function House:update_special_weapons(dt)
    for name, weapon in pairs(self.special_weapons) do
        if weapon.available and not weapon.ready then
            weapon.charge = weapon.charge + dt * 15  -- Game ticks
            if weapon.charge >= weapon.max_charge then
                weapon.charge = weapon.max_charge
                weapon.ready = true
                Events.emit("SPECIAL_WEAPON_READY", self, name)
            end
        end
    end
end

function House:use_special_weapon(weapon_name)
    local weapon = self.special_weapons[weapon_name]
    if weapon and weapon.available and weapon.ready then
        weapon.ready = false
        weapon.charge = 0
        Events.emit("SPECIAL_WEAPON_USED", self, weapon_name)
        return true
    end
    return false
end

function House:get_special_weapon_charge(weapon_name)
    local weapon = self.special_weapons[weapon_name]
    if weapon then
        return weapon.charge / weapon.max_charge
    end
    return 0
end

-- Diplomacy
function House:is_ally(other_house)
    if other_house == self then return true end
    return self.allies[other_house.type] == true
end

function House:is_enemy(other_house)
    if other_house == self then return false end
    return self.enemies[other_house.type] == true
end

function House:set_ally(other_house, is_ally)
    if is_ally then
        self.allies[other_house.type] = true
        self.enemies[other_house.type] = nil
    else
        self.allies[other_house.type] = nil
    end
    Events.emit("DIPLOMACY_CHANGED", self, other_house, is_ally)
end

function House:set_enemy(other_house, is_enemy)
    if is_enemy then
        self.enemies[other_house.type] = true
        self.allies[other_house.type] = nil
    else
        self.enemies[other_house.type] = nil
    end
    Events.emit("DIPLOMACY_CHANGED", self, other_house, not is_enemy)
end

-- Defeat check
function House:check_defeat()
    -- Check if all buildings destroyed
    local has_buildings = #self.buildings > 0

    -- Check if has construction yard or MCV
    local can_build = self:has_building_type("FACT")
    local has_mcv = false

    for _, unit in ipairs(self.units) do
        if unit.unit_type == "MCV" then
            has_mcv = true
            break
        end
    end

    -- Defeated if no buildings and no MCV
    if not has_buildings and not has_mcv then
        self:defeat()
        return true
    end

    return false
end

function House:defeat()
    if not self.is_defeated then
        self.is_defeated = true
        Events.emit("HOUSE_DEFEATED", self)
    end
end

--============================================================================
-- Production Methods
--============================================================================

--[[
    Begin building a unit.

    @param unit_type - UnitTypeClass to build
    @return true if production started
]]
function House:Build_Unit(unit_type)
    -- Lazy load FactoryClass
    if not FactoryClass then
        FactoryClass = require("src.production.factory")
    end

    -- Check if we have a war factory
    if not self.factories.vehicle then
        return false
    end

    -- Check if already building a unit
    if self.unit_factory and self.unit_factory:Is_Building() then
        return false  -- Already building
    end

    -- Check prerequisites
    if unit_type.Prerequisites and not self:meets_prerequisites(unit_type.Prerequisites) then
        return false
    end

    -- Check cost
    local cost = unit_type.Cost or 0
    if not self:can_afford(cost) then
        return false
    end

    -- Create factory and start production
    self.unit_factory = FactoryClass:new()
    if self.unit_factory:Set(unit_type, self) then
        self.unit_factory:Start()
        Events.emit("PRODUCTION_STARTED", self, "UNIT", unit_type)
        return true
    end

    self.unit_factory = nil
    return false
end

--[[
    Begin building infantry.

    @param infantry_type - InfantryTypeClass to build
    @return true if production started
]]
function House:Build_Infantry(infantry_type)
    if not FactoryClass then
        FactoryClass = require("src.production.factory")
    end

    -- Check if we have a barracks
    if not self.factories.infantry then
        return false
    end

    -- Check if already building
    if self.infantry_factory and self.infantry_factory:Is_Building() then
        return false
    end

    -- Check prerequisites
    if infantry_type.Prerequisites and not self:meets_prerequisites(infantry_type.Prerequisites) then
        return false
    end

    -- Check cost
    local cost = infantry_type.Cost or 0
    if not self:can_afford(cost) then
        return false
    end

    -- Create factory and start production
    self.infantry_factory = FactoryClass:new()
    if self.infantry_factory:Set(infantry_type, self) then
        self.infantry_factory:Start()
        Events.emit("PRODUCTION_STARTED", self, "INFANTRY", infantry_type)
        return true
    end

    self.infantry_factory = nil
    return false
end

--[[
    Begin building aircraft.

    @param aircraft_type - AircraftTypeClass to build
    @return true if production started
]]
function House:Build_Aircraft(aircraft_type)
    if not FactoryClass then
        FactoryClass = require("src.production.factory")
    end

    -- Check if we have an airfield
    if not self.factories.aircraft then
        return false
    end

    -- Check if already building
    if self.aircraft_factory and self.aircraft_factory:Is_Building() then
        return false
    end

    -- Check prerequisites
    if aircraft_type.Prerequisites and not self:meets_prerequisites(aircraft_type.Prerequisites) then
        return false
    end

    -- Check cost
    local cost = aircraft_type.Cost or 0
    if not self:can_afford(cost) then
        return false
    end

    -- Create factory and start production
    self.aircraft_factory = FactoryClass:new()
    if self.aircraft_factory:Set(aircraft_type, self) then
        self.aircraft_factory:Start()
        Events.emit("PRODUCTION_STARTED", self, "AIRCRAFT", aircraft_type)
        return true
    end

    self.aircraft_factory = nil
    return false
end

--[[
    Begin building a structure.

    @param building_type - BuildingTypeClass to build
    @return true if production started
]]
function House:Build_Structure(building_type)
    if not FactoryClass then
        FactoryClass = require("src.production.factory")
    end

    -- Check if we have a construction yard
    if not self.factories.building then
        return false
    end

    -- Check if already building
    if self.building_factory and self.building_factory:Is_Building() then
        return false
    end

    -- Check prerequisites
    if building_type.Prerequisites and not self:meets_prerequisites(building_type.Prerequisites) then
        return false
    end

    -- Check cost
    local cost = building_type.Cost or 0
    if not self:can_afford(cost) then
        return false
    end

    -- Create factory and start production
    self.building_factory = FactoryClass:new()
    if self.building_factory:Set(building_type, self) then
        self.building_factory:Start()
        Events.emit("PRODUCTION_STARTED", self, "BUILDING", building_type)
        return true
    end

    self.building_factory = nil
    return false
end

--[[
    Cancel production of a specific type.

    @param factory_type - "UNIT", "INFANTRY", "AIRCRAFT", "BUILDING"
    @return true if cancelled
]]
function House:Cancel_Production(factory_type)
    local factory = nil

    if factory_type == "UNIT" then
        factory = self.unit_factory
        self.unit_factory = nil
    elseif factory_type == "INFANTRY" then
        factory = self.infantry_factory
        self.infantry_factory = nil
    elseif factory_type == "AIRCRAFT" then
        factory = self.aircraft_factory
        self.aircraft_factory = nil
    elseif factory_type == "BUILDING" then
        factory = self.building_factory
        self.building_factory = nil
    end

    if factory then
        factory:Abandon()
        Events.emit("PRODUCTION_CANCELLED", self, factory_type)
        return true
    end

    return false
end

--[[
    Suspend/resume production.

    @param factory_type - "UNIT", "INFANTRY", "AIRCRAFT", "BUILDING"
    @return true if toggled
]]
function House:Toggle_Production(factory_type)
    local factory = nil

    if factory_type == "UNIT" then
        factory = self.unit_factory
    elseif factory_type == "INFANTRY" then
        factory = self.infantry_factory
    elseif factory_type == "AIRCRAFT" then
        factory = self.aircraft_factory
    elseif factory_type == "BUILDING" then
        factory = self.building_factory
    end

    if factory then
        if factory:Is_Building() then
            factory:Suspend()
            Events.emit("PRODUCTION_SUSPENDED", self, factory_type)
        else
            factory:Start()
            Events.emit("PRODUCTION_RESUMED", self, factory_type)
        end
        return true
    end

    return false
end

--[[
    Get production completion percentage.

    @param factory_type - "UNIT", "INFANTRY", "AIRCRAFT", "BUILDING"
    @return Completion percentage 0-100
]]
function House:Production_Completion(factory_type)
    local factory = nil

    if factory_type == "UNIT" then
        factory = self.unit_factory
    elseif factory_type == "INFANTRY" then
        factory = self.infantry_factory
    elseif factory_type == "AIRCRAFT" then
        factory = self.aircraft_factory
    elseif factory_type == "BUILDING" then
        factory = self.building_factory
    end

    if factory then
        return factory:Completion_Percent()
    end

    return 0
end

--[[
    Check if production of a type has completed.

    @param factory_type - "UNIT", "INFANTRY", "AIRCRAFT", "BUILDING"
    @return true if ready for placement/deployment
]]
function House:Production_Ready(factory_type)
    local factory = nil

    if factory_type == "UNIT" then
        factory = self.unit_factory
    elseif factory_type == "INFANTRY" then
        factory = self.infantry_factory
    elseif factory_type == "AIRCRAFT" then
        factory = self.aircraft_factory
    elseif factory_type == "BUILDING" then
        factory = self.building_factory
    end

    if factory then
        return factory:Has_Completed()
    end

    return false
end

--[[
    Update factory counts based on owned buildings.
    Called when buildings are added/removed.
]]
function House:update_factory_counts()
    self.infantry_factories = 0
    self.unit_factories = 0
    self.aircraft_factories = 0
    self.building_factories = 0

    for _, building in ipairs(self.buildings) do
        local bt = building.building_type

        if bt == "PYLE" or bt == "HAND" then
            self.infantry_factories = self.infantry_factories + 1
        elseif bt == "WEAP" then
            self.unit_factories = self.unit_factories + 1
        elseif bt == "AFLD" or bt == "HPAD" then
            self.aircraft_factories = self.aircraft_factories + 1
        elseif bt == "FACT" then
            self.building_factories = self.building_factories + 1
        end
    end
end

-- Update (call each game tick)
function House:update(dt)
    -- Update special weapon charges
    self:update_special_weapons(dt)

    -- Update radar based on power
    if self.radar_active and not self.has_power then
        self.radar_active = false
        Events.emit("RADAR_CHANGED", self, false)
    elseif not self.radar_active and self.has_power then
        self:update_radar()
    end

    -- Update production factories
    if self.infantry_factory then
        self.infantry_factory:AI()
        if self.infantry_factory:Has_Completed() then
            Events.emit("PRODUCTION_COMPLETE", self, "INFANTRY", self.infantry_factory:Get_Object())
        end
    end
    if self.unit_factory then
        self.unit_factory:AI()
        if self.unit_factory:Has_Completed() then
            Events.emit("PRODUCTION_COMPLETE", self, "UNIT", self.unit_factory:Get_Object())
        end
    end
    if self.aircraft_factory then
        self.aircraft_factory:AI()
        if self.aircraft_factory:Has_Completed() then
            Events.emit("PRODUCTION_COMPLETE", self, "AIRCRAFT", self.aircraft_factory:Get_Object())
        end
    end
    if self.building_factory then
        self.building_factory:AI()
        if self.building_factory:Has_Completed() then
            Events.emit("PRODUCTION_COMPLETE", self, "BUILDING", self.building_factory:Get_Object())
        end
    end
end

-- Serialize for save/load
function House:serialize()
    return {
        type = self.type,
        name = self.name,
        side = self.side,
        credits = self.credits,
        tech_level = self.tech_level,
        is_defeated = self.is_defeated,
        is_player = self.is_player,
        is_human = self.is_human,
        color_remap = self.color_remap,
        stats = self.stats,
        special_weapons = self.special_weapons
    }
end

-- Deserialize
function House.deserialize(data)
    local house = House.new(data.type, data.name)
    house.side = data.side
    house.credits = data.credits
    house.tech_level = data.tech_level
    house.is_defeated = data.is_defeated
    house.is_player = data.is_player
    house.is_human = data.is_human
    house.color_remap = data.color_remap
    house.stats = data.stats
    house.special_weapons = data.special_weapons
    return house
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of house state.
    Reference: HOUSE.H Debug_Dump() pattern
]]
function House:Debug_Dump()
    print(string.format("HouseClass: name=%s type=%d side=%s",
        self.name, self.type, self.side))
    print(string.format("  Economy: credits=%d capacity=%d tiberium=%d",
        self.credits, self.credits_capacity, self.tiberium))
    print(string.format("  Power: output=%d drain=%d has_power=%s",
        self.power_output, self.power_drain, tostring(self.has_power)))
    print(string.format("  Units: count=%d max=%d buildings=%d/%d",
        self.unit_count, self.max_units, self.building_count, self.max_buildings))
    print(string.format("  Flags: is_player=%s is_human=%s is_defeated=%s radar=%s",
        tostring(self.is_player), tostring(self.is_human),
        tostring(self.is_defeated), tostring(self.radar_active)))
    print(string.format("  AI: difficulty=%d iq=%d tech_level=%d",
        self.ai_difficulty, self.iq, self.tech_level))

    -- Factory counts
    print(string.format("  Factories: infantry=%d unit=%d aircraft=%d building=%d",
        self.infantry_factories, self.unit_factories,
        self.aircraft_factories, self.building_factories))

    -- Special weapons
    for name, weapon in pairs(self.special_weapons) do
        if weapon.available then
            print(string.format("  SpecialWeapon[%s]: ready=%s charge=%d/%d",
                name, tostring(weapon.ready), weapon.charge, weapon.max_charge))
        end
    end

    -- Statistics
    print(string.format("  Stats: units_built=%d units_lost=%d units_killed=%d",
        self.stats.units_built, self.stats.units_lost, self.stats.units_killed))
    print(string.format("  Stats: buildings_built=%d buildings_lost=%d buildings_destroyed=%d",
        self.stats.buildings_built, self.stats.buildings_lost, self.stats.buildings_destroyed))
    print(string.format("  Stats: credits_harvested=%d credits_spent=%d",
        self.stats.credits_harvested, self.stats.credits_spent))
end

return House
