--[[
    RadarClass - Minimap/radar display

    Port of RADAR.H/CPP from the original C&C source.

    RadarClass extends DisplayClass to provide:
    - Minimap rendering
    - Click-to-scroll functionality
    - Radar activation/deactivation animation
    - Zoom mode toggle
    - Player names display mode

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/RADAR.H
]]

local Class = require("src.objects.class")
local DisplayClass = require("src.display.display")
local Coord = require("src.core.coord")

-- RadarClass extends DisplayClass
local RadarClass = Class.extend(DisplayClass, "RadarClass")

--============================================================================
-- Constants
--============================================================================

RadarClass.RADAR_ACTIVATED_FRAME = 22
RadarClass.MAX_RADAR_FRAMES = 41
RadarClass.PIXELSTACK = 200  -- Max pixels to update per frame

--============================================================================
-- Constructor
--============================================================================

function RadarClass:init()
    -- Call parent constructor
    DisplayClass.init(self)

    --[[
        Radar display area position and dimensions.
    ]]
    self.RadX = 0            -- Radar area X position
    self.RadOffX = 0         -- Offset within radar area
    self.RadY = 0            -- Radar area Y position
    self.RadOffY = 0         -- Offset within radar area
    self.RadWidth = 64       -- Radar display width
    self.RadHeight = 64      -- Radar display height
    self.RadIWidth = 64      -- Internal width
    self.RadIHeight = 64     -- Internal height
    self.RadPWidth = 64      -- Pixel width
    self.RadPHeight = 64     -- Pixel height

    --[[
        Radar state flags.
    ]]
    self.IsToRedraw = false          -- Needs complete redraw
    self.RadarCursorRedraw = false   -- Cursor needs redraw
    self.DoesRadarExist = false      -- Radar has been built
    self.IsRadarActive = false       -- Radar is fully active
    self.IsRadarActivating = false   -- Animation playing (activating)
    self.IsRadarDeactivating = false -- Animation playing (deactivating)

    --[[
        Animation frame tracking.
    ]]
    self.SpecialRadarFrame = 0   -- Special cursor frame (0-7)
    self.RadarAnimFrame = 0      -- Current animation frame

    --[[
        Current radar view position (in cells).
    ]]
    self.RadarX = 0
    self.RadarY = 0
    self.RadarCell = 0
    self.BaseX = 0
    self.BaseY = 0
    self.RadarWidth_Cells = 0
    self.RadarCellWidth = 0
    self.RadarHeight_Cells = 0
    self.RadarCellHeight = 0

    --[[
        Zoom state.
    ]]
    self.IsZoomed = false
    self.ZoomFactor = 1

    --[[
        Player names display mode.
    ]]
    self.IsPlayerNames = false

    --[[
        Pixel update queue for incremental radar updates.
    ]]
    self.PixelPtr = 0
    self.PixelStack = {}
end

--============================================================================
-- Initialization
--============================================================================

function RadarClass:One_Time()
    DisplayClass.One_Time(self)

    -- Set default radar position (upper right corner in original)
    self.RadX = love.graphics.getWidth() - 160
    self.RadY = 0
    self.RadWidth = 64
    self.RadHeight = 64
end

function RadarClass:Init_Clear()
    DisplayClass.Init_Clear(self)

    self.DoesRadarExist = false
    self.IsRadarActive = false
    self.IsRadarActivating = false
    self.IsRadarDeactivating = false
    self.RadarAnimFrame = 0
    self.IsZoomed = false
    self.IsPlayerNames = false
    self.PixelPtr = 0
    self.PixelStack = {}
end

--============================================================================
-- Map Dimensions
--============================================================================

--[[
    Set the map dimensions for radar display.

    @param x - Map X offset
    @param y - Map Y offset
    @param w - Map width in cells
    @param h - Map height in cells
]]
function RadarClass:Set_Map_Dimensions(x, y, w, h)
    -- Store for radar calculations
    self.MapCellX = x
    self.MapCellY = y
    self.MapCellWidth = w
    self.MapCellHeight = h

    -- Calculate radar scale
    self:Calculate_Radar_Scale()
end

--[[
    Calculate the radar display scale based on map size.
]]
function RadarClass:Calculate_Radar_Scale()
    if self.MapCellWidth and self.MapCellHeight then
        -- Fit map into radar area
        local scale_x = self.RadWidth / self.MapCellWidth
        local scale_y = self.RadHeight / self.MapCellHeight
        self.ZoomFactor = math.min(scale_x, scale_y)
    else
        self.ZoomFactor = 1
    end
end

--============================================================================
-- Tactical Position Override
--============================================================================

--[[
    Override tactical position to also update radar cursor.
]]
function RadarClass:Set_Tactical_Position(coord)
    DisplayClass.Set_Tactical_Position(self, coord)

    -- Update radar cursor position
    self.RadarCursorRedraw = true
end

--============================================================================
-- Radar State Control
--============================================================================

--[[
    Activate or deactivate the radar.

    @param control - -1=toggle, 0=deactivate, 1=activate
    @return true if radar is now active
]]
function RadarClass:Radar_Activate(control)
    local should_be_active = false

    if control < 0 then
        should_be_active = not self.IsRadarActive
    else
        should_be_active = (control > 0)
    end

    if should_be_active and not self.IsRadarActive then
        -- Start activating
        if self.DoesRadarExist then
            self.IsRadarActivating = true
            self.IsRadarDeactivating = false
            self.RadarAnimFrame = 0
        end
    elseif not should_be_active and self.IsRadarActive then
        -- Start deactivating
        self.IsRadarDeactivating = true
        self.IsRadarActivating = false
        self.RadarAnimFrame = RadarClass.MAX_RADAR_FRAMES - 1
    end

    return self.IsRadarActive
end

--[[
    Check if radar is active.
]]
function RadarClass:Is_Radar_Active()
    return self.IsRadarActive
end

--[[
    Check if radar is in activation animation.
]]
function RadarClass:Is_Radar_Activating()
    return self.IsRadarActivating
end

--[[
    Check if a radar building exists.
]]
function RadarClass:Is_Radar_Existing()
    return self.DoesRadarExist
end

--[[
    Toggle zoom mode.

    @param cell - Cell to center zoom on
]]
function RadarClass:Zoom_Mode(cell)
    self.IsZoomed = not self.IsZoomed
    self:Calculate_Radar_Scale()
    self:Flag_To_Redraw(true)
end

--============================================================================
-- Click Handling
--============================================================================

--[[
    Override click cell calculation to handle radar clicks.

    @param x - Screen X
    @param y - Screen Y
    @return CELL number or -1
]]
function RadarClass:Click_Cell_Calc(x, y)
    -- Check if click is in radar area
    local radar_cell = self:Click_In_Radar(x, y)
    if radar_cell >= 0 then
        return radar_cell
    end

    -- Otherwise use normal tactical calculation
    return DisplayClass.Click_Cell_Calc(self, x, y)
end

--[[
    Check if a click is within the radar area.

    @param x - Screen X
    @param y - Screen Y
    @param change - If true, scroll to clicked position
    @return CELL clicked on, or -1 if not in radar
]]
function RadarClass:Click_In_Radar(x, y, change)
    change = change or false

    if not self.IsRadarActive then
        return -1
    end

    -- Check bounds
    if x < self.RadX or x >= self.RadX + self.RadWidth then
        return -1
    end
    if y < self.RadY or y >= self.RadY + self.RadHeight then
        return -1
    end

    -- Convert to cell
    local rel_x = x - self.RadX
    local rel_y = y - self.RadY

    local cell_x = math.floor(rel_x / self.ZoomFactor) + (self.MapCellX or 0)
    local cell_y = math.floor(rel_y / self.ZoomFactor) + (self.MapCellY or 0)

    local cell = Coord.XY_Cell(cell_x, cell_y)

    -- Scroll if requested
    if change then
        self:Set_Radar_Position(cell)
    end

    return cell
end

--[[
    Set the radar center position.

    @param cell - CELL to center on
]]
function RadarClass:Set_Radar_Position(cell)
    -- Calculate tactical position to center the view on this cell
    local cell_x = Coord.Cell_X(cell)
    local cell_y = Coord.Cell_Y(cell)

    -- Convert to coordinate and center
    local coord = Coord.XYL_Coord(cell_x, cell_y, 128, 128)

    -- Offset to put this at center of viewport
    local offset_x = self.TacLeptonWidth / 2
    local offset_y = self.TacLeptonHeight / 2

    local new_x = math.max(0, Coord.Coord_X(coord) - offset_x)
    local new_y = math.max(0, Coord.Coord_Y(coord) - offset_y)

    self:Set_Tactical_Position(Coord.XY_Coord(new_x, new_y))
end

--[[
    Get current radar position.

    @return CELL at center of radar view
]]
function RadarClass:Radar_Position()
    local cell_x = Coord.Coord_XCell(self.TacticalCoord)
    local cell_y = Coord.Coord_YCell(self.TacticalCoord)
    return Coord.XY_Cell(cell_x, cell_y)
end

--============================================================================
-- Coordinate Conversions
--============================================================================

--[[
    Convert cell coordinates to radar pixel position.

    @param cellx - Cell X
    @param celly - Cell Y
    @return x, y pixel position
]]
function RadarClass:Cell_XY_To_Radar_Pixel(cellx, celly)
    local rel_x = (cellx - (self.MapCellX or 0)) * self.ZoomFactor
    local rel_y = (celly - (self.MapCellY or 0)) * self.ZoomFactor

    return self.RadX + rel_x, self.RadY + rel_y
end

--[[
    Convert game coordinate to radar pixel position.

    @param coord - COORDINATE
    @return x, y pixel position
]]
function RadarClass:Coord_To_Radar_Pixel(coord)
    local cell_x = Coord.Coord_XCell(coord)
    local cell_y = Coord.Coord_YCell(coord)
    return self:Cell_XY_To_Radar_Pixel(cell_x, cell_y)
end

--[[
    Check if a cell is visible on the radar.

    @param cell - CELL to check
    @return true if visible
]]
function RadarClass:Cell_On_Radar(cell)
    if not self.IsRadarActive then
        return false
    end

    local cell_x = Coord.Cell_X(cell)
    local cell_y = Coord.Cell_Y(cell)

    local map_x = self.MapCellX or 0
    local map_y = self.MapCellY or 0
    local map_w = self.MapCellWidth or 64
    local map_h = self.MapCellHeight or 64

    return cell_x >= map_x and cell_x < map_x + map_w
       and cell_y >= map_y and cell_y < map_y + map_h
end

--============================================================================
-- Rendering
--============================================================================

--[[
    Main AI processing.
]]
function RadarClass:AI(key, x, y)
    DisplayClass.AI(self, key, x, y)

    -- Process activation/deactivation animation
    if self.IsRadarActivating then
        self.RadarAnimFrame = self.RadarAnimFrame + 1
        if self.RadarAnimFrame >= RadarClass.RADAR_ACTIVATED_FRAME then
            self.IsRadarActivating = false
            self.IsRadarActive = true
        end
    elseif self.IsRadarDeactivating then
        self.RadarAnimFrame = self.RadarAnimFrame - 1
        if self.RadarAnimFrame <= 0 then
            self.IsRadarDeactivating = false
            self.IsRadarActive = false
        end
    end
end

--[[
    Draw the display including radar.
]]
function RadarClass:Draw_It(complete)
    DisplayClass.Draw_It(self, complete)

    -- Draw radar if it exists
    if self.DoesRadarExist then
        self:Draw_Radar(complete)
    end
end

--[[
    Draw the radar display.

    @param complete - Full redraw if true
]]
function RadarClass:Draw_Radar(complete)
    -- Draw radar background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", self.RadX, self.RadY, self.RadWidth, self.RadHeight)

    if self.IsRadarActive or self.IsRadarActivating then
        -- Draw terrain pixels
        self:Draw_Radar_Terrain()

        -- Draw units on radar
        self:Draw_Radar_Units()

        -- Draw viewport cursor
        self:Draw_Radar_Cursor()
    end

    -- Draw radar frame/border
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("line", self.RadX, self.RadY, self.RadWidth, self.RadHeight)

    love.graphics.setColor(1, 1, 1, 1)
end

--[[
    Draw terrain on radar.
]]
function RadarClass:Draw_Radar_Terrain()
    -- Simplified terrain rendering - just draw base colors
    -- A full implementation would read from CellClass terrain data
    local map_w = self.MapCellWidth or 64
    local map_h = self.MapCellHeight or 64

    love.graphics.setColor(0.2, 0.4, 0.2, 1)  -- Green for ground
    love.graphics.rectangle("fill",
        self.RadX + 2, self.RadY + 2,
        self.RadWidth - 4, self.RadHeight - 4)
end

--[[
    Draw units on radar.
]]
function RadarClass:Draw_Radar_Units()
    -- Would iterate through all objects and draw colored dots
    -- For now, placeholder
end

--[[
    Draw the viewport cursor on radar.
]]
function RadarClass:Draw_Radar_Cursor()
    if not self.IsRadarActive then return end

    -- Calculate viewport rectangle on radar
    local tac_cell_x = Coord.Coord_XCell(self.TacticalCoord)
    local tac_cell_y = Coord.Coord_YCell(self.TacticalCoord)

    -- Viewport size in cells
    local view_w = math.ceil(self.TacLeptonWidth / 256)
    local view_h = math.ceil(self.TacLeptonHeight / 256)

    local x, y = self:Cell_XY_To_Radar_Pixel(tac_cell_x, tac_cell_y)
    local w = view_w * self.ZoomFactor
    local h = view_h * self.ZoomFactor

    -- Draw white rectangle for viewport
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", x, y, w, h)
end

--[[
    Animate radar (update pixels incrementally).
]]
function RadarClass:Radar_Anim()
    -- Incremental pixel update system
    -- Would process PixelStack entries
end

--============================================================================
-- Player Names Mode
--============================================================================

--[[
    Toggle player names display on radar.

    @param on - true to show names, false to hide
]]
function RadarClass:Player_Names(on)
    self.IsPlayerNames = on
    self:Flag_To_Redraw(true)
end

--[[
    Check if player names are displayed.
]]
function RadarClass:Is_Player_Names()
    return self.IsPlayerNames
end

--[[
    Draw player names on radar.
]]
function RadarClass:Draw_Names()
    if not self.IsPlayerNames then return end

    -- Would draw player names at their HQ locations
end

--============================================================================
-- Refresh
--============================================================================

--[[
    Refresh specific cells on the radar.

    @param cell - Base cell
    @param list - List of cell offsets to refresh
]]
function RadarClass:Refresh_Cells(cell, list)
    DisplayClass.Refresh_Cells(self, cell, list)

    -- Queue radar pixels for update
    if self:Cell_On_Radar(cell) then
        self:Plot_Radar_Pixel(cell)
    end
end

--[[
    Queue a radar pixel for update.

    @param cell - CELL to update
]]
function RadarClass:Plot_Radar_Pixel(cell)
    if self.PixelPtr < RadarClass.PIXELSTACK then
        self.PixelPtr = self.PixelPtr + 1
        self.PixelStack[self.PixelPtr] = cell
    end
end

--[[
    Update a single radar pixel.

    @param cell - CELL to render
]]
function RadarClass:Radar_Pixel(cell)
    -- Would read cell terrain/occupancy and draw appropriate color
end

--============================================================================
-- Rendering Helpers
--============================================================================

--[[
    Render terrain for a cell on radar.

    @param cell - CELL to render
    @param x - Radar pixel X
    @param y - Radar pixel Y
    @param size - Pixel size
]]
function RadarClass:Render_Terrain(cell, x, y, size)
    -- Get terrain type and draw appropriate color
    love.graphics.setColor(0.2, 0.4, 0.2, 1)
    love.graphics.rectangle("fill", x, y, size, size)
end

--[[
    Render infantry on radar.

    @param cell - CELL to check
    @param x - Radar pixel X
    @param y - Radar pixel Y
    @param size - Pixel size
]]
function RadarClass:Render_Infantry(cell, x, y, size)
    -- Would check cell for infantry and draw house color
end

--[[
    Render overlay (tiberium/walls) on radar.

    @param cell - CELL to check
    @param x - Radar pixel X
    @param y - Radar pixel Y
    @param size - Pixel size
]]
function RadarClass:Render_Overlay(cell, x, y, size)
    -- Would check cell overlay and draw appropriate color
    -- Tiberium = green, walls = gray
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function RadarClass:Code_Pointers()
    local data = DisplayClass.Code_Pointers(self)

    data.RadX = self.RadX
    data.RadY = self.RadY
    data.RadWidth = self.RadWidth
    data.RadHeight = self.RadHeight
    data.DoesRadarExist = self.DoesRadarExist
    data.IsRadarActive = self.IsRadarActive
    data.IsZoomed = self.IsZoomed

    return data
end

function RadarClass:Decode_Pointers(data, heap_lookup)
    DisplayClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.RadX = data.RadX or 0
        self.RadY = data.RadY or 0
        self.RadWidth = data.RadWidth or 64
        self.RadHeight = data.RadHeight or 64
        self.DoesRadarExist = data.DoesRadarExist or false
        self.IsRadarActive = data.IsRadarActive or false
        self.IsZoomed = data.IsZoomed or false
    end
end

--============================================================================
-- Debug Support
--============================================================================

function RadarClass:Debug_Dump()
    DisplayClass.Debug_Dump(self)

    print(string.format("RadarClass: Pos=%d,%d Size=%dx%d",
        self.RadX, self.RadY, self.RadWidth, self.RadHeight))
    print(string.format("  Exists=%s Active=%s Zoomed=%s",
        tostring(self.DoesRadarExist),
        tostring(self.IsRadarActive),
        tostring(self.IsZoomed)))
end

return RadarClass
