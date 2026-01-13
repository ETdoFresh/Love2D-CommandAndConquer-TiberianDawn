--[[
    DisplayClass - Tactical map display and rendering

    Port of DISPLAY.H/CPP from the original C&C source.

    DisplayClass extends the base display hierarchy to provide:
    - Tactical map viewport (TacticalCoord, TacLeptonWidth/Height)
    - Layer management for objects (GROUND, AIR, TOP)
    - Object placement and building cursor
    - Coordinate conversions (pixel <-> lepton <-> cell)
    - Cell selection and rubber-band selection
    - Repair/sell mode handling

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/DISPLAY.H
]]

local Class = require("src.objects.class")
local GScreenClass = require("src.display.gscreen")
local LayerClass = require("src.map.layer")
local Coord = require("src.core.coord")

-- DisplayClass extends GScreenClass
local DisplayClass = Class.extend(GScreenClass, "DisplayClass")

--============================================================================
-- Constants
--============================================================================

-- Icon/cell dimensions (from DISPLAY.H)
DisplayClass.ICON_PIXEL_W = 24
DisplayClass.ICON_PIXEL_H = 24
DisplayClass.ICON_LEPTON_W = 256
DisplayClass.ICON_LEPTON_H = 256
DisplayClass.CELL_PIXEL_W = 24
DisplayClass.CELL_PIXEL_H = 24
DisplayClass.CELL_LEPTON_W = 256
DisplayClass.CELL_LEPTON_H = 256

-- Pixel to lepton conversion factors
DisplayClass.PIXEL_LEPTON_W = DisplayClass.ICON_LEPTON_W / DisplayClass.ICON_PIXEL_W  -- 256/24 ≈ 10.67
DisplayClass.PIXEL_LEPTON_H = DisplayClass.ICON_LEPTON_H / DisplayClass.ICON_PIXEL_H

-- Theater types
DisplayClass.THEATER = {
    NONE = -1,
    TEMPERATE = 0,
    DESERT = 1,
    WINTER = 2,
}

--============================================================================
-- Constructor
--============================================================================

function DisplayClass:init()
    -- Call parent constructor
    GScreenClass.init(self)

    --[[
        This indicates the theater that the display is to represent.
    ]]
    self.Theater = DisplayClass.THEATER.TEMPERATE

    --[[
        The tactical map display position is indicated by the coordinate
        of the upper left corner. Use Set_Tactical_Position to change.
    ]]
    self.TacticalCoord = 0

    --[[
        The desired tactical position (for smooth scrolling).
    ]]
    self.DesiredTacticalCoord = 0

    --[[
        The dimensions (in leptons) of the visible window onto the game map.
    ]]
    self.TacLeptonWidth = 0
    self.TacLeptonHeight = 0

    --[[
        Pixel offset for the upper left corner of the tactical map.
    ]]
    self.TacPixelX = 0
    self.TacPixelY = 0

    --[[
        Building placement cursor data.
    ]]
    self.ZoneCell = 0          -- Cell under cursor
    self.ZoneOffset = 0        -- Offset within cell
    self.CursorSize = nil      -- Cursor shape data
    self.ProximityCheck = false -- Is proximity check OK?

    --[[
        Pending object placement state.
    ]]
    self.PendingObjectPtr = nil      -- Actual object instance
    self.PendingObject = nil         -- Object type class
    self.PendingHouse = nil          -- House type for pending

    --[[
        If the tactical map needs to be redrawn.
    ]]
    self.IsToRedraw = false

    --[[
        Repair/sell mode flags.
    ]]
    self.IsRepairMode = false
    self.IsSellMode = false

    --[[
        Special weapon targeting mode.
        0 = none, 1 = ion cannon, 2 = nuke, 3 = airstrike
    ]]
    self.IsTargettingMode = 0

    --[[
        Rubber band selection state.
    ]]
    self.IsRubberBand = false
    self.IsTentative = false
    self.BandX = 0
    self.BandY = 0
    self.NewX = 0
    self.NewY = 0

    --[[
        Cell redraw flags (which cells need updating).
        Using a table as a simple boolean array.
    ]]
    self.CellRedraw = {}

    -- Initialize layers
    LayerClass.Init_All()
end

--============================================================================
-- Initialization
--============================================================================

function DisplayClass:One_Time()
    GScreenClass.One_Time(self)
    -- Additional one-time initialization
end

function DisplayClass:Init_Clear()
    GScreenClass.Init_Clear(self)

    self.TacticalCoord = 0
    self.DesiredTacticalCoord = 0
    self.PendingObjectPtr = nil
    self.PendingObject = nil
    self.IsRepairMode = false
    self.IsSellMode = false
    self.IsTargettingMode = 0
    self.IsRubberBand = false
    self.IsTentative = false
    self.CellRedraw = {}

    LayerClass.Clear_All()
end

function DisplayClass:Init_IO()
    GScreenClass.Init_IO(self)
    -- Initialize tactical gadget
end

function DisplayClass:Init_Theater(theater)
    GScreenClass.Init_Theater(self, theater)
    self.Theater = theater
end

--============================================================================
-- View Dimensions
--============================================================================

--[[
    Set the tactical view dimensions.

    @param x - Pixel X offset of tactical view
    @param y - Pixel Y offset of tactical view
    @param width - Width in pixels (-1 = use screen width)
    @param height - Height in pixels (-1 = use screen height)
]]
function DisplayClass:Set_View_Dimensions(x, y, width, height)
    self.TacPixelX = x
    self.TacPixelY = y

    -- Get screen dimensions if not specified
    if width < 0 then
        width = love.graphics.getWidth() - x
    end
    if height < 0 then
        height = love.graphics.getHeight() - y
    end

    -- Convert to leptons
    self.TacLeptonWidth = width * DisplayClass.PIXEL_LEPTON_W
    self.TacLeptonHeight = height * DisplayClass.PIXEL_LEPTON_H
end

--============================================================================
-- Tactical Position
--============================================================================

--[[
    Set the tactical map scroll position.

    @param coord - COORDINATE for upper-left corner
]]
function DisplayClass:Set_Tactical_Position(coord)
    self.TacticalCoord = coord
    self.DesiredTacticalCoord = coord
    self:Flag_To_Redraw(true)
end

--[[
    Center the map on a specific coordinate.

    @return COORDINATE of the center
]]
function DisplayClass:Center_Map()
    -- Calculate center based on map dimensions
    local center_x = Coord.CELL_LEPTON_W * 32  -- Half of 64-cell map
    local center_y = Coord.CELL_LEPTON_H * 32

    -- Offset by half the viewport
    local view_center_x = center_x - (self.TacLeptonWidth / 2)
    local view_center_y = center_y - (self.TacLeptonHeight / 2)

    local coord = Coord.XY_Coord(math.max(0, view_center_x), math.max(0, view_center_y))
    self:Set_Tactical_Position(coord)

    return coord
end

--============================================================================
-- Coordinate Conversions
--============================================================================

--[[
    Convert screen pixel position to game coordinate.

    @param x - Pixel X (relative to screen)
    @param y - Pixel Y (relative to screen)
    @return COORDINATE in game space
]]
function DisplayClass:Pixel_To_Coord(x, y)
    -- Adjust for tactical viewport offset
    local tac_x = x - self.TacPixelX
    local tac_y = y - self.TacPixelY

    -- Convert to leptons
    local lepton_x = tac_x * DisplayClass.PIXEL_LEPTON_W
    local lepton_y = tac_y * DisplayClass.PIXEL_LEPTON_H

    -- Add tactical position offset
    local tac_lep_x = Coord.Coord_X(self.TacticalCoord)
    local tac_lep_y = Coord.Coord_Y(self.TacticalCoord)

    return Coord.XY_Coord(tac_lep_x + lepton_x, tac_lep_y + lepton_y)
end

--[[
    Convert game coordinate to screen pixel position.

    @param coord - COORDINATE in game space
    @param x - (out) Pixel X
    @param y - (out) Pixel Y
    @return true if coordinate is visible, x, y
]]
function DisplayClass:Coord_To_Pixel(coord)
    -- Get coordinate components
    local coord_x = Coord.Coord_X(coord)
    local coord_y = Coord.Coord_Y(coord)

    -- Get tactical position
    local tac_x = Coord.Coord_X(self.TacticalCoord)
    local tac_y = Coord.Coord_Y(self.TacticalCoord)

    -- Calculate offset from tactical corner
    local offset_x = coord_x - tac_x
    local offset_y = coord_y - tac_y

    -- Convert to pixels
    local pixel_x = offset_x / DisplayClass.PIXEL_LEPTON_W + self.TacPixelX
    local pixel_y = offset_y / DisplayClass.PIXEL_LEPTON_H + self.TacPixelY

    -- Check if visible
    local visible = offset_x >= 0 and offset_x < self.TacLeptonWidth
                and offset_y >= 0 and offset_y < self.TacLeptonHeight

    return visible, pixel_x, pixel_y
end

--[[
    Convert screen click position to cell.

    @param x - Screen X position
    @param y - Screen Y position
    @return CELL number or -1 if invalid
]]
function DisplayClass:Click_Cell_Calc(x, y)
    local coord = self:Pixel_To_Coord(x, y)
    return Coord.Coord_Cell(coord)
end

--============================================================================
-- Layer Management
--============================================================================

--[[
    Submit an object to a display layer.

    @param object - ObjectClass to add
    @param layer - LayerType enum value
]]
function DisplayClass:Submit(object, layer)
    if object and layer >= 0 and layer < LayerClass.LAYER_COUNT then
        LayerClass.Submit_To(object, layer, false)
    end
end

--[[
    Remove an object from a display layer.

    @param object - ObjectClass to remove
    @param layer - LayerType enum value
]]
function DisplayClass:Remove(object, layer)
    if object and layer >= 0 and layer < LayerClass.LAYER_COUNT then
        LayerClass.Remove_From(object, layer)
    end
end

--============================================================================
-- View Query
--============================================================================

--[[
    Check if a cell is within the visible tactical view.

    @param cell - CELL number to check
    @return true if cell is visible
]]
function DisplayClass:In_View(cell)
    local coord = Coord.Cell_Coord(cell)
    local coord_x = Coord.Coord_X(coord)
    local coord_y = Coord.Coord_Y(coord)

    local tac_x = Coord.Coord_X(self.TacticalCoord)
    local tac_y = Coord.Coord_Y(self.TacticalCoord)

    return coord_x >= tac_x
       and coord_x < (tac_x + self.TacLeptonWidth)
       and coord_y >= tac_y
       and coord_y < (tac_y + self.TacLeptonHeight)
end

--============================================================================
-- Cell Flagging
--============================================================================

--[[
    Flag a specific cell to be redrawn.

    @param cell - CELL number to flag
]]
function DisplayClass:Flag_Cell(cell)
    self:Flag_To_Redraw(false)
    self.IsToRedraw = true
    self.CellRedraw[cell] = true
end

--[[
    Check if a cell is flagged for redraw.

    @param cell - CELL number to check
    @return true if cell needs redrawing
]]
function DisplayClass:Is_Cell_Flagged(cell)
    return self.CellRedraw[cell] == true
end

--[[
    Clear all cell redraw flags.
]]
function DisplayClass:Clear_Cell_Flags()
    self.CellRedraw = {}
end

--============================================================================
-- Mode Control
--============================================================================

--[[
    Toggle repair mode.

    @param control - 0=off, 1=on, -1=toggle
]]
function DisplayClass:Repair_Mode_Control(control)
    if control == 0 then
        self.IsRepairMode = false
    elseif control == 1 then
        self.IsRepairMode = true
    else
        self.IsRepairMode = not self.IsRepairMode
    end

    -- Turn off other modes
    if self.IsRepairMode then
        self.IsSellMode = false
    end
end

--[[
    Toggle sell mode.

    @param control - 0=off, 1=on, -1=toggle
]]
function DisplayClass:Sell_Mode_Control(control)
    if control == 0 then
        self.IsSellMode = false
    elseif control == 1 then
        self.IsSellMode = true
    else
        self.IsSellMode = not self.IsSellMode
    end

    -- Turn off other modes
    if self.IsSellMode then
        self.IsRepairMode = false
    end
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Main AI processing.
]]
function DisplayClass:AI(key, x, y)
    GScreenClass.AI(self, key, x, y)

    -- Sort all layers each frame for proper Y-ordering
    LayerClass.Sort_All()
end

--[[
    Draw the tactical display.

    @param complete - If true, perform complete redraw
]]
function DisplayClass:Draw_It(complete)
    GScreenClass.Draw_It(self, complete)

    -- Draw layers in order: GROUND, AIR, TOP
    for layer_type = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Get_Layer(layer_type)
        if layer then
            self:Draw_Layer(layer, layer_type)
        end
    end

    -- Draw rubber band selection if active
    if self.IsRubberBand then
        self:Draw_Rubber_Band()
    end
end

--[[
    Draw all objects in a layer.

    @param layer - LayerClass instance
    @param layer_type - Layer type enum value
]]
function DisplayClass:Draw_Layer(layer, layer_type)
    for object in layer:Iterate() do
        if object and object.Render then
            local visible, x, y = self:Coord_To_Pixel(object.Coord or 0)
            if visible then
                object:Render(false)
            end
        end
    end
end

--[[
    Draw the rubber band selection rectangle.
]]
function DisplayClass:Draw_Rubber_Band()
    if not self.IsRubberBand then return end

    local x1 = math.min(self.BandX, self.NewX)
    local y1 = math.min(self.BandY, self.NewY)
    local x2 = math.max(self.BandX, self.NewX)
    local y2 = math.max(self.BandY, self.NewY)

    love.graphics.setColor(0, 1, 0, 0.5)
    love.graphics.rectangle("line", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(1, 1, 1, 1)
end

--============================================================================
-- Selection
--============================================================================

--[[
    Select all units within a rectangular region.

    @param coord1 - First corner coordinate
    @param coord2 - Second corner coordinate
    @param additive - If true, add to selection; if false, replace
]]
function DisplayClass:Select_These(coord1, coord2, additive)
    local x1 = math.min(Coord.Coord_X(coord1), Coord.Coord_X(coord2))
    local y1 = math.min(Coord.Coord_Y(coord1), Coord.Coord_Y(coord2))
    local x2 = math.max(Coord.Coord_X(coord1), Coord.Coord_X(coord2))
    local y2 = math.max(Coord.Coord_Y(coord1), Coord.Coord_Y(coord2))

    -- Iterate through ground layer (where selectable units are)
    local layer = LayerClass.Get_Layer(LayerClass.LAYER_TYPE.GROUND)
    if not layer then return end

    for object in layer:Iterate() do
        if object and object.Coord then
            local obj_x = Coord.Coord_X(object.Coord)
            local obj_y = Coord.Coord_Y(object.Coord)

            if obj_x >= x1 and obj_x <= x2 and obj_y >= y1 and obj_y <= y2 then
                if object.Select then
                    object:Select()
                end
            end
        end
    end
end

--============================================================================
-- Object Finding
--============================================================================

--[[
    Find the object at a specific cell.

    @param cell - CELL number
    @param x - Sub-cell X offset (optional)
    @param y - Sub-cell Y offset (optional)
    @return ObjectClass or nil
]]
function DisplayClass:Cell_Object(cell, x, y)
    x = x or 0
    y = y or 0

    local cell_coord = Coord.Cell_Coord(cell)

    -- Check all layers
    for layer_type = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Get_Layer(layer_type)
        if layer then
            for object in layer:Iterate() do
                if object and object.Coord then
                    local obj_cell = Coord.Coord_Cell(object.Coord)
                    if obj_cell == cell then
                        return object
                    end
                end
            end
        end
    end

    return nil
end

--[[
    Get the next object in the selection cycle.

    @param object - Current object (or nil for first)
    @return Next ObjectClass or nil
]]
function DisplayClass:Next_Object(object)
    local layer = LayerClass.Get_Layer(LayerClass.LAYER_TYPE.GROUND)
    if not layer then return nil end

    local found_current = (object == nil)

    for obj in layer:Iterate() do
        if found_current then
            return obj
        end
        if obj == object then
            found_current = true
        end
    end

    -- Wrap around to first
    return layer:Get(1)
end

--[[
    Get the previous object in the selection cycle.

    @param object - Current object
    @return Previous ObjectClass or nil
]]
function DisplayClass:Prev_Object(object)
    local layer = LayerClass.Get_Layer(LayerClass.LAYER_TYPE.GROUND)
    if not layer then return nil end

    local prev = nil
    for obj in layer:Iterate() do
        if obj == object then
            return prev
        end
        prev = obj
    end

    -- Return last object if wrapping
    return layer:Get(layer:Count())
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function DisplayClass:Code_Pointers()
    local data = GScreenClass.Code_Pointers(self)

    data.Theater = self.Theater
    data.TacticalCoord = self.TacticalCoord
    data.DesiredTacticalCoord = self.DesiredTacticalCoord
    data.TacLeptonWidth = self.TacLeptonWidth
    data.TacLeptonHeight = self.TacLeptonHeight
    data.TacPixelX = self.TacPixelX
    data.TacPixelY = self.TacPixelY
    data.IsRepairMode = self.IsRepairMode
    data.IsSellMode = self.IsSellMode
    data.IsTargettingMode = self.IsTargettingMode

    -- Encode layers
    data.Layers = {}
    for i = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Get_Layer(i)
        if layer then
            data.Layers[i] = layer:Code_Pointers()
        end
    end

    return data
end

function DisplayClass:Decode_Pointers(data, heap_lookup)
    GScreenClass.Decode_Pointers(self, data)

    if data then
        self.Theater = data.Theater or DisplayClass.THEATER.TEMPERATE
        self.TacticalCoord = data.TacticalCoord or 0
        self.DesiredTacticalCoord = data.DesiredTacticalCoord or 0
        self.TacLeptonWidth = data.TacLeptonWidth or 0
        self.TacLeptonHeight = data.TacLeptonHeight or 0
        self.TacPixelX = data.TacPixelX or 0
        self.TacPixelY = data.TacPixelY or 0
        self.IsRepairMode = data.IsRepairMode or false
        self.IsSellMode = data.IsSellMode or false
        self.IsTargettingMode = data.IsTargettingMode or 0

        -- Decode layers
        if data.Layers and heap_lookup then
            for i = 0, LayerClass.LAYER_COUNT - 1 do
                local layer = LayerClass.Get_Layer(i)
                if layer and data.Layers[i] then
                    layer:Decode_Pointers(data.Layers[i], heap_lookup)
                end
            end
        end
    end
end

--============================================================================
-- Debug Support
--============================================================================

function DisplayClass:Debug_Dump()
    GScreenClass.Debug_Dump(self)

    print(string.format("DisplayClass: Theater=%d TacticalCoord=%08X",
        self.Theater, self.TacticalCoord))
    print(string.format("  TacLepton: %dx%d TacPixel: %d,%d",
        self.TacLeptonWidth, self.TacLeptonHeight,
        self.TacPixelX, self.TacPixelY))
    print(string.format("  Modes: Repair=%s Sell=%s Target=%d",
        tostring(self.IsRepairMode), tostring(self.IsSellMode),
        self.IsTargettingMode))

    -- Dump layer counts
    for i = 0, LayerClass.LAYER_COUNT - 1 do
        local layer = LayerClass.Get_Layer(i)
        if layer then
            print(string.format("  Layer[%s]: %d objects",
                LayerClass.LAYER_NAMES[i], layer:Count()))
        end
    end
end

return DisplayClass
