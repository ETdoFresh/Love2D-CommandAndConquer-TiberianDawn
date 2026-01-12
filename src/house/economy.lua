--[[
    Economy - Credit and resource management system
    Handles harvesting income, storage capacity, and spending
    Reference: HOUSE.CPP credits system
]]

local Events = require("src.core.events")

local Economy = {}
Economy.__index = Economy

-- Economy constants (from original C&C)
Economy.TIBERIUM_VALUE = 25         -- Credits per load of tiberium
Economy.HARVEST_RATE = 28           -- Tiberium units per harvest cycle
Economy.REFINERY_PROCESS_RATE = 2   -- Credits added per game tick when processing
Economy.SILO_CAPACITY = 1500        -- Storage per silo
Economy.REFINERY_CAPACITY = 1000    -- Storage per refinery

function Economy.new(house)
    local self = setmetatable({}, Economy)

    -- Parent house
    self.house = house

    -- Current resources
    self.credits = 0
    self.storage_capacity = 0

    -- Processing state
    self.pending_tiberium = 0  -- Tiberium waiting to be processed
    self.processing_rate = Economy.REFINERY_PROCESS_RATE

    -- Harvesters
    self.harvesters = {}
    self.refineries = {}

    -- Income tracking (for statistics)
    self.income_per_minute = 0
    self.income_history = {}
    self.income_timer = 0

    return self
end

-- Update economy (call each game tick)
function Economy:update(dt)
    -- Process pending tiberium into credits
    if self.pending_tiberium > 0 then
        local process_amount = math.min(self.pending_tiberium, self.processing_rate)
        self.pending_tiberium = self.pending_tiberium - process_amount

        local credits_gained = process_amount * Economy.TIBERIUM_VALUE / Economy.HARVEST_RATE
        self:add_credits(credits_gained)
    end

    -- Track income rate
    self.income_timer = self.income_timer + dt
    if self.income_timer >= 60 then  -- Every minute
        self:calculate_income_rate()
        self.income_timer = 0
    end
end

-- Add credits
function Economy:add_credits(amount)
    local old_credits = self.credits
    self.credits = self.credits + amount

    -- Cap at storage capacity
    if self.storage_capacity > 0 and self.credits > self.storage_capacity then
        local overflow = self.credits - self.storage_capacity
        self.credits = self.storage_capacity
        -- Overflow is lost
        Events.emit("CREDITS_OVERFLOW", self.house, overflow)
    end

    -- Track for income calculation
    table.insert(self.income_history, amount)

    -- Sync with house
    if self.house then
        self.house.credits = self.credits
    end

    Events.emit("CREDITS_CHANGED", self.house, old_credits, self.credits)
    return self.credits
end

-- Spend credits
function Economy:spend(amount)
    if self.credits >= amount then
        self.credits = self.credits - amount

        -- Sync with house
        if self.house then
            self.house.credits = self.credits
        end

        Events.emit("CREDITS_SPENT", self.house, amount)
        return true
    end
    return false
end

-- Check if can afford
function Economy:can_afford(cost)
    return self.credits >= cost
end

-- Deposit tiberium (from harvester)
function Economy:deposit_tiberium(amount)
    self.pending_tiberium = self.pending_tiberium + amount
    Events.emit("TIBERIUM_DEPOSITED", self.house, amount)
end

-- Update storage capacity
function Economy:update_capacity()
    local capacity = 0

    -- Refineries
    for _, refinery in ipairs(self.refineries) do
        if refinery.health and refinery.health > 0 then
            capacity = capacity + Economy.REFINERY_CAPACITY
        end
    end

    -- Silos
    if self.house then
        for _, building in ipairs(self.house.buildings) do
            if building.building_type == "SILO" then
                capacity = capacity + Economy.SILO_CAPACITY
            end
        end
    end

    self.storage_capacity = capacity

    -- Sync with house
    if self.house then
        self.house.credits_capacity = capacity
    end

    return capacity
end

-- Add a refinery
function Economy:add_refinery(refinery)
    table.insert(self.refineries, refinery)
    self:update_capacity()
end

-- Remove a refinery
function Economy:remove_refinery(refinery)
    for i, r in ipairs(self.refineries) do
        if r == refinery then
            table.remove(self.refineries, i)
            self:update_capacity()
            return true
        end
    end
    return false
end

-- Add a harvester
function Economy:add_harvester(harvester)
    table.insert(self.harvesters, harvester)
end

-- Remove a harvester
function Economy:remove_harvester(harvester)
    for i, h in ipairs(self.harvesters) do
        if h == harvester then
            table.remove(self.harvesters, i)
            return true
        end
    end
    return false
end

-- Find nearest available refinery
function Economy:find_nearest_refinery(x, y)
    local nearest = nil
    local nearest_dist = math.huge

    for _, refinery in ipairs(self.refineries) do
        -- Check if refinery is accepting harvesters
        if refinery.health and refinery.health > 0 then
            local dx = (refinery.x or 0) - x
            local dy = (refinery.y or 0) - y
            local dist = dx * dx + dy * dy

            if dist < nearest_dist then
                nearest_dist = dist
                nearest = refinery
            end
        end
    end

    return nearest
end

-- Calculate income rate
function Economy:calculate_income_rate()
    local total = 0
    for _, amount in ipairs(self.income_history) do
        total = total + amount
    end

    self.income_per_minute = total
    self.income_history = {}

    return self.income_per_minute
end

-- Get storage fill percentage
function Economy:get_storage_fill()
    if self.storage_capacity == 0 then
        return 0
    end
    return self.credits / self.storage_capacity
end

-- Is storage full?
function Economy:is_storage_full()
    return self.storage_capacity > 0 and self.credits >= self.storage_capacity
end

-- Get harvester count
function Economy:get_harvester_count()
    return #self.harvesters
end

-- Get refinery count
function Economy:get_refinery_count()
    return #self.refineries
end

-- Serialize
function Economy:serialize()
    return {
        credits = self.credits,
        storage_capacity = self.storage_capacity,
        pending_tiberium = self.pending_tiberium,
        income_per_minute = self.income_per_minute
    }
end

-- Deserialize
function Economy:deserialize(data)
    self.credits = data.credits or 0
    self.storage_capacity = data.storage_capacity or 0
    self.pending_tiberium = data.pending_tiberium or 0
    self.income_per_minute = data.income_per_minute or 0
end

return Economy
