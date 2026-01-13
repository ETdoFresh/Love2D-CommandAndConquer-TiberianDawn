--[[
    Pointers - Object reference encoding/decoding for save/load

    This module implements the Code_Pointers/Decode_Pointers pattern from C&C.
    In the original, object pointers cannot be directly saved to disk because
    memory addresses change between sessions. Instead:

    1. Code_Pointers() converts object pointers to heap indices before saving
    2. Decode_Pointers() converts heap indices back to object pointers after loading

    In Lua, we don't have raw pointers, but we have the same problem with
    object references - they're runtime identities that don't persist.
    This module provides the same solution: encode references as type+index pairs.

    Reference: Code_Pointers/Decode_Pointers in various .CPP files
]]

local Pointers = {}

--============================================================================
-- RTTI Types (Run-Time Type Information)
-- Matches the RTTIType enum from the original
--============================================================================
Pointers.RTTI = {
    NONE = 0,
    UNIT = 1,
    BUILDING = 2,
    INFANTRY = 3,
    AIRCRAFT = 4,
    BULLET = 5,
    ANIM = 6,
    TRIGGER = 7,
    TEAM = 8,
    TEAMTYPE = 9,
    TERRAIN = 10,
    OVERLAY = 11,
    SMUDGE = 12,
    CELL = 13,
    HOUSE = 14,
    FACTORY = 15,
    -- Type classes
    UNITTYPE = 16,
    BUILDINGTYPE = 17,
    INFANTRYTYPE = 18,
    AIRCRAFTTYPE = 19,
    BULLETTYPE = 20,
    ANIMTYPE = 21,
    TERRAINTYPE = 22,
    OVERLAYTYPE = 23,
    SMUDGETYPE = 24,
    WEAPONTYPE = 25,
    WARHEADTYPE = 26,
}

-- Reverse lookup
Pointers.RTTI_NAMES = {}
for name, value in pairs(Pointers.RTTI) do
    Pointers.RTTI_NAMES[value] = name
end

--============================================================================
-- Object Heaps Reference
-- These will be set by the game during initialization
--============================================================================
Pointers.heaps = {
    -- Object heaps (runtime instances)
    [Pointers.RTTI.UNIT] = nil,
    [Pointers.RTTI.BUILDING] = nil,
    [Pointers.RTTI.INFANTRY] = nil,
    [Pointers.RTTI.AIRCRAFT] = nil,
    [Pointers.RTTI.BULLET] = nil,
    [Pointers.RTTI.ANIM] = nil,
    [Pointers.RTTI.TRIGGER] = nil,
    [Pointers.RTTI.TEAM] = nil,
    [Pointers.RTTI.TERRAIN] = nil,
    [Pointers.RTTI.OVERLAY] = nil,
    [Pointers.RTTI.SMUDGE] = nil,
    [Pointers.RTTI.FACTORY] = nil,
    [Pointers.RTTI.HOUSE] = nil,
}

-- Type registries (static type definitions)
Pointers.type_registries = {
    [Pointers.RTTI.UNITTYPE] = nil,
    [Pointers.RTTI.BUILDINGTYPE] = nil,
    [Pointers.RTTI.INFANTRYTYPE] = nil,
    [Pointers.RTTI.AIRCRAFTTYPE] = nil,
    [Pointers.RTTI.BULLETTYPE] = nil,
    [Pointers.RTTI.ANIMTYPE] = nil,
    [Pointers.RTTI.TERRAINTYPE] = nil,
    [Pointers.RTTI.OVERLAYTYPE] = nil,
    [Pointers.RTTI.SMUDGETYPE] = nil,
    [Pointers.RTTI.WEAPONTYPE] = nil,
    [Pointers.RTTI.WARHEADTYPE] = nil,
}

--============================================================================
-- Registration
--============================================================================

--[[
    Register an object heap for a given RTTI type.
    The heap should support get_by_index() and get_index() methods.

    @param rtti_type RTTI type constant
    @param heap Heap object or table with objects
]]
function Pointers.register_heap(rtti_type, heap)
    Pointers.heaps[rtti_type] = heap
end

--[[
    Register a type registry for a given RTTI type.

    @param rtti_type RTTI type constant
    @param registry Registry table mapping names/IDs to type objects
]]
function Pointers.register_type_registry(rtti_type, registry)
    Pointers.type_registries[rtti_type] = registry
end

--============================================================================
-- Encoding (Code_Pointers equivalent)
--============================================================================

--[[
    Encode an object reference to a serializable format.

    Converts a runtime object reference to a {rtti, index} pair that can
    be saved to disk and later decoded back to the object.

    @param obj Object reference (or nil)
    @param expected_rtti Optional expected RTTI type for validation
    @return Table {rtti=type, index=heap_index} or nil if obj is nil
]]
function Pointers.encode(obj, expected_rtti)
    if obj == nil then
        return nil
    end

    -- Get RTTI type from object
    local rtti = Pointers.get_rtti(obj)
    if rtti == Pointers.RTTI.NONE then
        print("Warning: Cannot encode object with unknown RTTI type")
        return nil
    end

    -- Validate expected type if provided
    if expected_rtti and rtti ~= expected_rtti then
        print(string.format("Warning: Expected RTTI %s but got %s",
            Pointers.RTTI_NAMES[expected_rtti] or "?",
            Pointers.RTTI_NAMES[rtti] or "?"))
    end

    -- Get index in heap
    local index = Pointers.get_heap_index(obj, rtti)
    if index == nil then
        print(string.format("Warning: Object not found in heap for RTTI %s",
            Pointers.RTTI_NAMES[rtti] or "?"))
        return nil
    end

    return {
        rtti = rtti,
        index = index
    }
end

--[[
    Encode a TARGET value.

    TARGETs in C&C are packed values containing RTTI type and heap index.
    This function handles TARGET-style encoding.

    @param target Target object or cell
    @return Encoded target data
]]
function Pointers.encode_target(target)
    if target == nil then
        return { rtti = Pointers.RTTI.NONE, value = 0 }
    end

    -- Check if it's a cell coordinate (number)
    if type(target) == "number" then
        return { rtti = Pointers.RTTI.CELL, value = target }
    end

    -- It's an object reference
    local encoded = Pointers.encode(target)
    if encoded then
        return encoded
    end

    return { rtti = Pointers.RTTI.NONE, value = 0 }
end

--============================================================================
-- Decoding (Decode_Pointers equivalent)
--============================================================================

--[[
    Decode a serialized reference back to an object.

    @param encoded Table {rtti=type, index=heap_index} or nil
    @return Object reference or nil
]]
function Pointers.decode(encoded)
    if encoded == nil then
        return nil
    end

    local rtti = encoded.rtti
    local index = encoded.index

    if rtti == nil or rtti == Pointers.RTTI.NONE then
        return nil
    end

    -- Get from heap
    return Pointers.get_from_heap(rtti, index)
end

--[[
    Decode a TARGET value.

    @param encoded Encoded target data
    @return Target object, cell coordinate, or nil
]]
function Pointers.decode_target(encoded)
    if encoded == nil then
        return nil
    end

    if encoded.rtti == Pointers.RTTI.CELL then
        return encoded.value  -- Return cell coordinate directly
    end

    return Pointers.decode(encoded)
end

--============================================================================
-- Helper Functions
--============================================================================

--[[
    Get RTTI type from an object.
    Objects should have an 'rtti' field or implement get_rtti().

    @param obj Object to get RTTI from
    @return RTTI type constant
]]
function Pointers.get_rtti(obj)
    if obj == nil then
        return Pointers.RTTI.NONE
    end

    -- Check for explicit rtti field
    if obj.rtti then
        return obj.rtti
    end

    -- Check for RTTI method
    if obj.get_rtti then
        return obj:get_rtti()
    end

    -- Try to infer from class name
    local class_name = obj.class_name or obj._class_name
    if class_name then
        local rtti_map = {
            UnitClass = Pointers.RTTI.UNIT,
            BuildingClass = Pointers.RTTI.BUILDING,
            InfantryClass = Pointers.RTTI.INFANTRY,
            AircraftClass = Pointers.RTTI.AIRCRAFT,
            BulletClass = Pointers.RTTI.BULLET,
            AnimClass = Pointers.RTTI.ANIM,
            TriggerClass = Pointers.RTTI.TRIGGER,
            TeamClass = Pointers.RTTI.TEAM,
            TerrainClass = Pointers.RTTI.TERRAIN,
            OverlayClass = Pointers.RTTI.OVERLAY,
            SmudgeClass = Pointers.RTTI.SMUDGE,
            HouseClass = Pointers.RTTI.HOUSE,
            FactoryClass = Pointers.RTTI.FACTORY,
        }
        if rtti_map[class_name] then
            return rtti_map[class_name]
        end
    end

    return Pointers.RTTI.NONE
end

--[[
    Get heap index for an object.

    @param obj Object to find
    @param rtti RTTI type of the object
    @return Heap index or nil
]]
function Pointers.get_heap_index(obj, rtti)
    local heap = Pointers.heaps[rtti]
    if heap == nil then
        return nil
    end

    -- Try heap's get_index method
    if heap.get_index then
        return heap:get_index(obj)
    end

    -- Try to find in array
    if type(heap) == "table" then
        for i, item in ipairs(heap) do
            if item == obj then
                return i
            end
        end
    end

    return nil
end

--[[
    Get object from heap by index.

    @param rtti RTTI type
    @param index Heap index
    @return Object or nil
]]
function Pointers.get_from_heap(rtti, index)
    local heap = Pointers.heaps[rtti]
    if heap == nil then
        return nil
    end

    -- Try heap's get_by_index method
    if heap.get_by_index then
        return heap:get_by_index(index)
    end

    -- Try direct array access
    if type(heap) == "table" then
        return heap[index]
    end

    return nil
end

--============================================================================
-- Batch Operations
--============================================================================

--[[
    Code all pointers in a table recursively.
    Converts object references to encoded form for serialization.

    @param data Table to process
    @return New table with encoded pointers
]]
function Pointers.code_all(data)
    if type(data) ~= "table" then
        return data
    end

    local result = {}

    for key, value in pairs(data) do
        if type(value) == "table" then
            -- Check if it looks like an object reference
            local rtti = Pointers.get_rtti(value)
            if rtti ~= Pointers.RTTI.NONE then
                -- Encode the object reference
                result[key] = {
                    _encoded_pointer = true,
                    rtti = rtti,
                    index = Pointers.get_heap_index(value, rtti)
                }
            else
                -- Recurse into nested tables
                result[key] = Pointers.code_all(value)
            end
        else
            result[key] = value
        end
    end

    return result
end

--[[
    Decode all pointers in a table recursively.
    Converts encoded references back to object references after loading.

    @param data Table with encoded pointers
    @return New table with decoded object references
]]
function Pointers.decode_all(data)
    if type(data) ~= "table" then
        return data
    end

    local result = {}

    for key, value in pairs(data) do
        if type(value) == "table" then
            if value._encoded_pointer then
                -- Decode the pointer
                result[key] = Pointers.get_from_heap(value.rtti, value.index)
            else
                -- Recurse into nested tables
                result[key] = Pointers.decode_all(value)
            end
        else
            result[key] = value
        end
    end

    return result
end

--============================================================================
-- Debug
--============================================================================

function Pointers.Debug_Dump()
    print("Pointers:")

    -- Show registered heaps
    print("  Registered Heaps:")
    for rtti, heap in pairs(Pointers.heaps) do
        if heap then
            local count = 0
            if heap.count then
                count = heap:count()
            elseif type(heap) == "table" then
                count = #heap
            end
            print(string.format("    %s: %d objects",
                Pointers.RTTI_NAMES[rtti] or tostring(rtti), count))
        end
    end

    -- Show registered type registries
    print("  Registered Type Registries:")
    for rtti, registry in pairs(Pointers.type_registries) do
        if registry then
            local count = 0
            for _ in pairs(registry) do count = count + 1 end
            print(string.format("    %s: %d types",
                Pointers.RTTI_NAMES[rtti] or tostring(rtti), count))
        end
    end
end

return Pointers
