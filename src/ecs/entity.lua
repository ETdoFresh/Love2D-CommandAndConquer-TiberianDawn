--[[
    Entity - A unique identifier with attached components
    Entities are just IDs; all data lives in components
]]

local Entity = {}
Entity.__index = Entity

local next_id = 1

-- Create a new entity
function Entity.new()
    local self = setmetatable({}, Entity)
    self.id = next_id
    next_id = next_id + 1
    self.components = {}  -- component_name -> component_data
    self.alive = true
    self.tags = {}  -- Set of string tags for quick filtering
    return self
end

-- Reset ID counter (for testing or new game)
function Entity.reset_id_counter()
    next_id = 1
end

-- Add a component to the entity
function Entity:add(component_name, component_data)
    if self.components[component_name] then
        error("Entity " .. self.id .. " already has component: " .. component_name)
    end
    self.components[component_name] = component_data
    return self
end

-- Remove a component from the entity
function Entity:remove(component_name)
    self.components[component_name] = nil
    return self
end

-- Get a component (returns nil if not present)
function Entity:get(component_name)
    return self.components[component_name]
end

-- Check if entity has a component
function Entity:has(component_name)
    return self.components[component_name] ~= nil
end

-- Check if entity has all specified components
function Entity:has_all(...)
    local names = {...}
    for _, name in ipairs(names) do
        if not self.components[name] then
            return false
        end
    end
    return true
end

-- Check if entity has any of the specified components
function Entity:has_any(...)
    local names = {...}
    for _, name in ipairs(names) do
        if self.components[name] then
            return true
        end
    end
    return false
end

-- Add a tag
function Entity:add_tag(tag)
    self.tags[tag] = true
    return self
end

-- Remove a tag
function Entity:remove_tag(tag)
    self.tags[tag] = nil
    return self
end

-- Check if entity has a tag
function Entity:has_tag(tag)
    return self.tags[tag] == true
end

-- Mark entity for destruction
function Entity:destroy()
    self.alive = false
end

-- Check if entity is alive
function Entity:is_alive()
    return self.alive
end

-- Get list of all component names
function Entity:get_component_names()
    local names = {}
    for name in pairs(self.components) do
        table.insert(names, name)
    end
    return names
end

-- Clone entity (creates new ID, copies component data)
function Entity:clone()
    local new_entity = Entity.new()
    for name, component in pairs(self.components) do
        -- Shallow copy component data
        local new_component = {}
        for k, v in pairs(component) do
            new_component[k] = v
        end
        new_entity.components[name] = new_component
    end
    for tag in pairs(self.tags) do
        new_entity.tags[tag] = true
    end
    return new_entity
end

-- String representation
function Entity:__tostring()
    local components = table.concat(self:get_component_names(), ", ")
    return string.format("Entity(%d)[%s]", self.id, components)
end

-- Serialize entity to a table for save/load
-- Performs deep copy of all component data
function Entity:serialize()
    local data = {
        id = self.id,
        alive = self.alive,
        components = {},
        tags = {}
    }

    -- Deep copy components
    for name, component in pairs(self.components) do
        data.components[name] = Entity.deep_copy(component)
    end

    -- Copy tags
    for tag in pairs(self.tags) do
        table.insert(data.tags, tag)
    end

    return data
end

-- Deserialize entity from saved data
-- Returns a new entity with the saved state
function Entity.deserialize(data)
    local entity = setmetatable({}, Entity)
    entity.id = data.id
    entity.alive = data.alive
    entity.components = {}
    entity.tags = {}

    -- Restore components
    for name, component_data in pairs(data.components) do
        entity.components[name] = Entity.deep_copy(component_data)
    end

    -- Restore tags
    for _, tag in ipairs(data.tags) do
        entity.tags[tag] = true
    end

    -- Update next_id to avoid collisions
    if data.id >= next_id then
        next_id = data.id + 1
    end

    return entity
end

-- Deep copy helper for component data
-- Handles nested tables but not functions or userdata
function Entity.deep_copy(obj)
    if type(obj) ~= "table" then
        return obj
    end

    -- Skip Love2D objects and functions (can't be serialized)
    if obj.typeOf or type(obj) == "userdata" then
        return nil
    end

    local copy = {}
    for k, v in pairs(obj) do
        if type(v) == "table" then
            copy[k] = Entity.deep_copy(v)
        elseif type(v) ~= "function" and type(v) ~= "userdata" then
            copy[k] = v
        end
    end
    return copy
end

-- Set the next ID counter (used when loading saves)
function Entity.set_next_id(id)
    next_id = id
end

-- Get current next ID (for save state)
function Entity.get_next_id()
    return next_id
end

return Entity
