--[[
    Sprite Loader - Loads and caches sprite sheets from extracted PNG files

    Loads sprite sheets from assets/sprites/ directory and creates
    Love2D Quads for each animation frame.
]]

-- Simple JSON parser for metadata files (only handles our simple format)
local function parse_json(str)
    -- Remove whitespace and parse key-value pairs
    local result = {}
    for key, value in str:gmatch('"([^"]+)"%s*:%s*(%d+)') do
        result[key] = tonumber(value)
    end
    return result
end

local SpriteLoader = {}
SpriteLoader.__index = SpriteLoader

-- Singleton instance
local instance = nil

function SpriteLoader.new()
    local self = setmetatable({}, SpriteLoader)

    -- Cache for loaded sprite sheets
    self.sheets = {}

    -- Cache for sprite metadata
    self.metadata = {}

    -- Cache for quads (organized by sprite name)
    self.quads = {}

    -- Base path for sprites
    self.base_path = "assets/sprites/"

    -- Category subdirectories
    self.categories = {
        "aircraft",
        "buildings",
        "effects",
        "infantry",
        "vehicles",
        "walls"
    }

    return self
end

-- Get singleton instance
function SpriteLoader.get_instance()
    if not instance then
        instance = SpriteLoader.new()
    end
    return instance
end

-- Normalize sprite name: remove .shp extension if present and lowercase
local function normalize_name(name)
    if not name then return nil end
    return name:gsub("%.shp$", ""):lower()
end

-- Load a sprite sheet by name (e.g., "mtnk", "e1", "fact")
-- Also accepts legacy names with .shp extension (e.g., "mtnk.shp")
function SpriteLoader:load(name)
    -- Normalize name
    name = normalize_name(name)
    if not name then return nil, nil end

    -- Check cache first
    if self.sheets[name] then
        return self.sheets[name], self.metadata[name]
    end

    -- Search in category directories
    local png_path, json_path
    for _, category in ipairs(self.categories) do
        local test_path = self.base_path .. category .. "/" .. name .. ".png"
        if love.filesystem.getInfo(test_path) then
            png_path = test_path
            json_path = test_path .. ".json"
            break
        end
    end

    if not png_path then
        -- Try direct path (without category)
        png_path = self.base_path .. name .. ".png"
        json_path = png_path .. ".json"
        if not love.filesystem.getInfo(png_path) then
            return nil, nil
        end
    end

    -- Load the image
    local success, image = pcall(love.graphics.newImage, png_path)
    if not success then
        print("SpriteLoader: Failed to load " .. png_path .. ": " .. tostring(image))
        return nil, nil
    end

    -- Load metadata
    local meta = nil
    if love.filesystem.getInfo(json_path) then
        local json_data = love.filesystem.read(json_path)
        if json_data then
            success, meta = pcall(parse_json, json_data)
            if not success then
                print("SpriteLoader: Failed to parse metadata for " .. name)
                meta = nil
            end
        end
    end

    -- If no metadata, create default (single frame)
    if not meta then
        local w, h = image:getDimensions()
        meta = {
            frame_width = w,
            frame_height = h,
            frame_count = 1,
            sheet_width = w,
            sheet_height = h,
            cols = 1,
            rows = 1
        }
    end

    -- Cache the loaded sprite
    self.sheets[name] = image
    self.metadata[name] = meta

    -- Create quads for each frame
    self:create_quads(name)

    return image, meta
end

-- Create Love2D Quads for each frame in a sprite sheet
function SpriteLoader:create_quads(name)
    local image = self.sheets[name]
    local meta = self.metadata[name]

    if not image or not meta then return end

    local quads = {}
    local fw = meta.frame_width
    local fh = meta.frame_height
    local sw = meta.sheet_width
    local sh = meta.sheet_height
    local cols = meta.cols

    for i = 0, meta.frame_count - 1 do
        local col = i % cols
        local row = math.floor(i / cols)
        local x = col * fw
        local y = row * fh

        quads[i] = love.graphics.newQuad(x, y, fw, fh, sw, sh)
    end

    self.quads[name] = quads
end

-- Get a specific frame quad
function SpriteLoader:get_quad(name, frame)
    name = normalize_name(name)
    if not name then return nil end

    -- Ensure sprite is loaded
    if not self.quads[name] then
        self:load(name)
    end

    local quads = self.quads[name]
    if not quads then return nil end

    frame = frame or 0
    return quads[frame]
end

-- Get sprite sheet image
function SpriteLoader:get_sheet(name)
    name = normalize_name(name)
    if not name then return nil end

    if not self.sheets[name] then
        self:load(name)
    end
    return self.sheets[name]
end

-- Get sprite metadata
function SpriteLoader:get_metadata(name)
    name = normalize_name(name)
    if not name then return nil end

    if not self.metadata[name] then
        self:load(name)
    end
    return self.metadata[name]
end

-- Get frame dimensions
function SpriteLoader:get_frame_size(name)
    local meta = self:get_metadata(name)
    if not meta then return 24, 24 end -- Default cell size
    return meta.frame_width, meta.frame_height
end

-- Get total frame count
function SpriteLoader:get_frame_count(name)
    local meta = self:get_metadata(name)
    if not meta then return 1 end
    return meta.frame_count
end

-- Draw a sprite at position with specific frame
function SpriteLoader:draw(name, x, y, frame, rotation, scale_x, scale_y, origin_x, origin_y)
    name = normalize_name(name)
    if not name then return false end

    local sheet = self:get_sheet(name)
    local quad = self:get_quad(name, frame or 0)

    if not sheet or not quad then
        return false
    end

    rotation = rotation or 0
    scale_x = scale_x or 1
    scale_y = scale_y or 1

    -- Default origin to center of frame
    if not origin_x or not origin_y then
        local meta = self:get_metadata(name)
        origin_x = origin_x or (meta.frame_width / 2)
        origin_y = origin_y or (meta.frame_height / 2)
    end

    love.graphics.draw(sheet, quad, x, y, rotation, scale_x, scale_y, origin_x, origin_y)
    return true
end

-- Preload all sprites in a category
function SpriteLoader:preload_category(category)
    local path = self.base_path .. category
    local files = love.filesystem.getDirectoryItems(path)

    local loaded = 0
    for _, file in ipairs(files) do
        if file:match("%.png$") and not file:match("%.png%.json$") then
            local name = file:gsub("%.png$", "")
            if self:load(name) then
                loaded = loaded + 1
            end
        end
    end

    return loaded
end

-- Preload all sprites
function SpriteLoader:preload_all()
    local total = 0
    for _, category in ipairs(self.categories) do
        total = total + self:preload_category(category)
    end
    print("SpriteLoader: Preloaded " .. total .. " sprite sheets")
    return total
end

-- Clear cache (for reloading)
function SpriteLoader:clear_cache()
    self.sheets = {}
    self.metadata = {}
    self.quads = {}
end

-- Check if a sprite exists
function SpriteLoader:exists(name)
    name = normalize_name(name)
    if not name then return false end

    if self.sheets[name] then return true end

    for _, category in ipairs(self.categories) do
        local test_path = self.base_path .. category .. "/" .. name .. ".png"
        if love.filesystem.getInfo(test_path) then
            return true
        end
    end

    return false
end

return SpriteLoader
