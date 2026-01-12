--[[
    Turret System - Handles turret rotation for vehicles and buildings

    In original C&C, turrets:
    - Rotate independently from vehicle body
    - Track towards target when attacking
    - Return to align with body facing when idle
    - Have different rotation speeds (tanks slower than lighter vehicles)
]]

local System = require("src.ecs.system")
local Direction = require("src.util.direction")
local Constants = require("src.core.constants")

local TurretSystem = setmetatable({}, {__index = System})
TurretSystem.__index = TurretSystem

-- Turret states
TurretSystem.STATE = {
    IDLE = 0,      -- Not tracking, return to body alignment
    TRACKING = 1,  -- Actively following a target
    LOCKED = 2     -- Locked on target, ready to fire
}

function TurretSystem.new()
    local self = System.new("turret", {"transform", "turret"})
    setmetatable(self, TurretSystem)

    -- Default rotation speed (full rotations per tick, in 32-direction units)
    -- Original C&C tanks rotate at about 2 facing units per tick
    self.default_rotation_speed = 2

    -- Idle delay before turret starts returning to body alignment
    self.idle_delay = 30  -- ~2 seconds at 15 FPS

    return self
end

function TurretSystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end
end

function TurretSystem:process_entity(dt, entity)
    local transform = entity:get("transform")
    local turret = entity:get("turret")

    if not turret.has_turret then return end

    -- Determine desired turret facing
    local desired_facing = nil
    local tracking_target = false

    -- Check if we have a combat target to track
    if entity:has("combat") then
        local combat = entity:get("combat")
        if combat.target then
            -- Try to get target entity
            local target = self.world and self.world:get_entity(combat.target)
            if target and target:has("transform") then
                local target_transform = target:get("transform")
                -- Calculate facing to target using 32-direction precision
                desired_facing = Direction.from_points_full(
                    transform.x, transform.y,
                    target_transform.x, target_transform.y
                )
                tracking_target = true
                turret.idle_timer = 0  -- Reset idle timer
            end
        end
    end

    -- If not tracking, check idle behavior
    if not tracking_target then
        turret.idle_timer = (turret.idle_timer or 0) + 1

        if turret.idle_timer >= self.idle_delay then
            -- Return turret to align with body
            -- Convert body facing (8-direction) to turret facing (32-direction)
            desired_facing = Direction.facing_to_full(transform.facing)
        end
    end

    -- Rotate turret towards desired facing
    if desired_facing and turret.facing ~= desired_facing then
        local rotation_speed = turret.rotation_speed or self.default_rotation_speed

        -- Calculate shortest turn direction
        local diff = Direction.shortest_turn_full(turret.facing, desired_facing)

        -- Apply rotation limited by speed
        if math.abs(diff) <= rotation_speed then
            turret.facing = desired_facing
        else
            if diff > 0 then
                turret.facing = (turret.facing + rotation_speed) % Direction.FULL_COUNT
            else
                turret.facing = (turret.facing - rotation_speed + Direction.FULL_COUNT) % Direction.FULL_COUNT
            end
        end
    end
end

-- Check if turret is aligned with target
function TurretSystem:is_aimed_at_target(entity, target)
    if not entity:has("turret") or not entity:has("transform") then
        return true  -- No turret, always "aimed"
    end

    local turret = entity:get("turret")
    if not turret.has_turret then
        return true
    end

    local transform = entity:get("transform")
    local target_transform = target:get("transform")

    local desired = Direction.from_points_full(
        transform.x, transform.y,
        target_transform.x, target_transform.y
    )

    -- Allow small tolerance (1 facing unit)
    local diff = Direction.shortest_turn_full(turret.facing, desired)
    return math.abs(diff) <= 1
end

-- Force turret to face a direction (used for deployed defensive buildings)
function TurretSystem:set_facing(entity, facing)
    if entity:has("turret") then
        local turret = entity:get("turret")
        turret.facing = facing
        turret.idle_timer = 0
    end
end

-- Get turret's current facing angle in radians
function TurretSystem:get_angle(entity)
    if entity:has("turret") then
        local turret = entity:get("turret")
        return Direction.full_to_angle(turret.facing)
    end
    return 0
end

return TurretSystem
