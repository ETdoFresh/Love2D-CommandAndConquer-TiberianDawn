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

return Entity
