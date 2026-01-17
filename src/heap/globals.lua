--[[
    Global Heap Management

    This module provides global access to all object heaps and
    a centralized lookup function for TARGET resolution.

    Reference: The original C&C uses global arrays (Infantry[], Units[], etc.)
    This module provides similar functionality with Lua tables.
]]

local HeapClass = require("src.heap.heap")
local Target = require("src.core.target")

local Globals = {}

-- Heap instances (created lazily when object classes are loaded)
Globals.heaps = {}

--============================================================================
-- Heap Registration
--============================================================================

--[[
    Register a heap for a specific object type.
    @param rtti - RTTI type
    @param object_class - Lua class for objects
    @param max_size - Maximum objects (from HeapClass.LIMITS)
]]
function Globals.Register_Heap(rtti, object_class, max_size)
    local heap = HeapClass.new(object_class, max_size, rtti)
    Globals.heaps[rtti] = heap
    return heap
end

--[[
    Get heap by RTTI type
]]
function Globals.Get_Heap(rtti)
    return Globals.heaps[rtti]
end

--============================================================================
-- Object Lookup
--============================================================================

--[[
    Look up an object by RTTI and heap index.
    This is the primary function for TARGET resolution.

    @param rtti - RTTI type
    @param index - Heap index
    Returns object or nil
]]
function Globals.Heap_Lookup(rtti, index)
    local heap = Globals.heaps[rtti]
    if heap then
        return heap:Get(index)
    end
    return nil
end

--[[
    Look up an object from a TARGET value.

    @param target - TARGET encoded value
    Returns object or nil
]]
function Globals.Target_To_Object(target)
    if not Target.Is_Valid(target) then
        return nil
    end

    local rtti = Target.Get_RTTI(target)
    local id = Target.Get_ID(target)

    return Globals.Heap_Lookup(rtti, id)
end

--============================================================================
-- Global AI Processing
--============================================================================

--[[
    Process AI for all active objects in all heaps.
    Call this each game tick.
]]
function Globals.Process_All_AI()
    -- Process in specific order to match original game
    local order = {
        Target.RTTI.BUILDING,
        Target.RTTI.INFANTRY,
        Target.RTTI.UNIT,
        Target.RTTI.AIRCRAFT,
        Target.RTTI.BULLET,
        Target.RTTI.ANIM,
    }

    for _, rtti in ipairs(order) do
        local heap = Globals.heaps[rtti]
        if heap then
            heap:Process_AI()
        end
    end
end

--============================================================================
-- Object Creation Helpers
--============================================================================

--[[
    Create a new object of the specified type.
    @param rtti - RTTI type
    Returns new object or nil if heap is full
]]
function Globals.Create_Object(rtti)
    local heap = Globals.heaps[rtti]
    if heap then
        return heap:Allocate()
    end
    return nil
end

--[[
    Destroy an object (return to heap).
    @param obj - Object to destroy
]]
function Globals.Destroy_Object(obj)
    if not obj then return false end

    local rtti = obj:get_rtti()
    local heap = Globals.heaps[rtti]

    if heap then
        return heap:Free(obj)
    end
    return false
end

--============================================================================
-- Statistics
--============================================================================

--[[
    Get count of all active objects across all heaps.
]]
function Globals.Total_Active_Count()
    local total = 0
    for _, heap in pairs(Globals.heaps) do
        total = total + heap:Count()
    end
    return total
end

--[[
    Get statistics for all heaps.
    Returns table of {rtti = {active, max, free}}
]]
function Globals.Get_Statistics()
    local stats = {}
    for rtti, heap in pairs(Globals.heaps) do
        stats[rtti] = {
            name = Target.RTTI_NAME[rtti] or "?",
            active = heap:Count(),
            max = heap:Max_Count(),
            free = heap:Free_Count()
        }
    end
    return stats
end

--============================================================================
-- Save/Load Support
--============================================================================

--[[
    Save all heaps to a table.
]]
function Globals.Code_All_Heaps()
    local data = {}
    for rtti, heap in pairs(Globals.heaps) do
        data[rtti] = heap:Code_All()
    end
    return data
end

--[[
    Load all heaps from saved data.
]]
function Globals.Decode_All_Heaps(data)
    for rtti, heap_data in pairs(data) do
        local heap = Globals.heaps[rtti]
        if heap then
            heap:Decode_All(heap_data)
        end
    end

    -- Resolve pointers after all objects loaded
    for _, heap in pairs(Globals.heaps) do
        heap:Resolve_Pointers(Globals.Heap_Lookup)
    end
end

--============================================================================
-- Heap Initialization
--============================================================================

-- Track initialization state
Globals._initialized = false

--[[
    Initialize all game object heaps.
    This must be called once during game initialization, before any
    objects are created.

    The heaps are created with the pool limits from the original game
    (see HeapClass.LIMITS).
]]
function Globals.Init_All_Heaps()
    if Globals._initialized then
        return  -- Already initialized
    end

    -- Lazy require to avoid circular dependencies during module loading
    local InfantryClass = require("src.objects.infantry")
    local UnitClass = require("src.objects.unit")
    local BuildingClass = require("src.objects.building")
    local AircraftClass = require("src.objects.aircraft")
    local BulletClass = require("src.objects.bullet")
    local AnimClass = require("src.objects.anim")

    -- Register heaps in the order used by Process_All_AI()
    -- This matches the original C&C processing order
    Globals.Register_Heap(Target.RTTI.BUILDING, BuildingClass, HeapClass.LIMITS.BUILDINGS)
    Globals.Register_Heap(Target.RTTI.INFANTRY, InfantryClass, HeapClass.LIMITS.INFANTRY)
    Globals.Register_Heap(Target.RTTI.UNIT, UnitClass, HeapClass.LIMITS.UNITS)
    Globals.Register_Heap(Target.RTTI.AIRCRAFT, AircraftClass, HeapClass.LIMITS.AIRCRAFT)
    Globals.Register_Heap(Target.RTTI.BULLET, BulletClass, HeapClass.LIMITS.BULLETS)
    Globals.Register_Heap(Target.RTTI.ANIM, AnimClass, HeapClass.LIMITS.ANIMS)

    Globals._initialized = true

    print(string.format("Globals.Init_All_Heaps(): Initialized %d heaps",
        Globals.Get_Heap_Count()))
end

--[[
    Check if heaps have been initialized.
]]
function Globals.Is_Initialized()
    return Globals._initialized
end

--[[
    Get the count of registered heaps.
]]
function Globals.Get_Heap_Count()
    local count = 0
    for _ in pairs(Globals.heaps) do
        count = count + 1
    end
    return count
end

--[[
    Reset all heaps (for testing or new game).
    Clears all objects and returns them to the free list.
]]
function Globals.Reset_All_Heaps()
    for rtti, heap in pairs(Globals.heaps) do
        -- Free all active objects
        for obj in heap:Active_Objects() do
            heap:Free(obj)
        end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function Globals.Debug_Dump()
    print("=== Global Heaps ===")
    print(string.format("Initialized: %s", tostring(Globals._initialized)))
    print(string.format("Total Active: %d", Globals.Total_Active_Count()))

    for rtti, heap in pairs(Globals.heaps) do
        heap:Debug_Dump()
    end
end

return Globals
