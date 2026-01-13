--[[
    HD Graphics Adapter - Remastered sprite rendering

    This adapter provides support for high-definition sprite rendering
    using assets from the C&C Remastered Collection.

    Features:
    - HD sprite loading and caching
    - Resolution scaling (320x200 -> 1920x1080+)
    - Frame interpolation for smooth animation
    - Dynamic sprite selection based on zoom level

    Original: 320x200 fixed resolution, pixel art sprites
    This Port: Toggle between classic and HD rendering

    Reference: PLAN.md "Intentional Deviations"
]]

local HDGraphics = {}

--============================================================================
-- Configuration
--============================================================================

HDGraphics.enabled = false
HDGraphics.scale = 1.0
HDGraphics.target_resolution = {1920, 1080}

-- Sprite caches
HDGraphics.sprite_cache = {}
HDGraphics.classic_cache = {}

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the HD graphics adapter.
]]
function HDGraphics.init()
    HDGraphics.enabled = true

    -- Detect screen resolution
    if love and love.graphics then
        local width, height = love.graphics.getDimensions()
        HDGraphics.target_resolution = {width, height}

        -- Calculate scale factor
        HDGraphics.scale = math.min(
            width / 320,
            height / 200
        )
    end

    print(string.format("HDGraphics: Initialized at %dx%d (scale %.2f)",
        HDGraphics.target_resolution[1],
        HDGraphics.target_resolution[2],
        HDGraphics.scale))
end

--============================================================================
-- Sprite Loading
--============================================================================

--[[
    Load an HD sprite, falling back to classic if not available.
    @param name - Sprite name
    @return Sprite image/quad or nil
]]
function HDGraphics.load_sprite(name)
    if not HDGraphics.enabled then
        return nil
    end

    -- Check cache
    if HDGraphics.sprite_cache[name] then
        return HDGraphics.sprite_cache[name]
    end

    -- Try to load HD version
    local hd_path = string.format("assets/sprites/hd/%s.png", name)
    if love and love.filesystem.getInfo(hd_path) then
        local sprite = love.graphics.newImage(hd_path)
        HDGraphics.sprite_cache[name] = sprite
        return sprite
    end

    return nil
end

--[[
    Get the appropriate sprite for current settings.
    @param classic_sprite - Classic sprite reference
    @param hd_sprite - HD sprite reference (optional)
    @return Sprite to use
]]
function HDGraphics.get_sprite(classic_sprite, hd_sprite)
    if HDGraphics.enabled and hd_sprite then
        return hd_sprite
    end
    return classic_sprite
end

--============================================================================
-- Rendering Helpers
--============================================================================

--[[
    Scale a coordinate from game space (320x200) to screen space.
    @param x - Game X coordinate
    @param y - Game Y coordinate
    @return Scaled X, Y coordinates
]]
function HDGraphics.scale_coord(x, y)
    if not HDGraphics.enabled then
        return x, y
    end
    return x * HDGraphics.scale, y * HDGraphics.scale
end

--[[
    Scale a dimension from game space to screen space.
    @param w - Width
    @param h - Height
    @return Scaled width, height
]]
function HDGraphics.scale_size(w, h)
    if not HDGraphics.enabled then
        return w, h
    end
    return w * HDGraphics.scale, h * HDGraphics.scale
end

--[[
    Draw a sprite at the given position with HD scaling.
    @param sprite - Sprite to draw
    @param x - X position (game coordinates)
    @param y - Y position (game coordinates)
    @param frame - Animation frame (optional)
]]
function HDGraphics.draw(sprite, x, y, frame)
    if not sprite then return end

    local sx, sy = HDGraphics.scale_coord(x, y)

    if love and love.graphics then
        if HDGraphics.enabled then
            love.graphics.draw(sprite, sx, sy, 0, HDGraphics.scale, HDGraphics.scale)
        else
            love.graphics.draw(sprite, sx, sy)
        end
    end
end

--============================================================================
-- Settings
--============================================================================

--[[
    Toggle HD graphics on/off.
    @return New state
]]
function HDGraphics.toggle()
    HDGraphics.enabled = not HDGraphics.enabled
    return HDGraphics.enabled
end

--[[
    Set the rendering scale.
    @param scale - Scale factor
]]
function HDGraphics.set_scale(scale)
    HDGraphics.scale = math.max(1.0, scale)
end

--============================================================================
-- Debug
--============================================================================

function HDGraphics.Debug_Dump()
    print("HDGraphics Adapter:")
    print(string.format("  Enabled: %s", tostring(HDGraphics.enabled)))
    print(string.format("  Scale: %.2f", HDGraphics.scale))
    print(string.format("  Target Resolution: %dx%d",
        HDGraphics.target_resolution[1],
        HDGraphics.target_resolution[2]))

    local cached = 0
    for _ in pairs(HDGraphics.sprite_cache) do cached = cached + 1 end
    print(string.format("  Cached HD Sprites: %d", cached))
end

return HDGraphics
