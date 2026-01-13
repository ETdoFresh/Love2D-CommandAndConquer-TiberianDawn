--[[
    Network Module - Exports all multiplayer networking components
]]

local Network = {
    EventClass = require("src.network.event"),
    SessionClass = require("src.network.session"),
    Protocol = require("src.network.protocol"),
    Lockstep = require("src.network.lockstep"),
    Lobby = require("src.network.lobby"),
    Spectator = require("src.network.spectator"),
    Socket = require("src.network.socket")
}

-- Expose global session instance
Network.Session = Network.SessionClass.Session

return Network
