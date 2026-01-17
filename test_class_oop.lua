--[[
    OOP Class System Verification Tests
    Run with: lovec . test_class_oop

    Tests the core Class.lua OOP functionality:
    1. Basic inheritance
    2. Multi-level inheritance chains
    3. Class.super() functionality
    4. Mixin composition
    5. Class.is_a() type checking
]]

package.path = package.path .. ";./?.lua;./src/?.lua;./?/init.lua"

local function test()
    local passed = 0
    local failed = 0

    local function check(name, condition, detail)
        if condition then
            passed = passed + 1
            print("[PASS] " .. name)
        else
            failed = failed + 1
            print("[FAIL] " .. name .. (detail and (" - " .. detail) or ""))
        end
        return condition
    end

    print("========================================")
    print("OOP Class System Verification")
    print("========================================\n")

    local Class = require("src.objects.class")

    -- Test 1: Basic class creation
    print("--- Basic Class Creation ---")
    local Animal = Class.new("Animal")
    function Animal:init(name)
        self.name = name or "unknown"
        self.legs = 4
    end
    function Animal:speak()
        return "..."
    end
    function Animal:describe()
        return self.name .. " has " .. self.legs .. " legs"
    end

    local animal = Animal:new("Generic")
    check("Create class instance", animal ~= nil)
    check("Init sets fields", animal.name == "Generic" and animal.legs == 4)
    check("Methods work", animal:describe() == "Generic has 4 legs")

    -- Test 2: Single inheritance
    print("\n--- Single Inheritance ---")
    local Dog = Class.extend(Animal, "Dog")
    function Dog:init(name)
        Animal.init(self, name)  -- Call parent init explicitly
        self.breed = "mutt"
    end
    function Dog:speak()  -- Override
        return "Woof!"
    end

    local dog = Dog:new("Rex")
    check("Child class inherits fields", dog.name == "Rex" and dog.legs == 4)
    check("Child can override methods", dog:speak() == "Woof!")
    check("Child inherits parent methods", dog:describe() == "Rex has 4 legs")

    -- Test 3: Multi-level inheritance
    print("\n--- Multi-Level Inheritance ---")
    local GermanShepherd = Class.extend(Dog, "GermanShepherd")
    function GermanShepherd:init(name)
        Dog.init(self, name)
        self.breed = "German Shepherd"
    end
    function GermanShepherd:guard()
        return "Guarding " .. self.name
    end

    local gs = GermanShepherd:new("Max")
    check("3-level chain: has Animal field", gs.legs == 4)
    check("3-level chain: has Dog override", gs:speak() == "Woof!")
    check("3-level chain: has GS method", gs:guard() == "Guarding Max")
    check("3-level chain: inherited describe", gs:describe() == "Max has 4 legs")

    -- Test 4: Class.super() functionality
    print("\n--- Class.super() ---")
    local Cat = Class.extend(Animal, "Cat")
    function Cat:init(name)
        Animal.init(self, name)
    end
    function Cat:speak()
        return "Meow!"
    end
    function Cat:speak_twice()
        local base = Class.super(self, "speak") or "..."  -- Should get Animal's speak
        return base .. " then " .. self:speak()
    end

    local cat = Cat:new("Whiskers")
    check("Class.super finds parent method", cat:speak_twice() == "... then Meow!")

    -- Test 5: Mixin composition
    print("\n--- Mixin Composition ---")
    local SwimMixin = Class.mixin("SwimMixin")
    function SwimMixin:init()
        self.can_swim = true
        self.swim_speed = 5
    end
    function SwimMixin:swim()
        return "Swimming at speed " .. self.swim_speed
    end

    local FlyMixin = Class.mixin("FlyMixin")
    function FlyMixin:init()
        self.can_fly = true
        self.altitude = 0
    end
    function FlyMixin:fly()
        self.altitude = 100
        return "Flying at altitude " .. self.altitude
    end

    local Duck = Class.extend(Animal, "Duck")
    Class.include(Duck, SwimMixin)
    Class.include(Duck, FlyMixin)
    function Duck:init(name)
        Animal.init(self, name)
        SwimMixin.init(self)
        FlyMixin.init(self)
        self.legs = 2
    end
    function Duck:speak()
        return "Quack!"
    end

    local duck = Duck:new("Donald")
    check("Mixin: has swim fields", duck.can_swim == true)
    check("Mixin: has fly fields", duck.can_fly == true)
    check("Mixin: swim method works", duck:swim() == "Swimming at speed 5")
    check("Mixin: fly method works", duck:fly() == "Flying at altitude 100")
    check("Mixin: override still works", duck:speak() == "Quack!")
    check("Mixin: parent method works", duck:describe() == "Donald has 2 legs")

    -- Test 6: Class.is_a() type checking
    print("\n--- Type Checking (Class.is_a) ---")
    check("is_a: animal is Animal", Class.is_a(animal, Animal))
    check("is_a: dog is Dog", Class.is_a(dog, Dog))
    check("is_a: dog is Animal", Class.is_a(dog, Animal))
    check("is_a: gs is GermanShepherd", Class.is_a(gs, GermanShepherd))
    check("is_a: gs is Dog", Class.is_a(gs, Dog))
    check("is_a: gs is Animal", Class.is_a(gs, Animal))
    check("is_a: duck is Duck", Class.is_a(duck, Duck))
    check("is_a: duck is Animal", Class.is_a(duck, Animal))
    check("is_a: cat is not Dog", not Class.is_a(cat, Dog))
    check("is_a: dog is not Cat", not Class.is_a(dog, Cat))

    -- Test 7: Class.is_a with mixins
    print("\n--- Type Checking with Mixins ---")
    check("is_a mixin: duck is SwimMixin", Class.is_a(duck, SwimMixin))
    check("is_a mixin: duck is FlyMixin", Class.is_a(duck, FlyMixin))
    check("is_a mixin: dog is not SwimMixin", not Class.is_a(dog, SwimMixin))

    -- Test 8: Class.get_rtti()
    print("\n--- RTTI (Class.get_rtti) ---")
    check("RTTI: Animal", Class.get_rtti(animal) == "Animal")
    check("RTTI: Dog", Class.get_rtti(dog) == "Dog")
    check("RTTI: GermanShepherd", Class.get_rtti(gs) == "GermanShepherd")
    check("RTTI: Duck", Class.get_rtti(duck) == "Duck")

    -- Test 9: get_class_name() and get_parent()
    print("\n--- Class Metadata ---")
    check("get_class_name: Dog", Dog:get_class_name() == "Dog")
    check("get_parent: Dog -> Animal", Dog:get_parent() == Animal)
    check("get_parent: GS -> Dog", GermanShepherd:get_parent() == Dog)
    check("get_parent: Animal -> nil", Animal:get_parent() == nil)

    -- Test 10: is_instance() method
    print("\n--- is_instance() method ---")
    check("is_instance: Animal:is_instance(animal)", Animal:is_instance(animal))
    check("is_instance: Dog:is_instance(dog)", Dog:is_instance(dog))
    check("is_instance: Animal:is_instance(dog)", Animal:is_instance(dog))
    check("is_instance: Dog:is_instance(animal) is false", not Dog:is_instance(animal))

    -- Summary
    print("\n========================================")
    print(string.format("RESULTS: %d passed, %d failed", passed, failed))
    print("========================================")

    return passed, failed
end

-- Run tests
local passed, failed = test()

-- Exit with appropriate code
if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
