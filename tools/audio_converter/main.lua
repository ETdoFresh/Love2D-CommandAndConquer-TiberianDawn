--[[
    Audio Converter Tool
    Converts C&C AUD files to WAV format

    Usage: lua main.lua <input.aud> <output.wav>

    Supports:
    - Westwood WS ADPCM (8-bit)
    - IMA ADPCM (16-bit)
]]

local AudParser = require("tools.audio_converter.aud_parser")
local WavWriter = require("tools.audio_converter.wav_writer")

local function main(args)
    if #args < 2 then
        print("Audio Converter for C&C Tiberian Dawn")
        print("======================================")
        print("")
        print("Usage: lua main.lua <input.aud> <output.wav>")
        print("")
        print("Converts Westwood Studios AUD audio files to WAV format.")
        print("")
        print("Examples:")
        print("  lua main.lua AWAIT1.AUD await1.wav")
        print("  lua main.lua APTS.AUD airstrike_ready.wav")
        return 1
    end

    local input_aud = args[1]
    local output_wav = args[2]

    print("Audio Converter for C&C Tiberian Dawn")
    print("======================================")
    print("")
    print("Input AUD:  " .. input_aud)
    print("Output WAV: " .. output_wav)
    print("")

    -- Load AUD file
    print("Loading AUD file...")
    local file = io.open(input_aud, "rb")
    if not file then
        print("Error: Could not open AUD file: " .. input_aud)
        return 1
    end

    local data = file:read("*all")
    file:close()

    print("  File size: " .. #data .. " bytes")

    -- Parse and decode
    print("Decoding audio...")
    local aud_data, err = AudParser.decode(data)
    if not aud_data then
        print("Error decoding AUD: " .. (err or "Unknown error"))
        return 1
    end

    local header = aud_data.header
    print("  Sample rate: " .. header.sample_rate .. " Hz")
    print("  Channels:    " .. header.channels)
    print("  Bit depth:   " .. header.bits_per_sample .. "-bit")
    print("  Codec:       " .. (header.codec == 1 and "WS ADPCM" or "IMA ADPCM"))
    print("  Samples:     " .. #aud_data.samples)

    local duration = #aud_data.samples / header.sample_rate / header.channels
    print("  Duration:    " .. string.format("%.2f", duration) .. " seconds")
    print("")

    -- Write WAV file
    print("Writing WAV file...")
    local success, write_err = WavWriter.write_from_aud(output_wav, aud_data)
    if not success then
        print("Error writing WAV: " .. (write_err or "Unknown error"))
        return 1
    end

    print("  Wrote: " .. output_wav)
    print("")
    print("Done!")
    return 0
end

-- Run if executed directly
if arg then
    os.exit(main(arg))
end

return {
    main = main
}
