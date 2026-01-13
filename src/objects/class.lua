--[[
    Lua OOP Class System with Multiple Inheritance (Mixin) Support

    This module provides a class system that mirrors the C++ class hierarchy
    from the original Command & Conquer source code.

    Features:
    - Single inheritance via extend()
    - Multiple inheritance emulation via mixins
    - Virtual method override support
    - Proper method resolution order

    Reference: Original C++ uses virtual functions for polymorphism.
    This system emulates that with Lua metatables.
]]

local Class = {}

--[[
    Create a new class definition

    Usage:
        local MyClass = Class.new("MyClass")
        -- or with parent:
        local ChildClass = Class.new("ChildClass", ParentClass)
]]
function Class.new(name, parent)
    local cls = {}
    cls.__name = name or "UnnamedClass"
    cls.__index = cls
    cls.__parent = parent
    cls.__mixins = {}

    -- Set up inheritance chain
    if parent then
        setmetatable(cls, {
            __index = function(t, k)
                -- First check parent class
                local v = parent[k]
                if v ~= nil then return v end

                -- Then check mixins (in order they were added)
                for _, mixin in ipairs(cls.__mixins) do
                    v = mixin[k]
                    if v ~= nil then return v end
                end

                return nil
            end,
            __call = function(_, ...)
                return cls:new(...)
            end
        })
    else
        setmetatable(cls, {
            __index = function(t, k)
                -- Check mixins
                for _, mixin in ipairs(cls.__mixins) do
                    local v = mixin[k]
                    if v ~= nil then return v end
                end
                return nil
            end,
            __call = function(_, ...)
                return cls:new(...)
            end
        })
    end

    -- Default constructor
    function cls:new(...)
        local instance = setmetatable({}, self)

        -- Initialize all mixins first
        for _, mixin in ipairs(self.__mixins) do
            if mixin.init then
                mixin.init(instance, ...)
            end
        end

        -- Then call class constructor
        -- Use instance:init() so 'self' inside init refers to the instance
        if self.init then
            instance:init(...)
        end

        return instance
    end

    -- Check if object is instance of class (or parent/mixin)
    function cls:is_instance(obj)
        if type(obj) ~= "table" then return false end

        local mt = getmetatable(obj)
        while mt do
            if mt == self then return true end
            mt = mt.__parent
        end
        return false
    end

    -- Get class name
    function cls:get_class_name()
        return self.__name
    end

    -- Get parent class
    function cls:get_parent()
        return self.__parent
    end

    return cls
end

--[[
    Extend an existing class to create a subclass

    Usage:
        local ChildClass = Class.extend(ParentClass, "ChildClass")
]]
function Class.extend(parent, name)
    return Class.new(name, parent)
end

--[[
    Include a mixin into a class (multiple inheritance emulation)

    Mixins are included in order, with later mixins taking precedence
    for method resolution after the main class and its parent chain.

    Usage:
        Class.include(TechnoClass, FlasherMixin)
        Class.include(TechnoClass, StageMixin)
]]
function Class.include(cls, mixin)
    table.insert(cls.__mixins, mixin)

    -- Copy mixin fields to class for direct access
    -- (methods are looked up via __index)
    for k, v in pairs(mixin) do
        if type(v) ~= "function" and k ~= "__name" and k ~= "__index" then
            if cls[k] == nil then
                cls[k] = v
            end
        end
    end

    return cls
end

--[[
    Create a mixin (for multiple inheritance emulation)

    Mixins are like classes but are meant to be composed into other classes
    rather than instantiated directly.

    Usage:
        local FlasherMixin = Class.mixin("Flasher")
        function FlasherMixin:flash(duration)
            self.flash_time = duration
        end
]]
function Class.mixin(name)
    local mixin = {
        __name = name or "UnnamedMixin"
    }
    return mixin
end

--[[
    Check if an object is an instance of a class (including parents)
]]
function Class.is_a(obj, cls)
    if type(obj) ~= "table" or type(cls) ~= "table" then
        return false
    end

    local mt = getmetatable(obj)
    while mt do
        if mt == cls then return true end

        -- Check mixins
        if mt.__mixins then
            for _, mixin in ipairs(mt.__mixins) do
                if mixin == cls then return true end
            end
        end

        mt = mt.__parent
    end
    return false
end

--[[
    Call parent method (for method overriding)

    Usage (inside a method):
        function ChildClass:some_method()
            Class.super(self, "some_method")  -- Call parent's some_method
            -- ... additional logic
        end
]]
function Class.super(instance, method_name, ...)
    local cls = getmetatable(instance)
    local parent = cls.__parent

    -- Walk up the parent chain to find the method
    while parent do
        -- Use rawget to check only the class's direct table, not its metatable chain
        local method = rawget(parent, method_name)
        if method then
            return method(instance, ...)
        end
        parent = parent.__parent
    end
end

--[[
    Get the RTTI (Run-Time Type Info) equivalent
    Used for TARGET encoding and type checking
]]
function Class.get_rtti(obj)
    if type(obj) ~= "table" then return nil end
    local mt = getmetatable(obj)
    return mt and mt.__name or nil
end

return Class
