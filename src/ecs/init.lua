--[[
    ECS Compatibility Shim

    This module provides stub implementations of the old ECS interface
    to allow the game to load during the Phase 0->Phase 1 migration.

    TODO: Remove this shim once src/core/game.lua is fully migrated to
    use the C++ class hierarchy in src/objects/ (Phase 1 completion).

    The class hierarchy uses:
    - HeapClass pools in src/heap/ for object allocation
    - AI() methods called per-tick on each active object
    - No entity-component-system pattern
]]

-- Stub World class
local World = {}
World.__index = World

function World.new()
    local self = setmetatable({}, World)
    self.entities = {}
    self.systems = {}
    self.next_id = 1
    return self
end

function World:add_entity(entity)
    if not entity then return nil end
    if not entity.id then
        entity.id = self.next_id
        self.next_id = self.next_id + 1
    end
    self.entities[entity.id] = entity
    return entity
end

function World:destroy_entity(entity)
    if entity and entity.id then
        self.entities[entity.id] = nil
    end
end

function World:get_all_entities()
    local result = {}
    for _, entity in pairs(self.entities) do
        table.insert(result, entity)
    end
    return result
end

function World:get_entities_with(...)
    local components = {...}
    local result = {}
    for _, entity in pairs(self.entities) do
        local has_all = true
        for _, comp in ipairs(components) do
            if not entity[comp] then
                has_all = false
                break
            end
        end
        if has_all then
            table.insert(result, entity)
        end
    end
    return result
end

function World:add_system(system)
    table.insert(self.systems, system)
    -- Sort by priority
    table.sort(self.systems, function(a, b)
        return (a.priority or 0) < (b.priority or 0)
    end)
end

function World:get_system(system_class)
    for _, system in ipairs(self.systems) do
        -- Check if system is an instance of the requested class
        if getmetatable(system) == system_class then
            return system
        end
        -- Also check by name if available
        if system.name and system_class.name and system.name == system_class.name then
            return system
        end
    end
    return nil
end

function World:update(dt)
    for _, system in ipairs(self.systems) do
        if system.update then
            system:update(dt)
        end
    end
end

function World:draw()
    for _, system in ipairs(self.systems) do
        if system.draw then
            system:draw()
        end
    end
end

function World:clear()
    self.entities = {}
    self.next_id = 1
end

function World:reset()
    self:clear()
    self.systems = {}
end

function World:entity_count()
    local count = 0
    for _ in pairs(self.entities) do
        count = count + 1
    end
    return count
end

-- Stub System base class
local System = {}
System.__index = System

function System.new()
    local self = setmetatable({}, System)
    self.priority = 0
    self.world = nil
    return self
end

function System:set_priority(priority)
    self.priority = priority or 0
end

function System:update(dt)
    -- Override in subclass
end

function System:draw()
    -- Override in subclass
end

-- Export
return {
    World = World,
    System = System
}
