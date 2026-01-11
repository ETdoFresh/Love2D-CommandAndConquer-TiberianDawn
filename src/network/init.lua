--[[
    Network Module - Exports all multiplayer networking components
]]

local Network = {
    Protocol = require("src.network.protocol"),
    Lockstep = require("src.network.lockstep"),
    Lobby = require("src.network.lobby"),
    Spectator = require("src.network.spectator")
}

return Network
