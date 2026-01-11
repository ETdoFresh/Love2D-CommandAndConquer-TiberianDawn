--[[
    Asset Extraction Script for C&C Tiberian Dawn
    Extracts graphics from MIX archives and converts SHP files to PNG spritesheets

    Usage from Love2D: love . --console extract_assets
    Usage standalone:  lua extract_assets.lua (requires LuaJIT for bit operations)
]]

-- Add tools to package path
package.path = package.path .. ";./?.lua"

local MixFormat = require("tools.mix_extractor.mix_format")
local CrcLookup = require("tools.mix_extractor.crc_lookup")
local ShpParser = require("tools.sprite_converter.shp_parser")
local Palette = require("tools.sprite_converter.palette")
local PngEncoder = require("tools.sprite_converter.png_encoder")

-- Configuration
local CONFIG = {
    mix_base_path = "temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/",
    output_dir = "assets/sprites/",
    extracted_dir = "extracted/",

    -- MIX files containing graphics
    mix_files = {
        "CONQUER.MIX",      -- Unit and building sprites
        "TEMPERAT.MIX",     -- Temperate theater terrain
        "DESERT.MIX",       -- Desert theater terrain
        "WINTER.MIX",       -- Winter theater terrain
    },

    -- Palette files (in order of preference)
    palette_files = {
        "temperat.pal",
        "conquer.pal",
        "desert.pal",
        "winter.pal",
    },

    -- Categories of files to extract and convert
    sprite_categories = {
        infantry = {"e1", "e2", "e3", "e4", "e5", "e6", "rmbo"},
        vehicles = {"htnk", "mtnk", "ltnk", "apc", "harv", "mcv", "jeep", "bggy", "bike", "arty", "mlrs", "msam", "stnk", "ftnk"},
        aircraft = {"orca", "heli", "tran", "a10", "c17"},
        buildings = {"fact", "pyle", "hand", "weap", "proc", "silo", "nuke", "nuk2", "hq", "hpad", "afld", "gtwr", "atwr", "sam", "gun", "obli", "eye", "tmpl", "fix", "bio", "hosp"},
        effects = {"fball1", "fire1", "fire2", "fire3", "fire4", "napalm", "smokey", "piff", "piffpiff", "ion", "atomsfx"},
        overlays = {"ti1", "ti2", "ti3", "ti4", "ti5", "ti6", "ti7", "ti8", "ti9", "ti10", "ti11", "ti12"},
        walls = {"sbag", "cycl", "brik", "barb", "wood"},
    }
}

local extracted_count = 0
local converted_count = 0

-- Create directories if needed
local function ensure_dir(path)
    -- Use os.execute to create directory (cross-platform)
    local sep = package.config:sub(1,1)
    if sep == "\\" then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
end

-- Extract all files from a MIX archive
local function extract_mix(mix_path, output_dir)
    print("Extracting: " .. mix_path)

    local mix, err = MixFormat.parse(mix_path)
    if not mix then
        print("  Error: " .. err)
        return 0
    end

    print("  Found " .. mix.file_count .. " files")

    local extracted = 0
    for _, entry in ipairs(mix.entries) do
        mix.file:seek("set", entry.offset)
        local data = mix.file:read(entry.size)

        -- Try to get filename from CRC lookup
        local filename = CrcLookup.BY_CRC[entry.crc]
        if not filename then
            filename = string.format("unknown_%08X.bin", entry.crc)
        end

        local out_path = output_dir .. "/" .. filename
        local out_file = io.open(out_path, "wb")
        if out_file then
            out_file:write(data)
            out_file:close()
            extracted = extracted + 1
        end
    end

    MixFormat.close(mix)
    print("  Extracted " .. extracted .. " files")
    return extracted
end

-- Create a spritesheet from SHP data
local function create_spritesheet(shp, palette, cols)
    cols = cols or 8  -- Frames per row

    local width = shp.width
    local height = shp.height
    local frame_count = shp.frame_count

    -- Validate dimensions to prevent overflow
    if width <= 0 or width > 512 or height <= 0 or height > 512 then
        print(string.format("  WARNING: Invalid dimensions %dx%d, skipping", width, height))
        return nil
    end

    if frame_count <= 0 or frame_count > 2000 then
        print(string.format("  WARNING: Invalid frame count %d, skipping", frame_count))
        return nil
    end

    local rows = math.ceil(frame_count / cols)
    local sheet_width = cols * width
    local sheet_height = rows * height

    -- Validate total size
    local total_pixels = sheet_width * sheet_height * 4
    if total_pixels > 100000000 then  -- 100MB max
        print(string.format("  WARNING: Spritesheet too large (%dx%d = %d pixels), skipping",
            sheet_width, sheet_height, total_pixels / 4))
        return nil
    end

    -- Create RGBA pixel data
    local pixels = {}
    for i = 1, total_pixels do
        pixels[i] = 0
    end

    -- Decode and place each frame
    local prev_frame = nil
    for frame_idx = 1, frame_count do
        local frame_pixels = ShpParser.decode_frame(shp, frame_idx, prev_frame)
        prev_frame = frame_pixels  -- Store for XOR delta frames
        if frame_pixels then
            -- Calculate position in spritesheet
            local col = (frame_idx - 1) % cols
            local row = math.floor((frame_idx - 1) / cols)
            local base_x = col * width
            local base_y = row * height

            -- Copy pixels with palette lookup
            for y = 0, height - 1 do
                for x = 0, width - 1 do
                    local src_idx = y * width + x + 1
                    local palette_idx = frame_pixels[src_idx]

                    -- Calculate destination position
                    local dest_x = base_x + x
                    local dest_y = base_y + y
                    local dest_idx = (dest_y * sheet_width + dest_x) * 4 + 1

                    if palette:is_transparent(palette_idx) then
                        -- Transparent pixel
                        pixels[dest_idx] = 0
                        pixels[dest_idx + 1] = 0
                        pixels[dest_idx + 2] = 0
                        pixels[dest_idx + 3] = 0
                    else
                        local r, g, b = palette:get_rgba(palette_idx)
                        pixels[dest_idx] = r
                        pixels[dest_idx + 1] = g
                        pixels[dest_idx + 2] = b
                        pixels[dest_idx + 3] = 255
                    end
                end
            end
        end
    end

    return {
        width = sheet_width,
        height = sheet_height,
        pixels = pixels,
        frame_width = width,
        frame_height = height,
        frame_count = frame_count,
        cols = cols,
        rows = rows
    }
end

-- Convert SHP file to PNG spritesheet
local function convert_shp_to_png(shp_path, output_path, palette)
    local file = io.open(shp_path, "rb")
    if not file then
        return false, "Could not open file"
    end

    local data = file:read("*all")
    file:close()

    local shp, err = ShpParser.parse(data)
    if not shp then
        return false, "Parse error: " .. (err or "unknown")
    end

    -- Create spritesheet
    local sheet = create_spritesheet(shp, palette)

    -- Encode as PNG
    local png_data = PngEncoder.encode(sheet.width, sheet.height, sheet.pixels)

    -- Write PNG file
    local out_file = io.open(output_path, "wb")
    if not out_file then
        return false, "Could not write output file"
    end
    out_file:write(png_data)
    out_file:close()

    -- Write metadata JSON
    local meta_file = io.open(output_path .. ".json", "w")
    if meta_file then
        meta_file:write(string.format([[{
    "frame_width": %d,
    "frame_height": %d,
    "frame_count": %d,
    "sheet_width": %d,
    "sheet_height": %d,
    "cols": %d,
    "rows": %d
}]], sheet.frame_width, sheet.frame_height, sheet.frame_count,
    sheet.width, sheet.height, sheet.cols, sheet.rows))
        meta_file:close()
    end

    return true, shp.frame_count
end

-- Load a palette
local function load_palette(extracted_dir)
    for _, pal_name in ipairs(CONFIG.palette_files) do
        local pal_path = extracted_dir .. pal_name
        local palette = Palette.load_pal(pal_path)
        if palette then
            print("Loaded palette: " .. pal_name)
            return palette
        end
    end

    print("Warning: No palette found, using grayscale")
    return Palette.create_grayscale()
end

-- Main extraction and conversion
local function main()
    print("")
    print("C&C Tiberian Dawn Asset Extractor")
    print("==================================")
    print("")

    -- Create output directories
    ensure_dir(CONFIG.extracted_dir)
    ensure_dir(CONFIG.output_dir)

    -- Phase 1: Extract from MIX archives
    print("Phase 1: Extracting from MIX archives")
    print("--------------------------------------")

    for _, mix_name in ipairs(CONFIG.mix_files) do
        local mix_path = CONFIG.mix_base_path .. mix_name
        local count = extract_mix(mix_path, CONFIG.extracted_dir)
        extracted_count = extracted_count + count
    end

    print("")
    print("Total extracted: " .. extracted_count .. " files")
    print("")

    -- Phase 2: Load palette
    print("Phase 2: Loading palette")
    print("------------------------")
    local palette = load_palette(CONFIG.extracted_dir)
    print("")

    -- Phase 3: Convert SHP files to PNG spritesheets
    print("Phase 3: Converting SHP to PNG spritesheets")
    print("--------------------------------------------")

    for category, sprites in pairs(CONFIG.sprite_categories) do
        local category_dir = CONFIG.output_dir .. category .. "/"
        ensure_dir(category_dir)

        for _, sprite_name in ipairs(sprites) do
            local shp_path = CONFIG.extracted_dir .. sprite_name .. ".shp"
            local png_path = category_dir .. sprite_name .. ".png"

            local success, result = convert_shp_to_png(shp_path, png_path, palette)
            if success then
                print("  " .. sprite_name .. ".shp -> " .. sprite_name .. ".png (" .. result .. " frames)")
                converted_count = converted_count + 1
            else
                -- Try uppercase
                shp_path = CONFIG.extracted_dir .. sprite_name:upper() .. ".SHP"
                success, result = convert_shp_to_png(shp_path, png_path, palette)
                if success then
                    print("  " .. sprite_name:upper() .. ".SHP -> " .. sprite_name .. ".png (" .. result .. " frames)")
                    converted_count = converted_count + 1
                else
                    print("  " .. sprite_name .. ".shp: " .. (result or "not found"))
                end
            end
        end
    end

    print("")
    print("Summary")
    print("-------")
    print("Files extracted: " .. extracted_count)
    print("Sprites converted: " .. converted_count)
    print("")
    print("Output directories:")
    print("  Extracted files: " .. CONFIG.extracted_dir)
    print("  PNG spritesheets: " .. CONFIG.output_dir)
    print("")
    print("Done!")

    return converted_count > 0
end

-- Run if executed directly
if arg and arg[0] and (arg[0]:match("extract_assets") or arg[0]:match("love")) then
    -- Check for command line arg
    local run_extract = false
    if arg then
        for _, a in ipairs(arg) do
            if a == "extract_assets" then
                run_extract = true
            end
        end
    end

    if run_extract then
        main()
    end
end

-- For Love2D integration
function love.load(args)
    for _, arg in ipairs(args) do
        if arg == "extract_assets" then
            main()
            print("Press any key to exit...")
            return
        end
    end
end

function love.keypressed(key)
    love.event.quit()
end

return {
    main = main,
    extract_mix = extract_mix,
    convert_shp_to_png = convert_shp_to_png,
    CONFIG = CONFIG
}
