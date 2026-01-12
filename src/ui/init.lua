--[[
    UI Module - Exports all UI components
]]

local UI = {
    Sidebar = require("src.ui.sidebar"),
    MainMenu = require("src.ui.main_menu"),
    Radar = require("src.ui.radar"),
    CampaignMap = require("src.ui.campaign_map"),
    Cursor = require("src.ui.cursor"),
    SelectionBox = require("src.ui.selection_box"),
    Messages = require("src.ui.messages"),
    PowerBar = require("src.ui.power_bar")
}

return UI
