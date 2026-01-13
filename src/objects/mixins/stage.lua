--[[
    StageClass - Animation frame staging mixin

    Port of STAGE.H/CPP from the original C&C source.

    This mixin provides animation frame management for objects.
    It handles animation timing and frame progression.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/STAGE.H
]]

local Class = require("src.objects.class")

-- Create StageClass as a mixin
local StageClass = Class.mixin("StageClass")

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize stage state.
    Called automatically when mixed into a class.
]]
function StageClass:init()
    --[[
        This handles the animation stage of the object. This includes smoke, walking,
        flapping, and rocket flames.
    ]]
    self.Stage = 0

    --[[
        This is the countdown timer for stage animation. When this counts down
        to zero, then the stage increments by one and the time cycle starts
        over again.
    ]]
    self.StageTimer = 0

    --[[
        This is the value to assign the StageTimer whenever it needs to be reset. Thus,
        this value is the control of how fast the stage value increments.
    ]]
    self.Rate = 0
end

--============================================================================
-- Stage Query
--============================================================================

--[[
    Get the current animation stage.
]]
function StageClass:Fetch_Stage()
    return self.Stage
end

--[[
    Get the current animation rate.
]]
function StageClass:Fetch_Rate()
    return self.Rate
end

--============================================================================
-- Stage Control
--============================================================================

--[[
    Set the current animation stage.

    @param stage - New stage value
]]
function StageClass:Set_Stage(stage)
    self.Stage = stage
end

--[[
    Set the animation rate (ticks per stage).

    @param rate - Ticks per stage (0 = no animation)
]]
function StageClass:Set_Rate(rate)
    self.Rate = rate
    self.StageTimer = rate
end

--============================================================================
-- Animation Processing
--============================================================================

--[[
    AI processing for stage.
    Currently empty in the original - animation is done in Graphic_Logic.
]]
function StageClass:AI_Stage()
    -- Empty in original
end

--[[
    Process the animation stage for this game tick.
    Should be called from the rendering/graphics loop.

    @return true if stage changed and redraw is needed
]]
function StageClass:Graphic_Logic()
    if self.Rate > 0 then
        self.StageTimer = self.StageTimer - 1
        if self.StageTimer <= 0 then
            self.Stage = self.Stage + 1
            self.StageTimer = self.Rate
            return true
        end
    end
    return false
end

--[[
    Reset the stage to the beginning.
]]
function StageClass:Reset_Stage()
    self.Stage = 0
    self.StageTimer = self.Rate
end

--[[
    Get how many ticks until the next stage change.
]]
function StageClass:Time_To_Next_Stage()
    if self.Rate <= 0 then
        return -1  -- No animation
    end
    return self.StageTimer
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function StageClass:Code_Pointers_Stage()
    return {
        Stage = self.Stage,
        StageTimer = self.StageTimer,
        Rate = self.Rate,
    }
end

function StageClass:Decode_Pointers_Stage(data)
    if data then
        self.Stage = data.Stage or 0
        self.StageTimer = data.StageTimer or 0
        self.Rate = data.Rate or 0
    end
end

--============================================================================
-- Debug Support
--============================================================================

function StageClass:Debug_Dump_Stage()
    print(string.format("StageClass: Stage=%d Timer=%d Rate=%d",
        self.Stage,
        self.StageTimer,
        self.Rate))
end

return StageClass
