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
    - Frame data (RLE/LCW compressed)

    Frame formats:
    - 0x00: Uncompressed
    - 0x20: RLE compressed
    - 0x40: LCW compressed
    - 0x80: XOR delta (references previous frame)
]]

local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

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

--[[
    LCW Decompression (Format 80)
    Reference: CnCTDRAMapEditor/Utility/WWCompression.cs LcwDecompress

    Command codes:
    - 0b0xxxxxxx: Short copy from output buffer (relative offset)
    - 0x80:       End of stream
    - 0b10xxxxxx: Copy raw bytes from input
    - 0b11xxxxxx: Medium copy from output buffer
    - 0xFE:       Long RLE fill
    - 0xFF:       Long copy from output buffer
]]
local function lcw_decompress(data, pos, output_size)
    local output = {}
    for i = 1, output_size do
        output[i] = 0
    end

    local write_pos = 1
    local read_pos = pos
    local data_len = #data

    while write_pos <= output_size and read_pos <= data_len do
        local flag = data:byte(read_pos)
        read_pos = read_pos + 1

        if band(flag, 0x80) ~= 0 then
            -- High bit set
            if band(flag, 0x40) ~= 0 then
                -- 0b11xxxxxx commands
                local cpysize = band(flag, 0x3F) + 3

                if flag == 0xFE then
                    -- Long RLE fill: 0xFE + length(2) + value(1)
                    if read_pos + 2 > data_len then break end
                    cpysize = data:byte(read_pos) + data:byte(read_pos + 1) * 256
                    read_pos = read_pos + 2
                    local value = data:byte(read_pos)
                    read_pos = read_pos + 1

                    cpysize = math.min(cpysize, output_size - write_pos + 1)
                    for i = 1, cpysize do
                        output[write_pos] = value
                        write_pos = write_pos + 1
                    end

                elseif flag == 0xFF then
                    -- Long copy from output: 0xFF + length(2) + offset(2)
                    -- Offset is ABSOLUTE from start of output buffer
                    if read_pos + 3 > data_len then break end
                    cpysize = data:byte(read_pos) + data:byte(read_pos + 1) * 256
                    read_pos = read_pos + 2
                    local offset = data:byte(read_pos) + data:byte(read_pos + 1) * 256
                    read_pos = read_pos + 2

                    -- Absolute offset from start (1-based in Lua)
                    local src_pos = offset + 1

                    cpysize = math.min(cpysize, output_size - write_pos + 1)
                    for i = 1, cpysize do
                        if src_pos >= 1 and src_pos <= output_size then
                            output[write_pos] = output[src_pos]
                        end
                        write_pos = write_pos + 1
                        src_pos = src_pos + 1
                    end

                else
                    -- Medium copy from output: 0b11xxxxxx + offset(2)
                    -- Offset is ABSOLUTE from start of output buffer
                    if read_pos + 1 > data_len then break end
                    local offset = data:byte(read_pos) + data:byte(read_pos + 1) * 256
                    read_pos = read_pos + 2

                    -- Absolute offset from start (1-based in Lua)
                    local src_pos = offset + 1

                    cpysize = math.min(cpysize, output_size - write_pos + 1)
                    for i = 1, cpysize do
                        if src_pos >= 1 and src_pos <= output_size then
                            output[write_pos] = output[src_pos]
                        end
                        write_pos = write_pos + 1
                        src_pos = src_pos + 1
                    end
                end
            else
                -- 0b10xxxxxx commands
                if flag == 0x80 then
                    -- End of stream
                    break
                end

                -- Copy from input: copy (flag & 0x3F) bytes directly
                -- Note: Count is x, not x+1 (checked against original asm)
                local cpysize = band(flag, 0x3F)
                if cpysize == 0 then cpysize = 64 end  -- 0 means 64
                cpysize = math.min(cpysize, output_size - write_pos + 1)
                for i = 1, cpysize do
                    if read_pos <= data_len then
                        output[write_pos] = data:byte(read_pos)
                        read_pos = read_pos + 1
                        write_pos = write_pos + 1
                    end
                end
            end
        else
            -- 0b0xxxxxxx: Short RELATIVE copy from output
            -- n=0xxxyyyy,yyyyyyyy: back y bytes and run x+3
            local cpysize = rshift(flag, 4) + 3
            if read_pos > data_len then break end
            local offset = lshift(band(flag, 0x0F), 8) + data:byte(read_pos)
            read_pos = read_pos + 1

            cpysize = math.min(cpysize, output_size - write_pos + 1)
            for i = 1, cpysize do
                local src_pos = write_pos - offset
                if src_pos >= 1 and src_pos <= output_size then
                    output[write_pos] = output[src_pos]
                end
                write_pos = write_pos + 1
            end
        end
    end

    return output
end

--[[
    XOR Delta Decompression (Format 40)
    Applies XOR differences to a base frame

    Command codes:
    - 0x00:       End marker (when followed by 0x00 0x00) or XOR fill
    - 0x01-0x7F:  XOR next N bytes
    - 0x80:       Extended command prefix
    - 0x81-0xFF:  Skip N-0x80 bytes
]]
local function xor_decompress(data, pos, base_frame, output_size)
    local output = {}
    -- Copy base frame
    for i = 1, output_size do
        output[i] = base_frame[i] or 0
    end

    local write_pos = 1
    local read_pos = pos
    local data_len = #data

    while write_pos <= output_size and read_pos <= data_len do
        local cmd = data:byte(read_pos)
        read_pos = read_pos + 1

        if cmd == 0 then
            -- 0x00: Could be end marker or XOR fill
            if read_pos > data_len then break end
            local next_byte = data:byte(read_pos)

            if next_byte == 0 then
                -- End marker: 0x00 0x00
                break
            else
                -- XOR fill: 0x00 + count + value
                read_pos = read_pos + 1
                if read_pos > data_len then break end
                local count = next_byte
                local value = data:byte(read_pos)
                read_pos = read_pos + 1

                for i = 1, count do
                    if write_pos <= output_size then
                        output[write_pos] = bxor(output[write_pos], value)
                        write_pos = write_pos + 1
                    end
                end
            end

        elseif cmd >= 1 and cmd <= 0x7F then
            -- XOR next cmd bytes
            for i = 1, cmd do
                if read_pos <= data_len and write_pos <= output_size then
                    output[write_pos] = bxor(output[write_pos], data:byte(read_pos))
                    read_pos = read_pos + 1
                    write_pos = write_pos + 1
                end
            end

        elseif cmd == 0x80 then
            -- Extended command
            if read_pos + 1 > data_len then break end
            local count_lo = data:byte(read_pos)
            local count_hi = data:byte(read_pos + 1)
            read_pos = read_pos + 2

            if count_lo == 0 and count_hi == 0 then
                -- End marker: 0x80 0x00 0x00
                break
            end

            local count = count_lo + band(count_hi, 0x3F) * 256
            local cmd_type = band(count_hi, 0xC0)

            if cmd_type == 0x00 or cmd_type == 0x80 then
                -- Extended skip (0x00) or extended XOR (0x80)
                if cmd_type == 0x00 then
                    -- Skip
                    write_pos = write_pos + count
                else
                    -- XOR next count bytes
                    for i = 1, count do
                        if read_pos <= data_len and write_pos <= output_size then
                            output[write_pos] = bxor(output[write_pos], data:byte(read_pos))
                            read_pos = read_pos + 1
                            write_pos = write_pos + 1
                        end
                    end
                end
            elseif cmd_type == 0xC0 then
                -- Extended XOR fill
                if read_pos > data_len then break end
                local value = data:byte(read_pos)
                read_pos = read_pos + 1

                for i = 1, count do
                    if write_pos <= output_size then
                        output[write_pos] = bxor(output[write_pos], value)
                        write_pos = write_pos + 1
                    end
                end
            else
                -- cmd_type == 0x40: Extended skip (alternate)
                write_pos = write_pos + count
            end

        else
            -- 0x81-0xFF: Skip (cmd - 0x80) bytes
            local skip = cmd - 0x80
            write_pos = write_pos + skip
        end
    end

    return output
end

-- Parse SHP file (Tiberian Dawn format)
-- Based on: https://moddingwiki.shikadi.net/wiki/Westwood_SHP_Format_(TD)
--
-- Header (14 bytes):
--   Frames (2 bytes) - Number of frames
--   XPos (2 bytes) - X offset (ignored)
--   YPos (2 bytes) - Y offset (ignored)
--   Width (2 bytes) - Width of frames
--   Height (2 bytes) - Height of frames
--   DeltaSize (2 bytes) - Largest decompression buffer needed
--   Flags (2 bytes) - Palette and option flags
--
-- Frame Table (8 bytes per entry, Frames+2 entries):
--   DataOffset (3 bytes) - Points to compressed frame data
--   DataFormat (1 byte) - 0x80=LCW, 0x40=XOR Base, 0x20=XOR Chain
--   ReferenceOffset (3 bytes) - Referenced frame offset or frame number
--   ReferenceFormat (1 byte) - Reference compression format
function ShpParser.parse(data)
    if #data < 14 then
        return nil, "File too small"
    end

    local pos = 1
    local shp = {}

    -- Read header
    shp.frame_count, pos = read_uint16(data, pos)
    shp.x_pos, pos = read_uint16(data, pos)
    shp.y_pos, pos = read_uint16(data, pos)
    shp.width, pos = read_uint16(data, pos)
    shp.height, pos = read_uint16(data, pos)
    shp.delta_size, pos = read_uint16(data, pos)
    shp.flags, pos = read_uint16(data, pos)

    -- Validate
    if shp.frame_count == 0 or shp.frame_count > 2000 then
        return nil, "Invalid frame count: " .. shp.frame_count
    end

    if shp.width == 0 or shp.width > 1024 or shp.height == 0 or shp.height > 1024 then
        return nil, "Invalid dimensions: " .. shp.width .. "x" .. shp.height
    end

    -- Read frame table (8 bytes per entry, Frames+2 entries)
    shp.frames = {}
    for i = 1, shp.frame_count + 2 do
        local data_offset, data_format, ref_offset, ref_format

        data_offset, pos = read_uint24(data, pos)
        data_format = data:byte(pos)
        pos = pos + 1
        ref_offset, pos = read_uint24(data, pos)
        ref_format = data:byte(pos)
        pos = pos + 1

        if i <= shp.frame_count then
            shp.frames[i] = {
                offset = data_offset + 1,  -- Convert to 1-based
                format = data_format,
                ref_offset = ref_offset,
                ref_format = ref_format
            }
        end
    end

    -- Store raw data for frame extraction
    shp.raw_data = data

    return shp
end

-- Decode a single frame to pixel data
-- prev_frame: previous frame's pixels (needed for XOR delta format)
-- Format: 0x80=LCW, 0x40=XOR Base (refs LCW frame), 0x20=XOR Chain (refs XOR Base)
function ShpParser.decode_frame(shp, frame_index, prev_frame)
    if frame_index < 1 or frame_index > shp.frame_count then
        return nil, "Invalid frame index"
    end

    local frame = shp.frames[frame_index]
    local data = shp.raw_data
    local width = shp.width
    local height = shp.height
    local pixel_count = width * height

    -- Create pixel buffer (palette indices)
    local pixels = {}
    for i = 1, pixel_count do
        pixels[i] = 0  -- Transparent by default
    end

    local format = frame.format or 0

    if format == 0x80 then
        -- LCW compressed frame
        pixels = lcw_decompress(data, frame.offset, pixel_count)
    elseif format == 0x40 or format == 0x20 then
        -- XOR frames (0x40 = XOR Base, 0x20 = XOR Chain)
        if prev_frame then
            pixels = xor_decompress(data, frame.offset, prev_frame, pixel_count)
        end
    elseif format == 0x00 then
        -- Uncompressed (raw pixel data)
        local pos = frame.offset
        for i = 1, pixel_count do
            if pos <= #data then
                pixels[i] = data:byte(pos)
                pos = pos + 1
            end
        end
    else
        -- Unknown format - try LCW as fallback
        pixels = lcw_decompress(data, frame.offset, pixel_count)
    end

    return pixels, nil
end

-- Legacy decode function kept for compatibility - redirects to new format
function ShpParser.decode_frame_legacy(shp, frame_index, prev_frame)
    if frame_index < 1 or frame_index > shp.frame_count then
        return nil, "Invalid frame index"
    end

    local frame = shp.frames[frame_index]
    local data = shp.raw_data
    local width = shp.width
    local height = shp.height
    local pixel_count = width * height

    -- Create pixel buffer (palette indices)
    local pixels = {}
    for i = 1, pixel_count do
        pixels[i] = 0  -- Transparent by default
    end

    -- Get frame format (old style)
    local format = frame.format or 0

    if format == 0x80 then
        -- Format 80: XOR with previous frame
        if prev_frame then
            pixels = xor_decompress(data, frame.offset, prev_frame, pixel_count)
        end
        return pixels, nil

    elseif format == 0x40 then
        -- Format 40: LCW compressed
        pixels = lcw_decompress(data, frame.offset, pixel_count)
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
