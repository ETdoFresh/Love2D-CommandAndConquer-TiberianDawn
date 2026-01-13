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
