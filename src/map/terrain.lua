--[[
    Terrain - Terrain templates and overlays
    Handles terrain types, passability, and visual rendering
    Reference: Original C&C terrain system (TERRAIN.CPP, TEMPLATE.H)
]]

local Paths = require("src.util.paths")

local Terrain = {}
Terrain.__index = Terrain

-- Terrain types (from DEFINES.H)
Terrain.TYPE = {
    CLEAR = 0,
    WATER = 1,
    ROAD = 2,
    ROCK = 3,
    ROUGH = 4,
    RIVER = 5,
    CLIFF = 6,
    SHORE = 7,
    TIBERIUM = 8
}

-- Land types (affects unit movement)
Terrain.LAND = {
    CLEAR = 0,      -- Normal ground
    ROAD = 1,       -- Road (bonus speed)
    WATER = 2,      -- Water (boats only)
    ROCK = 3,       -- Impassable rock
    WALL = 4,       -- Walls
    TIBERIUM = 5,   -- Tiberium field
    BEACH = 6,      -- Beach/shore
    ROUGH = 7,      -- Rough terrain
    RIVER = 8       -- River (impassable for most)
}

-- Movement costs per terrain type
Terrain.SPEED_MODIFIER = {
    [Terrain.TYPE.CLEAR] = 1.0,
    [Terrain.TYPE.WATER] = 0,       -- Impassable
    [Terrain.TYPE.ROAD] = 1.2,      -- Faster on roads
    [Terrain.TYPE.ROCK] = 0,        -- Impassable
    [Terrain.TYPE.ROUGH] = 0.6,     -- Slower on rough
    [Terrain.TYPE.RIVER] = 0,       -- Impassable
    [Terrain.TYPE.CLIFF] = 0,       -- Impassable
    [Terrain.TYPE.SHORE] = 0.8,     -- Slightly slower
    [Terrain.TYPE.TIBERIUM] = 1.0   -- Normal speed (but damages infantry)
}

function Terrain.new()
    local self = setmetatable({}, Terrain)

    -- Terrain templates
    self.templates = {}

    -- Overlay types (walls, tiberium, etc.)
    self.overlays = {}

    -- Theater (TEMPERATE, WINTER, DESERT)
    self.theater = "TEMPERATE"

    -- Loaded sprites
    self.sprites = {}

    -- Template data from JSON
    self.template_data = {}
    self.overlay_data = {}

    return self
end

-- Set theater
function Terrain:set_theater(theater)
    self.theater = theater or "TEMPERATE"
    -- Reload sprites for new theater
    self.sprites = {}
end

-- Load terrain templates from JSON
function Terrain:load_templates(path)
    path = path or "data/terrain/templates.json"

    if love.filesystem.getInfo(path) then
        local content = love.filesystem.read(path)
        if content then
            local success, data = pcall(function()
                return require("lib.json").decode(content)
            end)

            if success and data then
                self.template_data = data
                return true
            end
        end
    end

    return false
end

-- Load overlay definitions from JSON
function Terrain:load_overlays(path)
    path = path or "data/terrain/overlays.json"

    if love.filesystem.getInfo(path) then
        local content = love.filesystem.read(path)
        if content then
            local success, data = pcall(function()
                return require("lib.json").decode(content)
            end)

            if success and data then
                self.overlay_data = data
                return true
            end
        end
    end

    return false
end

-- Get template definition
function Terrain:get_template(name)
    return self.template_data[name]
end

-- Get overlay definition
function Terrain:get_overlay(name)
    return self.overlay_data[name]
end

-- Get terrain type for a template
function Terrain:get_terrain_type(template_name)
    local template = self.template_data[template_name]
    if template then
        return template.terrain_type or Terrain.TYPE.CLEAR
    end
    return Terrain.TYPE.CLEAR
end

-- Get land type for a template
function Terrain:get_land_type(template_name)
    local template = self.template_data[template_name]
    if template then
        return template.land_type or Terrain.LAND.CLEAR
    end
    return Terrain.LAND.CLEAR
end

-- Check if terrain is passable
function Terrain:is_passable(terrain_type, locomotor)
    locomotor = locomotor or "track"

    -- Flying units can pass anything
    if locomotor == "fly" then
        return true
    end

    -- Water passable for boats
    if terrain_type == Terrain.TYPE.WATER then
        return locomotor == "float" or locomotor == "boat"
    end

    -- Impassable types
    if terrain_type == Terrain.TYPE.ROCK or
       terrain_type == Terrain.TYPE.CLIFF or
       terrain_type == Terrain.TYPE.RIVER then
        return false
    end

    return true
end

-- Get movement speed modifier
function Terrain:get_speed_modifier(terrain_type, locomotor)
    locomotor = locomotor or "track"

    -- Flying ignores terrain
    if locomotor == "fly" then
        return 1.0
    end

    -- Wheeled vehicles slower on rough
    local base = Terrain.SPEED_MODIFIER[terrain_type] or 1.0

    if locomotor == "wheel" and terrain_type == Terrain.TYPE.ROUGH then
        return base * 0.7
    end

    -- Tracked vehicles better on rough
    if locomotor == "track" and terrain_type == Terrain.TYPE.ROUGH then
        return base * 1.2
    end

    return base
end

-- Check if terrain damages infantry
function Terrain:damages_infantry(terrain_type)
    return terrain_type == Terrain.TYPE.TIBERIUM
end

-- Get sprite for template
function Terrain:get_sprite(template_name, frame)
    frame = frame or 0

    local key = template_name .. "_" .. frame

    if not self.sprites[key] then
        local template = self.template_data[template_name]
        if template then
            local theater_lower = self.theater:lower()
            local sprite_path = Paths.sprite(theater_lower .. "/terrain/" .. template_name .. ".png")

            if love.filesystem.getInfo(sprite_path) then
                local success, image = pcall(function()
                    return love.graphics.newImage(sprite_path)
                end)

                if success and image then
                    self.sprites[key] = image
                end
            end
        end
    end

    return self.sprites[key]
end

-- Get overlay sprite
function Terrain:get_overlay_sprite(overlay_name, frame)
    frame = frame or 0

    local key = "overlay_" .. overlay_name .. "_" .. frame

    if not self.sprites[key] then
        local overlay = self.overlay_data[overlay_name]
        if overlay then
            local sprite_path = Paths.sprite("overlays/" .. overlay_name .. ".png")

            if love.filesystem.getInfo(sprite_path) then
                local success, image = pcall(function()
                    return love.graphics.newImage(sprite_path)
                end)

                if success and image then
                    self.sprites[key] = image
                end
            end
        end
    end

    return self.sprites[key]
end

-- Get tiberium overlay sprite by stage
function Terrain:get_tiberium_sprite(stage)
    stage = stage or 0
    local key = "tiberium_" .. stage

    if not self.sprites[key] then
        local sprite_path = Paths.sprite("overlays/tiberium_" .. stage .. ".png")

        if not love.filesystem.getInfo(sprite_path) then
            sprite_path = Paths.sprite("overlays/tiberium.png")
        end

        if love.filesystem.getInfo(sprite_path) then
            local success, image = pcall(function()
                return love.graphics.newImage(sprite_path)
            end)

            if success and image then
                self.sprites[key] = image
            end
        end
    end

    return self.sprites[key]
end

-- Get all templates of a type
function Terrain:get_templates_by_type(terrain_type)
    local result = {}

    for name, template in pairs(self.template_data) do
        if template.terrain_type == terrain_type then
            table.insert(result, name)
        end
    end

    return result
end

-- Get all overlays of a category
function Terrain:get_overlays_by_category(category)
    local result = {}

    for name, overlay in pairs(self.overlay_data) do
        if overlay.category == category then
            table.insert(result, name)
        end
    end

    return result
end

-- Terrain palette for a theater
function Terrain:get_palette()
    local palettes = {
        TEMPERATE = {
            grass = {0.2, 0.5, 0.2},
            dirt = {0.5, 0.4, 0.3},
            rock = {0.4, 0.4, 0.4},
            water = {0.1, 0.2, 0.5},
            tiberium = {0.2, 0.8, 0.2}
        },
        WINTER = {
            grass = {0.8, 0.8, 0.9},
            dirt = {0.6, 0.6, 0.65},
            rock = {0.5, 0.5, 0.55},
            water = {0.2, 0.3, 0.5},
            tiberium = {0.2, 0.8, 0.2}
        },
        DESERT = {
            grass = {0.7, 0.6, 0.4},
            dirt = {0.8, 0.7, 0.5},
            rock = {0.6, 0.5, 0.4},
            water = {0.2, 0.4, 0.5},
            tiberium = {0.2, 0.8, 0.2}
        }
    }

    return palettes[self.theater] or palettes.TEMPERATE
end

-- Draw terrain cell (fallback if no sprite)
function Terrain:draw_cell_fallback(terrain_type, x, y, cell_size)
    local palette = self:get_palette()

    local color
    if terrain_type == Terrain.TYPE.WATER then
        color = palette.water
    elseif terrain_type == Terrain.TYPE.ROCK or terrain_type == Terrain.TYPE.CLIFF then
        color = palette.rock
    elseif terrain_type == Terrain.TYPE.ROUGH then
        color = palette.dirt
    elseif terrain_type == Terrain.TYPE.ROAD then
        color = {0.4, 0.35, 0.3}
    elseif terrain_type == Terrain.TYPE.TIBERIUM then
        color = palette.tiberium
    else
        color = palette.grass
    end

    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.rectangle("fill", x, y, cell_size, cell_size)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Create a random terrain template
function Terrain:random_template(terrain_type)
    local templates = self:get_templates_by_type(terrain_type)
    if #templates > 0 then
        return templates[math.random(1, #templates)]
    end
    return nil
end

-- Clear sprite cache
function Terrain:clear_cache()
    self.sprites = {}
end

-- Get info for debugging
function Terrain:get_info()
    return {
        theater = self.theater,
        template_count = 0,  -- Would count template_data
        overlay_count = 0,   -- Would count overlay_data
        cached_sprites = 0   -- Would count sprites
    }
end

return Terrain
