--[[
    EventClass - Network event encapsulation for multiplayer synchronization

    Port of EventClass from EVENT.H/EVENT.CPP

    This class encapsulates all external game events (player actions) so they
    can be transported between linked computers. This ensures that each event
    affects all computers at the same time (same game frame).

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/EVENT.H
]]

local Target = require("src.core.target")

local EventClass = {}
EventClass.__index = EventClass

--============================================================================
-- Event Types (from EVENT.H)
--============================================================================

EventClass.TYPE = {
    EMPTY = 0,

    -- Player actions
    ALLY = 1,              -- Make ally of specified house
    MEGAMISSION = 2,       -- Full change of mission with target and destination
    IDLE = 3,              -- Request to enter idle mode
    SCATTER = 4,           -- Request to scatter from current location
    DESTRUCT = 5,          -- Self destruct request (surrender action)
    DEPLOY = 6,            -- MCV is to deploy at current location
    PLACE = 7,             -- Place building at location specified
    OPTIONS = 8,           -- Bring up options screen
    GAMESPEED = 9,         -- Set game speed
    PRODUCE = 10,          -- Start or Resume production
    SUSPEND = 11,          -- Suspend production
    ABANDON = 12,          -- Abandon production
    PRIMARY = 13,          -- Primary factory selected
    SPECIAL_PLACE = 14,    -- Special target location selected (superweapon)
    EXIT = 15,             -- Exit game
    ANIMATION = 16,        -- Flash ground as movement feedback
    REPAIR = 17,           -- Repair specified object
    SELL = 18,             -- Sell specified object
    SPECIAL = 19,          -- Special options control

    -- Network synchronization (private events)
    FRAMESYNC = 20,        -- Game-connection packet; includes Scenario CRC & sender's frame
    MESSAGE = 21,          -- Message to another player
    RESPONSE_TIME = 22,    -- Use a new propagation delay value
    FRAMEINFO = 23,        -- Game-heartbeat packet; includes Game CRC & command count
    ARCHIVE = 24,          -- Updates archive target on specified object
    TIMING = 25,           -- New timing values for all systems
    PROCESS_TIME = 26,     -- A system's average processing time

    LAST_EVENT = 27,       -- One past the last event
}

-- Event type names for debugging
EventClass.TYPE_NAMES = {
    [EventClass.TYPE.EMPTY] = "EMPTY",
    [EventClass.TYPE.ALLY] = "ALLY",
    [EventClass.TYPE.MEGAMISSION] = "MEGAMISSION",
    [EventClass.TYPE.IDLE] = "IDLE",
    [EventClass.TYPE.SCATTER] = "SCATTER",
    [EventClass.TYPE.DESTRUCT] = "DESTRUCT",
    [EventClass.TYPE.DEPLOY] = "DEPLOY",
    [EventClass.TYPE.PLACE] = "PLACE",
    [EventClass.TYPE.OPTIONS] = "OPTIONS",
    [EventClass.TYPE.GAMESPEED] = "GAMESPEED",
    [EventClass.TYPE.PRODUCE] = "PRODUCE",
    [EventClass.TYPE.SUSPEND] = "SUSPEND",
    [EventClass.TYPE.ABANDON] = "ABANDON",
    [EventClass.TYPE.PRIMARY] = "PRIMARY",
    [EventClass.TYPE.SPECIAL_PLACE] = "SPECIAL_PLACE",
    [EventClass.TYPE.EXIT] = "EXIT",
    [EventClass.TYPE.ANIMATION] = "ANIMATION",
    [EventClass.TYPE.REPAIR] = "REPAIR",
    [EventClass.TYPE.SELL] = "SELL",
    [EventClass.TYPE.SPECIAL] = "SPECIAL",
    [EventClass.TYPE.FRAMESYNC] = "FRAMESYNC",
    [EventClass.TYPE.MESSAGE] = "MESSAGE",
    [EventClass.TYPE.RESPONSE_TIME] = "RESPONSE_TIME",
    [EventClass.TYPE.FRAMEINFO] = "FRAMEINFO",
    [EventClass.TYPE.ARCHIVE] = "ARCHIVE",
    [EventClass.TYPE.TIMING] = "TIMING",
    [EventClass.TYPE.PROCESS_TIME] = "PROCESS_TIME",
}

-- Event data sizes (in bytes, excluding header)
-- These match the original C++ EventLength array
EventClass.EVENT_LENGTH = {
    [EventClass.TYPE.EMPTY] = 0,
    [EventClass.TYPE.ALLY] = 1,             -- House ID
    [EventClass.TYPE.MEGAMISSION] = 13,     -- Whom(4) + Mission(1) + Target(4) + Destination(4)
    [EventClass.TYPE.IDLE] = 4,             -- Whom(4)
    [EventClass.TYPE.SCATTER] = 4,          -- Whom(4)
    [EventClass.TYPE.DESTRUCT] = 0,
    [EventClass.TYPE.DEPLOY] = 4,           -- Whom(4)
    [EventClass.TYPE.PLACE] = 6,            -- Type(1) + ID(1) + Cell(4)
    [EventClass.TYPE.OPTIONS] = 4,          -- Special flags
    [EventClass.TYPE.GAMESPEED] = 1,        -- Speed value
    [EventClass.TYPE.PRODUCE] = 2,          -- Type(1) + ID(1)
    [EventClass.TYPE.SUSPEND] = 2,          -- Type(1) + ID(1)
    [EventClass.TYPE.ABANDON] = 2,          -- Type(1) + ID(1)
    [EventClass.TYPE.PRIMARY] = 4,          -- Whom(4)
    [EventClass.TYPE.SPECIAL_PLACE] = 6,    -- ID(2) + Cell(4)
    [EventClass.TYPE.EXIT] = 0,
    [EventClass.TYPE.ANIMATION] = 11,       -- What(1) + Owner(1) + Where(4) + Visible(4) + padding
    [EventClass.TYPE.REPAIR] = 4,           -- Whom(4)
    [EventClass.TYPE.SELL] = 4,             -- Whom(4)
    [EventClass.TYPE.SPECIAL] = 4,          -- Value(4)
    [EventClass.TYPE.FRAMESYNC] = 7,        -- CRC(4) + CommandCount(2) + Delay(1)
    [EventClass.TYPE.MESSAGE] = 40,         -- Message text
    [EventClass.TYPE.RESPONSE_TIME] = 1,    -- Delay value
    [EventClass.TYPE.FRAMEINFO] = 7,        -- CRC(4) + CommandCount(2) + Delay(1)
    [EventClass.TYPE.ARCHIVE] = 8,          -- Whom(4) + Target(4)
    [EventClass.TYPE.TIMING] = 4,           -- DesiredFrameRate(2) + MaxAhead(2)
    [EventClass.TYPE.PROCESS_TIME] = 2,     -- AverageTicks(2)
}

--============================================================================
-- Constructor
--============================================================================

function EventClass.new(event_type)
    local self = setmetatable({}, EventClass)

    -- Event type
    self.Type = event_type or EventClass.TYPE.EMPTY

    -- Frame number (27 bits gives over 25 days at 30 FPS)
    self.Frame = 0

    -- House index of player originating this event (4 bits, 0-15)
    self.ID = 0

    -- Whether this event has been executed
    self.IsExecuted = false

    -- Multiplayer ID (high nybble: color, low nybble: house type)
    self.MPlayerID = 0

    -- Event-specific data (union in C++)
    self.Data = {}

    return self
end

--============================================================================
-- Factory Constructors (matching C++ overloads)
--============================================================================

--[[
    Create a target-based event (IDLE, SCATTER, DEPLOY, REPAIR, SELL, PRIMARY).

    @param event_type - Event type
    @param target - TARGET value
    @return EventClass instance
]]
function EventClass.Target(event_type, target)
    local event = EventClass.new(event_type)
    event.Data.Whom = target
    return event
end

--[[
    Create a MegaMission event (full mission change with target and destination).

    @param whom - Unit/object to assign mission to
    @param mission - MissionType
    @param target - Attack target (optional)
    @param destination - Movement destination (optional)
    @return EventClass instance
]]
function EventClass.MegaMission(whom, mission, target, destination)
    local event = EventClass.new(EventClass.TYPE.MEGAMISSION)
    event.Data.Whom = whom
    event.Data.Mission = mission
    event.Data.Target = target or 0
    event.Data.Destination = destination or 0
    return event
end

--[[
    Create a simple value event (GAMESPEED, RESPONSE_TIME).

    @param event_type - Event type
    @param value - Integer value
    @return EventClass instance
]]
function EventClass.Value(event_type, value)
    local event = EventClass.new(event_type)
    event.Data.Value = value
    return event
end

--[[
    Create a production event (PRODUCE, SUSPEND, ABANDON).

    @param event_type - Event type
    @param rtti_type - RTTIType of object to produce
    @param type_id - Type ID within that RTTI category
    @return EventClass instance
]]
function EventClass.Production(event_type, rtti_type, type_id)
    local event = EventClass.new(event_type)
    event.Data.RTTIType = rtti_type
    event.Data.TypeID = type_id
    return event
end

--[[
    Create a building placement event.

    @param rtti_type - RTTIType of building
    @param cell - Cell to place at
    @return EventClass instance
]]
function EventClass.Place(rtti_type, cell)
    local event = EventClass.new(EventClass.TYPE.PLACE)
    event.Data.RTTIType = rtti_type
    event.Data.Cell = cell
    return event
end

--[[
    Create a special weapon placement event.

    @param special_id - Special weapon ID
    @param cell - Target cell
    @return EventClass instance
]]
function EventClass.SpecialPlace(special_id, cell)
    local event = EventClass.new(EventClass.TYPE.SPECIAL_PLACE)
    event.Data.SpecialID = special_id
    event.Data.Cell = cell
    return event
end

--[[
    Create an ally event.

    @param house - House to ally with
    @return EventClass instance
]]
function EventClass.Ally(house)
    local event = EventClass.new(EventClass.TYPE.ALLY)
    event.Data.House = house
    return event
end

--[[
    Create an animation event (visual feedback).

    @param anim_type - AnimType
    @param owner - House that owns the animation
    @param coord - COORDINATE to place animation
    @param visible - Visibility mask (-1 for all)
    @return EventClass instance
]]
function EventClass.Animation(anim_type, owner, coord, visible)
    local event = EventClass.new(EventClass.TYPE.ANIMATION)
    event.Data.AnimType = anim_type
    event.Data.Owner = owner
    event.Data.Coord = coord
    event.Data.Visible = visible or -1
    return event
end

--[[
    Create a frame sync event.

    @param crc - Game state CRC
    @param command_count - Number of commands sent
    @param delay - Propagation delay
    @return EventClass instance
]]
function EventClass.FrameSync(crc, command_count, delay)
    local event = EventClass.new(EventClass.TYPE.FRAMESYNC)
    event.Data.CRC = crc
    event.Data.CommandCount = command_count
    event.Data.Delay = delay
    return event
end

--[[
    Create a frame info event.

    @param crc - Game state CRC
    @param command_count - Number of commands sent
    @param delay - Propagation delay
    @return EventClass instance
]]
function EventClass.FrameInfo(crc, command_count, delay)
    local event = EventClass.new(EventClass.TYPE.FRAMEINFO)
    event.Data.CRC = crc
    event.Data.CommandCount = command_count
    event.Data.Delay = delay
    return event
end

--[[
    Create a timing event.

    @param desired_frame_rate - Target frame rate
    @param max_ahead - Maximum frames ahead
    @return EventClass instance
]]
function EventClass.Timing(desired_frame_rate, max_ahead)
    local event = EventClass.new(EventClass.TYPE.TIMING)
    event.Data.DesiredFrameRate = desired_frame_rate
    event.Data.MaxAhead = max_ahead
    return event
end

--[[
    Create a message event.

    @param message - Message text (max 40 chars)
    @return EventClass instance
]]
function EventClass.Message(message)
    local event = EventClass.new(EventClass.TYPE.MESSAGE)
    event.Data.Message = message:sub(1, 40)
    return event
end

--[[
    Create an archive event (update archive target).

    @param whom - Object to update
    @param target - New archive target
    @return EventClass instance
]]
function EventClass.Archive(whom, target)
    local event = EventClass.new(EventClass.TYPE.ARCHIVE)
    event.Data.Whom = whom
    event.Data.Target = target
    return event
end

--[[
    Create a special options event.

    @param options - Special options flags
    @return EventClass instance
]]
function EventClass.Options(options)
    local event = EventClass.new(EventClass.TYPE.OPTIONS)
    event.Data.Options = options
    return event
end

--============================================================================
-- Instance Methods
--============================================================================

--[[
    Execute the event. This is called when the event's frame arrives.
    The actual execution is handled by the game systems based on event type.

    @param game_state - Reference to game state for execution
]]
function EventClass:Execute(game_state)
    if self.IsExecuted then
        return
    end

    self.IsExecuted = true

    -- Dispatch to appropriate handler based on type
    local handler = EventClass.HANDLERS[self.Type]
    if handler then
        handler(self, game_state)
    end
end

--[[
    Get the name of this event type.

    @return Event type name string
]]
function EventClass:Get_Type_Name()
    return EventClass.TYPE_NAMES[self.Type] or "UNKNOWN"
end

--[[
    Get the data size for this event type.

    @return Data size in bytes
]]
function EventClass:Get_Data_Size()
    return EventClass.EVENT_LENGTH[self.Type] or 0
end

--[[
    Check if this event equals another event.

    @param other - Other EventClass to compare
    @return true if equal
]]
function EventClass:Equals(other)
    if self.Type ~= other.Type then return false end
    if self.Frame ~= other.Frame then return false end
    if self.ID ~= other.ID then return false end

    -- Compare data based on type
    for k, v in pairs(self.Data) do
        if other.Data[k] ~= v then return false end
    end

    return true
end

--============================================================================
-- Serialization
--============================================================================

--[[
    Encode the event to a binary string for network transmission.

    @return Binary string
]]
function EventClass:Encode()
    local parts = {}

    -- Header: Type (1) + Frame (4) + ID (1) + MPlayerID (1) = 7 bytes
    table.insert(parts, string.char(self.Type))
    table.insert(parts, string.char(
        bit.band(self.Frame, 0xFF),
        bit.band(bit.rshift(self.Frame, 8), 0xFF),
        bit.band(bit.rshift(self.Frame, 16), 0xFF),
        bit.band(bit.rshift(self.Frame, 24), 0x07)  -- Only 27 bits
    ))
    table.insert(parts, string.char(self.ID))
    table.insert(parts, string.char(self.MPlayerID))

    -- Data based on type
    local data = self:Encode_Data()
    if data then
        table.insert(parts, data)
    end

    return table.concat(parts)
end

--[[
    Encode event-specific data.

    @return Binary string or nil
]]
function EventClass:Encode_Data()
    local t = self.Type

    if t == EventClass.TYPE.EMPTY or t == EventClass.TYPE.DESTRUCT or t == EventClass.TYPE.EXIT then
        return nil

    elseif t == EventClass.TYPE.ALLY then
        return string.char(self.Data.House or 0)

    elseif t == EventClass.TYPE.MEGAMISSION then
        return self:Encode_Int32(self.Data.Whom or 0) ..
               string.char(self.Data.Mission or 0) ..
               self:Encode_Int32(self.Data.Target or 0) ..
               self:Encode_Int32(self.Data.Destination or 0)

    elseif t == EventClass.TYPE.IDLE or t == EventClass.TYPE.SCATTER or
           t == EventClass.TYPE.DEPLOY or t == EventClass.TYPE.REPAIR or
           t == EventClass.TYPE.SELL or t == EventClass.TYPE.PRIMARY then
        return self:Encode_Int32(self.Data.Whom or 0)

    elseif t == EventClass.TYPE.PLACE then
        return string.char(self.Data.RTTIType or 0) ..
               string.char(self.Data.TypeID or 0) ..
               self:Encode_Int32(self.Data.Cell or 0)

    elseif t == EventClass.TYPE.OPTIONS then
        return self:Encode_Int32(self.Data.Options or 0)

    elseif t == EventClass.TYPE.GAMESPEED then
        return string.char(self.Data.Value or 0)

    elseif t == EventClass.TYPE.PRODUCE or t == EventClass.TYPE.SUSPEND or
           t == EventClass.TYPE.ABANDON then
        return string.char(self.Data.RTTIType or 0) ..
               string.char(self.Data.TypeID or 0)

    elseif t == EventClass.TYPE.SPECIAL_PLACE then
        return self:Encode_Int16(self.Data.SpecialID or 0) ..
               self:Encode_Int32(self.Data.Cell or 0)

    elseif t == EventClass.TYPE.ANIMATION then
        return string.char(self.Data.AnimType or 0) ..
               string.char(self.Data.Owner or 0) ..
               self:Encode_Int32(self.Data.Coord or 0) ..
               self:Encode_Int32(self.Data.Visible or -1)

    elseif t == EventClass.TYPE.SPECIAL then
        return self:Encode_Int32(self.Data.Value or 0)

    elseif t == EventClass.TYPE.FRAMESYNC or t == EventClass.TYPE.FRAMEINFO then
        return self:Encode_Int32(self.Data.CRC or 0) ..
               self:Encode_Int16(self.Data.CommandCount or 0) ..
               string.char(self.Data.Delay or 0)

    elseif t == EventClass.TYPE.MESSAGE then
        local msg = self.Data.Message or ""
        msg = msg .. string.rep("\0", 40 - #msg)  -- Pad to 40 chars
        return msg:sub(1, 40)

    elseif t == EventClass.TYPE.RESPONSE_TIME then
        return string.char(self.Data.Delay or 0)

    elseif t == EventClass.TYPE.ARCHIVE then
        return self:Encode_Int32(self.Data.Whom or 0) ..
               self:Encode_Int32(self.Data.Target or 0)

    elseif t == EventClass.TYPE.TIMING then
        return self:Encode_Int16(self.Data.DesiredFrameRate or 0) ..
               self:Encode_Int16(self.Data.MaxAhead or 0)

    elseif t == EventClass.TYPE.PROCESS_TIME then
        return self:Encode_Int16(self.Data.AverageTicks or 0)
    end

    return nil
end

-- Helper: Encode 16-bit integer (little-endian)
function EventClass:Encode_Int16(value)
    return string.char(
        bit.band(value, 0xFF),
        bit.band(bit.rshift(value, 8), 0xFF)
    )
end

-- Helper: Encode 32-bit integer (little-endian)
function EventClass:Encode_Int32(value)
    return string.char(
        bit.band(value, 0xFF),
        bit.band(bit.rshift(value, 8), 0xFF),
        bit.band(bit.rshift(value, 16), 0xFF),
        bit.band(bit.rshift(value, 24), 0xFF)
    )
end

--[[
    Decode an event from a binary string.

    @param data - Binary string
    @param offset - Starting offset (default 1)
    @return EventClass instance, bytes consumed
]]
function EventClass.Decode(data, offset)
    offset = offset or 1

    if #data < offset + 6 then
        return nil, 0  -- Not enough data for header
    end

    local event = EventClass.new()

    -- Decode header
    event.Type = string.byte(data, offset)
    local frame_b0 = string.byte(data, offset + 1)
    local frame_b1 = string.byte(data, offset + 2)
    local frame_b2 = string.byte(data, offset + 3)
    local frame_b3 = string.byte(data, offset + 4)
    event.Frame = frame_b0 + frame_b1 * 256 + frame_b2 * 65536 + bit.band(frame_b3, 0x07) * 16777216
    event.ID = string.byte(data, offset + 5)
    event.MPlayerID = string.byte(data, offset + 6)

    local header_size = 7
    local data_offset = offset + header_size

    -- Decode data based on type
    local data_size = event:Decode_Data(data, data_offset)

    return event, header_size + data_size
end

--[[
    Decode event-specific data.

    @param data - Binary string
    @param offset - Starting offset
    @return Bytes consumed
]]
function EventClass:Decode_Data(data, offset)
    local t = self.Type

    if t == EventClass.TYPE.EMPTY or t == EventClass.TYPE.DESTRUCT or t == EventClass.TYPE.EXIT then
        return 0

    elseif t == EventClass.TYPE.ALLY then
        self.Data.House = string.byte(data, offset)
        return 1

    elseif t == EventClass.TYPE.MEGAMISSION then
        self.Data.Whom = self:Decode_Int32(data, offset)
        self.Data.Mission = string.byte(data, offset + 4)
        self.Data.Target = self:Decode_Int32(data, offset + 5)
        self.Data.Destination = self:Decode_Int32(data, offset + 9)
        return 13

    elseif t == EventClass.TYPE.IDLE or t == EventClass.TYPE.SCATTER or
           t == EventClass.TYPE.DEPLOY or t == EventClass.TYPE.REPAIR or
           t == EventClass.TYPE.SELL or t == EventClass.TYPE.PRIMARY then
        self.Data.Whom = self:Decode_Int32(data, offset)
        return 4

    elseif t == EventClass.TYPE.PLACE then
        self.Data.RTTIType = string.byte(data, offset)
        self.Data.TypeID = string.byte(data, offset + 1)
        self.Data.Cell = self:Decode_Int32(data, offset + 2)
        return 6

    elseif t == EventClass.TYPE.OPTIONS then
        self.Data.Options = self:Decode_Int32(data, offset)
        return 4

    elseif t == EventClass.TYPE.GAMESPEED then
        self.Data.Value = string.byte(data, offset)
        return 1

    elseif t == EventClass.TYPE.PRODUCE or t == EventClass.TYPE.SUSPEND or
           t == EventClass.TYPE.ABANDON then
        self.Data.RTTIType = string.byte(data, offset)
        self.Data.TypeID = string.byte(data, offset + 1)
        return 2

    elseif t == EventClass.TYPE.SPECIAL_PLACE then
        self.Data.SpecialID = self:Decode_Int16(data, offset)
        self.Data.Cell = self:Decode_Int32(data, offset + 2)
        return 6

    elseif t == EventClass.TYPE.ANIMATION then
        self.Data.AnimType = string.byte(data, offset)
        self.Data.Owner = string.byte(data, offset + 1)
        self.Data.Coord = self:Decode_Int32(data, offset + 2)
        self.Data.Visible = self:Decode_Int32(data, offset + 6)
        return 10

    elseif t == EventClass.TYPE.SPECIAL then
        self.Data.Value = self:Decode_Int32(data, offset)
        return 4

    elseif t == EventClass.TYPE.FRAMESYNC or t == EventClass.TYPE.FRAMEINFO then
        self.Data.CRC = self:Decode_Int32(data, offset)
        self.Data.CommandCount = self:Decode_Int16(data, offset + 4)
        self.Data.Delay = string.byte(data, offset + 6)
        return 7

    elseif t == EventClass.TYPE.MESSAGE then
        local msg = data:sub(offset, offset + 39)
        local null_pos = msg:find("\0")
        if null_pos then
            msg = msg:sub(1, null_pos - 1)
        end
        self.Data.Message = msg
        return 40

    elseif t == EventClass.TYPE.RESPONSE_TIME then
        self.Data.Delay = string.byte(data, offset)
        return 1

    elseif t == EventClass.TYPE.ARCHIVE then
        self.Data.Whom = self:Decode_Int32(data, offset)
        self.Data.Target = self:Decode_Int32(data, offset + 4)
        return 8

    elseif t == EventClass.TYPE.TIMING then
        self.Data.DesiredFrameRate = self:Decode_Int16(data, offset)
        self.Data.MaxAhead = self:Decode_Int16(data, offset + 2)
        return 4

    elseif t == EventClass.TYPE.PROCESS_TIME then
        self.Data.AverageTicks = self:Decode_Int16(data, offset)
        return 2
    end

    return 0
end

-- Helper: Decode 16-bit integer (little-endian)
function EventClass:Decode_Int16(data, offset)
    local b0 = string.byte(data, offset) or 0
    local b1 = string.byte(data, offset + 1) or 0
    return b0 + b1 * 256
end

-- Helper: Decode 32-bit integer (little-endian)
function EventClass:Decode_Int32(data, offset)
    local b0 = string.byte(data, offset) or 0
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    local b3 = string.byte(data, offset + 3) or 0
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

--============================================================================
-- Event Handlers (to be registered by game systems)
--============================================================================

EventClass.HANDLERS = {}

--[[
    Register a handler for an event type.

    @param event_type - EventType
    @param handler - Function(event, game_state)
]]
function EventClass.Register_Handler(event_type, handler)
    EventClass.HANDLERS[event_type] = handler
end

--============================================================================
-- Event Queue Management
--============================================================================

local EventQueue = {}
EventQueue.__index = EventQueue

--[[
    Create a new event queue.

    @return EventQueue instance
]]
function EventQueue.new()
    local self = setmetatable({}, EventQueue)
    self.events = {}
    self.current_frame = 0
    return self
end

--[[
    Add an event to the queue.

    @param event - EventClass instance
]]
function EventQueue:Add(event)
    table.insert(self.events, event)
end

--[[
    Get all events for a specific frame.

    @param frame - Frame number
    @return Table of events
]]
function EventQueue:Get_Events_For_Frame(frame)
    local result = {}
    for _, event in ipairs(self.events) do
        if event.Frame == frame and not event.IsExecuted then
            table.insert(result, event)
        end
    end
    return result
end

--[[
    Execute all events for a frame.

    @param frame - Frame number
    @param game_state - Game state reference
]]
function EventQueue:Execute_Frame(frame, game_state)
    local events = self:Get_Events_For_Frame(frame)
    for _, event in ipairs(events) do
        event:Execute(game_state)
    end
    self.current_frame = frame
end

--[[
    Clear executed events older than a certain frame.

    @param before_frame - Remove events before this frame
]]
function EventQueue:Cleanup(before_frame)
    local new_events = {}
    for _, event in ipairs(self.events) do
        if event.Frame >= before_frame or not event.IsExecuted then
            table.insert(new_events, event)
        end
    end
    self.events = new_events
end

--[[
    Get the count of pending events.

    @return Number of unexecuted events
]]
function EventQueue:Pending_Count()
    local count = 0
    for _, event in ipairs(self.events) do
        if not event.IsExecuted then
            count = count + 1
        end
    end
    return count
end

--[[
    Debug dump of queue state.
]]
function EventQueue:Debug_Dump()
    print(string.format("EventQueue: frame=%d events=%d pending=%d",
        self.current_frame, #self.events, self:Pending_Count()))
    for i, event in ipairs(self.events) do
        print(string.format("  [%d] Frame=%d Type=%s Executed=%s",
            i, event.Frame, event:Get_Type_Name(), tostring(event.IsExecuted)))
    end
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of event.
]]
function EventClass:Debug_Dump()
    print(string.format("EventClass: Type=%s Frame=%d ID=%d Executed=%s",
        self:Get_Type_Name(), self.Frame, self.ID, tostring(self.IsExecuted)))

    if self.Data then
        for k, v in pairs(self.Data) do
            print(string.format("  Data.%s = %s", k, tostring(v)))
        end
    end
end

--============================================================================
-- Export
--============================================================================

EventClass.Queue = EventQueue

return EventClass
