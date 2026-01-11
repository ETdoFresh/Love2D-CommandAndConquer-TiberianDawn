#!/usr/bin/env lua
--[[
    IPC Client - Send commands to running Love2D game

    Usage:
        lua ipc_client.lua <instance_id> <command> [args...]
        lua ipc_client.lua 1768144000 state          -- Get game state
        lua ipc_client.lua 1768144000 input return   -- Press Enter key
        lua ipc_client.lua 1768144000 screenshot     -- Take screenshot

    The instance_id is printed as IPC_ID=<id> when the game starts (to stdout).
]]

local function get_temp_dir()
    return os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

local function read_file(path)
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        return content
    end
    return nil
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
        return true
    end
    return false
end

local function dir_exists(path)
    -- Try to open a file in the directory
    local handle
    if package.config:sub(1,1) == '\\' then
        handle = io.popen('if exist "' .. path .. '" (echo 1) else (echo 0)')
    else
        handle = io.popen('[ -d "' .. path .. '" ] && echo 1 || echo 0')
    end
    if handle then
        local result = handle:read("*l")
        handle:close()
        return result == "1"
    end
    return false
end

local function send_command(instance_id, command)
    local temp = get_temp_dir()
    local ipc_dir = temp .. "/love2d_ipc_" .. instance_id
    local command_file = ipc_dir .. "/command.txt"
    local response_file = ipc_dir .. "/response.json"

    -- Check if instance directory exists
    if not dir_exists(ipc_dir) then
        print("Error: Instance " .. instance_id .. " not found")
        print("IPC directory: " .. ipc_dir)
        return nil
    end

    -- Clear old response
    os.remove(response_file)

    -- Write command
    if not write_file(command_file, command) then
        print("Error: Could not write command file")
        return nil
    end

    -- Wait for response (with timeout)
    local timeout = 5  -- seconds
    local start = os.clock()
    local response = nil

    while os.clock() - start < timeout do
        response = read_file(response_file)
        if response then
            break
        end
        -- Small delay
        local wait_until = os.clock() + 0.05
        while os.clock() < wait_until do end
    end

    if not response then
        print("Warning: No response received (timeout)")
    end

    return response
end

-- Main
local args = {...}

if #args < 2 then
    print("Usage: lua ipc_client.lua <instance_id> <command> [args...]")
    print("")
    print("The instance_id is printed as IPC_ID=<id> when the game starts.")
    print("")
    print("Commands:")
    print("  <id> input <key>        - Simulate key press")
    print("  <id> gamepad <button>   - Simulate gamepad button")
    print("  <id> type <text>        - Type text")
    print("  <id> screenshot [path]  - Take screenshot")
    print("  <id> state              - Get game state")
    print("  <id> pause              - Pause game")
    print("  <id> resume             - Resume game")
    print("  <id> tick [n]           - Advance n ticks")
    print("  <id> quit               - Quit game")
    print("  <id> help               - Show available commands")
    os.exit(1)
end

local instance_id = args[1]
table.remove(args, 1)

-- Build command from remaining args
local command = table.concat(args, " ")

-- Send command
local response = send_command(instance_id, command)

if response then
    print(response)
end
