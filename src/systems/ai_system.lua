--[[
    AI System - Unit behavior and mission handling
    Reference: MISSION.H, TECHNO.CPP
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")

local AISystem = setmetatable({}, {__index = System})
AISystem.__index = AISystem

-- Mission names for debugging
AISystem.MISSION_NAMES = {
    [Constants.MISSION.NONE] = "None",
    [Constants.MISSION.SLEEP] = "Sleep",
    [Constants.MISSION.ATTACK] = "Attack",
    [Constants.MISSION.MOVE] = "Move",
    [Constants.MISSION.RETREAT] = "Retreat",
    [Constants.MISSION.GUARD] = "Guard",
    [Constants.MISSION.STICKY] = "Sticky",
    [Constants.MISSION.ENTER] = "Enter",
    [Constants.MISSION.CAPTURE] = "Capture",
    [Constants.MISSION.HARVEST] = "Harvest",
    [Constants.MISSION.GUARD_AREA] = "Guard Area",
    [Constants.MISSION.RETURN] = "Return",
    [Constants.MISSION.STOP] = "Stop",
    [Constants.MISSION.AMBUSH] = "Ambush",
    [Constants.MISSION.HUNT] = "Hunt",
    [Constants.MISSION.TIMED_HUNT] = "Timed Hunt",
    [Constants.MISSION.UNLOAD] = "Unload",
    [Constants.MISSION.SABOTAGE] = "Sabotage",
    [Constants.MISSION.CONSTRUCTION] = "Construction",
    [Constants.MISSION.DECONSTRUCTION] = "Deconstruction",
    [Constants.MISSION.REPAIR] = "Repair",
    [Constants.MISSION.RESCUE] = "Rescue",
    [Constants.MISSION.MISSILE] = "Missile"
}

function AISystem.new()
    local self = System.new("ai", {"transform", "mission"})
    setmetatable(self, AISystem)

    -- References to other systems
    self.combat_system = nil
    self.movement_system = nil

    return self
end

function AISystem:init()
    -- Get references to other systems
    self.combat_system = self.world:get_system("combat")
    self.movement_system = self.world:get_system("movement")
end

function AISystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end
end

function AISystem:process_entity(dt, entity)
    local mission = entity:get("mission")

    -- Decrease mission timer
    if mission.timer > 0 then
        mission.timer = mission.timer - 1
    end

    -- Process based on current mission
    local handler = self.mission_handlers[mission.mission_type]
    if handler then
        handler(self, entity, mission)
    end
end

-- Mission handlers
AISystem.mission_handlers = {}

-- SLEEP: Do nothing
AISystem.mission_handlers[Constants.MISSION.SLEEP] = function(self, entity, mission)
    -- Just sit there
end

-- STOP: Stand still, don't react
AISystem.mission_handlers[Constants.MISSION.STOP] = function(self, entity, mission)
    -- Stop moving
    if self.movement_system and entity:has("mobile") then
        self.movement_system:stop(entity)
    end
end

-- GUARD: Stand still but respond to threats
AISystem.mission_handlers[Constants.MISSION.GUARD] = function(self, entity, mission)
    if not entity:has("combat") then
        return
    end

    local combat = entity:get("combat")

    -- Already attacking something?
    if combat.target then
        local target = self.world:get_entity(combat.target)
        if target and target:is_alive() then
            return  -- Keep attacking
        else
            combat.target = nil
        end
    end

    -- Look for threats
    if self.combat_system then
        local target = self.combat_system:find_target(entity)
        if target then
            combat.target = target.id
        end
    end
end

-- GUARD_AREA: Guard an area, chase enemies that come near
AISystem.mission_handlers[Constants.MISSION.GUARD_AREA] = function(self, entity, mission)
    if not entity:has("combat") then
        return
    end

    local transform = entity:get("transform")
    local combat = entity:get("combat")

    -- Store guard position if not set
    if not mission.guard_x then
        mission.guard_x = transform.x
        mission.guard_y = transform.y
    end

    -- Check if we have a target
    if combat.target then
        local target = self.world:get_entity(combat.target)
        if target and target:is_alive() then
            local target_transform = target:get("transform")

            -- Check distance from guard position
            local dx = target_transform.x - mission.guard_x
            local dy = target_transform.y - mission.guard_y
            local dist = math.sqrt(dx * dx + dy * dy) / Constants.LEPTON_PER_CELL

            if dist > combat.attack_range * 2 then
                -- Too far from guard position, return
                combat.target = nil
                if self.movement_system then
                    self.movement_system:move_to(entity, mission.guard_x, mission.guard_y)
                end
            end
            return
        else
            combat.target = nil
        end
    end

    -- Look for threats
    if self.combat_system then
        local target = self.combat_system:find_target(entity)
        if target then
            combat.target = target.id
            -- Move towards target if out of range
            local target_transform = target:get("transform")
            local dist = self.combat_system:calculate_distance(transform, target_transform)
            if dist > combat.attack_range and self.movement_system then
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end
end

-- ATTACK: Attack a specific target
AISystem.mission_handlers[Constants.MISSION.ATTACK] = function(self, entity, mission)
    if not entity:has("combat") then
        return
    end

    local combat = entity:get("combat")
    local transform = entity:get("transform")

    -- Check if target is valid
    local target = nil
    if mission.target then
        target = self.world:get_entity(mission.target)
    elseif combat.target then
        target = self.world:get_entity(combat.target)
    end

    if not target or not target:is_alive() then
        -- Target lost, revert to guard
        self:set_mission(entity, Constants.MISSION.GUARD)
        return
    end

    -- Make sure combat system knows about target
    combat.target = target.id

    -- Move towards target if out of range
    local target_transform = target:get("transform")
    local dist = self.combat_system:calculate_distance(transform, target_transform)

    if dist > combat.attack_range then
        if self.movement_system and entity:has("mobile") then
            -- Check if already moving towards target
            local mobile = entity:get("mobile")
            if not mobile.is_moving then
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    else
        -- In range, stop moving
        if self.movement_system and entity:has("mobile") then
            local mobile = entity:get("mobile")
            if mobile.is_moving then
                self.movement_system:stop(entity)
            end
        end
    end
end

-- MOVE: Move to a destination
AISystem.mission_handlers[Constants.MISSION.MOVE] = function(self, entity, mission)
    if not entity:has("mobile") then
        return
    end

    local mobile = entity:get("mobile")

    -- Check if we've arrived
    if not mobile.is_moving then
        -- Arrived at destination, switch to guard
        self:set_mission(entity, Constants.MISSION.GUARD)
    end
end

-- HUNT: Actively seek and destroy enemies
AISystem.mission_handlers[Constants.MISSION.HUNT] = function(self, entity, mission)
    if not entity:has("combat") then
        return
    end

    local combat = entity:get("combat")
    local transform = entity:get("transform")

    -- Check current target
    if combat.target then
        local target = self.world:get_entity(combat.target)
        if target and target:is_alive() then
            -- Chase and attack
            local target_transform = target:get("transform")
            local dist = self.combat_system:calculate_distance(transform, target_transform)

            if dist > combat.attack_range then
                if self.movement_system and entity:has("mobile") then
                    self.movement_system:move_to(entity, target_transform.x, target_transform.y)
                end
            end
            return
        else
            combat.target = nil
        end
    end

    -- Find new target
    if self.combat_system then
        local target = self.combat_system:find_target(entity)
        if target then
            combat.target = target.id
        else
            -- No targets visible, wander or patrol
            -- TODO: Implement patrol behavior
        end
    end
end

-- HARVEST: Collect tiberium
AISystem.mission_handlers[Constants.MISSION.HARVEST] = function(self, entity, mission)
    if not entity:has("harvester") then
        return
    end

    local harvester = entity:get("harvester")
    local transform = entity:get("transform")

    -- Check if full
    if harvester.tiberium_load >= harvester.max_load then
        -- Switch to return mission
        self:set_mission(entity, Constants.MISSION.RETURN)
        return
    end

    -- Find tiberium cell if not harvesting
    if not entity:has("mobile") then
        return
    end

    local mobile = entity:get("mobile")

    if not mobile.is_moving then
        -- Look for nearby tiberium
        -- TODO: Implement tiberium field finding
    end
end

-- RETURN: Return to refinery
AISystem.mission_handlers[Constants.MISSION.RETURN] = function(self, entity, mission)
    if not entity:has("harvester") or not entity:has("mobile") then
        return
    end

    local harvester = entity:get("harvester")
    local mobile = entity:get("mobile")

    -- Check if at refinery
    if not mobile.is_moving then
        -- Unload at refinery
        if harvester.tiberium_load > 0 then
            -- TODO: Transfer tiberium to house credits
            harvester.tiberium_load = 0
        end

        -- Go back to harvesting
        self:set_mission(entity, Constants.MISSION.HARVEST)
    end
end

-- ENTER: Enter a transport or building
AISystem.mission_handlers[Constants.MISSION.ENTER] = function(self, entity, mission)
    local target = mission.target and self.world:get_entity(mission.target)

    if not target or not target:is_alive() then
        self:set_mission(entity, Constants.MISSION.GUARD)
        return
    end

    -- Move towards target
    if entity:has("mobile") and self.movement_system then
        local mobile = entity:get("mobile")
        if not mobile.is_moving then
            local target_transform = target:get("transform")
            local transform = entity:get("transform")

            -- Check if close enough to enter
            local dx = target_transform.x - transform.x
            local dy = target_transform.y - transform.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < Constants.LEPTON_PER_CELL then
                -- Close enough, enter
                -- TODO: Actually enter the transport
                self:set_mission(entity, Constants.MISSION.SLEEP)
            else
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end
end

-- CAPTURE: Capture an enemy building
AISystem.mission_handlers[Constants.MISSION.CAPTURE] = function(self, entity, mission)
    if not entity:has("infantry") then
        return
    end

    local infantry = entity:get("infantry")
    if not infantry.can_capture then
        self:set_mission(entity, Constants.MISSION.GUARD)
        return
    end

    local target = mission.target and self.world:get_entity(mission.target)

    if not target or not target:is_alive() or not target:has("building") then
        self:set_mission(entity, Constants.MISSION.GUARD)
        return
    end

    -- Move towards building
    if entity:has("mobile") and self.movement_system then
        local mobile = entity:get("mobile")
        if not mobile.is_moving then
            local target_transform = target:get("transform")
            local transform = entity:get("transform")

            local dx = target_transform.x - transform.x
            local dy = target_transform.y - transform.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < Constants.LEPTON_PER_CELL then
                -- Capture the building
                local target_owner = target:get("owner")
                local my_owner = entity:get("owner")

                target_owner.house = my_owner.house
                target_owner.color = my_owner.color

                -- Engineer is consumed
                self.world:destroy_entity(entity)

                self:emit(Events.EVENTS.BUILDING_CAPTURED, target, entity)
            else
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end
end

-- Set mission for an entity
function AISystem:set_mission(entity, mission_type, target)
    if not entity:has("mission") then
        return
    end

    local mission = entity:get("mission")
    mission.mission_type = mission_type
    mission.target = target and target.id or nil
    mission.timer = 0

    -- Clear guard position when changing missions
    mission.guard_x = nil
    mission.guard_y = nil
end

-- Give move order
function AISystem:order_move(entity, dest_x, dest_y)
    if not entity:has("mobile") or not self.movement_system then
        return false
    end

    self:set_mission(entity, Constants.MISSION.MOVE)
    return self.movement_system:move_to(entity, dest_x, dest_y)
end

-- Give attack order
function AISystem:order_attack(entity, target)
    if not entity:has("combat") then
        return false
    end

    self:set_mission(entity, Constants.MISSION.ATTACK, target)
    entity:get("combat").target = target.id
    return true
end

-- Give guard order
function AISystem:order_guard(entity)
    self:set_mission(entity, Constants.MISSION.GUARD)
end

-- Give hunt order
function AISystem:order_hunt(entity)
    self:set_mission(entity, Constants.MISSION.HUNT)
end

-- Give stop order
function AISystem:order_stop(entity)
    self:set_mission(entity, Constants.MISSION.STOP)

    if self.movement_system and entity:has("mobile") then
        self.movement_system:stop(entity)
    end

    if entity:has("combat") then
        entity:get("combat").target = nil
    end
end

-- Get mission name for debugging
function AISystem:get_mission_name(entity)
    if not entity:has("mission") then
        return "None"
    end
    local mission_type = entity:get("mission").mission_type
    return self.MISSION_NAMES[mission_type] or "Unknown"
end

return AISystem
