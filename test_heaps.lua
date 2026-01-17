--[[
    test_heaps.lua - Heap initialization and object pool verification tests

    Run with: lovec . test_heaps
]]

print("\n========================================")
print("Heap Initialization Tests")
print("========================================\n")

local passed = 0
local failed = 0

local function test(name, condition)
    if condition then
        print("[PASS] " .. name)
        passed = passed + 1
    else
        print("[FAIL] " .. name)
        failed = failed + 1
    end
end

-- Test 1: Globals module loads
local Globals = require("src.heap.globals")
test("Globals module loads", Globals ~= nil)

-- Test 2: HeapClass module loads
local HeapClass = require("src.heap.heap")
test("HeapClass module loads", HeapClass ~= nil)

-- Test 3: Target module loads (needed for RTTI)
local Target = require("src.core.target")
test("Target module loads", Target ~= nil)
test("Target.RTTI exists", Target.RTTI ~= nil)

-- Test 4: Heaps not initialized before Init_All_Heaps()
test("Heaps not initialized initially", not Globals.Is_Initialized())

-- Test 5: Init_All_Heaps runs without error
local init_success = pcall(function()
    Globals.Init_All_Heaps()
end)
test("Init_All_Heaps runs without error", init_success)

-- Test 6: Is_Initialized returns true after init
test("Is_Initialized returns true", Globals.Is_Initialized())

-- Test 7: Correct number of heaps registered (6 game object types)
test("6 heaps registered", Globals.Get_Heap_Count() == 6)

-- Test 8: Each heap exists
test("BUILDING heap exists", Globals.Get_Heap(Target.RTTI.BUILDING) ~= nil)
test("INFANTRY heap exists", Globals.Get_Heap(Target.RTTI.INFANTRY) ~= nil)
test("UNIT heap exists", Globals.Get_Heap(Target.RTTI.UNIT) ~= nil)
test("AIRCRAFT heap exists", Globals.Get_Heap(Target.RTTI.AIRCRAFT) ~= nil)
test("BULLET heap exists", Globals.Get_Heap(Target.RTTI.BULLET) ~= nil)
test("ANIM heap exists", Globals.Get_Heap(Target.RTTI.ANIM) ~= nil)

-- Test 9: Heap sizes match limits
local infantry_heap = Globals.Get_Heap(Target.RTTI.INFANTRY)
test("Infantry heap size correct", infantry_heap:Max_Count() == HeapClass.LIMITS.INFANTRY)

local building_heap = Globals.Get_Heap(Target.RTTI.BUILDING)
test("Building heap size correct", building_heap:Max_Count() == HeapClass.LIMITS.BUILDINGS)

-- Test 10: Can allocate an object from heap
local infantry = infantry_heap:Allocate()
test("Can allocate infantry object", infantry ~= nil)
test("Allocated object is active", infantry and infantry.IsActive == true)
test("Heap count increased", infantry_heap:Count() == 1)

-- Test 11: Allocated object has correct RTTI
local rtti = infantry and infantry.get_rtti and infantry:get_rtti()
test("Allocated infantry has correct RTTI", rtti == Target.RTTI.INFANTRY)

-- Test 12: Can free object back to heap
local free_success = infantry_heap:Free(infantry)
test("Can free infantry object", free_success == true)
test("Heap count back to 0", infantry_heap:Count() == 0)

-- Test 13: Process_All_AI works with empty heaps
local ai_success = pcall(function()
    Globals.Process_All_AI()
end)
test("Process_All_AI works with empty heaps", ai_success)

-- Test 14: Allocate object and call AI
infantry = infantry_heap:Allocate()
test("Re-allocate infantry for AI test", infantry ~= nil)

local ai_call_success, ai_err = pcall(function()
    if infantry and infantry.AI then
        infantry:AI()
    end
end)
if not ai_call_success then
    print("  [DEBUG] Infantry:AI() error: " .. tostring(ai_err))
end
test("Infantry:AI() runs without error", ai_call_success)

-- Test 15: Process_All_AI with active object
ai_success, ai_err = pcall(function()
    Globals.Process_All_AI()
end)
if not ai_success then
    print("  [DEBUG] Process_All_AI error: " .. tostring(ai_err))
end
test("Process_All_AI works with active object", ai_success)

-- Cleanup
infantry_heap:Free(infantry)

-- Test 16: Reset_All_Heaps works
local unit_heap = Globals.Get_Heap(Target.RTTI.UNIT)
unit_heap:Allocate()
unit_heap:Allocate()
test("Allocated 2 units", unit_heap:Count() == 2)

Globals.Reset_All_Heaps()
test("Reset_All_Heaps clears all objects", Globals.Total_Active_Count() == 0)

-- Summary
print("\n========================================")
print(string.format("RESULTS: %d passed, %d failed", passed, failed))
print("========================================")

if failed > 0 then
    os.exit(1)
end
