--[[
    FactoryClass - Production queue management

    Port of FACTORY.H/CPP from the original C&C source.

    The factory class handles the production of objects (units, buildings,
    infantry, aircraft). It manages build time, cost installments, and
    production state.

    Key features:
    - Stage-based production (108 steps from start to completion)
    - Installment-based payment (cost spread over production time)
    - Suspend/resume production
    - Refund on abandonment
    - Multiple factory acceleration (more factories = faster production)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/FACTORY.H
]]

local Class = require("src.objects.class")
local StageClass = require("src.objects.mixins.stage")
local Constants = require("src.core.constants")

-- Create FactoryClass with StageClass mixin
local FactoryClass = {}
FactoryClass.__index = FactoryClass

--============================================================================
-- Constants
--============================================================================

-- Number of steps to break production into
FactoryClass.STEP_COUNT = 108

-- Special item types (from DEFINES.H)
FactoryClass.SPECIAL = {
    NONE = 0,
    ION_CANNON = 1,
    NUKE = 2,
    AIR_STRIKE = 3,
}

-- RTTI types for factory acceleration
FactoryClass.RTTI = {
    INFANTRY = 1,
    UNIT = 2,
    AIRCRAFT = 3,
    BUILDING = 4,
}

-- Ticks per minute (15 ticks/sec * 60 sec)
local TICKS_PER_MINUTE = Constants.TICKS_PER_SECOND * 60

--============================================================================
-- Constructor
--============================================================================

function FactoryClass:new()
    local self = setmetatable({}, FactoryClass)

    -- Initialize StageClass fields
    self.Stage = 0
    self.StageTimer = 0
    self.Rate = 0

    -- Factory state flags
    self.IsActive = true
    self.IsSuspended = true      -- Production suspended until Start() called
    self.IsDifferent = false     -- Has production advanced since last check?
    self.IsBlocked = false       -- Exit blocked (unit can't leave)

    -- Production tracking
    self.Balance = 0             -- Remaining cost to pay
    self.OriginalBalance = 0     -- Original total cost

    -- What's being built
    self.Object = nil            -- TechnoClass being produced
    self.ObjectType = nil        -- TechnoTypeClass of object
    self.SpecialItem = FactoryClass.SPECIAL.NONE

    -- Owner
    self.House = nil             -- HouseClass that owns this factory

    return self
end

--============================================================================
-- StageClass methods (incorporated directly)
--============================================================================

function FactoryClass:Fetch_Stage()
    return self.Stage
end

function FactoryClass:Fetch_Rate()
    return self.Rate
end

function FactoryClass:Set_Stage(stage)
    self.Stage = stage
end

function FactoryClass:Set_Rate(rate)
    self.Rate = rate
    self.StageTimer = rate
end

function FactoryClass:Graphic_Logic()
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

--============================================================================
-- Factory State Queries
--============================================================================

--[[
    Check if the factory is currently building.

    @return true if production is in progress
]]
function FactoryClass:Is_Building()
    return self:Fetch_Rate() ~= 0
end

--[[
    Check if production has completed.

    @return true if object is ready for placement
]]
function FactoryClass:Has_Completed()
    if (self.Object or self.ObjectType) and self:Fetch_Stage() == FactoryClass.STEP_COUNT then
        return true
    end
    if self.SpecialItem ~= FactoryClass.SPECIAL.NONE and
       self:Fetch_Stage() == FactoryClass.STEP_COUNT then
        return true
    end
    return false
end

--[[
    Check if the production display has changed.
    Clears the changed flag as a side effect.

    @return true if production has advanced since last call
]]
function FactoryClass:Has_Changed()
    local changed = self.IsDifferent
    self.IsDifferent = false
    return changed
end

--[[
    Get the completion percentage (0-100).
]]
function FactoryClass:Completion()
    return self:Fetch_Stage()
end

--[[
    Get completion as a percentage.
]]
function FactoryClass:Completion_Percent()
    return math.floor((self:Fetch_Stage() / FactoryClass.STEP_COUNT) * 100)
end

--[[
    Get the object being produced.

    @return TechnoClass or nil
]]
function FactoryClass:Get_Object()
    return self.Object
end

--[[
    Get the special item being produced.

    @return Special item type
]]
function FactoryClass:Get_Special_Item()
    return self.SpecialItem
end

--[[
    Get the owning house.

    @return HouseClass
]]
function FactoryClass:Get_House()
    return self.House
end

--[[
    Check if exit is blocked.
]]
function FactoryClass:Is_Blocked()
    return self.IsBlocked
end

--[[
    Set blocked state.
]]
function FactoryClass:Set_Is_Blocked(blocked)
    self.IsBlocked = blocked
end

--============================================================================
-- Production Setup
--============================================================================

--[[
    Set the factory to produce an object type.

    @param object_type - TechnoTypeClass to produce
    @param house - HouseClass that owns this production
    @return true if setup successful
]]
function FactoryClass:Set(object_type, house)
    -- Abandon any current production
    self:Abandon()

    -- Set up for new production
    self.IsDifferent = true
    self.IsSuspended = true
    self:Set_Rate(0)
    self:Set_Stage(0)

    -- Store the type class
    self.ObjectType = object_type
    self.House = house

    -- Create the object in limbo
    if object_type and object_type.Create_One_Of then
        self.Object = object_type:Create_One_Of(house)
    else
        -- Fallback: just store the type, create object later
        self.Object = nil
    end

    if self.Object or self.ObjectType then
        -- Calculate cost with house bias
        local cost = object_type.Cost or 0
        local cost_bias = house and house.cost_bias or 1.0
        self.Balance = math.floor(cost * cost_bias)
        self.OriginalBalance = self.Balance

        if self.Object then
            self.Object.PurchasePrice = self.Balance
        end

        return true
    end

    return false
end

--[[
    Set the factory to produce a special item (ion cannon, nuke, etc.).

    @param special_type - Special item type
    @param house - HouseClass that owns this
    @return true if setup successful
]]
function FactoryClass:Set_Special(special_type, house)
    self:Abandon()

    self.IsDifferent = true
    self.IsSuspended = true
    self:Set_Rate(0)
    self:Set_Stage(0)

    self.SpecialItem = special_type
    self.House = house
    self.Balance = 0
    self.OriginalBalance = 0

    return special_type ~= FactoryClass.SPECIAL.NONE
end

--[[
    Fill factory with an already-completed object.
    Used when placement is cancelled and object returns to factory.

    @param object - TechnoClass to place back in factory
]]
function FactoryClass:Set_Object(object)
    self:Abandon()

    self.Object = object
    self.House = object and object.House or nil
    self.Balance = 0
    self:Set_Rate(0)
    self:Set_Stage(FactoryClass.STEP_COUNT)
    self.IsDifferent = true
    self.IsSuspended = true
end

--============================================================================
-- Production Control
--============================================================================

--[[
    Start or resume production.

    @return true if production started successfully
]]
function FactoryClass:Start()
    if (self.Object or self.ObjectType or self.SpecialItem ~= FactoryClass.SPECIAL.NONE) and
       self.IsSuspended and not self:Has_Completed() then

        -- Check if house can afford to continue
        local cost_per_tick = self:Cost_Per_Tick()
        local is_human = self.House and self.House.is_human
        local can_afford = self.House and self.House:can_afford(cost_per_tick)

        if is_human or can_afford then
            -- Calculate production time
            local time
            if self.ObjectType then
                time = self.ObjectType.BuildTime or (TICKS_PER_MINUTE * 1)
                -- Apply house build time modifier if available
                if self.House and self.House.build_time_bias then
                    time = math.floor(time * self.House.build_time_bias)
                end
            else
                -- Special items take 5 minutes
                time = TICKS_PER_MINUTE * 5
            end

            -- Divide by steps to get time per step
            time = math.floor(time / FactoryClass.STEP_COUNT)
            time = math.max(1, math.min(time, 255))

            self:Set_Rate(time)
            self.IsSuspended = false
            return true
        end
    end
    return false
end

--[[
    Suspend production temporarily.

    @return true if production was suspended
]]
function FactoryClass:Suspend()
    if not self.IsSuspended then
        self.IsSuspended = true
        self:Set_Rate(0)
        return true
    end
    return false
end

--[[
    Abandon production and refund money spent.

    @return true if something was abandoned
]]
function FactoryClass:Abandon()
    if self.Object or self.ObjectType then
        -- Refund money spent so far
        if self.House then
            local original_cost = self.OriginalBalance
            local money_spent = original_cost - self.Balance
            self.House:add_credits(money_spent)
        end
        self.Balance = 0
        self.OriginalBalance = 0

        -- Delete the object under construction
        self.Object = nil
        self.ObjectType = nil
    end

    if self.SpecialItem ~= FactoryClass.SPECIAL.NONE then
        self.SpecialItem = FactoryClass.SPECIAL.NONE
    end

    -- Reset to idle state
    self:Set_Rate(0)
    self:Set_Stage(0)
    self.IsSuspended = true
    self.IsDifferent = true

    return true
end

--[[
    Clear the factory after completed object has been placed.

    @return true if factory was cleared
]]
function FactoryClass:Completed()
    if self.Object and self:Fetch_Stage() == FactoryClass.STEP_COUNT then
        self.Object = nil
        self.ObjectType = nil
        self.IsSuspended = true
        self.IsDifferent = true
        self:Set_Stage(0)
        self:Set_Rate(0)
        return true
    end

    if self.SpecialItem ~= FactoryClass.SPECIAL.NONE and
       self:Fetch_Stage() == FactoryClass.STEP_COUNT then
        self.SpecialItem = FactoryClass.SPECIAL.NONE
        self.IsSuspended = true
        self.IsDifferent = true
        self:Set_Stage(0)
        self:Set_Rate(0)
        return true
    end

    return false
end

--============================================================================
-- Production AI
--============================================================================

--[[
    Process production for this game tick.
    Should be called once per game tick.
]]
function FactoryClass:AI()
    if not self.IsSuspended and (self.Object or self.ObjectType or
       self.SpecialItem ~= FactoryClass.SPECIAL.NONE) then

        -- Calculate acceleration factor (multiple factories)
        local stages = 1
        if self.House and self.House.is_human and self.ObjectType then
            local rtti = self.ObjectType.RTTI or 0
            if rtti == FactoryClass.RTTI.AIRCRAFT then
                stages = self.House.aircraft_factories or 1
            elseif rtti == FactoryClass.RTTI.INFANTRY then
                stages = self.House.infantry_factories or 1
            elseif rtti == FactoryClass.RTTI.UNIT then
                stages = self.House.unit_factories or 1
            elseif rtti == FactoryClass.RTTI.BUILDING then
                stages = self.House.building_factories or 1
            end
            stages = math.max(stages, 1)
        end

        -- Process multiple stages if accelerated
        for _ = 1, stages do
            if not self:Has_Completed() and self:Graphic_Logic() then
                self.IsDifferent = true

                local cost = self:Cost_Per_Tick()
                cost = math.min(cost, self.Balance)

                -- Check if house can afford this tick
                if self.House then
                    local available = self.House:available_money()
                    if cost > available then
                        -- Not enough money, go back one step
                        self:Set_Stage(self:Fetch_Stage() - 1)
                    else
                        -- Spend the money
                        self.House:spend_credits(cost)
                        self.Balance = self.Balance - cost
                    end
                else
                    -- No house, just deduct from balance
                    self.Balance = self.Balance - cost
                end

                -- Check if production completed
                if self:Fetch_Stage() == FactoryClass.STEP_COUNT then
                    self.IsSuspended = true
                    self:Set_Rate(0)
                    -- Spend any remaining balance
                    if self.House and self.Balance > 0 then
                        self.House:spend_credits(self.Balance)
                    end
                    self.Balance = 0
                end
            end
        end
    end
end

--============================================================================
-- Cost Calculation
--============================================================================

--[[
    Calculate cost per production tick.

    @return Credits needed for one tick of production
]]
function FactoryClass:Cost_Per_Tick()
    if self.Object or self.ObjectType then
        local steps_remaining = FactoryClass.STEP_COUNT - self:Fetch_Stage()
        if steps_remaining > 0 then
            return math.floor(self.Balance / steps_remaining)
        end
        return self.Balance
    end
    return 0
end

--============================================================================
-- Debug Support
--============================================================================

--[[
    Force production to complete instantly.
    For debugging/testing only.
]]
function FactoryClass:Force_Complete()
    if not self.IsSuspended and (self.Object or self.ObjectType or
       self.SpecialItem ~= FactoryClass.SPECIAL.NONE) then
        self:Set_Stage(FactoryClass.STEP_COUNT)
        self.IsSuspended = true
        self:Set_Rate(0)
        self.Balance = 0
        self.IsDifferent = true
    end
end

function FactoryClass:Debug_Dump()
    local obj_name = "none"
    if self.ObjectType then
        obj_name = self.ObjectType.Name or "unknown"
    elseif self.Object then
        obj_name = "object"
    end

    print(string.format(
        "FactoryClass: Object=%s Stage=%d/%d Balance=%d Suspended=%s Building=%s",
        obj_name,
        self:Fetch_Stage(),
        FactoryClass.STEP_COUNT,
        self.Balance,
        tostring(self.IsSuspended),
        tostring(self:Is_Building())
    ))
end

--============================================================================
-- Save/Load
--============================================================================

function FactoryClass:Code_Pointers()
    return {
        Stage = self.Stage,
        StageTimer = self.StageTimer,
        Rate = self.Rate,
        IsSuspended = self.IsSuspended,
        IsDifferent = self.IsDifferent,
        IsBlocked = self.IsBlocked,
        Balance = self.Balance,
        OriginalBalance = self.OriginalBalance,
        SpecialItem = self.SpecialItem,
        -- Object and House need special handling
    }
end

function FactoryClass:Decode_Pointers(data)
    if data then
        self.Stage = data.Stage or 0
        self.StageTimer = data.StageTimer or 0
        self.Rate = data.Rate or 0
        self.IsSuspended = data.IsSuspended ~= false
        self.IsDifferent = data.IsDifferent or false
        self.IsBlocked = data.IsBlocked or false
        self.Balance = data.Balance or 0
        self.OriginalBalance = data.OriginalBalance or 0
        self.SpecialItem = data.SpecialItem or FactoryClass.SPECIAL.NONE
    end
end

return FactoryClass
