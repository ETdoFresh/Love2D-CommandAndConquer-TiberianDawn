--[[
    Palette Handling for C&C Sprites
    Supports 256-color VGA palettes (.PAL files)
]]

local Palette = {}
Palette.__index = Palette

-- Create a new palette
function Palette.new()
    local self = setmetatable({}, Palette)
    self.colors = {}
    for i = 0, 255 do
        self.colors[i] = {r = 0, g = 0, b = 0}
    end
    return self
end

-- Load palette from PAL file (768 bytes, 256 * 3 RGB values)
function Palette.load_pal(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return nil, "Could not open palette file: " .. filepath
    end

    local data = file:read("*all")
    file:close()

    if #data < 768 then
        return nil, "Invalid palette file size: " .. #data
    end

    local pal = Palette.new()

    for i = 0, 255 do
        local pos = i * 3 + 1
        local r, g, b = data:byte(pos, pos + 2)

        -- C&C palettes use 6-bit color (0-63), scale to 8-bit (0-255)
        pal.colors[i] = {
            r = math.floor(r * 255 / 63),
            g = math.floor(g * 255 / 63),
            b = math.floor(b * 255 / 63)
        }
    end

    return pal
end

-- Load palette from raw data
function Palette.from_data(data)
    if #data < 768 then
        return nil, "Invalid palette data size"
    end

    local pal = Palette.new()

    for i = 0, 255 do
        local pos = i * 3 + 1
        local r, g, b = data:byte(pos, pos + 2)

        pal.colors[i] = {
            r = math.floor(r * 255 / 63),
            g = math.floor(g * 255 / 63),
            b = math.floor(b * 255 / 63)
        }
    end

    return pal
end

-- Get color at index
function Palette:get_color(index)
    return self.colors[index] or {r = 0, g = 0, b = 0}
end

-- Get RGBA values (with optional alpha override)
function Palette:get_rgba(index, alpha)
    local c = self.colors[index] or {r = 0, g = 0, b = 0}
    return c.r, c.g, c.b, alpha or 255
end

-- Check if color index is transparent (index 0 is typically transparent)
function Palette:is_transparent(index)
    return index == 0
end

-- Apply house/player color remap
-- Remaps palette indices 80-95 to a different color range
function Palette:apply_remap(remap_table)
    local new_pal = Palette.new()

    for i = 0, 255 do
        if remap_table[i] then
            new_pal.colors[i] = self.colors[remap_table[i]]
        else
            new_pal.colors[i] = self.colors[i]
        end
    end

    return new_pal
end

-- Create a default/fallback palette (grayscale)
function Palette.create_grayscale()
    local pal = Palette.new()
    for i = 0, 255 do
        pal.colors[i] = {r = i, g = i, b = i}
    end
    return pal
end

-- Create a rainbow test palette
function Palette.create_rainbow()
    local pal = Palette.new()
    for i = 0, 255 do
        local h = i / 256
        local r, g, b = Palette.hsv_to_rgb(h, 1, 1)
        pal.colors[i] = {
            r = math.floor(r * 255),
            g = math.floor(g * 255),
            b = math.floor(b * 255)
        }
    end
    return pal
end

-- HSV to RGB conversion helper
function Palette.hsv_to_rgb(h, s, v)
    if s == 0 then
        return v, v, v
    end

    h = h * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))

    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q
    end
end

-- Player color remap tables (for GDI gold, Nod red, etc.)
Palette.REMAP = {
    -- Gold (GDI default)
    GOLD = {},
    -- Red (Nod default)
    RED = {},
    -- Light Blue
    LTBLUE = {},
    -- Green
    GREEN = {},
    -- Orange
    ORANGE = {},
    -- Blue
    BLUE = {}
}

-- Build remap tables (indices 80-95 are remapped)
local function build_remap_tables()
    -- These are approximations; actual remaps would come from game data
    for i = 80, 95 do
        Palette.REMAP.GOLD[i] = i  -- No change (gold is default)
        Palette.REMAP.RED[i] = i + 16
        Palette.REMAP.LTBLUE[i] = i + 32
        Palette.REMAP.GREEN[i] = i + 48
        Palette.REMAP.ORANGE[i] = i + 64
        Palette.REMAP.BLUE[i] = i + 80
    end
end

build_remap_tables()

return Palette
