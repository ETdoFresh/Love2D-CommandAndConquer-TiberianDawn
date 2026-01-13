--[[
    GScreenClass - Base screen class for display hierarchy

    Port of GSCREEN.H/CPP from the original C&C source.

    This is the root of the display hierarchy:
        GScreenClass
            └── MapClass (handled by existing grid.lua)
                    └── DisplayClass
                            └── RadarClass
                                    └── ScrollClass
                                            └── MouseClass

    GScreenClass provides:
    - Basic rendering framework (Flag_To_Redraw, Render, Draw_It)
    - Input routing (Input, AI)
    - Button/gadget management (Add_A_Button, Remove_A_Button)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/GSCREEN.H
]]

local Class = require("src.objects.class")

-- Create GScreenClass as a base class
local GScreenClass = Class.new("GScreenClass")

--============================================================================
-- Constructor
--============================================================================

function GScreenClass:init()
    --[[
        If the entire map is required to redraw, then this flag is true.
        This flag is set by the Flag_To_Redraw function. Typically, this
        occurs when the screen has been trashed or is first created.
    ]]
    self.IsToRedraw = false

    --[[
        If only a sub-system of the map must be redrawn, then this flag
        will be set. An example of something that would set this flag would
        be an animating icon in the sidebar.
    ]]
    self.IsToUpdate = false

    --[[
        List of UI buttons/gadgets for input handling.
        In the original, this was a static member shared across instances.
    ]]
    self.Buttons = nil
end

--============================================================================
-- Initialization
--============================================================================

--[[
    One-time initialization (called once at game startup).
]]
function GScreenClass:One_Time()
    -- Override in derived classes
end

--[[
    Full initialization with optional theater type.

    @param theater - TheaterType enum value (optional)
]]
function GScreenClass:Init(theater)
    self:Init_Clear()
    self:Init_IO()
    if theater then
        self:Init_Theater(theater)
    end
end

--[[
    Clear all to known state.
]]
function GScreenClass:Init_Clear()
    self.IsToRedraw = true
    self.IsToUpdate = false
end

--[[
    Initialize I/O button list.
]]
function GScreenClass:Init_IO()
    self.Buttons = nil
end

--[[
    Theater-specific initializations.

    @param theater - TheaterType enum value
]]
function GScreenClass:Init_Theater(theater)
    -- Override in derived classes
end

--============================================================================
-- Input Handling
--============================================================================

--[[
    Player I/O is routed through here. Called every game tick.

    @param key - KeyNumType (input key, can be modified)
    @param x - Mouse X position
    @param y - Mouse Y position
    @return key, x, y (possibly modified)
]]
function GScreenClass:Input(key, x, y)
    -- Process button input if we have buttons
    if self.Buttons and key then
        -- In the original, this would route through the gadget system
        -- For now, we pass through to AI
    end

    return key, x, y
end

--[[
    AI/logic processing for screen. Called every game tick.

    @param key - KeyNumType (input key)
    @param x - Mouse X position
    @param y - Mouse Y position
]]
function GScreenClass:AI(key, x, y)
    -- Override in derived classes
end

--============================================================================
-- Button/Gadget Management
--============================================================================

--[[
    Add a button/gadget to the input list.

    @param gadget - GadgetClass to add
]]
function GScreenClass:Add_A_Button(gadget)
    if gadget == nil then return end

    -- Simple linked list management
    if self.Buttons == nil then
        self.Buttons = gadget
        gadget._next = nil
    else
        -- Add to end of list
        local current = self.Buttons
        while current._next do
            current = current._next
        end
        current._next = gadget
        gadget._next = nil
    end
end

--[[
    Remove a button/gadget from the input list.

    @param gadget - GadgetClass to remove
]]
function GScreenClass:Remove_A_Button(gadget)
    if gadget == nil or self.Buttons == nil then return end

    -- Remove from linked list
    if self.Buttons == gadget then
        self.Buttons = gadget._next
    else
        local current = self.Buttons
        while current._next and current._next ~= gadget do
            current = current._next
        end
        if current._next == gadget then
            current._next = gadget._next
        end
    end
    gadget._next = nil
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Flag the map to be redrawn.

    @param complete - If true, requires complete redraw; if false, just update
]]
function GScreenClass:Flag_To_Redraw(complete)
    if complete then
        self.IsToRedraw = true
    end
    self.IsToUpdate = true
end

--[[
    Render maintenance routine (call every game tick).
    Probably no need to override this in derived classes.
]]
function GScreenClass:Render()
    if self.IsToRedraw or self.IsToUpdate then
        self:Draw_It(self.IsToRedraw)
        self.IsToRedraw = false
        self.IsToUpdate = false
    end
end

--[[
    Called when actual drawing is required.
    Override this function in derived classes.

    @param complete - If true, perform complete redraw
]]
function GScreenClass:Draw_It(complete)
    -- Override in derived classes
end

--[[
    Blit the back buffer to the screen.
    In Love2D, this is handled by the framework automatically.
]]
function GScreenClass:Blit_Display()
    -- Love2D handles double-buffering automatically
end

--============================================================================
-- Mouse Shape (Abstract - must be overridden)
--============================================================================

--[[
    Set the default mouse shape.

    @param mouse - MouseType enum value
    @param wwsmall - If true, use small version of cursor
]]
function GScreenClass:Set_Default_Mouse(mouse, wwsmall)
    -- Override in MouseClass
end

--[[
    Override the current mouse shape temporarily.

    @param mouse - MouseType enum value
    @param wwsmall - If true, use small version
    @return true if shape was changed
]]
function GScreenClass:Override_Mouse_Shape(mouse, wwsmall)
    -- Override in MouseClass
    return false
end

--[[
    Revert mouse shape to default.
]]
function GScreenClass:Revert_Mouse_Shape()
    -- Override in MouseClass
end

--[[
    Toggle small mouse mode.

    @param wwsmall - If true, use small cursors
]]
function GScreenClass:Mouse_Small(wwsmall)
    -- Override in MouseClass
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function GScreenClass:Code_Pointers()
    return {
        IsToRedraw = self.IsToRedraw,
        IsToUpdate = self.IsToUpdate,
    }
end

function GScreenClass:Decode_Pointers(data)
    if data then
        self.IsToRedraw = data.IsToRedraw or false
        self.IsToUpdate = data.IsToUpdate or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

function GScreenClass:Debug_Dump()
    print(string.format("GScreenClass: IsToRedraw=%s IsToUpdate=%s",
        tostring(self.IsToRedraw),
        tostring(self.IsToUpdate)))
end

return GScreenClass
