--[[
    CargoClass - Unit transport/passenger management mixin

    Port of CARGO.H/CPP from the original C&C source.

    This mixin provides cargo management for transports (APCs, helicopters).
    Objects being transported are stored as a linked list.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/CARGO.H
]]

local Class = require("src.objects.class")
local Target = require("src.core.target")

-- Create CargoClass as a mixin
local CargoClass = Class.mixin("CargoClass")

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize cargo state.
    Called automatically when mixed into a class.
]]
function CargoClass:init()
    --[[
        This is the number of objects attached to this cargo hold. For transporter
        objects, they might contain more than one object.
    ]]
    self.CargoQuantity = 0

    --[[
        This is the first object in the cargo hold. Additional objects are
        linked via the object's Member field.
    ]]
    self.CargoHold = nil
end

--============================================================================
-- Cargo Query
--============================================================================

--[[
    Get the number of objects in the cargo hold.
]]
function CargoClass:How_Many()
    return self.CargoQuantity
end

--[[
    Check if anything is attached/in the cargo hold.
]]
function CargoClass:Is_Something_Attached()
    return self.CargoHold ~= nil
end

--[[
    Get the first object in the cargo hold.
    Does not remove it.
]]
function CargoClass:Attached_Object()
    return self.CargoHold
end

--[[
    Get all cargo as a list.
]]
function CargoClass:Get_Cargo_List()
    local list = {}
    local current = self.CargoHold
    while current do
        table.insert(list, current)
        current = current.Member  -- FootClass objects have Member field
    end
    return list
end

--============================================================================
-- Cargo Management
--============================================================================

--[[
    Attach an object to the cargo hold.
    Objects are added to the front of the list.

    @param object - FootClass object to attach
]]
function CargoClass:Attach(object)
    if object == nil then return end

    -- Add to front of linked list
    object.Member = self.CargoHold
    self.CargoHold = object

    self.CargoQuantity = self.CargoQuantity + 1
end

--[[
    Detach and return the first object from the cargo hold.
    Returns nil if cargo hold is empty.
]]
function CargoClass:Detach_Object()
    local object = self.CargoHold

    if object then
        self.CargoHold = object.Member
        object.Member = nil
        self.CargoQuantity = self.CargoQuantity - 1
    end

    return object
end

--[[
    Remove a specific object from the cargo hold.

    @param object - Object to remove
    @return true if object was found and removed
]]
function CargoClass:Remove_Object(object)
    if object == nil or self.CargoHold == nil then
        return false
    end

    -- Special case: object is first in list
    if self.CargoHold == object then
        self.CargoHold = object.Member
        object.Member = nil
        self.CargoQuantity = self.CargoQuantity - 1
        return true
    end

    -- Search for object in list
    local current = self.CargoHold
    while current.Member do
        if current.Member == object then
            current.Member = object.Member
            object.Member = nil
            self.CargoQuantity = self.CargoQuantity - 1
            return true
        end
        current = current.Member
    end

    return false
end

--[[
    Clear all cargo.
]]
function CargoClass:Clear_Cargo()
    while self.CargoHold do
        local obj = self.CargoHold
        self.CargoHold = obj.Member
        obj.Member = nil
    end
    self.CargoQuantity = 0
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for cargo.
    Currently empty in the original.
]]
function CargoClass:AI_Cargo()
    -- Empty in original
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function CargoClass:Code_Pointers_Cargo()
    -- Encode cargo as TARGET values for serialization
    local cargo_targets = {}
    local current = self.CargoHold
    while current do
        if current.As_Target then
            table.insert(cargo_targets, current:As_Target())
        end
        current = current.Member
    end

    return {
        CargoQuantity = self.CargoQuantity,
        CargoTargets = cargo_targets,
    }
end

function CargoClass:Decode_Pointers_Cargo(data)
    if data then
        self.CargoQuantity = data.CargoQuantity or 0
        -- Store targets for later resolution
        self._decode_cargo_targets = data.CargoTargets or {}
    end
end

function CargoClass:Resolve_Pointers_Cargo(heap_lookup)
    if self._decode_cargo_targets then
        -- Rebuild cargo list from targets
        self.CargoHold = nil
        self.CargoQuantity = 0

        -- Process in reverse order to maintain original order
        for i = #self._decode_cargo_targets, 1, -1 do
            local target = self._decode_cargo_targets[i]
            if Target.Is_Valid(target) then
                local rtti = Target.Get_RTTI(target)
                local id = Target.Get_ID(target)
                local obj = heap_lookup(rtti, id)
                if obj then
                    self:Attach(obj)
                end
            end
        end

        self._decode_cargo_targets = nil
    end
end

--============================================================================
-- Debug Support
--============================================================================

function CargoClass:Debug_Dump_Cargo()
    print(string.format("CargoClass: Quantity=%d HasCargo=%s",
        self.CargoQuantity,
        tostring(self.CargoHold ~= nil)))

    if self.CargoHold then
        local current = self.CargoHold
        local index = 1
        while current do
            local name = "?"
            if current.get_class_name then
                name = current:get_class_name()
            end
            print(string.format("  [%d] %s", index, name))
            current = current.Member
            index = index + 1
        end
    end
end

return CargoClass
