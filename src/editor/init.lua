--[[
    Editor Module - Exports all scenario editor tools
]]

local Editor = {
    TerrainBrush = require("src.editor.terrain_brush"),
    UnitPlacer = require("src.editor.unit_placer"),
    TriggerEditor = require("src.editor.trigger_editor"),
    Export = require("src.editor.export")
}

return Editor
