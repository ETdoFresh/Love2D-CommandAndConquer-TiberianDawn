--[[
    Special Weapons System - Super weapons (Ion Cannon, Nukes, Airstrikes)
    Handles targeting, cooldowns, and effects
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")
local System = require("src.ecs.system")

local SpecialWeapons = setmetatable({}, {__index = System})
SpecialWeapons.__index = SpecialWeapons

-- Weapon types
SpecialWeapons.TYPE = {
    ION_CANNON = 1,
    NUCLEAR_STRIKE = 2,
    AIRSTRIKE = 3,
    NAPALM_STRIKE = 4
}

-- Weapon data
SpecialWeapons.DATA = {
    [1] = {  -- Ion Cannon
        name = "Ion Cannon",
        cooldown = 600,           -- 10 minutes at 60 FPS
        damage = 600,
        radius = 3,
        requires = "EYE",         -- Advanced Comm Center
        house = Constants.HOUSE.GOOD,
        effect = "ion_beam"
    },
    [2] = {  -- Nuclear Strike
        name = "Nuclear Strike",
        cooldown = 900,           -- 15 minutes
        damage = 1000,
        splash_damage = 500,
        radius = 5,
        requires = "TMPL",        -- Temple of Nod
        house = Constants.HOUSE.BAD,
        effect = "nuke"
    },
    [3] = {  -- Airstrike
        name = "A-10 Airstrike",
        cooldown = 300,           -- 5 minutes
        damage = 150,
        radius = 2,
        requires = "HQ",          -- Comm Center
        house = Constants.HOUSE.GOOD,
        effect = "airstrike"
    },
    [4] = {  -- Napalm
        name = "Napalm Strike",
        cooldown = 300,           -- 5 minutes
        damage = 200,
        radius = 3,
        requires = "HQ",
        house = Constants.HOUSE.BAD,
        effect = "napalm"
    }
}

function SpecialWeapons.new(world, combat_system)
    local self = setmetatable(System.new(), SpecialWeapons)

    self.name = "SpecialWeapons"
    self.world = world
    self.combat_system = combat_system

    -- Available weapons per house
    -- weapons[house][type] = {available, cooldown_remaining, one_time}
    self.weapons = {}

    -- Currently targeting weapon
    self.targeting = nil
    self.targeting_house = nil

    -- Active effects (for animation)
    self.active_effects = {}

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function SpecialWeapons:register_events()
    Events.on("ADD_SPECIAL", function(house, weapon_type, repeating)
        self:add_weapon(house, weapon_type, repeating)
    end)

    Events.on("LAUNCH_NUKES", function(house)
        -- Auto-target and launch all available nukes
        self:auto_launch(house, SpecialWeapons.TYPE.NUCLEAR_STRIKE)
    end)
end

-- Add a special weapon to a house
function SpecialWeapons:add_weapon(house, weapon_type, repeating)
    if not self.weapons[house] then
        self.weapons[house] = {}
    end

    self.weapons[house][weapon_type] = {
        available = true,
        cooldown = 0,
        one_time = not repeating
    }
end

-- Check if house has required building for weapon
function SpecialWeapons:has_requirement(house, weapon_type)
    local data = SpecialWeapons.DATA[weapon_type]
    if not data or not data.requires then
        return true
    end

    -- Check for required building
    local buildings = self.world:get_entities_with_tag("building")
    for _, entity in ipairs(buildings) do
        local owner = entity:get("owner")
        local building = entity:get("building")

        if owner and building and owner.house == house then
            if building.building_type == data.requires then
                return true
            end
        end
    end

    return false
end

-- Check if weapon is ready to fire
function SpecialWeapons:is_ready(house, weapon_type)
    if not self.weapons[house] then return false end

    local weapon = self.weapons[house][weapon_type]
    if not weapon then return false end

    return weapon.available and weapon.cooldown <= 0 and
           self:has_requirement(house, weapon_type)
end

-- Get cooldown remaining
function SpecialWeapons:get_cooldown(house, weapon_type)
    if not self.weapons[house] then return 0 end

    local weapon = self.weapons[house][weapon_type]
    if not weapon then return 0 end

    return weapon.cooldown
end

-- Start targeting mode
function SpecialWeapons:start_targeting(house, weapon_type)
    if not self:is_ready(house, weapon_type) then
        return false
    end

    self.targeting = weapon_type
    self.targeting_house = house

    Events.emit("SPECIAL_WEAPON_TARGETING", weapon_type)
    return true
end

-- Cancel targeting
function SpecialWeapons:cancel_targeting()
    self.targeting = nil
    self.targeting_house = nil
    Events.emit("SPECIAL_WEAPON_CANCELLED")
end

-- Fire weapon at target
function SpecialWeapons:fire(house, weapon_type, target_x, target_y)
    if not self:is_ready(house, weapon_type) then
        return false
    end

    local data = SpecialWeapons.DATA[weapon_type]
    local weapon = self.weapons[house][weapon_type]

    -- Create effect
    local effect = {
        type = weapon_type,
        effect = data.effect,
        target_x = target_x,
        target_y = target_y,
        damage = data.damage,
        splash_damage = data.splash_damage,
        radius = data.radius,
        time = 0,
        duration = 2,  -- seconds
        phase = "charging"
    }

    table.insert(self.active_effects, effect)

    -- Set cooldown
    if weapon.one_time then
        weapon.available = false
    else
        weapon.cooldown = data.cooldown
    end

    -- Cancel targeting
    self.targeting = nil
    self.targeting_house = nil

    -- Play sound/EVA
    Events.emit("PLAY_SPEECH", data.name .. " ready")
    Events.emit("SPECIAL_WEAPON_FIRED", weapon_type, target_x, target_y)

    return true
end

-- Auto-launch at best target (for AI/triggers)
function SpecialWeapons:auto_launch(house, weapon_type)
    if not self:is_ready(house, weapon_type) then
        return false
    end

    -- Find best target (highest value enemy concentration)
    local best_x, best_y = self:find_best_target(house)

    if best_x then
        return self:fire(house, weapon_type, best_x, best_y)
    end

    return false
end

-- Find best target for super weapon
function SpecialWeapons:find_best_target(house)
    local best_value = 0
    local best_x, best_y = nil, nil

    -- Score each cell based on enemy units/buildings nearby
    local entities = self.world:get_all_entities()
    local targets = {}

    for _, entity in ipairs(entities) do
        local owner = entity:get("owner")
        local transform = entity:get("transform")

        if owner and transform and owner.house ~= house then
            local cell_x = math.floor(transform.x / Constants.LEPTON_PER_CELL)
            local cell_y = math.floor(transform.y / Constants.LEPTON_PER_CELL)

            local value = 10
            if entity:has_tag("building") then
                value = 50
            end

            local key = cell_x .. "," .. cell_y
            targets[key] = (targets[key] or 0) + value
        end
    end

    for key, value in pairs(targets) do
        if value > best_value then
            best_value = value
            local x, y = key:match("(%d+),(%d+)")
            best_x = tonumber(x) * Constants.LEPTON_PER_CELL
            best_y = tonumber(y) * Constants.LEPTON_PER_CELL
        end
    end

    return best_x, best_y
end

-- Update special weapons
function SpecialWeapons:update(dt)
    -- Update cooldowns
    for house, house_weapons in pairs(self.weapons) do
        for weapon_type, weapon in pairs(house_weapons) do
            if weapon.cooldown > 0 then
                local was_charging = weapon.cooldown > 0
                weapon.cooldown = weapon.cooldown - dt * 60  -- Convert to frames

                -- Check if weapon just became ready
                if was_charging and weapon.cooldown <= 0 and weapon.available then
                    weapon.cooldown = 0  -- Clamp
                    -- Emit ready event for EVA announcement
                    local type_name = "ion_cannon"
                    if weapon_type == SpecialWeapons.TYPE.NUCLEAR_STRIKE then
                        type_name = "nuclear"
                    elseif weapon_type == SpecialWeapons.TYPE.AIRSTRIKE then
                        type_name = "airstrike"
                    elseif weapon_type == SpecialWeapons.TYPE.NAPALM_STRIKE then
                        type_name = "napalm"
                    end
                    Events.emit("SPECIAL_WEAPON_READY", house, type_name)
                end
            end
        end
    end

    -- Update active effects
    self:update_effects(dt)
end

-- Update active weapon effects
function SpecialWeapons:update_effects(dt)
    local i = 1
    while i <= #self.active_effects do
        local effect = self.active_effects[i]
        effect.time = effect.time + dt

        if effect.phase == "charging" then
            -- Charge up phase (visual only)
            if effect.time >= 0.5 then
                effect.phase = "firing"
                effect.time = 0
            end

        elseif effect.phase == "firing" then
            -- Main damage phase
            if effect.time >= 0.1 then
                self:apply_damage(effect)
                effect.phase = "aftermath"
                effect.time = 0
            end

        elseif effect.phase == "aftermath" then
            -- After effect (visual, fires, etc.)
            if effect.time >= effect.duration then
                table.remove(self.active_effects, i)
                i = i - 1
            end
        end

        i = i + 1
    end
end

-- Apply damage from effect
function SpecialWeapons:apply_damage(effect)
    local center_x = effect.target_x
    local center_y = effect.target_y
    local radius = effect.radius * Constants.LEPTON_PER_CELL

    -- Find all entities in radius
    local entities = self.world:get_all_entities()

    for _, entity in ipairs(entities) do
        local transform = entity:get("transform")
        local health = entity:get("health")

        if transform and health then
            local dx = transform.x - center_x
            local dy = transform.y - center_y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist <= radius then
                -- Calculate damage based on distance
                local damage_mult = 1 - (dist / radius)
                local damage = effect.damage * damage_mult

                if effect.splash_damage and dist > radius * 0.3 then
                    damage = effect.splash_damage * damage_mult
                end

                -- Apply damage
                if self.combat_system then
                    self.combat_system:apply_damage(entity, math.floor(damage))
                else
                    health.hp = health.hp - damage
                    if health.hp <= 0 then
                        entity.destroyed = true
                        Events.emit(Events.EVENTS.ENTITY_DESTROYED, entity)
                    end
                end
            end
        end
    end
end

-- Draw targeting cursor
function SpecialWeapons:draw_targeting(render_system, mouse_x, mouse_y)
    if not self.targeting then return end

    local data = SpecialWeapons.DATA[self.targeting]
    local world_x, world_y = render_system:screen_to_world(mouse_x, mouse_y)
    local radius = data.radius * Constants.CELL_PIXEL_W

    love.graphics.push()
    love.graphics.scale(render_system.scale, render_system.scale)
    love.graphics.translate(-render_system.camera_x, -render_system.camera_y)

    -- Animated pulse effect for radius
    local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 4)

    -- Draw damage falloff gradient (darker at edge = less damage)
    local segments = 16
    for i = segments, 1, -1 do
        local r = radius * (i / segments)
        local alpha = 0.15 * (i / segments)

        -- Color based on weapon type
        if self.targeting == SpecialWeapons.TYPE.ION_CANNON then
            love.graphics.setColor(0.2, 0.5, 1, alpha)
        elseif self.targeting == SpecialWeapons.TYPE.NUCLEAR_STRIKE then
            love.graphics.setColor(1, 0.3, 0, alpha)
        else
            love.graphics.setColor(1, 0.5, 0, alpha)
        end
        love.graphics.circle("fill", world_x, world_y, r)
    end

    -- Outer radius line (pulsing)
    local line_color
    if self.targeting == SpecialWeapons.TYPE.ION_CANNON then
        line_color = {0.5, 0.8, 1, pulse}
    elseif self.targeting == SpecialWeapons.TYPE.NUCLEAR_STRIKE then
        line_color = {1, 0.2, 0, pulse}
    else
        line_color = {1, 0.6, 0, pulse}
    end
    love.graphics.setColor(unpack(line_color))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", world_x, world_y, radius)
    love.graphics.setLineWidth(1)

    -- Inner kill zone indicator (high damage area)
    love.graphics.setColor(1, 1, 1, 0.4 * pulse)
    love.graphics.circle("line", world_x, world_y, radius * 0.3)

    -- Draw crosshair
    love.graphics.setColor(1, 1, 1, 1)
    local ch_size = 15
    love.graphics.setLineWidth(2)
    love.graphics.line(world_x - ch_size, world_y, world_x - 5, world_y)
    love.graphics.line(world_x + 5, world_y, world_x + ch_size, world_y)
    love.graphics.line(world_x, world_y - ch_size, world_x, world_y - 5)
    love.graphics.line(world_x, world_y + 5, world_x, world_y + ch_size)
    love.graphics.setLineWidth(1)

    -- Center dot
    love.graphics.circle("fill", world_x, world_y, 3)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()

    -- Draw weapon name and instructions (in screen space)
    love.graphics.setColor(1, 1, 1, 1)
    local font = love.graphics.getFont()
    local text = data.name .. " - Click to fire"
    local text_width = font:getWidth(text)
    love.graphics.print(text, mouse_x - text_width / 2, mouse_y + radius * render_system.scale + 20)

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local hint = "ESC to cancel"
    local hint_width = font:getWidth(hint)
    love.graphics.print(hint, mouse_x - hint_width / 2, mouse_y + radius * render_system.scale + 35)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw active effects
function SpecialWeapons:draw_effects(render_system)
    for _, effect in ipairs(self.active_effects) do
        self:draw_effect(effect, render_system)
    end
end

-- Draw single effect
function SpecialWeapons:draw_effect(effect, render_system)
    love.graphics.push()
    love.graphics.scale(render_system.scale, render_system.scale)
    love.graphics.translate(-render_system.camera_x, -render_system.camera_y)

    local px = effect.target_x / Constants.PIXEL_LEPTON_W
    local py = effect.target_y / Constants.PIXEL_LEPTON_H
    local radius = effect.radius * Constants.CELL_PIXEL_W

    if effect.effect == "ion_beam" then
        -- Ion cannon beam effect
        if effect.phase == "charging" then
            local alpha = effect.time / 0.5
            love.graphics.setColor(0.2, 0.5, 1, alpha)
            love.graphics.circle("fill", px, py, 10)
        elseif effect.phase == "firing" then
            love.graphics.setColor(0.5, 0.8, 1, 1)
            love.graphics.circle("fill", px, py, radius)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("fill", px, py, radius * 0.5)
        else
            local alpha = 1 - effect.time / effect.duration
            love.graphics.setColor(0.5, 0.8, 1, alpha)
            love.graphics.circle("fill", px, py, radius * (1 + effect.time))
        end

    elseif effect.effect == "nuke" then
        -- Nuclear explosion
        if effect.phase == "charging" then
            -- Incoming missile visual
            local alpha = effect.time / 0.5
            love.graphics.setColor(1, 0.5, 0, alpha)
            love.graphics.circle("fill", px, py - 50 * (1 - alpha), 5)
        elseif effect.phase == "firing" then
            -- Initial flash
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("fill", px, py, radius)
        else
            -- Mushroom cloud
            local alpha = 1 - effect.time / effect.duration
            local expand = 1 + effect.time * 0.5
            love.graphics.setColor(1, 0.3, 0, alpha)
            love.graphics.circle("fill", px, py, radius * expand)
            love.graphics.setColor(0.5, 0.2, 0, alpha)
            love.graphics.circle("fill", px, py - effect.time * 30, radius * expand * 0.6)
        end

    elseif effect.effect == "airstrike" or effect.effect == "napalm" then
        -- Airstrike/napalm
        if effect.phase == "firing" then
            love.graphics.setColor(1, 0.5, 0, 1)
            love.graphics.circle("fill", px, py, radius)
        else
            local alpha = 1 - effect.time / effect.duration
            love.graphics.setColor(1, 0.3, 0, alpha)
            love.graphics.circle("fill", px, py, radius * 1.5)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Get available weapons for a house
function SpecialWeapons:get_available_weapons(house)
    local result = {}

    if self.weapons[house] then
        for weapon_type, weapon in pairs(self.weapons[house]) do
            if weapon.available then
                local data = SpecialWeapons.DATA[weapon_type]
                table.insert(result, {
                    type = weapon_type,
                    name = data.name,
                    ready = weapon.cooldown <= 0 and self:has_requirement(house, weapon_type),
                    cooldown = math.max(0, weapon.cooldown),
                    max_cooldown = data.cooldown
                })
            end
        end
    end

    return result
end

return SpecialWeapons
