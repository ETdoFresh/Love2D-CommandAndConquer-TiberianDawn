--[[
    SHP File Parser
    Parses classic C&C SHP sprite format

    SHP Format:
    - 2 bytes: frame count
    - 2 bytes: unknown (0)
    - 2 bytes: unknown
    - 2 bytes: image width
    - 2 bytes: image height
    - 4 bytes: largest frame size
    - For each frame:
      - 3 bytes: offset (24-bit)
      - 1 byte: format flags
    - Frame data (RLE compressed)
]]

local ShpParser = {}

-- Read little-endian 16-bit unsigned
local function read_uint16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    return b1 + b2 * 256, pos + 2
end

-- Read little-endian 24-bit unsigned (for offsets)
local function read_uint24(data, pos)
    local b1, b2, b3 = data:byte(pos, pos + 2)
    return b1 + b2 * 256 + b3 * 65536, pos + 3
end

-- Read little-endian 32-bit unsigned
local function read_uint32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216, pos + 4
end

-- Parse SHP file header
function ShpParser.parse(data)
    if #data < 14 then
        return nil, "File too small"
    end

    local pos = 1
    local shp = {}

    shp.frame_count, pos = read_uint16(data, pos)
    shp.unknown1, pos = read_uint16(data, pos)
    shp.unknown2, pos = read_uint16(data, pos)
    shp.width, pos = read_uint16(data, pos)
    shp.height, pos = read_uint16(data, pos)
    shp.largest_frame, pos = read_uint32(data, pos)

    -- Validate
    if shp.frame_count == 0 or shp.frame_count > 1000 then
        return nil, "Invalid frame count: " .. shp.frame_count
    end

    if shp.width == 0 or shp.width > 1024 or shp.height == 0 or shp.height > 1024 then
        return nil, "Invalid dimensions: " .. shp.width .. "x" .. shp.height
    end

    -- Read frame offsets
    shp.frames = {}
    for i = 1, shp.frame_count do
        local offset, format_byte
        offset, pos = read_uint24(data, pos)
        format_byte = data:byte(pos)
        pos = pos + 1

        shp.frames[i] = {
            offset = offset + 1,  -- Convert to 1-based
            format = format_byte,
            data = nil,
            pixels = nil
        }
    end

    -- Store raw data for frame extraction
    shp.raw_data = data

    return shp
end

-- Decode a single frame to pixel data
function ShpParser.decode_frame(shp, frame_index)
    if frame_index < 1 or frame_index > shp.frame_count then
        return nil, "Invalid frame index"
    end

    local frame = shp.frames[frame_index]
    local data = shp.raw_data
    local width = shp.width
    local height = shp.height

    -- Create pixel buffer (palette indices)
    local pixels = {}
    for i = 1, width * height do
        pixels[i] = 0  -- Transparent by default
    end

    -- Get frame format
    local format = frame.format

    if format == 0x80 then
        -- Format 80: XOR with previous frame (skip for now)
        return pixels, nil
    elseif format == 0x40 then
        -- Format 40: LCW compressed
        -- TODO: Implement LCW decompression
        return pixels, nil
    elseif format == 0x20 then
        -- Format 20: RLE compressed
        local pos = frame.offset
        local pixel_pos = 1

        while pixel_pos <= width * height and pos <= #data do
            local cmd = data:byte(pos)
            pos = pos + 1

            if cmd == 0 then
                -- End of line or end of data
                -- Skip to next row
                local current_row = math.floor((pixel_pos - 1) / width)
                pixel_pos = (current_row + 1) * width + 1
            elseif cmd >= 1 and cmd <= 127 then
                -- Copy cmd bytes directly
                for j = 1, cmd do
                    if pixel_pos <= width * height and pos <= #data then
                        pixels[pixel_pos] = data:byte(pos)
                        pos = pos + 1
                        pixel_pos = pixel_pos + 1
                    end
                end
            else
                -- RLE: repeat next byte (cmd - 128) times
                local count = cmd - 128
                local value = data:byte(pos)
                pos = pos + 1
                for j = 1, count do
                    if pixel_pos <= width * height then
                        pixels[pixel_pos] = value
                        pixel_pos = pixel_pos + 1
                    end
                end
            end
        end

        return pixels, nil
    else
        -- Format 00: Uncompressed
        local pos = frame.offset
        for i = 1, width * height do
            if pos <= #data then
                pixels[i] = data:byte(pos)
                pos = pos + 1
            end
        end
        return pixels, nil
    end
end

-- Get frame dimensions
function ShpParser.get_dimensions(shp)
    return shp.width, shp.height
end

-- Get frame count
function ShpParser.get_frame_count(shp)
    return shp.frame_count
end

return ShpParser
