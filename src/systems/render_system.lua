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

    return self
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

    -- Sort entities into layers
    for _, entity in ipairs(entities) do
        local renderable = entity:get("renderable")
        if renderable.visible then
            local layer = renderable.layer or Constants.LAYER.GROUND
            table.insert(self.layers[layer], entity)
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

    -- Convert lepton position to pixels
    local px = transform.x / Constants.PIXEL_LEPTON_W
    local py = transform.y / Constants.PIXEL_LEPTON_H

    -- Apply offset
    px = px + (renderable.offset_x or 0)
    py = py + (renderable.offset_y or 0)

    -- Apply color/tint
    local color = renderable.color or {1, 1, 1, 1}
    love.graphics.setColor(unpack(color))

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

            -- Draw the sprite
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet, quad, px, py, rotation, 1, 1, ox, oy)

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

    -- Flash effect
    if renderable.flash then
        love.graphics.setColor(1, 1, 1, 0.8)
    end

    -- Draw different shapes based on entity type
    if is_building then
        -- Buildings: filled rectangle with thicker border
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h)
        love.graphics.setLineWidth(1)
    elseif is_infantry then
        -- Infantry: small circle
        local radius = math.min(w, h) / 3
        love.graphics.circle("fill", px, py, radius)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("line", px, py, radius)
    elseif is_vehicle then
        -- Vehicles: diamond shape
        local cx, cy = px, py
        local hw, hh = w / 2, h / 2
        local vertices = {
            cx, cy - hh,      -- top
            cx + hw, cy,      -- right
            cx, cy + hh,      -- bottom
            cx - hw, cy       -- left
        }
        love.graphics.polygon("fill", vertices)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.polygon("line", vertices)
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

return RenderSystem
