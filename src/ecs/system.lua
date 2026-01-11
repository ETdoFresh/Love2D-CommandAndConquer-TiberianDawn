--[[
    System Base Class - Processes entities with specific components
    Systems contain all game logic; entities are just data
]]

local System = {}
System.__index = System

-- Create a new system
-- required_components: list of component names this system operates on
function System.new(name, required_components)
    local self = setmetatable({}, System)
    self.name = name
    self.required_components = required_components or {}
    self.enabled = true
    self.priority = 0  -- Lower runs first
    self.world = nil   -- Set when added to world
    return self
end

-- Check if an entity matches this system's requirements
function System:matches(entity)
    if not entity:is_alive() then
        return false
    end
    return entity:has_all(unpack(self.required_components))
end

-- Initialize system (called when added to world)
function System:init()
    -- Override in subclass
end

-- Clean up system (called when removed from world)
function System:cleanup()
    -- Override in subclass
end

-- Update the system (called each tick)
-- dt: delta time in seconds
-- entities: list of matching entities
function System:update(dt, entities)
    -- Override in subclass
    -- Default: call process_entity on each matching entity
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end
end

-- Process a single entity
function System:process_entity(dt, entity)
    -- Override in subclass
end

-- Called when an entity is added that matches this system
function System:on_entity_added(entity)
    -- Override in subclass
end

-- Called when a matching entity is removed
function System:on_entity_removed(entity)
    -- Override in subclass
end

-- Called when a component is added to a matching entity
function System:on_component_added(entity, component_name)
    -- Override in subclass
end

-- Called when a component is removed from a matching entity
function System:on_component_removed(entity, component_name)
    -- Override in subclass
end

-- Draw (for render systems)
function System:draw(entities)
    -- Override in subclass
end

-- Set enabled state
function System:set_enabled(enabled)
    self.enabled = enabled
end

-- Check if enabled
function System:is_enabled()
    return self.enabled
end

-- Set priority (lower runs first)
function System:set_priority(priority)
    self.priority = priority
end

-- Create a filter function for this system
function System:create_filter()
    local required = self.required_components
    return function(entity)
        return entity:is_alive() and entity:has_all(unpack(required))
    end
end

-- Helper to get all entities in world that match
function System:get_entities()
    if self.world then
        return self.world:get_entities_with(unpack(self.required_components))
    end
    return {}
end

-- Helper to emit an event
function System:emit(event_name, ...)
    if self.world then
        self.world:emit(event_name, ...)
    end
end

-- Helper to subscribe to an event
function System:on(event_name, callback)
    if self.world then
        return self.world:on(event_name, callback)
    end
end

-- String representation
function System:__tostring()
    local components = table.concat(self.required_components, ", ")
    return string.format("System(%s)[%s]", self.name, components)
end

return System
