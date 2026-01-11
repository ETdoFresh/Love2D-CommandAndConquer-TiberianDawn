--[[
    Sprite Converter Tool
    Converts C&C SHP files to PNG spritesheets

    Usage: lua main.lua <input.shp> <palette.pal> <output.png>
]]

local ShpParser = require("tools.sprite_converter.shp_parser")
local Palette = require("tools.sprite_converter.palette")
local PngEncoder = require("tools.sprite_converter.png_encoder")

local function create_spritesheet(shp, palette, cols)
    cols = cols or 8  -- Frames per row

    local width = shp.width
    local height = shp.height
    local frame_count = shp.frame_count

    local rows = math.ceil(frame_count / cols)
    local sheet_width = cols * width
    local sheet_height = rows * height

    -- Create RGBA pixel data
    local pixels = {}
    for i = 1, sheet_width * sheet_height * 4 do
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

local function write_png_data(sheet)
    -- Encode as PNG using pure Lua encoder
    return PngEncoder.encode(sheet.width, sheet.height, sheet.pixels)
end

local function main(args)
    if #args < 3 then
        print("Usage: lua main.lua <input.shp> <palette.pal> <output.png>")
        print("")
        print("Converts C&C SHP sprite files to PNG spritesheets.")
        print("")
        print("Examples:")
        print("  lua main.lua e1.shp conquer.pal infantry_e1.png")
        print("  lua main.lua htnk.shp temperat.pal heavy_tank.png")
        return 1
    end

    local input_shp = args[1]
    local palette_file = args[2]
    local output_png = args[3]

    print("Sprite Converter for C&C Tiberian Dawn")
    print("=======================================")
    print("")
    print("Input SHP:  " .. input_shp)
    print("Palette:    " .. palette_file)
    print("Output:     " .. output_png)
    print("")

    -- Load palette
    print("Loading palette...")
    local palette, err = Palette.load_pal(palette_file)
    if not palette then
        print("Error loading palette: " .. err)
        print("Using grayscale fallback palette")
        palette = Palette.create_grayscale()
    end

    -- Load SHP
    print("Loading SHP file...")
    local file = io.open(input_shp, "rb")
    if not file then
        print("Error: Could not open SHP file: " .. input_shp)
        return 1
    end

    local data = file:read("*all")
    file:close()

    local shp, err = ShpParser.parse(data)
    if not shp then
        print("Error parsing SHP: " .. err)
        return 1
    end

    print("  Frames: " .. shp.frame_count)
    print("  Size:   " .. shp.width .. "x" .. shp.height)
    print("")

    -- Create spritesheet
    print("Creating spritesheet...")
    local sheet = create_spritesheet(shp, palette)

    print("  Sheet size: " .. sheet.width .. "x" .. sheet.height)
    print("  Layout:     " .. sheet.cols .. " columns, " .. sheet.rows .. " rows")
    print("")

    -- Write output
    print("Writing output...")
    local png_data = write_png_data(sheet)

    -- Write PNG file
    local out_file = io.open(output_png, "wb")
    if out_file then
        out_file:write(png_data)
        out_file:close()
        print("Wrote PNG to: " .. output_png)
    else
        print("Error: Could not write to: " .. output_png)
        return 1
    end

    -- Write metadata JSON
    local meta_file = io.open(output_png .. ".json", "w")
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
        print("Wrote metadata to: " .. output_png .. ".json")
    end

    print("")
    print("Done!")
    return 0
end

-- Run if executed directly
if arg then
    os.exit(main(arg))
end

return {
    main = main,
    create_spritesheet = create_spritesheet
}
