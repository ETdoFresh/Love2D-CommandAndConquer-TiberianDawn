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

-- Warhead data loaded from JSON (populated in init)
CombatSystem.warheads = {}

-- Warhead name mapping (weapons.json uses lowercase names, warheads.json uses uppercase)
CombatSystem.WARHEAD_MAP = {
    small_arms = "SA",
    he = "HE",
    ap = "AP",
    fire = "FIRE",
    laser = "LASER",
    super = "PB",  -- Particle beam for super weapons
    -- Direct mappings
    SA = "SA",
    HE = "HE",
    AP = "AP",
    FIRE = "FIRE",
    LASER = "LASER",
    PB = "PB",
    FIST = "FIST",
    FOOT = "FOOT",
    HOLLOW_POINT = "HOLLOW_POINT",
    SPORE = "SPORE",
    HEADBUTT = "HEADBUTT",
    FEEDME = "FEEDME"
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
    -- Load weapon, warhead, and projectile data
    self:load_weapon_data()
    self:load_warhead_data()
    self:load_projectile_data()
end

function CombatSystem:load_weapon_data()
    local Serialize = require("src.util.serialize")
    local data = Serialize.load_json("data/weapons/weapons.json")
    if data then
        self.weapons = data
    end
end

-- Load warhead damage modifiers from JSON
function CombatSystem:load_warhead_data()
    local Serialize = require("src.util.serialize")
    local data = Serialize.load_json("data/weapons/warheads.json")
    if data and data.warheads then
        CombatSystem.warheads = data.warheads
    end
end

-- Load projectile data from JSON
function CombatSystem:load_projectile_data()
    local Serialize = require("src.util.serialize")
    local data = Serialize.load_json("data/weapons/projectiles.json")
    if data and data.projectiles then
        CombatSystem.projectile_data = data.projectiles
    end
end

-- Get projectile speed for a projectile type
function CombatSystem:get_projectile_speed(proj_type)
    -- First check loaded JSON data
    if CombatSystem.projectile_data and CombatSystem.projectile_data[proj_type] then
        return CombatSystem.projectile_data[proj_type].speed or 100
    end
    -- Fall back to hardcoded speeds
    return CombatSystem.PROJECTILE_SPEEDS[proj_type] or CombatSystem.PROJECTILE_SPEEDS.default
end

-- Get projectile behavior flags from data
function CombatSystem:get_projectile_behavior(proj_type)
    if CombatSystem.projectile_data and CombatSystem.projectile_data[proj_type] then
        local data = CombatSystem.projectile_data[proj_type]
        return {
            homing = data.homing or false,
            arcing = data.arcing or false,
            dropping = data.dropping or false,
            invisible = data.invisible or false,
            rotates = data.rotates or false,
            inaccurate = data.inaccurate or false,
            high = data.high or false
        }
    end
    return {}
end

-- Get damage modifier for a warhead against armor type
-- Returns multiplier (1.0 = full damage, 0.5 = half damage)
function CombatSystem:get_damage_modifier(warhead_name, armor_type)
    -- Map warhead name to canonical form
    local warhead_key = CombatSystem.WARHEAD_MAP[warhead_name] or "SA"
    local warhead = CombatSystem.warheads[warhead_key]

    if not warhead or not warhead.modifiers then
        -- Fallback: 100% damage
        return 1.0
    end

    -- Get modifier for armor type (default to 'none' if not specified)
    local armor = armor_type or "none"
    local modifier = warhead.modifiers[armor]

    if modifier then
        return modifier / 100  -- Convert percentage to multiplier
    end

    return 1.0
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

    -- Get projectile type and speed from data files
    local proj_type = weapon.projectile or "default"
    local speed = self:get_projectile_speed(proj_type)
    local behavior = self:get_projectile_behavior(proj_type)

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
        speed = speed,
        damage = weapon.damage,
        warhead = weapon.warhead or "ap",
        homing = weapon.homing or behavior.homing or false,
        inaccurate = weapon.inaccurate or behavior.inaccurate or false,
        arcing = behavior.arcing or false,
        high = behavior.high or false,
        alive = true
    }

    -- Add inaccuracy for artillery-type weapons
    if projectile.inaccurate then
        local scatter = Constants.LEPTON_PER_CELL * 2  -- 2 cell scatter
        projectile.target_x = projectile.target_x + (math.random() - 0.5) * scatter
        projectile.target_y = projectile.target_y + (math.random() - 0.5) * scatter
    end

    self.next_projectile_id = self.next_projectile_id + 1

    -- For instant-hit weapons, apply damage immediately
    if weapon.projectile == "invisible" then
        self:apply_damage(target, projectile.damage, projectile.warhead, attacker)
        -- Emit attack event
        self:emit(Events.EVENTS.UNIT_ATTACKED, attacker, target, weapon)
    elseif weapon.projectile == "laser" then
        -- Laser shows beam briefly then applies damage
        projectile.lifetime = 8  -- Show laser for 8 ticks
        table.insert(self.projectiles, projectile)
        self:apply_damage(target, projectile.damage, projectile.warhead, attacker)
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
            -- Handle timed projectiles (laser beams)
            if proj.lifetime then
                proj.lifetime = proj.lifetime - 1
                if proj.lifetime <= 0 then
                    proj.alive = false
                    table.insert(to_remove, i)
                end
            else
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

                    -- Apply damage to target (unless already applied for instant weapons)
                    if not proj.damage_applied then
                        if target and target:is_alive() then
                            local attacker = self.world:get_entity(proj.source)
                            self:apply_damage(target, proj.damage, proj.warhead, attacker)
                            self:emit(Events.EVENTS.UNIT_ATTACKED, attacker, target, proj.weapon)
                        elseif proj.inaccurate then
                            -- Artillery can still damage nearby units even if target moved
                            self:apply_splash_damage(proj)
                        end
                    end

                    table.insert(to_remove, i)
                else
                    -- Move towards target
                    proj.x = proj.x + (dx / dist) * proj.speed
                    proj.y = proj.y + (dy / dist) * proj.speed
                end
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

-- Apply splash damage at projectile impact point (for artillery, explosives)
function CombatSystem:apply_splash_damage(proj)
    local splash_radius = proj.weapon.splash_radius or 1  -- In cells
    local splash_damage = proj.weapon.splash_damage or (proj.damage * 0.5)

    -- Find units near impact point
    local targets = self.world:get_entities_with("transform", "health")
    local attacker = self.world:get_entity(proj.source)

    for _, target in ipairs(targets) do
        if target:is_alive() then
            local transform = target:get("transform")
            local dx = transform.x - proj.target_x
            local dy = transform.y - proj.target_y
            local dist = math.sqrt(dx * dx + dy * dy) / Constants.LEPTON_PER_CELL

            if dist <= splash_radius then
                -- Damage falls off with distance
                local damage_mult = 1 - (dist / splash_radius)
                local damage = math.floor(splash_damage * damage_mult)
                if damage > 0 then
                    self:apply_damage(target, damage, proj.warhead, attacker)
                end
            end
        end
    end

    -- Also damage walls in splash radius
    self:apply_wall_splash_damage(proj.target_x, proj.target_y, splash_radius, splash_damage, proj.warhead)
end

-- Apply damage to walls in an area (for explosives, splash weapons)
function CombatSystem:apply_wall_splash_damage(center_x, center_y, radius, damage, warhead)
    -- Check if warhead can destroy walls
    local warhead_key = CombatSystem.WARHEAD_MAP[warhead] or "SA"
    local warhead_data = CombatSystem.warheads[warhead_key]
    if warhead_data and warhead_data.destroys_walls == false then
        return  -- Warhead cannot damage walls
    end

    -- Get grid reference
    local grid = self.world and self.world.grid
    if not grid then return end

    -- Calculate cell coordinates
    local center_cell_x = math.floor(center_x / Constants.LEPTON_PER_CELL)
    local center_cell_y = math.floor(center_y / Constants.LEPTON_PER_CELL)

    -- Check cells in radius
    local cell_radius = math.ceil(radius)
    for dy = -cell_radius, cell_radius do
        for dx = -cell_radius, cell_radius do
            local cell = grid:get_cell(center_cell_x + dx, center_cell_y + dy)
            if cell and cell:has_wall() then
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= radius then
                    -- Damage falls off with distance
                    local damage_mult = 1 - (dist / radius)
                    local wall_damage = math.floor(damage * damage_mult)
                    if wall_damage > 0 then
                        local destroyed = cell:damage_wall(wall_damage)
                        if destroyed then
                            -- Emit wall destroyed event
                            Events.emit(Events.EVENTS.WALL_DESTROYED, cell.x, cell.y)
                        end
                    end
                end
            end
        end
    end
end

-- Direct damage to a wall at a specific cell
function CombatSystem:damage_wall_at(cell_x, cell_y, damage, warhead)
    local grid = self.world and self.world.grid
    if not grid then return false end

    local cell = grid:get_cell(cell_x, cell_y)
    if not cell or not cell:has_wall() then
        return false
    end

    -- Check if warhead can destroy walls
    local warhead_key = CombatSystem.WARHEAD_MAP[warhead] or "SA"
    local warhead_data = CombatSystem.warheads[warhead_key]
    if warhead_data and warhead_data.destroys_walls == false then
        return false
    end

    -- Apply damage modifier based on wall armor
    local Theater = require("src.map.theater")
    local overlay_data = Theater.get_overlay_by_id(cell.overlay)
    local armor = overlay_data and overlay_data.armor or "concrete"
    local modifier = self:get_damage_modifier(warhead, armor)
    local final_damage = math.floor(damage * modifier)

    local destroyed = cell:damage_wall(final_damage)
    if destroyed then
        Events.emit(Events.EVENTS.WALL_DESTROYED, cell_x, cell_y)
    end
    return destroyed
end

function CombatSystem:apply_damage(target, damage, warhead, attacker)
    if not target:has("health") then
        return 0
    end

    local health = target:get("health")
    local armor = health.armor or "none"

    -- Apply armor modifier using warhead data from JSON
    local modifier = self:get_damage_modifier(warhead, armor)
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
    -- Spawn death/explosion effect based on unit type
    self:spawn_death_effect(target)

    -- Emit kill event (ENTITY_KILLED is for game logic like scoring)
    self:emit(Events.EVENTS.UNIT_KILLED, target, killer)
    self:emit(Events.EVENTS.ENTITY_KILLED, target, killer)

    -- Emit ENTITY_DESTROYED for trigger system (before removal from world)
    -- This must happen before destroy_entity so triggers can evaluate it
    self:emit(Events.EVENTS.ENTITY_DESTROYED, target, killer)

    -- Mark for destruction
    self.world:destroy_entity(target)
end

-- Spawn death/explosion animation at target's position
function CombatSystem:spawn_death_effect(target)
    if not target:has("transform") then
        return
    end

    local transform = target:get("transform")
    local effect_type = "explosion_small"  -- Default

    -- Determine effect type based on what died
    if target:has("infantry") then
        effect_type = "infantry_death"
    elseif target:has("vehicle") then
        effect_type = "explosion_medium"
    elseif target:has("aircraft") then
        effect_type = "explosion_large"
    elseif target:has("building") then
        effect_type = "explosion_large"
    end

    -- Create effect entity
    local Entity = require("src.ecs.entity")
    local Component = require("src.ecs.component")

    local effect = Entity.new()

    -- Transform at death location
    effect:add("transform", Component.create("transform", {
        x = transform.x,
        y = transform.y,
        cell_x = transform.cell_x,
        cell_y = transform.cell_y
    }))

    -- Renderable
    effect:add("renderable", Component.create("renderable", {
        visible = true,
        layer = Constants.LAYER.TOP or 3,  -- Render on top
        sprite = effect_type .. ".shp",
        color = {1, 1, 1, 1}
    }))

    -- Animation component for death animation
    effect:add("animation", Component.create("animation", {
        current = "play",
        frame = 0,
        timer = 0,
        looping = false,
        playing = true
    }))

    -- Tag for cleanup
    effect:add_tag("effect")
    effect:add_tag("death_effect")

    -- Set effect lifetime (will be cleaned up by animation system when done)
    effect.effect_lifetime = self:get_effect_duration(effect_type)
    effect.effect_timer = 0

    self.world:add_entity(effect)

    return effect
end

-- Get effect duration in ticks based on effect type
function CombatSystem:get_effect_duration(effect_type)
    local durations = {
        infantry_death = 15,    -- 1 second at 15 FPS
        explosion_small = 10,
        explosion_medium = 15,
        explosion_large = 20
    }
    return durations[effect_type] or 15
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

-- Threat priority values (higher = prioritize)
CombatSystem.THREAT_PRIORITY = {
    ATTACKING_ME = 100,     -- Target that is attacking this unit
    ATTACKING_ALLY = 50,    -- Target attacking nearby ally
    HARVESTER = 40,         -- Enemy harvesters (high value)
    INFANTRY = 30,          -- Infantry
    VEHICLE = 25,           -- Vehicles
    AIRCRAFT = 20,          -- Aircraft
    BUILDING = 10,          -- Buildings (lowest combat priority)
    DEFAULT = 15
}

-- Find best target in range with proper threat prioritization
function CombatSystem:find_target(entity, threat_mask)
    if not entity:has("combat") or not entity:has("transform") or not entity:has("owner") then
        return nil
    end

    local combat = entity:get("combat")
    local transform = entity:get("transform")
    local owner = entity:get("owner")

    local best_target = nil
    local best_score = -math.huge

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
                if dist <= combat.attack_range then
                    local score = self:calculate_threat_score(entity, target, dist)

                    if score > best_score then
                        best_score = score
                        best_target = target
                    end
                end
            end
        end
    end

    return best_target
end

-- Calculate threat score for target prioritization (like original TECHNO.CPP)
function CombatSystem:calculate_threat_score(attacker, target, distance)
    local score = 0

    -- Base priority by target type
    if target:has("harvester") then
        score = score + CombatSystem.THREAT_PRIORITY.HARVESTER
    elseif target:has("infantry") then
        score = score + CombatSystem.THREAT_PRIORITY.INFANTRY
    elseif target:has("aircraft") then
        score = score + CombatSystem.THREAT_PRIORITY.AIRCRAFT
    elseif target:has("building") then
        score = score + CombatSystem.THREAT_PRIORITY.BUILDING
    elseif target:has("mobile") then
        score = score + CombatSystem.THREAT_PRIORITY.VEHICLE
    else
        score = score + CombatSystem.THREAT_PRIORITY.DEFAULT
    end

    -- Bonus if target is attacking us
    if target:has("combat") then
        local target_combat = target:get("combat")
        if target_combat.target == attacker.id then
            score = score + CombatSystem.THREAT_PRIORITY.ATTACKING_ME
        end
    end

    -- Distance factor - closer targets score higher (normalize by range)
    local attacker_combat = attacker:get("combat")
    local range = attacker_combat.attack_range or 5
    local distance_factor = 1 - (distance / range)  -- 0 to 1, higher when closer
    score = score + (distance_factor * 20)

    -- Bonus for wounded targets (finish them off)
    if target:has("health") then
        local health = target:get("health")
        local hp_ratio = health.hp / health.max_hp
        if hp_ratio < 0.25 then
            score = score + 15  -- Nearly dead, prioritize
        elseif hp_ratio < 0.5 then
            score = score + 10  -- Wounded
        end
    end

    return score
end

-- Get projectiles for rendering
function CombatSystem:get_projectiles()
    return self.projectiles
end

-- Projectile visual definitions (from BULLET.CPP)
CombatSystem.PROJECTILE_VISUALS = {
    shell = {color = {1, 0.8, 0, 1}, size = 2, trail = false, shape = "circle"},
    rocket = {color = {1, 0.5, 0, 1}, size = 3, trail = true, shape = "triangle"},
    sam = {color = {1, 0.3, 0, 1}, size = 3, trail = true, shape = "triangle"},
    mlrs_rocket = {color = {1, 0.4, 0, 1}, size = 4, trail = true, shape = "triangle"},
    grenade = {color = {0.3, 0.3, 0.3, 1}, size = 3, trail = false, shape = "circle"},
    flame = {color = {1, 0.5, 0, 0.8}, size = 4, trail = true, shape = "flame"},
    napalm = {color = {1, 0.3, 0, 0.9}, size = 5, trail = true, shape = "flame"},
    chem = {color = {0.2, 0.9, 0.2, 0.8}, size = 4, trail = true, shape = "spray"},
    artillery = {color = {0.4, 0.4, 0.4, 1}, size = 3, trail = false, shape = "circle"},
    laser = {color = {1, 0, 0, 1}, size = 2, trail = false, shape = "line"},
    nuke = {color = {1, 1, 0, 1}, size = 6, trail = true, shape = "triangle"},
    ion_beam = {color = {0.5, 0.5, 1, 1}, size = 8, trail = false, shape = "beam"},
    default = {color = {1, 1, 0, 1}, size = 2, trail = false, shape = "circle"}
}

-- Projectile speeds (leptons per tick) from BULLET.CPP
CombatSystem.PROJECTILE_SPEEDS = {
    shell = 120,
    rocket = 80,
    sam = 100,
    mlrs_rocket = 60,
    grenade = 60,
    flame = 50,
    napalm = 40,
    chem = 50,
    artillery = 80,
    nuke = 40,
    default = 100
}

-- Draw projectiles with proper visuals
function CombatSystem:draw_projectiles(render_system)
    for _, proj in ipairs(self.projectiles) do
        if proj.alive then
            -- Convert to screen coordinates
            local px = proj.x / Constants.PIXEL_LEPTON_W
            local py = proj.y / Constants.PIXEL_LEPTON_H

            -- Get visual style for this projectile type
            local proj_type = proj.weapon.projectile or "default"
            local visual = CombatSystem.PROJECTILE_VISUALS[proj_type] or CombatSystem.PROJECTILE_VISUALS.default

            love.graphics.setColor(unpack(visual.color))

            -- Draw trail if applicable
            if visual.trail then
                local trail_len = 8
                local dx = proj.target_x - proj.x
                local dy = proj.target_y - proj.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0 then
                    local tx = px - (dx / dist) * trail_len
                    local ty = py - (dy / dist) * trail_len
                    love.graphics.setColor(visual.color[1], visual.color[2], visual.color[3], 0.4)
                    love.graphics.line(px, py, tx, ty)
                    love.graphics.setColor(unpack(visual.color))
                end
            end

            -- Draw projectile based on shape
            if visual.shape == "circle" then
                love.graphics.circle("fill", px, py, visual.size)
            elseif visual.shape == "triangle" then
                -- Oriented towards target
                local dx = proj.target_x - proj.x
                local dy = proj.target_y - proj.y
                local angle = math.atan2(dy, dx)
                local s = visual.size
                love.graphics.polygon("fill",
                    px + math.cos(angle) * s * 1.5, py + math.sin(angle) * s * 1.5,
                    px + math.cos(angle + 2.5) * s, py + math.sin(angle + 2.5) * s,
                    px + math.cos(angle - 2.5) * s, py + math.sin(angle - 2.5) * s
                )
            elseif visual.shape == "flame" then
                -- Animated flame effect
                local flicker = math.sin(love.timer.getTime() * 20) * 0.5 + 0.5
                love.graphics.setColor(1, 0.5 + flicker * 0.3, 0, 0.8)
                love.graphics.circle("fill", px, py, visual.size + flicker * 2)
                love.graphics.setColor(1, 0.8, 0.2, 0.6)
                love.graphics.circle("fill", px, py, visual.size * 0.6)
            elseif visual.shape == "spray" then
                -- Chemical spray effect
                for i = 1, 3 do
                    local offset_x = (math.random() - 0.5) * 6
                    local offset_y = (math.random() - 0.5) * 6
                    love.graphics.circle("fill", px + offset_x, py + offset_y, visual.size * 0.5)
                end
            elseif visual.shape == "line" then
                -- Laser line from source
                local source = self.world:get_entity(proj.source)
                if source and source:has("transform") then
                    local st = source:get("transform")
                    local sx = st.x / Constants.PIXEL_LEPTON_W
                    local sy = st.y / Constants.PIXEL_LEPTON_H
                    love.graphics.setLineWidth(2)
                    love.graphics.line(sx, sy, px, py)
                    love.graphics.setLineWidth(1)
                end
            elseif visual.shape == "beam" then
                -- Ion cannon beam
                love.graphics.setLineWidth(4)
                love.graphics.line(px, 0, px, py)
                love.graphics.setLineWidth(1)
            else
                love.graphics.circle("fill", px, py, visual.size)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return CombatSystem
