--[[
    House Module - Exports faction/player management components
    Handles houses, economy, tech trees, and AI control
]]

local House = {
    House = require("src.house.house"),
    Economy = require("src.house.economy"),
    TechTree = require("src.house.tech_tree"),
    AIController = require("src.house.ai_controller")
}

return House
