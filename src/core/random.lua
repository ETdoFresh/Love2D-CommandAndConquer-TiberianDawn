--[[
    Random Number Generator - Exact port of RAND.CPP

    This implements the deterministic random number generator used by C&C
    for all gameplay randomness. Using the same seed produces identical
    sequences across platforms, which is critical for:
    - Multiplayer synchronization (lockstep)
    - Replay compatibility
    - Save/load consistency

    Reference: RAND.CPP from original C&C source
]]

local Random = {}

--============================================================================
-- State
--============================================================================

-- Index into the random value table (wraps at 256)
-- Matches: int SimRandIndex = 0;
Random.index = 0

-- The exact random value table from RAND.CPP
-- This is a permutation of 0-255 that provides the random sequence
Random._randvals = {
    0x47, 0xce, 0xc6, 0x6e, 0xd7, 0x9f, 0x98, 0x29, 0x92, 0x0c, 0x74, 0xa2,
    0x65, 0x20, 0x4b, 0x4f, 0x1e, 0xed, 0x3a, 0xdf, 0xa5, 0x7d, 0xb5, 0xc8,
    0x86, 0x01, 0x81, 0xca, 0xf1, 0x17, 0xd6, 0x23, 0xe1, 0xbd, 0x0e, 0xe4,
    0x62, 0xfa, 0xd9, 0x5c, 0x68, 0xf5, 0x7f, 0xdc, 0xe7, 0xb9, 0xc4, 0xb3,
    0x7a, 0xd8, 0x06, 0x3e, 0xeb, 0x09, 0x1a, 0x31, 0x3f, 0x46, 0x28, 0x12,
    0xf0, 0x10, 0x84, 0x76, 0x3b, 0xc5, 0x53, 0x18, 0x14, 0x73, 0x7e, 0x59,
    0x48, 0x93, 0xaa, 0x1d, 0x5d, 0x79, 0x24, 0x61, 0x1b, 0xfd, 0x2b, 0xa8,
    0xc2, 0xdb, 0xe8, 0x2a, 0xb0, 0x25, 0x95, 0xab, 0x96, 0x83, 0xfc, 0x5f,
    0x9c, 0x32, 0x78, 0x9a, 0x9e, 0xe2, 0x8e, 0x35, 0x4c, 0x41, 0xa1, 0x69,
    0x5a, 0xfe, 0xa7, 0xa4, 0xf6, 0x6d, 0xc1, 0x58, 0x0a, 0xcf, 0xea, 0xc3,
    0xba, 0x85, 0x99, 0x8d, 0x36, 0xb6, 0xdd, 0xd3, 0x04, 0xe6, 0x45, 0x0d,
    0x60, 0xae, 0xa3, 0x22, 0x4d, 0xe9, 0xc9, 0x9b, 0xb7, 0x0f, 0x02, 0x42,
    0xf9, 0x0b, 0x8f, 0x43, 0x44, 0x87, 0x70, 0xbe, 0xe3, 0xf8, 0xee, 0xa9,
    0xbc, 0xc0, 0x67, 0x33, 0x16, 0x37, 0x57, 0xad, 0x5e, 0x9d, 0x64, 0x40,
    0x54, 0x05, 0x2c, 0xe0, 0xb2, 0x97, 0x08, 0xaf, 0x75, 0x8a, 0x5b, 0xfb,
    0x4e, 0xbf, 0x91, 0xf3, 0xcb, 0x7c, 0x63, 0xef, 0x89, 0x52, 0x6c, 0x2f,
    0x21, 0x4a, 0xf7, 0xcd, 0x2e, 0xf4, 0xc7, 0x6f, 0x19, 0xb1, 0x66, 0xcc,
    0x90, 0x8c, 0x50, 0x51, 0x26, 0x7b, 0xda, 0x49, 0x80, 0x30, 0x55, 0x1f,
    0xd2, 0xb4, 0xd1, 0xd5, 0x6b, 0xf2, 0x72, 0xbb, 0x13, 0x3d, 0xff, 0x15,
    0x38, 0xe5, 0xd4, 0xde, 0x2d, 0x27, 0x94, 0xa0, 0xd0, 0x39, 0x82, 0x8b,
    0x03, 0xac, 0x3c, 0x34, 0x77, 0xb8, 0xec, 0x00, 0x07, 0x1c, 0x88, 0xa6,
    0x56, 0x11, 0x71, 0x6a,
}

--============================================================================
-- Core Functions
--============================================================================

--[[
    Sim_Random - Returns 0-255

    Port of Sim_Random() from RAND.CPP.
    Advances the index and returns the value at that position in the table.
    The index wraps at 256 using unsigned char math.

    @return Integer in range [0, 255]
]]
function Random.Sim_Random()
    -- Increment and wrap at 256 (unsigned char behavior)
    Random.index = (Random.index + 1) % 256

    -- Lua tables are 1-indexed, so add 1
    return Random._randvals[Random.index + 1]
end

--[[
    Sim_IRandom - Returns minval to maxval, inclusive

    Port of Sim_IRandom() from RAND.CPP.
    Uses fixed-point math to scale the random value to the desired range.

    Original: return(Fixed_To_Cardinal((maxval-minval), Sim_Random()) + minval);

    @param minval Minimum value (inclusive)
    @param maxval Maximum value (inclusive)
    @return Integer in range [minval, maxval]
]]
function Random.Sim_IRandom(minval, maxval)
    -- Fixed_To_Cardinal(a, b) = (a * b) / 256
    -- This scales the 0-255 random value to the 0-(maxval-minval) range
    local range = maxval - minval
    local random_value = Random.Sim_Random()

    -- Fixed point: (range * random_value) / 256
    -- Use math.floor to match C integer division
    return math.floor((range * random_value) / 256) + minval
end

--============================================================================
-- Seed & State Management
--============================================================================

--[[
    Set the random seed (index position).

    In the original, the seed is simply the starting index into the table.
    Setting the same seed produces the same sequence of random numbers.

    @param seed Integer seed value (will be masked to 0-255)
]]
function Random.Set_Seed(seed)
    Random.index = seed % 256
end

--[[
    Get the current random state (for sync checking and save/load).

    @return Current index value
]]
function Random.Get_Seed()
    return Random.index
end

--[[
    Reset to initial state (index = 0).
]]
function Random.Reset()
    Random.index = 0
end

--============================================================================
-- Convenience Functions
--============================================================================

--[[
    Random percentage check.

    @param percent Chance of returning true (0-100)
    @return true if random roll succeeds
]]
function Random.Percent(percent)
    return Random.Sim_IRandom(0, 99) < percent
end

--[[
    Random value in range [0, max-1].

    @param max Upper bound (exclusive)
    @return Integer in range [0, max-1]
]]
function Random.Random(max)
    if max <= 1 then return 0 end
    return Random.Sim_IRandom(0, max - 1)
end

--[[
    Pick a random element from a table.

    @param t Table to pick from
    @return Random element from the table, or nil if empty
]]
function Random.Pick(t)
    local count = #t
    if count == 0 then return nil end
    return t[Random.Sim_IRandom(1, count)]
end

--[[
    Shuffle a table in place using Fisher-Yates algorithm.

    @param t Table to shuffle
    @return The same table, shuffled
]]
function Random.Shuffle(t)
    for i = #t, 2, -1 do
        local j = Random.Sim_IRandom(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--============================================================================
-- CRC for Sync Checking
--============================================================================

--[[
    Get a CRC of the current random state for sync verification.
    In multiplayer, all clients should have the same RNG state at each frame.

    @return CRC value of current state
]]
function Random.Get_CRC()
    -- Simple CRC: just return the index
    -- The index fully determines the RNG state
    return Random.index
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of random state.
]]
function Random.Debug_Dump()
    print("Random:")
    print(string.format("  Index: %d (0x%02X)", Random.index, Random.index))

    -- Show next few values that will be generated
    local preview = {}
    local saved_index = Random.index
    for i = 1, 5 do
        preview[i] = Random.Sim_Random()
    end
    Random.index = saved_index  -- Restore

    print(string.format("  Next 5 values: %d, %d, %d, %d, %d",
        preview[1], preview[2], preview[3], preview[4], preview[5]))
end

return Random
