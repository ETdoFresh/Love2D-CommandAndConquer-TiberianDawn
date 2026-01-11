--[[
    Command & Conquer: Tiberian Dawn - Love2D Port
    Configuration file
]]

function love.conf(t)
    t.identity = "cnc-tiberian-dawn"
    t.version = "11.5"
    t.console = true  -- Enable console for debugging

    t.window.title = "Command & Conquer: Tiberian Dawn"
    t.window.icon = nil
    t.window.width = 640
    t.window.height = 400
    t.window.borderless = false
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 200
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.display = 1
    t.window.highdpi = false
    t.window.x = nil
    t.window.y = nil

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false  -- Not using Box2D
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = true
    t.modules.timer = true
    t.modules.touch = true
    t.modules.video = true
    t.modules.window = true
end
