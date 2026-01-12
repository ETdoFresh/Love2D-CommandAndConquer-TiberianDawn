--[[
    Theater - Terrain theme (Temperate, Desert, Winter)
    Manages theater-specific terrain graphics and palettes
]]

local Constants = require("src.core.constants")
local Serialize = require("src.util.serialize")
local Paths = require("src.util.paths")

local Theater = {}
Theater.__index = Theater

-- Loaded terrain data from JSON (shared across all theaters)
Theater.land_types = nil
Theater.overlays = nil
Theater.terrain_objects = nil
Theater.tiberium_growth = nil

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

-- Load shared terrain data from JSON (called once)
function Theater.load_terrain_data()
    if Theater.land_types then return end  -- Already loaded

    -- Load templates.json
    local templates_data = Serialize.load_json("data/terrain/templates.json")
    if templates_data then
        Theater.land_types = templates_data.land_types or {}
        Theater.terrain_objects = templates_data.terrain_objects or {}
    end

    -- Load overlays.json
    local overlays_data = Serialize.load_json("data/terrain/overlays.json")
    if overlays_data then
        Theater.overlays = overlays_data.overlays or {}
        Theater.tiberium_growth = overlays_data.tiberium_growth or {}
    end
end

-- Get land type data by name
function Theater.get_land_type(land_name)
    if not Theater.land_types then Theater.load_terrain_data() end
    return Theater.land_types[land_name]
end

-- Get land type data by ID
function Theater.get_land_type_by_id(id)
    if not Theater.land_types then Theater.load_terrain_data() end
    for name, data in pairs(Theater.land_types or {}) do
        if data.id == id then
            return data, name
        end
    end
    return nil
end

-- Get overlay data by name
function Theater.get_overlay(overlay_name)
    if not Theater.overlays then Theater.load_terrain_data() end
    return Theater.overlays[overlay_name]
end

-- Get overlay data by ID
function Theater.get_overlay_by_id(id)
    if not Theater.overlays then Theater.load_terrain_data() end
    for name, data in pairs(Theater.overlays or {}) do
        if data.id == id then
            return data, name
        end
    end
    return nil
end

-- Get tiberium overlay for a given growth stage (1-12)
function Theater.get_tiberium_overlay(stage)
    if not Theater.overlays then Theater.load_terrain_data() end
    local key = "TIBERIUM" .. tostring(math.min(12, math.max(1, stage)))
    return Theater.overlays[key]
end

-- Get tiberium growth parameters
function Theater.get_tiberium_growth_params()
    if not Theater.tiberium_growth then Theater.load_terrain_data() end
    return Theater.tiberium_growth or {
        growth_rate = 0.02,
        spread_chance = 0.001,
        max_spread_distance = 2,
        infantry_damage_per_tick = 2
    }
end

-- Check if an overlay is a wall
function Theater.is_wall_overlay(overlay_id)
    local data = Theater.get_overlay_by_id(overlay_id)
    return data and data.is_wall
end

-- Check if an overlay is tiberium
function Theater.is_tiberium_overlay(overlay_id)
    local data = Theater.get_overlay_by_id(overlay_id)
    return data and data.is_tiberium
end

-- Load theater graphics
function Theater:load()
    if self.loaded then return end

    -- Load shared terrain data first
    Theater.load_terrain_data()

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
        tiberium = self.tiberium_color,
        -- Wall (gray concrete)
        wall = {0.6, 0.6, 0.6},
        -- Beach (sandy)
        beach = {0.75, 0.7, 0.5}
    }

    for name, color in pairs(colors) do
        local image_data = love.image.newImageData(
            Constants.CELL_PIXEL_W,
            Constants.CELL_PIXEL_H
        )

        for y = 0, Constants.CELL_PIXEL_H - 1 do
            for x = 0, Constants.CELL_PIXEL_W - 1 do
                -- Add grid lines for visibility
                local r, g, b = color[1], color[2], color[3]
                if x == 0 or y == 0 then
                    -- Darker grid lines
                    r, g, b = r * 0.7, g * 0.7, b * 0.7
                end
                image_data:setPixel(x, y, r, g, b, 1)
            end
        end

        self.tile_images[name] = love.graphics.newImage(image_data)
    end
end

-- Get tile image for a land type
function Theater:get_tile(land_type_id, icon)
    -- Map land type IDs to tile images using loaded data
    local land_data = Theater.get_land_type_by_id(land_type_id)

    if land_data then
        local name = land_data.name:lower()
        if self.tile_images[name] then
            return self.tile_images[name]
        end
    end

    -- Fallback mappings by ID
    if land_type_id == 0 then
        return self.tile_images.clear
    elseif land_type_id == 1 then
        return self.tile_images.road
    elseif land_type_id == 2 then
        return self.tile_images.water
    elseif land_type_id == 3 then
        return self.tile_images.rock
    elseif land_type_id == 4 then
        return self.tile_images.wall or self.tile_images.rock
    elseif land_type_id == 5 then
        return self.tile_images.tiberium
    elseif land_type_id == 6 then
        return self.tile_images.beach or self.tile_images.clear
    else
        return self.tile_images.clear
    end
end

-- Get overlay image
function Theater:get_overlay(overlay_id)
    local overlay_data = Theater.get_overlay_by_id(overlay_id)

    if overlay_data then
        -- Tiberium overlays
        if overlay_data.is_tiberium then
            return self.tile_images.tiberium
        end
        -- Wall overlays
        if overlay_data.is_wall then
            return self.tile_images.wall or self.tile_images.rock
        end
        -- Road overlays
        if overlay_data.is_road then
            return self.tile_images.road
        end
    end

    -- Fallback: tiberium overlay IDs 6-17
    if overlay_id >= 6 and overlay_id <= 17 then
        return self.tile_images.tiberium
    end

    return nil
end

-- Get overlay data including health for walls
function Theater:get_overlay_data(overlay_id)
    return Theater.get_overlay_by_id(overlay_id)
end

-- Get theater-specific asset path
function Theater:get_asset_path(base_name, extension)
    return Paths.sprite(string.format("classic/terrain/%s.%s.%s",
        base_name, self.suffix:lower(), extension or "png"))
end

-- String representation
function Theater:__tostring()
    return string.format("Theater(%s)", self.name)
end

return Theater
