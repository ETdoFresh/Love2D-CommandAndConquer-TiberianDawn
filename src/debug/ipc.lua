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

    elseif cmd == "help" then
        response.commands = {
            "input <key> - Simulate key press",
            "gamepad <button> - Simulate gamepad button",
            "type <text> - Type text string",
            "screenshot [path] - Take screenshot",
            "state - Get game state JSON",
            "pause - Pause game",
            "resume - Resume game",
            "tick [n] - Advance n ticks",
            "quit - Quit game",
            "eval <lua> - Execute Lua code",
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
        -- Simulate key press and release
        if self.game then
            self.game:keypressed(key)
        end
        love.keypressed(key)
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
