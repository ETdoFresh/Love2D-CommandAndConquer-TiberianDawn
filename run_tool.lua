--[[
    Tool Runner for Love2D
    Runs asset extraction tools from command line

    Usage:
        love . extract <mix_file> <output_dir>
        love . convert-shp <shp_file> <pal_file> <output.png>
        love . convert-aud <aud_file> <output.wav>
]]

local ToolRunner = {}

function ToolRunner.extract_mix(mix_path, output_dir)
    print("MIX Extractor for C&C Tiberian Dawn")
    print("====================================")
    print("")

    local MixFormat = require("tools.mix_extractor.mix_format")
    local CrcLookup = require("tools.mix_extractor.crc_lookup")

    print("Input:  " .. mix_path)
    print("Output: " .. output_dir)
    print("")

    -- Parse MIX file
    print("Parsing MIX file...")
    local mix, err = MixFormat.parse(mix_path)
    if not mix then
        print("Error: " .. err)
        return false
    end

    print("Found " .. mix.file_count .. " files")
    print("")

    -- Create output directory
    love.filesystem.createDirectory(output_dir)
    -- Also try OS level for absolute paths
    os.execute('mkdir "' .. output_dir .. '" 2>nul')

    -- Extract all files
    print("Extracting files...")
    local extracted = MixFormat.extract_all(mix, output_dir, CrcLookup.BY_CRC)

    print("")
    print("Extracted " .. #extracted .. " files:")
    local shown = 0
    for _, file in ipairs(extracted) do
        if shown < 30 then
            print("  " .. file.filename .. " (" .. file.size .. " bytes)")
            shown = shown + 1
        end
    end
    if #extracted > 30 then
        print("  ... and " .. (#extracted - 30) .. " more")
    end

    MixFormat.close(mix)

    print("")
    print("Done!")
    return true
end

function ToolRunner.convert_shp(shp_path, pal_path, output_path)
    print("Sprite Converter for C&C Tiberian Dawn")
    print("=======================================")
    print("")

    local ShpParser = require("tools.sprite_converter.shp_parser")
    local Palette = require("tools.sprite_converter.palette")
    local PngEncoder = require("tools.sprite_converter.png_encoder")

    print("Input SHP:  " .. shp_path)
    print("Palette:    " .. pal_path)
    print("Output:     " .. output_path)
    print("")

    -- Load palette
    print("Loading palette...")
    local palette, err = Palette.load_pal(pal_path)
    if not palette then
        print("Warning: " .. (err or "Could not load palette"))
        print("Using grayscale fallback")
        palette = Palette.create_grayscale()
    end

    -- Load SHP
    print("Loading SHP file...")
    local file = io.open(shp_path, "rb")
    if not file then
        print("Error: Could not open SHP file: " .. shp_path)
        return false
    end

    local data = file:read("*all")
    file:close()

    local shp, parse_err = ShpParser.parse(data)
    if not shp then
        print("Error parsing SHP: " .. parse_err)
        return false
    end

    print("  Frames: " .. shp.frame_count)
    print("  Size:   " .. shp.width .. "x" .. shp.height)
    print("")

    -- Create spritesheet
    print("Creating spritesheet...")
    local converter = require("tools.sprite_converter.main")
    local sheet = converter.create_spritesheet(shp, palette)

    print("  Sheet size: " .. sheet.width .. "x" .. sheet.height)
    print("  Layout:     " .. sheet.cols .. " columns, " .. sheet.rows .. " rows")
    print("")

    -- Write PNG
    print("Writing PNG...")
    local png_data = PngEncoder.encode(sheet.width, sheet.height, sheet.pixels)

    local out_file = io.open(output_path, "wb")
    if out_file then
        out_file:write(png_data)
        out_file:close()
        print("Wrote: " .. output_path)
    else
        print("Error: Could not write to: " .. output_path)
        return false
    end

    print("")
    print("Done!")
    return true
end

function ToolRunner.convert_aud(aud_path, output_path)
    print("Audio Converter for C&C Tiberian Dawn")
    print("======================================")
    print("")

    local AudParser = require("tools.audio_converter.aud_parser")
    local WavWriter = require("tools.audio_converter.wav_writer")

    print("Input AUD:  " .. aud_path)
    print("Output WAV: " .. output_path)
    print("")

    -- Load AUD file
    print("Loading AUD file...")
    local file = io.open(aud_path, "rb")
    if not file then
        print("Error: Could not open AUD file: " .. aud_path)
        return false
    end

    local data = file:read("*all")
    file:close()

    print("  File size: " .. #data .. " bytes")

    -- Parse and decode
    print("Decoding audio...")
    local aud_data, err = AudParser.decode(data)
    if not aud_data then
        print("Error decoding AUD: " .. (err or "Unknown error"))
        return false
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
    local success, write_err = WavWriter.write_from_aud(output_path, aud_data)
    if not success then
        print("Error writing WAV: " .. (write_err or "Unknown error"))
        return false
    end

    print("  Wrote: " .. output_path)
    print("")
    print("Done!")
    return true
end

function ToolRunner.show_help()
    print("")
    print("C&C Tiberian Dawn Asset Tools")
    print("==============================")
    print("")
    print("Usage:")
    print("  love . extract <mix_file> <output_dir>")
    print("      Extract files from a MIX archive")
    print("")
    print("  love . convert-shp <shp_file> <pal_file> <output.png>")
    print("      Convert SHP sprite to PNG spritesheet")
    print("")
    print("  love . convert-aud <aud_file> <output.wav>")
    print("      Convert AUD audio to WAV format")
    print("")
    print("Examples:")
    print('  love . extract "temp/CnC.../MIX/CD1/CONQUER.MIX" extracted/')
    print("  love . convert-shp extracted/E1.SHP extracted/TEMPERAT.PAL e1.png")
    print("  love . convert-aud extracted/AWAIT1.AUD await1.wav")
    print("")
end

function ToolRunner.run(args)
    -- Debug: print args
    -- for i, v in ipairs(args) do print("arg[" .. i .. "] = " .. tostring(v)) end

    if #args == 0 then
        ToolRunner.show_help()
        return
    end

    local command = args[1]

    -- Skip if command is "." (Love2D project path)
    if command == "." then
        command = args[2]
        -- Shift args
        local new_args = {}
        for i = 2, #args do
            new_args[i - 1] = args[i]
        end
        args = new_args
    end

    if not command then
        ToolRunner.show_help()
        return
    end

    if command == "extract" then
        if #args < 3 then
            print("Usage: love . extract <mix_file> <output_dir>")
            return
        end
        ToolRunner.extract_mix(args[2], args[3])

    elseif command == "convert-shp" then
        if #args < 4 then
            print("Usage: love . convert-shp <shp_file> <pal_file> <output.png>")
            return
        end
        ToolRunner.convert_shp(args[2], args[3], args[4])

    elseif command == "convert-aud" then
        if #args < 3 then
            print("Usage: love . convert-aud <aud_file> <output.wav>")
            return
        end
        ToolRunner.convert_aud(args[2], args[3])

    elseif command == "help" or command == "--help" or command == "-h" then
        ToolRunner.show_help()

    else
        print("Unknown command: " .. command)
        ToolRunner.show_help()
    end
end

return ToolRunner
