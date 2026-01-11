--[[
    Test script for asset extraction tools
    Run with: love . --console test_extractor
]]

-- Add tools to package path
package.path = package.path .. ";./?.lua"

local MixFormat = require("tools.mix_extractor.mix_format")
local CrcLookup = require("tools.mix_extractor.crc_lookup")

local function test_mix_extractor()
    print("=== Testing MIX Extractor ===")
    print("")

    local mix_path = "temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/CONQUER.MIX"
    print("Opening: " .. mix_path)

    local mix, err = MixFormat.parse(mix_path)
    if not mix then
        print("Error: " .. err)
        return false
    end

    print("File count: " .. mix.file_count)
    print("Body size: " .. mix.body_size)
    print("")

    -- List first 20 files
    print("First 20 files:")
    local files = MixFormat.list(mix, CrcLookup)
    for i = 1, math.min(20, #files) do
        local f = files[i]
        print(string.format("  %s (%d bytes)", f.filename, f.size))
    end

    -- Create output directory
    local output_dir = "extracted"
    os.execute('mkdir "' .. output_dir .. '" 2>nul')

    -- Extract first 10 files
    print("")
    print("Extracting first 10 files to: " .. output_dir)
    local extracted = {}
    for i = 1, math.min(10, #mix.entries) do
        local entry = mix.entries[i]
        mix.file:seek("set", entry.offset)
        local data = mix.file:read(entry.size)

        local filename = CrcLookup[entry.crc]
        if not filename then
            filename = string.format("unknown_%08X.bin", entry.crc)
        end

        local out_path = output_dir .. "/" .. filename
        local out_file = io.open(out_path, "wb")
        if out_file then
            out_file:write(data)
            out_file:close()
            print("  Extracted: " .. filename)
            table.insert(extracted, {filename = filename, size = entry.size})
        end
    end

    MixFormat.close(mix)

    print("")
    print("Done! Extracted " .. #extracted .. " files.")
    return true, extracted
end

local function test_sprite_converter()
    print("")
    print("=== Testing Sprite Converter ===")
    print("")

    local ShpParser = require("tools.sprite_converter.shp_parser")
    local Palette = require("tools.sprite_converter.palette")
    local PngEncoder = require("tools.sprite_converter.png_encoder")

    -- Try to find an extracted SHP file
    local shp_files = {"E1.SHP", "E2.SHP", "MTNK.SHP", "HTNK.SHP", "HARV.SHP"}
    local shp_path = nil
    local shp_data = nil

    for _, name in ipairs(shp_files) do
        local path = "extracted/" .. name
        local file = io.open(path, "rb")
        if file then
            shp_data = file:read("*all")
            file:close()
            shp_path = path
            break
        end
    end

    if not shp_data then
        print("No SHP files found in extracted/")
        print("Run MIX extractor first to extract SHP files.")
        return false
    end

    print("Testing with: " .. shp_path)

    -- Parse SHP
    local shp, err = ShpParser.parse(shp_data)
    if not shp then
        print("Error parsing SHP: " .. err)
        return false
    end

    print("  Frames: " .. shp.frame_count)
    print("  Size: " .. shp.width .. "x" .. shp.height)

    -- Try to load palette
    local pal_path = "temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/TEMPERAT.PAL"
    local palette = Palette.load_pal(pal_path)
    if not palette then
        print("  Using grayscale palette (could not load " .. pal_path .. ")")
        palette = Palette.create_grayscale()
    else
        print("  Loaded palette: " .. pal_path)
    end

    -- Decode first frame
    local pixels = ShpParser.decode_frame(shp, 1, nil)
    if pixels then
        print("  Frame 1 decoded: " .. #pixels .. " pixels")

        -- Check for non-zero pixels
        local non_zero = 0
        for i, p in ipairs(pixels) do
            if p ~= 0 then non_zero = non_zero + 1 end
        end
        print("  Non-transparent pixels: " .. non_zero)
    end

    print("")
    print("Sprite converter test complete!")
    return true
end

-- Main
function love.load(args)
    -- Check for test mode
    local test_mode = false
    for _, arg in ipairs(args) do
        if arg == "test_extractor" then
            test_mode = true
        end
    end

    if test_mode then
        print("")
        print("C&C Asset Extraction Tool Test")
        print("================================")
        print("")

        local success = test_mix_extractor()
        if success then
            test_sprite_converter()
        end

        print("")
        print("Press any key to exit...")
    end
end

function love.keypressed(key)
    love.event.quit()
end
