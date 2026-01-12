--[[
    Audio Module - Exports all audio components
    Provides music, sound effects, and speech management
]]

local Audio = {
    Music = require("src.audio.music"),
    SFX = require("src.audio.sfx"),
    Speech = require("src.audio.speech")
}

return Audio
