--[[
    Network Module - Exports all multiplayer networking components
]]

local Network = {
    EventClass = require("src.network.event"),
    Protocol = require("src.network.protocol"),
    Lockstep = require("src.network.lockstep"),
    Lobby = require("src.network.lobby"),
    Spectator = require("src.network.spectator"),
    Socket = require("src.network.socket")
}

return Network
