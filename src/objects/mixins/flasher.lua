--[[
    FlasherClass - Damage flash visual effect mixin

    Port of FLASHER.H/CPP from the original C&C source.

    This mixin provides visual feedback when objects are targeted or damaged.
    When an object is targeted, it will "flash" lighter for a brief period.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/FLASHER.H
]]

local Class = require("src.objects.class")

-- Create FlasherClass as a mixin
local FlasherClass = Class.mixin("FlasherClass")

--============================================================================
-- Constants
--============================================================================

-- Default number of flashes when targeted
FlasherClass.DEFAULT_FLASH_COUNT = 7

-- Maximum house count for per-player flash tracking
FlasherClass.HOUSE_COUNT = 8

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize flasher state.
    Called automatically when mixed into a class.
]]
function FlasherClass:init()
    --[[
        When this object is targeted, it will flash a number of times. This is the
        flash control number. It counts down to zero and then stops. Odd values
        cause the object to be rendered in a lighter color.
    ]]
    self.FlashCount = 0

    --[[
        When an object is targeted, it flashes several times to give visual feedback
        to the player. Every other game "frame", this flag is true until the flashing
        is determined to be completed.
    ]]
    self.IsBlushing = false

    --[[
        Per-player flash tracking (for multiplayer).
        Each house can have its own flash state.
    ]]
    self.FlashCountPerPlayer = {}
    for i = 0, FlasherClass.HOUSE_COUNT - 1 do
        self.FlashCountPerPlayer[i] = 0
    end
end

--============================================================================
-- Flash Processing
--============================================================================

--[[
    Process the flash state for this game tick.
    Should be called from AI() each game tick.

    @return true if state changed and redraw is needed
]]
function FlasherClass:Process()
    local redraw = false

    if self.FlashCount > 0 then
        self.FlashCount = self.FlashCount - 1

        -- Odd values cause blushing (lighter rendering)
        local new_blushing = (self.FlashCount % 2) == 1
        if new_blushing ~= self.IsBlushing then
            self.IsBlushing = new_blushing
            redraw = true
        end

        -- When count reaches zero, ensure blushing is off
        if self.FlashCount == 0 then
            self.IsBlushing = false
            redraw = true
        end
    end

    return redraw
end

--============================================================================
-- Flash Control
--============================================================================

--[[
    Start flashing this object.
    Called when the object is targeted.

    @param count - Number of flash cycles (default: DEFAULT_FLASH_COUNT)
]]
function FlasherClass:Start_Flash(count)
    count = count or FlasherClass.DEFAULT_FLASH_COUNT
    self.FlashCount = count
end

--[[
    Stop flashing immediately.
]]
function FlasherClass:Stop_Flash()
    self.FlashCount = 0
    self.IsBlushing = false
end

--[[
    Check if currently flashing.
]]
function FlasherClass:Is_Flashing()
    return self.FlashCount > 0
end

--[[
    Check if currently blushing (should render lighter).
]]
function FlasherClass:Is_Blushing()
    return self.IsBlushing
end

--============================================================================
-- Per-Player Flash Support (Multiplayer)
--============================================================================

--[[
    Start flashing for a specific player.

    @param house - House index (0-7)
    @param count - Number of flash cycles
]]
function FlasherClass:Start_Flash_For_Player(house, count)
    count = count or FlasherClass.DEFAULT_FLASH_COUNT
    if house >= 0 and house < FlasherClass.HOUSE_COUNT then
        self.FlashCountPerPlayer[house] = count
    end
end

--[[
    Get flashing flags as a bitmask.
    Each bit represents whether a house has an active flash.
]]
function FlasherClass:Get_Flashing_Flags()
    local flags = 0
    for i = 0, FlasherClass.HOUSE_COUNT - 1 do
        if self.FlashCountPerPlayer[i] > 0 then
            flags = flags + (2 ^ i)
        end
    end
    return flags
end

--[[
    Process per-player flash state.

    @return true if any player's state changed
]]
function FlasherClass:Process_Per_Player()
    local changed = false
    for i = 0, FlasherClass.HOUSE_COUNT - 1 do
        if self.FlashCountPerPlayer[i] > 0 then
            self.FlashCountPerPlayer[i] = self.FlashCountPerPlayer[i] - 1
            changed = true
        end
    end
    return changed
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function FlasherClass:Code_Pointers_Flasher()
    return {
        FlashCount = self.FlashCount,
        IsBlushing = self.IsBlushing,
        FlashCountPerPlayer = self.FlashCountPerPlayer,
    }
end

function FlasherClass:Decode_Pointers_Flasher(data)
    if data then
        self.FlashCount = data.FlashCount or 0
        self.IsBlushing = data.IsBlushing or false
        if data.FlashCountPerPlayer then
            self.FlashCountPerPlayer = data.FlashCountPerPlayer
        end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function FlasherClass:Debug_Dump_Flasher()
    print(string.format("FlasherClass: FlashCount=%d Blushing=%s",
        self.FlashCount,
        tostring(self.IsBlushing)))
end

return FlasherClass
