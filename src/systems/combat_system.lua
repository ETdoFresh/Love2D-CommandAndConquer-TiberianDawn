--[[
    Combat System - Handles weapons, projectiles, and damage
    Reference: TECHNO.H, BULLET.H
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")
local Direction = require("src.util.direction")
local Component = require("src.ecs.component")

local CombatSystem = setmetatable({}, {__index = System})
CombatSystem.__index = CombatSystem

-- Armor modifiers for damage calculation
CombatSystem.ARMOR_MODIFIERS = {
    none = {small_arms = 1.0, ap = 0.8, he = 1.0, fire = 1.5, super = 1.0},
    light = {small_arms = 0.5, ap = 1.0, he = 0.9, fire = 1.0, super = 1.0},
    heavy = {small_arms = 0.25, ap = 1.0, he = 0.5, fire = 0.5, super = 1.0},
    wood = {small_arms = 0.5, ap = 0.75, he = 1.0, fire = 1.5, super = 1.0},
    steel = {small_arms = 0.25, ap = 1.0, he = 0.75, fire = 0.25, super = 1.0}
}

function CombatSystem.new()
    local self = System.new("combat", {"transform", "combat"})
    setmetatable(self, CombatSystem)

    -- Active projectiles
    self.projectiles = {}
    self.next_projectile_id = 1

    -- Weapon data (loaded from JSON)
    self.weapons = {}

    return self
end

function CombatSystem:init()
    -- Load weapon data
    self:load_weapon_data()
end

function CombatSystem:load_weapon_data()
    local Serialize = require("src.util.serialize")
    local data = Serialize.load_json("data/weapons/weapons.json")
    if data then
        self.weapons = data
    end
end

function CombatSystem:update(dt, entities)
    -- Update all combat entities
    for _, entity in ipairs(entities) do
        self:process_entity(dt, entity)
    end

    -- Update projectiles
    self:update_projectiles(dt)
end

function CombatSystem:process_entity(dt, entity)
    local combat = entity:get("combat")
    local transform = entity:get("transform")

    -- Decrease rearm timer
    if combat.rearm_timer > 0 then
        combat.rearm_timer = combat.rearm_timer - 1
    end

    -- Check if we have a target
    if combat.target then
        local target = self.world:get_entity(combat.target)

        if not target or not target:is_alive() then
            -- Target lost
            combat.target = nil
            return
        end

        -- Check if target is in range
        local target_transform = target:get("transform")
        if not target_transform then
            combat.target = nil
            return
        end

        local dist = self:calculate_distance(transform, target_transform)
        local range = combat.attack_range

        if dist <= range then
            -- In range - try to attack
            self:attempt_attack(entity, target)
        end
    end
end

function CombatSystem:calculate_distance(t1, t2)
    local dx = t2.x - t1.x
    local dy = t2.y - t1.y
    -- Distance in cells (leptons / LEPTON_PER_CELL)
    return math.sqrt(dx * dx + dy * dy) / Constants.LEPTON_PER_CELL
end

function CombatSystem:attempt_attack(attacker, target)
    local combat = attacker:get("combat")
    local transform = attacker:get("transform")
    local target_transform = target:get("transform")

    -- Check rearm timer (apply power penalty for defensive buildings)
    local rearm_remaining = combat.rearm_timer
    if rearm_remaining > 0 then
        -- Buildings fire slower when power is low
        if attacker:has("building") and attacker:has("owner") then
            local owner = attacker:get("owner")
            local power_system = self.world:get_system("power")
            if power_system then
                local defense_mult = power_system:get_defense_multiplier(owner.house)
                -- Lower multiplier = slower rearm (subtract less per tick)
                rearm_remaining = rearm_remaining - defense_mult
                combat.rearm_timer = math.max(0, rearm_remaining)
            end
        end
        return false
    end

    -- Check ammo
    if combat.ammo == 0 then
        return false
    end

    -- Get weapon
    local weapon_name = combat.primary_weapon
    if not weapon_name then
        return false
    end

    local weapon = self.weapons[weapon_name]
    if not weapon then
        return false
    end

    -- Check if we need to rotate turret
    if attacker:has("turret") then
        local turret = attacker:get("turret")
        local desired_facing = Direction.from_points_full(
            transform.x, transform.y,
            target_transform.x, target_transform.y
        )

        if turret.facing ~= desired_facing then
            -- Need to rotate
            turret.facing = Direction.turn_towards_full(turret.facing, desired_facing)
            return false
        end
    end

    -- Fire weapon
    self:fire_weapon(attacker, target, weapon)

    -- Set rearm timer
    combat.rearm_timer = weapon.rate_of_fire or 15

    -- Decrease ammo
    if combat.ammo > 0 then
        combat.ammo = combat.ammo - 1
    end

    return true
end

function CombatSystem:fire_weapon(attacker, target, weapon)
    local transform = attacker:get("transform")
    local target_transform = target:get("transform")

    -- Create projectile
    local projectile = {
        id = self.next_projectile_id,
        source = attacker.id,
        target = target.id,
        weapon = weapon,
        x = transform.x,
        y = transform.y,
        target_x = target_transform.x,
        target_y = target_transform.y,
        speed = 100,  -- Leptons per tick
        damage = weapon.damage,
        warhead = weapon.warhead or "ap",
        homing = weapon.homing or false,
        alive = true
    }

    self.next_projectile_id = self.next_projectile_id + 1

    -- For instant-hit weapons, apply damage immediately
    if weapon.projectile == "invisible" or weapon.projectile == "laser" then
        self:apply_damage(target, projectile.damage, projectile.warhead, attacker)
        -- Emit attack event
        self:emit(Events.EVENTS.UNIT_ATTACKED, attacker, target, weapon)
    else
        -- Add to projectile list
        table.insert(self.projectiles, projectile)
    end
end

function CombatSystem:update_projectiles(dt)
    local to_remove = {}

    for i, proj in ipairs(self.projectiles) do
        if proj.alive then
            -- Get target position (for homing)
            local target = self.world:get_entity(proj.target)
            if proj.homing and target and target:is_alive() then
                local target_transform = target:get("transform")
                proj.target_x = target_transform.x
                proj.target_y = target_transform.y
            end

            -- Move projectile
            local dx = proj.target_x - proj.x
            local dy = proj.target_y - proj.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist <= proj.speed then
                -- Reached target
                proj.x = proj.target_x
                proj.y = proj.target_y
                proj.alive = false

                -- Apply damage to target
                if target and target:is_alive() then
                    local attacker = self.world:get_entity(proj.source)
                    self:apply_damage(target, proj.damage, proj.warhead, attacker)
                    self:emit(Events.EVENTS.UNIT_ATTACKED, attacker, target, proj.weapon)
                end

                table.insert(to_remove, i)
            else
                -- Move towards target
                proj.x = proj.x + (dx / dist) * proj.speed
                proj.y = proj.y + (dy / dist) * proj.speed
            end
        else
            table.insert(to_remove, i)
        end
    end

    -- Remove dead projectiles
    for i = #to_remove, 1, -1 do
        table.remove(self.projectiles, to_remove[i])
    end
end

function CombatSystem:apply_damage(target, damage, warhead, attacker)
    if not target:has("health") then
        return 0
    end

    local health = target:get("health")
    local armor = health.armor or "none"

    -- Apply armor modifier
    local modifiers = self.ARMOR_MODIFIERS[armor] or self.ARMOR_MODIFIERS.none
    local modifier = modifiers[warhead] or 1.0

    local final_damage = math.floor(damage * modifier)

    -- Apply damage
    health.hp = health.hp - final_damage

    -- Flash effect
    if target:has("renderable") then
        target:get("renderable").flash = true
    end

    -- Check for death
    if health.hp <= 0 then
        health.hp = 0
        self:kill_unit(target, attacker)
    end

    -- Emit damage event
    self:emit(Events.EVENTS.ENTITY_DAMAGED, target, final_damage, attacker)

    return final_damage
end

function CombatSystem:kill_unit(target, killer)
    -- Emit kill event
    self:emit(Events.EVENTS.UNIT_KILLED, target, killer)
    self:emit(Events.EVENTS.ENTITY_KILLED, target, killer)

    -- Mark for destruction
    self.world:destroy_entity(target)
end

-- Set target for an entity
function CombatSystem:set_target(attacker, target)
    if not attacker:has("combat") then
        return false
    end

    local combat = attacker:get("combat")
    combat.target = target and target.id or nil
    return true
end

-- Find best target in range
function CombatSystem:find_target(entity, threat_mask)
    if not entity:has("combat") or not entity:has("transform") or not entity:has("owner") then
        return nil
    end

    local combat = entity:get("combat")
    local transform = entity:get("transform")
    local owner = entity:get("owner")

    local best_target = nil
    local best_dist = math.huge

    -- Get all potential targets
    local targets = self.world:get_entities_with("transform", "health", "owner")

    for _, target in ipairs(targets) do
        if target.id ~= entity.id and target:is_alive() then
            local target_owner = target:get("owner")

            -- Check if enemy
            if target_owner.house ~= owner.house then
                local target_transform = target:get("transform")
                local dist = self:calculate_distance(transform, target_transform)

                -- Check range
                if dist <= combat.attack_range and dist < best_dist then
                    best_dist = dist
                    best_target = target
                end
            end
        end
    end

    return best_target
end

-- Get projectiles for rendering
function CombatSystem:get_projectiles()
    return self.projectiles
end

-- Draw projectiles
function CombatSystem:draw_projectiles(render_system)
    for _, proj in ipairs(self.projectiles) do
        if proj.alive then
            -- Convert to screen coordinates
            local px = proj.x / Constants.PIXEL_LEPTON_W
            local py = proj.y / Constants.PIXEL_LEPTON_H

            love.graphics.setColor(1, 0.8, 0, 1)
            love.graphics.circle("fill", px, py, 2)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return CombatSystem
