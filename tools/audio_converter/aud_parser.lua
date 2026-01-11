--[[
    AUD File Parser
    Parses Westwood Studios AUD audio format (C&C Tiberian Dawn)

    AUD Header (12 bytes):
    - 2 bytes: Sample rate (little-endian)
    - 4 bytes: File size (compressed data)
    - 4 bytes: Output size (uncompressed)
    - 1 byte:  Flags (bit 0 = stereo, bit 1 = 16-bit)
    - 1 byte:  Codec type (1 = WS ADPCM, 99 = IMA ADPCM)

    Chunk Header (8 bytes):
    - 2 bytes: Compressed chunk size
    - 2 bytes: Uncompressed chunk size
    - 4 bytes: Signature (0x0000DEAF)

    Reference: FFmpeg westwood.c, MultimediaWiki
]]

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local AudParser = {}

-- Constants
local AUD_HEADER_SIZE = 12
local AUD_CHUNK_PREAMBLE_SIZE = 8
local AUD_CHUNK_SIGNATURE = 0x0000DEAF

-- Codec types
local CODEC_WS_ADPCM = 1
local CODEC_IMA_ADPCM = 99

-- WS ADPCM delta tables
local WS_TABLE_2BIT = {-2, -1, 0, 1}
local WS_TABLE_4BIT = {-9, -8, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 8}

-- IMA ADPCM tables
local IMA_INDEX_TABLE = {
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8
}

local IMA_STEP_TABLE = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
}

-- Read little-endian values
local function read_uint16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    if not b1 or not b2 then return nil end
    return b1 + b2 * 256
end

local function read_uint32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    if not b1 then return nil end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Clamp value to range
local function clamp(val, min_val, max_val)
    if val < min_val then return min_val end
    if val > max_val then return max_val end
    return val
end

-- Parse AUD file header
function AudParser.parse_header(data)
    if #data < AUD_HEADER_SIZE then
        return nil, "File too small for AUD header"
    end

    local header = {}
    header.sample_rate = read_uint16(data, 1)
    header.file_size = read_uint32(data, 3)
    header.output_size = read_uint32(data, 7)
    header.flags = data:byte(11)
    header.codec = data:byte(12)

    -- Parse flags
    header.stereo = band(header.flags, 0x01) ~= 0
    header.is_16bit = band(header.flags, 0x02) ~= 0
    header.channels = header.stereo and 2 or 1
    header.bits_per_sample = header.is_16bit and 16 or 8

    -- Validate
    if header.sample_rate < 4000 or header.sample_rate > 48000 then
        return nil, "Invalid sample rate: " .. header.sample_rate
    end

    if header.codec ~= CODEC_WS_ADPCM and header.codec ~= CODEC_IMA_ADPCM then
        return nil, "Unknown codec type: " .. header.codec
    end

    return header
end

-- Decode WS ADPCM chunk (8-bit audio)
local function decode_ws_adpcm(input, input_pos, output_size)
    local output = {}
    local cur_sample = 0x80  -- Start at midpoint for unsigned 8-bit
    local out_pos = 1
    local in_pos = input_pos

    while out_pos <= output_size and in_pos <= #input do
        local byte = input:byte(in_pos)
        in_pos = in_pos + 1

        local code = rshift(byte, 6)

        if code == 2 then
            -- Raw sample, no delta
            cur_sample = byte
        elseif code == 1 then
            -- 4-bit ADPCM: use low 4 bits as index
            local index = band(byte, 0x0F) + 1
            cur_sample = clamp(cur_sample + WS_TABLE_4BIT[index], 0, 255)
        elseif code == 0 then
            -- 2-bit ADPCM: decode 4 samples from 8 bits
            for i = 0, 3 do
                if out_pos > output_size then break end
                local index = band(rshift(byte, i * 2), 0x03) + 1
                cur_sample = clamp(cur_sample + WS_TABLE_2BIT[index], 0, 255)
                output[out_pos] = cur_sample
                out_pos = out_pos + 1
            end
            -- Continue without adding another sample (already added 4)
            goto continue
        else
            -- code == 3: Repeat current sample (count in low 6 bits + 1)
            local count = band(byte, 0x3F) + 1
            for i = 1, count do
                if out_pos > output_size then break end
                output[out_pos] = cur_sample
                out_pos = out_pos + 1
            end
            goto continue
        end

        output[out_pos] = cur_sample
        out_pos = out_pos + 1

        ::continue::
    end

    return output
end

-- Decode IMA ADPCM nibble
local function decode_ima_nibble(nibble, predictor, step_index)
    local step = IMA_STEP_TABLE[step_index + 1]
    local diff = step * band(nibble, 0x07) / 4 + step / 8

    if band(nibble, 0x08) ~= 0 then
        predictor = predictor - diff
    else
        predictor = predictor + diff
    end

    predictor = clamp(predictor, -32768, 32767)

    step_index = step_index + IMA_INDEX_TABLE[band(nibble, 0x0F) + 1]
    step_index = clamp(step_index, 0, 88)

    return predictor, step_index
end

-- Decode IMA ADPCM chunk (16-bit audio)
local function decode_ima_adpcm(input, input_pos, output_size, channels)
    local output = {}
    local predictors = {0, 0}
    local step_indices = {0, 0}
    local out_pos = 1
    local in_pos = input_pos

    while out_pos <= output_size and in_pos <= #input do
        local byte = input:byte(in_pos)
        in_pos = in_pos + 1

        for nibble_idx = 0, 1 do
            if out_pos > output_size then break end

            local nibble
            if nibble_idx == 0 then
                nibble = band(byte, 0x0F)
            else
                nibble = rshift(byte, 4)
            end

            local ch = ((out_pos - 1) % channels) + 1
            local sample
            sample, step_indices[ch] = decode_ima_nibble(nibble, predictors[ch], step_indices[ch])
            predictors[ch] = sample

            output[out_pos] = sample
            out_pos = out_pos + 1
        end
    end

    return output
end

-- Parse and decode entire AUD file
function AudParser.decode(data)
    local header, err = AudParser.parse_header(data)
    if not header then
        return nil, err
    end

    local samples = {}
    local pos = AUD_HEADER_SIZE + 1

    while pos + AUD_CHUNK_PREAMBLE_SIZE <= #data do
        -- Read chunk header
        local chunk_size = read_uint16(data, pos)
        local out_size = read_uint16(data, pos + 2)
        local signature = read_uint32(data, pos + 5)

        -- Validate signature
        if signature ~= AUD_CHUNK_SIGNATURE then
            -- Some files don't have chunk headers, try raw decode
            break
        end

        pos = pos + AUD_CHUNK_PREAMBLE_SIZE

        if pos + chunk_size > #data + 1 then
            break
        end

        -- Decode chunk
        local chunk_samples
        if header.codec == CODEC_WS_ADPCM then
            chunk_samples = decode_ws_adpcm(data, pos, out_size)
        else
            local sample_count = header.is_16bit and out_size / 2 or out_size
            chunk_samples = decode_ima_adpcm(data, pos, sample_count, header.channels)
        end

        -- Append samples
        for _, s in ipairs(chunk_samples) do
            table.insert(samples, s)
        end

        pos = pos + chunk_size
    end

    -- If no chunks found, try decoding raw data after header
    if #samples == 0 then
        local raw_size = #data - AUD_HEADER_SIZE
        if header.codec == CODEC_WS_ADPCM then
            samples = decode_ws_adpcm(data, AUD_HEADER_SIZE + 1, header.output_size)
        else
            local sample_count = header.is_16bit and header.output_size / 2 or header.output_size
            samples = decode_ima_adpcm(data, AUD_HEADER_SIZE + 1, sample_count, header.channels)
        end
    end

    return {
        header = header,
        samples = samples,
        sample_rate = header.sample_rate,
        channels = header.channels,
        bits_per_sample = header.bits_per_sample
    }
end

return AudParser
