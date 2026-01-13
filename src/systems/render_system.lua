--[[
    Render System - Draws entities to screen
    Handles layered rendering and camera transformation
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local SpriteLoader = require("src.graphics.sprite_loader")

local RenderSystem = setmetatable({}, {__index = System})
RenderSystem.__index = RenderSystem

function RenderSystem.new()
    local self = System.new("render", {"transform", "renderable"})
    setmetatable(self, RenderSystem)

    -- Camera/viewport settings
    self.camera_x = 0
    self.camera_y = 0
    self.scale = 1
    self.use_hd = false

    -- Viewport bounds (in cells)
    self.view_x = 0
    self.view_y = 0
    self.view_width = 0
    self.view_height = 0

    -- Render layers
    self.layers = {
        [Constants.LAYER.GROUND] = {},
        [Constants.LAYER.AIR] = {},
        [Constants.LAYER.TOP] = {}
    }

    -- Reference to fog system for visibility checks
    self.fog_system = nil

    -- Reference to cloak system for stealth effects
    self.cloak_system = nil

    -- Viewer house (for cloaking visibility)
    self.viewer_house = nil

    return self
end

-- Set fog system reference for visibility filtering
function RenderSystem:set_fog_system(fog_system)
    self.fog_system = fog_system
end

-- Set cloak system reference for stealth rendering
function RenderSystem:set_cloak_system(cloak_system)
    self.cloak_system = cloak_system
end

-- Set viewer house (for cloak visibility determination)
function RenderSystem:set_viewer_house(house)
    self.viewer_house = house
end

function RenderSystem:init()
    -- Calculate initial viewport
    self:update_viewport()

    -- Get sprite loader instance
    self.sprite_loader = SpriteLoader.get_instance()

    -- Preload sprites (optional, can be done lazily)
    -- self.sprite_loader:preload_all()
end

function RenderSystem:update_viewport()
    local screen_w, screen_h = love.graphics.getDimensions()

    -- Calculate visible cells based on scale
    local cell_w = Constants.CELL_PIXEL_W * self.scale
    local cell_h = Constants.CELL_PIXEL_H * self.scale

    self.view_width = math.ceil(screen_w / cell_w) + 2
    self.view_height = math.ceil(screen_h / cell_h) + 2
end

function RenderSystem:set_camera(x, y)
    self.camera_x = x
    self.camera_y = y

    -- Update viewport cell bounds
    self.view_x = math.floor(x / (Constants.CELL_PIXEL_W * self.scale))
    self.view_y = math.floor(y / (Constants.CELL_PIXEL_H * self.scale))
end

function RenderSystem:set_scale(scale)
    self.scale = scale
    self:update_viewport()
end

function RenderSystem:set_hd_mode(use_hd)
    self.use_hd = use_hd
    -- TODO: Swap sprite sets
end

function RenderSystem:update(dt, entities)
    -- Clear layer lists
    for layer_id in pairs(self.layers) do
        self.layers[layer_id] = {}
    end

    -- Sort entities into layers (filter by fog visibility if enabled)
    for _, entity in ipairs(entities) do
        local renderable = entity:get("renderable")
        if renderable.visible then
            -- Check fog of war visibility for enemy units
            local should_render = true
            if self.fog_system and self.fog_system.fog_enabled then
                local owner = entity:get("owner")
                -- Only apply fog to enemy units (not your own units or effects)
                if owner and owner.house ~= self.fog_system.player_house then
                    should_render = self.fog_system:is_entity_visible(entity)
                end
            end

            if should_render then
                local layer = renderable.layer or Constants.LAYER.GROUND
                table.insert(self.layers[layer], entity)
            end
        end
    end

    -- Sort each layer by Y position (painter's algorithm)
    for layer_id, layer_entities in pairs(self.layers) do
        table.sort(layer_entities, function(a, b)
            local ta = a:get("transform")
            local tb = b:get("transform")
            return ta.y < tb.y
        end)
    end
end

function RenderSystem:draw(entities)
    love.graphics.push()

    -- Apply camera transform
    love.graphics.scale(self.scale, self.scale)
    love.graphics.translate(-self.camera_x, -self.camera_y)

    -- Draw each layer in order
    self:draw_layer(Constants.LAYER.GROUND)
    self:draw_layer(Constants.LAYER.AIR)
    self:draw_layer(Constants.LAYER.TOP)

    love.graphics.pop()
end

function RenderSystem:draw_layer(layer_id)
    local layer_entities = self.layers[layer_id] or {}

    for _, entity in ipairs(layer_entities) do
        self:draw_entity(entity)
    end
end

function RenderSystem:draw_entity(entity)
    local transform = entity:get("transform")
    local renderable = entity:get("renderable")

    if not renderable.visible then return end

    -- Check cloaking visibility
    -- Reference: Original C&C - cloaked units invisible to enemies, shimmer to owner
    local cloak_alpha = 1
    local shimmer_enabled = false
    local shimmer_x, shimmer_y = 0, 0
    local cloak_tint = {1, 1, 1}

    if entity:has("cloak") and self.cloak_system then
        local render_info = self.cloak_system:get_render_info(entity, self.viewer_house)
        cloak_alpha = render_info.alpha
        shimmer_enabled = render_info.shimmer_enabled
        shimmer_x = render_info.shimmer_x
        shimmer_y = render_info.shimmer_y
        cloak_tint = render_info.color_tint

        -- Don't render if fully invisible
        if cloak_alpha <= 0 then
            return
        end
    end

    -- Convert lepton position to pixels
    local px = transform.x / Constants.PIXEL_LEPTON_W
    local py = transform.y / Constants.PIXEL_LEPTON_H

    -- Apply offset
    px = px + (renderable.offset_x or 0)
    py = py + (renderable.offset_y or 0)

    -- Apply infantry sub-position offset (5 infantry can fit in one cell)
    -- Reference: Original C&C - sub_position 0=center, 1=NW, 2=NE, 3=SW, 4=SE
    if entity:has("infantry") then
        local infantry = entity:get("infantry")
        local sub_pos = infantry.sub_position or 0
        local sub_offset = self:get_infantry_sub_offset(sub_pos)
        px = px + sub_offset.x
        py = py + sub_offset.y
    end

    -- Apply shimmer offset for cloaked units
    if shimmer_enabled then
        px = px + shimmer_x
        py = py + shimmer_y
    end

    -- Aircraft altitude handling - draw shadow and offset sprite
    -- Reference: Original C&C draws shadow at ground level, sprite at altitude
    local altitude = 0
    local is_aircraft = entity:has("aircraft")
    if is_aircraft then
        local aircraft = entity:get("aircraft")
        altitude = aircraft.altitude or 0

        -- Add visual jitter for helicopters
        altitude = altitude + (aircraft.visual_altitude_offset or 0)

        -- Draw shadow at ground level if airborne
        if altitude > 0 then
            self:draw_aircraft_shadow(entity, px, py)
        end

        -- Offset sprite position by altitude (sprite drawn higher)
        py = py - altitude
    end

    -- Apply color/tint with cloak effects
    local color = renderable.color or {1, 1, 1, 1}
    local final_color = {
        color[1] * cloak_tint[1],
        color[2] * cloak_tint[2],
        color[3] * cloak_tint[3],
        (color[4] or 1) * cloak_alpha
    }
    love.graphics.setColor(unpack(final_color))

    -- Check if we have a sprite name string that we can load
    local sprite_name = renderable.sprite
    local drawn = false

    if sprite_name and type(sprite_name) == "string" and self.sprite_loader then
        -- Try to draw using sprite loader
        local frame = renderable.frame or 0
        local rotation = transform.rotation or 0

        -- Draw sprite using quad
        local sheet = self.sprite_loader:get_sheet(sprite_name)
        local quad = self.sprite_loader:get_quad(sprite_name, frame)
        local meta = self.sprite_loader:get_metadata(sprite_name)

        if sheet and quad and meta then
            -- Center the sprite on position
            local ox = meta.frame_width / 2
            local oy = meta.frame_height / 2

            -- Draw the sprite (vehicle body)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet, quad, px, py, rotation, 1, 1, ox, oy)

            -- Draw turret if vehicle has one
            if renderable.has_turret and renderable.turret_frame then
                local turret_quad = self.sprite_loader:get_quad(sprite_name, renderable.turret_frame)
                if turret_quad then
                    love.graphics.draw(sheet, turret_quad, px, py, 0, 1, 1, ox, oy)
                end
            end

            drawn = true
        end
    elseif renderable.sprite and type(renderable.sprite) ~= "string" then
        -- Draw actual Love2D Drawable (legacy support)
        love.graphics.draw(renderable.sprite, px, py)
        drawn = true
    end

    -- Fall back to placeholder if sprite couldn't be drawn
    if not drawn then
        self:draw_placeholder(entity, px, py)
    end

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw aircraft shadow on ground
-- Reference: Original C&C draws shadow offset south by altitude
function RenderSystem:draw_aircraft_shadow(entity, ground_x, ground_y)
    local renderable = entity:get("renderable")
    local aircraft = entity:get("aircraft")
    local altitude = aircraft.altitude or 0

    -- Shadow offset: south by altitude amount (original behavior)
    local shadow_x = ground_x
    local shadow_y = ground_y + altitude

    -- Draw shadow using sprite if available
    local sprite_name = renderable.sprite
    if sprite_name and type(sprite_name) == "string" and self.sprite_loader then
        local frame = renderable.frame or 0
        local sheet = self.sprite_loader:get_sheet(sprite_name)
        local quad = self.sprite_loader:get_quad(sprite_name, frame)
        local meta = self.sprite_loader:get_metadata(sprite_name)

        if sheet and quad and meta then
            local ox = meta.frame_width / 2
            local oy = meta.frame_height / 2

            -- Draw dark translucent shadow
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.draw(sheet, quad, shadow_x, shadow_y, 0, 1, 1, ox, oy)
            love.graphics.setColor(1, 1, 1, 1)
            return
        end
    end

    -- Fallback: draw simple oval shadow
    local shadow_w = (renderable.scale_x or 1) * Constants.CELL_PIXEL_W * 0.6
    local shadow_h = (renderable.scale_y or 1) * Constants.CELL_PIXEL_H * 0.3
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", shadow_x, shadow_y, shadow_w, shadow_h)
    love.graphics.setColor(1, 1, 1, 1)
end

function RenderSystem:draw_placeholder(entity, px, py)
    local renderable = entity:get("renderable")

    -- Determine size based on entity type
    local w = Constants.CELL_PIXEL_W * renderable.scale_x
    local h = Constants.CELL_PIXEL_H * renderable.scale_y

    -- Center the placeholder on position
    local x = px - w / 2
    local y = py - h / 2

    -- Get entity house for color
    local house = nil
    if entity:has("owner") then
        house = entity:get("owner").house
    end

    -- Determine entity type
    local is_building = entity:has("building")
    local is_infantry = entity:has("infantry")
    local is_vehicle = entity:has("mobile") and not is_infantry
    local is_effect = entity.has_tag and entity:has_tag("effect")

    -- Flash effect
    if renderable.flash then
        love.graphics.setColor(1, 1, 1, 0.8)
    end

    -- Draw different shapes based on entity type
    if is_effect then
        -- Effects: animated explosion/death visual
        local sprite_name = renderable.sprite or ""
        local anim = entity:has("animation") and entity:get("animation")
        local progress = 0
        if entity.effect_lifetime and entity.effect_timer then
            progress = entity.effect_timer / entity.effect_lifetime
        elseif anim then
            progress = anim.frame / 10  -- Approximate progress
        end

        -- Determine effect style based on sprite name
        if sprite_name:find("infantry") then
            -- Infantry death: red splat that fades
            local alpha = 1 - progress
            local radius = 6 + progress * 4
            love.graphics.setColor(0.8, 0.1, 0.1, alpha)
            love.graphics.circle("fill", px, py, radius)
            love.graphics.setColor(0.5, 0, 0, alpha * 0.5)
            love.graphics.circle("fill", px, py, radius * 0.6)
        else
            -- Explosion: expanding orange/yellow circle that fades
            local alpha = 1 - progress
            local max_radius = 12
            if sprite_name:find("medium") then
                max_radius = 18
            elseif sprite_name:find("large") then
                max_radius = 28
            end
            local radius = 4 + progress * max_radius

            -- Outer orange glow
            love.graphics.setColor(1, 0.5, 0, alpha * 0.6)
            love.graphics.circle("fill", px, py, radius)

            -- Inner yellow core
            love.graphics.setColor(1, 0.9, 0.2, alpha)
            love.graphics.circle("fill", px, py, radius * 0.5)

            -- White hot center (early in explosion)
            if progress < 0.3 then
                love.graphics.setColor(1, 1, 1, (0.3 - progress) * 3)
                love.graphics.circle("fill", px, py, radius * 0.25)
            end

            -- Smoke ring (later in explosion)
            if progress > 0.4 then
                local smoke_alpha = (progress - 0.4) * 0.8
                love.graphics.setColor(0.3, 0.3, 0.3, smoke_alpha * (1 - progress))
                love.graphics.circle("line", px, py, radius * 1.2)
            end
        end
    elseif is_building then
        -- Buildings: filled rectangle with damage states
        local health = entity:has("health") and entity:get("health") or nil
        local hp_ratio = health and (health.hp / health.max_hp) or 1

        -- Draw base building
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h)
        love.graphics.setLineWidth(1)

        -- Draw damage overlay based on health
        if hp_ratio < 0.75 then
            -- Light damage - some smoke
            love.graphics.setColor(0.3, 0.3, 0.3, 0.3)
            local smoke_x = x + w * 0.3
            local smoke_y = y + h * 0.2
            love.graphics.circle("fill", smoke_x, smoke_y, 3)
        end

        if hp_ratio < 0.5 then
            -- Medium damage - cracks and more smoke
            love.graphics.setColor(0.15, 0.15, 0.15, 0.5)
            -- Draw crack lines
            love.graphics.line(x + w * 0.2, y, x + w * 0.4, y + h * 0.3)
            love.graphics.line(x + w * 0.6, y + h, x + w * 0.8, y + h * 0.7)
            -- More smoke
            local smoke_x = x + w * 0.7
            local smoke_y = y + h * 0.3
            love.graphics.setColor(0.4, 0.4, 0.4, 0.4)
            love.graphics.circle("fill", smoke_x, smoke_y, 4)
        end

        if hp_ratio < 0.25 then
            -- Heavy damage - fire and lots of smoke
            -- Animated fire effect
            local fire_time = love.timer.getTime() * 4
            local fire_flicker = math.sin(fire_time) * 0.3 + 0.7

            -- Fire at multiple points
            love.graphics.setColor(1, 0.5 * fire_flicker, 0, 0.7)
            love.graphics.circle("fill", x + w * 0.3, y + h * 0.4, 5)
            love.graphics.circle("fill", x + w * 0.7, y + h * 0.5, 4)

            -- Yellow core
            love.graphics.setColor(1, 0.9, 0.2, 0.8)
            love.graphics.circle("fill", x + w * 0.3, y + h * 0.4, 3)

            -- Thick smoke
            love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
            love.graphics.circle("fill", x + w * 0.5, y - 3, 6)
            love.graphics.circle("fill", x + w * 0.4, y - 8, 4)
        end
    elseif is_infantry then
        -- Infantry: small circle
        local radius = math.min(w, h) / 3
        love.graphics.circle("fill", px, py, radius)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("line", px, py, radius)
    elseif is_vehicle then
        -- Vehicles: diamond shape with turret
        local cx, cy = px, py
        local hw, hh = w / 2, h / 2

        -- Get body facing direction for hull orientation
        local transform = entity:get("transform")
        local body_angle = (transform.facing or 0) * (math.pi / 4)  -- 8 directions

        -- Draw rotated diamond (hull)
        local cos_b, sin_b = math.cos(body_angle), math.sin(body_angle)
        local vertices = {
            cx + (-hw * sin_b), cy + (-hh * cos_b),      -- top (relative)
            cx + (hw * cos_b), cy + (-hw * sin_b),       -- right
            cx + (hw * sin_b), cy + (hh * cos_b),        -- bottom
            cx + (-hw * cos_b), cy + (hw * sin_b)        -- left
        }
        love.graphics.polygon("fill", vertices)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.polygon("line", vertices)

        -- Draw turret if entity has turret component
        if entity:has("turret") then
            local turret = entity:get("turret")
            local turret_facing = turret.facing or 0

            -- Convert 32-direction facing to angle
            local turret_angle = turret_facing * (math.pi / 16)

            -- Draw turret barrel
            local barrel_len = math.min(w, h) * 0.6
            local barrel_end_x = cx + math.sin(turret_angle) * barrel_len
            local barrel_end_y = cy - math.cos(turret_angle) * barrel_len

            -- Turret base
            love.graphics.setColor(renderable.color[1] * 0.7, renderable.color[2] * 0.7, renderable.color[3] * 0.7, 1)
            love.graphics.circle("fill", cx, cy, math.min(w, h) * 0.25)

            -- Barrel
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.setLineWidth(3)
            love.graphics.line(cx, cy, barrel_end_x, barrel_end_y)
            love.graphics.setLineWidth(1)
        end
    else
        -- Default: rectangle
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("line", x, y, w, h)
    end

    -- Draw selection indicator if selected
    if entity:has("selectable") then
        local selectable = entity:get("selectable")
        if selectable.selected then
            love.graphics.setColor(0, 1, 0, 1)
            love.graphics.setLineWidth(2)
            if is_infantry then
                local radius = math.min(w, h) / 3
                love.graphics.circle("line", px, py, radius + 3)
            else
                love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4)
            end
            love.graphics.setLineWidth(1)

            -- Draw "D" indicator for deployable units (MCV)
            if entity:has("deployable") then
                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print("D", x + w + 4, y)
            end
        end
    end

    -- Draw health bar if has health
    if entity:has("health") then
        local health = entity:get("health")
        local hp_ratio = health.hp / health.max_hp
        local bar_w = w
        local bar_h = 3
        local bar_y = y - bar_h - 2

        -- Background
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", x, bar_y, bar_w, bar_h)

        -- Health bar
        if hp_ratio > 0.5 then
            love.graphics.setColor(0, 1, 0, 1)
        elseif hp_ratio > 0.25 then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(1, 0, 0, 1)
        end
        love.graphics.rectangle("fill", x, bar_y, bar_w * hp_ratio, bar_h)
    end
end

-- Convert screen coordinates to world coordinates
function RenderSystem:screen_to_world(screen_x, screen_y)
    local world_x = (screen_x / self.scale) + self.camera_x
    local world_y = (screen_y / self.scale) + self.camera_y
    return world_x, world_y
end

-- Convert world coordinates to screen coordinates
function RenderSystem:world_to_screen(world_x, world_y)
    local screen_x = (world_x - self.camera_x) * self.scale
    local screen_y = (world_y - self.camera_y) * self.scale
    return screen_x, screen_y
end

-- Check if a world position is visible on screen
function RenderSystem:is_visible(world_x, world_y)
    local screen_w, screen_h = love.graphics.getDimensions()
    local sx, sy = self:world_to_screen(world_x, world_y)
    return sx >= 0 and sx < screen_w and sy >= 0 and sy < screen_h
end

-- Infantry sub-position offsets within a cell
-- Reference: Original C&C - 5 infantry per cell at different sub-positions
-- Sub-positions: 0=center, 1=NW, 2=NE, 3=SW, 4=SE
-- Offsets are in pixels, relative to cell center
RenderSystem.INFANTRY_SUB_OFFSETS = {
    [0] = {x = 0,  y = 0},   -- Center
    [1] = {x = -6, y = -6},  -- NW
    [2] = {x = 6,  y = -6},  -- NE
    [3] = {x = -6, y = 6},   -- SW
    [4] = {x = 6,  y = 6}    -- SE
}

-- Get the pixel offset for an infantry sub-position
function RenderSystem:get_infantry_sub_offset(sub_position)
    return self.INFANTRY_SUB_OFFSETS[sub_position] or self.INFANTRY_SUB_OFFSETS[0]
end

return RenderSystem
