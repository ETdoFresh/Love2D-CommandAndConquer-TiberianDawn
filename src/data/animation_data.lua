--[[
    Animation Data - Frame tables for infantry and vehicle animations
    Based on original C&C Tiberian Dawn source code (IDATA.CPP, INFANTRY.CPP)

    Infantry animations use 8 facing directions (via HumanShape remapping)
    Vehicles use 32 or 64 facing directions (one frame per direction)
]]

local AnimationData = {}

-- Animation states (DoType enum from DEFINES.H)
AnimationData.DO = {
    STAND_READY = 1,
    STAND_GUARD = 2,
    PRONE = 3,
    WALK = 4,
    FIRE_WEAPON = 5,
    LIE_DOWN = 6,
    CRAWL = 7,
    GET_UP = 8,
    FIRE_PRONE = 9,
    IDLE1 = 10,
    IDLE2 = 11,
    ON_GUARD = 12,
    FIGHT_READY = 13,
    PUNCH = 14,
    KICK = 15,
    PUNCH_HIT1 = 16,
    PUNCH_HIT2 = 17,
    PUNCH_DEATH = 18,
    KICK_HIT1 = 19,
    KICK_HIT2 = 20,
    KICK_DEATH = 21,
    READY_WEAPON = 22,
    GUN_DEATH = 23,
    EXPLOSION_DEATH = 24,
    EXPLOSION2_DEATH = 25,
    GRENADE_DEATH = 26,
    FIRE_DEATH = 27,
    GESTURE1 = 28,
    SALUTE1 = 29,
    GESTURE2 = 30,
    SALUTE2 = 31,
    PULL_GUN = 32,
    PLEAD = 33,
    PLEAD_DEATH = 34,
}

-- HumanShape remapping: 32 directions -> 8 visible shapes (0-7)
-- Infantry sprites only have 8 facing directions, so we remap
AnimationData.HUMAN_SHAPE = {
    0, 0, 7, 7, 7, 7, 6, 6,
    6, 6, 5, 5, 5, 5, 5, 4,
    4, 4, 3, 3, 3, 3, 2, 2,
    2, 2, 1, 1, 1, 1, 1, 0
}

-- Animation entry: {frame_offset, frame_count, frame_rate}
-- frame_offset: Starting frame in the spritesheet for this animation
-- frame_count: Number of frames in the animation
-- frame_rate: Ticks between frame changes (0 = no animation, just hold)

-- E1 - Minigunner infantry animations
AnimationData.E1 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.PRONE] = {192, 4, 0},
    [AnimationData.DO.WALK] = {16, 6, 2},
    [AnimationData.DO.FIRE_WEAPON] = {64, 8, 1},
    [AnimationData.DO.LIE_DOWN] = {192, 4, 2},
    [AnimationData.DO.CRAWL] = {208, 4, 2},
    [AnimationData.DO.GET_UP] = {192, 4, 2},
    [AnimationData.DO.FIRE_PRONE] = {240, 6, 1},
    [AnimationData.DO.IDLE1] = {256, 16, 2},
    [AnimationData.DO.IDLE2] = {272, 16, 2},
    [AnimationData.DO.GUN_DEATH] = {288, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {304, 8, 2},
    [AnimationData.DO.EXPLOSION2_DEATH] = {320, 8, 2},
    [AnimationData.DO.GRENADE_DEATH] = {336, 12, 2},
    [AnimationData.DO.FIRE_DEATH] = {360, 18, 2},
}

-- E2 - Grenadier infantry animations
AnimationData.E2 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.PRONE] = {192, 4, 0},
    [AnimationData.DO.WALK] = {16, 6, 2},
    [AnimationData.DO.FIRE_WEAPON] = {64, 20, 2},
    [AnimationData.DO.LIE_DOWN] = {192, 4, 2},
    [AnimationData.DO.CRAWL] = {224, 4, 2},
    [AnimationData.DO.GET_UP] = {192, 4, 2},
    [AnimationData.DO.FIRE_PRONE] = {256, 10, 2},
    [AnimationData.DO.IDLE1] = {336, 16, 2},
    [AnimationData.DO.IDLE2] = {352, 16, 2},
    [AnimationData.DO.GUN_DEATH] = {368, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {384, 8, 2},
    [AnimationData.DO.EXPLOSION2_DEATH] = {400, 8, 2},
    [AnimationData.DO.GRENADE_DEATH] = {416, 12, 2},
    [AnimationData.DO.FIRE_DEATH] = {440, 18, 2},
}

-- E3 - Rocket soldier
AnimationData.E3 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.PRONE] = {192, 4, 0},
    [AnimationData.DO.WALK] = {16, 6, 2},
    [AnimationData.DO.FIRE_WEAPON] = {64, 16, 2},
    [AnimationData.DO.LIE_DOWN] = {192, 4, 2},
    [AnimationData.DO.CRAWL] = {224, 4, 2},
    [AnimationData.DO.GET_UP] = {192, 4, 2},
    [AnimationData.DO.FIRE_PRONE] = {256, 8, 2},
    [AnimationData.DO.IDLE1] = {320, 14, 2},
    [AnimationData.DO.IDLE2] = {334, 14, 2},
    [AnimationData.DO.GUN_DEATH] = {348, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {364, 8, 2},
    [AnimationData.DO.EXPLOSION2_DEATH] = {380, 8, 2},
    [AnimationData.DO.GRENADE_DEATH] = {396, 12, 2},
    [AnimationData.DO.FIRE_DEATH] = {420, 18, 2},
}

-- E4 - Flamethrower
AnimationData.E4 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.PRONE] = {192, 4, 0},
    [AnimationData.DO.WALK] = {16, 6, 2},
    [AnimationData.DO.FIRE_WEAPON] = {64, 16, 2},
    [AnimationData.DO.LIE_DOWN] = {192, 4, 2},
    [AnimationData.DO.CRAWL] = {224, 4, 2},
    [AnimationData.DO.GET_UP] = {192, 4, 2},
    [AnimationData.DO.FIRE_PRONE] = {256, 8, 2},
    [AnimationData.DO.IDLE1] = {320, 16, 2},
    [AnimationData.DO.IDLE2] = {336, 16, 2},
    [AnimationData.DO.GUN_DEATH] = {352, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {368, 8, 2},
    [AnimationData.DO.EXPLOSION2_DEATH] = {384, 8, 2},
    [AnimationData.DO.GRENADE_DEATH] = {400, 12, 2},
    [AnimationData.DO.FIRE_DEATH] = {424, 18, 2},
}

-- E5 - Engineer
AnimationData.E5 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.WALK] = {8, 6, 2},
    [AnimationData.DO.IDLE1] = {56, 16, 2},
    [AnimationData.DO.IDLE2] = {72, 16, 2},
    [AnimationData.DO.GUN_DEATH] = {88, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {104, 8, 2},
    [AnimationData.DO.EXPLOSION2_DEATH] = {120, 8, 2},
    [AnimationData.DO.GRENADE_DEATH] = {136, 12, 2},
    [AnimationData.DO.FIRE_DEATH] = {160, 18, 2},
}

-- E6 - Commando
AnimationData.E6 = {
    [AnimationData.DO.STAND_READY] = {0, 1, 0},
    [AnimationData.DO.STAND_GUARD] = {0, 1, 0},
    [AnimationData.DO.PRONE] = {128, 4, 0},
    [AnimationData.DO.WALK] = {16, 6, 2},
    [AnimationData.DO.FIRE_WEAPON] = {64, 8, 1},
    [AnimationData.DO.LIE_DOWN] = {128, 4, 2},
    [AnimationData.DO.CRAWL] = {144, 4, 2},
    [AnimationData.DO.GET_UP] = {128, 4, 2},
    [AnimationData.DO.FIRE_PRONE] = {160, 6, 1},
    [AnimationData.DO.GUN_DEATH] = {192, 8, 2},
    [AnimationData.DO.EXPLOSION_DEATH] = {208, 8, 2},
}

-- RMBO - Commando (alternate name)
AnimationData.RMBO = AnimationData.E6

-- Vehicle animation types
AnimationData.VEHICLE = {
    IDLE = 1,
    MOVING = 2,
    HARVESTING = 3,
    FIRING = 4,
}

-- Vehicle data: {total_frames, has_turret, turret_offset}
-- Most vehicles have 32 body directions
-- Tanks with turrets have separate turret frames
AnimationData.VEHICLES = {
    mtnk = {frames = 32, has_turret = true, turret_offset = 32},
    htnk = {frames = 32, has_turret = true, turret_offset = 32},
    ltnk = {frames = 32, has_turret = true, turret_offset = 32},
    apc = {frames = 32, has_turret = false},
    harv = {frames = 32, has_turret = false},
    mcv = {frames = 32, has_turret = false},
    jeep = {frames = 32, has_turret = true, turret_offset = 32},
    bggy = {frames = 32, has_turret = true, turret_offset = 32},
    bike = {frames = 32, has_turret = false},
    arty = {frames = 32, has_turret = false},
    mlrs = {frames = 32, has_turret = true, turret_offset = 32},
    msam = {frames = 32, has_turret = true, turret_offset = 32},
    stnk = {frames = 32, has_turret = false},
    ftnk = {frames = 32, has_turret = false},
}

-- Aircraft data
AnimationData.AIRCRAFT = {
    orca = {frames = 32, rotor_frames = 4, rotor_offset = 32},
    heli = {frames = 32, rotor_frames = 4, rotor_offset = 0},
    tran = {frames = 32, rotor_frames = 4, rotor_offset = 0},
    a10 = {frames = 32, rotor_frames = 0},
    c17 = {frames = 32, rotor_frames = 0},
}

-- Building animation data
AnimationData.BUILDINGS = {
    fact = {frames = 49, anim_rate = 3},  -- Construction yard
    pyle = {frames = 21, anim_rate = 3},  -- Barracks
    hand = {frames = 3, anim_rate = 4},   -- Hand of Nod
    weap = {frames = 3, anim_rate = 4},   -- Weapons factory
    proc = {frames = 61, anim_rate = 3},  -- Refinery
    silo = {frames = 11, anim_rate = 0},  -- Silo (levels based on tiberium)
    nuke = {frames = 9, anim_rate = 4},   -- Power plant
    nuk2 = {frames = 9, anim_rate = 4},   -- Advanced power
    hq = {frames = 33, anim_rate = 3},    -- Communications center
    hpad = {frames = 15, anim_rate = 0},  -- Helipad
    afld = {frames = 33, anim_rate = 3},  -- Airfield
    gtwr = {frames = 3, anim_rate = 0},   -- Guard tower
    atwr = {frames = 3, anim_rate = 0},   -- Advanced guard tower
    sam = {frames = 129, anim_rate = 2},  -- SAM site (rotating)
    gun = {frames = 128, anim_rate = 2},  -- Turret (rotating)
    obli = {frames = 9, anim_rate = 4},   -- Obelisk
    eye = {frames = 33, anim_rate = 3},   -- Temple of Nod
    tmpl = {frames = 11, anim_rate = 4},  -- Temple
    fix = {frames = 15, anim_rate = 3},   -- Repair facility
    bio = {frames = 3, anim_rate = 4},    -- Bio lab
    hosp = {frames = 9, anim_rate = 4},   -- Hospital
}

-- Effect animations (simple looping)
AnimationData.EFFECTS = {
    fball1 = {frames = 18, rate = 1, loops = false},
    fire1 = {frames = 15, rate = 2, loops = true},
    fire2 = {frames = 15, rate = 2, loops = true},
    fire3 = {frames = 15, rate = 2, loops = true},
    fire4 = {frames = 15, rate = 2, loops = true},
    smokey = {frames = 7, rate = 2, loops = true},
    piff = {frames = 4, rate = 1, loops = false},
    piffpiff = {frames = 8, rate = 1, loops = false},
    atomsfx = {frames = 27, rate = 1, loops = false},
}

-- Get animation data for an infantry type
function AnimationData.get_infantry_data(infantry_type)
    local type_upper = infantry_type:upper()
    return AnimationData[type_upper]
end

-- Get frame for infantry given state and facing
-- @param infantry_type: e.g., "e1", "e2"
-- @param anim_state: DoType state
-- @param facing: 0-31 direction (will be remapped to 0-7)
-- @param frame_in_cycle: current frame within animation (0-based)
function AnimationData.get_infantry_frame(infantry_type, anim_state, facing, frame_in_cycle)
    local data = AnimationData.get_infantry_data(infantry_type)
    if not data then return 0 end

    local anim = data[anim_state]
    if not anim then
        -- Fall back to stand ready
        anim = data[AnimationData.DO.STAND_READY]
        if not anim then return 0 end
    end

    local frame_offset, frame_count, _ = anim[1], anim[2], anim[3]

    -- Remap 32 directions to 8 shape directions (1-based index)
    local shape_dir = AnimationData.HUMAN_SHAPE[(facing % 32) + 1]

    -- Calculate frame: base + (direction * frames_per_dir) + frame_in_cycle
    -- Each direction has frame_count frames
    local frame = frame_offset + (shape_dir * frame_count) + (frame_in_cycle % frame_count)

    return frame
end

-- Get frame for vehicle given facing
-- @param vehicle_type: e.g., "mtnk", "harv"
-- @param facing: 0-31 direction
function AnimationData.get_vehicle_frame(vehicle_type, facing)
    local data = AnimationData.VEHICLES[vehicle_type:lower()]
    if not data then return facing % 32 end

    -- Vehicles typically have 32 frames for body rotation
    return facing % data.frames
end

-- Get turret frame for vehicle
-- @param vehicle_type: e.g., "mtnk"
-- @param turret_facing: 0-31 turret direction
function AnimationData.get_turret_frame(vehicle_type, turret_facing)
    local data = AnimationData.VEHICLES[vehicle_type:lower()]
    if not data or not data.has_turret then return nil end

    return data.turret_offset + (turret_facing % 32)
end

-- Get animation rate (ticks per frame) for infantry animation
function AnimationData.get_infantry_rate(infantry_type, anim_state)
    local data = AnimationData.get_infantry_data(infantry_type)
    if not data then return 2 end

    local anim = data[anim_state]
    if not anim then return 2 end

    return anim[3]
end

-- Get frame count for infantry animation
function AnimationData.get_infantry_frame_count(infantry_type, anim_state)
    local data = AnimationData.get_infantry_data(infantry_type)
    if not data then return 1 end

    local anim = data[anim_state]
    if not anim then return 1 end

    return anim[2]
end

return AnimationData
