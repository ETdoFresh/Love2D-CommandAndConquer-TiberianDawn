--[[
    DriveClass - Ground vehicle movement class

    Port of DRIVE.H/CPP from the original C&C source.

    This class extends FootClass to provide ground movement for vehicles:
    - Track-based smooth turning
    - Tiberium storage for harvesters
    - Harvesting state management
    - Collision detection with other ground units

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/DRIVE.H
]]

local Class = require("src.objects.class")
local FootClass = require("src.objects.foot")
local Coord = require("src.core.coord")

-- Create DriveClass extending FootClass
local DriveClass = Class.extend(FootClass, "DriveClass")

--============================================================================
-- Constants
--============================================================================

-- Maximum tiberium a harvester can carry (100 units)
DriveClass.MAX_TIBERIUM = 100

-- Track types for smooth turning
DriveClass.TRACK = {
    NONE = -1,
    STRAIGHT = 0,
    CURVE_LEFT = 1,
    CURVE_RIGHT = 2,
    U_TURN_LEFT = 3,
    U_TURN_RIGHT = 4,
}

-- Number of stages in each track type
DriveClass.TRACK_STAGES = {
    [0] = 12,  -- STRAIGHT
    [1] = 8,   -- CURVE_LEFT
    [2] = 8,   -- CURVE_RIGHT
    [3] = 16,  -- U_TURN_LEFT
    [4] = 16,  -- U_TURN_RIGHT
}

--============================================================================
-- Constructor
--============================================================================

function DriveClass:init(house)
    -- Call parent constructor
    FootClass.init(self, house)

    --[[
        This is the amount of tiberium stored in the harvester.
        A value of 0 means empty, MAX_TIBERIUM means full.
    ]]
    self.Tiberium = 0

    --[[
        When the harvester is busy harvesting, this flag is set.
        It is used to play the harvesting animation and sound.
    ]]
    self.IsHarvesting = false

    --[[
        When the harvester is returning to the refinery, this flag is set.
        This prevents unnecessary recalculation of the destination.
    ]]
    self.IsReturning = false

    --[[
        When this flag is set, the turret (if any) is locked in the
        body-forward direction. Used during deployment animations.
    ]]
    self.IsTurretLockedDown = false

    --[[
        This indicates which track the vehicle is following.
        A value of -1 means no track.
    ]]
    self.TrackNumber = DriveClass.TRACK.NONE

    --[[
        This is the current index into the track's animation sequence.
        It advances each game tick while following a track.
    ]]
    self.TrackIndex = 0

    --[[
        The facing direction when the track started.
        Used to calculate final position/facing.
    ]]
    self.StartFacing = 0

    --[[
        The target facing direction at end of track.
    ]]
    self.TargetFacing = 0

    --[[
        The coordinate where this track started.
    ]]
    self.TrackStartCoord = 0

    --[[
        Speed accumulator for sub-cell movement.
        Accumulates fractional movement until full cell movement occurs.
    ]]
    self.SpeedAccum = 0
end

--============================================================================
-- Query Functions
--============================================================================

--[[
    Check if this is a harvester.
    Override in UnitClass based on unit type.
]]
function DriveClass:Is_Harvester()
    return false  -- Override in UnitClass
end

--[[
    Get the percentage of tiberium stored (0-100).
]]
function DriveClass:Tiberium_Percentage()
    if self:Is_Harvester() then
        return math.floor((self.Tiberium / DriveClass.MAX_TIBERIUM) * 100)
    end
    return 0
end

--[[
    Check if harvester is full.
]]
function DriveClass:Is_Harvester_Full()
    return self.Tiberium >= DriveClass.MAX_TIBERIUM
end

--[[
    Check if harvester is empty.
]]
function DriveClass:Is_Harvester_Empty()
    return self.Tiberium <= 0
end

--[[
    Check if currently following a track.
]]
function DriveClass:Is_On_Track()
    return self.TrackNumber ~= DriveClass.TRACK.NONE
end

--============================================================================
-- Tiberium Harvesting
--============================================================================

--[[
    Harvest tiberium from current cell.
    Returns true if tiberium was harvested.
]]
function DriveClass:Harvest_Tiberium()
    if not self:Is_Harvester() then
        return false
    end

    if self:Is_Harvester_Full() then
        return false
    end

    -- Would check cell for tiberium here
    -- For now, simplified implementation
    self.Tiberium = math.min(self.Tiberium + 1, DriveClass.MAX_TIBERIUM)
    self.IsHarvesting = true

    return true
end

--[[
    Offload a unit of tiberium to the refinery.
    Returns the value of tiberium offloaded.
]]
function DriveClass:Offload_Tiberium_Bail()
    if self.Tiberium > 0 then
        self.Tiberium = self.Tiberium - 1
        return 25  -- Value per bail
    end
    return 0
end

--[[
    Start returning to refinery.
]]
function DriveClass:Start_Return()
    self.IsReturning = true
    self.IsHarvesting = false
    -- Would set NavCom to nearest refinery here
end

--[[
    Stop returning to refinery.
]]
function DriveClass:Stop_Return()
    self.IsReturning = false
end

--============================================================================
-- Track-Based Movement
--============================================================================

--[[
    Determine which track to use for a turn.

    @param current_facing - Current body facing (0-255)
    @param desired_facing - Desired facing
    @return Track number to use
]]
function DriveClass:Determine_Track(current_facing, desired_facing)
    local diff = (desired_facing - current_facing) % 256

    -- Normalize to -128 to 127 range
    if diff > 128 then
        diff = diff - 256
    end

    -- Determine track type based on turn amount
    if diff == 0 then
        return DriveClass.TRACK.STRAIGHT
    elseif diff > 0 and diff <= 32 then
        return DriveClass.TRACK.CURVE_RIGHT
    elseif diff < 0 and diff >= -32 then
        return DriveClass.TRACK.CURVE_LEFT
    elseif diff > 0 then
        return DriveClass.TRACK.U_TURN_RIGHT
    else
        return DriveClass.TRACK.U_TURN_LEFT
    end
end

--[[
    Start following a track.

    @param track - Track number
    @param target_facing - Target facing at end of track
    @return true if track started successfully
]]
function DriveClass:Start_Track(track, target_facing)
    if track == DriveClass.TRACK.NONE then
        return false
    end

    self.TrackNumber = track
    self.TrackIndex = 0
    self.StartFacing = self.PrimaryFacing and self.PrimaryFacing.Current or 0
    self.TargetFacing = target_facing
    self.TrackStartCoord = self:Center_Coord()
    self.IsDriving = true

    return true
end

--[[
    Stop following the current track.
]]
function DriveClass:Stop_Track()
    self.TrackNumber = DriveClass.TRACK.NONE
    self.TrackIndex = 0
end

--[[
    Process one tick of track following.
    Returns true if track is complete.
]]
function DriveClass:Follow_Track()
    if self.TrackNumber == DriveClass.TRACK.NONE then
        return true
    end

    local stages = DriveClass.TRACK_STAGES[self.TrackNumber] or 12

    -- Advance track index
    self.TrackIndex = self.TrackIndex + 1

    -- Calculate intermediate facing
    if self.PrimaryFacing then
        local progress = self.TrackIndex / stages
        local facing_diff = self.TargetFacing - self.StartFacing
        if facing_diff > 128 then facing_diff = facing_diff - 256 end
        if facing_diff < -128 then facing_diff = facing_diff + 256 end

        local new_facing = (self.StartFacing + math.floor(facing_diff * progress)) % 256
        self.PrimaryFacing.Current = new_facing
    end

    -- Check if track complete
    if self.TrackIndex >= stages then
        -- Finalize facing
        if self.PrimaryFacing then
            self.PrimaryFacing.Current = self.TargetFacing
        end

        self:Stop_Track()
        return true
    end

    return false
end

--============================================================================
-- Turning
--============================================================================

--[[
    Perform a turn toward the target facing.
    Called each game tick.

    @return true if turn is complete
]]
function DriveClass:Do_Turn()
    if not self.PrimaryFacing then
        return true
    end

    local current = self.PrimaryFacing.Current
    local desired = self.PrimaryFacing.Desired

    if current == desired then
        return true
    end

    -- If on track, let track handle facing
    if self:Is_On_Track() then
        return false
    end

    -- Simple turn logic (full track-based turning would be more complex)
    local diff = (desired - current) % 256
    if diff > 128 then
        diff = diff - 256
    end

    -- Turn rate based on ROT (Rate Of Turn)
    local turn_rate = 8  -- Default, would come from unit type

    if math.abs(diff) <= turn_rate then
        self.PrimaryFacing.Current = desired
        return true
    elseif diff > 0 then
        self.PrimaryFacing.Current = (current + turn_rate) % 256
    else
        self.PrimaryFacing.Current = (current - turn_rate + 256) % 256
    end

    self.IsRotating = true
    return false
end

--============================================================================
-- Movement
--============================================================================

--[[
    Start driving to a coordinate.
    Override from FootClass to use tracks.
]]
function DriveClass:Start_Driver(headto)
    if self.IsDriving then
        return false
    end

    self.HeadToCoord = headto
    self.IsDriving = true
    self.IsNewNavCom = false

    -- Determine track needed
    local current_coord = self:Center_Coord()
    local dx = Coord.Coord_X(headto) - Coord.Coord_X(current_coord)
    local dy = Coord.Coord_Y(headto) - Coord.Coord_Y(current_coord)

    -- Calculate desired facing
    local desired_facing = 0
    if dx ~= 0 or dy ~= 0 then
        -- Simple 8-direction facing
        desired_facing = math.floor(math.atan2(dy, dx) * 128 / math.pi + 64) % 256
    end

    -- Start appropriate track
    local current_facing = self.PrimaryFacing and self.PrimaryFacing.Current or 0
    local track = self:Determine_Track(current_facing, desired_facing)
    self:Start_Track(track, desired_facing)

    return true
end

--[[
    Stop driving.
]]
function DriveClass:Stop_Driver()
    FootClass.Stop_Driver(self)
    self:Stop_Track()
end

--[[
    Mark the track cells for collision detection.
    Called when vehicle reserves/releases cells during movement.

    @param coord - Center coordinate
    @param flag - true to mark, false to clear
]]
function DriveClass:Mark_Track(coord, flag)
    -- Would mark cells the vehicle will pass through
    -- Used for collision avoidance
end

--[[
    Check if can enter a cell (ground movement restrictions).
]]
function DriveClass:Can_Enter_Cell(cell, facing)
    local result = FootClass.Can_Enter_Cell(self, cell, facing)

    if result ~= FootClass.MOVE.OK then
        return result
    end

    -- Additional ground-specific checks
    -- Would check for water, impassable terrain, etc.

    return FootClass.MOVE.OK
end

--============================================================================
-- Per-Cell Processing
--============================================================================

--[[
    Process when entering a cell.
    Override for harvester behavior.
]]
function DriveClass:Per_Cell_Process(center)
    FootClass.Per_Cell_Process(self, center)

    if center then
        -- If harvester, check for tiberium
        if self:Is_Harvester() and self.IsHarvesting then
            self:Harvest_Tiberium()
        end
    end
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for drive.
    Called each game tick.
]]
function DriveClass:AI()
    FootClass.AI(self)

    -- Process track following
    if self:Is_On_Track() then
        self:Follow_Track()
    end

    -- Process turning
    if self.IsRotating then
        if self:Do_Turn() then
            self.IsRotating = false
        end
    end

    -- If harvester is full, return to refinery
    if self:Is_Harvester() and self:Is_Harvester_Full() and not self.IsReturning then
        self:Start_Return()
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function DriveClass:Code_Pointers()
    local data = FootClass.Code_Pointers(self)

    -- Harvester state
    data.Tiberium = self.Tiberium
    data.IsHarvesting = self.IsHarvesting
    data.IsReturning = self.IsReturning
    data.IsTurretLockedDown = self.IsTurretLockedDown

    -- Track state
    data.TrackNumber = self.TrackNumber
    data.TrackIndex = self.TrackIndex
    data.StartFacing = self.StartFacing
    data.TargetFacing = self.TargetFacing
    data.TrackStartCoord = self.TrackStartCoord
    data.SpeedAccum = self.SpeedAccum

    return data
end

function DriveClass:Decode_Pointers(data, heap_lookup)
    FootClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        -- Harvester state
        self.Tiberium = data.Tiberium or 0
        self.IsHarvesting = data.IsHarvesting or false
        self.IsReturning = data.IsReturning or false
        self.IsTurretLockedDown = data.IsTurretLockedDown or false

        -- Track state
        self.TrackNumber = data.TrackNumber or DriveClass.TRACK.NONE
        self.TrackIndex = data.TrackIndex or 0
        self.StartFacing = data.StartFacing or 0
        self.TargetFacing = data.TargetFacing or 0
        self.TrackStartCoord = data.TrackStartCoord or 0
        self.SpeedAccum = data.SpeedAccum or 0
    end
end

--============================================================================
-- Debug Support
--============================================================================

function DriveClass:Debug_Dump()
    FootClass.Debug_Dump(self)

    print(string.format("DriveClass: Track=%d Index=%d Tiberium=%d/%d",
        self.TrackNumber,
        self.TrackIndex,
        self.Tiberium,
        DriveClass.MAX_TIBERIUM))

    print(string.format("  Flags: Harvesting=%s Returning=%s TurretLocked=%s",
        tostring(self.IsHarvesting),
        tostring(self.IsReturning),
        tostring(self.IsTurretLockedDown)))
end

return DriveClass
