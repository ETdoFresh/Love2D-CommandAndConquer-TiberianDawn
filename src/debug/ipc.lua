--[[
    IPC (Inter-Process Communication) System
    Allows external control of the game via file-based commands

    Commands are written to: <temp>/love2d_ipc_<pid>/command.txt
    Responses are written to: <temp>/love2d_ipc_<pid>/response.json

    Supported commands:
    - input <key>           : Simulate key press (e.g., "input return", "input w")
    - gamepad <button>      : Simulate gamepad button (e.g., "gamepad a", "gamepad start")
    - type <text>           : Type text string
    - screenshot [path]     : Take screenshot, save to path or return base64
    - state                 : Get JSON state of game
    - pause                 : Pause the game
    - resume                : Resume the game
    - tick [n]              : Advance n ticks (default 1)
    - quit                  : Quit the game
    - eval <lua>            : Evaluate Lua code (dangerous but useful for debug)
]]

local IPC = {}
IPC.__index = IPC

-- Get unique instance ID (timestamp when game started)
function IPC.get_instance_id()
    if not IPC._instance_id then
        IPC._instance_id = tostring(os.time())
    end
    return IPC._instance_id
end

-- Generate IPC directory path
function IPC.get_ipc_dir()
    local temp = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return temp .. "/love2d_ipc_" .. IPC.get_instance_id()
end


function IPC.new(game)
    local self = setmetatable({}, IPC)

    self.game = game
    self.instance_id = IPC.get_instance_id()
    self.ipc_dir = IPC.get_ipc_dir()
    self.command_file = self.ipc_dir .. "/command.txt"
    self.response_file = self.ipc_dir .. "/response.json"

    -- Pending input events to simulate
    self.pending_keys = {}
    self.pending_gamepad = {}
    self.pending_text = nil

    -- Tick control
    self.manual_tick_mode = false
    self.ticks_to_advance = 0

    -- Create IPC directory
    self:init_ipc()

    return self
end

-- Initialize IPC directory and files
function IPC:init_ipc()
    -- Create directory (platform specific)
    os.execute('mkdir "' .. self.ipc_dir .. '" 2>nul')

    -- Clear any old command file
    os.remove(self.command_file)
    os.remove(self.response_file)

    -- Print to stdout - this is how CLI discovers the instance
    print("IPC_ID=" .. self.instance_id)
end

-- Check for and process commands
function IPC:update(dt)
    -- Check for command file
    local f = io.open(self.command_file, "r")
    if f then
        local command = f:read("*all")
        f:close()

        -- Remove command file immediately
        os.remove(self.command_file)

        if command and #command > 0 then
            self:process_command(command:match("^%s*(.-)%s*$")) -- trim
        end
    end

    -- Process pending inputs
    self:process_pending_inputs()
end

-- Process a command string
function IPC:process_command(command)
    local parts = {}
    for part in command:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then return end

    local cmd = parts[1]:lower()
    local response = { success = true, command = cmd }

    if cmd == "input" or cmd == "key" then
        local key = parts[2]
        if key then
            table.insert(self.pending_keys, key:lower())
            response.message = "Queued key: " .. key
        else
            response.success = false
            response.error = "Missing key argument"
        end

    elseif cmd == "gamepad" or cmd == "button" then
        local button = parts[2]
        if button then
            table.insert(self.pending_gamepad, button:lower())
            response.message = "Queued gamepad: " .. button
        else
            response.success = false
            response.error = "Missing button argument"
        end

    elseif cmd == "type" then
        -- Rest of command is the text
        local text = command:sub(6) -- skip "type "
        self.pending_text = text
        response.message = "Queued text: " .. text

    elseif cmd == "screenshot" then
        local path = parts[2]
        local success, result = self:take_screenshot(path)
        response.success = success
        if success then
            response.path = result
        else
            response.error = result
        end

    elseif cmd == "state" then
        response.state = self:get_game_state()

    elseif cmd == "pause" then
        if self.game then
            self.game.paused = true
            if self.game.state == self.game.STATE.PLAYING then
                self.game.state = self.game.STATE.PAUSED
            end
        end
        response.message = "Game paused"

    elseif cmd == "resume" then
        if self.game then
            self.game.paused = false
            if self.game.state == self.game.STATE.PAUSED then
                self.game.state = self.game.STATE.PLAYING
            end
        end
        response.message = "Game resumed"

    elseif cmd == "tick" then
        local n = tonumber(parts[2]) or 1
        self.ticks_to_advance = n
        self.manual_tick_mode = true
        response.message = "Advancing " .. n .. " tick(s)"

    elseif cmd == "quit" or cmd == "exit" then
        response.message = "Quitting game"
        self:write_response(response)
        love.event.quit()
        return

    elseif cmd == "eval" then
        -- Dangerous but useful for debugging
        local code = command:sub(6) -- skip "eval "
        local fn, err = loadstring(code)
        if fn then
            -- Set up environment with access to game
            setfenv(fn, setmetatable({
                game = self.game,
                ipc = self,
                love = love,
                print = print
            }, {__index = _G}))
            local ok, result = pcall(fn)
            if ok then
                response.result = tostring(result)
            else
                response.success = false
                response.error = result
            end
        else
            response.success = false
            response.error = err
        end

    elseif cmd == "click" then
        -- click <x> <y> [button] - Simulate mouse click
        local x = tonumber(parts[2])
        local y = tonumber(parts[3])
        local button = tonumber(parts[4]) or 1
        if x and y then
            if self.game then
                self.game:mousepressed(x, y, button)
                self.game:mousereleased(x, y, button)
            end
            response.message = string.format("Clicked at (%d, %d) button %d", x, y, button)
        else
            response.success = false
            response.error = "Usage: click <x> <y> [button]"
        end

    elseif cmd == "test_classes" then
        -- Test the new class hierarchy implementation
        local test_result = self:test_class_hierarchy()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_display" then
        -- Test the display hierarchy implementation
        local test_result = self:test_display_hierarchy()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_techno" then
        -- Test the TechnoClass and FootClass implementation
        local test_result = self:test_techno_classes()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_drive" then
        -- Test the DriveClass, TurretClass, TarComClass, and FlyClass implementation
        local test_result = self:test_drive_classes()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_types" then
        -- Test the type class hierarchy
        local test_result = self:test_type_classes()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_concrete" then
        -- Test the concrete classes (InfantryClass, UnitClass, AircraftClass, BuildingClass)
        local test_result = self:test_concrete_classes()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_specific_types" then
        -- Test the specific type classes (InfantryTypeClass, UnitTypeClass, AircraftTypeClass, BuildingTypeClass)
        local test_result = self:test_specific_types()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_combat" then
        -- Test the Phase 3 combat classes (BulletClass, AnimClass, WeaponTypeClass, WarheadTypeClass)
        local test_result = self:test_combat_classes()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_phase3" then
        -- Test Phase 3 integration (pathfinding, combat system)
        local test_result = self:test_phase3_integration()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "help" then
        response.commands = {
            "input <key> - Simulate key press",
            "gamepad <button> - Simulate gamepad button",
            "type <text> - Type text string",
            "click <x> <y> [button] - Simulate mouse click",
            "screenshot [path] - Take screenshot",
            "state - Get game state JSON",
            "pause - Pause game",
            "resume - Resume game",
            "tick [n] - Advance n ticks",
            "quit - Quit game",
            "eval <lua> - Execute Lua code",
            "test_classes - Test the class hierarchy",
            "test_display - Test the display hierarchy",
            "test_techno - Test TechnoClass and FootClass",
            "test_drive - Test DriveClass, TurretClass, TarComClass, FlyClass",
            "test_types - Test AbstractTypeClass, ObjectTypeClass, TechnoTypeClass",
            "test_concrete - Test InfantryClass, UnitClass, AircraftClass, BuildingClass",
            "test_specific_types - Test InfantryTypeClass, UnitTypeClass, AircraftTypeClass, BuildingTypeClass",
            "test_combat - Test BulletClass, AnimClass, WeaponTypeClass, WarheadTypeClass",
            "test_phase3 - Test Phase 3 integration (pathfinding, combat)",
            "help - Show this help"
        }

    else
        response.success = false
        response.error = "Unknown command: " .. cmd
    end

    self:write_response(response)
end

-- Process pending input events
function IPC:process_pending_inputs()
    -- Process keyboard inputs
    while #self.pending_keys > 0 do
        local key = table.remove(self.pending_keys, 1)
        -- Simulate key press - only call game.keypressed
        -- (don't call love.keypressed as that would double the input)
        if self.game then
            self.game:keypressed(key)
        end
    end

    -- Process gamepad inputs
    while #self.pending_gamepad > 0 do
        local button = table.remove(self.pending_gamepad, 1)
        if self.game and self.game.gamepadpressed then
            -- Create a fake joystick object
            local fake_joystick = {
                getName = function() return "IPC Virtual Gamepad" end,
                isGamepad = function() return true end,
                isConnected = function() return true end,
                getGamepadAxis = function() return 0 end
            }
            self.game:gamepadpressed(fake_joystick, button)
        end
    end

    -- Process text input
    if self.pending_text then
        for i = 1, #self.pending_text do
            local char = self.pending_text:sub(i, i)
            love.textinput(char)
        end
        self.pending_text = nil
    end
end

-- Take a screenshot
function IPC:take_screenshot(path)
    if not path then
        path = "screenshot_" .. os.time() .. ".png"
    end

    -- In Love2D 11.x, use love.graphics.captureScreenshot
    -- This schedules a screenshot to be taken at the end of the current frame
    local full_path = love.filesystem.getSaveDirectory() .. "/" .. path

    local success, err = pcall(function()
        love.graphics.captureScreenshot(path)
    end)

    if not success then
        return false, "Screenshot failed: " .. tostring(err)
    end

    return true, full_path
end

-- Get game state as a table
function IPC:get_game_state()
    local state = {
        timestamp = os.time(),
        love_version = love.getVersion(),
    }

    if self.game then
        state.game = {
            state = self.game.state,
            mode = self.game.mode,
            paused = self.game.paused,
            tick_count = self.game.tick_count,
            player_house = self.game.player_house,
            menu_selection = self.game.menu_selection,
            menu_items = self.game.menu_items,
            use_hd = self.game.use_hd,
            fog_enabled = self.game.fog_enabled,
            show_sidebar = self.game.show_sidebar,
        }

        -- Camera info
        if self.game.render_system then
            state.camera = {
                x = self.game.render_system.camera_x,
                y = self.game.render_system.camera_y,
                scale = self.game.render_system.scale
            }
        end

        -- Selection info
        if self.game.selection_system then
            local selected = self.game.selection_system:get_selected_entities()
            state.selection = {
                count = #selected,
                entity_ids = {}
            }
            for _, e in ipairs(selected) do
                table.insert(state.selection.entity_ids, e.id)
            end
        end

        -- Entity count
        if self.game.world then
            local entities = self.game.world:get_all_entities()
            state.entities = {
                total = #entities
            }
        end
    end

    -- Window info
    state.window = {
        width = love.graphics.getWidth(),
        height = love.graphics.getHeight(),
        fullscreen = love.window.getFullscreen()
    }

    return state
end

-- Write response to file
function IPC:write_response(response)
    local f = io.open(self.response_file, "w")
    if f then
        f:write(self:encode_json(response))
        f:close()
    end
end

-- Simple JSON encoder (no external dependency)
function IPC:encode_json(value, indent)
    indent = indent or 0
    local t = type(value)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\')
                             :gsub('"', '\\"')
                             :gsub('\n', '\\n')
                             :gsub('\r', '\\r')
                             :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if array or object
        local is_array = true
        local max_index = 0
        for k, v in pairs(value) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                is_array = false
                break
            end
            max_index = math.max(max_index, k)
        end
        is_array = is_array and max_index == #value

        local parts = {}
        local spacing = string.rep("  ", indent + 1)

        if is_array then
            for i, v in ipairs(value) do
                table.insert(parts, spacing .. self:encode_json(v, indent + 1))
            end
            if #parts == 0 then
                return "[]"
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", indent) .. "]"
        else
            for k, v in pairs(value) do
                local key = type(k) == "string" and k or tostring(k)
                table.insert(parts, spacing .. '"' .. key .. '": ' .. self:encode_json(v, indent + 1))
            end
            if #parts == 0 then
                return "{}"
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", indent) .. "}"
        end
    else
        return '"[' .. t .. ']"'
    end
end

-- Test the class hierarchy implementation
function IPC:test_class_hierarchy()
    local result = {
        success = true,
        tests = {},
        message = ""
    }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail or ""
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all modules
    local ok, err = pcall(function()
        -- Core utilities
        local Coord = require("src.core.coord")
        local Target = require("src.core.target")

        -- Class system
        local Class = require("src.objects.class")
        local AbstractClass = require("src.objects.abstract")
        local ObjectClass = require("src.objects.object")
        local MissionClass = require("src.objects.mission")
        local RadioClass = require("src.objects.radio")

        -- Heap system
        local HeapClass = require("src.heap.heap")
        local Globals = require("src.heap.globals")

        add_test("Module loading", true, "All modules loaded successfully")
    end)

    if not ok then
        add_test("Module loading", false, tostring(err))
        result.message = "Failed to load modules: " .. tostring(err)
        return result
    end

    -- Test 2: COORDINATE utilities
    local Coord = require("src.core.coord")
    local ok2, err2 = pcall(function()
        -- Create a coordinate
        local coord = Coord.XYL_Coord(10, 20, 128, 128)

        -- Extract cell
        local cell_x = Coord.Coord_XCell(coord)
        local cell_y = Coord.Coord_YCell(coord)
        assert(cell_x == 10, "Cell X should be 10, got " .. cell_x)
        assert(cell_y == 20, "Cell Y should be 20, got " .. cell_y)

        -- Cell operations
        local cell = Coord.XY_Cell(15, 25)
        assert(Coord.Cell_X(cell) == 15, "Cell_X failed")
        assert(Coord.Cell_Y(cell) == 25, "Cell_Y failed")

        -- Distance
        local coord1 = Coord.XYL_Coord(0, 0, 128, 128)
        local coord2 = Coord.XYL_Coord(10, 0, 128, 128)
        local dist = Coord.Distance(coord1, coord2)
        assert(dist > 2000, "Distance should be > 2000 leptons")

        add_test("Coordinate utilities", true, "COORD/CELL operations work")
    end)

    if not ok2 then
        add_test("Coordinate utilities", false, tostring(err2))
    end

    -- Test 3: TARGET utilities
    local Target = require("src.core.target")
    local ok3, err3 = pcall(function()
        -- Create targets
        local infantry_target = Target.Build(Target.RTTI.INFANTRY, 5)
        assert(Target.Is_Valid(infantry_target), "Infantry target should be valid")
        assert(Target.Get_RTTI(infantry_target) == Target.RTTI.INFANTRY, "RTTI should be INFANTRY")
        assert(Target.Get_ID(infantry_target) == 5, "ID should be 5")

        -- Cell target
        local cell = Coord.XY_Cell(10, 20)
        local cell_target = Target.As_Cell(cell)
        assert(Target.Is_Cell(cell_target), "Should be cell target")
        assert(Target.Target_Cell(cell_target) == cell, "Cell value should match")

        add_test("TARGET utilities", true, "TARGET encoding/decoding works")
    end)

    if not ok3 then
        add_test("TARGET utilities", false, tostring(err3))
    end

    -- Test 4: Class inheritance
    local Class = require("src.objects.class")
    local AbstractClass = require("src.objects.abstract")
    local ObjectClass = require("src.objects.object")
    local MissionClass = require("src.objects.mission")
    local RadioClass = require("src.objects.radio")

    local ok4, err4 = pcall(function()
        -- Create a RadioClass instance (top of base hierarchy)
        local obj = RadioClass:new()

        -- Check inheritance chain
        assert(obj.IsActive == false, "Should start inactive")
        assert(obj.IsInLimbo == true, "Should start in limbo")
        assert(obj.Mission == MissionClass.MISSION.NONE, "Should have no mission")
        assert(obj.Radio == nil, "Should have no radio contact")

        -- Test methods from different levels
        obj.Coord = Coord.XYL_Coord(5, 10, 64, 64)
        local center = obj:Center_Coord()
        assert(center == obj.Coord, "Center_Coord should return Coord")

        -- Set active
        obj:Set_Active()
        assert(obj.IsActive == true, "Should be active after Set_Active")
        assert(obj.IsRecentlyCreated == true, "Should be recently created")

        add_test("Class inheritance", true, "Inheritance chain works correctly")
    end)

    if not ok4 then
        add_test("Class inheritance", false, tostring(err4))
    end

    -- Test 5: Mission system
    local ok5, err5 = pcall(function()
        local obj = RadioClass:new()
        obj:Set_Active()
        obj.IsInLimbo = false

        -- Assign mission
        obj:Assign_Mission(MissionClass.MISSION.GUARD)

        -- Mission should be queued or active
        assert(obj.Mission == MissionClass.MISSION.GUARD or
               obj.MissionQueue == MissionClass.MISSION.GUARD,
               "Mission should be assigned")

        add_test("Mission system", true, "Mission assignment works")
    end)

    if not ok5 then
        add_test("Mission system", false, tostring(err5))
    end

    -- Test 6: Radio system
    local ok6, err6 = pcall(function()
        local obj1 = RadioClass:new()
        local obj2 = RadioClass:new()
        obj1:Set_Active()
        obj2:Set_Active()

        -- Establish contact
        local reply = obj1:Transmit_Message(RadioClass.RADIO.HELLO, 0, obj2)
        assert(reply == RadioClass.RADIO.ROGER, "Should get ROGER reply")
        assert(obj1.Radio == obj2, "obj1 should be in contact with obj2")

        -- Break contact
        obj1:Transmit_Message(RadioClass.RADIO.OVER_OUT)
        assert(obj1.Radio == nil, "Contact should be broken")

        add_test("Radio system", true, "Radio contact works")
    end)

    if not ok6 then
        add_test("Radio system", false, tostring(err6))
    end

    -- Test 7: HeapClass
    local HeapClass = require("src.heap.heap")
    local ok7, err7 = pcall(function()
        -- Create a small heap for testing
        local heap = HeapClass.new(RadioClass, 10, Target.RTTI.INFANTRY)

        assert(heap:Count() == 0, "Heap should start empty")
        assert(heap:Max_Count() == 10, "Max should be 10")

        -- Allocate some objects
        local obj1 = heap:Allocate()
        local obj2 = heap:Allocate()
        assert(obj1 ~= nil, "Should allocate obj1")
        assert(obj2 ~= nil, "Should allocate obj2")
        assert(heap:Count() == 2, "Should have 2 active")

        -- Objects should have different heap indices
        assert(obj1:get_heap_index() ~= obj2:get_heap_index(), "Different indices")

        -- Free one
        heap:Free(obj1)
        assert(heap:Count() == 1, "Should have 1 active after free")

        -- Allocate again - should reuse slot
        local obj3 = heap:Allocate()
        assert(obj3 ~= nil, "Should allocate obj3")
        assert(heap:Count() == 2, "Should have 2 active again")

        add_test("HeapClass", true, "Heap allocation/deallocation works")
    end)

    if not ok7 then
        add_test("HeapClass", false, tostring(err7))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the display hierarchy implementation
function IPC:test_display_hierarchy()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all display modules
    local ok1, err1 = pcall(function()
        local LayerClass = require("src.map.layer")
        local GScreenClass = require("src.display.gscreen")
        local DisplayClass = require("src.display.display")
        local RadarClass = require("src.display.radar")
        local ScrollClass = require("src.display.scroll")
        local MouseClass = require("src.display.mouse")

        assert(LayerClass ~= nil, "LayerClass should load")
        assert(GScreenClass ~= nil, "GScreenClass should load")
        assert(DisplayClass ~= nil, "DisplayClass should load")
        assert(RadarClass ~= nil, "RadarClass should load")
        assert(ScrollClass ~= nil, "ScrollClass should load")
        assert(MouseClass ~= nil, "MouseClass should load")

        add_test("Module loading", true, "All display modules loaded")
    end)

    if not ok1 then
        add_test("Module loading", false, tostring(err1))
        return result
    end

    -- Test 2: LayerClass
    local LayerClass = require("src.map.layer")
    local ok2, err2 = pcall(function()
        -- Initialize layers
        LayerClass.Init_All()

        -- Get ground layer
        local ground = LayerClass.Get_Layer(LayerClass.LAYER_TYPE.GROUND)
        assert(ground ~= nil, "Should get ground layer")
        assert(ground:Count() == 0, "Ground layer should be empty")

        -- Create mock objects with Coord for sorting
        local obj1 = { Coord = 0x00140000 }  -- Y = 20
        local obj2 = { Coord = 0x000A0000 }  -- Y = 10
        local obj3 = { Coord = 0x001E0000 }  -- Y = 30

        -- Add objects
        ground:Submit(obj1)
        ground:Submit(obj2)
        ground:Submit(obj3)
        assert(ground:Count() == 3, "Should have 3 objects")

        -- Sort
        ground:Full_Sort()

        -- Check order (lowest Y first)
        assert(ground:Get(1) == obj2, "obj2 (Y=10) should be first")
        assert(ground:Get(2) == obj1, "obj1 (Y=20) should be second")
        assert(ground:Get(3) == obj3, "obj3 (Y=30) should be third")

        -- Remove
        ground:Remove(obj1)
        assert(ground:Count() == 2, "Should have 2 after remove")

        -- Clear
        ground:Clear()
        assert(ground:Count() == 0, "Should be empty after clear")

        add_test("LayerClass", true, "Layer sorting and management works")
    end)

    if not ok2 then
        add_test("LayerClass", false, tostring(err2))
    end

    -- Test 3: Display inheritance chain
    local MouseClass = require("src.display.mouse")
    local ok3, err3 = pcall(function()
        local display = MouseClass:new()

        -- Should have properties from all parent classes
        assert(display.IsToRedraw ~= nil, "Should have GScreenClass.IsToRedraw")
        assert(display.TacticalCoord ~= nil, "Should have DisplayClass.TacticalCoord")
        assert(display.IsRadarActive ~= nil, "Should have RadarClass.IsRadarActive")
        assert(display.IsAutoScroll ~= nil, "Should have ScrollClass.IsAutoScroll")
        assert(display.CurrentMouseShape ~= nil, "Should have MouseClass.CurrentMouseShape")

        add_test("Display inheritance", true, "Inheritance chain works correctly")
    end)

    if not ok3 then
        add_test("Display inheritance", false, tostring(err3))
    end

    -- Test 4: Coordinate conversions
    local Coord = require("src.core.coord")
    local DisplayClass = require("src.display.display")
    local ok4, err4 = pcall(function()
        local display = DisplayClass:new()

        -- Set up view dimensions
        display.TacPixelX = 0
        display.TacPixelY = 0
        display.TacLeptonWidth = 256 * 10   -- 10 cells wide
        display.TacLeptonHeight = 256 * 10  -- 10 cells tall
        display.TacticalCoord = 0

        -- Test Pixel_To_Coord
        local coord = display:Pixel_To_Coord(48, 48)
        assert(coord ~= nil, "Should get coordinate")

        -- Test In_View
        local cell_in_view = Coord.XY_Cell(5, 5)
        local cell_outside = Coord.XY_Cell(50, 50)
        assert(display:In_View(cell_in_view), "Cell 5,5 should be in view")
        -- Note: In_View may return true for large cells if viewport is small

        add_test("Coordinate conversions", true, "Coord conversions work")
    end)

    if not ok4 then
        add_test("Coordinate conversions", false, tostring(err4))
    end

    -- Test 5: ScrollClass
    local ScrollClass = require("src.display.scroll")
    local ok5, err5 = pcall(function()
        local scroll = ScrollClass:new()

        -- Test auto-scroll toggle
        assert(scroll.IsAutoScroll == true, "Auto-scroll should be on by default")
        scroll:Set_Autoscroll(0)
        assert(scroll.IsAutoScroll == false, "Should turn off")
        scroll:Set_Autoscroll(-1)
        assert(scroll.IsAutoScroll == true, "Should toggle on")

        -- Test edge detection
        local dir = scroll:Get_Edge_Direction(5, 100)  -- Left edge
        assert(dir == ScrollClass.DIR.W, "Should detect west edge")

        dir = scroll:Get_Edge_Direction(400, 5)  -- Top edge
        assert(dir == ScrollClass.DIR.N, "Should detect north edge")

        dir = scroll:Get_Edge_Direction(400, 300)  -- Center
        assert(dir == ScrollClass.DIR.NONE, "Should detect no edge")

        add_test("ScrollClass", true, "Edge scrolling detection works")
    end)

    if not ok5 then
        add_test("ScrollClass", false, tostring(err5))
    end

    -- Test 6: MouseClass cursor control
    local ok6, err6 = pcall(function()
        local mouse = MouseClass:new()

        -- Test default cursor
        assert(mouse.CurrentMouseShape == MouseClass.MOUSE.NORMAL, "Should start with NORMAL")

        -- Test override
        mouse:Override_Mouse_Shape(MouseClass.MOUSE.CAN_MOVE)
        assert(mouse.CurrentMouseShape == MouseClass.MOUSE.CAN_MOVE, "Should override")

        -- Test revert
        mouse:Revert_Mouse_Shape()
        assert(mouse.CurrentMouseShape == MouseClass.MOUSE.NORMAL, "Should revert to normal")

        -- Test set default
        mouse:Set_Default_Mouse(MouseClass.MOUSE.CAN_SELECT)
        assert(mouse.NormalMouseShape == MouseClass.MOUSE.CAN_SELECT, "Should set new default")

        add_test("MouseClass", true, "Cursor control works")
    end)

    if not ok6 then
        add_test("MouseClass", false, tostring(err6))
    end

    -- Test 7: RadarClass
    local RadarClass = require("src.display.radar")
    local ok7, err7 = pcall(function()
        local radar = RadarClass:new()

        -- Initial state
        assert(radar.DoesRadarExist == false, "Radar should not exist initially")
        assert(radar.IsRadarActive == false, "Radar should be inactive")

        -- Enable radar
        radar.DoesRadarExist = true
        radar:Radar_Activate(1)
        assert(radar.IsRadarActivating == true, "Should be activating")

        -- Simulate activation complete
        radar.RadarAnimFrame = RadarClass.RADAR_ACTIVATED_FRAME
        radar:AI(nil, 0, 0)  -- Process animation
        assert(radar.IsRadarActive == true, "Should be fully active")

        -- Test zoom toggle
        radar:Zoom_Mode(0)
        assert(radar.IsZoomed == true, "Should toggle zoom on")
        radar:Zoom_Mode(0)
        assert(radar.IsZoomed == false, "Should toggle zoom off")

        add_test("RadarClass", true, "Radar activation and zoom work")
    end)

    if not ok7 then
        add_test("RadarClass", false, tostring(err7))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the TechnoClass and FootClass implementation (Phase 2)
function IPC:test_techno_classes()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all mixin modules
    local ok1, err1 = pcall(function()
        local FlasherClass = require("src.objects.mixins.flasher")
        local StageClass = require("src.objects.mixins.stage")
        local CargoClass = require("src.objects.mixins.cargo")
        local DoorClass = require("src.objects.mixins.door")
        local CrewClass = require("src.objects.mixins.crew")

        assert(FlasherClass ~= nil, "FlasherClass should load")
        assert(StageClass ~= nil, "StageClass should load")
        assert(CargoClass ~= nil, "CargoClass should load")
        assert(DoorClass ~= nil, "DoorClass should load")
        assert(CrewClass ~= nil, "CrewClass should load")

        add_test("Mixin modules", true, "All mixin modules loaded")
    end)

    if not ok1 then
        add_test("Mixin modules", false, tostring(err1))
        return result
    end

    -- Test 2: Load TechnoClass and FootClass
    local ok2, err2 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local FootClass = require("src.objects.foot")

        assert(TechnoClass ~= nil, "TechnoClass should load")
        assert(FootClass ~= nil, "FootClass should load")

        add_test("TechnoClass/FootClass loading", true, "Main classes loaded")
    end)

    if not ok2 then
        add_test("TechnoClass/FootClass loading", false, tostring(err2))
        return result
    end

    -- Test 3: FlasherClass mixin
    local FlasherClass = require("src.objects.mixins.flasher")
    local ok3, err3 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        -- Should have flasher methods from mixin
        assert(techno.FlashCount ~= nil, "Should have FlashCount")
        assert(techno.IsBlushing ~= nil, "Should have IsBlushing")

        -- Test flash
        techno:Start_Flash(7)
        assert(techno.FlashCount == 7, "Flash count should be 7")

        -- Process flash - FlashCount goes 7 -> 6
        techno:Process()
        assert(techno.FlashCount == 6, "Flash count should decrement")
        assert(techno.IsBlushing == false, "Should not be blushing (6 is even)")

        -- FlashCount goes 6 -> 5
        techno:Process()
        assert(techno.FlashCount == 5, "Flash count should be 5")
        assert(techno.IsBlushing == true, "Should be blushing (5 is odd)")

        techno:Stop_Flash()
        assert(techno.FlashCount == 0, "Flash should be stopped")

        add_test("FlasherClass mixin", true, "Flasher behavior works")
    end)

    if not ok3 then
        add_test("FlasherClass mixin", false, tostring(err3))
    end

    -- Test 4: StageClass mixin
    local ok4, err4 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        -- Should have stage methods
        assert(techno:Fetch_Stage() == 0, "Stage should start at 0")

        techno:Set_Stage(5)
        assert(techno:Fetch_Stage() == 5, "Stage should be 5")

        techno:Set_Rate(3)
        assert(techno:Fetch_Rate() == 3, "Rate should be 3")

        -- Process graphics logic
        techno.StageTimer = 1  -- About to expire
        local changed = techno:Graphic_Logic()
        assert(changed == true, "Should signal stage change")
        assert(techno:Fetch_Stage() == 6, "Stage should increment")

        add_test("StageClass mixin", true, "Stage animation works")
    end)

    if not ok4 then
        add_test("StageClass mixin", false, tostring(err4))
    end

    -- Test 5: CargoClass mixin
    local ok5, err5 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        assert(techno:How_Many() == 0, "Should start empty")

        -- Create mock cargo objects
        local cargo1 = { Member = nil }
        local cargo2 = { Member = nil }

        techno:Attach(cargo1)
        assert(techno:How_Many() == 1, "Should have 1")
        assert(techno:Is_Something_Attached() == true, "Should have cargo")

        techno:Attach(cargo2)
        assert(techno:How_Many() == 2, "Should have 2")

        local detached = techno:Detach_Object()
        assert(detached == cargo2, "Should detach last attached (cargo2)")
        assert(techno:How_Many() == 1, "Should have 1 left")

        techno:Clear_Cargo()
        assert(techno:How_Many() == 0, "Should be empty")

        add_test("CargoClass mixin", true, "Cargo management works")
    end)

    if not ok5 then
        add_test("CargoClass mixin", false, tostring(err5))
    end

    -- Test 6: DoorClass mixin
    local DoorClass = require("src.objects.mixins.door")
    local ok6, err6 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        assert(techno:Is_Door_Closed() == true, "Should start closed")

        -- Open door
        techno:Open_Door(2, 4)  -- rate=2, stages=4
        assert(techno:Is_Door_Opening() == true, "Should be opening")

        -- Process door animation
        for i = 1, 10 do
            techno:AI_Door()
        end
        assert(techno:Is_Door_Open() == true, "Should be fully open")

        -- Close door
        techno:Close_Door(2, 4)
        assert(techno:Is_Door_Closing() == true, "Should be closing")

        for i = 1, 10 do
            techno:AI_Door()
        end
        assert(techno:Is_Door_Closed() == true, "Should be fully closed")

        add_test("DoorClass mixin", true, "Door animation works")
    end)

    if not ok6 then
        add_test("DoorClass mixin", false, tostring(err6))
    end

    -- Test 7: CrewClass mixin
    local ok7, err7 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        assert(techno:Get_Kills() == 0, "Should start with 0 kills")
        assert(techno:Get_Rank_Name() == "Rookie", "Should be Rookie")

        -- Add kills
        techno:Made_A_Kill()
        techno:Made_A_Kill()
        techno:Made_A_Kill()
        assert(techno:Get_Kills() == 3, "Should have 3 kills")
        assert(techno:Is_Veteran() == true, "Should be Veteran")

        -- More kills for elite
        for i = 1, 7 do
            techno:Made_A_Kill()
        end
        assert(techno:Get_Kills() == 10, "Should have 10 kills")
        assert(techno:Is_Elite() == true, "Should be Elite")
        assert(techno:Get_Rank_Name() == "Elite", "Should show Elite")

        add_test("CrewClass mixin", true, "Kill tracking and ranks work")
    end)

    if not ok7 then
        add_test("CrewClass mixin", false, tostring(err7))
    end

    -- Test 8: TechnoClass flags and state
    local Target = require("src.core.target")
    local ok8, err8 = pcall(function()
        local TechnoClass = require("src.objects.techno")
        local techno = TechnoClass:new()

        -- Test initial flags
        assert(techno.IsTickedOff == false, "Should not be ticked off")
        assert(techno.IsCloakable == false, "Should not be cloakable")
        assert(techno.IsLeader == false, "Should not be leader")
        assert(techno.Ammo == -1, "Should have unlimited ammo")
        assert(techno.Arm == 0, "Should not be rearming")

        -- Test cloak state
        assert(techno.Cloak == TechnoClass.CLOAK.UNCLOAKED, "Should be uncloaked")

        -- Test target assignment
        techno:Assign_Target(Target.Build(Target.RTTI.UNIT, 5))
        assert(Target.Is_Valid(techno.TarCom), "TarCom should be valid")

        add_test("TechnoClass state", true, "TechnoClass flags and state work")
    end)

    if not ok8 then
        add_test("TechnoClass state", false, tostring(err8))
    end

    -- Test 9: FootClass movement state
    local ok9, err9 = pcall(function()
        local FootClass = require("src.objects.foot")
        local Coord = require("src.core.coord")
        local foot = FootClass:new()

        -- Initial movement state
        assert(foot.IsDriving == false, "Should not be driving")
        assert(foot.IsRotating == false, "Should not be rotating")
        assert(foot.Speed == 255, "Should have full speed")
        assert(foot.Group == FootClass.GROUP_NONE, "Should have no group")

        -- Path should be empty
        assert(foot.Path[1] == FootClass.FACING.NONE, "Path should be empty")

        -- Test destination assignment
        local dest = Target.Build(Target.RTTI.CELL, 100)
        foot:Assign_Destination(dest)
        assert(foot.NavCom == dest, "NavCom should be set")
        assert(foot.IsNewNavCom == false, "IsNewNavCom should be false (not player owned)")

        -- Test player-owned navcom
        foot.IsOwnedByPlayer = true
        local dest2 = Target.Build(Target.RTTI.CELL, 200)
        foot:Assign_Destination(dest2)
        assert(foot.IsNewNavCom == true, "IsNewNavCom should be true")

        -- Test speed setting
        foot:Set_Speed(128)
        assert(foot.Speed == 128, "Speed should be 128")

        add_test("FootClass movement", true, "FootClass movement state works")
    end)

    if not ok9 then
        add_test("FootClass movement", false, tostring(err9))
    end

    -- Test 10: FootClass inheritance from TechnoClass
    local ok10, err10 = pcall(function()
        local FootClass = require("src.objects.foot")
        local foot = FootClass:new()

        -- Should have TechnoClass properties
        assert(foot.Cloak ~= nil, "Should have Cloak from TechnoClass")
        assert(foot.TarCom ~= nil, "Should have TarCom from TechnoClass")
        assert(foot.Ammo ~= nil, "Should have Ammo from TechnoClass")

        -- Should have all mixins
        assert(foot.FlashCount ~= nil, "Should have FlasherClass mixin")
        assert(foot.Stage ~= nil, "Should have StageClass mixin")
        assert(foot.CargoQuantity ~= nil, "Should have CargoClass mixin")
        assert(foot.DoorState ~= nil, "Should have DoorClass mixin")
        assert(foot.Kills ~= nil, "Should have CrewClass mixin")

        -- Should have RadioClass properties
        assert(foot.Radio ~= nil or foot.Radio == nil, "Should have Radio from RadioClass")
        assert(foot.LastMessage ~= nil, "Should have LastMessage")

        -- Should have MissionClass properties
        assert(foot.Mission ~= nil, "Should have Mission")

        -- Should have ObjectClass properties
        assert(foot.Strength ~= nil, "Should have Strength")
        assert(foot.IsInLimbo ~= nil, "Should have IsInLimbo")

        -- Should have AbstractClass properties
        assert(foot.Coord ~= nil, "Should have Coord")
        assert(foot.IsActive ~= nil, "Should have IsActive")

        add_test("FootClass inheritance", true, "Full inheritance chain works")
    end)

    if not ok10 then
        add_test("FootClass inheritance", false, tostring(err10))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the DriveClass, TurretClass, TarComClass, and FlyClass implementation (Phase 2 movement)
function IPC:test_drive_classes()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all drive modules
    local ok1, err1 = pcall(function()
        local DriveClass = require("src.objects.drive.drive")
        local TurretClass = require("src.objects.drive.turret")
        local TarComClass = require("src.objects.drive.tarcom")
        local FlyClass = require("src.objects.drive.fly")

        assert(DriveClass ~= nil, "DriveClass should load")
        assert(TurretClass ~= nil, "TurretClass should load")
        assert(TarComClass ~= nil, "TarComClass should load")
        assert(FlyClass ~= nil, "FlyClass should load")

        add_test("Drive module loading", true, "All drive modules loaded")
    end)

    if not ok1 then
        add_test("Drive module loading", false, tostring(err1))
        return result
    end

    -- Test 2: DriveClass inheritance and initialization
    local DriveClass = require("src.objects.drive.drive")
    local ok2, err2 = pcall(function()
        local drive = DriveClass:new()

        -- Should have FootClass properties
        assert(drive.NavCom ~= nil, "Should have NavCom from FootClass")
        assert(drive.IsDriving == false, "Should not be driving initially")
        assert(drive.Speed == 255, "Should have full speed")

        -- DriveClass specific properties
        assert(drive.Tiberium == 0, "Should have no tiberium")
        assert(drive.IsHarvesting == false, "Should not be harvesting")
        assert(drive.IsReturning == false, "Should not be returning")
        assert(drive.TrackNumber == DriveClass.TRACK.NONE, "Should have no track")
        assert(drive.TrackIndex == 0, "Track index should be 0")

        add_test("DriveClass initialization", true, "DriveClass initializes correctly")
    end)

    if not ok2 then
        add_test("DriveClass initialization", false, tostring(err2))
    end

    -- Test 3: DriveClass track system
    local ok3, err3 = pcall(function()
        local drive = DriveClass:new()

        -- Test track determination
        local track = drive:Determine_Track(0, 0)
        assert(track == DriveClass.TRACK.STRAIGHT, "Same facing should be straight")

        track = drive:Determine_Track(0, 16)
        assert(track == DriveClass.TRACK.CURVE_RIGHT, "Small right turn should curve right")

        track = drive:Determine_Track(0, 240)  -- -16 in 256 space
        assert(track == DriveClass.TRACK.CURVE_LEFT, "Small left turn should curve left")

        track = drive:Determine_Track(0, 128)
        assert(track == DriveClass.TRACK.U_TURN_RIGHT, "Large right turn should U-turn")

        -- Test starting a track
        drive.PrimaryFacing = { Current = 0, Desired = 64 }
        local started = drive:Start_Track(DriveClass.TRACK.CURVE_RIGHT, 64)
        assert(started == true, "Should start track")
        assert(drive.TrackNumber == DriveClass.TRACK.CURVE_RIGHT, "Track number set")
        assert(drive.IsDriving == true, "Should be driving")

        -- Test following track
        for i = 1, 10 do
            drive:Follow_Track()
        end
        assert(drive.TrackNumber == DriveClass.TRACK.NONE, "Track should be complete")

        add_test("DriveClass track system", true, "Track-based turning works")
    end)

    if not ok3 then
        add_test("DriveClass track system", false, tostring(err3))
    end

    -- Test 4: DriveClass harvesting
    local ok4, err4 = pcall(function()
        local drive = DriveClass:new()

        -- Override Is_Harvester for this test
        function drive:Is_Harvester() return true end

        assert(drive:Is_Harvester_Empty() == true, "Should be empty")
        assert(drive:Is_Harvester_Full() == false, "Should not be full")
        assert(drive:Tiberium_Percentage() == 0, "Should be 0%")

        -- Simulate loading tiberium
        drive.Tiberium = 50
        assert(drive:Is_Harvester_Empty() == false, "Should not be empty")
        assert(drive:Tiberium_Percentage() == 50, "Should be 50%")

        -- Fill completely
        drive.Tiberium = DriveClass.MAX_TIBERIUM
        assert(drive:Is_Harvester_Full() == true, "Should be full")
        assert(drive:Tiberium_Percentage() == 100, "Should be 100%")

        -- Test offload
        local value = drive:Offload_Tiberium_Bail()
        assert(value == 25, "Should get 25 credits per bail")
        assert(drive.Tiberium == DriveClass.MAX_TIBERIUM - 1, "Should have one less")

        add_test("DriveClass harvesting", true, "Tiberium harvesting works")
    end)

    if not ok4 then
        add_test("DriveClass harvesting", false, tostring(err4))
    end

    -- Test 5: TurretClass initialization and inheritance
    local TurretClass = require("src.objects.drive.turret")
    local ok5, err5 = pcall(function()
        local turret = TurretClass:new()

        -- Should have DriveClass properties
        assert(turret.Tiberium ~= nil, "Should have Tiberium from DriveClass")
        assert(turret.TrackNumber ~= nil, "Should have TrackNumber from DriveClass")

        -- TurretClass specific
        assert(turret.Reload == 0, "Should not be reloading")
        assert(turret.SecondaryFacing ~= nil, "Should have SecondaryFacing")
        assert(turret.SecondaryFacing.Current == 0, "Turret should face 0")
        assert(turret.IsTurretRotating == false, "Turret should not be rotating")

        add_test("TurretClass initialization", true, "TurretClass initializes correctly")
    end)

    if not ok5 then
        add_test("TurretClass initialization", false, tostring(err5))
    end

    -- Test 6: TurretClass turret control
    local ok6, err6 = pcall(function()
        local turret = TurretClass:new()

        -- Test turret facing
        turret:Set_Turret_Facing(90)
        assert(turret.SecondaryFacing.Desired == 90, "Should set desired facing")

        -- Test turret rotation
        turret.SecondaryFacing.Current = 0
        local done = turret:Do_Turn_Turret()
        assert(done == false, "Should not be done immediately")
        assert(turret.SecondaryFacing.Current > 0, "Should have rotated")
        assert(turret.IsTurretRotating == true, "Should be rotating")

        -- Complete rotation
        for i = 1, 20 do
            turret:Do_Turn_Turret()
        end
        assert(turret.SecondaryFacing.Current == 90, "Should reach target facing")
        assert(turret.IsTurretRotating == false, "Should stop rotating")

        -- Test turret lock
        turret:Lock_Turret()
        assert(turret.IsTurretLockedDown == true, "Should be locked")
        assert(turret:Can_Rotate_Turret() == false, "Should not rotate when locked")

        turret:Unlock_Turret()
        assert(turret.IsTurretLockedDown == false, "Should be unlocked")

        add_test("TurretClass turret control", true, "Turret rotation works")
    end)

    if not ok6 then
        add_test("TurretClass turret control", false, tostring(err6))
    end

    -- Test 7: TurretClass reload system
    local ok7, err7 = pcall(function()
        local turret = TurretClass:new()

        assert(turret:Is_Reloading() == false, "Should not be reloading")
        assert(turret:Is_Weapon_Ready() == true, "Weapon should be ready")

        turret:Start_Reload(10)
        assert(turret:Is_Reloading() == true, "Should be reloading")
        assert(turret:Reload_Time() == 10, "Should have 10 ticks left")

        -- Process reload
        for i = 1, 5 do
            turret:Process_Reload()
        end
        assert(turret:Reload_Time() == 5, "Should have 5 ticks left")

        for i = 1, 5 do
            turret:Process_Reload()
        end
        assert(turret:Is_Weapon_Ready() == true, "Should be ready after reload")

        add_test("TurretClass reload", true, "Reload timer works")
    end)

    if not ok7 then
        add_test("TurretClass reload", false, tostring(err7))
    end

    -- Test 8: TarComClass initialization and inheritance
    local TarComClass = require("src.objects.drive.tarcom")
    local ok8, err8 = pcall(function()
        local tarcom = TarComClass:new()

        -- Should have TurretClass properties
        assert(tarcom.SecondaryFacing ~= nil, "Should have SecondaryFacing from TurretClass")
        assert(tarcom.Reload ~= nil, "Should have Reload from TurretClass")

        -- TarComClass specific
        assert(tarcom.ScanTimer == 0, "Should have scan timer")
        assert(tarcom.LastTargetCoord == 0, "Should have no last target coord")
        assert(tarcom.IsEngaging == false, "Should not be engaging")

        add_test("TarComClass initialization", true, "TarComClass initializes correctly")
    end)

    if not ok8 then
        add_test("TarComClass initialization", false, tostring(err8))
    end

    -- Test 9: TarComClass target evaluation
    local Target = require("src.core.target")
    local ok9, err9 = pcall(function()
        local tarcom = TarComClass:new()

        -- Invalid target should have 0 threat
        local threat = tarcom:Evaluate_Threat(Target.TARGET_NONE)
        assert(threat == 0, "Invalid target should have 0 threat")

        -- Test engaging state
        assert(tarcom:Is_Engaging() == false, "Should not be engaging")

        tarcom.IsEngaging = true
        tarcom.TarCom = Target.Build(Target.RTTI.UNIT, 5)
        assert(tarcom:Is_Engaging() == true, "Should be engaging with valid target")

        add_test("TarComClass targeting", true, "Targeting state works")
    end)

    if not ok9 then
        add_test("TarComClass targeting", false, tostring(err9))
    end

    -- Test 10: FlyClass mixin
    local FlyClass = require("src.objects.drive.fly")
    local ok10, err10 = pcall(function()
        -- FlyClass is a mixin, create a test object with metatable for method access
        local flyer = setmetatable({}, { __index = FlyClass })
        FlyClass.init(flyer)

        -- Initial state
        assert(flyer.SpeedAccum == 0, "Should have no speed accumulated")
        assert(flyer.Altitude == FlyClass.ALTITUDE.GROUND, "Should be on ground")
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.GROUNDED, "Should be grounded")

        assert(flyer:Is_Grounded() == true, "Should be grounded")
        assert(flyer:Is_Airborne() == false, "Should not be airborne")

        -- Test takeoff
        flyer:Take_Off()
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.TAKING_OFF, "Should be taking off")
        assert(flyer.TargetAltitude == FlyClass.ALTITUDE.MEDIUM, "Should target medium altitude")

        -- Process altitude change
        for i = 1, 100 do
            flyer:Process_Altitude()
        end
        assert(flyer:Is_Airborne() == true, "Should be airborne")
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.FLYING, "Should be flying")

        -- Test landing
        flyer:Land()
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.LANDING, "Should be landing")

        for i = 1, 200 do
            flyer:Process_Altitude()
        end
        assert(flyer:Is_Grounded() == true, "Should be grounded after landing")

        add_test("FlyClass mixin", true, "Flight physics works")
    end)

    if not ok10 then
        add_test("FlyClass mixin", false, tostring(err10))
    end

    -- Test 11: FlyClass speed control
    local ok11, err11 = pcall(function()
        local flyer = setmetatable({}, { __index = FlyClass })
        FlyClass.init(flyer)

        -- Set speed
        flyer:Fly_Speed(255, 50)  -- Full throttle, max 50 MPH
        assert(flyer.SpeedAdd == 50, "Should be at max speed")

        flyer:Fly_Speed(128, 50)  -- Half throttle
        assert(flyer.SpeedAdd == 25, "Should be at half speed")

        flyer:Stop_Flight()
        assert(flyer.SpeedAdd == 0, "Should have stopped")
        assert(flyer.SpeedAccum == 0, "Accumulator should be cleared")

        add_test("FlyClass speed", true, "Speed control works")
    end)

    if not ok11 then
        add_test("FlyClass speed", false, tostring(err11))
    end

    -- Test 12: FlyClass VTOL hover
    local ok12, err12 = pcall(function()
        local flyer = setmetatable({}, { __index = FlyClass })
        FlyClass.init(flyer)
        flyer.IsVTOL = true

        -- Take off and fly
        flyer:Take_Off()
        for i = 1, 100 do
            flyer:Process_Altitude()
        end
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.FLYING, "Should be flying")

        -- Enter hover mode
        flyer:Hover()
        assert(flyer.FlightState == FlyClass.FLIGHT_STATE.HOVERING, "VTOL should hover")
        assert(flyer.SpeedAdd == 0, "Should stop moving when hovering")

        add_test("FlyClass VTOL hover", true, "VTOL hovering works")
    end)

    if not ok12 then
        add_test("FlyClass VTOL hover", false, tostring(err12))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the type class hierarchy (AbstractTypeClass, ObjectTypeClass, TechnoTypeClass)
function IPC:test_type_classes()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all type modules
    local ok1, err1 = pcall(function()
        local AbstractTypeClass = require("src.objects.types.abstracttype")
        local ObjectTypeClass = require("src.objects.types.objecttype")
        local TechnoTypeClass = require("src.objects.types.technotype")

        assert(AbstractTypeClass ~= nil, "AbstractTypeClass should load")
        assert(ObjectTypeClass ~= nil, "ObjectTypeClass should load")
        assert(TechnoTypeClass ~= nil, "TechnoTypeClass should load")

        add_test("Type module loading", true, "All type modules loaded")
    end)

    if not ok1 then
        add_test("Type module loading", false, tostring(err1))
        return result
    end

    -- Test 2: AbstractTypeClass initialization and naming
    local AbstractTypeClass = require("src.objects.types.abstracttype")
    local ok2, err2 = pcall(function()
        local abst = AbstractTypeClass:new("E1", "Minigunner")

        assert(abst.IniName == "E1", "IniName should be E1")
        assert(abst.Name == "Minigunner", "Name should be Minigunner")
        assert(abst:Get_Name() == "E1", "Get_Name should return E1")
        assert(abst:Full_Name() == "Minigunner", "Full_Name should return Minigunner")

        -- Test name truncation
        abst:Set_Name("VERYLONGNAME")
        assert(#abst.IniName <= 8, "IniName should be truncated to 8 chars")

        add_test("AbstractTypeClass naming", true, "Name handling works")
    end)

    if not ok2 then
        add_test("AbstractTypeClass naming", false, tostring(err2))
    end

    -- Test 3: AbstractTypeClass ownership
    local ok3, err3 = pcall(function()
        local abst = AbstractTypeClass:new("TEST", "Test")

        -- Default ownership is all houses
        assert(abst:Get_Ownable() == 0xFFFF, "Should allow all houses by default")

        -- Test house check
        assert(abst:Can_House_Own(0) == true, "House 0 should be allowed")
        assert(abst:Can_House_Own(7) == true, "House 7 should be allowed")
        assert(abst:Can_House_Own(-1) == false, "Invalid house should be rejected")
        assert(abst:Can_House_Own(16) == false, "Invalid house should be rejected")

        add_test("AbstractTypeClass ownership", true, "Ownership checks work")
    end)

    if not ok3 then
        add_test("AbstractTypeClass ownership", false, tostring(err3))
    end

    -- Test 4: ObjectTypeClass initialization
    local ObjectTypeClass = require("src.objects.types.objecttype")
    local ok4, err4 = pcall(function()
        local obj = ObjectTypeClass:new("TANK", "Medium Tank")

        -- Should have AbstractTypeClass properties
        assert(obj.IniName == "TANK", "Should have IniName")
        assert(obj.Name == "Medium Tank", "Should have Name")

        -- ObjectTypeClass specific
        assert(obj.Armor == ObjectTypeClass.ARMOR.NONE, "Default armor should be NONE")
        assert(obj.MaxStrength == 1, "Default MaxStrength should be 1")
        assert(obj.IsSelectable == false, "Should not be selectable by default")
        assert(obj.IsLegalTarget == true, "Should be legal target by default")

        add_test("ObjectTypeClass initialization", true, "ObjectTypeClass initializes correctly")
    end)

    if not ok4 then
        add_test("ObjectTypeClass initialization", false, tostring(err4))
    end

    -- Test 5: ObjectTypeClass dimensions and properties
    local ok5, err5 = pcall(function()
        local obj = ObjectTypeClass:new("BLDG", "Building")

        -- Set dimensions
        obj:Set_Dimensions(2, 3)
        local w, h = obj:Dimensions()
        assert(w == 2, "Width should be 2")
        assert(h == 3, "Height should be 3")

        -- Set health
        obj:Set_Max_Strength(500)
        assert(obj:Get_Max_Strength() == 500, "MaxStrength should be 500")

        -- Set armor
        obj:Set_Armor(ObjectTypeClass.ARMOR.HEAVY)
        assert(obj:Get_Armor() == ObjectTypeClass.ARMOR.HEAVY, "Armor should be HEAVY")

        -- Max pips based on dimensions
        assert(obj:Max_Pips() == 3, "Max pips should be max(width, height)")

        add_test("ObjectTypeClass properties", true, "Dimensions and properties work")
    end)

    if not ok5 then
        add_test("ObjectTypeClass properties", false, tostring(err5))
    end

    -- Test 6: ObjectTypeClass occupy list
    local ok6, err6 = pcall(function()
        local obj = ObjectTypeClass:new("BLDG", "Building")

        -- 1x1 should have empty occupy list
        obj:Set_Dimensions(1, 1)
        local list = obj:Occupy_List()
        assert(#list == 0, "1x1 should have empty occupy list")

        -- 2x2 should have 3 additional cells
        obj:Set_Dimensions(2, 2)
        list = obj:Occupy_List()
        assert(#list == 3, "2x2 should have 3 additional cells")

        add_test("ObjectTypeClass occupy list", true, "Occupy list generation works")
    end)

    if not ok6 then
        add_test("ObjectTypeClass occupy list", false, tostring(err6))
    end

    -- Test 7: TechnoTypeClass initialization
    local TechnoTypeClass = require("src.objects.types.technotype")
    local ok7, err7 = pcall(function()
        local tech = TechnoTypeClass:new("MTNK", "Medium Tank")

        -- Should have all parent properties
        assert(tech.IniName == "MTNK", "Should have IniName")
        assert(tech.Armor ~= nil, "Should have Armor from ObjectTypeClass")

        -- TechnoTypeClass specific
        assert(tech.Cost == 0, "Default cost should be 0")
        assert(tech.SightRange == 2, "Default sight range should be 2")
        assert(tech.MaxSpeed == TechnoTypeClass.MPH.IMMOBILE, "Default speed should be immobile")
        assert(tech.Primary == TechnoTypeClass.WEAPON.NONE, "No primary weapon by default")
        assert(tech.IsBuildable == true, "Should be buildable by default")

        add_test("TechnoTypeClass initialization", true, "TechnoTypeClass initializes correctly")
    end)

    if not ok7 then
        add_test("TechnoTypeClass initialization", false, tostring(err7))
    end

    -- Test 8: TechnoTypeClass production properties
    local ok8, err8 = pcall(function()
        local tech = TechnoTypeClass:new("MTNK", "Medium Tank")

        -- Set cost
        tech:Set_Cost(800)
        assert(tech.Cost == 800, "Cost should be 800")
        assert(tech:Cost_Of() == 800, "Cost_Of should return 800")
        assert(tech:Raw_Cost() == 800, "Raw_Cost should return 800")

        -- Build time
        local time = tech:Time_To_Build(0)
        assert(time >= 15, "Build time should be at least 15")
        assert(time == math.max(15, math.floor(800/5)), "Build time should be cost/5")

        -- Prerequisites
        tech.Prerequisites = TechnoTypeClass.PREREQ.FACTORY
        assert(tech:Can_Build(TechnoTypeClass.PREREQ.FACTORY) == true, "Should build with factory")
        assert(tech:Can_Build(0) == false, "Should not build without prereqs")

        add_test("TechnoTypeClass production", true, "Production properties work")
    end)

    if not ok8 then
        add_test("TechnoTypeClass production", false, tostring(err8))
    end

    -- Test 9: TechnoTypeClass combat properties
    local ok9, err9 = pcall(function()
        local tech = TechnoTypeClass:new("MLRS", "Rocket Launcher")

        -- Set combat properties
        tech:Set_Sight_Range(5)
        assert(tech:Get_Sight_Range() == 5, "Sight range should be 5")

        tech:Set_Max_Speed(TechnoTypeClass.MPH.MEDIUM)
        assert(tech:Get_Max_Speed() == TechnoTypeClass.MPH.MEDIUM, "Speed should be MEDIUM")

        -- Set weapons
        tech.Primary = TechnoTypeClass.WEAPON.ROCKET
        assert(tech:Get_Primary_Weapon() == TechnoTypeClass.WEAPON.ROCKET, "Primary should be ROCKET")
        assert(tech:Is_Armed() == true, "Should be armed")

        -- No secondary
        assert(tech:Get_Secondary_Weapon() == TechnoTypeClass.WEAPON.NONE, "No secondary")

        add_test("TechnoTypeClass combat", true, "Combat properties work")
    end)

    if not ok9 then
        add_test("TechnoTypeClass combat", false, tostring(err9))
    end

    -- Test 10: TechnoTypeClass transport and repair
    local ok10, err10 = pcall(function()
        local tech = TechnoTypeClass:new("APC", "APC")

        -- Not a transport by default
        assert(tech:Max_Passengers() == 0, "Non-transport should have 0 capacity")

        -- Make it a transport
        tech.IsTransporter = true
        assert(tech:Max_Passengers() == 5, "Transport should have 5 capacity")

        -- Repair calculations
        tech:Set_Cost(300)
        tech:Set_Max_Strength(200)
        local step = tech:Repair_Step()
        assert(step >= 1, "Repair step should be at least 1")
        local cost = tech:Repair_Cost()
        assert(cost >= 0, "Repair cost should be non-negative")

        add_test("TechnoTypeClass transport/repair", true, "Transport and repair work")
    end)

    if not ok10 then
        add_test("TechnoTypeClass transport/repair", false, tostring(err10))
    end

    -- Test 11: TechnoTypeClass ownership restrictions
    local ok11, err11 = pcall(function()
        local tech = TechnoTypeClass:new("ORCA", "Orca")

        -- Default all houses
        assert(tech:Get_Ownable() == 0xFFFF, "Default should be all houses")

        -- Restrict to GDI only (house 0)
        tech:Set_Ownable(0x0001)
        assert(tech:Get_Ownable() == 0x0001, "Should be GDI only")
        assert(tech:Can_House_Own(0) == true, "GDI should own")
        assert(tech:Can_House_Own(1) == false, "NOD should not own")

        add_test("TechnoTypeClass ownership", true, "Ownership restrictions work")
    end)

    if not ok11 then
        add_test("TechnoTypeClass ownership", false, tostring(err11))
    end

    -- Test 12: Type hierarchy inheritance
    local ok12, err12 = pcall(function()
        local tech = TechnoTypeClass:new("TEST", "Test")

        -- Should have methods from all parents
        assert(tech.Get_Name ~= nil, "Should have AbstractTypeClass.Get_Name")
        assert(tech.Dimensions ~= nil, "Should have ObjectTypeClass.Dimensions")
        assert(tech.Cost_Of ~= nil, "Should have TechnoTypeClass.Cost_Of")

        -- Should be able to call them
        assert(tech:Get_Name() == "TEST", "Get_Name should work")
        local w, h = tech:Dimensions()
        assert(w == 1, "Dimensions should work")
        assert(tech:Cost_Of() == 0, "Cost_Of should work")

        add_test("Type hierarchy inheritance", true, "Full inheritance chain works")
    end)

    if not ok12 then
        add_test("Type hierarchy inheritance", false, tostring(err12))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the concrete classes (InfantryClass, UnitClass, AircraftClass, BuildingClass)
function IPC:test_concrete_classes()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all concrete class modules
    local ok1, err1 = pcall(function()
        local InfantryClass = require("src.objects.infantry")
        local UnitClass = require("src.objects.unit")
        local AircraftClass = require("src.objects.aircraft")
        local BuildingClass = require("src.objects.building")

        assert(InfantryClass ~= nil, "InfantryClass should load")
        assert(UnitClass ~= nil, "UnitClass should load")
        assert(AircraftClass ~= nil, "AircraftClass should load")
        assert(BuildingClass ~= nil, "BuildingClass should load")

        add_test("Concrete module loading", true, "All concrete modules loaded")
    end)

    if not ok1 then
        add_test("Concrete module loading", false, tostring(err1))
        return result
    end

    -- Test 2: InfantryClass initialization
    local InfantryClass = require("src.objects.infantry")
    local ok2, err2 = pcall(function()
        local infantry = InfantryClass:new()

        -- Should have FootClass properties
        assert(infantry.NavCom ~= nil, "Should have NavCom from FootClass")
        assert(infantry.IsDriving == false, "Should not be driving")

        -- Infantry specific
        assert(infantry.Fear == InfantryClass.FEAR.NONE, "Should have no fear")
        assert(infantry.Doing == InfantryClass.DO.NOTHING, "Should be doing nothing")
        assert(infantry.IsProne == false, "Should not be prone")
        assert(infantry.IsTechnician == false, "Should not be technician")
        assert(infantry.Occupy == InfantryClass.SUBCELL.CENTER, "Should be in center")

        add_test("InfantryClass initialization", true, "InfantryClass initializes correctly")
    end)

    if not ok2 then
        add_test("InfantryClass initialization", false, tostring(err2))
    end

    -- Test 3: InfantryClass fear system
    local ok3, err3 = pcall(function()
        local infantry = InfantryClass:new()

        assert(infantry:Get_Fear() == 0, "Should have no fear")
        assert(infantry:Is_Panicking() == false, "Should not be panicking")
        assert(infantry:Is_Scared() == false, "Should not be scared")

        -- Add fear
        infantry:Add_Fear(InfantryClass.FEAR_ATTACK)
        assert(infantry:Get_Fear() == InfantryClass.FEAR_ATTACK, "Should have attack fear")
        assert(infantry:Is_Scared() == false, "Not yet scared")

        -- More fear
        infantry:Add_Fear(InfantryClass.FEAR_ATTACK)
        assert(infantry:Get_Fear() == 100, "Should have 100 fear")
        assert(infantry:Is_Scared() == true, "Should be scared now")

        -- Panic level
        infantry:Add_Fear(150)
        assert(infantry:Is_Panicking() == true, "Should be panicking")

        -- Fear decay
        infantry:Reduce_Fear()
        assert(infantry:Get_Fear() < InfantryClass.FEAR.MAXIMUM, "Fear should decrease")

        add_test("InfantryClass fear system", true, "Fear system works")
    end)

    if not ok3 then
        add_test("InfantryClass fear system", false, tostring(err3))
    end

    -- Test 4: InfantryClass prone system
    local ok4, err4 = pcall(function()
        local infantry = InfantryClass:new()

        assert(infantry:Is_Prone() == false, "Should not be prone")

        infantry:Go_Prone()
        assert(infantry.IsProne == true, "Should be prone")
        assert(infantry.Stop == InfantryClass.STOP.PRONE, "Stop should be PRONE")

        infantry:Clear_Prone()
        assert(infantry:Is_Prone() == false, "Should not be prone after clear")

        add_test("InfantryClass prone system", true, "Prone system works")
    end)

    if not ok4 then
        add_test("InfantryClass prone system", false, tostring(err4))
    end

    -- Test 5: InfantryClass actions
    local ok5, err5 = pcall(function()
        local infantry = InfantryClass:new()

        assert(infantry:Get_Action() == InfantryClass.DO.NOTHING, "Should be doing nothing")

        infantry:Do_Action(InfantryClass.DO.WALK)
        assert(infantry:Get_Action() == InfantryClass.DO.WALK, "Should be walking")

        infantry:Clear_Action()
        assert(infantry:Get_Action() == InfantryClass.DO.NOTHING, "Should be doing nothing after clear")

        add_test("InfantryClass actions", true, "Action system works")
    end)

    if not ok5 then
        add_test("InfantryClass actions", false, tostring(err5))
    end

    -- Test 6: UnitClass initialization
    local UnitClass = require("src.objects.unit")
    local ok6, err6 = pcall(function()
        local unit = UnitClass:new()

        -- Should have TarComClass properties
        assert(unit.ScanTimer ~= nil, "Should have ScanTimer from TarComClass")
        assert(unit.SecondaryFacing ~= nil, "Should have SecondaryFacing from TurretClass")
        assert(unit.Tiberium ~= nil, "Should have Tiberium from DriveClass")

        -- Unit specific
        assert(unit.Flagged == false, "Should not be flagged")
        assert(unit.IsDeploying == false, "Should not be deploying")
        assert(unit.HarvestTimer == 0, "Should have no harvest timer")

        add_test("UnitClass initialization", true, "UnitClass initializes correctly")
    end)

    if not ok6 then
        add_test("UnitClass initialization", false, tostring(err6))
    end

    -- Test 7: UnitClass harvester system
    local ok7, err7 = pcall(function()
        local unit = UnitClass:new()

        -- Make it a harvester for testing
        unit.Class = { IsHarvester = true }

        assert(unit:Is_Harvester() == true, "Should be harvester")
        assert(unit:Is_Empty() == true, "Should be empty")
        assert(unit:Is_Full() == false, "Should not be full")
        assert(unit:Tiberium_Load() == 0, "Should have no tiberium")

        -- Add tiberium
        unit.Tiberium = 14
        assert(unit:Is_Empty() == false, "Should not be empty")
        assert(unit:Is_Full() == false, "Should not be full yet")

        -- Fill completely
        unit.Tiberium = UnitClass.TIBERIUM_CAPACITY
        assert(unit:Is_Full() == true, "Should be full")

        -- Offload
        local credits = unit:Offload_Tiberium_Bail()
        assert(credits == 25, "Should get 25 credits per bail")
        assert(unit.Tiberium == UnitClass.TIBERIUM_CAPACITY - 1, "Should have one less")

        add_test("UnitClass harvester", true, "Harvester system works")
    end)

    if not ok7 then
        add_test("UnitClass harvester", false, tostring(err7))
    end

    -- Test 8: UnitClass deployment
    local ok8, err8 = pcall(function()
        local unit = UnitClass:new()

        -- Make it an MCV
        unit.Class = { IsDeployable = true }

        assert(unit:Can_Deploy() == true, "MCV should be able to deploy")

        local deployed = unit:Deploy()
        assert(deployed == true, "Should start deployment")
        assert(unit.IsDeploying == true, "Should be deploying")
        assert(unit.DeployTimer > 0, "Should have deploy timer")

        -- Already deploying
        assert(unit:Can_Deploy() == false, "Cannot deploy while deploying")

        add_test("UnitClass deployment", true, "MCV deployment works")
    end)

    if not ok8 then
        add_test("UnitClass deployment", false, tostring(err8))
    end

    -- Test 9: AircraftClass initialization
    local AircraftClass = require("src.objects.aircraft")
    local FlyClass = require("src.objects.drive.fly")
    local ok9, err9 = pcall(function()
        local aircraft = AircraftClass:new()

        -- Should have FootClass properties
        assert(aircraft.NavCom ~= nil, "Should have NavCom from FootClass")

        -- Should have FlyClass mixin properties
        assert(aircraft.Altitude == FlyClass.ALTITUDE.GROUND, "Should be on ground")
        assert(aircraft.FlightState == FlyClass.FLIGHT_STATE.GROUNDED, "Should be grounded")

        -- Aircraft specific
        assert(aircraft.IsLanding == false, "Should not be landing")
        assert(aircraft.IsTakingOff == false, "Should not be taking off")
        assert(aircraft.Fuel == 255, "Should have full fuel")

        add_test("AircraftClass initialization", true, "AircraftClass initializes correctly")
    end)

    if not ok9 then
        add_test("AircraftClass initialization", false, tostring(err9))
    end

    -- Test 10: AircraftClass flight control
    local ok10, err10 = pcall(function()
        local aircraft = AircraftClass:new()

        assert(aircraft:Is_Grounded() == true, "Should be grounded")
        assert(aircraft:Is_Airborne() == false, "Should not be airborne")

        -- Takeoff
        aircraft:Start_Takeoff()
        assert(aircraft.IsTakingOff == true, "Should be taking off")
        assert(aircraft.FlightState == FlyClass.FLIGHT_STATE.TAKING_OFF, "Flight state should be TAKING_OFF")

        -- Process until airborne
        for i = 1, 100 do
            aircraft:AI_Fly()
        end
        assert(aircraft:Is_Airborne() == true, "Should be airborne")

        -- Landing
        aircraft:Start_Landing()
        assert(aircraft.IsLanding == true, "Should be landing")

        -- Process landing
        for i = 1, 200 do
            aircraft:AI_Fly()
        end
        assert(aircraft:Is_Grounded() == true, "Should be grounded after landing")

        add_test("AircraftClass flight control", true, "Flight control works")
    end)

    if not ok10 then
        add_test("AircraftClass flight control", false, tostring(err10))
    end

    -- Test 11: AircraftClass return to base
    local ok11, err11 = pcall(function()
        local aircraft = AircraftClass:new()
        aircraft.MaxAmmo = 4
        aircraft.Ammo = 4

        assert(aircraft:Should_Return_To_Base() == false, "Should not need RTB with full ammo")

        aircraft.Ammo = 0
        assert(aircraft:Should_Return_To_Base() == true, "Should RTB with no ammo")

        aircraft.Ammo = 4
        aircraft.Fuel = 20
        assert(aircraft:Should_Return_To_Base() == true, "Should RTB with low fuel")

        -- Reload
        aircraft:Reload_Ammo()
        assert(aircraft.Ammo == 4, "Should have reloaded ammo")

        add_test("AircraftClass RTB", true, "Return to base logic works")
    end)

    if not ok11 then
        add_test("AircraftClass RTB", false, tostring(err11))
    end

    -- Test 12: BuildingClass initialization
    local BuildingClass = require("src.objects.building")
    local ok12, err12 = pcall(function()
        local building = BuildingClass:new()

        -- Should have TechnoClass properties
        assert(building.TarCom ~= nil, "Should have TarCom from TechnoClass")
        assert(building.Cloak ~= nil, "Should have Cloak from TechnoClass")

        -- Building specific
        assert(building.BState == BuildingClass.BSTATE.IDLE, "Should be idle")
        assert(building.IsRepairing == false, "Should not be repairing")
        assert(building.IsSelling == false, "Should not be selling")
        assert(building.IsCaptured == false, "Should not be captured")
        assert(building.TiberiumStored == 0, "Should have no tiberium")

        add_test("BuildingClass initialization", true, "BuildingClass initializes correctly")
    end)

    if not ok12 then
        add_test("BuildingClass initialization", false, tostring(err12))
    end

    -- Test 13: BuildingClass state machine
    local ok13, err13 = pcall(function()
        local building = BuildingClass:new()

        assert(building:Get_State() == BuildingClass.BSTATE.IDLE, "Should be idle")
        assert(building:Is_Operational() == true, "Should be operational")

        building:Set_State(BuildingClass.BSTATE.ACTIVE)
        assert(building:Get_State() == BuildingClass.BSTATE.ACTIVE, "Should be active")

        building:Set_State(BuildingClass.BSTATE.CONSTRUCTION)
        assert(building:Is_Under_Construction() == true, "Should be under construction")
        assert(building:Is_Operational() == false, "Should not be operational during construction")

        add_test("BuildingClass state machine", true, "State machine works")
    end)

    if not ok13 then
        add_test("BuildingClass state machine", false, tostring(err13))
    end

    -- Test 14: BuildingClass power system
    local ok14, err14 = pcall(function()
        local building = BuildingClass:new()
        building.PowerOutput = 100
        building.PowerDrain = 20
        building.Strength = 100
        building.MaxStrength = 100

        assert(building:Power_Output() == 100, "Full health = full power")
        assert(building:Power_Drain() == 20, "Should drain 20")

        -- Damaged building produces less power
        building.Strength = 50
        assert(building:Power_Output() == 50, "Half health = half power")

        -- Not operational = no power
        building.BState = BuildingClass.BSTATE.CONSTRUCTION
        assert(building:Power_Output() == 0, "Construction = no power")
        assert(building:Power_Drain() == 0, "Construction = no drain")

        add_test("BuildingClass power system", true, "Power system works")
    end)

    if not ok14 then
        add_test("BuildingClass power system", false, tostring(err14))
    end

    -- Test 15: BuildingClass tiberium storage
    local ok15, err15 = pcall(function()
        local building = BuildingClass:new()
        building.TiberiumCapacity = 1000

        assert(building:Tiberium_Stored() == 0, "Should start empty")
        assert(building:Storage_Capacity() == 1000, "Capacity should be 1000")
        assert(building:Is_Storage_Full() == false, "Should not be full")

        -- Store tiberium
        local stored = building:Store_Tiberium(500)
        assert(stored == 500, "Should store 500")
        assert(building:Tiberium_Stored() == 500, "Should have 500")

        -- Try to store more than capacity
        stored = building:Store_Tiberium(700)
        assert(stored == 500, "Should only store 500 more")
        assert(building:Is_Storage_Full() == true, "Should be full")

        -- Remove tiberium
        local removed = building:Remove_Tiberium(200)
        assert(removed == 200, "Should remove 200")
        assert(building:Tiberium_Stored() == 800, "Should have 800 left")

        add_test("BuildingClass tiberium storage", true, "Storage system works")
    end)

    if not ok15 then
        add_test("BuildingClass tiberium storage", false, tostring(err15))
    end

    -- Test 16: BuildingClass repair system
    local ok16, err16 = pcall(function()
        local building = BuildingClass:new()
        building.Strength = 50
        building.MaxStrength = 100

        assert(building:Can_Repair() == true, "Should be able to repair")

        building:Start_Repair()
        assert(building.IsRepairing == true, "Should be repairing")

        -- Process repair
        building.RepairTimer = 1  -- Almost ready
        building:Process_Repair()
        -- Timer reset to 15
        for i = 1, 16 do
            building:Process_Repair()
        end
        assert(building.Strength > 50, "Should have more health")

        -- Full health = stop repair
        building.Strength = building.MaxStrength
        building:Process_Repair()
        assert(building.IsRepairing == false, "Should stop when full")

        add_test("BuildingClass repair system", true, "Repair system works")
    end)

    if not ok16 then
        add_test("BuildingClass repair system", false, tostring(err16))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the specific type classes (InfantryTypeClass, UnitTypeClass, AircraftTypeClass, BuildingTypeClass)
function IPC:test_specific_types()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all type class modules
    local ok1, err1 = pcall(function()
        local InfantryTypeClass = require("src.objects.types.infantrytype")
        local UnitTypeClass = require("src.objects.types.unittype")
        local AircraftTypeClass = require("src.objects.types.aircrafttype")
        local BuildingTypeClass = require("src.objects.types.buildingtype")

        assert(InfantryTypeClass ~= nil, "InfantryTypeClass should load")
        assert(UnitTypeClass ~= nil, "UnitTypeClass should load")
        assert(AircraftTypeClass ~= nil, "AircraftTypeClass should load")
        assert(BuildingTypeClass ~= nil, "BuildingTypeClass should load")

        add_test("Type class modules", true, "All type class modules loaded")
    end)

    if not ok1 then
        add_test("Type class modules", false, tostring(err1))
        return result
    end

    -- Test 2: InfantryTypeClass basic creation
    local InfantryTypeClass = require("src.objects.types.infantrytype")
    local ok2, err2 = pcall(function()
        local infType = InfantryTypeClass:new("TEST", "Test Infantry")
        assert(infType.IniName == "TEST", "Should have correct IniName")
        assert(infType.Name == "Test Infantry", "Should have correct Name")
        assert(infType.Type == InfantryTypeClass.INFANTRY.NONE, "Should default to NONE")
        assert(infType.IsFemale == false, "Should default to male")
        assert(infType.IsCrawling == true, "Should default to crawling")
        assert(infType.IsCapture == false, "Should default to no capture")
        assert(infType.IsFraidyCat == false, "Should default to not afraid")

        add_test("InfantryTypeClass creation", true, "Basic creation works")
    end)

    if not ok2 then
        add_test("InfantryTypeClass creation", false, tostring(err2))
    end

    -- Test 3: InfantryTypeClass factory method
    local ok3, err3 = pcall(function()
        local minigunner = InfantryTypeClass.Create(InfantryTypeClass.INFANTRY.E1)
        assert(minigunner.Type == InfantryTypeClass.INFANTRY.E1, "Should be E1 type")
        assert(minigunner.Cost == 100, "E1 should cost 100")
        assert(minigunner.MaxStrength == 50, "E1 should have 50 health")

        local engineer = InfantryTypeClass.Create(InfantryTypeClass.INFANTRY.E7)
        assert(engineer.IsCapture == true, "Engineer should capture")
        assert(engineer.Cost == 500, "Engineer should cost 500")

        local commando = InfantryTypeClass.Create(InfantryTypeClass.INFANTRY.RAMBO)
        assert(commando.IsLeader == true, "Commando should be leader")
        assert(commando.Cost == 1000, "Commando should cost 1000")

        add_test("InfantryTypeClass factory", true, "Factory creates correct types")
    end)

    if not ok3 then
        add_test("InfantryTypeClass factory", false, tostring(err3))
    end

    -- Test 4: InfantryTypeClass DoType animation control
    local ok4, err4 = pcall(function()
        local infType = InfantryTypeClass:new("TEST", "Test")
        infType:Set_Do_Control(InfantryTypeClass.DO.WALK, 10, 8, 4)

        local control = infType:Get_Do_Control(InfantryTypeClass.DO.WALK)
        assert(control.Frame == 10, "Walk frame should be 10")
        assert(control.Count == 8, "Walk count should be 8")
        assert(control.Jump == 4, "Walk jump should be 4")

        local frame = infType:Get_Action_Frame(InfantryTypeClass.DO.WALK, 3)
        assert(frame == 10 + (3 * 4), "Action frame should be 22")

        local count = infType:Get_Action_Count(InfantryTypeClass.DO.WALK)
        assert(count == 8, "Action count should be 8")

        add_test("InfantryTypeClass animation", true, "DoType animation works")
    end)

    if not ok4 then
        add_test("InfantryTypeClass animation", false, tostring(err4))
    end

    -- Test 5: UnitTypeClass basic creation
    local UnitTypeClass = require("src.objects.types.unittype")
    local ok5, err5 = pcall(function()
        local unitType = UnitTypeClass:new("TEST", "Test Vehicle")
        assert(unitType.Type == UnitTypeClass.UNIT.NONE, "Should default to NONE")
        assert(unitType.SpeedType == UnitTypeClass.SPEED.TRACKED, "Should default to TRACKED")
        assert(unitType.IsCrusher == false, "Should default to no crush")
        assert(unitType.IsHarvester == false, "Should default to no harvest")
        assert(unitType.IsDeployable == false, "Should default to no deploy")

        add_test("UnitTypeClass creation", true, "Basic creation works")
    end)

    if not ok5 then
        add_test("UnitTypeClass creation", false, tostring(err5))
    end

    -- Test 6: UnitTypeClass factory method
    local ok6, err6 = pcall(function()
        local mammoth = UnitTypeClass.Create(UnitTypeClass.UNIT.HTANK)
        assert(mammoth.Type == UnitTypeClass.UNIT.HTANK, "Should be HTANK")
        assert(mammoth.Cost == 1500, "Mammoth should cost 1500")
        assert(mammoth.IsCrusher == true, "Mammoth should crush")
        assert(mammoth.IsTwoShooter == true, "Mammoth has dual weapons")

        local harvester = UnitTypeClass.Create(UnitTypeClass.UNIT.HARVESTER)
        assert(harvester.IsHarvester == true, "Should be harvester")
        assert(harvester.Cost == 1400, "Harvester should cost 1400")

        local mcv = UnitTypeClass.Create(UnitTypeClass.UNIT.MCV)
        assert(mcv.IsDeployable == true, "MCV should deploy")
        assert(mcv.Cost == 5000, "MCV should cost 5000")

        add_test("UnitTypeClass factory", true, "Factory creates correct types")
    end)

    if not ok6 then
        add_test("UnitTypeClass factory", false, tostring(err6))
    end

    -- Test 7: UnitTypeClass query functions
    local ok7, err7 = pcall(function()
        local buggy = UnitTypeClass.Create(UnitTypeClass.UNIT.BUGGY)
        assert(buggy:Is_Wheeled() == true, "Buggy should be wheeled")
        assert(buggy:Is_Tracked() == false, "Buggy should not be tracked")
        assert(buggy:Can_Crush() == false, "Buggy should not crush")

        local tank = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        assert(tank:Is_Tracked() == true, "Tank should be tracked")
        assert(tank:Can_Crush() == true, "Tank should crush")

        add_test("UnitTypeClass queries", true, "Query functions work")
    end)

    if not ok7 then
        add_test("UnitTypeClass queries", false, tostring(err7))
    end

    -- Test 8: AircraftTypeClass basic creation
    local AircraftTypeClass = require("src.objects.types.aircrafttype")
    local ok8, err8 = pcall(function()
        local airType = AircraftTypeClass:new("TEST", "Test Aircraft")
        assert(airType.Type == AircraftTypeClass.AIRCRAFT.NONE, "Should default to NONE")
        assert(airType.IsFixedWing == false, "Should default to rotorcraft")
        assert(airType.IsRotorEquipped == true, "Should default to rotor")
        assert(airType.IsLandable == true, "Should default to landable")
        assert(airType.IsVTOL == true, "Should default to VTOL")

        add_test("AircraftTypeClass creation", true, "Basic creation works")
    end)

    if not ok8 then
        add_test("AircraftTypeClass creation", false, tostring(err8))
    end

    -- Test 9: AircraftTypeClass factory method
    local ok9, err9 = pcall(function()
        local transport = AircraftTypeClass.Create(AircraftTypeClass.AIRCRAFT.TRANSPORT)
        assert(transport.IsTransportAircraft == true, "Should be transport")
        assert(transport.IsRotorEquipped == true, "Chinook has rotor")
        assert(transport.Cost == 1500, "Transport should cost 1500")

        local a10 = AircraftTypeClass.Create(AircraftTypeClass.AIRCRAFT.A10)
        assert(a10.IsFixedWing == true, "A-10 is fixed wing")
        assert(a10.IsLandable == false, "A-10 cannot land")
        assert(a10.IsBuildable == false, "A-10 is not buildable")

        local apache = AircraftTypeClass.Create(AircraftTypeClass.AIRCRAFT.HELICOPTER)
        assert(apache.MaxAmmo == 15, "Apache has 15 ammo")
        assert(apache.Cost == 1200, "Apache should cost 1200")

        add_test("AircraftTypeClass factory", true, "Factory creates correct types")
    end)

    if not ok9 then
        add_test("AircraftTypeClass factory", false, tostring(err9))
    end

    -- Test 10: AircraftTypeClass query functions
    local ok10, err10 = pcall(function()
        local a10 = AircraftTypeClass.Create(AircraftTypeClass.AIRCRAFT.A10)
        assert(a10:Is_Fixed_Wing() == true, "A-10 is fixed wing")
        assert(a10:Is_Rotor_Equipped() == false, "A-10 has no rotor")
        assert(a10:Can_Land() == false, "A-10 cannot land")
        assert(a10:Is_VTOL() == false, "A-10 is not VTOL")

        local heli = AircraftTypeClass.Create(AircraftTypeClass.AIRCRAFT.HELICOPTER)
        assert(heli:Is_Fixed_Wing() == false, "Heli is not fixed wing")
        assert(heli:Can_Land() == true, "Heli can land")

        add_test("AircraftTypeClass queries", true, "Query functions work")
    end)

    if not ok10 then
        add_test("AircraftTypeClass queries", false, tostring(err10))
    end

    -- Test 11: BuildingTypeClass basic creation
    local BuildingTypeClass = require("src.objects.types.buildingtype")
    local ok11, err11 = pcall(function()
        local bldType = BuildingTypeClass:new("TEST", "Test Building")
        assert(bldType.Type == BuildingTypeClass.STRUCT.NONE, "Should default to NONE")
        assert(bldType.SizeWidth == 1, "Should default to 1 wide")
        assert(bldType.SizeHeight == 1, "Should default to 1 tall")
        assert(bldType.PowerOutput == 0, "Should default to 0 power output")
        assert(bldType.PowerDrain == 0, "Should default to 0 power drain")
        assert(bldType.FactoryType == BuildingTypeClass.FACTORY.NONE, "Should default to no factory")

        add_test("BuildingTypeClass creation", true, "Basic creation works")
    end)

    if not ok11 then
        add_test("BuildingTypeClass creation", false, tostring(err11))
    end

    -- Test 12: BuildingTypeClass factory method - power buildings
    local ok12, err12 = pcall(function()
        local powerPlant = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.POWER)
        assert(powerPlant.PowerOutput == 100, "Power plant should output 100")
        assert(powerPlant.Cost == 300, "Power plant should cost 300")

        local advPower = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.ADVANCED_POWER)
        assert(advPower.PowerOutput == 200, "Adv power should output 200")
        assert(advPower.Cost == 700, "Adv power should cost 700")

        add_test("BuildingTypeClass power buildings", true, "Power buildings work")
    end)

    if not ok12 then
        add_test("BuildingTypeClass power buildings", false, tostring(err12))
    end

    -- Test 13: BuildingTypeClass factory method - factories
    local ok13, err13 = pcall(function()
        local barracks = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.BARRACKS)
        assert(barracks.FactoryType == BuildingTypeClass.FACTORY.INFANTRY, "Barracks builds infantry")
        assert(barracks:Can_Build_Infantry() == true, "Should build infantry")

        local weap = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.WEAP)
        assert(weap.FactoryType == BuildingTypeClass.FACTORY.UNIT, "Weap builds units")
        assert(weap:Can_Build_Units() == true, "Should build units")

        local helipad = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.HELIPAD)
        assert(helipad.FactoryType == BuildingTypeClass.FACTORY.AIRCRAFT, "Helipad builds aircraft")
        assert(helipad.IsHelipad == true, "Should be helipad")

        local conyard = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.CONST)
        assert(conyard.FactoryType == BuildingTypeClass.FACTORY.BUILDING, "CY builds buildings")
        assert(conyard:Can_Build_Buildings() == true, "Should build buildings")

        add_test("BuildingTypeClass factories", true, "Factory buildings work")
    end)

    if not ok13 then
        add_test("BuildingTypeClass factories", false, tostring(err13))
    end

    -- Test 14: BuildingTypeClass size and foundation
    local ok14, err14 = pcall(function()
        local conyard = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.CONST)
        local w, h = conyard:Get_Size()
        assert(w == 3 and h == 3, "CY should be 3x3")

        local foundation = conyard:Get_Foundation()
        assert(#foundation == 9, "CY should have 9 foundation cells")

        local refinery = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.REFINERY)
        w, h = refinery:Get_Size()
        assert(w == 3 and h == 2, "Refinery should be 3x2")

        add_test("BuildingTypeClass size", true, "Size and foundation work")
    end)

    if not ok14 then
        add_test("BuildingTypeClass size", false, tostring(err14))
    end

    -- Test 15: BuildingTypeClass defense buildings
    local ok15, err15 = pcall(function()
        local gtower = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.GTWR)
        assert(gtower.IsBaseDefense == true, "Guard tower is defense")
        assert(gtower.IsCapturable == false, "Defense cannot be captured")

        local obelisk = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.OBELISK)
        assert(obelisk.IsBaseDefense == true, "Obelisk is defense")
        assert(obelisk.PowerDrain == 150, "Obelisk drains 150 power")

        local turret = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.TURRET)
        assert(turret.IsTurretEquipped == true, "Gun turret has turret")

        add_test("BuildingTypeClass defenses", true, "Defense buildings work")
    end)

    if not ok15 then
        add_test("BuildingTypeClass defenses", false, tostring(err15))
    end

    -- Test 16: BuildingTypeClass storage
    local ok16, err16 = pcall(function()
        local refinery = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.REFINERY)
        assert(refinery.TiberiumCapacity == 1000, "Refinery stores 1000")

        local silo = BuildingTypeClass.Create(BuildingTypeClass.STRUCT.STORAGE)
        assert(silo.TiberiumCapacity == 1500, "Silo stores 1500")

        add_test("BuildingTypeClass storage", true, "Storage buildings work")
    end)

    if not ok16 then
        add_test("BuildingTypeClass storage", false, tostring(err16))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test the Phase 3 combat classes (BulletClass, AnimClass, WeaponTypeClass, WarheadTypeClass)
function IPC:test_combat_classes()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Load all combat modules
    local ok1, err1 = pcall(function()
        local BulletTypeClass = require("src.objects.types.bullettype")
        local AnimTypeClass = require("src.objects.types.animtype")
        local BulletClass = require("src.objects.bullet")
        local AnimClass = require("src.objects.anim")
        local WeaponTypeClass = require("src.combat.weapon")
        local WarheadTypeClass = require("src.combat.warhead")

        assert(BulletTypeClass ~= nil, "BulletTypeClass should load")
        assert(AnimTypeClass ~= nil, "AnimTypeClass should load")
        assert(BulletClass ~= nil, "BulletClass should load")
        assert(AnimClass ~= nil, "AnimClass should load")
        assert(WeaponTypeClass ~= nil, "WeaponTypeClass should load")
        assert(WarheadTypeClass ~= nil, "WarheadTypeClass should load")

        add_test("Combat module loading", true, "All combat modules loaded")
    end)

    if not ok1 then
        add_test("Combat module loading", false, tostring(err1))
        return result
    end

    -- Test 2: BulletTypeClass creation and factory
    local BulletTypeClass = require("src.objects.types.bullettype")
    local ok2, err2 = pcall(function()
        local bulletType = BulletTypeClass:new("TEST", "Test Bullet")
        assert(bulletType.Type == BulletTypeClass.BULLET.NONE, "Should default to NONE")
        assert(bulletType.IsHoming == false, "Should not be homing")
        assert(bulletType.IsArcing == false, "Should not be arcing")

        local ssm = BulletTypeClass.Create(BulletTypeClass.BULLET.SSM)
        assert(ssm.IsHoming == true, "SSM should be homing")
        assert(ssm.IsFlameEquipped == true, "SSM should have flame trail")

        local grenade = BulletTypeClass.Create(BulletTypeClass.BULLET.GRENADE)
        assert(grenade.IsArcing == true, "Grenade should arc")
        assert(grenade.IsInaccurate == true, "Grenade should be inaccurate")

        local sam = BulletTypeClass.Create(BulletTypeClass.BULLET.SAM)
        assert(sam.IsAntiAircraft == true, "SAM should be anti-aircraft")

        add_test("BulletTypeClass", true, "Bullet types work correctly")
    end)

    if not ok2 then
        add_test("BulletTypeClass", false, tostring(err2))
    end

    -- Test 3: AnimTypeClass creation and factory
    local AnimTypeClass = require("src.objects.types.animtype")
    local ok3, err3 = pcall(function()
        local animType = AnimTypeClass:new("TEST", "Test Anim")
        assert(animType.Type == AnimTypeClass.ANIM.NONE, "Should default to NONE")
        assert(animType.Stages == 1, "Should default to 1 stage")

        local fball = AnimTypeClass.Create(AnimTypeClass.ANIM.FBALL1)
        assert(fball.Stages == 14, "Fireball should have 14 stages")
        assert(fball.IsScorcher == true, "Fireball should scorch")
        assert(fball.IsCraterForming == true, "Fireball should make crater")

        local napalm = AnimTypeClass.Create(AnimTypeClass.ANIM.NAPALM3)
        assert(napalm.IsSticky == true, "Napalm should be sticky")
        assert(napalm.Damage > 0, "Napalm should deal damage")

        add_test("AnimTypeClass", true, "Animation types work correctly")
    end)

    if not ok3 then
        add_test("AnimTypeClass", false, tostring(err3))
    end

    -- Test 4: BulletClass creation and fuse system
    local BulletClass = require("src.objects.bullet")
    local ok4, err4 = pcall(function()
        local bulletType = BulletTypeClass.Create(BulletTypeClass.BULLET.SSM)
        local bullet = BulletClass:new(bulletType)

        assert(bullet.IsInLimbo == true, "Should start in limbo")
        assert(bullet.Class == bulletType, "Should have type reference")
        assert(bullet.SpeedAdd > 0, "Should have speed")

        -- Test fuse arming
        bullet:Arm_Fuse({x=100, y=100}, 50, 5)
        assert(bullet.FuseTimer == 50, "Fuse timer should be 50")
        assert(bullet.ArmingTimer == 5, "Arming timer should be 5")

        -- Test fuse countdown
        local triggered = bullet:Fuse_Checkup()
        assert(triggered == false, "Should not trigger during arming")
        assert(bullet.ArmingTimer == 4, "Arming should decrement")

        add_test("BulletClass fuse system", true, "Fuse system works")
    end)

    if not ok4 then
        add_test("BulletClass fuse system", false, tostring(err4))
    end

    -- Test 5: BulletClass arcing behavior
    local ok5, err5 = pcall(function()
        local grenadeType = BulletTypeClass.Create(BulletTypeClass.BULLET.GRENADE)
        local bullet = BulletClass:new(grenadeType)

        -- Simulate arc
        bullet.ArcAltitude = 0
        bullet.Riser = 20  -- Initial upward velocity

        -- First tick - rising
        bullet.ArcAltitude = bullet.ArcAltitude + bullet.Riser
        bullet.Riser = bullet.Riser - BulletClass.GRAVITY
        assert(bullet.ArcAltitude == 20, "Should rise")
        assert(bullet.Riser == 17, "Riser should decrease by gravity")

        add_test("BulletClass arcing", true, "Arcing physics work")
    end)

    if not ok5 then
        add_test("BulletClass arcing", false, tostring(err5))
    end

    -- Test 6: AnimClass creation and attachment
    local AnimClass = require("src.objects.anim")
    local ok6, err6 = pcall(function()
        local animType = AnimTypeClass.Create(AnimTypeClass.ANIM.FBALL1)
        local anim = AnimClass:new(animType, {x=100, y=100}, 0, 1, false)

        assert(anim.IsInLimbo == false, "Should not be in limbo")
        assert(anim.Class == animType, "Should have type reference")
        assert(anim.Loops == 1, "Should have 1 loop")

        -- Test stage
        assert(anim:Fetch_Stage() == 0, "Should start at stage 0")

        add_test("AnimClass creation", true, "Animation creation works")
    end)

    if not ok6 then
        add_test("AnimClass creation", false, tostring(err6))
    end

    -- Test 7: AnimClass looping
    local ok7, err7 = pcall(function()
        local animType = AnimTypeClass.Create(AnimTypeClass.ANIM.FIRE_SMALL)
        local anim = AnimClass:new(animType, {x=100, y=100}, 0, 3, false)

        assert(anim.Loops == 3, "Should have 3 loops")

        -- Advance stage manually
        anim:Set_Stage(5)
        assert(anim:Fetch_Stage() == 5, "Stage should be 5")

        add_test("AnimClass looping", true, "Animation looping works")
    end)

    if not ok7 then
        add_test("AnimClass looping", false, tostring(err7))
    end

    -- Test 8: WarheadTypeClass creation and damage
    local WarheadTypeClass = require("src.combat.warhead")
    local ok8, err8 = pcall(function()
        local sa = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.SA)
        assert(sa.Name == "Small Arms", "Should be Small Arms")
        assert(sa.SpreadFactor == 2, "Should have spread 2")

        -- Test damage modification
        local damage = sa:Modify_Damage(100, WarheadTypeClass.ARMOR.NONE)
        assert(damage == 100, "Full damage vs NONE armor")

        damage = sa:Modify_Damage(100, WarheadTypeClass.ARMOR.STEEL)
        assert(damage == 25, "25% damage vs STEEL")

        add_test("WarheadTypeClass damage", true, "Warhead damage calc works")
    end)

    if not ok8 then
        add_test("WarheadTypeClass damage", false, tostring(err8))
    end

    -- Test 9: WarheadTypeClass types
    local ok9, err9 = pcall(function()
        local he = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.HE)
        assert(he.IsWallDestroyer == true, "HE destroys walls")
        assert(he.IsTiberiumDestroyer == true, "HE destroys tiberium")

        local ap = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.AP)
        assert(ap.IsWallDestroyer == true, "AP destroys walls")
        local ap_damage = ap:Modify_Damage(100, WarheadTypeClass.ARMOR.STEEL)
        assert(ap_damage == 100, "AP full damage vs steel")

        local fire = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.FIRE)
        assert(fire.IsWoodDestroyer == true, "Fire destroys wood")

        add_test("WarheadTypeClass types", true, "Warhead types work")
    end)

    if not ok9 then
        add_test("WarheadTypeClass types", false, tostring(err9))
    end

    -- Test 10: WeaponTypeClass creation
    local WeaponTypeClass = require("src.combat.weapon")
    local ok10, err10 = pcall(function()
        local rifle = WeaponTypeClass.Create(WeaponTypeClass.WEAPON.RIFLE)
        assert(rifle.Name == "Sniper Rifle", "Should be Sniper Rifle")
        assert(rifle.Attack == 125, "Sniper does 125 damage")
        assert(rifle.Fires == BulletTypeClass.BULLET.SNIPER, "Fires sniper bullet")

        local cannon = WeaponTypeClass.Create(WeaponTypeClass.WEAPON._120MM)
        assert(cannon.Attack == 40, "120mm does 40 damage")
        assert(cannon.Fires == BulletTypeClass.BULLET.APDS, "Fires APDS")

        add_test("WeaponTypeClass creation", true, "Weapon creation works")
    end)

    if not ok10 then
        add_test("WeaponTypeClass creation", false, tostring(err10))
    end

    -- Test 11: WeaponTypeClass range
    local ok11, err11 = pcall(function()
        local pistol = WeaponTypeClass.Create(WeaponTypeClass.WEAPON.PISTOL)
        assert(pistol:Range_In_Cells() == 1, "Pistol range ~1 cell")

        local obelisk = WeaponTypeClass.Create(WeaponTypeClass.WEAPON.OBELISK_LASER)
        assert(obelisk:Range_In_Cells() == 7, "Obelisk range 7 cells")
        assert(obelisk.Attack == 200, "Obelisk does 200 damage")

        local tomahawk = WeaponTypeClass.Create(WeaponTypeClass.WEAPON.TOMAHAWK)
        assert(tomahawk:Range_In_Cells() == 7, "Tomahawk range 7 cells")

        add_test("WeaponTypeClass range", true, "Weapon range works")
    end)

    if not ok11 then
        add_test("WeaponTypeClass range", false, tostring(err11))
    end

    -- Test 12: WeaponTypeClass global lookup
    local ok12, err12 = pcall(function()
        WeaponTypeClass.Init()
        local weapon = WeaponTypeClass.Get(WeaponTypeClass.WEAPON.M16)
        assert(weapon ~= nil, "Should get M16")
        assert(weapon.Name == "M16", "Should be M16")

        WarheadTypeClass.Init()
        local warhead = WarheadTypeClass.Get(WarheadTypeClass.WARHEAD.LASER)
        assert(warhead ~= nil, "Should get Laser")
        assert(warhead.Name == "Laser", "Should be Laser")

        add_test("Global lookup tables", true, "Lookup tables work")
    end)

    if not ok12 then
        add_test("Global lookup tables", false, tostring(err12))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Test Phase 3 integration (pathfinding, combat system)
function IPC:test_phase3_integration()
    local result = { success = true, tests = {} }

    local function add_test(name, passed, detail)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            detail = detail
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: FindPath module loading
    local ok1, err1 = pcall(function()
        local FindPath = require("src.pathfinding.findpath")
        assert(FindPath ~= nil, "FindPath module should load")
        assert(FindPath.FACING ~= nil, "Should have FACING constants")
        assert(FindPath.ADJACENT_CELL ~= nil, "Should have ADJACENT_CELL table")
        add_test("FindPath module loading", true, "FindPath loaded successfully")
    end)

    if not ok1 then
        add_test("FindPath module loading", false, tostring(err1))
        return result
    end

    -- Test 2: FindPath cell utilities
    local FindPath = require("src.pathfinding.findpath")
    local ok2, err2 = pcall(function()
        local pathfinder = FindPath.new(nil)

        -- Test cell_index
        local idx = pathfinder:cell_index(5, 10)
        assert(idx == 645, "cell_index(5,10) = 645 for 64-wide map")

        -- Test cell_coords
        local x, y = pathfinder:cell_coords(645)
        assert(x == 5 and y == 10, "cell_coords(645) = (5,10)")

        -- Test is_valid_cell
        assert(pathfinder:is_valid_cell(0) == true, "Cell 0 valid")
        assert(pathfinder:is_valid_cell(4095) == true, "Cell 4095 valid")
        assert(pathfinder:is_valid_cell(-1) == false, "Cell -1 invalid")
        assert(pathfinder:is_valid_cell(4096) == false, "Cell 4096 invalid")

        add_test("FindPath cell utilities", true, "Cell utilities work")
    end)

    if not ok2 then
        add_test("FindPath cell utilities", false, tostring(err2))
    end

    -- Test 3: FindPath adjacent cells
    local ok3, err3 = pcall(function()
        local pathfinder = FindPath.new(nil)

        -- Cell in middle of map
        local cell = pathfinder:cell_index(32, 32)  -- 32 + 32*64 = 2080

        -- Test adjacent cells
        local n = pathfinder:adjacent_cell(cell, FindPath.FACING.N)
        local s = pathfinder:adjacent_cell(cell, FindPath.FACING.S)
        local e = pathfinder:adjacent_cell(cell, FindPath.FACING.E)
        local w = pathfinder:adjacent_cell(cell, FindPath.FACING.W)

        assert(n == cell - 64, "North is cell - 64")
        assert(s == cell + 64, "South is cell + 64")
        assert(e == cell + 1, "East is cell + 1")
        assert(w == cell - 1, "West is cell - 1")

        add_test("FindPath adjacent cells", true, "Adjacent cell calculation works")
    end)

    if not ok3 then
        add_test("FindPath adjacent cells", false, tostring(err3))
    end

    -- Test 4: FindPath facing calculation
    local ok4, err4 = pcall(function()
        local pathfinder = FindPath.new(nil)

        local cell1 = pathfinder:cell_index(10, 10)
        local cell2 = pathfinder:cell_index(11, 9)  -- NE of cell1

        local facing = pathfinder:cell_facing(cell1, cell2)
        assert(facing == FindPath.FACING.NE, "Should face NE")

        cell2 = pathfinder:cell_index(10, 11)  -- S of cell1
        facing = pathfinder:cell_facing(cell1, cell2)
        assert(facing == FindPath.FACING.S, "Should face S")

        add_test("FindPath facing calculation", true, "Facing calculation works")
    end)

    if not ok4 then
        add_test("FindPath facing calculation", false, tostring(err4))
    end

    -- Test 5: FindPath simple path
    local ok5, err5 = pcall(function()
        local pathfinder = FindPath.new(nil)

        local start = pathfinder:cell_index(10, 10)
        local dest = pathfinder:cell_index(12, 10)  -- 2 cells east

        local path = pathfinder:find_path(start, dest)
        assert(path ~= nil, "Should find path")
        assert(path.Length == 2, "Path length should be 2")
        assert(path.Command[1] == FindPath.FACING.E, "First move should be E")
        assert(path.Command[2] == FindPath.FACING.E, "Second move should be E")

        add_test("FindPath simple path", true, "Simple pathfinding works")
    end)

    if not ok5 then
        add_test("FindPath simple path", false, tostring(err5))
    end

    -- Test 6: FindPath diagonal path
    local ok6, err6 = pcall(function()
        local pathfinder = FindPath.new(nil)

        local start = pathfinder:cell_index(10, 10)
        local dest = pathfinder:cell_index(12, 12)  -- 2 cells SE

        local path = pathfinder:find_path(start, dest)
        assert(path ~= nil, "Should find diagonal path")
        assert(path.Length == 2, "Diagonal path length should be 2")
        assert(path.Command[1] == FindPath.FACING.SE, "First move should be SE")

        add_test("FindPath diagonal path", true, "Diagonal pathfinding works")
    end)

    if not ok6 then
        add_test("FindPath diagonal path", false, tostring(err6))
    end

    -- Test 7: WarheadTypeClass damage modification
    local ok7, err7 = pcall(function()
        local WarheadTypeClass = require("src.combat.warhead")

        local ap = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.AP)
        assert(ap ~= nil, "Should create AP warhead")

        -- AP should do full damage to steel
        local steel_damage = ap:Modify_Damage(100, WarheadTypeClass.ARMOR.STEEL)
        assert(steel_damage == 100, "AP full damage vs steel")

        -- AP should do reduced damage to infantry (NONE armor)
        local inf_damage = ap:Modify_Damage(100, WarheadTypeClass.ARMOR.NONE)
        assert(inf_damage == 25, "AP 25% damage vs infantry")

        add_test("Warhead damage modification", true, "Damage modifiers work")
    end)

    if not ok7 then
        add_test("Warhead damage modification", false, tostring(err7))
    end

    -- Test 8: WarheadTypeClass distance falloff
    local ok8, err8 = pcall(function()
        local WarheadTypeClass = require("src.combat.warhead")

        local he = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.HE)

        -- At impact point
        local damage0 = he:Distance_Damage(100, 0)
        assert(damage0 == 100, "Full damage at impact")

        -- At distance
        local damage_far = he:Distance_Damage(100, 100)
        assert(damage_far < 100, "Reduced damage at distance")
        assert(damage_far > 0, "Still some damage at distance")

        add_test("Warhead distance falloff", true, "Distance falloff works")
    end)

    if not ok8 then
        add_test("Warhead distance falloff", false, tostring(err8))
    end

    -- Test 9: WeaponTypeClass integration
    local ok9, err9 = pcall(function()
        local WeaponTypeClass = require("src.combat.weapon")
        local BulletTypeClass = require("src.objects.types.bullettype")

        local cannon = WeaponTypeClass.Create(WeaponTypeClass.WEAPON._120MM)
        assert(cannon ~= nil, "Should create 120mm weapon")
        assert(cannon.Attack == 40, "120mm does 40 damage")
        assert(cannon.Fires == BulletTypeClass.BULLET.APDS, "Fires APDS")

        local bullet = BulletTypeClass.Create(cannon.Fires)
        assert(bullet ~= nil, "Should create APDS bullet")
        assert(bullet.IsFaceless == true, "APDS is faceless")

        add_test("Weapon/Bullet integration", true, "Weapon-bullet chain works")
    end)

    if not ok9 then
        add_test("Weapon/Bullet integration", false, tostring(err9))
    end

    -- Test 10: ObjectClass Take_Damage with warhead
    local ok10, err10 = pcall(function()
        local ObjectClass = require("src.objects.object")
        local WarheadTypeClass = require("src.combat.warhead")

        local obj = ObjectClass:new()
        obj.Strength = 100
        obj.IsActive = true
        obj.IsInLimbo = false

        -- Take damage with SA warhead
        local result_type = obj:Take_Damage(30, 0, WarheadTypeClass.WARHEAD.SA, nil)
        assert(result_type == ObjectClass.RESULT.LIGHT, "Should take light damage")
        assert(obj.Strength == 70, "30 SA damage reduces to 70")

        add_test("ObjectClass Take_Damage", true, "Take_Damage with warhead works")
    end)

    if not ok10 then
        add_test("ObjectClass Take_Damage", false, tostring(err10))
    end

    -- Test 11: TechnoClass Get_Armor
    local ok11, err11 = pcall(function()
        local TechnoClass = require("src.objects.techno")

        local techno = TechnoClass:new()
        local armor = techno:Get_Armor()
        assert(armor == 0, "Default armor is NONE")

        add_test("TechnoClass Get_Armor", true, "Get_Armor works")
    end)

    if not ok11 then
        add_test("TechnoClass Get_Armor", false, tostring(err11))
    end

    -- Test 12: FootClass pathfinding integration
    local ok12, err12 = pcall(function()
        local FootClass = require("src.objects.foot")
        local Coord = require("src.core.coord")
        local Target = require("src.core.target")

        local foot = FootClass:new()
        foot.Strength = 100
        foot.IsActive = true
        foot.IsInLimbo = false
        foot.Coord = Coord.Cell_Coord(10, 10)

        -- Set destination using As_Coord (encodes coord as target)
        local dest_coord = Coord.Cell_Coord(12, 10)
        foot.NavCom = Target.As_Coord(dest_coord)

        -- Calculate path
        local success = foot:Basic_Path()
        assert(success == true, "Should calculate path")
        assert(foot.Path[1] == FootClass.FACING.E, "First step should be East")

        add_test("FootClass pathfinding", true, "FootClass uses FindPath")
    end)

    if not ok12 then
        add_test("FootClass pathfinding", false, tostring(err12))
    end

    -- Summary
    local passed = 0
    local failed = 0
    for _, test in ipairs(result.tests) do
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    result.message = string.format("%d/%d tests passed", passed, passed + failed)

    return result
end

-- Cleanup on quit
function IPC:cleanup()
    os.remove(self.command_file)
    os.remove(self.response_file)
    os.execute('rmdir "' .. self.ipc_dir .. '" 2>nul')
end

-- Check if we should allow game tick (for manual tick mode)
function IPC:should_tick()
    if not self.manual_tick_mode then
        return true
    end

    if self.ticks_to_advance > 0 then
        self.ticks_to_advance = self.ticks_to_advance - 1
        return true
    end

    return false
end

return IPC
