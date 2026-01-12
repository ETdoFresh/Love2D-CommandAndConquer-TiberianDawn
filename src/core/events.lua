--[[
    Event Bus - Pub/Sub system for game events
    Allows decoupled communication between systems
]]

local Events = {}
Events.__index = Events

-- Create a new event bus instance
function Events.new()
    local self = setmetatable({}, Events)
    self.listeners = {}  -- event_name -> {callback1, callback2, ...}
    self.once_listeners = {}  -- One-time listeners
    return self
end

-- Subscribe to an event
-- Returns an unsubscribe function
function Events:on(event_name, callback)
    if not self.listeners[event_name] then
        self.listeners[event_name] = {}
    end
    table.insert(self.listeners[event_name], callback)

    -- Return unsubscribe function
    return function()
        self:off(event_name, callback)
    end
end

-- Subscribe to an event (fires once then auto-unsubscribes)
function Events:once(event_name, callback)
    if not self.once_listeners[event_name] then
        self.once_listeners[event_name] = {}
    end
    table.insert(self.once_listeners[event_name], callback)
end

-- Unsubscribe from an event
function Events:off(event_name, callback)
    if self.listeners[event_name] then
        for i, cb in ipairs(self.listeners[event_name]) do
            if cb == callback then
                table.remove(self.listeners[event_name], i)
                break
            end
        end
    end
end

-- Emit an event with optional data
function Events:emit(event_name, ...)
    -- Regular listeners
    if self.listeners[event_name] then
        for _, callback in ipairs(self.listeners[event_name]) do
            callback(...)
        end
    end

    -- Once listeners (fire and remove)
    if self.once_listeners[event_name] then
        local once = self.once_listeners[event_name]
        self.once_listeners[event_name] = nil
        for _, callback in ipairs(once) do
            callback(...)
        end
    end
end

-- Clear all listeners for an event (or all events if no name given)
function Events:clear(event_name)
    if event_name then
        self.listeners[event_name] = nil
        self.once_listeners[event_name] = nil
    else
        self.listeners = {}
        self.once_listeners = {}
    end
end

-- Check if event has listeners
function Events:has_listeners(event_name)
    return (self.listeners[event_name] and #self.listeners[event_name] > 0) or
           (self.once_listeners[event_name] and #self.once_listeners[event_name] > 0)
end

-- Get listener count for an event
function Events:listener_count(event_name)
    local count = 0
    if self.listeners[event_name] then
        count = count + #self.listeners[event_name]
    end
    if self.once_listeners[event_name] then
        count = count + #self.once_listeners[event_name]
    end
    return count
end

-- Global event bus instance
local global_bus = Events.new()

-- Module-level convenience functions using global bus
local M = {
    new = Events.new,
    global = global_bus
}

function M.on(event_name, callback)
    return global_bus:on(event_name, callback)
end

function M.once(event_name, callback)
    return global_bus:once(event_name, callback)
end

function M.off(event_name, callback)
    return global_bus:off(event_name, callback)
end

function M.emit(event_name, ...)
    return global_bus:emit(event_name, ...)
end

function M.clear(event_name)
    return global_bus:clear(event_name)
end

-- Predefined event names for type safety
M.EVENTS = {
    -- Game state
    GAME_START = "game:start",
    GAME_PAUSE = "game:pause",
    GAME_RESUME = "game:resume",
    GAME_TICK = "game:tick",
    GAME_END = "game:end",
    GAME_WIN = "game:win",
    GAME_LOSE = "game:lose",

    -- Entity lifecycle
    ENTITY_CREATED = "entity:created",
    ENTITY_DESTROYED = "entity:destroyed",
    ENTITY_DAMAGED = "entity:damaged",
    ENTITY_KILLED = "entity:killed",

    -- Selection
    SELECTION_CHANGED = "selection:changed",
    SELECTION_CLEARED = "selection:cleared",

    -- Commands
    COMMAND_MOVE = "command:move",
    COMMAND_ATTACK = "command:attack",
    COMMAND_ATTACK_MOVE = "command:attack_move",
    COMMAND_ATTACK_GROUND = "command:attack_ground",
    COMMAND_STOP = "command:stop",
    COMMAND_GUARD = "command:guard",

    -- Production
    PRODUCTION_START = "production:start",
    PRODUCTION_COMPLETE = "production:complete",
    PRODUCTION_CANCEL = "production:cancel",

    -- Building
    BUILDING_PLACED = "building:placed",
    BUILDING_SOLD = "building:sold",
    BUILDING_CAPTURED = "building:captured",

    -- Combat
    UNIT_ATTACKED = "combat:attacked",
    UNIT_KILLED = "combat:killed",
    ENTITY_ATTACKED = "combat:entity_attacked",

    -- Unit/Building lifecycle
    UNIT_BUILT = "unit:built",
    UNIT_DEPLOYED = "unit:deployed",
    BUILDING_BUILT = "building:built",
    BUILDING_REPAIR_START = "building:repair_start",
    BUILDING_REPAIR_STOP = "building:repair_stop",

    -- Economy
    CREDITS_CHANGED = "economy:credits",
    POWER_CHANGED = "economy:power",

    -- Map
    SHROUD_REVEALED = "map:revealed",
    WALL_DESTROYED = "map:wall_destroyed",

    -- Audio
    SOUND_PLAY = "audio:sound",
    MUSIC_PLAY = "audio:music",
    EVA_SPEAK = "audio:eva",

    -- UI
    UI_MESSAGE = "ui:message",
    UI_SIDEBAR_UPDATE = "ui:sidebar",

    -- Network
    NET_PLAYER_JOIN = "net:join",
    NET_PLAYER_LEAVE = "net:leave",
    NET_SYNC = "net:sync",
    NET_DESYNC = "net:desync"
}

return M
