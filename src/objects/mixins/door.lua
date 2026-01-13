--[[
    DoorClass - Building door animation state mixin

    Port of DOOR.H/CPP from the original C&C source.

    This mixin provides door animation management for buildings and vehicles
    that have doors (War Factory, Barracks, APC, etc.).

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/DOOR.H
]]

local Class = require("src.objects.class")

-- Create DoorClass as a mixin
local DoorClass = Class.mixin("DoorClass")

--============================================================================
-- Constants
--============================================================================

-- Door states
DoorClass.STATE = {
    CLOSED = 0,     -- Door is closed
    OPENING = 1,    -- Door is in the process of opening
    OPEN = 2,       -- Door is fully open
    CLOSING = 3,    -- Door is in the process of closing
}

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize door state.
    Called automatically when mixed into a class.
]]
function DoorClass:init()
    --[[
        Animation control for the door.
    ]]
    self.DoorStage = 0
    self.DoorTimer = 0
    self.DoorRate = 0

    --[[
        This is the recorded number of stages of the current
        door animation process.
    ]]
    self.DoorStages = 0

    --[[
        This is the door state.
    ]]
    self.DoorState = DoorClass.STATE.CLOSED

    --[[
        If the animation for this door indicates that the object it is
        attached to should be redrawn, then this flag will be true.
    ]]
    self.IsDoorToRedraw = false
end

--============================================================================
-- Door Query
--============================================================================

--[[
    Check if door needs redrawing.
]]
function DoorClass:Time_To_Redraw()
    return self.IsDoorToRedraw
end

--[[
    Clear the redraw flag.
]]
function DoorClass:Clear_Redraw_Flag()
    self.IsDoorToRedraw = false
end

--[[
    Get the current door animation stage.
]]
function DoorClass:Door_Stage()
    return self.DoorStage
end

--[[
    Check if door is opening.
]]
function DoorClass:Is_Door_Opening()
    return self.DoorState == DoorClass.STATE.OPENING
end

--[[
    Check if door is closing.
]]
function DoorClass:Is_Door_Closing()
    return self.DoorState == DoorClass.STATE.CLOSING
end

--[[
    Check if door is fully open.
]]
function DoorClass:Is_Door_Open()
    return self.DoorState == DoorClass.STATE.OPEN
end

--[[
    Check if door is fully closed.
]]
function DoorClass:Is_Door_Closed()
    return self.DoorState == DoorClass.STATE.CLOSED
end

--[[
    Check if door is ready to open (fully closed and idle).
]]
function DoorClass:Is_Ready_To_Open()
    return self.DoorState == DoorClass.STATE.CLOSED
end

--============================================================================
-- Door Control
--============================================================================

--[[
    Start opening the door.

    @param rate - Animation rate (ticks per stage)
    @param stages - Number of animation stages
    @return true if door started opening
]]
function DoorClass:Open_Door(rate, stages)
    if self.DoorState == DoorClass.STATE.CLOSED or
       self.DoorState == DoorClass.STATE.CLOSING then

        self.DoorState = DoorClass.STATE.OPENING
        self.DoorRate = rate
        self.DoorTimer = rate
        self.DoorStages = stages

        -- If closing, continue from current stage
        -- Otherwise start from 0
        if self.DoorStage <= 0 then
            self.DoorStage = 0
        end

        self.IsDoorToRedraw = true
        return true
    end

    return false
end

--[[
    Start closing the door.

    @param rate - Animation rate (ticks per stage)
    @param stages - Number of animation stages
    @return true if door started closing
]]
function DoorClass:Close_Door(rate, stages)
    if self.DoorState == DoorClass.STATE.OPEN or
       self.DoorState == DoorClass.STATE.OPENING then

        self.DoorState = DoorClass.STATE.CLOSING
        self.DoorRate = rate
        self.DoorTimer = rate
        self.DoorStages = stages

        -- If opening, continue from current stage
        -- Otherwise start from full open
        if self.DoorStage >= stages then
            self.DoorStage = stages
        end

        self.IsDoorToRedraw = true
        return true
    end

    return false
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for door animation.
    Should be called from the main AI() each game tick.
]]
function DoorClass:AI_Door()
    if self.DoorState == DoorClass.STATE.OPENING then
        self.DoorTimer = self.DoorTimer - 1
        if self.DoorTimer <= 0 then
            self.DoorTimer = self.DoorRate
            self.DoorStage = self.DoorStage + 1
            self.IsDoorToRedraw = true

            -- Check if fully open
            if self.DoorStage >= self.DoorStages then
                self.DoorState = DoorClass.STATE.OPEN
                self.DoorStage = self.DoorStages
            end
        end

    elseif self.DoorState == DoorClass.STATE.CLOSING then
        self.DoorTimer = self.DoorTimer - 1
        if self.DoorTimer <= 0 then
            self.DoorTimer = self.DoorRate
            self.DoorStage = self.DoorStage - 1
            self.IsDoorToRedraw = true

            -- Check if fully closed
            if self.DoorStage <= 0 then
                self.DoorState = DoorClass.STATE.CLOSED
                self.DoorStage = 0
            end
        end
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function DoorClass:Code_Pointers_Door()
    return {
        DoorStage = self.DoorStage,
        DoorTimer = self.DoorTimer,
        DoorRate = self.DoorRate,
        DoorStages = self.DoorStages,
        DoorState = self.DoorState,
    }
end

function DoorClass:Decode_Pointers_Door(data)
    if data then
        self.DoorStage = data.DoorStage or 0
        self.DoorTimer = data.DoorTimer or 0
        self.DoorRate = data.DoorRate or 0
        self.DoorStages = data.DoorStages or 0
        self.DoorState = data.DoorState or DoorClass.STATE.CLOSED
    end
    self.IsDoorToRedraw = false
end

--============================================================================
-- Debug Support
--============================================================================

local STATE_NAMES = {
    [0] = "CLOSED",
    [1] = "OPENING",
    [2] = "OPEN",
    [3] = "CLOSING",
}

function DoorClass:Debug_Dump_Door()
    print(string.format("DoorClass: State=%s Stage=%d/%d Timer=%d",
        STATE_NAMES[self.DoorState] or "?",
        self.DoorStage,
        self.DoorStages,
        self.DoorTimer))
end

return DoorClass
