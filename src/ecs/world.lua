--[[
    World - Container for entities and systems
    Manages the game simulation
]]

local Entity = require("src.ecs.entity")
local Events = require("src.core.events")

local World = {}
World.__index = World

-- Create a new world
function World.new()
    local self = setmetatable({}, World)
    self.entities = {}          -- id -> entity
    self.systems = {}           -- ordered list of systems
    self.systems_by_name = {}   -- name -> system
    self.events = Events.new()  -- Local event bus
    self.to_remove = {}         -- Entities marked for removal
    self.paused = false
    return self
end

-- Create and add a new entity
function World:create_entity()
    local entity = Entity.new()
    self.entities[entity.id] = entity
    return entity
end

-- Add an existing entity
function World:add_entity(entity)
    self.entities[entity.id] = entity
    -- Notify systems
    for _, system in ipairs(self.systems) do
        if system:matches(entity) then
            system:on_entity_added(entity)
        end
    end
    self.events:emit(Events.EVENTS.ENTITY_CREATED, entity)
    return entity
end

-- Remove an entity (immediate)
function World:remove_entity(entity)
    if type(entity) == "number" then
        entity = self.entities[entity]
    end
    if not entity then return end

    -- Notify systems
    for _, system in ipairs(self.systems) do
        if system:matches(entity) then
            system:on_entity_removed(entity)
        end
    end

    self.events:emit(Events.EVENTS.ENTITY_DESTROYED, entity)
    entity:destroy()
    self.entities[entity.id] = nil
end

-- Mark entity for deferred removal (safe during iteration)
function World:destroy_entity(entity)
    if type(entity) == "number" then
        entity = self.entities[entity]
    end
    if entity then
        entity:destroy()
        table.insert(self.to_remove, entity)
    end
end

-- Get entity by ID
function World:get_entity(id)
    return self.entities[id]
end

-- Get all entities
function World:get_all_entities()
    local list = {}
    for _, entity in pairs(self.entities) do
        if entity:is_alive() then
            table.insert(list, entity)
        end
    end
    return list
end

-- Get entities with specific components
function World:get_entities_with(...)
    local required = {...}
    local list = {}
    for _, entity in pairs(self.entities) do
        if entity:is_alive() and entity:has_all(unpack(required)) then
            table.insert(list, entity)
        end
    end
    return list
end

-- Get entities with a specific tag
function World:get_entities_tagged(tag)
    local list = {}
    for _, entity in pairs(self.entities) do
        if entity:is_alive() and entity:has_tag(tag) then
            table.insert(list, entity)
        end
    end
    return list
end

-- Get first entity matching filter
function World:find_entity(filter_fn)
    for _, entity in pairs(self.entities) do
        if entity:is_alive() and filter_fn(entity) then
            return entity
        end
    end
    return nil
end

-- Count entities
function World:entity_count()
    local count = 0
    for _, entity in pairs(self.entities) do
        if entity:is_alive() then
            count = count + 1
        end
    end
    return count
end

-- Add a system
function World:add_system(system)
    system.world = self
    self.systems_by_name[system.name] = system
    table.insert(self.systems, system)

    -- Sort by priority
    table.sort(self.systems, function(a, b)
        return a.priority < b.priority
    end)

    system:init()
    return system
end

-- Remove a system
function World:remove_system(system)
    if type(system) == "string" then
        system = self.systems_by_name[system]
    end
    if not system then return end

    system:cleanup()
    self.systems_by_name[system.name] = nil

    for i, s in ipairs(self.systems) do
        if s == system then
            table.remove(self.systems, i)
            break
        end
    end
end

-- Get system by name
function World:get_system(name)
    return self.systems_by_name[name]
end

-- Update all systems
function World:update(dt)
    if self.paused then return end

    -- Process deferred removals first
    for _, entity in ipairs(self.to_remove) do
        self:remove_entity(entity)
    end
    self.to_remove = {}

    -- Update all enabled systems
    for _, system in ipairs(self.systems) do
        if system:is_enabled() then
            local entities = self:get_entities_with(unpack(system.required_components))
            system:update(dt, entities)
        end
    end
end

-- Draw all render systems
function World:draw()
    for _, system in ipairs(self.systems) do
        if system:is_enabled() then
            local entities = self:get_entities_with(unpack(system.required_components))
            system:draw(entities)
        end
    end
end

-- Pause/unpause world
function World:set_paused(paused)
    self.paused = paused
end

function World:is_paused()
    return self.paused
end

-- Event bus shortcuts
function World:on(event_name, callback)
    return self.events:on(event_name, callback)
end

function World:emit(event_name, ...)
    self.events:emit(event_name, ...)
end

-- Clear world (only entities, preserves systems)
function World:clear()
    -- Remove all entities
    for _, entity in pairs(self.entities) do
        entity:destroy()
    end
    self.entities = {}
    self.to_remove = {}

    -- Note: Systems are preserved - only entities are cleared
    -- This allows scenario loading without losing render/update systems
end

-- Full reset including systems (for complete game restart)
function World:reset()
    -- Clear entities first
    self:clear()

    -- Cleanup systems
    for _, system in ipairs(self.systems) do
        system:cleanup()
    end
    self.systems = {}
    self.systems_by_name = {}

    -- Clear events
    self.events:clear()
end

-- Serialize world state (for save/load)
function World:serialize()
    local data = {
        entities = {}
    }

    for id, entity in pairs(self.entities) do
        if entity:is_alive() then
            data.entities[id] = {
                id = entity.id,
                components = entity.components,
                tags = entity.tags
            }
        end
    end

    return data
end

-- Deserialize world state
function World:deserialize(data)
    self:clear()

    for _, entity_data in pairs(data.entities) do
        local entity = Entity.new()
        -- Manually set ID
        entity.id = entity_data.id
        entity.components = entity_data.components
        entity.tags = entity_data.tags or {}
        self.entities[entity.id] = entity
    end

    -- Re-initialize systems
    for _, system in ipairs(self.systems) do
        system:init()
    end
end

return World
