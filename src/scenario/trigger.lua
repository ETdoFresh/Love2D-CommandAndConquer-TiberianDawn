--[[
    Trigger System - Runtime trigger evaluation and execution
    Handles game events and conditions matching original C&C behavior
]]

local Events = require("src.core.events")
local Constants = require("src.core.constants")

local TriggerSystem = {}
TriggerSystem.__index = TriggerSystem

-- House string to constant mapping
TriggerSystem.HOUSE_MAP = {
    GoodGuy = Constants.HOUSE.GOOD,
    BadGuy = Constants.HOUSE.BAD,
    Neutral = Constants.HOUSE.NEUTRAL,
    Special = Constants.HOUSE.JP,
    Multi1 = Constants.HOUSE.MULTI1,
    Multi2 = Constants.HOUSE.MULTI2,
    Multi3 = Constants.HOUSE.MULTI3,
    Multi4 = Constants.HOUSE.MULTI4,
    GOOD = Constants.HOUSE.GOOD,
    BAD = Constants.HOUSE.BAD
}

-- Event types (matching original)
TriggerSystem.EVENT = {
    NONE = 0,
    ENTERED_BY = 1,
    SPIED_BY = 2,
    THIEVED_BY = 3,
    DISCOVERED_BY = 4,
    HOUSE_DISCOVERED = 5,
    ATTACKED = 6,
    DESTROYED = 7,
    ANY_EVENT = 8,
    NO_BUILDINGS_LEFT = 9,
    ALL_UNITS_DESTROYED = 10,
    ALL_DESTROYED = 11,
    CREDITS_EXCEED = 12,
    TIME_ELAPSED = 13,
    MISSION_TIMER_EXPIRED = 14,
    BUILDINGS_DESTROYED = 15,
    UNITS_DESTROYED = 16,
    NOFACTORY = 17,
    CIVILIAN_EVACUATED = 18,
    BUILD_BUILDING_TYPE = 19,
    BUILD_UNIT_TYPE = 20,
    BUILD_INFANTRY_TYPE = 21,
    BUILD_AIRCRAFT_TYPE = 22,
    LEAVES_MAP = 23,
    ZONE_ENTRY = 24,
    CROSSES_HORIZONTAL = 25,
    CROSSES_VERTICAL = 26,
    GLOBAL_SET = 27,
    GLOBAL_CLEAR = 28,
    DESTROYED_BY_ANYONE = 29,
    LOW_POWER = 30,
    BRIDGE_DESTROYED = 31,
    BUILDING_EXISTS = 32
}

-- Action types
TriggerSystem.ACTION = {
    NONE = 0,
    WIN = 1,
    LOSE = 2,
    PRODUCTION_BEGINS = 3,
    CREATE_TEAM = 4,
    DESTROY_TEAM = 5,
    ALL_TO_HUNT = 6,
    REINFORCEMENT = 7,
    DROP_ZONE_FLARE = 8,
    FIRE_SALE = 9,
    PLAY_MOVIE = 10,
    TEXT = 11,
    DESTROY_TRIGGER = 12,
    AUTOCREATE = 13,
    ALLOW_WIN = 14,
    REVEAL_MAP = 15,
    REVEAL_ZONE = 16,
    PLAY_SOUND = 17,
    PLAY_MUSIC = 18,
    PLAY_SPEECH = 19,
    FORCE_TRIGGER = 20,
    TIMER_START = 21,
    TIMER_STOP = 22,
    TIMER_EXTEND = 23,
    TIMER_SHORTEN = 24,
    TIMER_SET = 25,
    GLOBAL_SET = 26,
    GLOBAL_CLEAR = 27,
    AUTO_BASE_AI = 28,
    GROW_TIBERIUM = 29,
    DESTROY_ATTACHED = 30,
    ADD_1TIME_SPECIAL = 31,
    ADD_REPEATING_SPECIAL = 32,
    PREFERRED_TARGET = 33,
    LAUNCH_NUKES = 34
}

function TriggerSystem.new(world, game)
    local self = setmetatable({}, TriggerSystem)

    self.world = world
    self.game = game

    -- All triggers in scenario
    self.triggers = {}

    -- Global flags (32 available)
    self.globals = {}
    for i = 0, 31 do
        self.globals[i] = false
    end

    -- Cell triggers (cell -> trigger name)
    self.cell_triggers = {}

    -- Object triggers (entity id -> trigger name)
    self.object_triggers = {}

    -- Mission timer
    self.mission_timer = 0
    self.mission_timer_running = false
    self.mission_timer_direction = -1  -- -1 = countdown, 1 = countup

    -- Statistics per house for event checking
    self.house_stats = {}

    -- Pending actions queue
    self.pending_actions = {}

    -- Win/Lose state
    self.win_allowed = true
    self.game_over = false
    self.victory = false

    -- Register event listeners
    self:register_events()

    return self
end

-- Register for game events
function TriggerSystem:register_events()
    Events.on(Events.EVENTS.ENTITY_DESTROYED, function(entity, attacker)
        self:on_entity_destroyed(entity, attacker)
    end)

    Events.on(Events.EVENTS.ENTITY_ATTACKED, function(entity, attacker)
        self:on_entity_attacked(entity, attacker)
    end)

    Events.on(Events.EVENTS.UNIT_BUILT, function(entity, house)
        self:on_unit_built(entity, house)
    end)

    Events.on(Events.EVENTS.BUILDING_BUILT, function(entity, house)
        self:on_building_built(entity, house)
    end)

    -- Automated house statistics tracking
    Events.on(Events.EVENTS.CREDITS_CHANGED, function(house, credits)
        self:ensure_house_stats(house)
        self.house_stats[house].credits = credits
    end)

    Events.on(Events.EVENTS.POWER_CHANGED, function(house, produced, consumed)
        self:ensure_house_stats(house)
        self.house_stats[house].power_output = produced
        self.house_stats[house].power_drain = consumed
    end)
end

-- Ensure house_stats entry exists for a house
function TriggerSystem:ensure_house_stats(house)
    if not self.house_stats[house] then
        self.house_stats[house] = {
            credits = 0,
            units = 0,
            buildings = 0,
            power_output = 0,
            power_drain = 0,
            -- Per-type destruction tracking for campaign triggers
            destroyed_building_types = {},  -- e.g., {PROC = 2, HAND = 1}
            destroyed_unit_types = {},      -- e.g., {E1 = 5, MTNK = 2}
            building_type_counts = {},      -- Current count of each building type
            unit_type_counts = {}           -- Current count of each unit type
        }
    end
end

-- Track destruction of specific entity types (for campaign mission objectives)
function TriggerSystem:track_entity_destroyed(entity, attacker)
    local owner = entity:has("owner") and entity:get("owner")
    if not owner then return end

    local house = owner.house
    self:ensure_house_stats(house)
    local stats = self.house_stats[house]

    if entity:has("building") then
        local building = entity:get("building")
        local btype = building.structure_type or building.building_type

        if btype then
            -- Track destroyed building type count
            stats.destroyed_building_types[btype] = (stats.destroyed_building_types[btype] or 0) + 1

            -- Decrement current count
            stats.building_type_counts[btype] = math.max(0, (stats.building_type_counts[btype] or 1) - 1)

            -- Check triggers for specific building destruction
            self:check_event(TriggerSystem.EVENT.BUILDINGS_DESTROYED, house, btype)

            -- Check if all buildings of this type are destroyed
            if stats.building_type_counts[btype] == 0 then
                self:check_event(TriggerSystem.EVENT.BUILDING_EXISTS, house, btype)
            end
        end

    elseif entity:has("infantry") then
        local infantry = entity:get("infantry")
        local utype = infantry.infantry_type

        if utype then
            stats.destroyed_unit_types[utype] = (stats.destroyed_unit_types[utype] or 0) + 1
            stats.unit_type_counts[utype] = math.max(0, (stats.unit_type_counts[utype] or 1) - 1)
            self:check_event(TriggerSystem.EVENT.UNITS_DESTROYED, house, utype)
        end

    elseif entity:has("vehicle") then
        local vehicle = entity:get("vehicle")
        local utype = vehicle.vehicle_type

        if utype then
            stats.destroyed_unit_types[utype] = (stats.destroyed_unit_types[utype] or 0) + 1
            stats.unit_type_counts[utype] = math.max(0, (stats.unit_type_counts[utype] or 1) - 1)
            self:check_event(TriggerSystem.EVENT.UNITS_DESTROYED, house, utype)
        end
    end
end

-- Track entity creation (for counting current unit/building types)
function TriggerSystem:track_entity_created(entity)
    local owner = entity:has("owner") and entity:get("owner")
    if not owner then return end

    local house = owner.house
    self:ensure_house_stats(house)
    local stats = self.house_stats[house]

    if entity:has("building") then
        local building = entity:get("building")
        local btype = building.structure_type or building.building_type

        if btype then
            stats.building_type_counts[btype] = (stats.building_type_counts[btype] or 0) + 1
        end

    elseif entity:has("infantry") then
        local infantry = entity:get("infantry")
        local utype = infantry.infantry_type

        if utype then
            stats.unit_type_counts[utype] = (stats.unit_type_counts[utype] or 0) + 1
        end

    elseif entity:has("vehicle") then
        local vehicle = entity:get("vehicle")
        local utype = vehicle.vehicle_type

        if utype then
            stats.unit_type_counts[utype] = (stats.unit_type_counts[utype] or 0) + 1
        end
    end
end

-- Get count of destroyed entities of a specific type
function TriggerSystem:get_destroyed_count(house, entity_type, is_building)
    self:ensure_house_stats(house)
    local stats = self.house_stats[house]

    if is_building then
        return stats.destroyed_building_types[entity_type] or 0
    else
        return stats.destroyed_unit_types[entity_type] or 0
    end
end

-- Check if a specific building type still exists for a house
function TriggerSystem:building_type_exists(house, building_type)
    self:ensure_house_stats(house)
    return (self.house_stats[house].building_type_counts[building_type] or 0) > 0
end

-- Convert house string to constant
function TriggerSystem:house_to_constant(house_str)
    if type(house_str) == "number" then
        return house_str
    end
    return TriggerSystem.HOUSE_MAP[house_str] or Constants.HOUSE.NEUTRAL
end

-- Load triggers from scenario data
function TriggerSystem:load_triggers(trigger_data)
    self.triggers = {}

    for _, t in ipairs(trigger_data) do
        local trigger = {
            name = t.name,
            house = self:house_to_constant(t.house or "GOOD"),  -- Convert to numeric constant
            event = t.event or TriggerSystem.EVENT.NONE,
            event_param = t.event_param or 0,
            action = t.action or TriggerSystem.ACTION.NONE,
            action_param = t.action_param or 0,
            team = t.team,
            repeatable = t.repeatable or false,
            persistent = t.persistent or false,
            enabled = true,
            fired = false
        }

        self.triggers[trigger.name] = trigger
    end
end

-- Load cell triggers
function TriggerSystem:load_cell_triggers(cell_trigger_data)
    self.cell_triggers = {}

    for _, ct in ipairs(cell_trigger_data) do
        local key = ct.cell_x .. "," .. ct.cell_y
        self.cell_triggers[key] = ct.trigger
    end
end

-- Add a single cell trigger
function TriggerSystem:add_cell_trigger(cell_x, cell_y, trigger_name)
    local key = cell_x .. "," .. cell_y
    self.cell_triggers[key] = trigger_name
end

-- Attach trigger to entity
function TriggerSystem:attach_to_entity(entity_id, trigger_name)
    self.object_triggers[entity_id] = trigger_name
end

-- Get trigger by name
function TriggerSystem:get_trigger(name)
    return self.triggers[name]
end

-- Enable/disable trigger
function TriggerSystem:set_enabled(name, enabled)
    local trigger = self.triggers[name]
    if trigger then
        trigger.enabled = enabled
    end
end

-- Set global flag
function TriggerSystem:set_global(index, value)
    if index >= 0 and index <= 31 then
        local old_value = self.globals[index]
        self.globals[index] = value

        -- Check triggers that depend on globals
        if value and not old_value then
            self:check_event(TriggerSystem.EVENT.GLOBAL_SET, nil, index)
        elseif not value and old_value then
            self:check_event(TriggerSystem.EVENT.GLOBAL_CLEAR, nil, index)
        end
    end
end

-- Get global flag
function TriggerSystem:get_global(index)
    if index >= 0 and index <= 31 then
        return self.globals[index]
    end
    return false
end

-- Update trigger system
function TriggerSystem:update(dt)
    if self.game_over then return end

    -- Update mission timer
    if self.mission_timer_running then
        self.mission_timer = self.mission_timer + dt * self.mission_timer_direction

        if self.mission_timer <= 0 and self.mission_timer_direction == -1 then
            self.mission_timer = 0
            self.mission_timer_running = false
            self:check_event(TriggerSystem.EVENT.MISSION_TIMER_EXPIRED, nil, 0)
        end
    end

    -- Process pending actions
    self:process_pending_actions(dt)

    -- Periodic checks
    self:check_periodic_events()
end

-- Check periodic events (buildings/units destroyed counts, etc.)
function TriggerSystem:check_periodic_events()
    for _, trigger in pairs(self.triggers) do
        if trigger.enabled and not trigger.fired then
            local should_fire = false

            if trigger.event == TriggerSystem.EVENT.TIME_ELAPSED then
                -- Check game time
                if self.game and self.game.tick_count then
                    local elapsed_seconds = self.game.tick_count / 15  -- 15 FPS
                    if elapsed_seconds >= trigger.event_param then
                        should_fire = true
                    end
                end

            elseif trigger.event == TriggerSystem.EVENT.CREDITS_EXCEED then
                -- Check house credits
                local stats = self.house_stats[trigger.house]
                if stats and stats.credits >= trigger.event_param then
                    should_fire = true
                end

            elseif trigger.event == TriggerSystem.EVENT.NO_BUILDINGS_LEFT then
                local stats = self.house_stats[trigger.house]
                if stats and stats.buildings == 0 then
                    should_fire = true
                end

            elseif trigger.event == TriggerSystem.EVENT.ALL_UNITS_DESTROYED then
                local stats = self.house_stats[trigger.house]
                if stats and stats.units == 0 then
                    should_fire = true
                end

            elseif trigger.event == TriggerSystem.EVENT.ALL_DESTROYED then
                local stats = self.house_stats[trigger.house]
                if stats and stats.buildings == 0 and stats.units == 0 then
                    should_fire = true
                end

            elseif trigger.event == TriggerSystem.EVENT.LOW_POWER then
                local stats = self.house_stats[trigger.house]
                if stats and stats.power_drain > stats.power_output then
                    should_fire = true
                end
            end

            if should_fire then
                self:fire_trigger(trigger)
            end
        end
    end
end

-- Check if event should fire any triggers
function TriggerSystem:check_event(event_type, house, param)
    for _, trigger in pairs(self.triggers) do
        if trigger.enabled and not trigger.fired then
            if trigger.event == event_type then
                if trigger.house == house or trigger.event == TriggerSystem.EVENT.ANY_EVENT then
                    if trigger.event_param == 0 or trigger.event_param == param then
                        self:fire_trigger(trigger)
                    end
                end
            end
        end
    end
end

-- Fire a trigger
function TriggerSystem:fire_trigger(trigger)
    if not trigger.repeatable then
        trigger.fired = true
    end

    -- Queue the action
    table.insert(self.pending_actions, {
        trigger = trigger,
        action = trigger.action,
        param = trigger.action_param,
        delay = 0
    })

    Events.emit("TRIGGER_FIRED", trigger.name)
end

-- Process pending actions
function TriggerSystem:process_pending_actions(dt)
    local i = 1
    while i <= #self.pending_actions do
        local action = self.pending_actions[i]

        action.delay = action.delay - dt
        if action.delay <= 0 then
            self:execute_action(action.trigger, action.action, action.param)
            table.remove(self.pending_actions, i)
        else
            i = i + 1
        end
    end
end

-- Execute a trigger action
function TriggerSystem:execute_action(trigger, action, param)
    if action == TriggerSystem.ACTION.WIN then
        if self.win_allowed then
            self.game_over = true
            self.victory = true
            Events.emit(Events.EVENTS.GAME_WIN, trigger.house)
        end

    elseif action == TriggerSystem.ACTION.LOSE then
        self.game_over = true
        self.victory = false
        Events.emit(Events.EVENTS.GAME_LOSE, trigger.house)

    elseif action == TriggerSystem.ACTION.CREATE_TEAM then
        Events.emit("CREATE_TEAM", param)

    elseif action == TriggerSystem.ACTION.DESTROY_TEAM then
        Events.emit("DESTROY_TEAM", param)

    elseif action == TriggerSystem.ACTION.ALL_TO_HUNT then
        Events.emit("ALL_TO_HUNT", trigger.house)

    elseif action == TriggerSystem.ACTION.REINFORCEMENT then
        Events.emit("REINFORCEMENT", trigger.team, param)

    elseif action == TriggerSystem.ACTION.DROP_ZONE_FLARE then
        Events.emit("DROP_FLARE", param)

    elseif action == TriggerSystem.ACTION.FIRE_SALE then
        Events.emit("FIRE_SALE", trigger.house)

    elseif action == TriggerSystem.ACTION.PLAY_MOVIE then
        Events.emit("PLAY_MOVIE", param)

    elseif action == TriggerSystem.ACTION.TEXT then
        Events.emit("SHOW_TEXT", param)

    elseif action == TriggerSystem.ACTION.DESTROY_TRIGGER then
        local target = self.triggers[param]
        if target then
            target.enabled = false
        end

    elseif action == TriggerSystem.ACTION.AUTOCREATE then
        Events.emit("AUTOCREATE", trigger.house, param == 1)

    elseif action == TriggerSystem.ACTION.ALLOW_WIN then
        self.win_allowed = true

    elseif action == TriggerSystem.ACTION.REVEAL_MAP then
        Events.emit("REVEAL_MAP", trigger.house)

    elseif action == TriggerSystem.ACTION.REVEAL_ZONE then
        Events.emit("REVEAL_ZONE", trigger.house, param)

    elseif action == TriggerSystem.ACTION.PLAY_SOUND then
        Events.emit("PLAY_SOUND", param)

    elseif action == TriggerSystem.ACTION.PLAY_MUSIC then
        Events.emit("PLAY_MUSIC", param)

    elseif action == TriggerSystem.ACTION.PLAY_SPEECH then
        Events.emit("PLAY_SPEECH", param)

    elseif action == TriggerSystem.ACTION.FORCE_TRIGGER then
        local target = self.triggers[param]
        if target and target.enabled then
            self:fire_trigger(target)
        end

    elseif action == TriggerSystem.ACTION.TIMER_START then
        self.mission_timer_running = true

    elseif action == TriggerSystem.ACTION.TIMER_STOP then
        self.mission_timer_running = false

    elseif action == TriggerSystem.ACTION.TIMER_EXTEND then
        self.mission_timer = self.mission_timer + param

    elseif action == TriggerSystem.ACTION.TIMER_SHORTEN then
        self.mission_timer = math.max(0, self.mission_timer - param)

    elseif action == TriggerSystem.ACTION.TIMER_SET then
        self.mission_timer = param

    elseif action == TriggerSystem.ACTION.GLOBAL_SET then
        self:set_global(param, true)

    elseif action == TriggerSystem.ACTION.GLOBAL_CLEAR then
        self:set_global(param, false)

    elseif action == TriggerSystem.ACTION.AUTO_BASE_AI then
        Events.emit("AUTO_BASE_AI", trigger.house, param == 1)

    elseif action == TriggerSystem.ACTION.GROW_TIBERIUM then
        Events.emit("GROW_TIBERIUM")

    elseif action == TriggerSystem.ACTION.DESTROY_ATTACHED then
        -- Destroy objects attached to this trigger
        for entity_id, trigger_name in pairs(self.object_triggers) do
            if trigger_name == trigger.name then
                Events.emit("DESTROY_ENTITY", entity_id)
            end
        end

    elseif action == TriggerSystem.ACTION.ADD_1TIME_SPECIAL then
        Events.emit("ADD_SPECIAL", trigger.house, param, false)

    elseif action == TriggerSystem.ACTION.ADD_REPEATING_SPECIAL then
        Events.emit("ADD_SPECIAL", trigger.house, param, true)

    elseif action == TriggerSystem.ACTION.PREFERRED_TARGET then
        Events.emit("SET_TARGET_PREFERENCE", trigger.house, param)

    elseif action == TriggerSystem.ACTION.LAUNCH_NUKES then
        Events.emit("LAUNCH_NUKES", trigger.house)
    end
end

-- Event handlers

function TriggerSystem:on_entity_destroyed(entity, attacker)
    local owner = entity:get("owner")
    local entity_house = owner and owner.house or nil

    -- Check object triggers
    local trigger_name = self.object_triggers[entity.id]
    if trigger_name then
        local trigger = self.triggers[trigger_name]
        if trigger and trigger.enabled and trigger.event == TriggerSystem.EVENT.DESTROYED then
            self:fire_trigger(trigger)
        end
        self.object_triggers[entity.id] = nil
    end

    -- Update house stats
    if entity_house then
        self:ensure_house_stats(entity_house)
        if entity:has_tag("building") or entity:has("building") then
            self.house_stats[entity_house].buildings =
                math.max(0, self.house_stats[entity_house].buildings - 1)
        elseif entity:has_tag("unit") then
            self.house_stats[entity_house].units =
                math.max(0, self.house_stats[entity_house].units - 1)
        end

        -- Track per-type destruction for campaign objectives
        self:track_entity_destroyed(entity, attacker)
    end

    -- Check destroyed events
    self:check_event(TriggerSystem.EVENT.DESTROYED, entity_house, 0)
    self:check_event(TriggerSystem.EVENT.DESTROYED_BY_ANYONE, entity_house, 0)
end

function TriggerSystem:on_entity_attacked(entity, attacker)
    local trigger_name = self.object_triggers[entity.id]
    if trigger_name then
        local trigger = self.triggers[trigger_name]
        if trigger and trigger.enabled and trigger.event == TriggerSystem.EVENT.ATTACKED then
            self:fire_trigger(trigger)
        end
    end
end

function TriggerSystem:on_unit_built(entity, house)
    -- Update house stats
    self:ensure_house_stats(house)
    self.house_stats[house].units = self.house_stats[house].units + 1

    self:check_event(TriggerSystem.EVENT.BUILD_UNIT_TYPE, house, 0)
end

function TriggerSystem:on_building_built(entity, house)
    -- Update house stats
    self:ensure_house_stats(house)
    self.house_stats[house].buildings = self.house_stats[house].buildings + 1

    self:check_event(TriggerSystem.EVENT.BUILD_BUILDING_TYPE, house, 0)
end

-- Check cell entry
function TriggerSystem:on_cell_entered(cell_x, cell_y, entity)
    local key = cell_x .. "," .. cell_y
    local trigger_name = self.cell_triggers[key]

    if trigger_name then
        local trigger = self.triggers[trigger_name]
        if trigger and trigger.enabled and trigger.event == TriggerSystem.EVENT.ENTERED_BY then
            local owner = entity:get("owner")
            local entity_house = owner and owner.house or nil

            -- Check if entity house matches trigger house (or is enemy)
            if trigger.house ~= entity_house then
                self:fire_trigger(trigger)
            end
        end
    end
end

-- Update house statistics
function TriggerSystem:update_house_stats(house, stats)
    self.house_stats[house] = stats
end

-- Get mission timer display string
function TriggerSystem:get_timer_display()
    if not self.mission_timer_running then
        return nil
    end

    local minutes = math.floor(self.mission_timer / 60)
    local seconds = math.floor(self.mission_timer % 60)
    return string.format("%02d:%02d", minutes, seconds)
end

-- Reset for new scenario
function TriggerSystem:reset()
    self.triggers = {}
    self.cell_triggers = {}
    self.object_triggers = {}
    self.pending_actions = {}
    self.house_stats = {}

    for i = 0, 31 do
        self.globals[i] = false
    end

    self.mission_timer = 0
    self.mission_timer_running = false
    self.win_allowed = true
    self.game_over = false
    self.victory = false
end

-- Initialize house stats from existing entities on scenario load
-- This must be called after all entities are created
function TriggerSystem:init_house_stats_from_entities()
    if not self.world then return end

    -- Reset all house stats first
    self.house_stats = {}

    -- Get all entities with owner component
    local entities = self.world:get_all_entities()

    for _, entity in ipairs(entities) do
        if entity:has("owner") then
            local owner = entity:get("owner")
            local house = owner.house

            -- Ensure stats exist for this house
            self:ensure_house_stats(house)

            -- Count buildings vs units
            if entity:has("building") then
                self.house_stats[house].buildings = self.house_stats[house].buildings + 1
            elseif entity:has("mobile") or entity:has("infantry") or entity:has("vehicle") or entity:has("aircraft") then
                self.house_stats[house].units = self.house_stats[house].units + 1
            end
        end
    end

    -- Also get power and credits from systems
    if self.power_system then
        for house, _ in pairs(self.house_stats) do
            local produced, consumed = self.power_system:get_power(house)
            self.house_stats[house].power_output = produced or 0
            self.house_stats[house].power_drain = consumed or 0
        end
    end

    if self.harvest_system then
        for house, _ in pairs(self.house_stats) do
            local credits = self.harvest_system:get_credits(house)
            self.house_stats[house].credits = credits or 0
        end
    end
end

-- Get statistics for a house (for trigger conditions)
function TriggerSystem:get_house_stats(house)
    self:ensure_house_stats(house)
    return self.house_stats[house]
end

return TriggerSystem
