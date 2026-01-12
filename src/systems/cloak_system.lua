--[[
    Cloak System - Stealth/cloaking for units
    Handles Stealth Tank and other invisible units
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")
local System = require("src.ecs.system")

local CloakSystem = setmetatable({}, {__index = System})
CloakSystem.__index = CloakSystem

-- Cloak states
CloakSystem.STATE = {
    UNCLOAKED = 0,
    CLOAKING = 1,
    CLOAKED = 2,
    UNCLOAKING = 3
}

function CloakSystem.new()
    local self = setmetatable(System.new(), CloakSystem)

    self.name = "CloakSystem"

    -- Cloak timing (in seconds)
    self.cloak_delay = 3.0        -- Time before cloaking starts
    self.cloak_duration = 1.0     -- Time to fully cloak
    self.uncloak_duration = 0.5   -- Time to fully uncloak

    -- Units that can cloak
    self.cloakable_types = {
        STNK = true   -- Stealth Tank
    }

    return self
end

-- Check if entity can cloak
function CloakSystem:can_cloak(entity)
    local vehicle = entity:get("vehicle")
    if vehicle and self.cloakable_types[vehicle.vehicle_type] then
        return true
    end
    return false
end

-- Initialize cloak component for entity
function CloakSystem:init_cloak(entity)
    if not entity:has("cloak") then
        entity:add("cloak", {
            state = CloakSystem.STATE.UNCLOAKED,
            timer = 0,
            progress = 0,    -- 0 = uncloaked, 1 = cloaked
            detected = false
        })
    end
end

-- Update cloak system
function CloakSystem:update(dt)
    local entities = self.world:get_entities_with("cloak")

    for _, entity in ipairs(entities) do
        self:update_entity(entity, dt)
    end

    -- Check cloakable units that need cloak component
    local all_entities = self.world:get_all_entities()
    for _, entity in ipairs(all_entities) do
        if self:can_cloak(entity) and not entity:has("cloak") then
            self:init_cloak(entity)
        end
    end
end

-- Update single entity's cloak
function CloakSystem:update_entity(entity, dt)
    local cloak = entity:get("cloak")
    if not cloak then return end

    -- Check if entity is doing something that prevents cloaking
    local is_active = self:is_entity_active(entity)

    if cloak.state == CloakSystem.STATE.UNCLOAKED then
        if not is_active then
            -- Start cloak delay
            cloak.timer = cloak.timer + dt
            if cloak.timer >= self.cloak_delay then
                cloak.state = CloakSystem.STATE.CLOAKING
                cloak.timer = 0
            end
        else
            cloak.timer = 0
        end

    elseif cloak.state == CloakSystem.STATE.CLOAKING then
        if is_active then
            -- Activity interrupts cloaking
            cloak.state = CloakSystem.STATE.UNCLOAKING
            cloak.timer = cloak.progress * self.uncloak_duration
        else
            cloak.timer = cloak.timer + dt
            cloak.progress = math.min(1, cloak.timer / self.cloak_duration)

            if cloak.progress >= 1 then
                cloak.state = CloakSystem.STATE.CLOAKED
                cloak.progress = 1
                Events.emit("UNIT_CLOAKED", entity)
            end
        end

    elseif cloak.state == CloakSystem.STATE.CLOAKED then
        if is_active then
            -- Activity breaks cloak
            cloak.state = CloakSystem.STATE.UNCLOAKING
            cloak.timer = 0
        end

        -- Check for detection
        cloak.detected = self:check_detection(entity)

    elseif cloak.state == CloakSystem.STATE.UNCLOAKING then
        cloak.timer = cloak.timer + dt
        cloak.progress = 1 - math.min(1, cloak.timer / self.uncloak_duration)

        if cloak.progress <= 0 then
            cloak.state = CloakSystem.STATE.UNCLOAKED
            cloak.progress = 0
            cloak.timer = 0
            cloak.detected = false
            Events.emit("UNIT_UNCLOAKED", entity)
        end
    end
end

-- Check if entity is doing something (moving, firing)
function CloakSystem:is_entity_active(entity)
    local mobile = entity:get("mobile")
    if mobile and mobile.moving then
        return true
    end

    local combat = entity:get("combat")
    if combat and combat.firing then
        return true
    end

    return false
end

-- Check if cloaked unit is detected by enemy
function CloakSystem:check_detection(entity)
    local transform = entity:get("transform")
    local owner = entity:get("owner")
    if not transform or not owner then return false end

    -- Check for nearby enemy units/buildings that can detect
    local entities = self.world:get_all_entities()
    local detection_range = 3 * Constants.LEPTON_PER_CELL  -- 3 cells

    for _, other in ipairs(entities) do
        if other ~= entity then
            local other_owner = other:get("owner")
            local other_transform = other:get("transform")

            if other_owner and other_transform and other_owner.house ~= owner.house then
                -- Check if this unit can detect cloaked units
                if self:can_detect_cloak(other) then
                    local dx = transform.x - other_transform.x
                    local dy = transform.y - other_transform.y
                    local dist = math.sqrt(dx * dx + dy * dy)

                    if dist <= detection_range then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Check if entity can detect cloaked units
function CloakSystem:can_detect_cloak(entity)
    -- Buildings with radar can detect
    local building = entity:get("building")
    if building then
        if building.building_type == "HQ" or
           building.building_type == "EYE" or
           building.building_type == "SAM" then
            return true
        end
    end

    -- Vehicles with radar can detect (APC, MLRS)
    local vehicle = entity:get("vehicle")
    if vehicle then
        if vehicle.vehicle_type == "APC" or
           vehicle.vehicle_type == "MLRS" or
           vehicle.vehicle_type == "MSAM" then
            return true
        end
    end

    -- Infantry cannot detect cloaked units (original behavior)
    -- Only radar-equipped units can see them

    return false
end

-- Force entity to uncloak (called when taking damage or firing)
function CloakSystem:force_uncloak(entity)
    local cloak = entity:get("cloak")
    if not cloak then return end

    if cloak.state == CloakSystem.STATE.CLOAKED or
       cloak.state == CloakSystem.STATE.CLOAKING then
        cloak.state = CloakSystem.STATE.UNCLOAKING
        cloak.timer = 0
        cloak.detected = false
        Events.emit("UNIT_UNCLOAKED", entity)
    end
end

-- Register for damage events to break cloak
function CloakSystem:init()
    -- Listen for damage events to break cloak
    Events.on(Events.EVENTS.ENTITY_DAMAGED, function(target, damage, attacker)
        if target:has("cloak") then
            self:force_uncloak(target)
        end
    end)

    -- Listen for combat firing events to break cloak
    Events.on("WEAPON_FIRED", function(attacker, target, weapon)
        if attacker:has("cloak") then
            self:force_uncloak(attacker)
        end
    end)
end

-- Check if entity is visible (for rendering/targeting)
function CloakSystem:is_visible(entity, viewer_house)
    local cloak = entity:get("cloak")
    if not cloak then return true end

    local owner = entity:get("owner")
    if owner and owner.house == viewer_house then
        -- Own units always visible
        return true
    end

    if cloak.state == CloakSystem.STATE.CLOAKED then
        return cloak.detected
    elseif cloak.state == CloakSystem.STATE.CLOAKING and cloak.progress > 0.5 then
        return cloak.detected
    end

    return true
end

-- Get cloak alpha for rendering
function CloakSystem:get_cloak_alpha(entity, viewer_house)
    local cloak = entity:get("cloak")
    if not cloak then return 1 end

    local owner = entity:get("owner")
    if owner and owner.house == viewer_house then
        -- Own units show with shimmer effect when cloaked
        if cloak.state == CloakSystem.STATE.CLOAKED then
            return 0.3
        elseif cloak.state == CloakSystem.STATE.CLOAKING then
            return 1 - cloak.progress * 0.7
        elseif cloak.state == CloakSystem.STATE.UNCLOAKING then
            return 0.3 + (1 - cloak.progress) * 0.7
        end
    else
        -- Enemy cloaked units
        if cloak.state == CloakSystem.STATE.CLOAKED then
            return cloak.detected and 0.2 or 0
        elseif cloak.state == CloakSystem.STATE.CLOAKING then
            return 1 - cloak.progress
        elseif cloak.state == CloakSystem.STATE.UNCLOAKING then
            return 1 - cloak.progress
        end
    end

    return 1
end

-- Force uncloak (for taking damage, etc.)
function CloakSystem:force_uncloak(entity)
    local cloak = entity:get("cloak")
    if cloak and cloak.state ~= CloakSystem.STATE.UNCLOAKED then
        cloak.state = CloakSystem.STATE.UNCLOAKING
        cloak.timer = 0
    end
end

return CloakSystem
