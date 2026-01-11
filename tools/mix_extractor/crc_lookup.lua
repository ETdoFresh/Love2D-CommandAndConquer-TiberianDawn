--[[
    CRC Lookup Table for Known C&C Tiberian Dawn Files
    Maps CRC32 values to filenames for MIX extraction
]]

local CrcLookup = {}

-- Known file CRCs from Tiberian Dawn
-- Generated from original file lists
CrcLookup.KNOWN_FILES = {
    -- Infantry sprites
    ["e1.shp"] = true,
    ["e2.shp"] = true,
    ["e3.shp"] = true,
    ["e4.shp"] = true,
    ["e5.shp"] = true,
    ["e6.shp"] = true,
    ["rmbo.shp"] = true,
    ["c1.shp"] = true,
    ["c2.shp"] = true,
    ["c3.shp"] = true,
    ["c4.shp"] = true,
    ["c5.shp"] = true,
    ["c6.shp"] = true,
    ["c7.shp"] = true,
    ["c8.shp"] = true,
    ["c9.shp"] = true,
    ["c10.shp"] = true,
    ["moebius.shp"] = true,
    ["delphi.shp"] = true,
    ["chan.shp"] = true,

    -- Vehicle sprites
    ["apc.shp"] = true,
    ["arty.shp"] = true,
    ["bggy.shp"] = true,
    ["bike.shp"] = true,
    ["ftnk.shp"] = true,
    ["harv.shp"] = true,
    ["htnk.shp"] = true,
    ["jeep.shp"] = true,
    ["ltnk.shp"] = true,
    ["mcv.shp"] = true,
    ["mlrs.shp"] = true,
    ["msam.shp"] = true,
    ["mtnk.shp"] = true,
    ["stnk.shp"] = true,
    ["boat.shp"] = true,
    ["hover.shp"] = true,
    ["vice.shp"] = true,

    -- Aircraft sprites
    ["orca.shp"] = true,
    ["heli.shp"] = true,
    ["tran.shp"] = true,
    ["a10.shp"] = true,
    ["c17.shp"] = true,

    -- Building sprites
    ["afld.shp"] = true,
    ["atwr.shp"] = true,
    ["bio.shp"] = true,
    ["eye.shp"] = true,
    ["fact.shp"] = true,
    ["fix.shp"] = true,
    ["gtwr.shp"] = true,
    ["gun.shp"] = true,
    ["hand.shp"] = true,
    ["hpad.shp"] = true,
    ["hq.shp"] = true,
    ["nuke.shp"] = true,
    ["obli.shp"] = true,
    ["proc.shp"] = true,
    ["pyle.shp"] = true,
    ["sam.shp"] = true,
    ["silo.shp"] = true,
    ["tmpl.shp"] = true,
    ["weap.shp"] = true,
    ["nuk2.shp"] = true,

    -- Walls
    ["brik.shp"] = true,
    ["cycl.shp"] = true,
    ["sbag.shp"] = true,
    ["wood.shp"] = true,
    ["barb.shp"] = true,

    -- Effects
    ["bomb.shp"] = true,
    ["fball1.shp"] = true,
    ["fire1.shp"] = true,
    ["fire2.shp"] = true,
    ["fire3.shp"] = true,
    ["fire4.shp"] = true,
    ["napalm.shp"] = true,
    ["piff.shp"] = true,
    ["piffpiff.shp"] = true,
    ["smokey.shp"] = true,
    ["veh-hit1.shp"] = true,
    ["veh-hit2.shp"] = true,
    ["veh-hit3.shp"] = true,
    ["ion.shp"] = true,
    ["atomsfx.shp"] = true,

    -- UI elements
    ["mouse.shp"] = true,
    ["options.shp"] = true,
    ["sidebar.shp"] = true,
    ["btexture.shp"] = true,
    ["tabs.shp"] = true,

    -- Terrain templates
    ["clear1.tem"] = true,
    ["w1.tem"] = true,
    ["w2.tem"] = true,
    ["sh1.tem"] = true,
    ["sh2.tem"] = true,
    ["sh3.tem"] = true,
    ["sh4.tem"] = true,
    ["sh5.tem"] = true,

    -- Overlays
    ["ti1.shp"] = true,
    ["ti2.shp"] = true,
    ["ti3.shp"] = true,
    ["ti4.shp"] = true,
    ["ti5.shp"] = true,
    ["ti6.shp"] = true,
    ["ti7.shp"] = true,
    ["ti8.shp"] = true,
    ["ti9.shp"] = true,
    ["ti10.shp"] = true,
    ["ti11.shp"] = true,
    ["ti12.shp"] = true,

    -- Palettes
    ["temperat.pal"] = true,
    ["desert.pal"] = true,
    ["winter.pal"] = true,
    ["conquer.pal"] = true,
}

-- Build reverse lookup (name -> CRC)
local function calculate_crc32(str)
    str = str:lower()
    local crc = 0xFFFFFFFF
    local crc_table = {}

    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if c % 2 == 1 then
                c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
            else
                c = bit.rshift(c, 1)
            end
        end
        crc_table[i] = c
    end

    for i = 1, #str do
        local byte = str:byte(i)
        local index = bit.band(bit.bxor(crc, byte), 0xFF)
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[index])
    end

    return bit.bxor(crc, 0xFFFFFFFF)
end

-- Build CRC -> name lookup
function CrcLookup.build_lookup()
    local lookup = {}

    for filename in pairs(CrcLookup.KNOWN_FILES) do
        local crc = calculate_crc32(filename)
        lookup[crc] = filename
    end

    return lookup
end

-- Get lookup table
CrcLookup.BY_CRC = CrcLookup.build_lookup()

return CrcLookup
