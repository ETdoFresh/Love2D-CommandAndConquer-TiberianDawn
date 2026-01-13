--[[
    LayerClass - Render layer management for depth-sorted object display

    Port of LAYER.H/CPP from the original C&C source.

    Objects are organized into layers for proper rendering order:
    - GROUND: Objects touching the ground (units, buildings)
    - AIR: Flying above ground (explosions, flames)
    - TOP: Topmost layer (aircraft, bullets)

    Within each layer, objects are sorted by Y-coordinate for proper
    visual overlap (objects lower on screen render on top).

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/LAYER.H
]]

local LayerClass = {}
LayerClass.__index = LayerClass

--============================================================================
-- Layer Type Constants
--============================================================================

LayerClass.LAYER_TYPE = {
    NONE = -1,
    GROUND = 0,    -- Touching the ground (units, buildings)
    AIR = 1,       -- Flying above ground (explosions, flames)
    TOP = 2,       -- Topmost layer (aircraft, bullets)
}

LayerClass.LAYER_COUNT = 3
LayerClass.LAYER_FIRST = 0

-- Layer names for debugging
LayerClass.LAYER_NAMES = {
    [-1] = "NONE",
    [0] = "GROUND",
    [1] = "AIR",
    [2] = "TOP",
}

--============================================================================
-- Constructor
--============================================================================

function LayerClass.new()
    local self = setmetatable({}, LayerClass)

    -- Dynamic array of objects in this layer
    self.objects = {}

    -- Count of active objects
    self.count = 0

    return self
end

--============================================================================
-- Initialization
--============================================================================

function LayerClass:Init()
    self:Clear()
end

function LayerClass:Clear()
    self.objects = {}
    self.count = 0
end

function LayerClass:One_Time()
    -- One-time initialization (called once at startup)
end

--============================================================================
-- Object Management
--============================================================================

--[[
    Submit an object to this layer.

    @param object - ObjectClass to add
    @param sort - If true, insert in sorted position (default false)
    @return true if successfully added
]]
function LayerClass:Submit(object, sort)
    if object == nil then
        return false
    end

    if sort then
        return self:Sorted_Add(object)
    else
        return self:Add(object)
    end
end

--[[
    Add an object to the end of the layer (unsorted).

    @param object - ObjectClass to add
    @return true if successfully added
]]
function LayerClass:Add(object)
    if object == nil then
        return false
    end

    self.count = self.count + 1
    self.objects[self.count] = object

    return true
end

--[[
    Add an object in sorted order (by Y coordinate).
    Objects with higher Y values (lower on screen) come after
    objects with lower Y values.

    @param object - ObjectClass to add
    @return true if successfully added
]]
function LayerClass:Sorted_Add(object)
    if object == nil then
        return false
    end

    -- Find the correct insertion position
    local insert_index = self.count + 1

    for i = 1, self.count do
        local existing = self.objects[i]
        if existing and self:Compare(existing, object) > 0 then
            insert_index = i
            break
        end
    end

    -- Shift elements to make room
    for i = self.count, insert_index, -1 do
        self.objects[i + 1] = self.objects[i]
    end

    -- Insert the new object
    self.objects[insert_index] = object
    self.count = self.count + 1

    return true
end

--[[
    Remove an object from this layer.

    @param object - ObjectClass to remove
    @return true if object was found and removed
]]
function LayerClass:Remove(object)
    if object == nil then
        return false
    end

    for i = 1, self.count do
        if self.objects[i] == object then
            -- Shift elements down
            for j = i, self.count - 1 do
                self.objects[j] = self.objects[j + 1]
            end
            self.objects[self.count] = nil
            self.count = self.count - 1
            return true
        end
    end

    return false
end

--============================================================================
-- Sorting
--============================================================================

--[[
    Compare two objects for sorting.
    Objects are sorted by Y coordinate (Sort_Y).

    @param a - First object
    @param b - Second object
    @return negative if a < b, 0 if equal, positive if a > b
]]
function LayerClass:Compare(a, b)
    local sort_y_a = self:Get_Sort_Y(a)
    local sort_y_b = self:Get_Sort_Y(b)

    if sort_y_a < sort_y_b then
        return -1
    elseif sort_y_a > sort_y_b then
        return 1
    else
        return 0
    end
end

--[[
    Get the Y coordinate used for sorting.
    This extracts the Y lepton component from the object's coordinate.

    @param object - ObjectClass to get sort Y from
    @return Y value for sorting
]]
function LayerClass:Get_Sort_Y(object)
    if object == nil then
        return 0
    end

    -- If object has a Sort_Y method, use it
    if object.Sort_Y then
        return object:Sort_Y()
    end

    -- Otherwise extract Y from Coord
    local coord = object.Coord or 0
    if coord == 0 then
        return 0
    end

    -- Y is in the high 16 bits of the coordinate
    -- Each cell is 256 leptons, Y cell is in high byte of high word
    local Coord = require("src.core.coord")
    return Coord.Coord_Y(coord)
end

--[[
    Perform an incremental sort pass on the layer.
    This is a single-pass bubble sort step, designed to be called
    frequently to maintain approximate sort order without the cost
    of a full sort each frame.

    Reference: LAYER.CPP Sort()
]]
function LayerClass:Sort()
    for i = 1, self.count - 1 do
        local a = self.objects[i]
        local b = self.objects[i + 1]

        if a and b and self:Compare(a, b) > 0 then
            -- Swap
            self.objects[i] = b
            self.objects[i + 1] = a
        end
    end
end

--[[
    Perform a full sort of all objects in the layer.
    Uses insertion sort for stability.
]]
function LayerClass:Full_Sort()
    -- Simple insertion sort for stability
    for i = 2, self.count do
        local current = self.objects[i]
        local j = i - 1

        while j >= 1 and self:Compare(self.objects[j], current) > 0 do
            self.objects[j + 1] = self.objects[j]
            j = j - 1
        end

        self.objects[j + 1] = current
    end
end

--============================================================================
-- Queries
--============================================================================

--[[
    Get the number of objects in this layer.
]]
function LayerClass:Count()
    return self.count
end

--[[
    Check if this layer is empty.
]]
function LayerClass:Is_Empty()
    return self.count == 0
end

--[[
    Get an object by index (1-based).
]]
function LayerClass:Get(index)
    if index < 1 or index > self.count then
        return nil
    end
    return self.objects[index]
end

--[[
    Iterate over all objects in this layer.
    Returns iterator function compatible with for loops.
]]
function LayerClass:Iterate()
    local i = 0
    return function()
        i = i + 1
        if i <= self.count then
            return self.objects[i]
        end
        return nil
    end
end

--[[
    Get all objects as a table (for iteration).
]]
function LayerClass:Get_All()
    local result = {}
    for i = 1, self.count do
        result[i] = self.objects[i]
    end
    return result
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

--[[
    Encode object pointers for saving.
    Converts object references to heap indices.
]]
function LayerClass:Code_Pointers()
    local Target = require("src.core.target")
    local data = {
        count = self.count,
        objects = {}
    }

    for i = 1, self.count do
        local obj = self.objects[i]
        if obj and obj.As_Target then
            data.objects[i] = obj:As_Target()
        else
            data.objects[i] = Target.TARGET_NONE
        end
    end

    return data
end

--[[
    Decode object pointers after loading.
    Converts heap indices back to object references.

    @param data - Saved data from Code_Pointers
    @param heap_lookup - Function to look up objects by RTTI and ID
]]
function LayerClass:Decode_Pointers(data, heap_lookup)
    local Target = require("src.core.target")

    self:Clear()

    if not data then return end

    for i = 1, (data.count or 0) do
        local target = data.objects[i]
        if target and Target.Is_Valid(target) then
            local rtti = Target.Get_RTTI(target)
            local id = Target.Get_ID(target)
            local obj = heap_lookup(rtti, id)
            if obj then
                self:Add(obj)
            end
        end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function LayerClass:Debug_Dump(layer_type)
    local name = LayerClass.LAYER_NAMES[layer_type] or "UNKNOWN"
    print(string.format("LayerClass [%s]: %d objects", name, self.count))

    for i = 1, math.min(self.count, 10) do
        local obj = self.objects[i]
        if obj then
            local coord = obj.Coord or 0
            local sort_y = self:Get_Sort_Y(obj)
            print(string.format("  [%d] Coord=%08X Sort_Y=%d", i, coord, sort_y))
        end
    end

    if self.count > 10 then
        print(string.format("  ... and %d more", self.count - 10))
    end
end

--============================================================================
-- Layer Manager (Static)
-- Manages all three layer instances
--============================================================================

LayerClass.Layers = {}

--[[
    Initialize all layers (called once at game start).
]]
function LayerClass.Init_All()
    for i = 0, LayerClass.LAYER_COUNT - 1 do
        LayerClass.Layers[i] = LayerClass.new()
    end
end

--[[
    Get a specific layer by type.

    @param layer_type - LAYER_TYPE enum value
    @return LayerClass instance or nil
]]
function LayerClass.Get_Layer(layer_type)
    if layer_type < 0 or layer_type >= LayerClass.LAYER_COUNT then
        return nil
    end
    return LayerClass.Layers[layer_type]
end

--[[
    Submit an object to the appropriate layer.

    @param object - ObjectClass to add
    @param layer_type - LAYER_TYPE enum value
    @param sort - If true, insert sorted (default false)
    @return true if successfully added
]]
function LayerClass.Submit_To(object, layer_type, sort)
    local layer = LayerClass.Get_Layer(layer_type)
    if layer then
        return layer:Submit(object, sort)
    end
    return false
end

--[[
    Remove an object from a layer.

    @param object - ObjectClass to remove
    @param layer_type - LAYER_TYPE enum value
    @return true if object was removed
]]
function LayerClass.Remove_From(object, layer_type)
    local layer = LayerClass.Get_Layer(layer_type)
    if layer then
        return layer:Remove(object)
    end
    return false
end

--[[
    Sort all layers (call each frame for incremental sort).
]]
function LayerClass.Sort_All()
    for i = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Layers[i]
        if layer then
            layer:Sort()
        end
    end
end

--[[
    Clear all layers.
]]
function LayerClass.Clear_All()
    for i = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Layers[i]
        if layer then
            layer:Clear()
        end
    end
end

return LayerClass
