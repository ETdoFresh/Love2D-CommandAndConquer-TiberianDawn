--[[
    WAV File Writer
    Writes audio samples to standard WAV format

    WAV Format:
    - RIFF header (12 bytes)
    - fmt chunk (24 bytes for PCM)
    - data chunk (8 bytes + audio data)

    Reference: Microsoft WAVE specification
]]

local WavWriter = {}

-- Write little-endian 16-bit
local function write_uint16(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256
    )
end

-- Write little-endian 32-bit
local function write_uint32(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

-- Write WAV file from audio data
function WavWriter.write(filepath, samples, sample_rate, channels, bits_per_sample)
    channels = channels or 1
    bits_per_sample = bits_per_sample or 8

    local bytes_per_sample = bits_per_sample / 8
    local block_align = channels * bytes_per_sample
    local byte_rate = sample_rate * block_align
    local data_size = #samples * bytes_per_sample
    local file_size = 36 + data_size  -- Total file size minus 8

    local wav = {}

    -- RIFF header
    table.insert(wav, "RIFF")
    table.insert(wav, write_uint32(file_size))
    table.insert(wav, "WAVE")

    -- fmt chunk
    table.insert(wav, "fmt ")
    table.insert(wav, write_uint32(16))  -- Chunk size
    table.insert(wav, write_uint16(1))   -- Audio format (1 = PCM)
    table.insert(wav, write_uint16(channels))
    table.insert(wav, write_uint32(sample_rate))
    table.insert(wav, write_uint32(byte_rate))
    table.insert(wav, write_uint16(block_align))
    table.insert(wav, write_uint16(bits_per_sample))

    -- data chunk header
    table.insert(wav, "data")
    table.insert(wav, write_uint32(data_size))

    -- Write audio samples
    local sample_data = {}
    for i, sample in ipairs(samples) do
        if bits_per_sample == 8 then
            -- 8-bit WAV is unsigned (0-255)
            local byte_val = math.floor(sample)
            byte_val = math.max(0, math.min(255, byte_val))
            table.insert(sample_data, string.char(byte_val))
        else
            -- 16-bit WAV is signed (-32768 to 32767)
            local int_val = math.floor(sample)
            int_val = math.max(-32768, math.min(32767, int_val))
            -- Convert to unsigned for byte writing
            if int_val < 0 then
                int_val = int_val + 65536
            end
            table.insert(sample_data, write_uint16(int_val))
        end
    end

    table.insert(wav, table.concat(sample_data))

    -- Write file
    local file = io.open(filepath, "wb")
    if not file then
        return false, "Could not open file for writing: " .. filepath
    end

    file:write(table.concat(wav))
    file:close()

    return true
end

-- Write from decoded AUD data structure
function WavWriter.write_from_aud(filepath, aud_data)
    return WavWriter.write(
        filepath,
        aud_data.samples,
        aud_data.sample_rate,
        aud_data.channels,
        aud_data.bits_per_sample
    )
end

return WavWriter
