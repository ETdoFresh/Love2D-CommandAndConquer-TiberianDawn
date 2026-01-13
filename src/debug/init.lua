--[[
    Debug Module - Development and testing tools

    Reference: PLAN.md Phase 6 Debug Support
    - Debug_Dump() for all classes
    - MonoClass equivalent logging
    - Cheat commands
]]

local Debug = {
    IPC = require("src.debug.ipc"),
    Dump = require("src.debug.dump"),
    Mono = require("src.debug.mono"),
    Cheats = require("src.debug.cheats")
}

return Debug
