--[[
    Deterministic Random Number Generator
    Uses Linear Congruential Generator (LCG) matching original C&C algorithm
    Critical for multiplayer sync - all clients must produce identical results
]]

local Random = {}
Random.__index = Random

-- LCG constants (matches original Westwood implementation)
-- These produce a full period of 2^32
local MULTIPLIER = 1103515245
local INCREMENT = 12345
local MODULUS = 2^32

-- Create a new random generator with optional seed
function Random.new(seed)
    local self = setmetatable({}, Random)
    self:set_seed(seed or os.time())
    return self
end

-- Set seed
function Random:set_seed(seed)
    self.seed = seed % MODULUS
    self.initial_seed = self.seed
end

-- Get current seed (for save/load)
function Random:get_seed()
    return self.seed
end

-- Reset to initial seed
function Random:reset()
    self.seed = self.initial_seed
end

-- Generate next raw random value (0 to MODULUS-1)
function Random:next_raw()
    self.seed = (MULTIPLIER * self.seed + INCREMENT) % MODULUS
    return self.seed
end

-- Generate random integer in range [min, max] inclusive
function Random:range(min, max)
    if max < min then
        min, max = max, min
    end
    local raw = self:next_raw()
    return min + (raw % (max - min + 1))
end

-- Generate random float in range [0, 1)
function Random:random()
    return self:next_raw() / MODULUS
end

-- Generate random float in range [min, max)
function Random:float_range(min, max)
    return min + self:random() * (max - min)
end

-- Generate random boolean with optional probability
function Random:bool(probability)
    probability = probability or 0.5
    return self:random() < probability
end

-- Pick random element from array
function Random:pick(array)
    if #array == 0 then return nil end
    local index = self:range(1, #array)
    return array[index]
end

-- Shuffle array in place (Fisher-Yates)
function Random:shuffle(array)
    for i = #array, 2, -1 do
        local j = self:range(1, i)
        array[i], array[j] = array[j], array[i]
    end
    return array
end

-- Generate random direction (0-7 for 8-direction)
function Random:direction()
    return self:range(0, 7)
end

-- Generate random percentage (0-99)
function Random:percent()
    return self:range(0, 99)
end

-- Roll dice: returns true if random percent < chance
function Random:roll(chance)
    return self:percent() < chance
end

-- Generate weighted random selection
-- weights: table of {item, weight} or {item = weight}
function Random:weighted_pick(weights)
    local total = 0
    local items = {}

    -- Handle both array and dictionary formats
    if weights[1] then
        -- Array format: {{item, weight}, ...}
        for _, entry in ipairs(weights) do
            total = total + entry[2]
            table.insert(items, {item = entry[1], cumulative = total})
        end
    else
        -- Dictionary format: {item = weight, ...}
        for item, weight in pairs(weights) do
            total = total + weight
            table.insert(items, {item = item, cumulative = total})
        end
    end

    if total <= 0 then return nil end

    local roll = self:float_range(0, total)
    for _, entry in ipairs(items) do
        if roll < entry.cumulative then
            return entry.item
        end
    end

    return items[#items].item
end

-- Generate random point in circle
function Random:in_circle(radius)
    local angle = self:float_range(0, 2 * math.pi)
    local r = math.sqrt(self:random()) * radius  -- sqrt for uniform distribution
    return r * math.cos(angle), r * math.sin(angle)
end

-- Generate random point in rectangle
function Random:in_rect(width, height)
    return self:float_range(0, width), self:float_range(0, height)
end

-- Create a child generator with derived seed
function Random:child()
    return Random.new(self:next_raw())
end

-- Serialize state for network sync
function Random:serialize()
    return {
        seed = self.seed,
        initial = self.initial_seed
    }
end

-- Deserialize state
function Random:deserialize(data)
    self.seed = data.seed
    self.initial_seed = data.initial
end

-- Global deterministic RNG instance (for game logic)
local game_rng = Random.new(12345)  -- Fixed default seed for testing

-- Module interface
local M = {
    new = Random.new,
    game = game_rng
}

-- Global instance shortcuts
function M.set_seed(seed)
    game_rng:set_seed(seed)
end

function M.get_seed()
    return game_rng:get_seed()
end

function M.range(min, max)
    return game_rng:range(min, max)
end

function M.random()
    return game_rng:random()
end

function M.float_range(min, max)
    return game_rng:float_range(min, max)
end

function M.bool(probability)
    return game_rng:bool(probability)
end

function M.pick(array)
    return game_rng:pick(array)
end

function M.shuffle(array)
    return game_rng:shuffle(array)
end

function M.direction()
    return game_rng:direction()
end

function M.percent()
    return game_rng:percent()
end

function M.roll(chance)
    return game_rng:roll(chance)
end

return M
