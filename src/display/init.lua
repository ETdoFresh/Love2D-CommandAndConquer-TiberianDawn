--[[
    Display Module - Screen and view hierarchy

    This module exports the display class hierarchy:
        GScreenClass
            └── DisplayClass
                    └── RadarClass
                            └── ScrollClass
                                    └── MouseClass

    The MouseClass is typically what you instantiate for the game display,
    as it inherits all functionality from the chain.

    Usage:
        local Display = require("src.display")
        local screen = Display.MouseClass:new()
        screen:One_Time()
        screen:Init()
]]

local Display = {
    -- Base screen class
    GScreenClass = require("src.display.gscreen"),

    -- Tactical display with layers
    DisplayClass = require("src.display.display"),

    -- Minimap/radar
    RadarClass = require("src.display.radar"),

    -- Edge scrolling
    ScrollClass = require("src.display.scroll"),

    -- Mouse cursor handling (top of hierarchy)
    MouseClass = require("src.display.mouse"),
}

return Display
