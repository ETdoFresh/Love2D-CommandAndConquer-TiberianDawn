--[[
    Pure Lua PNG Encoder
    Based on lua-pngencoder by wyozi (https://github.com/wyozi/lua-pngencoder)
    Adapted for LuaJIT and C&C sprite conversion

    Usage:
        local PngEncoder = require("tools.sprite_converter.png_encoder")
        local png = PngEncoder.new(width, height)
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                png:write(r, g, b, a)  -- RGBA values 0-255
            end
        end
        local data = png:finish()
        -- write data to file
]]

local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local PngEncoder = {}
PngEncoder.__index = PngEncoder

-- CRC32 lookup table
local crc_table = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if band(c, 1) == 1 then
            c = bxor(rshift(c, 1), 0xEDB88320)
        else
            c = rshift(c, 1)
        end
    end
    crc_table[i] = c
end

-- Calculate CRC32 of data
local function crc32(data, start, length)
    local crc = 0xFFFFFFFF
    for i = start, start + length - 1 do
        local byte = data:byte(i)
        local index = band(bxor(crc, byte), 0xFF)
        crc = bxor(rshift(crc, 8), crc_table[index])
    end
    return bxor(crc, 0xFFFFFFFF)
end

-- Adler32 checksum for zlib
local function adler32(data)
    local s1, s2 = 1, 0
    for i = 1, #data do
        s1 = (s1 + data:byte(i)) % 65521
        s2 = (s2 + s1) % 65521
    end
    return bor(lshift(s2, 16), s1)
end

-- Write big-endian 32-bit integer
local function write_uint32_be(n)
    return string.char(
        band(rshift(n, 24), 0xFF),
        band(rshift(n, 16), 0xFF),
        band(rshift(n, 8), 0xFF),
        band(n, 0xFF)
    )
end

-- Write a PNG chunk
local function write_chunk(chunk_type, data)
    local length = #data
    local chunk = chunk_type .. data
    local crc = crc32(chunk, 1, #chunk)
    return write_uint32_be(length) .. chunk .. write_uint32_be(crc)
end

-- Create new PNG encoder
function PngEncoder.new(width, height)
    local self = setmetatable({}, PngEncoder)
    self.width = width
    self.height = height
    self.row_size = width * 4 + 1  -- RGBA + filter byte
    self.pixels = {}
    self.current_row = {}
    self.current_x = 0
    self.current_y = 0
    return self
end

-- Write RGBA pixel
function PngEncoder:write(r, g, b, a)
    a = a or 255

    -- Start new row with filter byte (0 = no filter)
    if self.current_x == 0 then
        table.insert(self.current_row, 0)
    end

    table.insert(self.current_row, band(r, 0xFF))
    table.insert(self.current_row, band(g, 0xFF))
    table.insert(self.current_row, band(b, 0xFF))
    table.insert(self.current_row, band(a, 0xFF))

    self.current_x = self.current_x + 1

    -- End of row
    if self.current_x >= self.width then
        table.insert(self.pixels, string.char(unpack(self.current_row)))
        self.current_row = {}
        self.current_x = 0
        self.current_y = self.current_y + 1
    end
end

-- Write entire row of RGBA data (table of {r, g, b, a} or flat r, g, b, a values)
function PngEncoder:write_row(pixels)
    -- Add filter byte
    table.insert(self.current_row, 0)

    for i = 1, #pixels do
        table.insert(self.current_row, band(pixels[i], 0xFF))
    end

    table.insert(self.pixels, string.char(unpack(self.current_row)))
    self.current_row = {}
    self.current_y = self.current_y + 1
end

-- Compress data using deflate (store-only, no actual compression for simplicity)
local function deflate_store(data)
    local result = {}
    local pos = 1
    local len = #data

    while pos <= len do
        local block_size = math.min(65535, len - pos + 1)
        local is_final = (pos + block_size > len) and 1 or 0

        -- Block header: BFINAL=is_final, BTYPE=00 (stored)
        table.insert(result, string.char(is_final))

        -- Length and one's complement
        local len_lo = band(block_size, 0xFF)
        local len_hi = band(rshift(block_size, 8), 0xFF)
        local nlen_lo = band(bxor(block_size, 0xFFFF), 0xFF)
        local nlen_hi = band(rshift(bxor(block_size, 0xFFFF), 8), 0xFF)

        table.insert(result, string.char(len_lo, len_hi, nlen_lo, nlen_hi))
        table.insert(result, data:sub(pos, pos + block_size - 1))

        pos = pos + block_size
    end

    return table.concat(result)
end

-- Create zlib wrapper around deflate data
local function zlib_compress(data)
    -- CMF byte: CM=8 (deflate), CINFO=7 (32K window)
    local cmf = 0x78
    -- FLG byte: FCHECK so (CMF*256 + FLG) % 31 == 0, no dict, no level
    local flg = 0x9C

    local compressed = deflate_store(data)
    local checksum = adler32(data)

    return string.char(cmf, flg) .. compressed .. write_uint32_be(checksum)
end

-- Finish encoding and return PNG data
function PngEncoder:finish()
    local result = {}

    -- PNG signature
    table.insert(result, "\137PNG\r\n\026\n")

    -- IHDR chunk
    local ihdr = write_uint32_be(self.width) ..
                 write_uint32_be(self.height) ..
                 string.char(8) ..   -- bit depth
                 string.char(6) ..   -- color type (RGBA)
                 string.char(0) ..   -- compression method
                 string.char(0) ..   -- filter method
                 string.char(0)      -- interlace method
    table.insert(result, write_chunk("IHDR", ihdr))

    -- IDAT chunk (compressed image data)
    local raw_data = table.concat(self.pixels)
    local compressed = zlib_compress(raw_data)
    table.insert(result, write_chunk("IDAT", compressed))

    -- IEND chunk
    table.insert(result, write_chunk("IEND", ""))

    return table.concat(result)
end

-- Convenience function: encode RGBA pixel array to PNG
function PngEncoder.encode(width, height, pixels)
    local png = PngEncoder.new(width, height)

    local idx = 1
    for _ = 1, height do
        for _ = 1, width do
            png:write(pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
            idx = idx + 4
        end
    end

    return png:finish()
end

return PngEncoder
