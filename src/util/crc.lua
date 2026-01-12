--[[
    CRC32 Utility - Checksum calculation for multiplayer sync verification
    Based on standard CRC-32 (IEEE 802.3) polynomial
    Used for deterministic lockstep sync validation
]]

local CRC32 = {}

-- CRC-32 polynomial (IEEE 802.3)
local POLYNOMIAL = 0xEDB88320

-- Precomputed CRC table for performance
local crc_table = {}

-- Initialize CRC lookup table
local function init_table()
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if bit.band(crc, 1) == 1 then
                crc = bit.bxor(bit.rshift(crc, 1), POLYNOMIAL)
            else
                crc = bit.rshift(crc, 1)
            end
        end
        crc_table[i] = crc
    end
end

-- Initialize table on module load
init_table()

-- Calculate CRC32 of a string
function CRC32.string(s)
    local crc = 0xFFFFFFFF

    for i = 1, #s do
        local byte = string.byte(s, i)
        local index = bit.band(bit.bxor(crc, byte), 0xFF)
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[index])
    end

    return bit.bxor(crc, 0xFFFFFFFF)
end

-- Calculate CRC32 of a number (converted to 4 bytes, little-endian)
function CRC32.number(n)
    local crc = 0xFFFFFFFF

    -- Process as 4-byte integer
    for _ = 1, 4 do
        local byte = bit.band(n, 0xFF)
        local index = bit.band(bit.bxor(crc, byte), 0xFF)
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[index])
        n = bit.rshift(n, 8)
    end

    return bit.bxor(crc, 0xFFFFFFFF)
end

-- Combine two CRC values (useful for incremental checksums)
function CRC32.combine(crc1, crc2)
    return bit.bxor(crc1, crc2)
end

-- Calculate CRC32 of a table of values (for game state sync)
function CRC32.table(t)
    local crc = 0

    -- Sort keys for deterministic ordering
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local v = t[k]
        local vtype = type(v)

        -- Hash the key
        crc = CRC32.combine(crc, CRC32.string(tostring(k)))

        -- Hash the value based on type
        if vtype == "number" then
            -- Convert to integer for determinism
            crc = CRC32.combine(crc, CRC32.number(math.floor(v * 1000)))
        elseif vtype == "string" then
            crc = CRC32.combine(crc, CRC32.string(v))
        elseif vtype == "boolean" then
            crc = CRC32.combine(crc, v and 1 or 0)
        elseif vtype == "table" then
            crc = CRC32.combine(crc, CRC32.table(v))
        end
        -- Skip functions, userdata, etc.
    end

    return crc
end

-- Calculate game state checksum for sync verification
-- Takes key game state values and produces a deterministic CRC
function CRC32.game_state(entities, tick)
    local crc = CRC32.number(tick)

    -- Sort entities by ID for deterministic ordering
    local sorted = {}
    for _, entity in ipairs(entities) do
        table.insert(sorted, entity)
    end
    table.sort(sorted, function(a, b)
        return a.id < b.id
    end)

    for _, entity in ipairs(sorted) do
        -- Hash entity ID
        crc = CRC32.combine(crc, CRC32.number(entity.id))

        -- Hash transform if present
        if entity.transform then
            crc = CRC32.combine(crc, CRC32.number(math.floor(entity.transform.x)))
            crc = CRC32.combine(crc, CRC32.number(math.floor(entity.transform.y)))
        end

        -- Hash health if present
        if entity.health then
            crc = CRC32.combine(crc, CRC32.number(math.floor(entity.health.hp)))
        end

        -- Hash mission if present
        if entity.mission then
            crc = CRC32.combine(crc, CRC32.number(entity.mission.mission_type or 0))
        end

        -- Hash owner if present
        if entity.owner then
            crc = CRC32.combine(crc, CRC32.number(entity.owner.house or 0))
        end
    end

    return crc
end

-- Simplified state hash for quick sync checks
-- Returns CRC of just positions and health for all entities
function CRC32.quick_state(world, tick)
    if not world then return 0 end

    local crc = CRC32.number(tick)

    local entities = world:get_entities_with("transform")

    -- Sort by ID
    table.sort(entities, function(a, b) return a.id < b.id end)

    for _, entity in ipairs(entities) do
        local transform = entity:get("transform")

        -- Include entity ID
        crc = CRC32.combine(crc, CRC32.number(entity.id))

        -- Include position (as integers)
        crc = CRC32.combine(crc, CRC32.number(math.floor(transform.x)))
        crc = CRC32.combine(crc, CRC32.number(math.floor(transform.y)))

        -- Include health if present
        if entity:has("health") then
            local health = entity:get("health")
            crc = CRC32.combine(crc, CRC32.number(math.floor(health.hp)))
        end
    end

    return crc
end

return CRC32
