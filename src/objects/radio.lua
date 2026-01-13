--[[
    RadioClass - Inter-object communication system

    Port of RADIO.H/CPP from the original C&C source.

    This class extends MissionClass to add:
    - Radio contact with other objects
    - Message passing between objects
    - Coordination for complex behaviors (docking, loading, etc.)

    Radio contact is used when one object needs to coordinate with another,
    such as:
    - Aircraft landing on a helipad
    - Units entering a transport
    - Harvesters docking with a refinery
    - Engineers entering buildings

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/RADIO.H
]]

local Class = require("src.objects.class")
local MissionClass = require("src.objects.mission")
local Target = require("src.core.target")

-- Create RadioClass extending MissionClass
local RadioClass = Class.extend(MissionClass, "RadioClass")

--============================================================================
-- Constants - Radio Messages
--============================================================================

-- Radio message types (from RADIO.H)
RadioClass.RADIO = {
    STATIC = 0,           -- No message / ignored
    ROGER = 1,            -- Affirmative / OK
    HELLO = 2,            -- Request to establish contact
    OVER_OUT = 3,         -- Breaking radio contact
    PICK_UP = 4,          -- Request to be picked up (enter transport)
    ATTACH = 5,           -- Request to attach/dock
    DELIVERY = 6,         -- Ready for delivery
    HOLD_STILL = 7,       -- Stop moving - I'm approaching
    UNLOADING = 8,        -- Currently unloading
    LOADING = 9,          -- Currently loading
    NEED_TO_MOVE = 10,    -- Request permission to move
    TRY_ANOTHER = 11,     -- Try another docking bay
    ARE_YOU_CLEAR = 12,   -- Are you clear of the area?
    AM_CLEAR = 13,        -- I am clear of the area
    BUILDING = 14,        -- I'm constructing
    COMPLETE = 15,        -- Construction complete
    CANT = 16,            -- Cannot comply
    ALL_CLEAR = 17,       -- All units clear
    ON_MY_WAY = 18,       -- Moving to rendezvous
    NEED_TRANSPORT = 19,  -- Request transport pickup
    TRANSPORT_FULL = 20,  -- Transport is full
    REVERT = 21,          -- Revert to normal behavior
}

-- Count for array sizing
RadioClass.RADIO_COUNT = 22

-- Message names for debugging
RadioClass.RADIO_NAMES = {
    [0] = "STATIC",
    [1] = "ROGER",
    [2] = "HELLO",
    [3] = "OVER_OUT",
    [4] = "PICK_UP",
    [5] = "ATTACH",
    [6] = "DELIVERY",
    [7] = "HOLD_STILL",
    [8] = "UNLOADING",
    [9] = "LOADING",
    [10] = "NEED_TO_MOVE",
    [11] = "TRY_ANOTHER",
    [12] = "ARE_YOU_CLEAR",
    [13] = "AM_CLEAR",
    [14] = "BUILDING",
    [15] = "COMPLETE",
    [16] = "CANT",
    [17] = "ALL_CLEAR",
    [18] = "ON_MY_WAY",
    [19] = "NEED_TRANSPORT",
    [20] = "TRANSPORT_FULL",
    [21] = "REVERT",
}

--============================================================================
-- Constructor
--============================================================================

function RadioClass:init()
    -- Call parent constructor
    MissionClass.init(self)

    --[[
        This is a record of the last message received by this receiver.
    ]]
    self.LastMessage = RadioClass.RADIO.STATIC

    --[[
        This is the object that radio communication has been established with.
        Although it is only a one-way reference, it is required that the
        receiving radio is also tuned to the object that contains this radio set.
    ]]
    self.Radio = nil
end

--============================================================================
-- Radio Contact Query
--============================================================================

--[[
    Check if currently in radio contact with another object
]]
function RadioClass:In_Radio_Contact()
    return self.Radio ~= nil
end

--[[
    Get the object we're in radio contact with
    Returns TechnoClass or nil
]]
function RadioClass:Contact_With_Whom()
    return self.Radio
end

--[[
    Clear radio contact (one-way)
    Use Transmit_Message(OVER_OUT) for proper two-way disconnect
]]
function RadioClass:Radio_Off()
    self.Radio = nil
end

--[[
    Get the last message received
]]
function RadioClass:Get_Last_Message()
    return self.LastMessage
end

--============================================================================
-- Message Transmission
--============================================================================

--[[
    Transmit a radio message to another object.

    @param message - RadioMessageType to send
    @param param - Optional parameter (default 0)
    @param to - Target RadioClass (nil = current contact)
    Returns reply message from receiver
]]
function RadioClass:Transmit_Message(message, param, to)
    param = param or 0

    -- Default to current radio contact if no target specified
    local target = to or self.Radio

    -- Can't transmit to nothing
    if target == nil then
        return RadioClass.RADIO.STATIC
    end

    -- Special handling for OVER_OUT - breaks contact on both ends
    if message == RadioClass.RADIO.OVER_OUT then
        -- Clear our contact
        local old_contact = self.Radio
        self.Radio = nil

        -- Tell them we're breaking contact
        if old_contact and old_contact ~= to then
            old_contact:Receive_Message(self, message, param)
        end

        -- Tell the explicit target if different
        if to then
            return to:Receive_Message(self, message, param)
        end

        return RadioClass.RADIO.ROGER
    end

    -- Forward message to target
    local reply = target:Receive_Message(self, message, param)

    -- If we sent HELLO and got ROGER, establish our side of the contact
    if message == RadioClass.RADIO.HELLO and reply == RadioClass.RADIO.ROGER then
        self.Radio = target
    end

    return reply
end

--[[
    Simplified transmit that takes message and target only
]]
function RadioClass:Transmit_Message_To(message, to)
    return self:Transmit_Message(message, 0, to)
end

--============================================================================
-- Message Reception
--============================================================================

--[[
    Receive a radio message from another object.
    Override in derived classes for specific behavior.

    @param from - RadioClass sender
    @param message - RadioMessageType received
    @param param - Message parameter (reference, can be modified)
    Returns reply message
]]
function RadioClass:Receive_Message(from, message, param)
    -- Record the message
    self.LastMessage = message

    -- Handle HELLO - establish contact
    if message == RadioClass.RADIO.HELLO then
        -- If not in contact, accept
        if not self:In_Radio_Contact() then
            self.Radio = from
            return RadioClass.RADIO.ROGER
        else
            -- Already in contact with someone else
            return RadioClass.RADIO.CANT
        end
    end

    -- Handle OVER_OUT - break contact
    if message == RadioClass.RADIO.OVER_OUT then
        if self.Radio == from then
            self.Radio = nil
        end
        return RadioClass.RADIO.ROGER
    end

    -- Default response is STATIC (no response)
    return RadioClass.RADIO.STATIC
end

--============================================================================
-- Helper Functions
--============================================================================

--[[
    Establish radio contact with another object.
    Sends HELLO message and waits for ROGER.
    Returns true if contact established.
]]
function RadioClass:Establish_Contact(target)
    if target == nil then
        return false
    end

    -- Already in contact?
    if self.Radio == target then
        return true
    end

    -- Try to establish contact
    local reply = self:Transmit_Message(RadioClass.RADIO.HELLO, 0, target)

    if reply == RadioClass.RADIO.ROGER then
        self.Radio = target
        return true
    end

    return false
end

--[[
    Break radio contact with current or specified target.
]]
function RadioClass:Break_Contact(target)
    target = target or self.Radio

    if target == nil then
        return
    end

    self:Transmit_Message(RadioClass.RADIO.OVER_OUT, 0, target)
end

--[[
    Get message name as string (for debugging)
]]
function RadioClass.Message_Name(message)
    return RadioClass.RADIO_NAMES[message] or "UNKNOWN"
end

--============================================================================
-- Limbo Override
--============================================================================

--[[
    Override Limbo to break radio contact before going into limbo
]]
function RadioClass:Limbo()
    -- Break any radio contact
    if self:In_Radio_Contact() then
        self:Transmit_Message(RadioClass.RADIO.OVER_OUT)
    end

    -- Call parent Limbo
    return Class.super(self, "Limbo")
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

--[[
    Save object state
]]
function RadioClass:Code_Pointers()
    local data = Class.super(self, "Code_Pointers") or {}

    data.LastMessage = self.LastMessage

    -- Encode radio contact as TARGET
    if self.Radio then
        data.Radio = self.Radio:As_Target()
    else
        data.Radio = Target.TARGET_NONE
    end

    return data
end

--[[
    Load object state
]]
function RadioClass:Decode_Pointers(data, heap_lookup)
    Class.super(self, "Decode_Pointers", data, heap_lookup)

    self.LastMessage = data.LastMessage or RadioClass.RADIO.STATIC

    -- Decode radio contact (requires heap lookup)
    self._decode_radio = data.Radio or Target.TARGET_NONE
    -- Actual pointer resolution happens in a second pass
end

--[[
    Resolve pointers after all objects are loaded
]]
function RadioClass:Resolve_Pointers(heap_lookup)
    if self._decode_radio and Target.Is_Valid(self._decode_radio) then
        local rtti = Target.Get_RTTI(self._decode_radio)
        local id = Target.Get_ID(self._decode_radio)
        self.Radio = heap_lookup(rtti, id)
    end
    self._decode_radio = nil
end

--============================================================================
-- Debug Support
--============================================================================

function RadioClass:Debug_Dump()
    Class.super(self, "Debug_Dump")

    local contact_str = "none"
    if self.Radio then
        contact_str = string.format("%s[%d]",
            Class.get_rtti(self.Radio) or "?",
            self.Radio:get_heap_index() or -1)
    end

    print(string.format("RadioClass: Radio=%s LastMessage=%s",
        contact_str,
        RadioClass.Message_Name(self.LastMessage)))
end

return RadioClass
