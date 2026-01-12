--[[
    Animation System - Updates entity animation frames based on state
    Handles frame timing, state transitions, and direction-based frame selection
]]

local System = require("src.ecs.system")
local AnimationData = require("src.data.animation_data")

local AnimationSystem = setmetatable({}, {__index = System})
AnimationSystem.__index = AnimationSystem

function AnimationSystem.new()
    local self = System.new("animation", {"renderable"})
    setmetatable(self, AnimationSystem)
    return self
end

function AnimationSystem:init()
    -- Nothing to initialize
end

function AnimationSystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:update_entity(entity)
    end

    -- Update death effect animations
    self:update_death_effects()

    -- Clean up expired effects
    self:cleanup_effects()
end

-- Update death effect animations (infantry death sequences, explosions)
function AnimationSystem:update_death_effects()
    local effects = self.world:get_entities_with_tag("death_effect")

    for _, effect in ipairs(effects) do
        if effect:has("animation") and effect:has("renderable") then
            local animation = effect:get("animation")
            local renderable = effect:get("renderable")
            local transform = effect:has("transform") and effect:get("transform") or nil

            -- Determine which death animation to play
            local death_state = self:get_death_state_from_type(animation.death_type)

            -- Get infantry type for frame lookup
            local infantry_type = effect.infantry_type or "E1"

            -- Get animation data
            local sprite_name = infantry_type:upper()
            local anim_data = AnimationData[sprite_name]
            if anim_data and anim_data[death_state] then
                local data = anim_data[death_state]
                local frame_offset = data[1] or 0
                local frame_count = data[2] or 1
                local frame_rate = data[3] or 2

                -- Initialize animation frame tracking
                if not renderable.anim_frame then
                    renderable.anim_frame = 0
                end
                if not renderable.anim_timer then
                    renderable.anim_timer = 0
                end

                -- Advance animation
                if frame_rate > 0 then
                    renderable.anim_timer = renderable.anim_timer + 1
                    if renderable.anim_timer >= frame_rate then
                        renderable.anim_timer = 0
                        if renderable.anim_frame < frame_count - 1 then
                            renderable.anim_frame = renderable.anim_frame + 1
                        end
                        -- Hold on last frame (non-looping)
                    end
                end

                -- Calculate final frame
                renderable.frame = frame_offset + renderable.anim_frame
            else
                -- Fallback for non-infantry explosions - just use a simple frame counter
                if not renderable.anim_frame then
                    renderable.anim_frame = 0
                end
                if not renderable.anim_timer then
                    renderable.anim_timer = 0
                end

                renderable.anim_timer = renderable.anim_timer + 1
                if renderable.anim_timer >= 2 then
                    renderable.anim_timer = 0
                    renderable.anim_frame = renderable.anim_frame + 1
                end

                renderable.frame = renderable.anim_frame
            end
        end
    end
end

-- Map death type string to AnimationData.DO constant
function AnimationSystem:get_death_state_from_type(death_type)
    local mapping = {
        gun = AnimationData.DO.GUN_DEATH,
        explosion = AnimationData.DO.EXPLOSION_DEATH,
        explosion2 = AnimationData.DO.EXPLOSION2_DEATH,
        grenade = AnimationData.DO.GRENADE_DEATH,
        fire = AnimationData.DO.FIRE_DEATH,
        punch = AnimationData.DO.PUNCH_DEATH,
        kick = AnimationData.DO.KICK_DEATH
    }
    return mapping[death_type] or AnimationData.DO.GUN_DEATH
end

-- Clean up death effects and other temporary animations
function AnimationSystem:cleanup_effects()
    local effects = self.world:get_entities_with_tag("death_effect")

    for _, effect in ipairs(effects) do
        if effect.effect_lifetime then
            effect.effect_timer = (effect.effect_timer or 0) + 1

            if effect.effect_timer >= effect.effect_lifetime then
                self.world:destroy_entity(effect)
            end
        end
    end
end

function AnimationSystem:update_entity(entity)
    local renderable = entity:get("renderable")

    -- Initialize animation state if not present
    if not renderable.anim_state then
        renderable.anim_state = AnimationData.DO.STAND_READY
    end
    if not renderable.anim_timer then
        renderable.anim_timer = 0
    end
    if not renderable.anim_frame then
        renderable.anim_frame = 0
    end

    -- Determine animation based on entity type
    if entity:has("infantry") then
        self:update_infantry(entity)
    elseif entity:has("mobile") then
        self:update_vehicle(entity)
    elseif entity:has("building") then
        self:update_building(entity)
    end
end

function AnimationSystem:update_infantry(entity)
    local renderable = entity:get("renderable")
    local transform = entity:get("transform")
    local infantry = entity:get("infantry")
    local mobile = entity:has("mobile") and entity:get("mobile") or nil

    -- Get sprite name (e.g., "e1")
    local sprite_name = renderable.sprite
    if not sprite_name or type(sprite_name) ~= "string" then return end

    -- Determine animation state based on unit behavior
    local new_state = self:determine_infantry_state(entity)

    -- Check for state change
    if new_state ~= renderable.anim_state then
        renderable.anim_state = new_state
        renderable.anim_frame = 0
        renderable.anim_timer = 0
    end

    -- Get animation rate
    local rate = AnimationData.get_infantry_rate(sprite_name, renderable.anim_state)

    -- Advance animation timer
    if rate > 0 then
        renderable.anim_timer = renderable.anim_timer + 1

        if renderable.anim_timer >= rate then
            renderable.anim_timer = 0
            renderable.anim_frame = renderable.anim_frame + 1

            -- Check for animation end (looping or one-shot)
            local frame_count = AnimationData.get_infantry_frame_count(sprite_name, renderable.anim_state)
            if renderable.anim_frame >= frame_count then
                -- Check if this is a death animation (non-looping)
                if self:is_death_animation(renderable.anim_state) then
                    renderable.anim_frame = frame_count - 1  -- Hold last frame
                else
                    renderable.anim_frame = 0  -- Loop
                end
            end
        end
    end

    -- Get facing direction (0-31)
    local facing = transform.facing or 0

    -- Calculate final frame
    renderable.frame = AnimationData.get_infantry_frame(
        sprite_name,
        renderable.anim_state,
        facing,
        renderable.anim_frame
    )
end

function AnimationSystem:determine_infantry_state(entity)
    local mobile = entity:has("mobile") and entity:get("mobile") or nil
    local health = entity:has("health") and entity:get("health") or nil
    local combat = entity:has("combat") and entity:get("combat") or nil

    -- Check if dead
    if health and health.hp <= 0 then
        return AnimationData.DO.GUN_DEATH
    end

    -- Check if firing
    if combat and combat.firing then
        return AnimationData.DO.FIRE_WEAPON
    end

    -- Check if moving (mobile.is_moving is set by movement system)
    if mobile and mobile.is_moving then
        return AnimationData.DO.WALK
    end

    -- Default to standing
    return AnimationData.DO.STAND_READY
end

function AnimationSystem:is_death_animation(state)
    return state == AnimationData.DO.GUN_DEATH or
           state == AnimationData.DO.EXPLOSION_DEATH or
           state == AnimationData.DO.EXPLOSION2_DEATH or
           state == AnimationData.DO.GRENADE_DEATH or
           state == AnimationData.DO.FIRE_DEATH or
           state == AnimationData.DO.PUNCH_DEATH or
           state == AnimationData.DO.KICK_DEATH or
           state == AnimationData.DO.PLEAD_DEATH
end

function AnimationSystem:update_vehicle(entity)
    local renderable = entity:get("renderable")
    local transform = entity:get("transform")
    local mobile = entity:get("mobile")

    -- Get sprite name
    local sprite_name = renderable.sprite
    if not sprite_name or type(sprite_name) ~= "string" then return end

    -- Get facing direction (0-31 for vehicles)
    local facing = transform.facing_full or transform.facing or 0

    -- Calculate frame from facing
    renderable.frame = AnimationData.get_vehicle_frame(sprite_name, facing)

    -- Handle turret separately if entity has turret component
    if entity:has("turret") then
        local turret = entity:get("turret")
        local turret_facing = turret.facing or 0

        -- Get turret frame from animation data
        local turret_frame = AnimationData.get_turret_frame(sprite_name, turret_facing)
        if turret_frame then
            renderable.turret_frame = turret_frame
            renderable.has_turret = true
        else
            renderable.has_turret = false
        end
    else
        renderable.has_turret = false
    end
end

function AnimationSystem:update_building(entity)
    local renderable = entity:get("renderable")
    local building = entity:get("building")

    -- Get sprite name
    local sprite_name = renderable.sprite
    if not sprite_name or type(sprite_name) ~= "string" then return end

    -- Get building animation data
    local data = AnimationData.BUILDINGS[sprite_name:lower()]
    if not data then return end

    -- Buildings have different animation behaviors:
    -- - Production buildings animate when producing
    -- - Power plants have constant animation
    -- - Turrets/SAM rotate toward targets

    if data.anim_rate > 0 then
        -- Initialize timer
        if not renderable.anim_timer then
            renderable.anim_timer = 0
        end

        -- Check if building is active (producing, powered, etc.)
        local is_active = true
        if entity:has("power") then
            local power = entity:get("power")
            is_active = not power.low_power
        end

        if is_active then
            renderable.anim_timer = renderable.anim_timer + 1

            if renderable.anim_timer >= data.anim_rate then
                renderable.anim_timer = 0
                renderable.frame = (renderable.frame + 1) % data.frames
            end
        end
    end
end

return AnimationSystem
