--[[
    Core module - exports all core functionality
]]

local Core = {
    Constants = require("src.core.constants"),
    Events = require("src.core.events"),
    Pool = require("src.core.pool"),
    Game = require("src.core.game")
}

return Core
