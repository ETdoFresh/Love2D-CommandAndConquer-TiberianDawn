--[[
    Theater - Terrain theme (Temperate, Desert, Winter)
    Manages theater-specific terrain graphics and palettes
]]

local Constants = require("src.core.constants")

local Theater = {}
Theater.__index = Theater

-- Theater definitions
Theater.TYPES = {
    TEMPERATE = {
        id = Constants.THEATER.TEMPERATE,
        name = "Temperate",
        suffix = "TEM",
        mix_file = "TEMPERAT.MIX",
        palette = "temperat.pal",
        tiberium_color = {0.4, 0.9, 0.3},  -- Green tiberium
        water_color = {0.2, 0.4, 0.8}
    },
    DESERT = {
        id = Constants.THEATER.DESERT,
        name = "Desert",
        suffix = "DES",
        mix_file = "DESERT.MIX",
        palette = "desert.pal",
        tiberium_color = {0.4, 0.9, 0.3},
        water_color = {0.3, 0.5, 0.7}
    },
    WINTER = {
        id = Constants.THEATER.WINTER,
        name = "Winter",
        suffix = "WIN",
        mix_file = "WINTER.MIX",
        palette = "winter.pal",
        tiberium_color = {0.3, 0.8, 0.4},  -- Slightly different green
        water_color = {0.3, 0.5, 0.8}
    }
}

-- Create a new theater
function Theater.new(theater_type)
    local self = setmetatable({}, Theater)

    local theater_def = Theater.TYPES[theater_type] or Theater.TYPES.TEMPERATE
    self.type = theater_def.id
    self.name = theater_def.name
    self.suffix = theater_def.suffix
    self.mix_file = theater_def.mix_file
    self.palette = theater_def.palette
    self.tiberium_color = theater_def.tiberium_color
    self.water_color = theater_def.water_color

    -- Terrain templates (loaded from data)
    self.templates = {}

    -- Loaded graphics
    self.tile_images = {}
    self.loaded = false

    return self
end

-- Get theater by ID
function Theater.from_id(id)
    for name, def in pairs(Theater.TYPES) do
        if def.id == id then
            return Theater.new(name)
        end
    end
    return Theater.new("TEMPERATE")
end

-- Load theater graphics
function Theater:load()
    if self.loaded then return end

    -- TODO: Load actual graphics from extracted assets
    -- For now, create placeholder tiles
    self:create_placeholder_tiles()

    self.loaded = true
end

-- Unload theater graphics
function Theater:unload()
    self.tile_images = {}
    self.loaded = false
end

-- Create placeholder colored tiles for testing
function Theater:create_placeholder_tiles()
    local colors = {
        -- Clear terrain
        clear = {0.4, 0.6, 0.3},
        -- Water
        water = self.water_color,
        -- Road
        road = {0.5, 0.5, 0.5},
        -- Rock
        rock = {0.4, 0.4, 0.4},
        -- Cliff
        cliff = {0.3, 0.25, 0.2},
        -- Rough
        rough = {0.45, 0.5, 0.3},
        -- Tiberium
        tiberium = self.tiberium_color
    }

    for name, color in pairs(colors) do
        local image_data = love.image.newImageData(
            Constants.CELL_PIXEL_W,
            Constants.CELL_PIXEL_H
        )

        for y = 0, Constants.CELL_PIXEL_H - 1 do
            for x = 0, Constants.CELL_PIXEL_W - 1 do
                image_data:setPixel(x, y, color[1], color[2], color[3], 1)
            end
        end

        self.tile_images[name] = love.graphics.newImage(image_data)
    end
end

-- Get tile image for a template type
function Theater:get_tile(template_type, icon)
    -- TODO: Map template types to actual graphics
    -- For now, return based on template ranges

    if template_type == 0 then
        return self.tile_images.clear
    elseif template_type >= 1 and template_type <= 5 then
        return self.tile_images.water
    elseif template_type >= 6 and template_type <= 10 then
        return self.tile_images.road
    elseif template_type >= 11 and template_type <= 20 then
        return self.tile_images.rock
    elseif template_type >= 21 and template_type <= 30 then
        return self.tile_images.cliff
    else
        return self.tile_images.clear
    end
end

-- Get overlay image
function Theater:get_overlay(overlay_type)
    -- Tiberium overlays
    if overlay_type >= 6 and overlay_type <= 17 then
        return self.tile_images.tiberium
    end

    return nil
end

-- Get theater-specific asset path
function Theater:get_asset_path(base_name, extension)
    return string.format("assets/sprites/classic/terrain/%s.%s.%s",
        base_name, self.suffix:lower(), extension or "png")
end

-- String representation
function Theater:__tostring()
    return string.format("Theater(%s)", self.name)
end

return Theater
