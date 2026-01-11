--[[
    Scenario Module - Exports scenario/campaign components
]]

local Scenario = {
    TriggerSystem = require("src.scenario.trigger"),
    TeamSystem = require("src.scenario.team"),
    Loader = require("src.scenario.loader")
}

return Scenario
