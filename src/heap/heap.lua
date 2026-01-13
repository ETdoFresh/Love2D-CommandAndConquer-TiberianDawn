--[[
    HeapClass - Object pool management for game objects

    Port of HEAP.H/CPP from the original C&C source.

    The HeapClass manages fixed-size pools of game objects to:
    - Avoid garbage collection during gameplay
    - Enable deterministic object allocation (for multiplayer sync)
    - Support save/load via heap indices
    - Match original game's memory management patterns

    Each object type (Infantry, Units, Buildings, etc.) has its own heap
    with a fixed maximum capacity matching the original game limits.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/HEAP.H
]]

local Target = require("src.core.target")

local HeapClass = {}
HeapClass.__index = HeapClass

--============================================================================
-- Pool Limits (from original DEFINES.H)
--============================================================================

HeapClass.LIMITS = {
    INFANTRY = 500,
    UNITS = 500,
    BUILDINGS = 500,
    AIRCRAFT = 100,
    BULLETS = 50,
    ANIMS = 100,
    TEAMS = 50,
    TRIGGERS = 100,
    TERRAIN = 500,
    OVERLAY = 1024,
    SMUDGE = 100,
}

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new heap for a specific object class.

    @param object_class - The Lua class to instantiate objects from
    @param max_size - Maximum number of objects in the pool
    @param rtti - RTTI type for TARGET encoding
]]
function HeapClass.new(object_class, max_size, rtti)
    local self = setmetatable({}, HeapClass)

    self.object_class = object_class
    self.max_size = max_size or 100
    self.rtti = rtti or Target.RTTI.NONE

    -- Array of all allocated object slots
    self.objects = {}

    -- Free list (indices of available slots)
    self.free_list = {}

    -- Active count
    self.active_count = 0

    -- Pre-allocate all slots
    for i = 1, self.max_size do
        local obj = object_class:new()
        obj:set_heap_index(i - 1)  -- 0-based index
        obj.IsActive = false
        self.objects[i] = obj
        table.insert(self.free_list, i)
    end

    return self
end

--============================================================================
-- Allocation / Deallocation
--============================================================================

--[[
    Allocate a new object from the heap.
    Returns the object or nil if heap is full.
]]
function HeapClass:Allocate()
    if #self.free_list == 0 then
        return nil  -- Heap is full
    end

    -- Get next free slot
    local slot = table.remove(self.free_list)
    local obj = self.objects[slot]

    -- Reset and activate
    obj.IsActive = true
    obj.IsRecentlyCreated = true
    self.active_count = self.active_count + 1

    return obj
end

--[[
    Free an object back to the heap.
    @param obj - Object to free (or heap index)
]]
function HeapClass:Free(obj)
    local slot

    if type(obj) == "number" then
        slot = obj + 1  -- Convert 0-based index to 1-based
    else
        slot = obj:get_heap_index() + 1
    end

    if slot < 1 or slot > self.max_size then
        return false
    end

    local object = self.objects[slot]
    if not object.IsActive then
        return false  -- Already free
    end

    -- Deactivate and reset
    object.IsActive = false
    object.IsInLimbo = true
    object.IsDown = false
    object.IsSelected = false
    object.Next = nil
    object.Radio = nil

    -- Add back to free list
    table.insert(self.free_list, slot)
    self.active_count = self.active_count - 1

    return true
end

--============================================================================
-- Object Access
--============================================================================

--[[
    Get object by heap index (0-based).
    Returns nil if index invalid or object not active.
]]
function HeapClass:Get(index)
    local slot = index + 1  -- Convert to 1-based

    if slot < 1 or slot > self.max_size then
        return nil
    end

    local obj = self.objects[slot]
    if not obj.IsActive then
        return nil
    end

    return obj
end

--[[
    Get object by heap index, even if not active.
    Used for save/load pointer resolution.
]]
function HeapClass:Get_Raw(index)
    local slot = index + 1

    if slot < 1 or slot > self.max_size then
        return nil
    end

    return self.objects[slot]
end

--[[
    Get index of an object (-1 if not in heap)
]]
function HeapClass:Index_Of(obj)
    return obj:get_heap_index()
end

--============================================================================
-- Iteration
--============================================================================

--[[
    Iterate over all active objects.
    Usage:
        for obj in heap:Active_Objects() do
            obj:AI()
        end
]]
function HeapClass:Active_Objects()
    local i = 0
    local n = self.max_size

    return function()
        while i < n do
            i = i + 1
            local obj = self.objects[i]
            if obj and obj.IsActive then
                return obj
            end
        end
        return nil
    end
end

--[[
    Iterate over all objects (active and inactive).
    Usage:
        for obj in heap:All_Objects() do
            -- ...
        end
]]
function HeapClass:All_Objects()
    local i = 0
    local n = self.max_size

    return function()
        while i < n do
            i = i + 1
            if self.objects[i] then
                return self.objects[i]
            end
        end
        return nil
    end
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Get count of active objects
]]
function HeapClass:Count()
    return self.active_count
end

--[[
    Get maximum capacity
]]
function HeapClass:Max_Count()
    return self.max_size
end

--[[
    Get number of free slots
]]
function HeapClass:Free_Count()
    return #self.free_list
end

--[[
    Check if heap is full
]]
function HeapClass:Is_Full()
    return #self.free_list == 0
end

--[[
    Check if heap is empty
]]
function HeapClass:Is_Empty()
    return self.active_count == 0
end

--[[
    Get RTTI type for this heap
]]
function HeapClass:Get_RTTI()
    return self.rtti
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    Process AI for all active objects in this heap.
    This should be called each game tick.
]]
function HeapClass:Process_AI()
    for obj in self:Active_Objects() do
        if obj.AI then
            obj:AI()
        end
    end
end

--============================================================================
-- Save/Load Support
--============================================================================

--[[
    Code all objects for saving.
    Returns array of encoded object data.
]]
function HeapClass:Code_All()
    local data = {}

    for i = 1, self.max_size do
        local obj = self.objects[i]
        if obj.IsActive and obj.Code_Pointers then
            data[i] = {
                index = i - 1,
                active = true,
                data = obj:Code_Pointers()
            }
        else
            data[i] = {
                index = i - 1,
                active = false
            }
        end
    end

    return data
end

--[[
    Decode all objects from saved data.
    @param data - Array from Code_All()
]]
function HeapClass:Decode_All(data)
    -- First, reset all objects
    for i = 1, self.max_size do
        self.objects[i].IsActive = false
    end
    self.free_list = {}
    self.active_count = 0

    -- Then load saved objects
    for _, entry in ipairs(data) do
        local slot = entry.index + 1

        if entry.active and entry.data then
            local obj = self.objects[slot]
            obj.IsActive = true
            if obj.Decode_Pointers then
                obj:Decode_Pointers(entry.data)
            end
            self.active_count = self.active_count + 1
        else
            table.insert(self.free_list, slot)
        end
    end

    -- Add remaining slots to free list
    for i = 1, self.max_size do
        if not self.objects[i].IsActive then
            local found = false
            for _, slot in ipairs(self.free_list) do
                if slot == i then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(self.free_list, i)
            end
        end
    end
end

--[[
    Resolve pointers after all heaps are loaded.
    @param heap_lookup - Function(rtti, index) that returns the object
]]
function HeapClass:Resolve_Pointers(heap_lookup)
    for obj in self:Active_Objects() do
        if obj.Resolve_Pointers then
            obj:Resolve_Pointers(heap_lookup)
        end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function HeapClass:Debug_Dump()
    print(string.format("HeapClass: RTTI=%s Active=%d/%d Free=%d",
        Target.RTTI_NAME[self.rtti] or "?",
        self.active_count,
        self.max_size,
        #self.free_list))

    -- Dump first few active objects
    local count = 0
    for obj in self:Active_Objects() do
        if obj.Debug_Dump then
            obj:Debug_Dump()
        end
        count = count + 1
        if count >= 5 then
            print("  ... and " .. (self.active_count - 5) .. " more")
            break
        end
    end
end

return HeapClass
