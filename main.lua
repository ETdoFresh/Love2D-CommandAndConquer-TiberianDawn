--[[
    Command & Conquer: Tiberian Dawn - Love2D Port
    Main entry point

    A faithful port of Command & Conquer: Tiberian Dawn to Love2D.
    Requires C&C Remastered Collection assets for full functionality.

    License: Fan project - EA/Westwood trademark attribution required
]]

-- Global game instance
local Game = require("src.core.game")
local IPC = require("src.debug.ipc")
local game = nil
local ipc = nil
local tool_mode = false

function love.load(arg)
    -- Check for tool mode (extract, convert-shp, convert-aud)
    local tool_commands = {extract = true, ["convert-shp"] = true, ["convert-aud"] = true, help = true}
    if arg and #arg > 0 and tool_commands[arg[1]] then
        tool_mode = true
        local ToolRunner = require("run_tool")
        ToolRunner.run(arg)
        print("")
        print("Press any key to exit or close the window...")
        return
    end

    -- Set random seed
    math.randomseed(os.time())

    -- Set default font
    love.graphics.setFont(love.graphics.newFont(14))

    -- Create and initialize game
    game = Game.new()
    game:init()

    -- Initialize IPC system for CLI control
    ipc = IPC.new(game)

    -- Print startup info
    print("===========================================")
    print("  Command & Conquer: Tiberian Dawn")
    print("  Love2D Port - Phase 1 Foundation")
    print("===========================================")
    print("")
    print("Controls:")
    print("  WASD - Pan camera")
    print("  +/- or Mouse wheel - Zoom")
    print("  Left click - Select units")
    print("  Shift+click - Add to selection")
    print("  Right click - Move command")
    print("  1-9 - Select control group")
    print("  Ctrl+1-9 - Assign control group")
    print("  TAB - Toggle sidebar")
    print("  ESC - Pause/Menu")
    print("  F5 - Quick save")
    print("  F9 - Quick load")
    print("")
    print("Gamepad Controls:")
    print("  Left stick - Move cursor")
    print("  Right stick - Pan camera")
    print("  A button - Select/Confirm")
    print("  X button - Move command")
    print("  Start - Pause")
    print("  LB/RB - Zoom out/in")
    print("")
end

function love.update(dt)
    if tool_mode then return end

    -- Update IPC system (check for commands)
    if ipc then
        ipc:update(dt)
    end

    if game then
        game:update(dt)
    end
end

function love.draw()
    if tool_mode then
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Tool mode - see console for output", 20, 20)
        love.graphics.print("Press any key to exit...", 20, 40)
        return
    end

    if game then
        game:draw()
    end
end

function love.keypressed(key)
    if tool_mode then
        love.event.quit()
        return
    end

    if key == "f11" then
        -- Toggle fullscreen
        love.window.setFullscreen(not love.window.getFullscreen())
    elseif key == "f12" then
        -- Screenshot
        local screenshot = love.graphics.newScreenshot()
        screenshot:encode("png", "screenshot_" .. os.time() .. ".png")
        print("Screenshot saved!")
    else
        if game then
            game:keypressed(key)
        end
    end
end

function love.mousepressed(x, y, button)
    if game then
        game:mousepressed(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if game then
        game:mousemoved(x, y, dx, dy)
    end
end

function love.mousereleased(x, y, button)
    if game then
        game:mousereleased(x, y, button)
    end
end

function love.wheelmoved(x, y)
    if game then
        game:wheelmoved(x, y)
    end
end

function love.resize(w, h)
    if game then
        game:resize(w, h)
    end
end

function love.gamepadpressed(joystick, button)
    if game then
        game:gamepadpressed(joystick, button)
    end
end

function love.joystickadded(joystick)
    print("Gamepad connected: " .. joystick:getName())
end

function love.joystickremoved(joystick)
    print("Gamepad disconnected")
    if game and game.gamepad == joystick then
        game.gamepad = nil
        game.use_gamepad_cursor = false
    end
end

function love.quit()
    -- Cleanup IPC
    if ipc then
        ipc:cleanup()
    end

    if game then
        game:quit()
    end
    print("Game closed.")
    return false
end

-- Error handler
function love.errorhandler(msg)
    print("Error: " .. tostring(msg))
    print(debug.traceback())
    return nil  -- Use default Love2D error screen
end
