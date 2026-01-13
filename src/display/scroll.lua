--[[
    ScrollClass - Map scrolling and edge detection

    Port of SCROLL.H/CPP from the original C&C source.

    ScrollClass extends RadarClass to provide:
    - Automatic edge scrolling (when mouse at screen edges)
    - Scroll speed control
    - Scroll inertia
    - Direction-based scrolling

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/SCROLL.H
]]

local Class = require("src.objects.class")
local RadarClass = require("src.display.radar")
local Coord = require("src.core.coord")

-- ScrollClass extends RadarClass
local ScrollClass = Class.extend(RadarClass, "ScrollClass")

--============================================================================
-- Constants
--============================================================================

-- Scroll timing (in game ticks, 15 FPS)
ScrollClass.INITIAL_DELAY = 8    -- Delay before scrolling starts
ScrollClass.SEQUENCE_DELAY = 4   -- Delay between scroll steps

-- Edge detection zones (in pixels)
ScrollClass.EDGE_ZONE = 16       -- Distance from edge to trigger scroll

-- Scroll speeds (in leptons per step)
ScrollClass.SCROLL_SPEEDS = {
    64,   -- Slowest
    128,  -- Slower
    192,  -- Normal
    256,  -- Faster
    384,  -- Fastest
}

-- Direction values (8 cardinal + 8 diagonal = 16, but we use 8)
ScrollClass.DIR = {
    NONE = -1,
    N = 0,
    NE = 1,
    E = 2,
    SE = 3,
    S = 4,
    SW = 5,
    W = 6,
    NW = 7,
}

-- Direction to offset mapping
ScrollClass.DIR_OFFSET = {
    [0] = {x = 0, y = -1},   -- N
    [1] = {x = 1, y = -1},   -- NE
    [2] = {x = 1, y = 0},    -- E
    [3] = {x = 1, y = 1},    -- SE
    [4] = {x = 0, y = 1},    -- S
    [5] = {x = -1, y = 1},   -- SW
    [6] = {x = -1, y = 0},   -- W
    [7] = {x = -1, y = -1},  -- NW
}

--============================================================================
-- Constructor
--============================================================================

function ScrollClass:init()
    -- Call parent constructor
    RadarClass.init(self)

    --[[
        If map scrolling is automatic, then this flag is true.
        Automatic scrolling will cause the map to scroll if the mouse
        is in the scroll region, regardless of whether or not the
        mouse button is held down.
    ]]
    self.IsAutoScroll = true

    --[[
        Scroll countdown timer. When this reaches zero, perform a scroll step.
    ]]
    self.ScrollTimer = 0

    --[[
        Current scroll inertia. Builds up while scrolling for smoother feel.
    ]]
    self.Inertia = 0

    --[[
        Current scroll speed setting (index into SCROLL_SPEEDS).
    ]]
    self.ScrollSpeedIndex = 2  -- Normal

    --[[
        Last scroll direction (for inertia continuation).
    ]]
    self.LastScrollDir = ScrollClass.DIR.NONE

    --[[
        Whether currently in a scroll operation.
    ]]
    self.IsScrolling = false
end

--============================================================================
-- Initialization
--============================================================================

function ScrollClass:Init_IO()
    RadarClass.Init_IO(self)
    self.ScrollTimer = 0
    self.Inertia = 0
end

--============================================================================
-- Auto-Scroll Control
--============================================================================

--[[
    Set auto-scroll mode.

    @param control - -1=toggle, 0=off, 1=on
    @return true if auto-scroll is now enabled
]]
function ScrollClass:Set_Autoscroll(control)
    if control < 0 then
        self.IsAutoScroll = not self.IsAutoScroll
    elseif control == 0 then
        self.IsAutoScroll = false
    else
        self.IsAutoScroll = true
    end

    return self.IsAutoScroll
end

--[[
    Check if auto-scroll is enabled.
]]
function ScrollClass:Is_Autoscroll()
    return self.IsAutoScroll
end

--============================================================================
-- Scroll Speed Control
--============================================================================

--[[
    Set the scroll speed.

    @param speed_index - Index into SCROLL_SPEEDS (0-4)
]]
function ScrollClass:Set_Scroll_Speed(speed_index)
    self.ScrollSpeedIndex = math.max(0, math.min(#ScrollClass.SCROLL_SPEEDS - 1, speed_index))
end

--[[
    Get current scroll speed in leptons.
]]
function ScrollClass:Get_Scroll_Speed()
    return ScrollClass.SCROLL_SPEEDS[self.ScrollSpeedIndex + 1] or 192
end

--============================================================================
-- Edge Detection
--============================================================================

--[[
    Detect scroll direction based on mouse position.

    @param x - Mouse X position
    @param y - Mouse Y position
    @return Direction enum value, or DIR.NONE
]]
function ScrollClass:Get_Edge_Direction(x, y)
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local zone = ScrollClass.EDGE_ZONE

    local at_left = x < zone
    local at_right = x >= screen_w - zone
    local at_top = y < zone
    local at_bottom = y >= screen_h - zone

    -- Determine direction based on edge combination
    if at_top then
        if at_left then return ScrollClass.DIR.NW end
        if at_right then return ScrollClass.DIR.NE end
        return ScrollClass.DIR.N
    elseif at_bottom then
        if at_left then return ScrollClass.DIR.SW end
        if at_right then return ScrollClass.DIR.SE end
        return ScrollClass.DIR.S
    elseif at_left then
        return ScrollClass.DIR.W
    elseif at_right then
        return ScrollClass.DIR.E
    end

    return ScrollClass.DIR.NONE
end

--============================================================================
-- Scrolling
--============================================================================

--[[
    Perform the actual scroll operation.

    @param facing - Direction to scroll
    @param distance - Distance in leptons to scroll
    @param really - If true, actually perform the scroll
    @return true if scroll was performed
]]
function ScrollClass:Scroll_Map(facing, distance, really)
    if facing == ScrollClass.DIR.NONE or facing < 0 then
        return false
    end

    -- Get direction offset
    local offset = ScrollClass.DIR_OFFSET[facing]
    if not offset then
        return false
    end

    -- Calculate new position
    local current_x = Coord.Coord_X(self.TacticalCoord)
    local current_y = Coord.Coord_Y(self.TacticalCoord)

    local new_x = current_x + (offset.x * distance)
    local new_y = current_y + (offset.y * distance)

    -- Clamp to map bounds
    local max_x = (64 * 256) - self.TacLeptonWidth
    local max_y = (64 * 256) - self.TacLeptonHeight

    new_x = math.max(0, math.min(max_x, new_x))
    new_y = math.max(0, math.min(max_y, new_y))

    -- Check if position changed
    local new_coord = Coord.XY_Coord(new_x, new_y)
    if new_coord == self.TacticalCoord then
        return false
    end

    -- Actually scroll if requested
    if really then
        self:Set_Tactical_Position(new_coord)
    end

    return true
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    Process input and scrolling.
]]
function ScrollClass:AI(key, x, y)
    RadarClass.AI(self, key, x, y)

    -- Handle auto-scroll
    if self.IsAutoScroll then
        self:Process_Edge_Scroll(x, y)
    end
end

--[[
    Process edge scrolling based on mouse position.

    @param x - Mouse X
    @param y - Mouse Y
]]
function ScrollClass:Process_Edge_Scroll(x, y)
    local dir = self:Get_Edge_Direction(x, y)

    if dir ~= ScrollClass.DIR.NONE then
        -- At an edge - process scrolling
        if self.ScrollTimer > 0 then
            self.ScrollTimer = self.ScrollTimer - 1
        else
            -- Time to scroll
            local speed = self:Get_Scroll_Speed()

            -- Apply inertia bonus
            if dir == self.LastScrollDir then
                self.Inertia = math.min(self.Inertia + 1, 4)
                speed = speed + (self.Inertia * 32)
            else
                self.Inertia = 0
            end

            self:Scroll_Map(dir, speed, true)
            self.LastScrollDir = dir
            self.IsScrolling = true

            -- Reset timer
            self.ScrollTimer = ScrollClass.SEQUENCE_DELAY
        end
    else
        -- Not at edge - reset scroll state
        if self.IsScrolling then
            self.IsScrolling = false
            self.Inertia = 0
            self.LastScrollDir = ScrollClass.DIR.NONE
            self.ScrollTimer = ScrollClass.INITIAL_DELAY
        end
    end
end

--============================================================================
-- Keyboard Scrolling
--============================================================================

--[[
    Handle keyboard-based scrolling.

    @param key - Key that was pressed
    @return true if key was handled
]]
function ScrollClass:Handle_Scroll_Key(key)
    local dir = ScrollClass.DIR.NONE

    -- Check arrow keys
    if key == "up" then
        dir = ScrollClass.DIR.N
    elseif key == "down" then
        dir = ScrollClass.DIR.S
    elseif key == "left" then
        dir = ScrollClass.DIR.W
    elseif key == "right" then
        dir = ScrollClass.DIR.E
    end

    if dir ~= ScrollClass.DIR.NONE then
        local speed = self:Get_Scroll_Speed() * 2  -- Keyboard scrolls faster
        self:Scroll_Map(dir, speed, true)
        return true
    end

    return false
end

--============================================================================
-- Jump to Position
--============================================================================

--[[
    Jump the view to center on a specific cell.

    @param cell - CELL to center on
]]
function ScrollClass:Jump_To_Cell(cell)
    local cell_x = Coord.Cell_X(cell)
    local cell_y = Coord.Cell_Y(cell)

    -- Calculate coordinate at center of cell
    local coord = Coord.XYL_Coord(cell_x, cell_y, 128, 128)

    -- Offset to put cell at center of view
    local offset_x = self.TacLeptonWidth / 2
    local offset_y = self.TacLeptonHeight / 2

    local new_x = math.max(0, Coord.Coord_X(coord) - offset_x)
    local new_y = math.max(0, Coord.Coord_Y(coord) - offset_y)

    self:Set_Tactical_Position(Coord.XY_Coord(new_x, new_y))
end

--[[
    Jump the view to center on a specific coordinate.

    @param coord - COORDINATE to center on
]]
function ScrollClass:Jump_To_Coord(coord)
    local offset_x = self.TacLeptonWidth / 2
    local offset_y = self.TacLeptonHeight / 2

    local new_x = math.max(0, Coord.Coord_X(coord) - offset_x)
    local new_y = math.max(0, Coord.Coord_Y(coord) - offset_y)

    self:Set_Tactical_Position(Coord.XY_Coord(new_x, new_y))
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function ScrollClass:Code_Pointers()
    local data = RadarClass.Code_Pointers(self)

    data.IsAutoScroll = self.IsAutoScroll
    data.ScrollSpeedIndex = self.ScrollSpeedIndex

    return data
end

function ScrollClass:Decode_Pointers(data, heap_lookup)
    RadarClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.IsAutoScroll = data.IsAutoScroll
        if self.IsAutoScroll == nil then
            self.IsAutoScroll = true
        end
        self.ScrollSpeedIndex = data.ScrollSpeedIndex or 2
    end
end

--============================================================================
-- Debug Support
--============================================================================

function ScrollClass:Debug_Dump()
    RadarClass.Debug_Dump(self)

    print(string.format("ScrollClass: AutoScroll=%s SpeedIndex=%d Inertia=%d",
        tostring(self.IsAutoScroll),
        self.ScrollSpeedIndex,
        self.Inertia))
    print(string.format("  LastDir=%d Scrolling=%s Timer=%d",
        self.LastScrollDir,
        tostring(self.IsScrolling),
        self.ScrollTimer))
end

return ScrollClass
