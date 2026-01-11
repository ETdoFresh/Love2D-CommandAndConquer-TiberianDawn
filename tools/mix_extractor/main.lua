--[[
    MIX Extractor Tool
    Extracts files from C&C MIX archives

    Usage: lua main.lua <input.mix> <output_dir>
]]

local MixFormat = require("tools.mix_extractor.mix_format")
local CrcLookup = require("tools.mix_extractor.crc_lookup")

local function main(args)
    if #args < 2 then
        print("Usage: lua main.lua <input.mix> <output_dir>")
        print("")
        print("Extracts files from Command & Conquer MIX archives.")
        print("")
        print("Examples:")
        print("  lua main.lua CONQUER.MIX ./extracted/")
        print("  lua main.lua TEMPERAT.MIX ./terrain/")
        return 1
    end

    local input_file = args[1]
    local output_dir = args[2]

    print("MIX Extractor for C&C Tiberian Dawn")
    print("====================================")
    print("")
    print("Input:  " .. input_file)
    print("Output: " .. output_dir)
    print("")

    -- Parse MIX file
    print("Parsing MIX file...")
    local mix, err = MixFormat.parse(input_file)
    if not mix then
        print("Error: " .. err)
        return 1
    end

    print("Found " .. mix.file_count .. " files")
    print("")

    -- Create output directory
    os.execute("mkdir -p " .. output_dir)

    -- Extract all files
    print("Extracting files...")
    local extracted = MixFormat.extract_all(mix, output_dir, CrcLookup.BY_CRC)

    print("")
    print("Extracted " .. #extracted .. " files:")
    for _, file in ipairs(extracted) do
        print("  " .. file.filename .. " (" .. file.size .. " bytes)")
    end

    -- Close MIX file
    MixFormat.close(mix)

    print("")
    print("Done!")
    return 0
end

-- Run if executed directly
if arg then
    os.exit(main(arg))
end

return {main = main}
