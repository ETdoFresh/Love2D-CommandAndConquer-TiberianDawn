--[[
    MIX File Format Parser
    Reference: MIXFILE.H from C&C Remastered Collection

    MIX files are archive files containing game assets.
    Format:
    - 2 bytes: file count
    - 4 bytes: body size
    - For each file:
      - 4 bytes: CRC32 of filename (lowercase)
      - 4 bytes: offset from body start
      - 4 bytes: file size
    - Body: raw file data
]]

local MixFormat = {}

-- C&C Tiberian Dawn uses a rolling hash for filename lookup
-- Reference: OpenRA PackageEntry.cs HashFilename function
-- Algorithm: Pad to 4-byte boundary, uppercase, then for each 4-byte chunk (little-endian),
-- rotate result left by 1 and add chunk value
function MixFormat.crc(str)
    str = str:upper()  -- C&C uses uppercase filenames

    -- Pad string to multiple of 4 bytes with null characters
    local padding = (4 - (#str % 4)) % 4
    local padded = str .. string.rep("\0", padding)

    local result = 0

    -- Process 4 bytes at a time (little-endian order - x86 memory layout)
    for i = 1, #padded, 4 do
        local b1 = padded:byte(i) or 0
        local b2 = padded:byte(i + 1) or 0
        local b3 = padded:byte(i + 2) or 0
        local b4 = padded:byte(i + 3) or 0

        -- Little-endian 32-bit value (as read from x86 memory)
        local chunk = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216

        -- Rotate left by 1: (result << 1) | (result >> 31)
        -- Use bor to combine shifted parts for proper rotation
        local rotated = bit.bor(bit.lshift(result, 1), bit.rshift(result, 31))
        -- Mask to 32-bit before addition to avoid overflow
        rotated = bit.band(rotated, 0xFFFFFFFF)
        -- Add chunk and mask to 32-bit
        result = bit.band(rotated + chunk, 0xFFFFFFFF)
    end

    -- Convert to unsigned (mask off sign extension)
    if result < 0 then
        result = result + 0x100000000
    end

    return result
end

-- Legacy alias for compatibility
MixFormat.crc32 = MixFormat.crc

-- Read a little-endian 16-bit unsigned integer
local function read_uint16(file)
    local b1, b2 = file:read(2):byte(1, 2)
    return b1 + b2 * 256
end

-- Read a little-endian 32-bit unsigned integer
local function read_uint32(file)
    local b1, b2, b3, b4 = file:read(4):byte(1, 4)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Parse MIX file header and return file entries
function MixFormat.parse(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    -- Check for encrypted/new format flag
    local first_bytes = file:read(4)
    file:seek("set", 0)

    local is_new_format = false
    local header_offset = 0

    -- Check for TD/RA MIX format (first 2 bytes are file count)
    local b1, b2 = first_bytes:byte(1, 2)
    local potential_count = b1 + b2 * 256

    if potential_count == 0 or potential_count > 10000 then
        -- Possibly encrypted or new format
        is_new_format = true
        header_offset = 4  -- Skip flags
        file:seek("set", 4)
    end

    -- Read header
    local file_count = read_uint16(file)
    local body_size = read_uint32(file)

    -- Validate
    if file_count == 0 or file_count > 10000 then
        file:close()
        return nil, "Invalid file count: " .. file_count
    end

    -- Read file entries
    local entries = {}
    local header_size = 6 + (file_count * 12)

    for i = 1, file_count do
        local crc = read_uint32(file)
        local offset = read_uint32(file)
        local size = read_uint32(file)

        entries[i] = {
            crc = crc,
            offset = offset + header_offset + header_size,  -- Absolute offset
            size = size,
            index = i
        }
    end

    -- Sort by offset for sequential reading
    table.sort(entries, function(a, b) return a.offset < b.offset end)

    local result = {
        filepath = filepath,
        file = file,
        file_count = file_count,
        body_size = body_size,
        header_size = header_size,
        entries = entries,
        entries_by_crc = {}
    }

    -- Build CRC lookup
    for _, entry in ipairs(entries) do
        result.entries_by_crc[entry.crc] = entry
    end

    return result
end

-- Extract a file by CRC
function MixFormat.extract_by_crc(mix, crc)
    local entry = mix.entries_by_crc[crc]
    if not entry then
        return nil, "File not found with CRC: " .. string.format("0x%08X", crc)
    end

    mix.file:seek("set", entry.offset)
    local data = mix.file:read(entry.size)

    return data, entry
end

-- Extract a file by filename
function MixFormat.extract_by_name(mix, filename)
    local crc = MixFormat.crc(filename)
    return MixFormat.extract_by_crc(mix, crc)
end

-- Extract all files to a directory
function MixFormat.extract_all(mix, output_dir, name_lookup)
    name_lookup = name_lookup or {}

    local extracted = {}

    for _, entry in ipairs(mix.entries) do
        mix.file:seek("set", entry.offset)
        local data = mix.file:read(entry.size)

        -- Try to find filename from lookup
        local filename = name_lookup[entry.crc]
        if not filename then
            filename = string.format("unknown_%08X.bin", entry.crc)
        end

        local output_path = output_dir .. "/" .. filename
        local out_file = io.open(output_path, "wb")
        if out_file then
            out_file:write(data)
            out_file:close()
            table.insert(extracted, {
                filename = filename,
                crc = entry.crc,
                size = entry.size
            })
        end
    end

    return extracted
end

-- Close MIX file
function MixFormat.close(mix)
    if mix and mix.file then
        mix.file:close()
        mix.file = nil
    end
end

-- List all files in MIX
function MixFormat.list(mix, name_lookup)
    name_lookup = name_lookup or {}
    local list = {}

    for _, entry in ipairs(mix.entries) do
        local filename = name_lookup[entry.crc] or string.format("0x%08X", entry.crc)
        table.insert(list, {
            filename = filename,
            crc = entry.crc,
            offset = entry.offset,
            size = entry.size
        })
    end

    return list
end

return MixFormat
