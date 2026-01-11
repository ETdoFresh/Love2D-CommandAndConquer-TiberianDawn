--[[
    Command & Conquer: Tiberian Dawn - Love2D Port
    Main Source Module - Exports all game components
]]

local Src = {
    -- Core
    Core = {
        Constants = require("src.core.constants"),
        Events = require("src.core.events"),
        Pool = require("src.core.pool"),
        Game = require("src.core.game")
    },

    -- Utilities
    Util = {
        Vector = require("src.util.vector"),
        Direction = require("src.util.direction"),
        Random = require("src.util.random"),
        Serialize = require("src.util.serialize")
    },

    -- ECS
    ECS = require("src.ecs"),

    -- Map
    Map = require("src.map"),

    -- Systems
    Systems = require("src.systems"),

    -- UI
    UI = require("src.ui"),

    -- Input
    Input = require("src.input"),

    -- Editor
    Editor = require("src.editor"),

    -- Scenario/Campaign
    Scenario = require("src.scenario"),

    -- Network
    Network = require("src.network")
}

return Src
