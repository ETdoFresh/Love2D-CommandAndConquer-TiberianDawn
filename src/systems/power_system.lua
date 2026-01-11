--[[
    Power System - Tracks power production and consumption
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")

local PowerSystem = setmetatable({}, {__index = System})
PowerSystem.__index = PowerSystem

function PowerSystem.new()
    local self = System.new("power", {"power", "owner"})
    setmetatable(self, PowerSystem)

    -- Power state per house
    self.power_produced = {}
    self.power_consumed = {}

    for i = 0, Constants.HOUSE.COUNT - 1 do
        self.power_produced[i] = 0
        self.power_consumed[i] = 0
    end

    return self
end

function PowerSystem:init()
    -- Initial calculation
    self:recalculate_power()
end

function PowerSystem:update(dt, entities)
    -- Power doesn't need per-tick updates
    -- Only recalculate when buildings are added/removed
end

function PowerSystem:recalculate_power()
    -- Reset
    for i = 0, Constants.HOUSE.COUNT - 1 do
        self.power_produced[i] = 0
        self.power_consumed[i] = 0
    end

    -- Sum up all power buildings
    local entities = self:get_entities()

    for _, entity in ipairs(entities) do
        local power = entity:get("power")
        local owner = entity:get("owner")

        self.power_produced[owner.house] = (self.power_produced[owner.house] or 0) + power.produces
        self.power_consumed[owner.house] = (self.power_consumed[owner.house] or 0) + power.consumes
    end

    -- Emit events for each house that changed
    for i = 0, Constants.HOUSE.COUNT - 1 do
        self:emit(Events.EVENTS.POWER_CHANGED, i,
            self.power_produced[i], self.power_consumed[i])
    end
end

function PowerSystem:get_power(house)
    return self.power_produced[house] or 0, self.power_consumed[house] or 0
end

function PowerSystem:get_power_ratio(house)
    local produced = self.power_produced[house] or 0
    local consumed = self.power_consumed[house] or 0

    if consumed == 0 then
        return 1.0
    end

    return produced / consumed
end

function PowerSystem:is_low_power(house)
    return self:get_power_ratio(house) < 1.0
end

function PowerSystem:get_power_level(house)
    local ratio = self:get_power_ratio(house)

    if ratio >= 1.0 then
        return "full"
    elseif ratio >= 0.5 then
        return "low"
    else
        return "critical"
    end
end

-- Get production speed multiplier based on power level
-- In original C&C, low power slows production significantly
function PowerSystem:get_production_multiplier(house)
    local ratio = self:get_power_ratio(house)

    if ratio >= 1.0 then
        return 1.0  -- Full speed
    elseif ratio >= 0.5 then
        return 0.5  -- Half speed
    else
        return 0.25  -- Quarter speed (critical power)
    end
end

-- Check if radar is functional (requires power)
function PowerSystem:is_radar_active(house)
    -- Radar requires at least 50% power to function
    return self:get_power_ratio(house) >= 0.5
end

-- Get defensive structure fire rate multiplier
function PowerSystem:get_defense_multiplier(house)
    local ratio = self:get_power_ratio(house)

    if ratio >= 1.0 then
        return 1.0  -- Full fire rate
    elseif ratio >= 0.5 then
        return 0.75  -- 75% fire rate
    else
        return 0.5  -- 50% fire rate (critical)
    end
end

-- Hook for when buildings are added/removed
function PowerSystem:on_entity_added(entity)
    self:recalculate_power()
end

function PowerSystem:on_entity_removed(entity)
    self:recalculate_power()
end

return PowerSystem
