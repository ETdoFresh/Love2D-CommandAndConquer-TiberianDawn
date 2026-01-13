--[[
    MouseClass - Mouse cursor handling and display

    Port of MOUSE.H/CPP from the original C&C source.

    MouseClass is the top of the display hierarchy, extending ScrollClass
    to provide:
    - Mouse cursor shape management
    - Cursor animation for animated cursors
    - Small cursor mode toggle
    - Default and override cursor states

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/MOUSE.H
]]

local Class = require("src.objects.class")
local ScrollClass = require("src.display.scroll")

-- MouseClass extends ScrollClass
local MouseClass = Class.extend(ScrollClass, "MouseClass")

--============================================================================
-- Mouse Type Constants
--============================================================================

MouseClass.MOUSE = {
    NORMAL = 0,           -- Standard pointer
    N = 1,                -- Scroll north
    NE = 2,               -- Scroll northeast
    E = 3,                -- Scroll east
    SE = 4,               -- Scroll southeast
    S = 5,                -- Scroll south
    SW = 6,               -- Scroll southwest
    W = 7,                -- Scroll west
    NW = 8,               -- Scroll northwest
    NO_N = 9,             -- Can't scroll north (at edge)
    NO_NE = 10,           -- Can't scroll northeast
    NO_E = 11,            -- Can't scroll east
    NO_SE = 12,           -- Can't scroll southeast
    NO_S = 13,            -- Can't scroll south
    NO_SW = 14,           -- Can't scroll southwest
    NO_W = 15,            -- Can't scroll west
    NO_NW = 16,           -- Can't scroll northwest
    CAN_SELECT = 17,      -- Unit can be selected
    CAN_MOVE = 18,        -- Unit can move here
    NO_MOVE = 19,         -- Unit cannot move here
    STAY_ATTACK = 20,     -- Attack without moving
    CAN_ATTACK = 21,      -- Unit can attack target
    AREA_GUARD = 22,      -- Area guard command
    TOTE = 23,            -- Carry/transport cursor
    NO_TOTE = 24,         -- Cannot carry
    ENTER = 25,           -- Enter building/transport
    NO_ENTER = 26,        -- Cannot enter
    DEPLOY = 27,          -- Deploy unit
    NO_DEPLOY = 28,       -- Cannot deploy
    SELL = 29,            -- Sell mode cursor
    SELL_BACK = 30,       -- Sell in progress
    NO_SELL_BACK = 31,    -- Cannot sell
    GREPAIR = 32,         -- Repair mode cursor
    REPAIR = 33,          -- Repair target
    NO_REPAIR = 34,       -- Cannot repair
    ION_CANNON = 35,      -- Ion cannon target
    NUCLEAR_BOMB = 36,    -- Nuke target
    AIR_STRIKE = 37,      -- Airstrike target
    DEMOLITIONS = 38,     -- C4/demolitions
    HEAL = 39,            -- Heal target
    DAMAGE = 40,          -- Damaged (?)
    GREPAIR_FULL = 41,    -- Repair full (?)
}

MouseClass.MOUSE_COUNT = 42

-- Cursor names for debugging
MouseClass.MOUSE_NAMES = {}
for name, value in pairs(MouseClass.MOUSE) do
    MouseClass.MOUSE_NAMES[value] = name
end

--============================================================================
-- Cursor Animation Data
--============================================================================

-- Animation control for each cursor type
-- {StartFrame, FrameCount, FrameRate, SmallFrame, HotX, HotY}
MouseClass.MouseControl = {
    [MouseClass.MOUSE.NORMAL]     = {start = 0,  count = 1, rate = 0, small = -1, x = 0, y = 0},
    [MouseClass.MOUSE.N]          = {start = 1,  count = 1, rate = 0, small = -1, x = 7, y = 0},
    [MouseClass.MOUSE.NE]         = {start = 2,  count = 1, rate = 0, small = -1, x = 15, y = 0},
    [MouseClass.MOUSE.E]          = {start = 3,  count = 1, rate = 0, small = -1, x = 15, y = 7},
    [MouseClass.MOUSE.SE]         = {start = 4,  count = 1, rate = 0, small = -1, x = 15, y = 15},
    [MouseClass.MOUSE.S]          = {start = 5,  count = 1, rate = 0, small = -1, x = 7, y = 15},
    [MouseClass.MOUSE.SW]         = {start = 6,  count = 1, rate = 0, small = -1, x = 0, y = 15},
    [MouseClass.MOUSE.W]          = {start = 7,  count = 1, rate = 0, small = -1, x = 0, y = 7},
    [MouseClass.MOUSE.NW]         = {start = 8,  count = 1, rate = 0, small = -1, x = 0, y = 0},
    [MouseClass.MOUSE.CAN_SELECT] = {start = 9,  count = 8, rate = 4, small = 17, x = 7, y = 7},
    [MouseClass.MOUSE.CAN_MOVE]   = {start = 25, count = 8, rate = 4, small = 33, x = 7, y = 7},
    [MouseClass.MOUSE.NO_MOVE]    = {start = 41, count = 1, rate = 0, small = 42, x = 7, y = 7},
    [MouseClass.MOUSE.CAN_ATTACK] = {start = 43, count = 8, rate = 4, small = 51, x = 7, y = 7},
    [MouseClass.MOUSE.SELL]       = {start = 59, count = 8, rate = 4, small = 67, x = 7, y = 7},
    [MouseClass.MOUSE.GREPAIR]    = {start = 75, count = 1, rate = 0, small = 76, x = 7, y = 7},
    [MouseClass.MOUSE.ENTER]      = {start = 77, count = 8, rate = 4, small = 85, x = 7, y = 7},
}

--============================================================================
-- Constructor
--============================================================================

function MouseClass:init()
    -- Call parent constructor
    ScrollClass.init(self)

    --[[
        Current mouse cursor shape.
    ]]
    self.CurrentMouseShape = MouseClass.MOUSE.NORMAL

    --[[
        Normal/default mouse shape (reverts to this when override ends).
    ]]
    self.NormalMouseShape = MouseClass.MOUSE.NORMAL

    --[[
        If using small cursor variants.
    ]]
    self.IsSmall = false

    --[[
        Animation frame for animated cursors.
    ]]
    self.Frame = 0

    --[[
        Animation timer for cursor animation.
    ]]
    self.AnimTimer = 0

    --[[
        Override stack (for temporary cursor changes).
    ]]
    self.OverrideStack = {}
end

--============================================================================
-- Initialization
--============================================================================

function MouseClass:One_Time()
    ScrollClass.One_Time(self)

    -- Load mouse cursor sprites here if needed
    -- For now, we rely on system cursor or custom rendering
end

function MouseClass:Init_Clear()
    ScrollClass.Init_Clear(self)

    self.CurrentMouseShape = MouseClass.MOUSE.NORMAL
    self.NormalMouseShape = MouseClass.MOUSE.NORMAL
    self.IsSmall = false
    self.Frame = 0
    self.AnimTimer = 0
    self.OverrideStack = {}
end

--============================================================================
-- Mouse Shape Control
--============================================================================

--[[
    Set the default mouse shape.

    @param mouse - MouseType enum value
    @param wwsmall - If true, use small variant
]]
function MouseClass:Set_Default_Mouse(mouse, wwsmall)
    wwsmall = wwsmall or false

    self.NormalMouseShape = mouse
    self.IsSmall = wwsmall

    -- If not overridden, update current
    if #self.OverrideStack == 0 then
        self:Set_Mouse_Shape(mouse)
    end
end

--[[
    Override the current mouse shape temporarily.

    @param mouse - MouseType enum value
    @param wwsmall - If true, use small variant
    @return true if shape was changed
]]
function MouseClass:Override_Mouse_Shape(mouse, wwsmall)
    wwsmall = wwsmall or false

    -- Push override onto stack
    table.insert(self.OverrideStack, {
        shape = self.CurrentMouseShape,
        small = self.IsSmall
    })

    self.IsSmall = wwsmall
    self:Set_Mouse_Shape(mouse)

    return true
end

--[[
    Revert mouse shape from override.
]]
function MouseClass:Revert_Mouse_Shape()
    if #self.OverrideStack > 0 then
        local prev = table.remove(self.OverrideStack)
        self.IsSmall = prev.small
        self:Set_Mouse_Shape(prev.shape)
    else
        -- No override - go back to default
        self:Set_Mouse_Shape(self.NormalMouseShape)
    end
end

--[[
    Get the current mouse shape.

    @return MouseType enum value
]]
function MouseClass:Get_Mouse_Shape()
    return self.CurrentMouseShape
end

--[[
    Toggle small mouse mode.

    @param wwsmall - If true, use small cursors
]]
function MouseClass:Mouse_Small(wwsmall)
    self.IsSmall = wwsmall
    -- Re-apply current shape with new size
    self:Set_Mouse_Shape(self.CurrentMouseShape)
end

--[[
    Actually set the mouse cursor shape.

    @param mouse - MouseType enum value
]]
function MouseClass:Set_Mouse_Shape(mouse)
    if mouse < 0 or mouse >= MouseClass.MOUSE_COUNT then
        mouse = MouseClass.MOUSE.NORMAL
    end

    self.CurrentMouseShape = mouse
    self.Frame = 0
    self.AnimTimer = 0

    -- Update system cursor or custom cursor here
    self:Apply_Cursor()
end

--[[
    Apply the current cursor shape to the system.
]]
function MouseClass:Apply_Cursor()
    -- In a full implementation, this would set the system cursor
    -- or prepare a custom cursor sprite for rendering

    -- For now, we can use Love2D's system cursor as a placeholder
    local cursor_map = {
        [MouseClass.MOUSE.NORMAL] = love.mouse.getSystemCursor("arrow"),
        [MouseClass.MOUSE.CAN_MOVE] = love.mouse.getSystemCursor("crosshair"),
        [MouseClass.MOUSE.NO_MOVE] = love.mouse.getSystemCursor("no"),
        [MouseClass.MOUSE.CAN_ATTACK] = love.mouse.getSystemCursor("crosshair"),
    }

    local sys_cursor = cursor_map[self.CurrentMouseShape]
    if sys_cursor then
        love.mouse.setCursor(sys_cursor)
    else
        love.mouse.setCursor()  -- Default cursor
    end
end

--============================================================================
-- Cursor for Actions
--============================================================================

--[[
    Get the appropriate cursor for a scroll direction.

    @param dir - Direction enum (from ScrollClass)
    @param can_scroll - If false, use "no scroll" variant
    @return MouseType enum value
]]
function MouseClass:Cursor_For_Direction(dir, can_scroll)
    can_scroll = (can_scroll ~= false)

    if dir == ScrollClass.DIR.N then
        return can_scroll and MouseClass.MOUSE.N or MouseClass.MOUSE.NO_N
    elseif dir == ScrollClass.DIR.NE then
        return can_scroll and MouseClass.MOUSE.NE or MouseClass.MOUSE.NO_NE
    elseif dir == ScrollClass.DIR.E then
        return can_scroll and MouseClass.MOUSE.E or MouseClass.MOUSE.NO_E
    elseif dir == ScrollClass.DIR.SE then
        return can_scroll and MouseClass.MOUSE.SE or MouseClass.MOUSE.NO_SE
    elseif dir == ScrollClass.DIR.S then
        return can_scroll and MouseClass.MOUSE.S or MouseClass.MOUSE.NO_S
    elseif dir == ScrollClass.DIR.SW then
        return can_scroll and MouseClass.MOUSE.SW or MouseClass.MOUSE.NO_SW
    elseif dir == ScrollClass.DIR.W then
        return can_scroll and MouseClass.MOUSE.W or MouseClass.MOUSE.NO_W
    elseif dir == ScrollClass.DIR.NW then
        return can_scroll and MouseClass.MOUSE.NW or MouseClass.MOUSE.NO_NW
    end

    return MouseClass.MOUSE.NORMAL
end

--============================================================================
-- AI Processing
--============================================================================

function MouseClass:AI(key, x, y)
    ScrollClass.AI(self, key, x, y)

    -- Update cursor animation
    self:Update_Cursor_Animation()

    -- Update cursor based on position
    self:Update_Cursor_For_Position(x, y)
end

--[[
    Update cursor animation frame.
]]
function MouseClass:Update_Cursor_Animation()
    local control = MouseClass.MouseControl[self.CurrentMouseShape]
    if not control or control.count <= 1 then
        return
    end

    self.AnimTimer = self.AnimTimer + 1
    if self.AnimTimer >= control.rate then
        self.AnimTimer = 0
        self.Frame = self.Frame + 1
        if self.Frame >= control.count then
            self.Frame = 0
        end
    end
end

--[[
    Update cursor shape based on mouse position.

    @param x - Mouse X
    @param y - Mouse Y
]]
function MouseClass:Update_Cursor_For_Position(x, y)
    -- Check if at screen edge (scroll cursor)
    local dir = self:Get_Edge_Direction(x, y)
    if dir ~= ScrollClass.DIR.NONE then
        local can_scroll = self:Scroll_Map(dir, 1, false)
        local cursor = self:Cursor_For_Direction(dir, can_scroll)
        if cursor ~= self.CurrentMouseShape then
            self:Set_Mouse_Shape(cursor)
        end
        return
    end

    -- Check for mode-specific cursors
    if self.IsSellMode then
        self:Set_Mouse_Shape(MouseClass.MOUSE.SELL)
        return
    end

    if self.IsRepairMode then
        self:Set_Mouse_Shape(MouseClass.MOUSE.GREPAIR)
        return
    end

    -- Default cursor
    if self.CurrentMouseShape ~= self.NormalMouseShape then
        if self.CurrentMouseShape >= MouseClass.MOUSE.N and
           self.CurrentMouseShape <= MouseClass.MOUSE.NO_NW then
            -- Was a scroll cursor, now normal
            self:Set_Mouse_Shape(self.NormalMouseShape)
        end
    end
end

--============================================================================
-- Custom Cursor Rendering
--============================================================================

--[[
    Draw the mouse cursor (if using custom rendering).

    @param x - Mouse X
    @param y - Mouse Y
]]
function MouseClass:Draw_Cursor(x, y)
    -- This would be called if we're doing custom cursor rendering
    -- instead of system cursors

    local control = MouseClass.MouseControl[self.CurrentMouseShape]
    if not control then return end

    -- Calculate actual frame
    local frame = control.start + self.Frame
    if self.IsSmall and control.small >= 0 then
        frame = control.small + self.Frame
    end

    -- Get hotspot
    local hot_x = control.x
    local hot_y = control.y

    -- Draw cursor sprite at position
    -- (would need actual sprite loading)
    -- love.graphics.draw(cursorSprite, quad, x - hot_x, y - hot_y)
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function MouseClass:Code_Pointers()
    local data = ScrollClass.Code_Pointers(self)

    data.CurrentMouseShape = self.CurrentMouseShape
    data.NormalMouseShape = self.NormalMouseShape
    data.IsSmall = self.IsSmall

    return data
end

function MouseClass:Decode_Pointers(data, heap_lookup)
    ScrollClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.CurrentMouseShape = data.CurrentMouseShape or MouseClass.MOUSE.NORMAL
        self.NormalMouseShape = data.NormalMouseShape or MouseClass.MOUSE.NORMAL
        self.IsSmall = data.IsSmall or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

function MouseClass:Debug_Dump()
    ScrollClass.Debug_Dump(self)

    local current_name = MouseClass.MOUSE_NAMES[self.CurrentMouseShape] or "UNKNOWN"
    local normal_name = MouseClass.MOUSE_NAMES[self.NormalMouseShape] or "UNKNOWN"

    print(string.format("MouseClass: Current=%s Normal=%s Small=%s Frame=%d",
        current_name, normal_name,
        tostring(self.IsSmall), self.Frame))
    print(string.format("  OverrideStack depth: %d", #self.OverrideStack))
end

return MouseClass
