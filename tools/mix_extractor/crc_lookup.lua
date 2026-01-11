--[[
    CRC Lookup Table for Known C&C Tiberian Dawn Files
    Maps CRC32 values to filenames for MIX extraction

    Comprehensive list extracted from original source code
]]

local CrcLookup = {}

-- Known file CRCs from Tiberian Dawn
-- Generated from original C++ source code analysis
CrcLookup.KNOWN_FILES = {
    -- Infantry sprites (from IDATA.CPP)
    ["e1.shp"] = true,      -- Minigunner
    ["e2.shp"] = true,      -- Grenadier
    ["e3.shp"] = true,      -- Rocket soldier
    ["e4.shp"] = true,      -- Flamethrower
    ["e5.shp"] = true,      -- Chem warrior
    ["e6.shp"] = true,      -- Engineer
    ["rmbo.shp"] = true,    -- Commando
    ["c1.shp"] = true,      -- Civilian
    ["c2.shp"] = true,      -- Civilian
    ["c3.shp"] = true,      -- Civilian
    ["c4.shp"] = true,      -- Civilian
    ["c5.shp"] = true,      -- Civilian
    ["c6.shp"] = true,      -- Civilian
    ["c7.shp"] = true,      -- Civilian
    ["c8.shp"] = true,      -- Civilian
    ["c9.shp"] = true,      -- Civilian
    ["c10.shp"] = true,     -- Nikumba
    ["moebius.shp"] = true, -- Dr. Moebius
    ["delphi.shp"] = true,  -- Agent Delphi
    ["chan.shp"] = true,    -- Dr. Chan

    -- Vehicle sprites (from UDATA.CPP)
    ["vice.shp"] = true,    -- Visceroid
    ["ftnk.shp"] = true,    -- Flame tank
    ["stnk.shp"] = true,    -- Stealth tank
    ["ltnk.shp"] = true,    -- Light tank
    ["mtnk.shp"] = true,    -- Medium tank
    ["htnk.shp"] = true,    -- Mammoth tank (Heavy tank)
    ["mhq.shp"] = true,     -- Mobile HQ
    ["lst.shp"] = true,     -- Hovercraft (Hover)
    ["mlrs.shp"] = true,    -- MLRS
    ["arty.shp"] = true,    -- Artillery
    ["harv.shp"] = true,    -- Harvester
    ["mcv.shp"] = true,     -- MCV
    ["jeep.shp"] = true,    -- Jeep/Humvee
    ["bggy.shp"] = true,    -- Dune buggy
    ["bike.shp"] = true,    -- Recon bike
    ["msam.shp"] = true,    -- Mobile SAM (Rocket launcher)
    ["apc.shp"] = true,     -- APC
    ["boat.shp"] = true,    -- Gunboat
    ["hover.shp"] = true,   -- Hovercraft

    -- Dinosaurs (special units)
    ["tric.shp"] = true,    -- Triceratops
    ["trex.shp"] = true,    -- T-Rex
    ["rapt.shp"] = true,    -- Velociraptor
    ["steg.shp"] = true,    -- Stegosaurus

    -- Aircraft sprites (from AADATA.CPP)
    ["a10.shp"] = true,     -- A-10 Warthog
    ["tran.shp"] = true,    -- Chinook transport
    ["heli.shp"] = true,    -- Apache helicopter
    ["orca.shp"] = true,    -- Orca
    ["c17.shp"] = true,     -- C-17 cargo plane
    ["lrotor.shp"] = true,  -- Left rotor
    ["rrotor.shp"] = true,  -- Right rotor

    -- Building sprites (from BDATA.CPP)
    ["tmpl.shp"] = true,    -- Temple of Nod
    ["eye.shp"] = true,     -- Advanced comm center
    ["weap.shp"] = true,    -- Weapons factory
    ["gtwr.shp"] = true,    -- Guard tower
    ["atwr.shp"] = true,    -- Advanced guard tower
    ["obli.shp"] = true,    -- Obelisk of Light
    ["gun.shp"] = true,     -- Turret
    ["fact.shp"] = true,    -- Construction yard
    ["proc.shp"] = true,    -- Refinery
    ["silo.shp"] = true,    -- Tiberium silo
    ["hpad.shp"] = true,    -- Helipad
    ["hq.shp"] = true,      -- Communications center
    ["sam.shp"] = true,     -- SAM site
    ["afld.shp"] = true,    -- Airstrip
    ["nuke.shp"] = true,    -- Power plant
    ["nuk2.shp"] = true,    -- Advanced power plant
    ["hosp.shp"] = true,    -- Hospital
    ["bio.shp"] = true,     -- Bio-research lab
    ["pyle.shp"] = true,    -- Barracks
    ["hand.shp"] = true,    -- Hand of Nod
    ["arco.shp"] = true,    -- Tanker (oil tanker)
    ["fix.shp"] = true,     -- Repair bay
    ["road.shp"] = true,    -- Road
    ["miss.shp"] = true,    -- Church/Mission

    -- Civilian buildings (V01-V37)
    ["v01.shp"] = true,
    ["v02.shp"] = true,
    ["v03.shp"] = true,
    ["v04.shp"] = true,
    ["v05.shp"] = true,
    ["v06.shp"] = true,
    ["v07.shp"] = true,
    ["v08.shp"] = true,
    ["v09.shp"] = true,
    ["v10.shp"] = true,
    ["v11.shp"] = true,
    ["v12.shp"] = true,
    ["v13.shp"] = true,
    ["v14.shp"] = true,
    ["v15.shp"] = true,
    ["v16.shp"] = true,
    ["v17.shp"] = true,
    ["v18.shp"] = true,
    ["v19.shp"] = true,
    ["v20.shp"] = true,
    ["v21.shp"] = true,
    ["v22.shp"] = true,
    ["v23.shp"] = true,
    ["v24.shp"] = true,
    ["v25.shp"] = true,
    ["v26.shp"] = true,
    ["v27.shp"] = true,
    ["v28.shp"] = true,
    ["v29.shp"] = true,
    ["v30.shp"] = true,
    ["v31.shp"] = true,
    ["v32.shp"] = true,
    ["v33.shp"] = true,
    ["v34.shp"] = true,
    ["v35.shp"] = true,
    ["v36.shp"] = true,
    ["v37.shp"] = true,

    -- Walls
    ["sbag.shp"] = true,    -- Sandbag wall
    ["cycl.shp"] = true,    -- Cyclone fence
    ["brik.shp"] = true,    -- Concrete wall
    ["barb.shp"] = true,    -- Barbed wire
    ["wood.shp"] = true,    -- Wooden fence

    -- Overlays (Tiberium)
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

    -- Road/concrete overlays
    ["conc.shp"] = true,
    ["squish.shp"] = true,
    ["fpls.shp"] = true,

    -- Crates
    ["wcrate.shp"] = true,
    ["scrate.shp"] = true,

    -- Effects and animations
    ["bomb.shp"] = true,
    ["fball1.shp"] = true,
    ["fball2.shp"] = true,
    ["fire1.shp"] = true,
    ["fire2.shp"] = true,
    ["fire3.shp"] = true,
    ["fire4.shp"] = true,
    ["napalm.shp"] = true,
    ["napalm1.shp"] = true,
    ["napalm2.shp"] = true,
    ["napalm3.shp"] = true,
    ["piff.shp"] = true,
    ["piffpiff.shp"] = true,
    ["smokey.shp"] = true,
    ["veh-hit1.shp"] = true,
    ["veh-hit2.shp"] = true,
    ["veh-hit3.shp"] = true,
    ["ion.shp"] = true,
    ["atomsfx.shp"] = true,
    ["wake.shp"] = true,
    ["flagfly.shp"] = true,
    ["shadow.shp"] = true,
    ["select.shp"] = true,
    ["pips.shp"] = true,

    -- Projectiles/bullets
    ["bomb.shp"] = true,
    ["dragon.shp"] = true,
    ["laser.shp"] = true,
    ["missile.shp"] = true,

    -- UI elements
    ["mouse.shp"] = true,
    ["options.shp"] = true,
    ["btexture.shp"] = true,
    ["tabs.shp"] = true,
    ["side1.shp"] = true,
    ["side2.shp"] = true,
    ["strip.shp"] = true,
    ["clock.shp"] = true,
    ["stripup.shp"] = true,
    ["stripdn.shp"] = true,
    ["repair.shp"] = true,
    ["repairf.shp"] = true,
    ["repairg.shp"] = true,
    ["sell.shp"] = true,
    ["sellf.shp"] = true,
    ["sellg.shp"] = true,
    ["map.shp"] = true,
    ["mapf.shp"] = true,
    ["mapg.shp"] = true,
    ["power.shp"] = true,
    ["hpower.shp"] = true,
    ["pwrbar.shp"] = true,
    ["sidebar.shp"] = true,

    -- Score screen
    ["bar3ylw.shp"] = true,
    ["bar3red.shp"] = true,
    ["time.shp"] = true,
    ["hiscore1.shp"] = true,
    ["hiscore2.shp"] = true,
    ["logos.shp"] = true,
    ["creds.shp"] = true,

    -- Map selection
    ["countrye.shp"] = true,
    ["countrya.shp"] = true,

    -- Infantry sidebar icons
    ["e1icnh.shp"] = true,
    ["e2icnh.shp"] = true,
    ["e3icnh.shp"] = true,
    ["e4icnh.shp"] = true,
    ["e5icnh.shp"] = true,
    ["e6icnh.shp"] = true,
    ["rmboicnh.shp"] = true,
    ["e1icon.shp"] = true,
    ["e2icon.shp"] = true,
    ["e3icon.shp"] = true,
    ["e4icon.shp"] = true,
    ["e5icon.shp"] = true,
    ["e6icon.shp"] = true,
    ["rmboicon.shp"] = true,

    -- Vehicle sidebar icons
    ["apcicnh.shp"] = true,
    ["harvicnh.shp"] = true,
    ["htnkicnh.shp"] = true,
    ["mtnkicnh.shp"] = true,
    ["ltnkicnh.shp"] = true,
    ["mcvicnh.shp"] = true,
    ["jeepicnh.shp"] = true,
    ["bggyicnh.shp"] = true,
    ["bikeicnh.shp"] = true,
    ["artyicnh.shp"] = true,
    ["mlrsicnh.shp"] = true,
    ["msamicnh.shp"] = true,
    ["stnkicnh.shp"] = true,
    ["ftnkicnh.shp"] = true,

    -- Aircraft sidebar icons
    ["orcaicnh.shp"] = true,
    ["heliicnh.shp"] = true,
    ["tranicnh.shp"] = true,

    -- Building sidebar icons
    ["facticnh.shp"] = true,
    ["pyleicnh.shp"] = true,
    ["handicnh.shp"] = true,
    ["weapicnh.shp"] = true,
    ["procicnh.shp"] = true,
    ["siloicnh.shp"] = true,
    ["nukeicnh.shp"] = true,
    ["nuk2icnh.shp"] = true,
    ["hqicnh.shp"] = true,
    ["samicnh.shp"] = true,
    ["gtwricnh.shp"] = true,
    ["atwricnh.shp"] = true,
    ["oblicnh.shp"] = true,
    ["gunicnh.shp"] = true,
    ["fixicnh.shp"] = true,
    ["hpadicnh.shp"] = true,
    ["afldicnh.shp"] = true,
    ["eyeicnh.shp"] = true,
    ["tmplicnh.shp"] = true,

    -- Palettes
    ["temperat.pal"] = true,
    ["desert.pal"] = true,
    ["winter.pal"] = true,
    ["conquer.pal"] = true,
    ["scores.pal"] = true,

    -- Terrain templates (theater-specific)
    ["clear1.tem"] = true,
    ["w1.tem"] = true,
    ["w2.tem"] = true,
    ["sh1.tem"] = true,
    ["sh2.tem"] = true,
    ["sh3.tem"] = true,
    ["sh4.tem"] = true,
    ["sh5.tem"] = true,
    ["sh6.tem"] = true,
    ["sh7.tem"] = true,
    ["sh8.tem"] = true,
    ["sh9.tem"] = true,
    ["sh10.tem"] = true,
    ["sh11.tem"] = true,
    ["sh12.tem"] = true,
    ["sh13.tem"] = true,
    ["s01.tem"] = true,
    ["s02.tem"] = true,
    ["s03.tem"] = true,
    ["s04.tem"] = true,
    ["s05.tem"] = true,
    ["s06.tem"] = true,
    ["s07.tem"] = true,
    ["s08.tem"] = true,
    ["s09.tem"] = true,
    ["s10.tem"] = true,
    ["s11.tem"] = true,
    ["s12.tem"] = true,
    ["s13.tem"] = true,
    ["s14.tem"] = true,
    ["s15.tem"] = true,
    ["s16.tem"] = true,
    ["s17.tem"] = true,
    ["s18.tem"] = true,
    ["s19.tem"] = true,
    ["s20.tem"] = true,
    ["s21.tem"] = true,
    ["s22.tem"] = true,
    ["s23.tem"] = true,
    ["s24.tem"] = true,
    ["s25.tem"] = true,
    ["s26.tem"] = true,
    ["s27.tem"] = true,
    ["s28.tem"] = true,
    ["s29.tem"] = true,
    ["s30.tem"] = true,
    ["s31.tem"] = true,
    ["s32.tem"] = true,
    ["s33.tem"] = true,
    ["s34.tem"] = true,
    ["s35.tem"] = true,
    ["s36.tem"] = true,
    ["s37.tem"] = true,
    ["s38.tem"] = true,

    -- River templates
    ["rv01.tem"] = true,
    ["rv02.tem"] = true,
    ["rv03.tem"] = true,
    ["rv04.tem"] = true,
    ["rv05.tem"] = true,
    ["rv06.tem"] = true,
    ["rv07.tem"] = true,
    ["rv08.tem"] = true,
    ["rv09.tem"] = true,
    ["rv10.tem"] = true,
    ["rv11.tem"] = true,
    ["rv12.tem"] = true,
    ["rv13.tem"] = true,

    -- Falls templates
    ["falls1.tem"] = true,
    ["falls1a.tem"] = true,
    ["falls2.tem"] = true,
    ["falls2a.tem"] = true,

    -- Ford templates
    ["ford1.tem"] = true,
    ["ford2.tem"] = true,

    -- Bridge templates
    ["br1.tem"] = true,
    ["br2.tem"] = true,
    ["br3.tem"] = true,
    ["br4.tem"] = true,
    ["br5.tem"] = true,
    ["br6.tem"] = true,
    ["br7.tem"] = true,
    ["br8.tem"] = true,
    ["br9.tem"] = true,
    ["br10.tem"] = true,

    -- Trees
    ["t01.tem"] = true,
    ["t02.tem"] = true,
    ["t03.tem"] = true,
    ["t04.tem"] = true,
    ["t05.tem"] = true,
    ["t06.tem"] = true,
    ["t07.tem"] = true,
    ["t08.tem"] = true,
    ["t09.tem"] = true,
    ["t10.tem"] = true,
    ["t11.tem"] = true,
    ["t12.tem"] = true,
    ["t13.tem"] = true,
    ["t14.tem"] = true,
    ["t15.tem"] = true,
    ["t16.tem"] = true,
    ["t17.tem"] = true,
    ["t18.tem"] = true,
    ["tc01.tem"] = true,
    ["tc02.tem"] = true,
    ["tc03.tem"] = true,
    ["tc04.tem"] = true,
    ["tc05.tem"] = true,

    -- Rocks
    ["rock1.tem"] = true,
    ["rock2.tem"] = true,
    ["rock3.tem"] = true,
    ["rock4.tem"] = true,
    ["rock5.tem"] = true,
    ["rock6.tem"] = true,
    ["rock7.tem"] = true,

    -- Terrain objects (SHP in temperat/desert/winter)
    ["t01.shp"] = true,
    ["t02.shp"] = true,
    ["t03.shp"] = true,
    ["t04.shp"] = true,
    ["t05.shp"] = true,
    ["t06.shp"] = true,
    ["t07.shp"] = true,
    ["t08.shp"] = true,
    ["t09.shp"] = true,
    ["t10.shp"] = true,
    ["t11.shp"] = true,
    ["t12.shp"] = true,
    ["t13.shp"] = true,
    ["t14.shp"] = true,
    ["t15.shp"] = true,
    ["t16.shp"] = true,
    ["t17.shp"] = true,
    ["t18.shp"] = true,
    ["tc01.shp"] = true,
    ["tc02.shp"] = true,
    ["tc03.shp"] = true,
    ["tc04.shp"] = true,
    ["tc05.shp"] = true,
    ["rock1.shp"] = true,
    ["rock2.shp"] = true,
    ["rock3.shp"] = true,
    ["rock4.shp"] = true,
    ["rock5.shp"] = true,
    ["rock6.shp"] = true,
    ["rock7.shp"] = true,

    -- Smudges
    ["sc1.shp"] = true,
    ["sc2.shp"] = true,
    ["sc3.shp"] = true,
    ["sc4.shp"] = true,
    ["sc5.shp"] = true,
    ["sc6.shp"] = true,
    ["cr1.shp"] = true,
    ["cr2.shp"] = true,
    ["cr3.shp"] = true,
    ["cr4.shp"] = true,
    ["cr5.shp"] = true,
    ["cr6.shp"] = true,

    -- Mission/scenario files
    ["scg01ea.ini"] = true,
    ["scg02ea.ini"] = true,
    ["scg03ea.ini"] = true,
    ["scg04ea.ini"] = true,
    ["scg05ea.ini"] = true,
    ["scg06ea.ini"] = true,
    ["scg07ea.ini"] = true,
    ["scg08ea.ini"] = true,
    ["scg09ea.ini"] = true,
    ["scg10ea.ini"] = true,
    ["scg11ea.ini"] = true,
    ["scg12ea.ini"] = true,
    ["scg13ea.ini"] = true,
    ["scg14ea.ini"] = true,
    ["scg15ea.ini"] = true,
    ["scb01ea.ini"] = true,
    ["scb02ea.ini"] = true,
    ["scb03ea.ini"] = true,
    ["scb04ea.ini"] = true,
    ["scb05ea.ini"] = true,
    ["scb06ea.ini"] = true,
    ["scb07ea.ini"] = true,
    ["scb08ea.ini"] = true,
    ["scb09ea.ini"] = true,
    ["scb10ea.ini"] = true,
    ["scb11ea.ini"] = true,
    ["scb12ea.ini"] = true,
    ["scb13ea.ini"] = true,

    -- Map/scenario binary files
    ["scg01ea.bin"] = true,
    ["scg02ea.bin"] = true,
    ["scg03ea.bin"] = true,
    ["scg04ea.bin"] = true,
    ["scg05ea.bin"] = true,
    ["scg06ea.bin"] = true,
    ["scg07ea.bin"] = true,
    ["scg08ea.bin"] = true,
    ["scg09ea.bin"] = true,
    ["scg10ea.bin"] = true,
    ["scg11ea.bin"] = true,
    ["scg12ea.bin"] = true,
    ["scg13ea.bin"] = true,
    ["scg14ea.bin"] = true,
    ["scg15ea.bin"] = true,
    ["scb01ea.bin"] = true,
    ["scb02ea.bin"] = true,
    ["scb03ea.bin"] = true,
    ["scb04ea.bin"] = true,
    ["scb05ea.bin"] = true,
    ["scb06ea.bin"] = true,
    ["scb07ea.bin"] = true,
    ["scb08ea.bin"] = true,
    ["scb09ea.bin"] = true,
    ["scb10ea.bin"] = true,
    ["scb11ea.bin"] = true,
    ["scb12ea.bin"] = true,
    ["scb13ea.bin"] = true,

    -- Fonts
    ["6point.fnt"] = true,
    ["8point.fnt"] = true,
    ["grad6fnt.fnt"] = true,
    ["vcr.fnt"] = true,
    ["hitp.fnt"] = true,
    ["scorefnt.fnt"] = true,

    -- Audio (common)
    ["intro2.aud"] = true,
    ["hellmrch.aud"] = true,
    ["airstrik.aud"] = true,
    ["await.aud"] = true,
    ["depth.aud"] = true,
    ["destruct.aud"] = true,
    ["dron.aud"] = true,
    ["fac1.aud"] = true,
    ["fight.aud"] = true,
    ["fuel.aud"] = true,
    ["ind.aud"] = true,
    ["ion.aud"] = true,
    ["j1.aud"] = true,
    ["jdi.aud"] = true,
    ["justdoit.aud"] = true,
    ["march.aud"] = true,
    ["nomercy.aud"] = true,
    ["otp.aud"] = true,
    ["recon.aud"] = true,
    ["rout.aud"] = true,
    ["stopthem.aud"] = true,
    ["target.aud"] = true,
    ["trouble.aud"] = true,
    ["warfare.aud"] = true,
    ["wrkmen.aud"] = true,
}

-- C&C Tiberian Dawn uses a rolling hash for filename lookup
-- Reference: OpenRA PackageEntry.cs HashFilename function
-- Algorithm: Pad to 4-byte boundary, uppercase, then for each 4-byte chunk (little-endian),
-- rotate result left by 1 and add chunk value
local function calculate_crc(str)
    str = str:upper()  -- C&C uses uppercase filenames

    -- Pad string to multiple of 4 bytes with null characters
    local padding = (4 - (#str % 4)) % 4
    local padded = str .. string.rep("\0", padding)

    local result = 0

    -- Process 4 bytes at a time (little-endian order - x86 memory layout)
    for i = 1, #padded, 4 do
        local b1 = padded:byte(i) or 0
        local b2 = padded:byte(i + 1) or 0
        local b3 = padded:byte(i + 2) or 0
        local b4 = padded:byte(i + 3) or 0

        -- Little-endian 32-bit value (as read from x86 memory)
        local chunk = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216

        -- Rotate left by 1: (result << 1) | (result >> 31)
        -- Use bor to combine shifted parts for proper rotation
        local rotated = bit.bor(bit.lshift(result, 1), bit.rshift(result, 31))
        -- Mask to 32-bit before addition to avoid overflow
        rotated = bit.band(rotated, 0xFFFFFFFF)
        -- Add chunk and mask to 32-bit
        result = bit.band(rotated + chunk, 0xFFFFFFFF)
    end

    -- Convert to unsigned (mask off sign extension)
    if result < 0 then
        result = result + 0x100000000
    end

    return result
end

-- Build CRC -> name lookup
function CrcLookup.build_lookup()
    local lookup = {}

    for filename in pairs(CrcLookup.KNOWN_FILES) do
        local crc = calculate_crc(filename)
        lookup[crc] = filename
    end

    return lookup
end

-- Get lookup table
CrcLookup.BY_CRC = CrcLookup.build_lookup()

return CrcLookup
