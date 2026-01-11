--[[
    Quick test for asset tools
    Run with: love . test
]]

function love.load(arg)
    if arg[1] ~= "test" then return end

    print("")
    print("=== Asset Tool Tests ===")
    print("")

    -- Test 1: SHP Parser
    print("Test 1: SHP Parser")
    local ok, ShpParser = pcall(require, "tools.sprite_converter.shp_parser")
    if not ok then
        print("  FAIL: Could not load shp_parser: " .. tostring(ShpParser))
    else
        print("  OK: shp_parser loaded")

        -- Try to parse an extracted file
        local shp_path = "extracted/unknown_00D2F7D6.bin"
        local file = io.open(shp_path, "rb")
        if file then
            local data = file:read("*all")
            file:close()
            print("  OK: Read " .. #data .. " bytes from " .. shp_path)

            local shp, err = ShpParser.parse(data)
            if shp then
                print("  OK: Parsed SHP - " .. shp.frame_count .. " frames, " .. shp.width .. "x" .. shp.height)

                -- Try to decode first frame
                local pixels, decode_err = ShpParser.decode_frame(shp, 1, nil)
                if pixels then
                    local non_zero = 0
                    for _, p in ipairs(pixels) do
                        if p ~= 0 then non_zero = non_zero + 1 end
                    end
                    print("  OK: Decoded frame 1 - " .. non_zero .. " non-transparent pixels")
                else
                    print("  WARN: Frame decode issue: " .. tostring(decode_err))
                end
            else
                print("  FAIL: Parse error: " .. tostring(err))
            end
        else
            print("  SKIP: No extracted files found (run 'love . extract' first)")
        end
    end

    print("")

    -- Test 2: Palette
    print("Test 2: Palette Loader")
    local ok2, Palette = pcall(require, "tools.sprite_converter.palette")
    if not ok2 then
        print("  FAIL: Could not load palette: " .. tostring(Palette))
    else
        print("  OK: palette module loaded")

        local pal_path = "temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/TEMPERAT.PAL"
        local pal, err = Palette.load_pal(pal_path)
        if pal then
            print("  OK: Loaded palette from " .. pal_path)
            local r, g, b = pal:get_rgba(1)
            print("  OK: Color 1 = RGB(" .. r .. ", " .. g .. ", " .. b .. ")")
        else
            print("  FAIL: " .. tostring(err))
        end
    end

    print("")

    -- Test 3: PNG Encoder
    print("Test 3: PNG Encoder")
    local ok3, PngEncoder = pcall(require, "tools.sprite_converter.png_encoder")
    if not ok3 then
        print("  FAIL: Could not load png_encoder: " .. tostring(PngEncoder))
    else
        print("  OK: png_encoder loaded")

        -- Create a simple test image
        local width, height = 16, 16
        local pixels = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                -- Red/green gradient
                table.insert(pixels, math.floor(x * 16))  -- R
                table.insert(pixels, math.floor(y * 16))  -- G
                table.insert(pixels, 128)                  -- B
                table.insert(pixels, 255)                  -- A
            end
        end

        local png_data = PngEncoder.encode(width, height, pixels)
        print("  OK: Generated " .. #png_data .. " bytes of PNG data")

        -- Write test file
        local out = io.open("test_gradient.png", "wb")
        if out then
            out:write(png_data)
            out:close()
            print("  OK: Wrote test_gradient.png")
        end
    end

    print("")

    -- Test 4: Full sprite conversion
    print("Test 4: Full Sprite Conversion")
    if ok and ok2 and ok3 then
        local shp_path = "extracted/unknown_00D2F7D6.bin"
        local pal_path = "temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/TEMPERAT.PAL"

        local file = io.open(shp_path, "rb")
        if file then
            local data = file:read("*all")
            file:close()

            local shp = ShpParser.parse(data)
            local pal = Palette.load_pal(pal_path) or Palette.create_grayscale()

            if shp then
                -- Create a small test: just first 8 frames
                local cols = 8
                local frames_to_use = math.min(8, shp.frame_count)
                local rows = math.ceil(frames_to_use / cols)
                local sheet_w = cols * shp.width
                local sheet_h = rows * shp.height

                local pixels = {}
                for i = 1, sheet_w * sheet_h * 4 do
                    pixels[i] = 0
                end

                local prev_frame = nil
                for f = 1, frames_to_use do
                    local frame_pixels = ShpParser.decode_frame(shp, f, prev_frame)
                    prev_frame = frame_pixels

                    if frame_pixels then
                        local col = (f - 1) % cols
                        local row = math.floor((f - 1) / cols)

                        for y = 0, shp.height - 1 do
                            for x = 0, shp.width - 1 do
                                local src_idx = y * shp.width + x + 1
                                local pal_idx = frame_pixels[src_idx]

                                local dest_x = col * shp.width + x
                                local dest_y = row * shp.height + y
                                local dest_idx = (dest_y * sheet_w + dest_x) * 4 + 1

                                if pal:is_transparent(pal_idx) then
                                    pixels[dest_idx] = 0
                                    pixels[dest_idx + 1] = 0
                                    pixels[dest_idx + 2] = 0
                                    pixels[dest_idx + 3] = 0
                                else
                                    local r, g, b = pal:get_rgba(pal_idx)
                                    pixels[dest_idx] = r
                                    pixels[dest_idx + 1] = g
                                    pixels[dest_idx + 2] = b
                                    pixels[dest_idx + 3] = 255
                                end
                            end
                        end
                    end
                end

                local png_data = PngEncoder.encode(sheet_w, sheet_h, pixels)
                local out = io.open("test_sprite.png", "wb")
                if out then
                    out:write(png_data)
                    out:close()
                    print("  OK: Wrote test_sprite.png (" .. sheet_w .. "x" .. sheet_h .. ", " .. #png_data .. " bytes)")
                else
                    print("  FAIL: Could not write output file")
                end
            end
        else
            print("  SKIP: No extracted SHP files")
        end
    else
        print("  SKIP: Previous tests failed")
    end

    print("")
    print("=== Tests Complete ===")
    print("")
    print("Press any key to exit...")
end

function love.draw()
    if love.keyboard.isDown("escape") then
        love.event.quit()
    end
    love.graphics.print("Test mode - see console output", 20, 20)
    love.graphics.print("Press ESC to exit", 20, 40)
end

function love.keypressed(key)
    love.event.quit()
end

return {
    love_load = love.load
}
