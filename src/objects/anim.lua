--[[
    AnimClass - Animation/visual effect game object

    Port of ANIM.H/CPP from the original C&C source.

    AnimClass extends ObjectClass and incorporates StageClass mixin
    to handle frame-based animation.

    Features:
    - Frame-based animation with looping
    - Attachment to other objects
    - Ground effects (scorch marks, craters)
    - Damage over time to attached objects
    - Animation chaining

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/ANIM.H
    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/ANIM.CPP
]]

local Class = require("src.objects.class")
local ObjectClass = require("src.objects.object")
local StageClass = require("src.objects.mixins.stage")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create AnimClass extending ObjectClass
local AnimClass = Class.extend(ObjectClass, "AnimClass")

-- Include StageClass mixin for animation frame management
Class.include(AnimClass, StageClass)

--============================================================================
-- Constants
--============================================================================

-- Animation states
AnimClass.STATE = {
    DELAY = 0,      -- Waiting for delay to expire
    PLAYING = 1,    -- Animation is playing
    LOOPING = 2,    -- In loop section
    FINISHED = 3,   -- Animation complete
}

-- Maximum accumulated damage before applying (fixed-point, 256 = 1 HP)
AnimClass.DAMAGE_THRESHOLD = 256

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new AnimClass.

    @param anim_type - AnimTypeClass instance
    @param coord - Coordinate to place animation
    @param delay - Ticks before animation starts (default 0)
    @param loops - Number of loops (default from type, -1 = infinite)
    @param alt - Use alternate coloring (default false)
]]
function AnimClass:init(anim_type, coord, delay, loops, alt)
    -- Call parent constructor
    ObjectClass.init(self)

    -- Initialize StageClass mixin
    StageClass.init(self)

    --========================================================================
    -- Type Reference
    --========================================================================

    --[[
        Pointer to the animation type definition.
    ]]
    self.Class = anim_type

    --========================================================================
    -- Attachment
    --========================================================================

    --[[
        Pointer to attached object (animation follows the object's movement).
    ]]
    self.Object = nil

    --[[
        Offset from attached object's center (when attached).
    ]]
    self.AttachOffset = nil

    --[[
        Used for Y-sorting when rendering.
    ]]
    self.SortTarget = nil

    --========================================================================
    -- Ownership
    --========================================================================

    --[[
        House responsible for damage caused by animation.
    ]]
    self.OwnerHouse = nil

    --========================================================================
    -- Loop Control
    --========================================================================

    --[[
        Number of remaining loops before animation terminates.
        -1 = infinite loops
    ]]
    self.Loops = loops or (anim_type and anim_type.Loops or 1)

    --========================================================================
    -- State Flags
    --========================================================================

    --[[
        Flag to delete animation at next opportunity.
    ]]
    self.IsToDelete = false

    --[[
        Skip first logic pass for newly created anims.
    ]]
    self.IsBrandNew = true

    --[[
        Use alternate color when drawing.
    ]]
    self.IsAlternate = alt or false

    --[[
        Animation exists but is not rendered (for sync).
    ]]
    self.IsInvisible = false

    --========================================================================
    -- Timing
    --========================================================================

    --[[
        Countdown before animation starts.
    ]]
    self.Delay = delay or 0

    --[[
        Accumulated fractional damage (damage applied at 256).
    ]]
    self.DamageAccum = 0

    --========================================================================
    -- Animation State
    --========================================================================

    self.AnimState = AnimClass.STATE.DELAY
    if self.Delay == 0 then
        self.AnimState = AnimClass.STATE.PLAYING
    end

    --========================================================================
    -- Apply Type Properties
    --========================================================================

    if anim_type then
        -- Set initial frame
        self:Set_Stage(anim_type.Start or 0)
        self:Set_Rate(anim_type.Delay or 1)
    end

    --========================================================================
    -- Place on Map
    --========================================================================

    if coord then
        self.Coord = coord
        self.IsInLimbo = false
    end
end

--============================================================================
-- Type Identification
--============================================================================

--[[
    Returns what RTTI type this object is.
]]
function AnimClass:What_Am_I()
    return Target.RTTI.ANIM
end

--[[
    Get the animation type class.
]]
function AnimClass:Get_Type()
    return self.Class
end

--============================================================================
-- Attachment
--============================================================================

--[[
    Attach this animation to follow an object.

    @param obj - Object to attach to
]]
function AnimClass:Attach_To(obj)
    if not obj then return end

    self.Object = obj

    -- Convert absolute coordinate to offset from object center
    if self.Coord and obj.Coord then
        local ax, ay = Coord.From_Lepton(self.Coord)
        local ox, oy = Coord.From_Lepton(obj:Center_Coord())
        self.AttachOffset = { x = ax - ox, y = ay - oy }
    else
        self.AttachOffset = { x = 0, y = 0 }
    end

    -- Mark object as having animation attached
    obj.IsAnimAttached = true
end

--[[
    Detach from current object.
]]
function AnimClass:Detach_From_Object()
    if self.Object then
        self.Object.IsAnimAttached = false
        self.Object = nil
        self.AttachOffset = nil
    end
end

--[[
    Force animation to sort above specified target.

    @param target - Target to sort above
]]
function AnimClass:Sort_Above(target)
    self.SortTarget = target
end

--============================================================================
-- Visibility
--============================================================================

--[[
    Make animation invisible (but still exists for sync).
]]
function AnimClass:Make_Invisible()
    self.IsInvisible = true
end

--[[
    Make animation visible again.
]]
function AnimClass:Make_Visible()
    self.IsInvisible = false
end

--============================================================================
-- AI - Main Logic
--============================================================================

--[[
    Main animation logic called every game tick.
]]
function AnimClass:AI()
    ObjectClass.AI(self)

    if self.IsInLimbo then return end

    -- Skip first frame for brand new anims
    if self.IsBrandNew then
        self.IsBrandNew = false
        return
    end

    -- Handle deletion
    if self.IsToDelete then
        self:Limbo()
        self.IsActive = false
        return
    end

    -- Handle delay countdown
    if self.Delay > 0 then
        self.Delay = self.Delay - 1
        if self.Delay == 0 then
            self.AnimState = AnimClass.STATE.PLAYING
            self:Start()
        end
        return
    end

    -- Update attached position
    if self.Object then
        if not self.Object.IsActive then
            -- Attached object was destroyed
            self:Detach_From_Object()
        else
            -- Update position to follow object
            local ox, oy = Coord.From_Lepton(self.Object:Center_Coord())
            self.Coord = Coord.To_Lepton(
                ox + (self.AttachOffset and self.AttachOffset.x or 0),
                oy + (self.AttachOffset and self.AttachOffset.y or 0)
            )
        end
    end

    -- Apply damage to attached object
    if self.Object and self.Class and self.Class.Damage > 0 then
        self.DamageAccum = self.DamageAccum + self.Class.Damage
        if self.DamageAccum >= AnimClass.DAMAGE_THRESHOLD then
            local damage = math.floor(self.DamageAccum / AnimClass.DAMAGE_THRESHOLD)
            self.DamageAccum = self.DamageAccum % AnimClass.DAMAGE_THRESHOLD

            if self.Object.Take_Damage then
                self.Object:Take_Damage(damage, 0, nil, self.OwnerHouse)
            end
        end
    end

    -- Advance animation frame
    local frame_changed = self:Graphic_Logic()

    if frame_changed then
        local current_stage = self:Fetch_Stage()

        -- Check if at largest frame (trigger middle effects)
        if self.Class and current_stage == self.Class.Biggest then
            self:Middle()
        end

        -- Check for loop boundary
        if self.Class then
            local loop_end = self.Class.LoopEnd
            if loop_end > 0 and current_stage >= loop_end then
                -- End of loop section
                if self.Loops > 0 then
                    self.Loops = self.Loops - 1
                end

                if self.Loops == 0 then
                    -- Loops exhausted, check for chain
                    if self.Class.ChainTo >= 0 then
                        self:Chain()
                    else
                        self.AnimState = AnimClass.STATE.FINISHED
                        self.IsToDelete = true
                    end
                else
                    -- Continue looping
                    self:Set_Stage(self.Class.LoopStart or 0)
                    self.AnimState = AnimClass.STATE.LOOPING
                end
            end
        end

        -- Check for end of animation
        if self.Class and current_stage >= self.Class.Stages then
            if self.Loops > 0 then
                self.Loops = self.Loops - 1
            end

            if self.Loops == 0 then
                if self.Class.ChainTo >= 0 then
                    self:Chain()
                else
                    self.AnimState = AnimClass.STATE.FINISHED
                    self.IsToDelete = true
                end
            elseif self.Loops ~= 0 then
                -- Loop back
                self:Set_Stage(self.Class.LoopStart or self.Class.Start or 0)
            end
        end
    end
end

--============================================================================
-- Animation Events
--============================================================================

--[[
    Called when animation starts (delay expires).
]]
function AnimClass:Start()
    -- Play sound effect
    if self.Class and self.Class.Sound >= 0 then
        -- Would play sound here
        -- Sound.Play(self.Class.Sound, self.Coord)
    end

    -- Check for immediate middle effects
    if self.Class and self.Class.Biggest == 0 then
        self:Middle()
    end

    -- Auto-attach if sticky
    if self.Class and self.Class.IsSticky then
        -- Would search for objects at same cell to attach to
    end
end

--[[
    Called at midpoint (largest frame) for ground effects.
]]
function AnimClass:Middle()
    if not self.Class then return end

    local coord = self:Center_Coord()

    -- Create scorch marks
    if self.Class.IsScorcher then
        -- Would create SmudgeClass (scorch mark) here
    end

    -- Create craters (also reduces Tiberium)
    if self.Class.IsCraterForming then
        -- Would create SmudgeClass (crater) here
        -- Would also remove Tiberium from cell
    end

    -- Special handling for specific animations
    -- (Ion cannon, nuke, napalm spawning fires, etc.)
end

--[[
    Transition to chain animation.
]]
function AnimClass:Chain()
    if not self.Class or self.Class.ChainTo < 0 then return end

    -- Would look up AnimTypeClass for ChainTo and morph into it
    -- For now, just mark for deletion
    self.IsToDelete = true
end

--============================================================================
-- Coordinate/Position
--============================================================================

--[[
    Get the center coordinate (factoring in attachment).
]]
function AnimClass:Center_Coord()
    if self.Object and self.Object.IsActive then
        local ox, oy = Coord.From_Lepton(self.Object:Center_Coord())
        return Coord.To_Lepton(
            ox + (self.AttachOffset and self.AttachOffset.x or 0),
            oy + (self.AttachOffset and self.AttachOffset.y or 0)
        )
    end
    return self.Coord
end

--[[
    Get Y coordinate for depth sorting.
]]
function AnimClass:Sort_Y()
    if self.SortTarget then
        if type(self.SortTarget) == "table" and self.SortTarget.Sort_Y then
            return self.SortTarget:Sort_Y()
        end
    end
    return Coord.Y_From_Lepton(self:Center_Coord())
end

--============================================================================
-- Layer
--============================================================================

--[[
    Return which render layer this animation is in.
]]
function AnimClass:In_Which_Layer()
    -- Ground layer if attached or explicitly ground layer type
    if self.Object then
        return ObjectClass.LAYER.GROUND
    end
    if self.Class and self.Class.IsGroundLayer then
        return ObjectClass.LAYER.GROUND
    end
    return ObjectClass.LAYER.AIR
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Render the animation.
]]
function AnimClass:Draw_It(x, y)
    if self.IsInvisible then return end

    -- Would draw animation sprite at current stage
    local stage = self:Fetch_Stage()

    -- Handle translucency
    if self.Class and self.Class.IsTranslucent then
        -- Would use translucent blending
    end

    -- Handle house-specific coloring
    if self.IsAlternate and self.OwnerHouse then
        -- Would remap colors for house
    end
end

--============================================================================
-- Target Handling
--============================================================================

--[[
    Called when attached object is destroyed.
]]
function AnimClass:Detach(target)
    if self.Object == target then
        self:Detach_From_Object()
    end
end

--============================================================================
-- Debug Support
--============================================================================

function AnimClass:Debug_Dump()
    ObjectClass.Debug_Dump(self)

    print(string.format("AnimClass: Type=%s Stage=%d/%d Loops=%d",
        self.Class and self.Class.IniName or "none",
        self:Fetch_Stage(),
        self.Class and self.Class.Stages or 0,
        self.Loops))

    print(string.format("  State: %d Delay=%d Attached=%s",
        self.AnimState,
        self.Delay,
        self.Object and "yes" or "no"))
end

return AnimClass
