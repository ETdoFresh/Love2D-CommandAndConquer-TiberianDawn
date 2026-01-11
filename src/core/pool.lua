--[[
    Object Pool - Reuse objects to avoid garbage collection
    Reduces GC stutters during gameplay
]]

local Pool = {}
Pool.__index = Pool

-- Create a new pool
-- factory: function that creates a new object
-- reset: optional function to reset an object before reuse
-- initial_size: optional number of objects to pre-create
function Pool.new(factory, reset, initial_size)
    local self = setmetatable({}, Pool)
    self.factory = factory
    self.reset = reset or function(obj) end
    self.available = {}  -- Stack of available objects
    self.in_use = {}     -- Set of objects currently in use
    self.total_created = 0
    self.peak_usage = 0

    -- Pre-populate pool
    if initial_size and initial_size > 0 then
        for i = 1, initial_size do
            local obj = self.factory()
            self.total_created = self.total_created + 1
            table.insert(self.available, obj)
        end
    end

    return self
end

-- Acquire an object from the pool
function Pool:acquire(...)
    local obj

    if #self.available > 0 then
        obj = table.remove(self.available)
    else
        obj = self.factory(...)
        self.total_created = self.total_created + 1
    end

    self.in_use[obj] = true

    -- Track peak usage
    local current_usage = self:in_use_count()
    if current_usage > self.peak_usage then
        self.peak_usage = current_usage
    end

    return obj
end

-- Release an object back to the pool
function Pool:release(obj)
    if not self.in_use[obj] then
        return false  -- Object not from this pool or already released
    end

    self.in_use[obj] = nil
    self.reset(obj)
    table.insert(self.available, obj)
    return true
end

-- Get count of available objects
function Pool:available_count()
    return #self.available
end

-- Get count of objects in use
function Pool:in_use_count()
    local count = 0
    for _ in pairs(self.in_use) do
        count = count + 1
    end
    return count
end

-- Get total objects created
function Pool:get_total_created()
    return self.total_created
end

-- Get peak usage
function Pool:get_peak_usage()
    return self.peak_usage
end

-- Clear all objects (for cleanup)
function Pool:clear()
    self.available = {}
    self.in_use = {}
end

-- Pre-warm the pool with additional objects
function Pool:warm(count)
    for i = 1, count do
        local obj = self.factory()
        self.total_created = self.total_created + 1
        table.insert(self.available, obj)
    end
end

-- Trim excess available objects
function Pool:trim(keep_count)
    while #self.available > keep_count do
        table.remove(self.available)
    end
end

return Pool
