--[[
    Core game constants matching original C&C Tiberian Dawn values
    Reference: DEFINES.H, DISPLAY.H
]]

local Constants = {}

-- Timing (from DEFINES.H)
Constants.TICKS_PER_SECOND = 15
Constants.TICKS_PER_MINUTE = Constants.TICKS_PER_SECOND * 60
Constants.TICK_DURATION = 1 / Constants.TICKS_PER_SECOND  -- ~0.0667 seconds

-- Lepton coordinate system (from DISPLAY.H)
-- Leptons are the sub-cell coordinate unit: 256 leptons = 1 cell
Constants.LEPTON_PER_CELL = 256
Constants.CELL_LEPTON_W = 256
Constants.CELL_LEPTON_H = 256

-- Map dimensions (from DEFINES.H)
Constants.MAP_CELL_MAX_X_BITS = 6
Constants.MAP_CELL_MAX_Y_BITS = 6
Constants.MAP_CELL_W = 64  -- 2^6
Constants.MAP_CELL_H = 64  -- 2^6
Constants.MAP_CELL_TOTAL = Constants.MAP_CELL_W * Constants.MAP_CELL_H

-- Display settings
Constants.ICON_PIXEL_W = 24  -- Classic cell size in pixels
Constants.ICON_PIXEL_H = 24
Constants.CELL_PIXEL_W = Constants.ICON_PIXEL_W
Constants.CELL_PIXEL_H = Constants.ICON_PIXEL_H

-- Pixel to lepton conversion
Constants.PIXEL_LEPTON_W = Constants.LEPTON_PER_CELL / Constants.ICON_PIXEL_W
Constants.PIXEL_LEPTON_H = Constants.LEPTON_PER_CELL / Constants.ICON_PIXEL_H

-- Resolution modes
Constants.CLASSIC_WIDTH = 320
Constants.CLASSIC_HEIGHT = 200
Constants.HD_WIDTH = 1920
Constants.HD_HEIGHT = 1080

-- Rendering
Constants.RENDER_FPS = 60

-- Game speed levels (multipliers)
Constants.GAME_SPEED = {
    SLOWEST = 0.5,
    SLOWER = 0.75,
    NORMAL = 1.0,
    FASTER = 1.5,
    FASTEST = 2.0
}

-- Regions for pathfinding optimization
Constants.REGION_WIDTH = 4
Constants.REGION_HEIGHT = 4

-- Maximum players
Constants.MAX_PLAYERS = 6

-- Direction count
Constants.FACING_COUNT = 8      -- 8 cardinal directions
Constants.FACING_FULL = 32      -- Full rotation precision

-- Refresh markers
Constants.REFRESH_EOL = 32767
Constants.REFRESH_SIDEBAR = 32766

-- Economy
Constants.REPAIR_THRESHOLD = 1000  -- Credits threshold for AI repair

-- Special weapon timers (in ticks)
Constants.NUKE_COOLDOWN = 14 * Constants.TICKS_PER_MINUTE
Constants.ION_CANNON_COOLDOWN = 10 * Constants.TICKS_PER_MINUTE
Constants.AIR_STRIKE_COOLDOWN = 8 * Constants.TICKS_PER_MINUTE

-- Houses (factions)
Constants.HOUSE = {
    NONE = -1,
    GOOD = 0,       -- GDI
    BAD = 1,        -- Nod
    NEUTRAL = 2,    -- Civilians
    JP = 3,         -- Disaster Containment Team
    MULTI1 = 4,
    MULTI2 = 5,
    MULTI3 = 6,
    MULTI4 = 7,
    MULTI5 = 8,
    MULTI6 = 9,
    COUNT = 10
}

-- Player colors
Constants.PLAYER_COLOR = {
    NONE = -1,
    GOLD = 0,
    LTBLUE = 1,
    RED = 2,
    GREEN = 3,
    ORANGE = 4,
    BLUE = 5,
    COUNT = 6
}

-- Layer types for rendering order
Constants.LAYER = {
    NONE = -1,
    GROUND = 0,     -- Units & buildings on ground
    AIR = 1,        -- Explosions & flames
    TOP = 2,        -- Aircraft & bullets
    COUNT = 3
}

-- Movement result types
Constants.MOVE = {
    OK = 0,
    CLOAK = 1,
    MOVING_BLOCK = 2,
    DESTROYABLE = 3,
    TEMP = 4,
    NO = 5,
    COUNT = 6
}

-- Mission types (AI behavior states)
Constants.MISSION = {
    NONE = -1,
    SLEEP = 0,
    ATTACK = 1,
    MOVE = 2,
    RETREAT = 3,
    GUARD = 4,
    STICKY = 5,
    ENTER = 6,
    CAPTURE = 7,
    HARVEST = 8,
    GUARD_AREA = 9,
    RETURN = 10,
    STOP = 11,
    AMBUSH = 12,
    HUNT = 13,
    TIMED_HUNT = 14,
    UNLOAD = 15,
    SABOTAGE = 16,
    CONSTRUCTION = 17,
    DECONSTRUCTION = 18,
    REPAIR = 19,
    RESCUE = 20,
    MISSILE = 21,
    COUNT = 22
}

-- Action types (cursor/command actions)
Constants.ACTION = {
    NONE = 0,
    MOVE = 1,
    NOMOVE = 2,
    ENTER = 3,
    SELF = 4,
    ATTACK = 5,
    HARVEST = 6,
    SELECT = 7,
    TOGGLE_SELECT = 8,
    CAPTURE = 9,
    REPAIR = 10,
    SELL = 11,
    SELL_UNIT = 12,
    NO_SELL = 13,
    NO_REPAIR = 14,
    SABOTAGE = 15,
    ION = 16,
    NUKE_BOMB = 17,
    AIR_STRIKE = 18,
    GUARD_AREA = 19,
    TOGGLE_PRIMARY = 20,
    NO_DEPLOY = 21,
    COUNT = 22
}

-- Fire error types
Constants.FIRE = {
    OK = 0,
    AMMO = 1,
    FACING = 2,
    REARM = 3,
    ROTATING = 4,
    ILLEGAL = 5,
    CANT = 6,
    MOVING = 7,
    RANGE = 8,
    CLOAKED = 9,
    BUSY = 10
}

-- Cloak states
Constants.CLOAK = {
    UNCLOAKED = 0,
    CLOAKING = 1,
    CLOAKED = 2,
    UNCLOAKING = 3
}

-- Difficulty levels
Constants.DIFFICULTY = {
    EASY = 0,
    NORMAL = 1,
    HARD = 2,
    COUNT = 3
}

-- Theaters (terrain themes)
Constants.THEATER = {
    NONE = -1,
    TEMPERATE = 0,
    DESERT = 1,
    WINTER = 2,
    COUNT = 3
}

-- Special weapons
Constants.SPECIAL_WEAPON = {
    NONE = 0,
    ION_CANNON = 1,
    NUCLEAR_BOMB = 2,
    AIR_STRIKE = 3
}

-- Overlay types (from OVERLAY.H)
-- These match original C&C values
Constants.OVERLAY = {
    NONE = -1,
    SANDBAG = 0,       -- Sandbag wall
    CYCLONE = 1,       -- Chain link fence
    BRICK = 2,         -- Concrete wall
    BARBWIRE = 3,      -- Barbed wire
    WOOD = 4,          -- Wood wall
    -- Tiberium (6-17)
    TI1 = 6,           -- Tiberium stage 1
    TI2 = 7,           -- Tiberium stage 2
    TI3 = 8,           -- Tiberium stage 3
    TI4 = 9,           -- Tiberium stage 4
    TI5 = 10,          -- Tiberium stage 5
    TI6 = 11,          -- Tiberium stage 6
    TI7 = 12,          -- Tiberium stage 7
    TI8 = 13,          -- Tiberium stage 8
    TI9 = 14,          -- Tiberium stage 9
    TI10 = 15,         -- Tiberium stage 10
    TI11 = 16,         -- Tiberium stage 11
    TI12 = 17,         -- Tiberium stage 12
    -- Other overlays
    SQUISH = 18,       -- Squished infantry
    V12 = 19,          -- Haystacks
    V13 = 20,          -- Haystacks 2
    V14 = 21,          -- Wheat field
    V15 = 22,          -- Fallow field
    V16 = 23,          -- Corn
    V17 = 24,          -- Celery
    V18 = 25,          -- Potato
    FPLS = 26,         -- Flag placement (multiplayer)
    WCRATE = 27,       -- Wood crate (power-up)
    SCRATE = 28        -- Steel crate (power-up)
}

-- Tiberium value per overlay stage
Constants.TIBERIUM_VALUE = {
    [6] = 25,   -- TI1
    [7] = 26,
    [8] = 27,
    [9] = 28,
    [10] = 29,
    [11] = 30,
    [12] = 31,
    [13] = 32,
    [14] = 33,
    [15] = 34,
    [16] = 35,
    [17] = 36   -- TI12 (maximum growth)
}

return Constants
