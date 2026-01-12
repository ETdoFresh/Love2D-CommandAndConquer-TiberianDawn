--[[
    Commands - Command pattern for unit orders
    Encapsulates player commands for undo/redo, networking, and replay
    Reference: Original C&C command system (EVENT.H)
]]

local Events = require("src.core.events")

local Commands = {}
Commands.__index = Commands

-- Command types matching original C&C (from EVENT.H)
Commands.TYPE = {
    -- Movement
    MOVE = "move",
    MOVE_CELL = "move_cell",
    WAYPOINT = "waypoint",

    -- Combat
    ATTACK = "attack",
    FORCE_ATTACK = "force_attack",

    -- Unit orders
    GUARD = "guard",
    GUARD_AREA = "guard_area",
    STOP = "stop",
    SCATTER = "scatter",
    DEPLOY = "deploy",
    ENTER = "enter",
    UNLOAD = "unload",
    HARVEST = "harvest",
    RETURN = "return",

    -- Selection
    SELECT = "select",
    SELECT_ADD = "select_add",
    SELECT_BOX = "select_box",
    DESELECT = "deselect",
    DESELECT_ALL = "deselect_all",

    -- Control groups
    ASSIGN_GROUP = "assign_group",
    SELECT_GROUP = "select_group",
    ADD_TO_GROUP = "add_to_group",

    -- Production
    BUILD = "build",
    CANCEL_BUILD = "cancel_build",
    PLACE_BUILDING = "place_building",
    SET_PRIMARY = "set_primary",
    SET_RALLY = "set_rally",

    -- Base
    SELL = "sell",
    REPAIR = "repair",

    -- Special weapons
    SPECIAL_WEAPON = "special_weapon",
    ION_CANNON = "ion_cannon",
    NUKE = "nuke",
    AIRSTRIKE = "airstrike",

    -- Team AI
    TEAM_FORMATION = "team_formation",

    -- Game
    ALLY = "ally",
    RESIGN = "resign",
    OPTIONS = "options"
}

-- Command class
local Command = {}
Command.__index = Command

function Command.new(cmd_type, params)
    local self = setmetatable({}, Command)

    self.type = cmd_type
    self.params = params or {}
    self.timestamp = love.timer.getTime()
    self.frame = 0  -- Set by game when executed
    self.player_id = 0  -- Set by game for multiplayer

    return self
end

function Command:serialize()
    return {
        type = self.type,
        params = self.params,
        timestamp = self.timestamp,
        frame = self.frame,
        player_id = self.player_id
    }
end

function Command.deserialize(data)
    local cmd = Command.new(data.type, data.params)
    cmd.timestamp = data.timestamp
    cmd.frame = data.frame
    cmd.player_id = data.player_id
    return cmd
end

-- Command Queue/Processor
function Commands.new()
    local self = setmetatable({}, Commands)

    -- Pending commands (not yet executed)
    self.pending = {}

    -- Executed commands (for history/replay)
    self.history = {}
    self.history_index = 0
    self.max_history = 1000

    -- Current game frame (for synchronization)
    self.current_frame = 0

    -- Network mode
    self.network_mode = false
    self.local_player_id = 1

    -- Command handlers (registered by game systems)
    self.handlers = {}

    return self
end

-- Register a command handler
function Commands:register_handler(cmd_type, handler)
    if not self.handlers[cmd_type] then
        self.handlers[cmd_type] = {}
    end
    table.insert(self.handlers[cmd_type], handler)
end

-- Unregister all handlers for a type
function Commands:unregister_handlers(cmd_type)
    self.handlers[cmd_type] = nil
end

-- Queue a command for execution
function Commands:queue(cmd_type, params)
    local cmd = Command.new(cmd_type, params)
    cmd.player_id = self.local_player_id
    cmd.frame = self.current_frame

    table.insert(self.pending, cmd)

    Events.emit("COMMAND_QUEUED", cmd)

    return cmd
end

-- Queue a command from network (already has player_id)
function Commands:queue_network(cmd)
    table.insert(self.pending, cmd)
    Events.emit("COMMAND_QUEUED_NETWORK", cmd)
end

-- Execute all pending commands for current frame
function Commands:execute_pending()
    local executed = {}

    for i, cmd in ipairs(self.pending) do
        if cmd.frame <= self.current_frame then
            self:execute(cmd)
            table.insert(executed, i)
        end
    end

    -- Remove executed commands (in reverse order to preserve indices)
    for i = #executed, 1, -1 do
        table.remove(self.pending, executed[i])
    end
end

-- Execute a single command
function Commands:execute(cmd)
    local handlers = self.handlers[cmd.type]

    if handlers then
        for _, handler in ipairs(handlers) do
            handler(cmd)
        end
    end

    -- Add to history
    self:add_to_history(cmd)

    Events.emit("COMMAND_EXECUTED", cmd)
end

-- Add command to history
function Commands:add_to_history(cmd)
    -- Truncate future history if we're not at the end
    while #self.history > self.history_index do
        table.remove(self.history)
    end

    table.insert(self.history, cmd)
    self.history_index = #self.history

    -- Limit history size
    while #self.history > self.max_history do
        table.remove(self.history, 1)
        self.history_index = self.history_index - 1
    end
end

-- Advance to next frame
function Commands:advance_frame()
    self.current_frame = self.current_frame + 1
end

-- Get current frame
function Commands:get_frame()
    return self.current_frame
end

-- Set current frame (for synchronization)
function Commands:set_frame(frame)
    self.current_frame = frame
end

-- Clear all pending commands
function Commands:clear_pending()
    self.pending = {}
end

-- Clear history
function Commands:clear_history()
    self.history = {}
    self.history_index = 0
end

-- Get all commands for a specific frame (for replay/network)
function Commands:get_commands_for_frame(frame)
    local commands = {}
    for _, cmd in ipairs(self.history) do
        if cmd.frame == frame then
            table.insert(commands, cmd)
        end
    end
    return commands
end

-- Serialize all pending commands (for network transmission)
function Commands:serialize_pending()
    local data = {}
    for _, cmd in ipairs(self.pending) do
        table.insert(data, cmd:serialize())
    end
    return data
end

-- Deserialize and queue commands from network
function Commands:deserialize_and_queue(data)
    for _, cmd_data in ipairs(data) do
        local cmd = Command.deserialize(cmd_data)
        self:queue_network(cmd)
    end
end

-- Helper functions for common commands

function Commands:move(entities, target_x, target_y)
    return self:queue(Commands.TYPE.MOVE, {
        entities = entities,
        target_x = target_x,
        target_y = target_y
    })
end

function Commands:attack(entities, target_entity)
    return self:queue(Commands.TYPE.ATTACK, {
        entities = entities,
        target = target_entity
    })
end

function Commands:force_attack(entities, target_x, target_y)
    return self:queue(Commands.TYPE.FORCE_ATTACK, {
        entities = entities,
        target_x = target_x,
        target_y = target_y
    })
end

function Commands:guard(entities)
    return self:queue(Commands.TYPE.GUARD, {
        entities = entities
    })
end

function Commands:stop(entities)
    return self:queue(Commands.TYPE.STOP, {
        entities = entities
    })
end

function Commands:scatter(entities)
    return self:queue(Commands.TYPE.SCATTER, {
        entities = entities
    })
end

function Commands:deploy(entity)
    return self:queue(Commands.TYPE.DEPLOY, {
        entity = entity
    })
end

function Commands:select(entity, add_to_selection)
    return self:queue(add_to_selection and Commands.TYPE.SELECT_ADD or Commands.TYPE.SELECT, {
        entity = entity
    })
end

function Commands:select_box(x1, y1, x2, y2, add_to_selection)
    return self:queue(Commands.TYPE.SELECT_BOX, {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        add = add_to_selection
    })
end

function Commands:deselect_all()
    return self:queue(Commands.TYPE.DESELECT_ALL, {})
end

function Commands:assign_group(group_number, entities)
    return self:queue(Commands.TYPE.ASSIGN_GROUP, {
        group = group_number,
        entities = entities
    })
end

function Commands:select_group(group_number)
    return self:queue(Commands.TYPE.SELECT_GROUP, {
        group = group_number
    })
end

function Commands:build(building_type, factory_entity)
    return self:queue(Commands.TYPE.BUILD, {
        type = building_type,
        factory = factory_entity
    })
end

function Commands:cancel_build(factory_entity)
    return self:queue(Commands.TYPE.CANCEL_BUILD, {
        factory = factory_entity
    })
end

function Commands:place_building(building_type, cell_x, cell_y)
    return self:queue(Commands.TYPE.PLACE_BUILDING, {
        type = building_type,
        cell_x = cell_x,
        cell_y = cell_y
    })
end

function Commands:sell(entity)
    return self:queue(Commands.TYPE.SELL, {
        entity = entity
    })
end

function Commands:repair(entity)
    return self:queue(Commands.TYPE.REPAIR, {
        entity = entity
    })
end

function Commands:special_weapon(weapon_type, target_x, target_y)
    return self:queue(Commands.TYPE.SPECIAL_WEAPON, {
        weapon = weapon_type,
        target_x = target_x,
        target_y = target_y
    })
end

function Commands:set_rally(factory_entity, target_x, target_y)
    return self:queue(Commands.TYPE.SET_RALLY, {
        factory = factory_entity,
        target_x = target_x,
        target_y = target_y
    })
end

-- Export both Commands processor and Command class
Commands.Command = Command

return Commands
