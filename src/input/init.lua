--[[
    Input Module - Exports all input handling components
    Handles keyboard, mouse, and controller input with rebindable hotkeys
]]

local Input = {
    Keyboard = require("src.input.keyboard"),
    Mouse = require("src.input.mouse"),
    Controller = require("src.input.controller"),
    Commands = require("src.input.commands")
}

return Input
