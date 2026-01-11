--[[
    Trigger Editor - Tool for creating and editing scenario triggers
]]

local TriggerEditor = {}
TriggerEditor.__index = TriggerEditor

-- Trigger event types (matching original C&C)
TriggerEditor.EVENT = {
    NONE = 0,
    ENTERED_BY = 1,           -- Cell entered by unit
    SPIED_BY = 2,             -- Building spied
    THIEVED_BY = 3,           -- Building captured
    DISCOVERED_BY = 4,        -- Unit discovered
    HOUSE_DISCOVERED = 5,     -- Player discovered
    ATTACKED = 6,             -- Object attacked
    DESTROYED = 7,            -- Object destroyed
    ANY_EVENT = 8,            -- Any event
    NO_BUILDINGS_LEFT = 9,    -- All buildings destroyed
    ALL_UNITS_DESTROYED = 10, -- All units destroyed
    ALL_DESTROYED = 11,       -- Everything destroyed
    CREDITS_EXCEED = 12,      -- Credits >= amount
    TIME_ELAPSED = 13,        -- Game time elapsed
    MISSION_TIMER_EXPIRED = 14, -- Mission timer done
    BUILDINGS_DESTROYED = 15, -- N buildings destroyed
    UNITS_DESTROYED = 16,     -- N units destroyed
    NOFACTORY = 17,           -- No more factories
    CIVILIAN_EVACUATED = 18,  -- Civilian escaped
    BUILD_BUILDING_TYPE = 19, -- Built specific building
    BUILD_UNIT_TYPE = 20,     -- Built specific unit
    BUILD_INFANTRY_TYPE = 21, -- Built specific infantry
    BUILD_AIRCRAFT_TYPE = 22, -- Built specific aircraft
    LEAVES_MAP = 23,          -- Object leaves map
    ZONE_ENTRY = 24,          -- Unit enters zone
    CROSSES_HORIZONTAL = 25,  -- Unit crosses line
    CROSSES_VERTICAL = 26,    -- Unit crosses line
    GLOBAL_SET = 27,          -- Global flag set
    GLOBAL_CLEAR = 28,        -- Global flag cleared
    DESTROYED_BY_ANYONE = 29, -- Destroyed by any player
    LOW_POWER = 30,           -- Low power state
    BRIDGE_DESTROYED = 31,    -- Bridge destroyed
    BUILDING_EXISTS = 32      -- Specific building exists
}

-- Trigger action types
TriggerEditor.ACTION = {
    NONE = 0,
    WIN = 1,                  -- Player wins
    LOSE = 2,                 -- Player loses
    PRODUCTION_BEGINS = 3,    -- AI starts building
    CREATE_TEAM = 4,          -- Create AI team
    DESTROY_TEAM = 5,         -- Remove AI team
    ALL_TO_HUNT = 6,          -- All units attack
    REINFORCEMENT = 7,        -- Spawn reinforcements
    DROP_ZONE_FLARE = 8,      -- Show flare
    FIRE_SALE = 9,            -- Sell all buildings
    PLAY_MOVIE = 10,          -- Play cutscene
    TEXT = 11,                -- Show message
    DESTROY_TRIGGER = 12,     -- Remove trigger
    AUTOCREATE = 13,          -- Enable AI auto-create
    ALLOW_WIN = 14,           -- Enable win condition
    REVEAL_MAP = 15,          -- Reveal entire map
    REVEAL_ZONE = 16,         -- Reveal area
    PLAY_SOUND = 17,          -- Play sound effect
    PLAY_MUSIC = 18,          -- Play music track
    PLAY_SPEECH = 19,         -- Play EVA speech
    FORCE_TRIGGER = 20,       -- Force trigger event
    TIMER_START = 21,         -- Start mission timer
    TIMER_STOP = 22,          -- Stop mission timer
    TIMER_EXTEND = 23,        -- Add time to timer
    TIMER_SHORTEN = 24,       -- Remove time from timer
    TIMER_SET = 25,           -- Set timer value
    GLOBAL_SET = 26,          -- Set global flag
    GLOBAL_CLEAR = 27,        -- Clear global flag
    AUTO_BASE_AI = 28,        -- Enable base building AI
    GROW_TIBERIUM = 29,       -- Force tiberium growth
    DESTROY_ATTACHED = 30,    -- Destroy attached object
    ADD_1TIME_SPECIAL = 31,   -- Add one-time special weapon
    ADD_REPEATING_SPECIAL = 32, -- Add repeating special weapon
    PREFERRED_TARGET = 33,    -- Set AI target preference
    LAUNCH_NUKES = 34         -- Launch nuclear missiles
}

function TriggerEditor.new()
    local self = setmetatable({}, TriggerEditor)

    -- Current triggers list
    self.triggers = {}

    -- Currently selected trigger
    self.selected_trigger = nil

    -- UI state
    self.scroll_offset = 0
    self.visible_count = 10

    -- Global flags (32 available like original)
    self.globals = {}
    for i = 0, 31 do
        self.globals[i] = false
    end

    return self
end

-- Create a new trigger
function TriggerEditor:create_trigger(name)
    local trigger = {
        name = name or ("Trigger" .. (#self.triggers + 1)),
        house = "GOOD",           -- Which house this trigger belongs to
        event = TriggerEditor.EVENT.NONE,
        event_param = 0,          -- Parameter for event (e.g., credits amount)
        action = TriggerEditor.ACTION.NONE,
        action_param = 0,         -- Parameter for action
        team = nil,               -- Associated team name
        repeatable = false,       -- Can trigger multiple times
        persistent = false,       -- Survives scenario reset
        enabled = true,           -- Currently active
        cell_x = -1,              -- Attached cell position
        cell_y = -1
    }

    table.insert(self.triggers, trigger)
    self.selected_trigger = trigger

    return trigger
end

-- Delete a trigger
function TriggerEditor:delete_trigger(trigger)
    for i, t in ipairs(self.triggers) do
        if t == trigger then
            table.remove(self.triggers, i)
            if self.selected_trigger == trigger then
                self.selected_trigger = self.triggers[1]
            end
            return true
        end
    end
    return false
end

-- Select trigger by name
function TriggerEditor:select_trigger(name)
    for _, trigger in ipairs(self.triggers) do
        if trigger.name == name then
            self.selected_trigger = trigger
            return trigger
        end
    end
    return nil
end

-- Set trigger event
function TriggerEditor:set_event(trigger, event_type, param)
    trigger.event = event_type
    trigger.event_param = param or 0
end

-- Set trigger action
function TriggerEditor:set_action(trigger, action_type, param)
    trigger.action = action_type
    trigger.action_param = param or 0
end

-- Attach trigger to cell
function TriggerEditor:attach_to_cell(trigger, cell_x, cell_y)
    trigger.cell_x = cell_x
    trigger.cell_y = cell_y
end

-- Get event name
function TriggerEditor:get_event_name(event_type)
    for name, value in pairs(TriggerEditor.EVENT) do
        if value == event_type then
            return name
        end
    end
    return "UNKNOWN"
end

-- Get action name
function TriggerEditor:get_action_name(action_type)
    for name, value in pairs(TriggerEditor.ACTION) do
        if value == action_type then
            return name
        end
    end
    return "UNKNOWN"
end

-- Get all triggers for a cell
function TriggerEditor:get_triggers_at_cell(cell_x, cell_y)
    local result = {}
    for _, trigger in ipairs(self.triggers) do
        if trigger.cell_x == cell_x and trigger.cell_y == cell_y then
            table.insert(result, trigger)
        end
    end
    return result
end

-- Get all triggers for a house
function TriggerEditor:get_triggers_for_house(house)
    local result = {}
    for _, trigger in ipairs(self.triggers) do
        if trigger.house == house then
            table.insert(result, trigger)
        end
    end
    return result
end

-- Set global flag
function TriggerEditor:set_global(index, value)
    if index >= 0 and index <= 31 then
        self.globals[index] = value
    end
end

-- Get global flag
function TriggerEditor:get_global(index)
    if index >= 0 and index <= 31 then
        return self.globals[index]
    end
    return false
end

-- Serialize triggers for saving
function TriggerEditor:serialize()
    local data = {
        triggers = {},
        globals = {}
    }

    for _, trigger in ipairs(self.triggers) do
        table.insert(data.triggers, {
            name = trigger.name,
            house = trigger.house,
            event = trigger.event,
            event_param = trigger.event_param,
            action = trigger.action,
            action_param = trigger.action_param,
            team = trigger.team,
            repeatable = trigger.repeatable,
            persistent = trigger.persistent,
            enabled = trigger.enabled,
            cell_x = trigger.cell_x,
            cell_y = trigger.cell_y
        })
    end

    for i = 0, 31 do
        data.globals[i] = self.globals[i]
    end

    return data
end

-- Deserialize triggers from saved data
function TriggerEditor:deserialize(data)
    self.triggers = {}

    if data.triggers then
        for _, t in ipairs(data.triggers) do
            local trigger = {
                name = t.name,
                house = t.house,
                event = t.event,
                event_param = t.event_param,
                action = t.action,
                action_param = t.action_param,
                team = t.team,
                repeatable = t.repeatable,
                persistent = t.persistent,
                enabled = t.enabled,
                cell_x = t.cell_x,
                cell_y = t.cell_y
            }
            table.insert(self.triggers, trigger)
        end
    end

    if data.globals then
        for i = 0, 31 do
            self.globals[i] = data.globals[i] or false
        end
    end

    self.selected_trigger = self.triggers[1]
end

-- Draw trigger editor UI
function TriggerEditor:draw(x, y, width, height)
    -- Background
    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", x, y, width, height)

    -- Border
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.rectangle("line", x, y, width, height)

    -- Title
    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.print("TRIGGER EDITOR", x + 10, y + 5)

    -- Trigger list
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    local list_y = y + 25

    for i, trigger in ipairs(self.triggers) do
        if i > self.scroll_offset and i <= self.scroll_offset + self.visible_count then
            local item_y = list_y + (i - self.scroll_offset - 1) * 20

            if trigger == self.selected_trigger then
                love.graphics.setColor(0.3, 0.3, 0.5, 1)
                love.graphics.rectangle("fill", x + 5, item_y, width - 10, 18)
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
            end

            local status = trigger.enabled and "" or "[OFF] "
            love.graphics.print(status .. trigger.name, x + 10, item_y + 2)
        end
    end

    -- Selected trigger details
    if self.selected_trigger then
        local details_y = y + height - 120

        love.graphics.setColor(0.3, 0.3, 0.35, 1)
        love.graphics.rectangle("fill", x + 5, details_y, width - 10, 110)

        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.print("Name: " .. self.selected_trigger.name, x + 10, details_y + 5)
        love.graphics.print("House: " .. self.selected_trigger.house, x + 10, details_y + 20)
        love.graphics.print("Event: " .. self:get_event_name(self.selected_trigger.event), x + 10, details_y + 35)
        love.graphics.print("Action: " .. self:get_action_name(self.selected_trigger.action), x + 10, details_y + 50)

        local cell_text = "Cell: "
        if self.selected_trigger.cell_x >= 0 then
            cell_text = cell_text .. self.selected_trigger.cell_x .. "," .. self.selected_trigger.cell_y
        else
            cell_text = cell_text .. "None"
        end
        love.graphics.print(cell_text, x + 10, details_y + 65)

        local flags = ""
        if self.selected_trigger.repeatable then flags = flags .. "[REPEAT] " end
        if self.selected_trigger.persistent then flags = flags .. "[PERSIST] " end
        love.graphics.print("Flags: " .. (flags ~= "" and flags or "None"), x + 10, details_y + 80)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Handle click in trigger list
function TriggerEditor:handle_click(x, y, editor_x, editor_y, width)
    local list_y = editor_y + 25

    for i, trigger in ipairs(self.triggers) do
        if i > self.scroll_offset and i <= self.scroll_offset + self.visible_count then
            local item_y = list_y + (i - self.scroll_offset - 1) * 20

            if x >= editor_x + 5 and x <= editor_x + width - 5 and
               y >= item_y and y <= item_y + 18 then
                self.selected_trigger = trigger
                return true
            end
        end
    end

    return false
end

return TriggerEditor
