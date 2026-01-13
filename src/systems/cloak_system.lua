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

    for _, other in ipairs(entities) do
        if other ~= entity then
            local other_owner = other:get("owner")
            local other_transform = other:get("transform")

            if other_owner and other_transform and other_owner.house ~= owner.house then
                -- Check if this unit can detect cloaked units
                if self:can_detect_cloak(other) then
                    -- Get detection range for this specific detector
                    local detection_range = self:get_detection_range(other)

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
-- Reference: BDATA.CPP - Buildings have "Can Detect Adjacent Cloaked Objects" flag
function CloakSystem:can_detect_cloak(entity)
    -- Buildings with cloak detection (from original BDATA.CPP)
    local building = entity:get("building")
    if building then
        local btype = building.building_type
        -- Original C&C buildings with cloak detection:
        -- HQ (Command Center/Radar), GTWR (Guard Tower), ATWR (Advanced Guard Tower)
        -- OBLI (Obelisk of Light), GUN (Gun Turret), MISS (Mission Temple)
        if btype == "HQ" or btype == "RADAR" or      -- Command Center
           btype == "GTWR" or btype == "GUARD" or    -- Guard Tower
           btype == "ATWR" or btype == "AGTWR" or    -- Advanced Guard Tower
           btype == "OBLI" or btype == "OBELISK" or  -- Obelisk of Light
           btype == "GUN" or btype == "TURRET" or    -- Gun Turret
           btype == "EYE" or                          -- Advanced Comm Center (Nod Eye)
           btype == "TMPL" then                       -- Temple of Nod (has detection)
            return true
        end
    end

    -- No vehicles have inherent cloak detection in original C&C
    -- Detection is purely building-based with "adjacent" range
    -- Units only see cloaked enemies if they're near a detecting building
    -- However, for gameplay purposes we allow these radar-equipped vehicles:
    local vehicle = entity:get("vehicle")
    if vehicle then
        local vtype = vehicle.vehicle_type
        -- These are not in original but enhance gameplay:
        -- (Remove if strict accuracy to original is required)
        if vtype == "APC" or      -- Armored Personnel Carrier has radar
           vtype == "MLRS" or     -- Multiple Launch Rocket System
           vtype == "MSAM" then   -- Mobile SAM
            return true
        end
    end

    -- Infantry cannot detect cloaked units (original behavior)
    -- Only radar-equipped buildings (and optionally vehicles) can see them

    return false
end

-- Get detection range for an entity (in leptons)
-- Original C&C used "adjacent" which means neighboring cells
function CloakSystem:get_detection_range(entity)
    local base_range = 3 * Constants.LEPTON_PER_CELL  -- 3 cells default

    -- Buildings may have different detection ranges
    local building = entity:get("building")
    if building then
        local btype = building.building_type
        -- Command Center and Eye have larger detection radius
        if btype == "HQ" or btype == "RADAR" or btype == "EYE" then
            return 5 * Constants.LEPTON_PER_CELL  -- 5 cells
        end
        -- Guard towers have shorter range
        if btype == "GTWR" or btype == "GUARD" or btype == "GUN" then
            return 2 * Constants.LEPTON_PER_CELL  -- 2 cells (adjacent)
        end
        -- Obelisk has medium range
        if btype == "OBLI" or btype == "OBELISK" then
            return 4 * Constants.LEPTON_PER_CELL  -- 4 cells
        end
    end

    return base_range
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

-- Get shimmer effect parameters for rendering
-- Returns: shimmer_enabled, offset_x, offset_y, color_shift
function CloakSystem:get_shimmer_effect(entity)
    local cloak = entity:get("cloak")
    if not cloak then
        return false, 0, 0, 0
    end

    -- Only shimmer when partially cloaked or transitioning
    local shimmer_enabled = cloak.state == CloakSystem.STATE.CLOAKED or
                            cloak.state == CloakSystem.STATE.CLOAKING or
                            cloak.state == CloakSystem.STATE.UNCLOAKING

    if not shimmer_enabled then
        return false, 0, 0, 0
    end

    -- Time-based shimmer animation
    local time = love.timer.getTime()

    -- Multi-frequency shimmer for more natural effect
    local shimmer_x = math.sin(time * 12 + entity.id * 0.7) * 1.5 +
                      math.sin(time * 7 + entity.id * 1.3) * 0.8
    local shimmer_y = math.cos(time * 10 + entity.id * 0.9) * 1.2 +
                      math.cos(time * 5 + entity.id * 1.1) * 0.5

    -- Color shift (subtle blue/cyan tint for cloaking effect)
    local color_shift = math.sin(time * 8 + entity.id) * 0.15 + 0.1

    -- Scale shimmer based on cloak state
    local intensity = 1.0
    if cloak.state == CloakSystem.STATE.CLOAKING then
        intensity = cloak.progress  -- Increases as it cloaks
    elseif cloak.state == CloakSystem.STATE.UNCLOAKING then
        intensity = 1 - cloak.progress  -- Decreases as it uncloaks
    end

    return true, shimmer_x * intensity, shimmer_y * intensity, color_shift * intensity
end

-- Get cloak render info (combined alpha and shimmer)
-- Returns a table with all rendering parameters
function CloakSystem:get_render_info(entity, viewer_house)
    local info = {
        alpha = self:get_cloak_alpha(entity, viewer_house),
        shimmer_enabled = false,
        shimmer_x = 0,
        shimmer_y = 0,
        color_tint = {1, 1, 1}  -- RGB tint
    }

    local shimmer_enabled, sx, sy, color_shift = self:get_shimmer_effect(entity)
    info.shimmer_enabled = shimmer_enabled
    info.shimmer_x = sx
    info.shimmer_y = sy

    -- Apply blue/cyan tint when shimmering
    if shimmer_enabled and color_shift > 0 then
        info.color_tint = {
            1 - color_shift * 0.3,   -- Slightly reduce red
            1 - color_shift * 0.1,   -- Slightly reduce green
            1 + color_shift * 0.2    -- Boost blue (capped at 1 by renderer)
        }
    end

    return info
end

-- Draw shimmer outline effect (called by render system)
-- This creates the classic "heat wave" distortion look
function CloakSystem:draw_shimmer_outline(x, y, width, height, entity)
    local shimmer_enabled, sx, sy, color_shift = self:get_shimmer_effect(entity)
    if not shimmer_enabled then return end

    local cloak = entity:get("cloak")
    if not cloak then return end

    -- Only draw outline for partially visible cloaked units
    local alpha = 0.3
    if cloak.state == CloakSystem.STATE.CLOAKING then
        alpha = 0.4 * cloak.progress
    elseif cloak.state == CloakSystem.STATE.UNCLOAKING then
        alpha = 0.4 * (1 - cloak.progress)
    elseif cloak.state == CloakSystem.STATE.CLOAKED then
        alpha = 0.2
    end

    if alpha <= 0 then return end

    -- Draw wavering outline
    love.graphics.setColor(0.3, 0.8, 1.0, alpha)
    love.graphics.setLineWidth(1)

    -- Create wavy outline using multiple points
    local segments = 16
    local points = {}
    local time = love.timer.getTime()

    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2
        local wave_offset = math.sin(time * 8 + angle * 3) * 2

        -- Calculate point on ellipse with wave
        local px = x + width/2 + (math.cos(angle) * (width/2 + wave_offset))
        local py = y + height/2 + (math.sin(angle) * (height/2 + wave_offset))

        table.insert(points, px)
        table.insert(points, py)
    end

    if #points >= 4 then
        love.graphics.polygon("line", points)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return CloakSystem
