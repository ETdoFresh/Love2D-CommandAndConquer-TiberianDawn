--[[
    AI System - Unit behavior and mission handling
    Reference: MISSION.H, TECHNO.CPP
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")
local Random = require("src.util.random")

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

    -- Handle transport destruction - eject all passengers
    Events.on(Events.EVENTS.ENTITY_DESTROYED, function(entity)
        if entity:has("cargo") then
            self:eject_passengers(entity)
        end
    end)

    Events.on(Events.EVENTS.UNIT_KILLED, function(entity, killer, cause)
        if entity:has("cargo") then
            self:eject_passengers(entity)
        end
    end)
end

-- Eject all passengers when transport is destroyed (passengers take damage)
function AISystem:eject_passengers(transport)
    if not transport:has("cargo") then return end

    local cargo = transport:get("cargo")
    local transform = transport:get("transform")

    for _, passenger_id in ipairs(cargo.passengers) do
        local passenger = self.world:get_entity(passenger_id)
        if passenger and passenger:is_alive() then
            local passenger_transform = passenger:get("transform")

            -- Place near destroyed transport
            local offset_x = (Random.random() - 0.5) * Constants.LEPTON_PER_CELL * 2
            local offset_y = (Random.random() - 0.5) * Constants.LEPTON_PER_CELL * 2
            passenger_transform.x = transform.x + offset_x
            passenger_transform.y = transform.y + offset_y
            passenger_transform.cell_x = math.floor(passenger_transform.x / Constants.LEPTON_PER_CELL)
            passenger_transform.cell_y = math.floor(passenger_transform.y / Constants.LEPTON_PER_CELL)

            -- Make visible and selectable again
            if passenger:has("renderable") then
                passenger:get("renderable").visible = true
            end
            if passenger:has("selectable") then
                passenger:get("selectable").can_select = true
            end
            if passenger:has("mission") then
                passenger:get("mission").inside_transport = nil
            end

            -- Apply damage to ejected passengers (transport explosion damages them)
            if passenger:has("health") then
                local health = passenger:get("health")
                local damage = math.floor(health.max_hp * 0.5) -- 50% damage on crash
                health.hp = math.max(1, health.hp - damage)
            end

            self:set_mission(passenger, Constants.MISSION.GUARD)
            Events.emit("UNIT_EJECTED", passenger, transport)
        end
    end

    -- Clear passengers list
    cargo.passengers = {}
end

function AISystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)

        -- Update infantry fear and prone state
        -- Reference: INFANTRY.CPP - Infantry::AI() handles fear every tick
        if entity:has("infantry") then
            self:update_infantry_fear(entity, dt)
        end
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
            -- No targets visible, patrol/wander behavior
            self:patrol_behavior(entity, mission)
        end
    end
end

-- Patrol behavior for units with no visible targets
function AISystem:patrol_behavior(entity, mission)
    if not entity:has("mobile") or not entity:has("transform") then
        return
    end

    local mobile = entity:get("mobile")
    local transform = entity:get("transform")

    -- Only patrol if not already moving
    if mobile.is_moving then
        return
    end

    -- Initialize patrol state if needed
    if not mission.patrol_timer then
        mission.patrol_timer = 0
        mission.patrol_delay = Random.range(30, 90)  -- 2-6 seconds random delay
    end

    -- Increment timer
    mission.patrol_timer = mission.patrol_timer + 1

    -- Wait for patrol delay before moving
    if mission.patrol_timer < mission.patrol_delay then
        return
    end

    -- Reset patrol timer
    mission.patrol_timer = 0
    mission.patrol_delay = Random.range(30, 90)

    -- Pick a random direction to patrol
    local movement_system = self.world:get_system("movement")
    if not movement_system then return end

    -- Get unit sight range for patrol distance
    local sight_range = 5
    if self.fog_system then
        sight_range = self.fog_system:get_sight_range(entity)
    end

    -- Pick random offset within patrol range
    local patrol_dist = Random.range(2, sight_range) * Constants.LEPTON_PER_CELL
    local angle = Random.float_range(0, math.pi * 2)

    local dest_x = transform.x + math.cos(angle) * patrol_dist
    local dest_y = transform.y + math.sin(angle) * patrol_dist

    -- Clamp to map bounds
    local map_width = (self.grid and self.grid.width or 64) * Constants.LEPTON_PER_CELL
    local map_height = (self.grid and self.grid.height or 64) * Constants.LEPTON_PER_CELL
    dest_x = math.max(Constants.LEPTON_PER_CELL, math.min(dest_x, map_width - Constants.LEPTON_PER_CELL))
    dest_y = math.max(Constants.LEPTON_PER_CELL, math.min(dest_y, map_height - Constants.LEPTON_PER_CELL))

    -- Move to patrol destination
    movement_system:move_to(entity, dest_x, dest_y)
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
        -- Look for nearby tiberium using harvest system
        local harvest_system = self.world:get_system("harvest")
        if harvest_system then
            local tib_cell = harvest_system:find_tiberium(transform.cell_x, transform.cell_y)
            if tib_cell then
                local movement_system = self.world:get_system("movement")
                if movement_system then
                    local lx, ly = tib_cell:to_leptons()
                    movement_system:move_to(entity, lx, ly)
                end
            end
        end
    end
end

-- RETURN: Return to refinery
AISystem.mission_handlers[Constants.MISSION.RETURN] = function(self, entity, mission)
    if not entity:has("harvester") or not entity:has("mobile") then
        return
    end

    local harvester = entity:get("harvester")
    local mobile = entity:get("mobile")
    local owner = entity:has("owner") and entity:get("owner") or nil

    -- Check if at refinery (not moving)
    if not mobile.is_moving then
        -- Unload at refinery
        if harvester.tiberium_load > 0 then
            -- Get harvest system and transfer tiberium to house credits
            local harvest_system = self.world:get_system("harvest")
            if harvest_system and owner then
                -- Calculate credits based on tiberium load
                local HarvestSystem = require("src.systems.harvest_system")
                local unload_amount = math.min(harvester.tiberium_load, HarvestSystem.UNLOAD_RATE)
                local credits_earned = unload_amount * HarvestSystem.TIBERIUM_VALUE

                -- Transfer credits
                harvest_system:add_credits(owner.house, credits_earned)

                -- Reduce harvester load
                harvester.tiberium_load = harvester.tiberium_load - unload_amount

                -- Emit event for audio feedback
                Events.emit("HARVESTER_UNLOADING", entity, unload_amount, credits_earned)

                -- If still has load, continue unloading next tick
                if harvester.tiberium_load > 0 then
                    return
                end
            else
                -- No harvest system, just clear the load
                harvester.tiberium_load = 0
            end
        end

        -- All tiberium unloaded, go back to harvesting
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
                -- Close enough, attempt to enter transport
                if target:has("cargo") then
                    local cargo = target:get("cargo")

                    -- Check if transport has room
                    if #cargo.passengers < cargo.capacity then
                        -- Enter the transport
                        table.insert(cargo.passengers, entity.id)

                        -- Hide the unit (remove from rendering, disable collision)
                        if entity:has("renderable") then
                            entity:get("renderable").visible = false
                        end
                        if entity:has("selectable") then
                            entity:get("selectable").is_selected = false
                            entity:get("selectable").can_select = false
                        end

                        -- Mark as inside transport
                        mission.inside_transport = target.id

                        -- Set to sleep while inside
                        self:set_mission(entity, Constants.MISSION.SLEEP)

                        Events.emit("UNIT_ENTERED_TRANSPORT", entity, target)
                    else
                        -- Transport full, return to guard
                        self:set_mission(entity, Constants.MISSION.GUARD)
                    end
                else
                    -- Target is not a transport
                    self:set_mission(entity, Constants.MISSION.GUARD)
                end
            else
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end
end

-- RETREAT: Run away from enemies
AISystem.mission_handlers[Constants.MISSION.RETREAT] = function(self, entity, mission)
    if not entity:has("mobile") or not self.movement_system then
        return
    end

    local transform = entity:get("transform")
    local owner = entity:get("owner")

    -- Find nearest enemy
    local enemies = self.world:get_entities_with("combat", "transform", "owner")
    local closest_enemy = nil
    local closest_dist = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy:is_alive() then
            local enemy_owner = enemy:get("owner")
            if enemy_owner.house ~= owner.house then
                local enemy_transform = enemy:get("transform")
                local dx = enemy_transform.x - transform.x
                local dy = enemy_transform.y - transform.y
                local dist = dx * dx + dy * dy

                if dist < closest_dist then
                    closest_dist = dist
                    closest_enemy = enemy
                end
            end
        end
    end

    if closest_enemy then
        -- Run away from enemy
        local enemy_transform = closest_enemy:get("transform")
        local dx = transform.x - enemy_transform.x
        local dy = transform.y - enemy_transform.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 0 then
            -- Normalize and run 5 cells away
            dx = dx / dist * 5 * Constants.LEPTON_PER_CELL
            dy = dy / dist * 5 * Constants.LEPTON_PER_CELL
            self.movement_system:move_to(entity, transform.x + dx, transform.y + dy)
        end
    else
        -- No enemies nearby, switch to guard
        self:set_mission(entity, Constants.MISSION.GUARD)
    end
end

-- AMBUSH: Wait in hiding until enemy comes near
AISystem.mission_handlers[Constants.MISSION.AMBUSH] = function(self, entity, mission)
    if not entity:has("combat") then
        return
    end

    local combat = entity:get("combat")
    local transform = entity:get("transform")

    -- Look for enemies in close range (closer than normal sight)
    if self.combat_system then
        local target = self.combat_system:find_target(entity)
        if target then
            local target_transform = target:get("transform")
            local dist = self.combat_system:calculate_distance(transform, target_transform)

            -- Only reveal if very close
            if dist <= combat.attack_range * 0.75 then
                combat.target = target.id
                self:set_mission(entity, Constants.MISSION.ATTACK, target)
            end
        end
    end
end

-- UNLOAD: Unload passengers from transport
AISystem.mission_handlers[Constants.MISSION.UNLOAD] = function(self, entity, mission)
    if not entity:has("cargo") then
        self:set_mission(entity, Constants.MISSION.GUARD)
        return
    end

    local cargo = entity:get("cargo")
    local transform = entity:get("transform")

    -- Unload one passenger at a time
    if #cargo.passengers > 0 then
        if cargo.unload_timer > 0 then
            cargo.unload_timer = cargo.unload_timer - 1
        else
            -- Pop a passenger and place them near the transport
            local passenger_id = table.remove(cargo.passengers, 1)
            local passenger = self.world:get_entity(passenger_id)

            if passenger and passenger:is_alive() then
                local passenger_transform = passenger:get("transform")

                -- Place passenger next to transport (use deterministic RNG for multiplayer sync)
                local offset_x = (Random.random() - 0.5) * Constants.LEPTON_PER_CELL
                local offset_y = (Random.random() - 0.5) * Constants.LEPTON_PER_CELL
                passenger_transform.x = transform.x + offset_x
                passenger_transform.y = transform.y + offset_y
                passenger_transform.cell_x = math.floor(passenger_transform.x / Constants.LEPTON_PER_CELL)
                passenger_transform.cell_y = math.floor(passenger_transform.y / Constants.LEPTON_PER_CELL)

                -- Make passenger visible and selectable again
                if passenger:has("renderable") then
                    passenger:get("renderable").visible = true
                end
                if passenger:has("selectable") then
                    passenger:get("selectable").can_select = true
                end

                -- Clear transport reference
                if passenger:has("mission") then
                    passenger:get("mission").inside_transport = nil
                end

                -- Set passenger to guard
                self:set_mission(passenger, Constants.MISSION.GUARD)

                self:emit(Events.EVENTS.UNIT_UNLOADED, entity, passenger)
            end

            cargo.unload_timer = 15  -- Delay before next unload
        end
    else
        -- All passengers unloaded
        self:set_mission(entity, Constants.MISSION.GUARD)
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

-- Give scatter order to infantry
-- Scatter makes infantry run to a random nearby location to avoid AOE damage
-- This is the classic C&C "X" key command
function AISystem:order_scatter(entity)
    if not entity:has("infantry") or not entity:has("mobile") or not entity:has("transform") then
        return false
    end

    local transform = entity:get("transform")
    local mobile = entity:get("mobile")

    -- Calculate random scatter direction and distance
    local angle = math.random() * math.pi * 2
    local distance = Constants.LEPTON_PER_CELL * (2 + math.random() * 3)  -- 2-5 cells away

    local dest_x = transform.x + math.cos(angle) * distance
    local dest_y = transform.y + math.sin(angle) * distance

    -- Move to scatter position
    self:set_mission(entity, Constants.MISSION.MOVE)
    if self.movement_system then
        self.movement_system:move_to(entity, dest_x, dest_y)
    end

    return true
end

-- Scatter multiple infantry units (avoiding overlap)
function AISystem:order_scatter_group(entities)
    if not entities or #entities == 0 then
        return
    end

    -- Calculate center of group
    local center_x, center_y = 0, 0
    local count = 0

    for _, entity in ipairs(entities) do
        if entity:has("infantry") and entity:has("transform") then
            local transform = entity:get("transform")
            center_x = center_x + transform.x
            center_y = center_y + transform.y
            count = count + 1
        end
    end

    if count == 0 then
        return
    end

    center_x = center_x / count
    center_y = center_y / count

    -- Scatter each unit away from center
    local angle_step = (math.pi * 2) / count
    local base_angle = math.random() * math.pi * 2

    local idx = 0
    for _, entity in ipairs(entities) do
        if entity:has("infantry") and entity:has("transform") and entity:has("mobile") then
            local transform = entity:get("transform")

            -- Direction away from center, with some angular spread
            local dx = transform.x - center_x
            local dy = transform.y - center_y
            local dist_from_center = math.sqrt(dx * dx + dy * dy)

            local angle
            if dist_from_center > Constants.LEPTON_PER_CELL then
                -- Move away from center
                angle = math.atan2(dy, dx) + (math.random() - 0.5) * 0.5
            else
                -- Units near center get evenly distributed angles
                angle = base_angle + idx * angle_step
            end

            local distance = Constants.LEPTON_PER_CELL * (3 + math.random() * 2)  -- 3-5 cells

            local dest_x = transform.x + math.cos(angle) * distance
            local dest_y = transform.y + math.sin(angle) * distance

            -- Set move mission
            self:set_mission(entity, Constants.MISSION.MOVE)
            if self.movement_system then
                self.movement_system:move_to(entity, dest_x, dest_y)
            end

            idx = idx + 1
        end
    end

    -- Play scatter sound
    Events.emit("PLAY_SOUND", "await1", center_x, center_y)
end

-- Get mission name for debugging
function AISystem:get_mission_name(entity)
    if not entity:has("mission") then
        return "None"
    end
    local mission_type = entity:get("mission").mission_type
    return self.MISSION_NAMES[mission_type] or "Unknown"
end

-- Fear level constants (from INFANTRY.H)
AISystem.FEAR_ANXIOUS = 10    -- Something makes them scared
AISystem.FEAR_SCARED = 100    -- Scared enough to take cover
AISystem.FEAR_PANIC = 200     -- Run away! Run away!
AISystem.FEAR_MAXIMUM = 255   -- Maximum fear

-- Fear decay rate (fear decreases over time when not being shot at)
AISystem.FEAR_DECAY_RATE = 1  -- per tick

-- Update infantry fear and prone state
-- Reference: INFANTRY.CPP - Infantry::AI() fear handling
-- When fear >= FEAR_ANXIOUS and not moving, infantry will go prone
-- Prone infantry take 50% damage and move at 50% speed (crawling)
function AISystem:update_infantry_fear(entity, dt)
    if not entity:has("infantry") then return end

    local infantry = entity:get("infantry")
    local mobile = entity:has("mobile") and entity:get("mobile")
    local is_moving = mobile and mobile.path and #mobile.path > 0

    -- Decay fear over time
    if infantry.fear > 0 then
        infantry.fear = math.max(0, infantry.fear - self.FEAR_DECAY_RATE)
    end

    -- Handle prone state based on fear
    if infantry.prone then
        -- Get up if fear drops below anxious and not stationary
        if infantry.fear < self.FEAR_ANXIOUS then
            self:infantry_get_up(entity)
        end
    else
        -- Go prone if scared and not moving (unless fraidy cat)
        -- Reference: IsProne logic in INFANTRY.CPP line 1094
        if infantry.fear >= self.FEAR_ANXIOUS and not is_moving and not infantry.is_fraidy_cat then
            self:infantry_go_prone(entity)
        end
    end

    -- Fraidy cats (civilians) run when scared instead of going prone
    if infantry.is_fraidy_cat and infantry.fear > self.FEAR_ANXIOUS and not is_moving then
        self:order_scatter(entity)
    end
end

-- Make infantry go prone (lie down)
-- Reference: INFANTRY.CPP - Do_Action(DO_LIE_DOWN)
function AISystem:infantry_go_prone(entity)
    if not entity:has("infantry") then return end

    local infantry = entity:get("infantry")
    if infantry.prone then return end  -- Already prone

    -- Civilians with no crawl animation can't go prone
    if infantry.is_fraidy_cat and not infantry.is_crawling then
        return
    end

    infantry.prone = true

    -- Reduce movement speed when prone (crawling)
    if entity:has("mobile") then
        local mobile = entity:get("mobile")
        mobile.speed_modifier = (mobile.speed_modifier or 1.0) * 0.5
    end

    -- Emit event for animation system
    Events.emit("INFANTRY_PRONE", entity, true)
end

-- Make infantry get up from prone position
-- Reference: INFANTRY.CPP - Do_Action(DO_GET_UP)
function AISystem:infantry_get_up(entity)
    if not entity:has("infantry") then return end

    local infantry = entity:get("infantry")
    if not infantry.prone then return end  -- Not prone

    infantry.prone = false

    -- Restore movement speed
    if entity:has("mobile") then
        local mobile = entity:get("mobile")
        mobile.speed_modifier = (mobile.speed_modifier or 0.5) * 2.0
    end

    -- Emit event for animation system
    Events.emit("INFANTRY_PRONE", entity, false)
end

-- Increase infantry fear when taking damage or seeing combat
-- Reference: INFANTRY.CPP - Take_Damage() lines 542-551
function AISystem:increase_infantry_fear(entity, damage_source, damage_amount)
    if not entity:has("infantry") then return end

    local infantry = entity:get("infantry")

    -- Calculate fear increase based on damage
    local fear_increase = self.FEAR_ANXIOUS

    -- More fear from nearby explosions
    if damage_amount and damage_amount > 20 then
        fear_increase = self.FEAR_SCARED
    end

    -- Max out fear if damage is lethal-level
    if damage_amount and damage_amount > 50 then
        fear_increase = self.FEAR_PANIC
    end

    infantry.fear = math.min(infantry.fear + fear_increase, self.FEAR_MAXIMUM)
end

-- Force infantry to get up (when ordered to move by player)
-- Reference: INFANTRY.CPP line 929 - double-clicking destination forces get up
function AISystem:force_infantry_get_up(entity)
    if not entity:has("infantry") then return end

    local infantry = entity:get("infantry")

    -- Only get up if not a fraidy cat (they run scared)
    if not infantry.is_fraidy_cat and infantry.prone then
        self:infantry_get_up(entity)
        infantry.fear = 0  -- Reset fear when ordered to move
    end
end

return AISystem
