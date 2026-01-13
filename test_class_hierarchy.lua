--[[
    Standalone test for the class hierarchy implementation
    Run with: lua test_class_hierarchy.lua
    Or with Love2D: love . test
]]

-- Setup package path to find modules
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
    print("Testing Class Hierarchy Implementation")
    print("========================================\n")

    -- Test 1: Load core utilities
    print("--- Loading Core Modules ---")
    local ok, Coord = pcall(require, "src.core.coord")
    check("Load coord.lua", ok, not ok and Coord or nil)

    local ok2, Target = pcall(require, "src.core.target")
    check("Load target.lua", ok2, not ok2 and Target or nil)

    -- Test 2: Load class system
    print("\n--- Loading Class System ---")
    local ok3, Class = pcall(require, "src.objects.class")
    check("Load class.lua", ok3, not ok3 and Class or nil)

    local ok4, AbstractClass = pcall(require, "src.objects.abstract")
    check("Load abstract.lua", ok4, not ok4 and AbstractClass or nil)

    local ok5, ObjectClass = pcall(require, "src.objects.object")
    check("Load object.lua", ok5, not ok5 and ObjectClass or nil)

    local ok6, MissionClass = pcall(require, "src.objects.mission")
    check("Load mission.lua", ok6, not ok6 and MissionClass or nil)

    local ok7, RadioClass = pcall(require, "src.objects.radio")
    check("Load radio.lua", ok7, not ok7 and RadioClass or nil)

    -- Test 3: Load heap system
    print("\n--- Loading Heap System ---")
    local ok8, HeapClass = pcall(require, "src.heap.heap")
    check("Load heap.lua", ok8, not ok8 and HeapClass or nil)

    local ok9, Globals = pcall(require, "src.heap.globals")
    check("Load globals.lua", ok9, not ok9 and Globals or nil)

    -- Skip remaining tests if basic loading failed
    if not (ok and ok2 and ok3 and ok4 and ok5 and ok6 and ok7 and ok8 and ok9) then
        print("\n========================================")
        print(string.format("RESULTS: %d passed, %d failed", passed, failed))
        print("========================================")
        return passed, failed
    end

    -- Test 4: Coordinate utilities
    print("\n--- Testing Coordinate Utilities ---")
    local coord = Coord.XYL_Coord(10, 20, 128, 128)
    check("Create COORDINATE", coord ~= 0)
    check("Extract Cell X", Coord.Coord_XCell(coord) == 10)
    check("Extract Cell Y", Coord.Coord_YCell(coord) == 20)

    local cell = Coord.XY_Cell(15, 25)
    check("Create CELL", cell ~= 0)
    check("Cell_X", Coord.Cell_X(cell) == 15)
    check("Cell_Y", Coord.Cell_Y(cell) == 25)

    local coord1 = Coord.XYL_Coord(0, 0, 128, 128)
    local coord2 = Coord.XYL_Coord(10, 0, 128, 128)
    local dist = Coord.Distance(coord1, coord2)
    check("Distance calculation", dist > 2000, string.format("distance=%d", dist))

    -- Test 5: TARGET utilities
    print("\n--- Testing TARGET Utilities ---")
    local infantry_target = Target.Build(Target.RTTI.INFANTRY, 5)
    check("Build TARGET", Target.Is_Valid(infantry_target))
    check("Get RTTI", Target.Get_RTTI(infantry_target) == Target.RTTI.INFANTRY)
    check("Get ID", Target.Get_ID(infantry_target) == 5)

    local cell_target = Target.As_Cell(cell)
    check("Cell TARGET", Target.Is_Cell(cell_target))
    check("Cell value preserved", Target.Target_Cell(cell_target) == cell)

    -- Test 6: Class inheritance
    print("\n--- Testing Class Inheritance ---")
    local obj = RadioClass:new()
    check("Create RadioClass instance", obj ~= nil)
    check("IsActive starts false", obj.IsActive == false)
    check("IsInLimbo starts true", obj.IsInLimbo == true)
    check("Mission starts NONE", obj.Mission == MissionClass.MISSION.NONE)
    check("Radio starts nil", obj.Radio == nil)

    obj.Coord = Coord.XYL_Coord(5, 10, 64, 64)
    check("Center_Coord returns Coord", obj:Center_Coord() == obj.Coord)

    obj:Set_Active()
    check("Set_Active sets IsActive", obj.IsActive == true)
    check("Set_Active sets IsRecentlyCreated", obj.IsRecentlyCreated == true)

    -- Test 7: Mission system
    print("\n--- Testing Mission System ---")
    local unit = RadioClass:new()
    unit:Set_Active()
    unit.IsInLimbo = false
    unit:Assign_Mission(MissionClass.MISSION.GUARD)
    local has_mission = (unit.Mission == MissionClass.MISSION.GUARD or
                         unit.MissionQueue == MissionClass.MISSION.GUARD)
    check("Assign_Mission", has_mission)

    -- Test 8: Radio system
    print("\n--- Testing Radio System ---")
    local obj1 = RadioClass:new()
    local obj2 = RadioClass:new()
    obj1:Set_Active()
    obj2:Set_Active()

    local reply = obj1:Transmit_Message(RadioClass.RADIO.HELLO, 0, obj2)
    check("HELLO returns ROGER", reply == RadioClass.RADIO.ROGER)
    check("Contact established", obj1.Radio == obj2)

    obj1:Transmit_Message(RadioClass.RADIO.OVER_OUT)
    check("Contact broken", obj1.Radio == nil)

    -- Test 9: HeapClass
    print("\n--- Testing HeapClass ---")
    local heap = HeapClass.new(RadioClass, 10, Target.RTTI.INFANTRY)
    check("Heap created", heap ~= nil)
    check("Heap starts empty", heap:Count() == 0)
    check("Max size correct", heap:Max_Count() == 10)

    local alloc1 = heap:Allocate()
    local alloc2 = heap:Allocate()
    check("Allocate obj1", alloc1 ~= nil)
    check("Allocate obj2", alloc2 ~= nil)
    check("Count after alloc", heap:Count() == 2)
    check("Different indices", alloc1:get_heap_index() ~= alloc2:get_heap_index())

    heap:Free(alloc1)
    check("Count after free", heap:Count() == 1)

    local alloc3 = heap:Allocate()
    check("Reallocate after free", alloc3 ~= nil)
    check("Count after realloc", heap:Count() == 2)

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
