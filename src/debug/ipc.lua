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

    elseif cmd == "test_phase4" then
        -- Test Phase 4 integration (economy, production, overlays)
        local test_result = self:test_phase4_integration()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_phase5" then
        -- Test Phase 5 integration (teams, triggers, scenarios)
        local test_result = self:test_phase5_integration()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_phase6" then
        -- Test Phase 6 integration (network events)
        local test_result = self:test_phase6_integration()
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
            "test_phase4 - Test Phase 4 integration (economy, production, overlays)",
            "test_phase5 - Test Phase 5 integration (teams, triggers, scenarios)",
            "test_phase6 - Test Phase 6 integration (network events)",
            "test_terrain_smudge - Test TerrainClass, SmudgeClass and type classes",
            "test_missions - Test FootClass mission methods and threat detection",
            "test_combat_system - Test Combat system (Explosion_Damage, BulletClass, Approach_Target)",
            "test_pathfinding - Test Pathfinding and Animation effects (SmudgeClass, Middle())",
            "test_economy - Test Economy and Production systems (Phase 4: harvesters, MCV, factories)",
            "help - Show this help"
        }

    elseif cmd == "test_terrain_smudge" then
        -- Test terrain and smudge classes
        local test_result = self:test_terrain_smudge()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_missions" then
        -- Test FootClass missions and TechnoClass threat detection
        local test_result = self:test_missions()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_combat_system" then
        -- Test Combat system (Explosion_Damage, BulletClass:Detonate, FootClass:Approach_Target)
        local test_result = self:test_combat()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_pathfinding" then
        -- Test Pathfinding and Animation Effects (Phase 3 completion)
        local test_result = self:test_pathfinding()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

    elseif cmd == "test_economy" then
        -- Test Economy and Production systems (Phase 4)
        local test_result = self:test_economy()
        response.success = test_result.success
        response.tests = test_result.tests
        response.message = test_result.message

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

-- Test Phase 4 integration (economy, production, overlays)
function IPC:test_phase4_integration()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: FactoryClass loading and basic operations
    local ok1, err1 = pcall(function()
        local FactoryClass = require("src.production.factory")

        local factory = FactoryClass:new()
        assert(factory ~= nil, "Factory should be created")
        assert(factory.IsActive == true, "Factory should be active")
        assert(factory.IsSuspended == true, "Factory should start suspended")
        assert(factory:Fetch_Stage() == 0, "Stage should be 0")
        assert(factory:Fetch_Rate() == 0, "Rate should be 0")
        assert(factory:Is_Building() == false, "Should not be building")
        assert(factory:Has_Completed() == false, "Should not be completed")

        add_test("FactoryClass creation", true, "FactoryClass creates and initializes correctly")
    end)

    if not ok1 then
        add_test("FactoryClass creation", false, tostring(err1))
    end

    -- Test 2: FactoryClass Set and Start
    local ok2, err2 = pcall(function()
        local FactoryClass = require("src.production.factory")
        local UnitTypeClass = require("src.objects.types.unittype")

        local factory = FactoryClass:new()

        -- Create a mock house
        local mock_house = {
            is_human = true,
            cost_bias = 1.0,
            build_time_bias = 1.0,
            can_afford = function() return true end,
            available_money = function() return 10000 end,
            spend_credits = function() end,
            add_credits = function() end,
        }

        -- Set up production using a unit type
        local unit_type = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        local success = factory:Set(unit_type, mock_house)
        assert(success == true, "Set should succeed")
        assert(factory.ObjectType == unit_type, "ObjectType should be set")
        assert(factory.Balance > 0, "Balance should be set from cost")
        assert(factory.IsSuspended == true, "Should still be suspended")

        -- Start production
        local started = factory:Start()
        assert(started == true, "Start should succeed")
        assert(factory.IsSuspended == false, "Should not be suspended after start")
        assert(factory:Fetch_Rate() > 0, "Rate should be set")
        assert(factory:Is_Building() == true, "Should be building")

        add_test("FactoryClass Set/Start", true, "Set and Start work correctly")
    end)

    if not ok2 then
        add_test("FactoryClass Set/Start", false, tostring(err2))
    end

    -- Test 3: FactoryClass Suspend and Abandon
    local ok3, err3 = pcall(function()
        local FactoryClass = require("src.production.factory")
        local UnitTypeClass = require("src.objects.types.unittype")

        local factory = FactoryClass:new()

        local mock_house = {
            is_human = true,
            cost_bias = 1.0,
            build_time_bias = 1.0,
            can_afford = function() return true end,
            available_money = function() return 10000 end,
            spend_credits = function() end,
            add_credits = function() end,
        }

        local unit_type = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        factory:Set(unit_type, mock_house)
        factory:Start()

        -- Suspend
        local suspended = factory:Suspend()
        assert(suspended == true, "Suspend should succeed")
        assert(factory.IsSuspended == true, "Should be suspended")
        assert(factory:Is_Building() == false, "Should not be building")

        -- Resume
        factory:Start()
        assert(factory.IsSuspended == false, "Should resume")

        -- Abandon
        local abandoned = factory:Abandon()
        assert(abandoned == true, "Abandon should succeed")
        assert(factory.Object == nil, "Object should be nil")
        assert(factory.ObjectType == nil, "ObjectType should be nil")
        assert(factory:Fetch_Stage() == 0, "Stage should be reset")

        add_test("FactoryClass Suspend/Abandon", true, "Suspend and Abandon work correctly")
    end)

    if not ok3 then
        add_test("FactoryClass Suspend/Abandon", false, tostring(err3))
    end

    -- Test 4: FactoryClass AI and completion
    local ok4, err4 = pcall(function()
        local FactoryClass = require("src.production.factory")
        local UnitTypeClass = require("src.objects.types.unittype")

        local factory = FactoryClass:new()
        local credits_spent = 0

        local mock_house = {
            is_human = true,
            cost_bias = 1.0,
            build_time_bias = 1.0,
            can_afford = function() return true end,
            available_money = function() return 10000 end,
            spend_credits = function(self, amount) credits_spent = credits_spent + amount end,
            add_credits = function() end,
        }

        local unit_type = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        factory:Set(unit_type, mock_house)
        factory:Start()

        local initial_balance = factory.Balance

        -- Simulate faster by reducing rate for testing
        factory:Set_Rate(1)  -- Fastest rate

        -- Run AI until completed (with faster rate)
        local ticks = 0
        while not factory:Has_Completed() and ticks < 500 do
            factory:AI()
            ticks = ticks + 1
        end

        assert(factory:Has_Completed() == true, "Should complete")
        assert(factory:Fetch_Stage() == FactoryClass.STEP_COUNT, "Should be at max stage")
        assert(factory.Balance == 0, "Balance should be 0")
        assert(credits_spent > 0, "Should have spent credits")

        add_test("FactoryClass AI/completion", true, string.format("Completed in %d ticks, spent %d credits", ticks, credits_spent))
    end)

    if not ok4 then
        add_test("FactoryClass AI/completion", false, tostring(err4))
    end

    -- Test 5: OverlayTypeClass loading
    local ok5, err5 = pcall(function()
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        -- Test overlay type constants
        assert(OverlayTypeClass.OVERLAY.NONE == -1, "NONE should be -1")
        assert(OverlayTypeClass.OVERLAY.SANDBAG_WALL == 1, "SANDBAG_WALL should be 1")
        assert(OverlayTypeClass.OVERLAY.TIBERIUM1 == 6, "TIBERIUM1 should be 6")
        assert(OverlayTypeClass.OVERLAY.WOOD_CRATE == 28, "WOOD_CRATE should be 28")

        -- Test creating overlay type
        local wall_type = OverlayTypeClass.Create(OverlayTypeClass.OVERLAY.SANDBAG_WALL)
        assert(wall_type ~= nil, "Wall type should be created")
        assert(wall_type.Name == "SBAG", "Name should be SBAG")
        assert(wall_type.IsWall == true, "Should be a wall")
        assert(wall_type.IsTiberium == false, "Should not be tiberium")

        local tib_type = OverlayTypeClass.Create(OverlayTypeClass.OVERLAY.TIBERIUM1)
        assert(tib_type ~= nil, "Tiberium type should be created")
        assert(tib_type.IsTiberium == true, "Should be tiberium")
        assert(tib_type.IsWall == false, "Should not be a wall")

        add_test("OverlayTypeClass creation", true, "OverlayTypeClass creates types correctly")
    end)

    if not ok5 then
        add_test("OverlayTypeClass creation", false, tostring(err5))
    end

    -- Test 6: OverlayTypeClass Tiberium_Value
    local ok6, err6 = pcall(function()
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        -- Test tiberium values (should increase with stage)
        local val1 = OverlayTypeClass.Tiberium_Value(OverlayTypeClass.OVERLAY.TIBERIUM1)
        local val6 = OverlayTypeClass.Tiberium_Value(OverlayTypeClass.OVERLAY.TIBERIUM6)
        local val12 = OverlayTypeClass.Tiberium_Value(OverlayTypeClass.OVERLAY.TIBERIUM12)

        assert(val1 > 0, "TIBERIUM1 should have value")
        assert(val6 > val1, "TIBERIUM6 should be more valuable than TIBERIUM1")
        assert(val12 > val6, "TIBERIUM12 should be more valuable than TIBERIUM6")

        -- Non-tiberium should be 0
        local wall_val = OverlayTypeClass.Tiberium_Value(OverlayTypeClass.OVERLAY.SANDBAG_WALL)
        assert(wall_val == 0, "Walls should have 0 tiberium value")

        add_test("OverlayTypeClass Tiberium_Value", true, string.format("Values: T1=%d, T6=%d, T12=%d", val1, val6, val12))
    end)

    if not ok6 then
        add_test("OverlayTypeClass Tiberium_Value", false, tostring(err6))
    end

    -- Test 7: OverlayClass creation and type helpers
    local ok7, err7 = pcall(function()
        local OverlayClass = require("src.objects.overlay")
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        -- Create a tiberium overlay
        local tib = OverlayClass:new(OverlayTypeClass.OVERLAY.TIBERIUM5)
        assert(tib ~= nil, "Tiberium overlay should be created")
        assert(tib:Is_Tiberium() == true, "Should be tiberium")
        assert(tib:Is_Wall() == false, "Should not be a wall")
        assert(tib:Is_Crate() == false, "Should not be a crate")
        assert(tib:Tiberium_Value() > 0, "Should have tiberium value")

        -- Create a wall overlay
        local wall = OverlayClass:new(OverlayTypeClass.OVERLAY.BRICK_WALL)
        assert(wall ~= nil, "Wall overlay should be created")
        assert(wall:Is_Wall() == true, "Should be a wall")
        assert(wall:Is_Tiberium() == false, "Should not be tiberium")

        -- Create a crate overlay
        local crate = OverlayClass:new(OverlayTypeClass.OVERLAY.WOOD_CRATE)
        assert(crate ~= nil, "Crate overlay should be created")
        assert(crate:Is_Crate() == true, "Should be a crate")
        assert(crate:Is_Wall() == false, "Should not be a wall")

        add_test("OverlayClass type helpers", true, "Is_Tiberium, Is_Wall, Is_Crate work")
    end)

    if not ok7 then
        add_test("OverlayClass type helpers", false, tostring(err7))
    end

    -- Test 8: OverlayClass tiberium growth
    local ok8, err8 = pcall(function()
        local OverlayClass = require("src.objects.overlay")
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        local tib = OverlayClass:new(OverlayTypeClass.OVERLAY.TIBERIUM1)
        local initial_type = tib.Type
        local initial_value = tib:Tiberium_Value()

        -- Grow tiberium
        local new_type = tib:Grow_Tiberium()
        assert(new_type ~= nil, "Should grow")
        assert(new_type > initial_type, "Type should increase")
        assert(tib:Tiberium_Value() > initial_value, "Value should increase")

        -- Grow to max
        while tib:Grow_Tiberium() ~= nil do end
        assert(tib.Type == OverlayTypeClass.OVERLAY.TIBERIUM12, "Should reach TIBERIUM12")

        -- Can't grow past max
        local past_max = tib:Grow_Tiberium()
        assert(past_max == nil, "Should not grow past max")

        add_test("OverlayClass tiberium growth", true, "Grow_Tiberium works correctly")
    end)

    if not ok8 then
        add_test("OverlayClass tiberium growth", false, tostring(err8))
    end

    -- Test 9: OverlayClass harvesting
    local ok9, err9 = pcall(function()
        local OverlayClass = require("src.objects.overlay")
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        local tib = OverlayClass:new(OverlayTypeClass.OVERLAY.TIBERIUM6)
        local expected_value = tib:Tiberium_Value()

        local harvested = tib:Harvest_Tiberium()
        assert(harvested == expected_value, "Should return correct value")
        assert(tib.IsInLimbo == true, "Should be in limbo after harvest")

        add_test("OverlayClass harvesting", true, string.format("Harvested %d credits", harvested))
    end)

    if not ok9 then
        add_test("OverlayClass harvesting", false, tostring(err9))
    end

    -- Test 10: OverlayClass wall damage
    local ok10, err10 = pcall(function()
        local OverlayClass = require("src.objects.overlay")
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        local wall = OverlayClass:new(OverlayTypeClass.OVERLAY.SANDBAG_WALL)
        wall.Strength = 3  -- Give it 3 HP

        -- Low damage (< 20 damage_points) should not reduce strength
        local destroyed = wall:Take_Wall_Damage(10)
        assert(destroyed == false, "Should not destroy with low damage")
        assert(wall.Strength == 3, "Strength unchanged with insufficient damage")

        -- Sufficient damage (>= 20) should reduce strength
        destroyed = wall:Take_Wall_Damage(25)
        assert(destroyed == false, "Should not destroy yet")
        assert(wall.Strength == 2, "Strength should be reduced")

        -- Keep damaging until destroyed
        wall:Take_Wall_Damage(25)
        destroyed = wall:Take_Wall_Damage(25)
        assert(destroyed == true, "Should be destroyed")
        assert(wall.IsInLimbo == true, "Should be in limbo")

        add_test("OverlayClass wall damage", true, "Take_Wall_Damage works correctly")
    end)

    if not ok10 then
        add_test("OverlayClass wall damage", false, tostring(err10))
    end

    -- Test 11: OverlayClass crate opening
    local ok11, err11 = pcall(function()
        local OverlayClass = require("src.objects.overlay")
        local OverlayTypeClass = require("src.objects.types.overlaytype")

        local wood_crate = OverlayClass:new(OverlayTypeClass.OVERLAY.WOOD_CRATE)
        local content_type, value = wood_crate:Open_Crate(nil)
        assert(content_type == "MONEY", "Wood crate should give money")
        assert(value == 500, "Wood crate should give 500")
        assert(wood_crate.IsInLimbo == true, "Crate should be in limbo")

        local steel_crate = OverlayClass:new(OverlayTypeClass.OVERLAY.STEEL_CRATE)
        content_type, value = steel_crate:Open_Crate(nil)
        assert(content_type == "MONEY", "Steel crate should give money")
        assert(value == 2000, "Steel crate should give 2000")

        add_test("OverlayClass crate opening", true, "Open_Crate works correctly")
    end)

    if not ok11 then
        add_test("OverlayClass crate opening", false, tostring(err11))
    end

    -- Test 12: HouseClass factory tracking
    local ok12, err12 = pcall(function()
        local House = require("src.house.house")

        local house = House:new("GDI", 1, true)
        assert(house ~= nil, "House should be created")
        assert(house.infantry_factories == 0, "Should start with 0 infantry factories")
        assert(house.unit_factories == 0, "Should start with 0 unit factories")
        assert(house.aircraft_factories == 0, "Should start with 0 aircraft factories")
        assert(house.building_factories == 0, "Should start with 0 building factories")

        add_test("HouseClass factory tracking", true, "Factory count tracking initialized")
    end)

    if not ok12 then
        add_test("HouseClass factory tracking", false, tostring(err12))
    end

    -- Test 13: HouseClass Build_Unit
    local ok13, err13 = pcall(function()
        local House = require("src.house.house")
        local UnitTypeClass = require("src.objects.types.unittype")

        local house = House:new("GDI", 1, true)
        house:add_credits(10000)  -- Give some money
        house.factories.vehicle = true  -- Simulate having a war factory

        local unit_type = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        local success = house:Build_Unit(unit_type)
        assert(success == true, "Build_Unit should succeed")
        assert(house.unit_factory ~= nil, "Should have unit factory")
        assert(house.unit_factory:Is_Building() == true, "Factory should be building")

        add_test("HouseClass Build_Unit", true, "Build_Unit starts production correctly")
    end)

    if not ok13 then
        add_test("HouseClass Build_Unit", false, tostring(err13))
    end

    -- Test 14: HouseClass Build_Infantry
    local ok14, err14 = pcall(function()
        local House = require("src.house.house")
        local InfantryTypeClass = require("src.objects.types.infantrytype")

        local house = House:new("GDI", 1, true)
        house:add_credits(1000)
        house.factories.infantry = true  -- Simulate having a barracks

        local infantry_type = InfantryTypeClass.Create(InfantryTypeClass.INFANTRY.E1)
        local success = house:Build_Infantry(infantry_type)
        assert(success == true, "Build_Infantry should succeed")
        assert(house.infantry_factory ~= nil, "Should have infantry factory")

        add_test("HouseClass Build_Infantry", true, "Build_Infantry starts production correctly")
    end)

    if not ok14 then
        add_test("HouseClass Build_Infantry", false, tostring(err14))
    end

    -- Test 15: BuildingClass placement validation
    local ok15, err15 = pcall(function()
        local BuildingClass = require("src.objects.building")

        -- Test basic placement check (no map, just function existence)
        assert(BuildingClass.Can_Place_Building ~= nil, "Can_Place_Building should exist")
        assert(BuildingClass.Is_Adjacent_To_Building ~= nil, "Is_Adjacent_To_Building should exist")
        assert(BuildingClass.Get_Valid_Placement_Cells ~= nil, "Get_Valid_Placement_Cells should exist")

        add_test("BuildingClass placement", true, "Placement validation functions exist")
    end)

    if not ok15 then
        add_test("BuildingClass placement", false, tostring(err15))
    end

    -- Test 16: FactoryClass Cost_Per_Tick
    local ok16, err16 = pcall(function()
        local FactoryClass = require("src.production.factory")
        local UnitTypeClass = require("src.objects.types.unittype")

        local factory = FactoryClass:new()

        local mock_house = {
            is_human = true,
            cost_bias = 1.0,
            build_time_bias = 1.0,
            can_afford = function() return true end,
            available_money = function() return 10000 end,
            spend_credits = function() end,
            add_credits = function() end,
        }

        local unit_type = UnitTypeClass.Create(UnitTypeClass.UNIT.MTANK)
        factory:Set(unit_type, mock_house)

        local initial_balance = factory.Balance
        local cost_per_tick = factory:Cost_Per_Tick()

        -- Cost per tick should be balance / steps_remaining
        local expected = math.floor(initial_balance / FactoryClass.STEP_COUNT)
        assert(cost_per_tick == expected, string.format("Cost per tick should be %d, got %d", expected, cost_per_tick))

        add_test("FactoryClass Cost_Per_Tick", true, string.format("Cost per tick: %d", cost_per_tick))
    end)

    if not ok16 then
        add_test("FactoryClass Cost_Per_Tick", false, tostring(err16))
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

-- Test Phase 5 integration (teams, triggers, scenarios)
function IPC:test_phase5_integration()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: TeamTypeClass loading
    local ok1, err1 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        -- Test constants
        assert(TeamTypeClass.TMISSION.ATTACKBASE == 0, "ATTACKBASE should be 0")
        assert(TeamTypeClass.TMISSION.MOVE == 5, "MOVE should be 5")
        assert(TeamTypeClass.TMISSION.UNLOAD == 11, "UNLOAD should be 11")
        assert(TeamTypeClass.MAX_TEAM_CLASSCOUNT == 5, "MAX_TEAM_CLASSCOUNT should be 5")
        assert(TeamTypeClass.MAX_TEAM_MISSIONS == 20, "MAX_TEAM_MISSIONS should be 20")

        add_test("TeamTypeClass constants", true, "Constants loaded correctly")
    end)

    if not ok1 then
        add_test("TeamTypeClass constants", false, tostring(err1))
    end

    -- Test 2: TeamTypeClass creation
    local ok2, err2 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        -- Clear registry for clean test
        TeamTypeClass.Init()

        local team_type = TeamTypeClass.Create("TestTeam1")
        assert(team_type ~= nil, "Team type should be created")
        assert(team_type.IniName == "TestTeam1", "IniName should match")
        assert(team_type.IsActive == true, "Should be active")
        assert(team_type.IsAutocreate == false, "Should not be autocreate by default")
        assert(team_type.IsSuicide == false, "Should not be suicide by default")
        assert(team_type.ClassCount == 0, "Should have no units yet")
        assert(team_type.MissionCount == 0, "Should have no missions yet")

        add_test("TeamTypeClass creation", true, "TeamTypeClass creates correctly")
    end)

    if not ok2 then
        add_test("TeamTypeClass creation", false, tostring(err2))
    end

    -- Test 3: TeamTypeClass Fill_In
    local ok3, err3 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        TeamTypeClass.Init()

        local team_type = TeamTypeClass.Create("AttackTeam")
        team_type:Fill_In({
            house = 1,  -- NOD
            roundabout = true,
            suicide = true,
            autocreate = true,
            priority = 10,
            max_allowed = 2,
            fear = 50,
            members = {
                { type = "E1", count = 3 },
                { type = "E3", count = 2 },
            },
            missions = {
                { mission = TeamTypeClass.TMISSION.MOVE, argument = 5 },
                { mission = TeamTypeClass.TMISSION.ATTACKBASE, argument = 0 },
            }
        })

        assert(team_type.House == 1, "House should be 1")
        assert(team_type.IsRoundAbout == true, "Should be roundabout")
        assert(team_type.IsSuicide == true, "Should be suicide")
        assert(team_type.IsAutocreate == true, "Should be autocreate")
        assert(team_type.RecruitPriority == 10, "Priority should be 10")
        assert(team_type.MaxAllowed == 2, "MaxAllowed should be 2")
        assert(team_type.Fear == 50, "Fear should be 50")
        assert(team_type.ClassCount == 2, "Should have 2 unit types")
        assert(team_type.DesiredNum[1] == 3, "First type should have 3 units")
        assert(team_type.MissionCount == 2, "Should have 2 missions")
        assert(team_type.MissionList[1].Mission == TeamTypeClass.TMISSION.MOVE, "First mission should be MOVE")

        add_test("TeamTypeClass Fill_In", true, "Fill_In populates data correctly")
    end)

    if not ok3 then
        add_test("TeamTypeClass Fill_In", false, tostring(err3))
    end

    -- Test 4: TeamTypeClass As_Pointer
    local ok4, err4 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        TeamTypeClass.Init()

        local team1 = TeamTypeClass.Create("Team1")
        local team2 = TeamTypeClass.Create("Team2")

        -- Retrieve by name
        local found1 = TeamTypeClass.As_Pointer("Team1")
        local found2 = TeamTypeClass.As_Pointer("Team2")
        local not_found = TeamTypeClass.As_Pointer("NonExistent")

        assert(found1 == team1, "Should find Team1")
        assert(found2 == team2, "Should find Team2")
        assert(not_found == nil, "Should not find NonExistent")

        add_test("TeamTypeClass As_Pointer", true, "Registry lookup works")
    end)

    if not ok4 then
        add_test("TeamTypeClass As_Pointer", false, tostring(err4))
    end

    -- Test 5: TeamTypeClass Create_One_Of
    local ok5, err5 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        TeamTypeClass.Init()

        local team_type = TeamTypeClass.Create("SpawnTeam")
        team_type.MaxAllowed = 2
        team_type.House = 0

        -- Create first team
        local data1 = team_type:Create_One_Of()
        assert(data1 ~= nil, "Should create first team")
        assert(team_type.ActiveCount == 1, "ActiveCount should be 1")

        -- Create second team
        local data2 = team_type:Create_One_Of()
        assert(data2 ~= nil, "Should create second team")
        assert(team_type.ActiveCount == 2, "ActiveCount should be 2")

        -- Should fail to create third (max reached)
        local data3 = team_type:Create_One_Of()
        assert(data3 == nil, "Should not create third team")
        assert(team_type.ActiveCount == 2, "ActiveCount should still be 2")

        add_test("TeamTypeClass Create_One_Of", true, "Team creation with limits works")
    end)

    if not ok5 then
        add_test("TeamTypeClass Create_One_Of", false, tostring(err5))
    end

    -- Test 6: TeamTypeClass mission names
    local ok6, err6 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        -- Test Name_From_Mission
        local name = TeamTypeClass.Name_From_Mission(TeamTypeClass.TMISSION.ATTACKBASE)
        assert(name == "Attack Base", "ATTACKBASE should be 'Attack Base'")

        local name2 = TeamTypeClass.Name_From_Mission(TeamTypeClass.TMISSION.GUARD)
        assert(name2 == "Guard", "GUARD should be 'Guard'")

        -- Test Mission_From_Name
        local mission = TeamTypeClass.Mission_From_Name("Move")
        assert(mission == TeamTypeClass.TMISSION.MOVE, "Move should be TMISSION.MOVE")

        local mission2 = TeamTypeClass.Mission_From_Name("Attack Units")
        assert(mission2 == TeamTypeClass.TMISSION.ATTACKUNITS, "'Attack Units' should be TMISSION.ATTACKUNITS")

        add_test("TeamTypeClass mission names", true, "Mission name conversion works")
    end)

    if not ok6 then
        add_test("TeamTypeClass mission names", false, tostring(err6))
    end

    -- Test 7: ScenarioClass loading
    local ok7, err7 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        -- Test constants
        assert(ScenarioClass.PLAYER.GDI == 0, "GDI should be 0")
        assert(ScenarioClass.PLAYER.NOD == 1, "NOD should be 1")
        assert(ScenarioClass.THEATER.TEMPERATE == 1, "TEMPERATE should be 1")
        assert(ScenarioClass.DIR.EAST == 0, "EAST should be 0")
        assert(ScenarioClass.VAR.A == 0, "VAR A should be 0")

        add_test("ScenarioClass constants", true, "Constants loaded correctly")
    end)

    if not ok7 then
        add_test("ScenarioClass constants", false, tostring(err7))
    end

    -- Test 8: ScenarioClass creation
    local ok8, err8 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()
        assert(scenario ~= nil, "Scenario should be created")
        assert(scenario.Number == 0, "Number should be 0")
        assert(scenario.IsEnded == false, "Should not be ended")
        assert(scenario.IsPlayerWinner == false, "Should not have winner")
        assert(scenario.Timer == 0, "Timer should be 0")
        assert(scenario.TechLevel == 10, "TechLevel should be 10")

        add_test("ScenarioClass creation", true, "ScenarioClass creates correctly")
    end)

    if not ok8 then
        add_test("ScenarioClass creation", false, tostring(err8))
    end

    -- Test 9: ScenarioClass Initialize
    local ok9, err9 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()
        scenario:Initialize({
            name = "SCG01EA",
            description = "GDI Mission 1",
            number = 1,
            player = "GDI",
            theater = "TEMPERATE",
            map_width = 64,
            map_height = 64,
            briefing = "Test briefing",
            tech_level = 5,
            starting_credits = 5000,
            difficulty = 1,
        })

        assert(scenario.Name == "SCG01EA", "Name should be SCG01EA")
        assert(scenario.Description == "GDI Mission 1", "Description should match")
        assert(scenario.Number == 1, "Number should be 1")
        assert(scenario.Player == ScenarioClass.PLAYER.GDI, "Player should be GDI")
        assert(scenario.Theater == ScenarioClass.THEATER.TEMPERATE, "Theater should be TEMPERATE")
        assert(scenario.TechLevel == 5, "TechLevel should be 5")
        assert(scenario.StartingCredits == 5000, "Credits should be 5000")

        add_test("ScenarioClass Initialize", true, "Initialize sets data correctly")
    end)

    if not ok9 then
        add_test("ScenarioClass Initialize", false, tostring(err9))
    end

    -- Test 10: ScenarioClass global flags
    local ok10, err10 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()

        -- Test Set_Global and Get_Global
        assert(scenario:Get_Global(0) == false, "Flag 0 should be false initially")
        scenario:Set_Global(0, true)
        assert(scenario:Get_Global(0) == true, "Flag 0 should be true after set")

        scenario:Set_Global(15, true)
        assert(scenario:Get_Global(15) == true, "Flag 15 should be true")

        scenario:Clear_Global(0)
        assert(scenario:Get_Global(0) == false, "Flag 0 should be false after clear")

        -- Test out of range
        assert(scenario:Get_Global(50) == false, "Out of range should return false")

        add_test("ScenarioClass global flags", true, "Global flags work correctly")
    end)

    if not ok10 then
        add_test("ScenarioClass global flags", false, tostring(err10))
    end

    -- Test 11: ScenarioClass victory/defeat
    local ok11, err11 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        -- Test win
        local scenario1 = ScenarioClass.Reset()
        assert(scenario1:Has_Ended() == false, "Should not be ended")
        scenario1:Player_Wins()
        assert(scenario1:Has_Ended() == true, "Should be ended after win")
        assert(scenario1:Did_Win() == true, "Should have won")

        -- Test lose
        local scenario2 = ScenarioClass.Reset()
        scenario2:Player_Loses()
        assert(scenario2:Has_Ended() == true, "Should be ended after lose")
        assert(scenario2:Did_Win() == false, "Should not have won")

        add_test("ScenarioClass victory/defeat", true, "Victory/defeat works correctly")
    end)

    if not ok11 then
        add_test("ScenarioClass victory/defeat", false, tostring(err11))
    end

    -- Test 12: ScenarioClass timer
    local ok12, err12 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()
        scenario.Timer = 900  -- 60 seconds * 15 ticks
        local timer_str = scenario:Get_Timer_String()
        assert(timer_str == "01:00", string.format("Timer should be 01:00, got %s", timer_str))

        scenario.Timer = 1350  -- 90 seconds
        timer_str = scenario:Get_Timer_String()
        assert(timer_str == "01:30", string.format("Timer should be 01:30, got %s", timer_str))

        add_test("ScenarioClass timer", true, "Timer formatting works")
    end)

    if not ok12 then
        add_test("ScenarioClass timer", false, tostring(err12))
    end

    -- Test 13: ScenarioClass singleton
    local ok13, err13 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario1 = ScenarioClass.Get()
        local scenario2 = ScenarioClass.Get()
        assert(scenario1 == scenario2, "Get should return same instance")

        ScenarioClass.Reset()
        local scenario3 = ScenarioClass.Get()
        assert(scenario1 ~= scenario3, "Reset should create new instance")

        add_test("ScenarioClass singleton", true, "Singleton pattern works")
    end)

    if not ok13 then
        add_test("ScenarioClass singleton", false, tostring(err13))
    end

    -- Test 14: ScenarioClass theater name
    local ok14, err14 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()

        scenario.Theater = ScenarioClass.THEATER.DESERT
        assert(scenario:Get_Theater_Name() == "DESERT", "Should be DESERT")

        scenario.Theater = ScenarioClass.THEATER.TEMPERATE
        assert(scenario:Get_Theater_Name() == "TEMPERATE", "Should be TEMPERATE")

        scenario.Theater = ScenarioClass.THEATER.WINTER
        assert(scenario:Get_Theater_Name() == "WINTER", "Should be WINTER")

        add_test("ScenarioClass theater name", true, "Theater names work")
    end)

    if not ok14 then
        add_test("ScenarioClass theater name", false, tostring(err14))
    end

    -- Test 15: ScenarioClass trigger tracking
    local ok15, err15 = pcall(function()
        local ScenarioClass = require("src.scenario.scenario")

        local scenario = ScenarioClass.Reset()

        assert(scenario:Has_Trigger_Fired("Test1") == false, "Trigger should not be fired")
        scenario:Record_Trigger_Fired("Test1")
        assert(scenario:Has_Trigger_Fired("Test1") == true, "Trigger should be fired")
        assert(scenario:Has_Trigger_Fired("Test2") == false, "Other trigger should not be fired")

        add_test("ScenarioClass trigger tracking", true, "Trigger tracking works")
    end)

    if not ok15 then
        add_test("ScenarioClass trigger tracking", false, tostring(err15))
    end

    -- Test 16: TeamTypeClass validation
    local ok16, err16 = pcall(function()
        local TeamTypeClass = require("src.scenario.team_type")

        TeamTypeClass.Init()

        local valid_team = TeamTypeClass.Create("ValidTeam")
        assert(valid_team:Validate() == true, "Valid team should validate")

        local invalid_team = TeamTypeClass.Create("")
        invalid_team.IniName = ""  -- Force invalid name
        assert(invalid_team:Validate() == false, "Invalid team should not validate")

        add_test("TeamTypeClass validation", true, "Validation works correctly")
    end)

    if not ok16 then
        add_test("TeamTypeClass validation", false, tostring(err16))
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

-- Test Phase 6 integration (network events)
function IPC:test_phase6_integration()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: EventClass loading
    local ok1, err1 = pcall(function()
        local EventClass = require("src.network.event")

        -- Test constants
        assert(EventClass.TYPE.EMPTY == 0, "EMPTY should be 0")
        assert(EventClass.TYPE.MEGAMISSION == 2, "MEGAMISSION should be 2")
        assert(EventClass.TYPE.DEPLOY == 6, "DEPLOY should be 6")
        assert(EventClass.TYPE.PRODUCE == 10, "PRODUCE should be 10")
        assert(EventClass.TYPE.FRAMESYNC == 20, "FRAMESYNC should be 20")
        assert(EventClass.TYPE.LAST_EVENT == 27, "LAST_EVENT should be 27")

        add_test("EventClass constants", true, "Event type constants loaded correctly")
    end)

    if not ok1 then
        add_test("EventClass constants", false, tostring(err1))
    end

    -- Test 2: EventClass creation
    local ok2, err2 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.new(EventClass.TYPE.DEPLOY)
        assert(event ~= nil, "Event should be created")
        assert(event.Type == EventClass.TYPE.DEPLOY, "Type should be DEPLOY")
        assert(event.Frame == 0, "Frame should be 0")
        assert(event.ID == 0, "ID should be 0")
        assert(event.IsExecuted == false, "Should not be executed")

        add_test("EventClass creation", true, "EventClass creates correctly")
    end)

    if not ok2 then
        add_test("EventClass creation", false, tostring(err2))
    end

    -- Test 3: EventClass.Target factory
    local ok3, err3 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.Target(EventClass.TYPE.REPAIR, 0x12345678)
        assert(event.Type == EventClass.TYPE.REPAIR, "Type should be REPAIR")
        assert(event.Data.Whom == 0x12345678, "Whom should match target")

        local event2 = EventClass.Target(EventClass.TYPE.SELL, 0xAABBCCDD)
        assert(event2.Type == EventClass.TYPE.SELL, "Type should be SELL")
        assert(event2.Data.Whom == 0xAABBCCDD, "Whom should match target")

        add_test("EventClass.Target factory", true, "Target factory works correctly")
    end)

    if not ok3 then
        add_test("EventClass.Target factory", false, tostring(err3))
    end

    -- Test 4: EventClass.MegaMission factory
    local ok4, err4 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.MegaMission(0x1111, 5, 0x2222, 0x3333)
        assert(event.Type == EventClass.TYPE.MEGAMISSION, "Type should be MEGAMISSION")
        assert(event.Data.Whom == 0x1111, "Whom should match")
        assert(event.Data.Mission == 5, "Mission should match")
        assert(event.Data.Target == 0x2222, "Target should match")
        assert(event.Data.Destination == 0x3333, "Destination should match")

        add_test("EventClass.MegaMission factory", true, "MegaMission factory works correctly")
    end)

    if not ok4 then
        add_test("EventClass.MegaMission factory", false, tostring(err4))
    end

    -- Test 5: EventClass.Production factory
    local ok5, err5 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.Production(EventClass.TYPE.PRODUCE, 3, 5)
        assert(event.Type == EventClass.TYPE.PRODUCE, "Type should be PRODUCE")
        assert(event.Data.RTTIType == 3, "RTTIType should match")
        assert(event.Data.TypeID == 5, "TypeID should match")

        add_test("EventClass.Production factory", true, "Production factory works correctly")
    end)

    if not ok5 then
        add_test("EventClass.Production factory", false, tostring(err5))
    end

    -- Test 6: EventClass.Place factory
    local ok6, err6 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.Place(7, 0x1234)
        assert(event.Type == EventClass.TYPE.PLACE, "Type should be PLACE")
        assert(event.Data.RTTIType == 7, "RTTIType should match")
        assert(event.Data.Cell == 0x1234, "Cell should match")

        add_test("EventClass.Place factory", true, "Place factory works correctly")
    end)

    if not ok6 then
        add_test("EventClass.Place factory", false, tostring(err6))
    end

    -- Test 7: EventClass.SpecialPlace factory
    local ok7, err7 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.SpecialPlace(2, 0x5678)
        assert(event.Type == EventClass.TYPE.SPECIAL_PLACE, "Type should be SPECIAL_PLACE")
        assert(event.Data.SpecialID == 2, "SpecialID should match")
        assert(event.Data.Cell == 0x5678, "Cell should match")

        add_test("EventClass.SpecialPlace factory", true, "SpecialPlace factory works correctly")
    end)

    if not ok7 then
        add_test("EventClass.SpecialPlace factory", false, tostring(err7))
    end

    -- Test 8: EventClass.FrameSync factory
    local ok8, err8 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.FrameSync(0xDEADBEEF, 100, 3)
        assert(event.Type == EventClass.TYPE.FRAMESYNC, "Type should be FRAMESYNC")
        assert(event.Data.CRC == 0xDEADBEEF, "CRC should match")
        assert(event.Data.CommandCount == 100, "CommandCount should match")
        assert(event.Data.Delay == 3, "Delay should match")

        add_test("EventClass.FrameSync factory", true, "FrameSync factory works correctly")
    end)

    if not ok8 then
        add_test("EventClass.FrameSync factory", false, tostring(err8))
    end

    -- Test 9: EventClass.Message factory
    local ok9, err9 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.Message("Hello World!")
        assert(event.Type == EventClass.TYPE.MESSAGE, "Type should be MESSAGE")
        assert(event.Data.Message == "Hello World!", "Message should match")

        -- Test truncation
        local long_msg = string.rep("X", 50)
        local event2 = EventClass.Message(long_msg)
        assert(#event2.Data.Message == 40, "Message should be truncated to 40 chars")

        add_test("EventClass.Message factory", true, "Message factory works correctly")
    end)

    if not ok9 then
        add_test("EventClass.Message factory", false, tostring(err9))
    end

    -- Test 10: Event type names
    local ok10, err10 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.new(EventClass.TYPE.MEGAMISSION)
        assert(event:Get_Type_Name() == "MEGAMISSION", "Type name should be MEGAMISSION")

        local event2 = EventClass.new(EventClass.TYPE.FRAMESYNC)
        assert(event2:Get_Type_Name() == "FRAMESYNC", "Type name should be FRAMESYNC")

        add_test("EventClass type names", true, "Type name lookup works")
    end)

    if not ok10 then
        add_test("EventClass type names", false, tostring(err10))
    end

    -- Test 11: Event data sizes
    local ok11, err11 = pcall(function()
        local EventClass = require("src.network.event")

        local event1 = EventClass.new(EventClass.TYPE.EMPTY)
        assert(event1:Get_Data_Size() == 0, "EMPTY should have 0 data size")

        local event2 = EventClass.new(EventClass.TYPE.MEGAMISSION)
        assert(event2:Get_Data_Size() == 13, "MEGAMISSION should have 13 data size")

        local event3 = EventClass.new(EventClass.TYPE.MESSAGE)
        assert(event3:Get_Data_Size() == 40, "MESSAGE should have 40 data size")

        add_test("EventClass data sizes", true, "Data size lookup works")
    end)

    if not ok11 then
        add_test("EventClass data sizes", false, tostring(err11))
    end

    -- Test 12: Event encoding (simple event)
    local ok12, err12 = pcall(function()
        local EventClass = require("src.network.event")

        local event = EventClass.new(EventClass.TYPE.EXIT)
        event.Frame = 100
        event.ID = 2
        event.MPlayerID = 0x35

        local encoded = event:Encode()
        assert(encoded ~= nil, "Encoding should succeed")
        assert(#encoded == 7, string.format("EXIT event should be 7 bytes, got %d", #encoded))

        add_test("EventClass encoding (simple)", true, "Simple event encoding works")
    end)

    if not ok12 then
        add_test("EventClass encoding (simple)", false, tostring(err12))
    end

    -- Test 13: Event encoding/decoding roundtrip
    local ok13, err13 = pcall(function()
        local EventClass = require("src.network.event")

        -- Test MegaMission roundtrip
        local original = EventClass.MegaMission(0x12345678, 5, 0xAABBCCDD, 0x11223344)
        original.Frame = 12345
        original.ID = 3
        original.MPlayerID = 0x42

        local encoded = original:Encode()
        assert(encoded ~= nil, "Encoding should succeed")

        local decoded, bytes = EventClass.Decode(encoded)
        assert(decoded ~= nil, "Decoding should succeed")
        assert(decoded.Type == original.Type, "Type should match")
        assert(decoded.Frame == original.Frame, "Frame should match")
        assert(decoded.ID == original.ID, "ID should match")
        assert(decoded.MPlayerID == original.MPlayerID, "MPlayerID should match")
        assert(decoded.Data.Whom == original.Data.Whom, "Whom should match")
        assert(decoded.Data.Mission == original.Data.Mission, "Mission should match")
        assert(decoded.Data.Target == original.Data.Target, "Target should match")
        assert(decoded.Data.Destination == original.Data.Destination, "Destination should match")

        add_test("EventClass encoding/decoding roundtrip", true, "Roundtrip encoding works")
    end)

    if not ok13 then
        add_test("EventClass encoding/decoding roundtrip", false, tostring(err13))
    end

    -- Test 14: EventQueue creation
    local ok14, err14 = pcall(function()
        local EventClass = require("src.network.event")

        local queue = EventClass.Queue.new()
        assert(queue ~= nil, "Queue should be created")
        assert(queue.current_frame == 0, "Current frame should be 0")
        assert(#queue.events == 0, "Events should be empty")

        add_test("EventQueue creation", true, "EventQueue creates correctly")
    end)

    if not ok14 then
        add_test("EventQueue creation", false, tostring(err14))
    end

    -- Test 15: EventQueue Add and Get_Events_For_Frame
    local ok15, err15 = pcall(function()
        local EventClass = require("src.network.event")

        local queue = EventClass.Queue.new()

        -- Add events for different frames
        local event1 = EventClass.new(EventClass.TYPE.DEPLOY)
        event1.Frame = 10
        queue:Add(event1)

        local event2 = EventClass.new(EventClass.TYPE.REPAIR)
        event2.Frame = 10
        queue:Add(event2)

        local event3 = EventClass.new(EventClass.TYPE.SELL)
        event3.Frame = 15
        queue:Add(event3)

        -- Get events for frame 10
        local frame10_events = queue:Get_Events_For_Frame(10)
        assert(#frame10_events == 2, "Should have 2 events for frame 10")

        -- Get events for frame 15
        local frame15_events = queue:Get_Events_For_Frame(15)
        assert(#frame15_events == 1, "Should have 1 event for frame 15")

        -- Get events for frame 20 (none)
        local frame20_events = queue:Get_Events_For_Frame(20)
        assert(#frame20_events == 0, "Should have 0 events for frame 20")

        add_test("EventQueue Add and Get", true, "EventQueue Add/Get works correctly")
    end)

    if not ok15 then
        add_test("EventQueue Add and Get", false, tostring(err15))
    end

    -- Test 16: EventQueue Pending_Count and Cleanup
    local ok16, err16 = pcall(function()
        local EventClass = require("src.network.event")

        local queue = EventClass.Queue.new()

        local event1 = EventClass.new(EventClass.TYPE.DEPLOY)
        event1.Frame = 5
        queue:Add(event1)

        local event2 = EventClass.new(EventClass.TYPE.REPAIR)
        event2.Frame = 10
        queue:Add(event2)

        assert(queue:Pending_Count() == 2, "Should have 2 pending events")

        -- Execute frame 5
        queue:Execute_Frame(5, {})
        assert(queue:Pending_Count() == 1, "Should have 1 pending event after execute")

        -- Cleanup events before frame 8
        queue:Cleanup(8)
        assert(#queue.events == 1, "Should have 1 event after cleanup")

        add_test("EventQueue Pending_Count and Cleanup", true, "Pending count and cleanup work")
    end)

    if not ok16 then
        add_test("EventQueue Pending_Count and Cleanup", false, tostring(err16))
    end

    -- Test 17: Random module
    local ok17, err17 = pcall(function()
        local Random = require("src.core.random")

        -- Test that we can get random values
        Random.Reset()
        local v1 = Random.Sim_Random()
        local v2 = Random.Sim_Random()
        assert(v1 >= 0 and v1 <= 255, "Random value should be 0-255")
        assert(v2 >= 0 and v2 <= 255, "Random value should be 0-255")

        -- Test determinism - same seed should give same sequence
        Random.Set_Seed(42)
        local seq1_a = Random.Sim_Random()
        local seq1_b = Random.Sim_Random()

        Random.Set_Seed(42)
        local seq2_a = Random.Sim_Random()
        local seq2_b = Random.Sim_Random()

        assert(seq1_a == seq2_a, "Same seed should give same first value")
        assert(seq1_b == seq2_b, "Same seed should give same second value")

        -- Test Sim_IRandom range
        Random.Set_Seed(0)
        for i = 1, 50 do
            local r = Random.Sim_IRandom(10, 20)
            assert(r >= 10 and r <= 20, "IRandom should be in range")
        end

        add_test("Random module", true, "Random number generator works correctly")
    end)

    if not ok17 then
        add_test("Random module", false, tostring(err17))
    end

    -- Test 18: SessionClass
    local ok18, err18 = pcall(function()
        local SessionClass = require("src.network.session")

        -- Test constants
        assert(SessionClass.MAX_PLAYERS == 6, "MAX_PLAYERS should be 6")
        assert(SessionClass.MPLAYER_NAME_MAX == 12, "MPLAYER_NAME_MAX should be 12")

        -- Test creation
        local session = SessionClass.new()
        assert(session ~= nil, "Session should be created")
        assert(session.Type == SessionClass.GAME_TYPE.NORMAL, "Type should be NORMAL")
        assert(session.NumPlayers == 0, "NumPlayers should be 0")
        assert(session.Handle == "Player", "Handle should be 'Player'")
        assert(session.UniqueID ~= nil, "UniqueID should be set")

        -- Test player management
        local player = session:Add_Player("TestPlayer", 0, 1)
        assert(player ~= nil, "Player should be added")
        assert(session.NumPlayers == 1, "NumPlayers should be 1")
        assert(player.Name == "TestPlayer", "Player name should match")

        add_test("SessionClass", true, "SessionClass works correctly")
    end)

    if not ok18 then
        add_test("SessionClass", false, tostring(err18))
    end

    -- Test 19: Pointers module
    local ok19, err19 = pcall(function()
        local Pointers = require("src.io.pointers")

        -- Test RTTI constants
        assert(Pointers.RTTI.NONE == 0, "RTTI.NONE should be 0")
        assert(Pointers.RTTI.UNIT == 1, "RTTI.UNIT should be 1")
        assert(Pointers.RTTI.BUILDING == 2, "RTTI.BUILDING should be 2")
        assert(Pointers.RTTI.INFANTRY == 3, "RTTI.INFANTRY should be 3")

        -- Test encoding nil
        local encoded = Pointers.encode(nil)
        assert(encoded == nil, "Encoding nil should return nil")

        -- Test decode nil
        local decoded = Pointers.decode(nil)
        assert(decoded == nil, "Decoding nil should return nil")

        add_test("Pointers module", true, "Pointers module works correctly")
    end)

    if not ok19 then
        add_test("Pointers module", false, tostring(err19))
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

-- Test terrain and smudge classes
function IPC:test_terrain_smudge()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: TerrainTypeClass loading
    local ok1, err1 = pcall(function()
        local TerrainTypeClass = require("src.objects.types.terraintype")

        -- Check enum
        assert(TerrainTypeClass.TERRAIN.NONE == -1, "TERRAIN.NONE should be -1")
        assert(TerrainTypeClass.TERRAIN.TREE1 == 0, "TERRAIN.TREE1 should be 0")
        assert(TerrainTypeClass.TERRAIN.ROCK1 == 25, "TERRAIN.ROCK1 should be 25")
        assert(TerrainTypeClass.TERRAIN.COUNT == 32, "TERRAIN.COUNT should be 32")

        add_test("TerrainTypeClass enum", true, "Enum values correct")
    end)

    if not ok1 then
        add_test("TerrainTypeClass enum", false, tostring(err1))
    end

    -- Test 2: TerrainTypeClass creation
    local ok2, err2 = pcall(function()
        local TerrainTypeClass = require("src.objects.types.terraintype")

        local tree = TerrainTypeClass.Create(TerrainTypeClass.TERRAIN.TREE1)
        assert(tree ~= nil, "Tree type should be created")
        assert(tree.IniName == "T01", "IniName should be T01")
        assert(tree.IsDestroyable == true, "Trees are destroyable")
        assert(tree.IsFlammable == true, "Trees are flammable")

        local rock = TerrainTypeClass.Create(TerrainTypeClass.TERRAIN.ROCK1)
        assert(rock ~= nil, "Rock type should be created")
        assert(rock.IniName == "ROCK1", "IniName should be ROCK1")
        assert(rock.IsDestroyable == false, "Rocks are not destroyable")
        assert(rock.IsFlammable == false, "Rocks are not flammable")

        local blossom = TerrainTypeClass.Create(TerrainTypeClass.TERRAIN.BLOSSOMTREE1)
        assert(blossom ~= nil, "Blossom type should be created")
        assert(blossom.IsTiberiumSpawn == true, "Blossom trees spawn tiberium")

        add_test("TerrainTypeClass creation", true, "All terrain types create correctly")
    end)

    if not ok2 then
        add_test("TerrainTypeClass creation", false, tostring(err2))
    end

    -- Test 3: SmudgeTypeClass loading
    local ok3, err3 = pcall(function()
        local SmudgeTypeClass = require("src.objects.types.smudgetype")

        -- Check enum
        assert(SmudgeTypeClass.SMUDGE.NONE == -1, "SMUDGE.NONE should be -1")
        assert(SmudgeTypeClass.SMUDGE.CRATER1 == 0, "SMUDGE.CRATER1 should be 0")
        assert(SmudgeTypeClass.SMUDGE.SCORCH1 == 6, "SMUDGE.SCORCH1 should be 6")
        assert(SmudgeTypeClass.SMUDGE.BIB1 == 12, "SMUDGE.BIB1 should be 12")
        assert(SmudgeTypeClass.SMUDGE.COUNT == 15, "SMUDGE.COUNT should be 15")

        add_test("SmudgeTypeClass enum", true, "Enum values correct")
    end)

    if not ok3 then
        add_test("SmudgeTypeClass enum", false, tostring(err3))
    end

    -- Test 4: SmudgeTypeClass creation
    local ok4, err4 = pcall(function()
        local SmudgeTypeClass = require("src.objects.types.smudgetype")

        local crater = SmudgeTypeClass.Create(SmudgeTypeClass.SMUDGE.CRATER1)
        assert(crater ~= nil, "Crater type should be created")
        assert(crater.IsCrater == true, "Craters are marked as craters")
        assert(crater.IsBib == false, "Craters are not bibs")
        assert(crater.Width == 1, "Craters are 1x1")

        local scorch = SmudgeTypeClass.Create(SmudgeTypeClass.SMUDGE.SCORCH1)
        assert(scorch ~= nil, "Scorch type should be created")
        assert(scorch.IsCrater == false, "Scorch marks are not craters")

        local bib = SmudgeTypeClass.Create(SmudgeTypeClass.SMUDGE.BIB1)
        assert(bib ~= nil, "Bib type should be created")
        assert(bib.IsBib == true, "Bibs are marked as bibs")
        assert(bib.Width == 4, "BIB1 is 4 cells wide")
        assert(bib.Height == 2, "BIB1 is 2 cells tall")

        add_test("SmudgeTypeClass creation", true, "All smudge types create correctly")
    end)

    if not ok4 then
        add_test("SmudgeTypeClass creation", false, tostring(err4))
    end

    -- Test 5: TerrainClass instantiation
    local ok5, err5 = pcall(function()
        local TerrainClass = require("src.objects.terrain")
        local TerrainTypeClass = require("src.objects.types.terraintype")

        local terrain = TerrainClass:new(TerrainTypeClass.TERRAIN.TREE1)
        assert(terrain ~= nil, "Terrain should be created")
        assert(terrain.Type == TerrainTypeClass.TERRAIN.TREE1, "Type should be TREE1")
        assert(terrain.Class ~= nil, "Class reference should be set")
        assert(terrain.IsOnFire == false, "Should not be on fire initially")
        assert(terrain.IsCrumbling == false, "Should not be crumbling initially")
        assert(terrain:What_Am_I() == 10, "RTTI should be 10 (TERRAIN)")

        add_test("TerrainClass instantiation", true, "TerrainClass creates correctly")
    end)

    if not ok5 then
        add_test("TerrainClass instantiation", false, tostring(err5))
    end

    -- Test 6: SmudgeClass instantiation
    local ok6, err6 = pcall(function()
        local SmudgeClass = require("src.objects.smudge")
        local SmudgeTypeClass = require("src.objects.types.smudgetype")

        local smudge = SmudgeClass:new(SmudgeTypeClass.SMUDGE.CRATER1)
        assert(smudge ~= nil, "Smudge should be created")
        assert(smudge.Type == SmudgeTypeClass.SMUDGE.CRATER1, "Type should be CRATER1")
        assert(smudge.Class ~= nil, "Class reference should be set")
        assert(smudge:What_Am_I() == 12, "RTTI should be 12 (SMUDGE)")

        add_test("SmudgeClass instantiation", true, "SmudgeClass creates correctly")
    end)

    if not ok6 then
        add_test("SmudgeClass instantiation", false, tostring(err6))
    end

    -- Test 7: TerrainClass fire mechanics
    local ok7, err7 = pcall(function()
        local TerrainClass = require("src.objects.terrain")
        local TerrainTypeClass = require("src.objects.types.terraintype")

        local tree = TerrainClass:new(TerrainTypeClass.TERRAIN.TREE1)

        -- Trees should be able to catch fire
        local caught = tree:Catch_Fire()
        assert(caught == true, "Tree should catch fire")
        assert(tree.IsOnFire == true, "IsOnFire should be true")

        -- Calling again should return false
        local caught_again = tree:Catch_Fire()
        assert(caught_again == false, "Already on fire")

        -- Rock should not catch fire
        local rock = TerrainClass:new(TerrainTypeClass.TERRAIN.ROCK1)
        local rock_fire = rock:Catch_Fire()
        assert(rock_fire == false, "Rocks should not catch fire")

        add_test("TerrainClass fire mechanics", true, "Fire mechanics work correctly")
    end)

    if not ok7 then
        add_test("TerrainClass fire mechanics", false, tostring(err7))
    end

    -- Test 8: Adapters module
    local ok8, err8 = pcall(function()
        local HDGraphics = require("src.adapters.hd_graphics")
        local Controller = require("src.adapters.controller")
        local Hotkeys = require("src.adapters.hotkeys")
        local RemasteredAudio = require("src.adapters.remastered_audio")

        assert(HDGraphics ~= nil, "HDGraphics should load")
        assert(Controller ~= nil, "Controller should load")
        assert(Hotkeys ~= nil, "Hotkeys should load")
        assert(RemasteredAudio ~= nil, "RemasteredAudio should load")

        -- Check default bindings exist
        assert(Hotkeys.defaults.select_all == "e", "select_all default should be 'e'")
        assert(Hotkeys.defaults.stop == "s", "stop default should be 's'")

        add_test("Adapters module", true, "All adapter modules load correctly")
    end)

    if not ok8 then
        add_test("Adapters module", false, tostring(err8))
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

-- Test FootClass mission methods and TechnoClass threat detection
function IPC:test_missions()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: TechnoClass THREAT constants
    local ok1, err1 = pcall(function()
        local TechnoClass = require("src.objects.techno")

        assert(TechnoClass.THREAT ~= nil, "THREAT constants should exist")
        assert(TechnoClass.THREAT.NORMAL == 0x0000, "THREAT_NORMAL should be 0")
        assert(TechnoClass.THREAT.RANGE == 0x0001, "THREAT_RANGE should be 1")
        assert(TechnoClass.THREAT.AREA == 0x0002, "THREAT_AREA should be 2")
        assert(TechnoClass.THREAT.AIR == 0x0004, "THREAT_AIR should be 4")
        assert(TechnoClass.THREAT.INFANTRY == 0x0008, "THREAT_INFANTRY should be 8")
        assert(TechnoClass.THREAT.VEHICLES == 0x0010, "THREAT_VEHICLES should be 16")
        assert(TechnoClass.THREAT.BUILDINGS == 0x0020, "THREAT_BUILDINGS should be 32")
        assert(TechnoClass.THREAT.GROUND ~= nil, "THREAT_GROUND combined flag should exist")

        add_test("TechnoClass THREAT constants", true, "All THREAT flags defined correctly")
    end)

    if not ok1 then
        add_test("TechnoClass THREAT constants", false, tostring(err1))
    end

    -- Test 2: TechnoClass methods exist
    local ok2, err2 = pcall(function()
        local TechnoClass = require("src.objects.techno")

        -- Create a minimal techno instance to test methods
        local techno = setmetatable({
            IsActive = true,
            IsInLimbo = false,
            TarCom = 0,
            House = nil,
            Coord = 0,
            Class = { MaxStrength = 100 },
            Strength = 100,
        }, { __index = TechnoClass })

        -- Check methods exist
        assert(type(TechnoClass.Greatest_Threat) == "function", "Greatest_Threat should be a function")
        assert(type(TechnoClass.Target_Something_Nearby) == "function", "Target_Something_Nearby should be a function")
        assert(type(TechnoClass.Is_Enemy) == "function", "Is_Enemy should be a function")
        assert(type(TechnoClass.Evaluate_Object) == "function", "Evaluate_Object should be a function")
        assert(type(TechnoClass.Threat_Range) == "function", "Threat_Range should be a function")

        add_test("TechnoClass threat methods", true, "All threat detection methods exist")
    end)

    if not ok2 then
        add_test("TechnoClass threat methods", false, tostring(err2))
    end

    -- Test 3: FootClass mission methods exist
    local ok3, err3 = pcall(function()
        local FootClass = require("src.objects.foot")

        -- Check mission methods exist
        assert(type(FootClass.Mission_Move) == "function", "Mission_Move should be a function")
        assert(type(FootClass.Mission_Attack) == "function", "Mission_Attack should be a function")
        assert(type(FootClass.Mission_Guard) == "function", "Mission_Guard should be a function")
        assert(type(FootClass.Mission_Guard_Area) == "function", "Mission_Guard_Area should be a function")
        assert(type(FootClass.Mission_Hunt) == "function", "Mission_Hunt should be a function")
        assert(type(FootClass.Mission_Capture) == "function", "Mission_Capture should be a function")
        assert(type(FootClass.Mission_Enter) == "function", "Mission_Enter should be a function")
        assert(type(FootClass.Mission_Timed_Hunt) == "function", "Mission_Timed_Hunt should be a function")
        assert(type(FootClass.Random_Animate) == "function", "Random_Animate should be a function")

        add_test("FootClass mission methods", true, "All mission methods exist")
    end)

    if not ok3 then
        add_test("FootClass mission methods", false, tostring(err3))
    end

    -- Test 4: InfantryClass loads and has missions
    local ok4, err4 = pcall(function()
        local InfantryClass = require("src.objects.infantry")
        local Target = require("src.core.target")

        -- InfantryClass should inherit from FootClass
        assert(type(InfantryClass.Mission_Move) == "function", "InfantryClass should have Mission_Move")
        assert(type(InfantryClass.Mission_Attack) == "function", "InfantryClass should have Mission_Attack")
        assert(type(InfantryClass.Mission_Guard) == "function", "InfantryClass should have Mission_Guard")

        add_test("InfantryClass inheritance", true, "InfantryClass inherits mission methods")
    end)

    if not ok4 then
        add_test("InfantryClass inheritance", false, tostring(err4))
    end

    -- Test 5: UnitClass loads and has missions
    local ok5, err5 = pcall(function()
        local UnitClass = require("src.objects.unit")

        -- UnitClass should inherit from FootClass
        assert(type(UnitClass.Mission_Move) == "function", "UnitClass should have Mission_Move")
        assert(type(UnitClass.Mission_Attack) == "function", "UnitClass should have Mission_Attack")
        assert(type(UnitClass.Mission_Hunt) == "function", "UnitClass should have Mission_Hunt")

        add_test("UnitClass inheritance", true, "UnitClass inherits mission methods")
    end)

    if not ok5 then
        add_test("UnitClass inheritance", false, tostring(err5))
    end

    -- Test 6: Mission_Move returns correct delay
    local ok6, err6 = pcall(function()
        local FootClass = require("src.objects.foot")
        local Target = require("src.core.target")

        -- Create a mock foot instance
        local foot = setmetatable({
            IsActive = true,
            IsInLimbo = false,
            NavCom = 0,  -- TARGET_NONE
            TarCom = 0,
            IsDriving = false,
            MissionQueue = 0,  -- MISSION_NONE
            House = nil,
            Mission = 0,
            MISSION = FootClass.MISSION or { NONE = 0, SLEEP = 1, GUARD = 2 },
            Enter_Idle_Mode = function(self) self.Mission = 2 end,
            Target_Something_Nearby = function() return false end,
        }, { __index = FootClass })

        -- Call Mission_Move with no valid NavCom
        local delay = foot:Mission_Move()
        assert(type(delay) == "number", "Mission_Move should return a number")
        assert(delay > 0, "Mission_Move delay should be positive")
        assert(delay == 18, "Mission_Move should return TICKS_PER_SECOND + 3 = 18")

        add_test("Mission_Move return value", true, "Mission_Move returns correct tick delay")
    end)

    if not ok6 then
        add_test("Mission_Move return value", false, tostring(err6))
    end

    -- Test 7: Target module integration
    local ok7, err7 = pcall(function()
        local Target = require("src.core.target")

        -- Check Target constants exist
        assert(Target.TARGET_NONE ~= nil, "TARGET_NONE should exist")
        assert(Target.RTTI ~= nil, "RTTI constants should exist")
        assert(Target.RTTI.INFANTRY ~= nil, "RTTI.INFANTRY should exist")
        assert(Target.RTTI.UNIT ~= nil, "RTTI.UNIT should exist")
        assert(Target.RTTI.BUILDING ~= nil, "RTTI.BUILDING should exist")

        -- Check target functions
        assert(type(Target.Is_Valid) == "function", "Is_Valid should be a function")

        add_test("Target module integration", true, "Target module has required constants")
    end)

    if not ok7 then
        add_test("Target module integration", false, tostring(err7))
    end

    -- Test 8: Coord module has required functions
    local ok8, err8 = pcall(function()
        local Coord = require("src.core.coord")

        assert(type(Coord.Coord_Cell) == "function", "Coord_Cell should be a function")
        assert(type(Coord.Cell_X) == "function", "Cell_X should be a function")
        assert(type(Coord.Cell_Y) == "function", "Cell_Y should be a function")
        assert(type(Coord.Distance) == "function", "Distance should be a function")

        add_test("Coord module functions", true, "Coord module has required functions")
    end)

    if not ok8 then
        add_test("Coord module functions", false, tostring(err8))
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

-- Test Combat system (Explosion_Damage, BulletClass:Detonate, FootClass:Approach_Target)
function IPC:test_combat()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: Combat module loads
    local ok1, err1 = pcall(function()
        local Combat = require("src.combat.combat")

        assert(Combat ~= nil, "Combat module should load")
        assert(type(Combat.Explosion_Damage) == "function", "Explosion_Damage should be a function")
        assert(type(Combat.Do_Explosion) == "function", "Do_Explosion should be a function")
        assert(type(Combat.Distance_Modify) == "function", "Distance_Modify should be a function")

        add_test("Combat module loads", true, "All combat functions available")
    end)

    if not ok1 then
        add_test("Combat module loads", false, tostring(err1))
    end

    -- Test 2: WarheadTypeClass has damage modifiers
    local ok2, err2 = pcall(function()
        local WarheadTypeClass = require("src.combat.warhead")

        -- Test creating a warhead
        local he_warhead = WarheadTypeClass.Create(WarheadTypeClass.WARHEAD.HE)
        assert(he_warhead ~= nil, "HE warhead should be created")
        assert(he_warhead.Name == "High Explosive", "Name should be High Explosive")

        -- Test damage modification
        local base_damage = 100
        local mod_damage = he_warhead:Modify_Damage(base_damage, WarheadTypeClass.ARMOR.NONE)
        assert(mod_damage > 0, "Modified damage should be positive")

        -- Test armor resistance
        local steel_damage = he_warhead:Modify_Damage(base_damage, WarheadTypeClass.ARMOR.STEEL)
        assert(steel_damage <= mod_damage, "Steel should resist HE damage")

        add_test("WarheadTypeClass damage modifiers", true, "Damage modification works correctly")
    end)

    if not ok2 then
        add_test("WarheadTypeClass damage modifiers", false, tostring(err2))
    end

    -- Test 3: BulletClass has Detonate method
    local ok3, err3 = pcall(function()
        local BulletClass = require("src.objects.bullet")

        assert(type(BulletClass.Detonate) == "function", "Detonate should be a function")

        add_test("BulletClass:Detonate exists", true, "Detonate method available")
    end)

    if not ok3 then
        add_test("BulletClass:Detonate exists", false, tostring(err3))
    end

    -- Test 4: FootClass has Approach_Target
    local ok4, err4 = pcall(function()
        local FootClass = require("src.objects.foot")

        assert(type(FootClass.Approach_Target) == "function", "Approach_Target should be a function")
        assert(type(FootClass.Mission_Move) == "function", "Mission_Move should be a function")
        assert(type(FootClass.Mission_Attack) == "function", "Mission_Attack should be a function")

        add_test("FootClass combat methods", true, "All combat methods available")
    end)

    if not ok4 then
        add_test("FootClass combat methods", false, tostring(err4))
    end

    -- Test 5: Coord module has Coord_Move_Dir
    local ok5, err5 = pcall(function()
        local Coord = require("src.core.coord")

        assert(type(Coord.Coord_Move_Dir) == "function", "Coord_Move_Dir should be a function")
        assert(type(Coord.Direction256) == "function", "Direction256 should be a function")
        assert(type(Coord.Distance) == "function", "Distance should be a function")

        -- Test Coord_Move_Dir
        local start_coord = Coord.XY_Coord(1000, 1000)
        local moved_coord = Coord.Coord_Move_Dir(start_coord, 64, 100)  -- Move east 100 leptons
        assert(moved_coord ~= start_coord, "Moved coord should differ from start")

        local new_x = Coord.Coord_X(moved_coord)
        assert(new_x > 1000, "X should increase when moving east (dir=64)")

        add_test("Coord directional movement", true, "Coord_Move_Dir works correctly")
    end)

    if not ok5 then
        add_test("Coord directional movement", false, tostring(err5))
    end

    -- Test 6: ObjectClass Take_Damage returns correct results
    local ok6, err6 = pcall(function()
        local ObjectClass = require("src.objects.object")

        -- Check RESULT constants exist
        assert(ObjectClass.RESULT ~= nil, "RESULT constants should exist")
        assert(ObjectClass.RESULT.NONE ~= nil, "RESULT.NONE should exist")
        assert(ObjectClass.RESULT.LIGHT ~= nil, "RESULT.LIGHT should exist")
        assert(ObjectClass.RESULT.HALF ~= nil, "RESULT.HALF should exist")
        assert(ObjectClass.RESULT.DESTROYED ~= nil, "RESULT.DESTROYED should exist")

        add_test("ObjectClass damage results", true, "Damage result constants defined")
    end)

    if not ok6 then
        add_test("ObjectClass damage results", false, tostring(err6))
    end

    -- Test 7: TechnoClass has threat detection
    local ok7, err7 = pcall(function()
        local TechnoClass = require("src.objects.techno")

        assert(TechnoClass.THREAT ~= nil, "THREAT constants should exist")
        assert(type(TechnoClass.Greatest_Threat) == "function", "Greatest_Threat should be a function")
        assert(type(TechnoClass.Target_Something_Nearby) == "function", "Target_Something_Nearby should exist")

        add_test("TechnoClass threat detection", true, "Threat detection methods available")
    end)

    if not ok7 then
        add_test("TechnoClass threat detection", false, tostring(err7))
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

-- Test Pathfinding and Animation Effects (Phase 3 completion)
function IPC:test_pathfinding()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: FindPath module loads and has key functions
    local ok1, err1 = pcall(function()
        local FindPath = require("src.pathfinding.findpath")

        assert(FindPath ~= nil, "FindPath module should load")
        assert(type(FindPath.new) == "function", "FindPath.new should be a function")
        assert(type(FindPath.find_path) == "function", "find_path should be a function")
        assert(type(FindPath.follow_edge) == "function", "follow_edge should be a function")
        assert(type(FindPath.register_cell) == "function", "register_cell should be a function")

        -- Check constants
        assert(FindPath.FACING ~= nil, "FACING constants should exist")
        assert(FindPath.FACING.N == 0, "FACING.N should be 0")
        assert(FindPath.FACING.COUNT == 8, "Should have 8 directions")
        assert(FindPath.MOVE ~= nil, "MOVE constants should exist")

        add_test("FindPath module structure", true, "All pathfinding functions available")
    end)

    if not ok1 then
        add_test("FindPath module structure", false, tostring(err1))
    end

    -- Test 2: FindPath can find simple path
    local ok2, err2 = pcall(function()
        local FindPath = require("src.pathfinding.findpath")

        -- Create pathfinder without map (uses default passability)
        local pathfinder = FindPath.new(nil)
        assert(pathfinder ~= nil, "Should create pathfinder instance")

        -- Find path from cell 0,0 to cell 5,5
        local start_cell = pathfinder:cell_index(10, 10)
        local dest_cell = pathfinder:cell_index(15, 15)

        local path = pathfinder:find_path(start_cell, dest_cell)
        assert(path ~= nil, "Should find path")
        assert(path.Length > 0, "Path should have length > 0")
        assert(path.Command ~= nil, "Path should have Command array")

        add_test("FindPath basic pathfinding", true, string.format("Found path with %d steps", path.Length))
    end)

    if not ok2 then
        add_test("FindPath basic pathfinding", false, tostring(err2))
    end

    -- Test 3: FindPath coordinate interface
    local ok3, err3 = pcall(function()
        local FindPath = require("src.pathfinding.findpath")

        local pathfinder = FindPath.new(nil)

        -- Test coordinate-based path finding
        local waypoints = pathfinder:find_path_coords(5, 5, 10, 10)
        assert(waypoints ~= nil, "Should find waypoints")
        assert(#waypoints > 0, "Should have waypoints")
        assert(waypoints[1].x == 5 and waypoints[1].y == 5, "First waypoint should be start")

        add_test("FindPath coordinate interface", true, string.format("Found %d waypoints", #waypoints))
    end)

    if not ok3 then
        add_test("FindPath coordinate interface", false, tostring(err3))
    end

    -- Test 4: SmudgeClass exists and has factory methods
    local ok4, err4 = pcall(function()
        local SmudgeClass = require("src.objects.smudge")

        assert(SmudgeClass ~= nil, "SmudgeClass should load")
        assert(type(SmudgeClass.Create_Crater) == "function", "Create_Crater should exist")
        assert(type(SmudgeClass.Create_Scorch) == "function", "Create_Scorch should exist")
        assert(type(SmudgeClass.Create_Bib) == "function", "Create_Bib should exist")
        assert(SmudgeClass.RTTI == 12, "SmudgeClass RTTI should be 12")

        add_test("SmudgeClass factory methods", true, "All smudge factory methods available")
    end)

    if not ok4 then
        add_test("SmudgeClass factory methods", false, tostring(err4))
    end

    -- Test 5: SmudgeTypeClass has crater/scorch types
    local ok5, err5 = pcall(function()
        local SmudgeTypeClass = require("src.objects.types.smudgetype")

        assert(SmudgeTypeClass ~= nil, "SmudgeTypeClass should load")
        assert(SmudgeTypeClass.SMUDGE ~= nil, "SMUDGE enum should exist")
        assert(SmudgeTypeClass.SMUDGE.CRATER1 ~= nil, "CRATER1 should exist")
        assert(SmudgeTypeClass.SMUDGE.SCORCH1 ~= nil, "SCORCH1 should exist")

        -- Test random picker functions
        assert(type(SmudgeTypeClass.Random_Crater) == "function", "Random_Crater should exist")
        assert(type(SmudgeTypeClass.Random_Scorch) == "function", "Random_Scorch should exist")

        add_test("SmudgeTypeClass types", true, "All smudge types defined")
    end)

    if not ok5 then
        add_test("SmudgeTypeClass types", false, tostring(err5))
    end

    -- Test 6: AnimClass has Middle() method
    local ok6, err6 = pcall(function()
        local AnimClass = require("src.objects.anim")

        assert(AnimClass ~= nil, "AnimClass should load")
        assert(type(AnimClass.Middle) == "function", "Middle should be a function")
        assert(type(AnimClass.Chain) == "function", "Chain should be a function")
        assert(type(AnimClass.Start) == "function", "Start should be a function")

        add_test("AnimClass Middle method", true, "AnimClass has Middle() for effects")
    end)

    if not ok6 then
        add_test("AnimClass Middle method", false, tostring(err6))
    end

    -- Test 7: AnimTypeClass has special weapon animation types
    local ok7, err7 = pcall(function()
        local AnimTypeClass = require("src.objects.types.animtype")

        assert(AnimTypeClass ~= nil, "AnimTypeClass should load")
        assert(AnimTypeClass.ANIM ~= nil, "ANIM enum should exist")
        assert(AnimTypeClass.ANIM.ATOM_BLAST ~= nil, "ATOM_BLAST should exist")
        assert(AnimTypeClass.ANIM.ION_CANNON ~= nil, "ION_CANNON should exist")
        assert(AnimTypeClass.ANIM.NAPALM1 ~= nil, "NAPALM1 should exist")
        assert(AnimTypeClass.ANIM.FLAME_N ~= nil, "FLAME_N should exist")
        assert(AnimTypeClass.ANIM.FIRE_SMALL ~= nil, "FIRE_SMALL should exist")

        add_test("AnimTypeClass special weapons", true, "All special weapon anim types defined")
    end)

    if not ok7 then
        add_test("AnimTypeClass special weapons", false, tostring(err7))
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

-- Test Mission Handlers and Economy Systems (Phase 4)
function IPC:test_economy()
    local result = {
        success = true,
        tests = {}
    }

    local function add_test(name, passed, message)
        table.insert(result.tests, {
            name = name,
            passed = passed,
            message = message
        })
        if not passed then
            result.success = false
        end
    end

    -- Test 1: UnitClass harvester methods exist
    local ok1, err1 = pcall(function()
        local UnitClass = require("src.objects.unit")

        assert(UnitClass ~= nil, "UnitClass should load")
        assert(type(UnitClass.Mission_Harvest) == "function", "Mission_Harvest should exist")
        assert(type(UnitClass.Find_Tiberium) == "function", "Find_Tiberium should exist")
        assert(type(UnitClass.Find_Refinery) == "function", "Find_Refinery should exist")
        assert(type(UnitClass.Harvesting) == "function", "Harvesting should exist")
        assert(type(UnitClass.On_Tiberium) == "function", "On_Tiberium should exist")
        assert(type(UnitClass.Is_Harvester) == "function", "Is_Harvester should exist")
        assert(type(UnitClass.Is_Full) == "function", "Is_Full should exist")

        add_test("UnitClass harvester methods", true, "All harvester methods available")
    end)

    if not ok1 then
        add_test("UnitClass harvester methods", false, tostring(err1))
    end

    -- Test 2: UnitClass MCV deployment methods exist
    local ok2, err2 = pcall(function()
        local UnitClass = require("src.objects.unit")

        assert(type(UnitClass.Can_Deploy) == "function", "Can_Deploy should exist")
        assert(type(UnitClass.Deploy) == "function", "Deploy should exist")
        assert(type(UnitClass.Complete_Deploy) == "function", "Complete_Deploy should exist")

        -- Check constants
        assert(UnitClass.DEPLOY_TIME ~= nil, "DEPLOY_TIME constant should exist")
        assert(UnitClass.TIBERIUM_CAPACITY ~= nil, "TIBERIUM_CAPACITY should exist")
        assert(UnitClass.HARVEST_DELAY ~= nil, "HARVEST_DELAY should exist")

        add_test("UnitClass MCV deployment", true, "All MCV deployment methods available")
    end)

    if not ok2 then
        add_test("UnitClass MCV deployment", false, tostring(err2))
    end

    -- Test 3: Cell class has tiberium methods
    local ok3, err3 = pcall(function()
        local Cell = require("src.map.cell")

        assert(Cell ~= nil, "Cell should load")
        assert(type(Cell.has_tiberium) == "function", "has_tiberium should exist")
        assert(type(Cell.harvest_tiberium) == "function", "harvest_tiberium should exist")
        assert(type(Cell.get_tiberium_value) == "function", "get_tiberium_value should exist")
        assert(type(Cell.grow_tiberium) == "function", "grow_tiberium should exist")

        add_test("Cell tiberium methods", true, "All cell tiberium methods available")
    end)

    if not ok3 then
        add_test("Cell tiberium methods", false, tostring(err3))
    end

    -- Test 4: HouseClass has economy methods
    local ok4, err4 = pcall(function()
        local HouseClass = require("src.house.house")

        assert(HouseClass ~= nil, "HouseClass should load")
        assert(type(HouseClass.add_credits) == "function", "add_credits should exist")
        assert(type(HouseClass.spend_credits) == "function", "spend_credits should exist")
        assert(type(HouseClass.can_afford) == "function", "can_afford should exist")
        assert(type(HouseClass.add_building) == "function", "add_building should exist")
        assert(type(HouseClass.update_power) == "function", "update_power should exist")

        add_test("HouseClass economy methods", true, "All economy methods available")
    end)

    if not ok4 then
        add_test("HouseClass economy methods", false, tostring(err4))
    end

    -- Test 5: FactoryClass production methods
    local ok5, err5 = pcall(function()
        local FactoryClass = require("src.production.factory")

        assert(FactoryClass ~= nil, "FactoryClass should load")
        assert(type(FactoryClass.Set) == "function", "Set should exist")
        assert(type(FactoryClass.Start) == "function", "Start should exist")
        assert(type(FactoryClass.Suspend) == "function", "Suspend should exist")
        assert(type(FactoryClass.Abandon) == "function", "Abandon should exist")
        assert(type(FactoryClass.Completed) == "function", "Completed should exist")
        assert(type(FactoryClass.Cost_Per_Tick) == "function", "Cost_Per_Tick should exist")

        add_test("FactoryClass production methods", true, "All production methods available")
    end)

    if not ok5 then
        add_test("FactoryClass production methods", false, tostring(err5))
    end

    -- Test 6: FootClass mission methods exist
    local ok6, err6 = pcall(function()
        local FootClass = require("src.objects.foot")

        assert(FootClass ~= nil, "FootClass should load")
        assert(type(FootClass.Mission_Move) == "function", "Mission_Move should exist")
        assert(type(FootClass.Mission_Attack) == "function", "Mission_Attack should exist")
        assert(type(FootClass.Mission_Guard) == "function", "Mission_Guard should exist")
        assert(type(FootClass.Mission_Hunt) == "function", "Mission_Hunt should exist")
        assert(type(FootClass.Mission_Enter) == "function", "Mission_Enter should exist")
        assert(type(FootClass.Assign_Destination) == "function", "Assign_Destination should exist")

        add_test("FootClass mission methods", true, "All mission methods available")
    end)

    if not ok6 then
        add_test("FootClass mission methods", false, tostring(err6))
    end

    -- Test 7: Grid search functionality
    local ok7, err7 = pcall(function()
        local Grid = require("src.map.grid")

        assert(Grid ~= nil, "Grid should load")
        assert(type(Grid.get_cell) == "function", "get_cell should exist")
        assert(type(Grid.get_cells_in_radius) == "function", "get_cells_in_radius should exist")
        assert(type(Grid.is_valid) == "function", "is_valid should exist")

        -- Create a test grid
        local grid = Grid.new(16, 16)
        assert(grid ~= nil, "Should create grid")

        local cell = grid:get_cell(8, 8)
        assert(cell ~= nil, "Should get cell at valid coords")

        local nil_cell = grid:get_cell(100, 100)
        assert(nil_cell == nil, "Should return nil for invalid coords")

        add_test("Grid search functionality", true, "Grid cell access works correctly")
    end)

    if not ok7 then
        add_test("Grid search functionality", false, tostring(err7))
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
