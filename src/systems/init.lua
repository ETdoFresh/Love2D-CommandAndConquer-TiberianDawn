--[[
    Systems Module - Exports all game systems
]]

local Systems = {
    RenderSystem = require("src.systems.render_system"),
    SelectionSystem = require("src.systems.selection_system"),
    MovementSystem = require("src.systems.movement_system")
}

return Systems
