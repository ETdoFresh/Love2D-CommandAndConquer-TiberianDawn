--[[
    CrewClass - Crew/survivor generation mixin

    Port of CREW.H/CPP from the original C&C source.

    This mixin tracks kills and provides crew/survivor type generation
    when vehicles or buildings are destroyed.

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/CREW.H
]]

local Class = require("src.objects.class")

-- Create CrewClass as a mixin
local CrewClass = Class.mixin("CrewClass")

--============================================================================
-- Constants
--============================================================================

-- Kill thresholds for rank promotion
CrewClass.RANK_THRESHOLDS = {
    ROOKIE = 0,
    VETERAN = 3,
    ELITE = 10,
}

--============================================================================
-- Mixin Initialization
--============================================================================

--[[
    Initialize crew state.
    Called automatically when mixed into a class.
]]
function CrewClass:init()
    --[[
        This keeps track of the number of "kills" the unit as accumulated.
        When it reaches a certain point, the unit improves (gains rank).
    ]]
    self.Kills = 0
end

--============================================================================
-- Kill Tracking
--============================================================================

--[[
    Record a kill for this unit.
    Returns the new kill count.
]]
function CrewClass:Made_A_Kill()
    self.Kills = self.Kills + 1
    return self.Kills
end

--[[
    Get the current kill count.
]]
function CrewClass:Get_Kills()
    return self.Kills
end

--[[
    Set the kill count directly.
    Used for save/load and initialization.

    @param kills - New kill count
]]
function CrewClass:Set_Kills(kills)
    self.Kills = kills or 0
end

--============================================================================
-- Rank System
--============================================================================

--[[
    Get the current rank level based on kills.
    Returns: 0=Rookie, 1=Veteran, 2=Elite
]]
function CrewClass:Get_Rank()
    if self.Kills >= CrewClass.RANK_THRESHOLDS.ELITE then
        return 2  -- Elite
    elseif self.Kills >= CrewClass.RANK_THRESHOLDS.VETERAN then
        return 1  -- Veteran
    else
        return 0  -- Rookie
    end
end

--[[
    Get the rank name as a string.
]]
function CrewClass:Get_Rank_Name()
    local rank = self:Get_Rank()
    if rank == 2 then
        return "Elite"
    elseif rank == 1 then
        return "Veteran"
    else
        return "Rookie"
    end
end

--[[
    Check if unit is elite (highest rank).
]]
function CrewClass:Is_Elite()
    return self.Kills >= CrewClass.RANK_THRESHOLDS.ELITE
end

--[[
    Check if unit is at least veteran rank.
]]
function CrewClass:Is_Veteran()
    return self.Kills >= CrewClass.RANK_THRESHOLDS.VETERAN
end

--============================================================================
-- Crew Type Generation
--============================================================================

--[[
    Get the crew type that should spawn when this object is destroyed.
    Override in derived classes for specific behavior.

    In the original C&C, different units spawn different infantry types.
    E.g., GDI vehicles spawn minigunners, Nod vehicles spawn basic infantry, etc.

    @return InfantryType enum value
]]
function CrewClass:Crew_Type()
    -- Default to E1 (Minigunner/basic infantry)
    -- This should be overridden based on house/unit type
    return 0  -- INFANTRY_E1
end

--[[
    Check if this object should spawn crew when destroyed.
    Some objects don't spawn survivors (aircraft, some buildings).

    @return true if should spawn crew
]]
function CrewClass:Should_Spawn_Crew()
    -- Override in derived classes
    -- Default is true for vehicles
    return true
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function CrewClass:Code_Pointers_Crew()
    return {
        Kills = self.Kills,
    }
end

function CrewClass:Decode_Pointers_Crew(data)
    if data then
        self.Kills = data.Kills or 0
    end
end

--============================================================================
-- Debug Support
--============================================================================

function CrewClass:Debug_Dump_Crew()
    print(string.format("CrewClass: Kills=%d Rank=%s",
        self.Kills,
        self:Get_Rank_Name()))
end

return CrewClass
