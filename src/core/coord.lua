--[[
    COORDINATE and CELL manipulation utilities

    Ported from the original C&C coordinate system:
    - COORDINATE: 32-bit packed value (cell + lepton offset)
    - CELL: 16-bit packed value (x << 6 | y for 64x64 map)

    Reference: COORD.CPP, DEFINES.H
]]

local Constants = require("src.core.constants")

-- LuaJIT bit operations
local bit = bit or bit32 or require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local Coord = {}

-- Constants from original (DEFINES.H)
Coord.CELL_MASK = 0x003F         -- 6 bits for cell position (0-63)
Coord.LEPTON_MASK = 0x00FF       -- 8 bits for sub-cell position (0-255)
Coord.CELL_LEPTON_W = 256        -- Leptons per cell
Coord.MAP_CELL_W = 64            -- Map width in cells
Coord.MAP_CELL_H = 64            -- Map height in cells

-- Coordinate bit layout (32-bit COORDINATE):
-- Bits 0-7:   X sub-cell (lepton) position
-- Bits 8-13:  X cell position (0-63)
-- Bits 14-15: Unused
-- Bits 16-23: Y sub-cell (lepton) position
-- Bits 24-29: Y cell position (0-63)
-- Bits 30-31: Unused

Coord.X_LEPTON_SHIFT = 0
Coord.X_CELL_SHIFT = 8
Coord.Y_LEPTON_SHIFT = 16
Coord.Y_CELL_SHIFT = 24

--============================================================================
-- CELL Operations (16-bit packed cell position)
--============================================================================

--[[
    Create a CELL value from x, y coordinates
    CELL is packed as: (y << 6) | x
]]
function Coord.XY_Cell(x, y)
    x = band(x, Coord.CELL_MASK)
    y = band(y, Coord.CELL_MASK)
    return bor(lshift(y, 6), x)
end

--[[
    Extract X cell coordinate from CELL
]]
function Coord.Cell_X(cell)
    return band(cell, Coord.CELL_MASK)
end

--[[
    Extract Y cell coordinate from CELL
]]
function Coord.Cell_Y(cell)
    return band(rshift(cell, 6), Coord.CELL_MASK)
end

--[[
    Get adjacent cell in given facing direction
    facing: 0-7 (N, NE, E, SE, S, SW, W, NW)
]]
function Coord.Adjacent_Cell(cell, facing)
    local x = Coord.Cell_X(cell)
    local y = Coord.Cell_Y(cell)

    -- Direction offsets (N=0, rotating clockwise)
    local dx = {[0]=0, 1, 1, 1, 0, -1, -1, -1}
    local dy = {[0]=-1, -1, 0, 1, 1, 1, 0, -1}

    x = x + (dx[facing] or 0)
    y = y + (dy[facing] or 0)

    -- Clamp to map bounds
    if x < 0 or x >= Coord.MAP_CELL_W or y < 0 or y >= Coord.MAP_CELL_H then
        return -1  -- Invalid cell
    end

    return Coord.XY_Cell(x, y)
end

--[[
    Check if CELL is within map bounds
]]
function Coord.Cell_Is_Valid(cell)
    if cell < 0 then return false end
    local x = Coord.Cell_X(cell)
    local y = Coord.Cell_Y(cell)
    return x >= 0 and x < Coord.MAP_CELL_W and y >= 0 and y < Coord.MAP_CELL_H
end

--============================================================================
-- COORDINATE Operations (32-bit packed coordinate with sub-cell precision)
--============================================================================

--[[
    Create a COORDINATE from cell x, y and lepton offsets
]]
function Coord.XYL_Coord(cell_x, cell_y, lepton_x, lepton_y)
    lepton_x = lepton_x or 128  -- Default to cell center
    lepton_y = lepton_y or 128

    return bor(
        lshift(band(lepton_x, Coord.LEPTON_MASK), Coord.X_LEPTON_SHIFT),
        lshift(band(cell_x, Coord.CELL_MASK), Coord.X_CELL_SHIFT),
        lshift(band(lepton_y, Coord.LEPTON_MASK), Coord.Y_LEPTON_SHIFT),
        lshift(band(cell_y, Coord.CELL_MASK), Coord.Y_CELL_SHIFT)
    )
end

--[[
    Create a COORDINATE from a CELL (centered in cell)
]]
function Coord.Cell_Coord(cell)
    local x = Coord.Cell_X(cell)
    local y = Coord.Cell_Y(cell)
    return Coord.XYL_Coord(x, y, 128, 128)
end

--[[
    Extract the CELL from a COORDINATE
]]
function Coord.Coord_Cell(coord)
    local x = band(rshift(coord, Coord.X_CELL_SHIFT), Coord.CELL_MASK)
    local y = band(rshift(coord, Coord.Y_CELL_SHIFT), Coord.CELL_MASK)
    return Coord.XY_Cell(x, y)
end

--[[
    Extract X cell coordinate from COORDINATE
]]
function Coord.Coord_XCell(coord)
    return band(rshift(coord, Coord.X_CELL_SHIFT), Coord.CELL_MASK)
end

--[[
    Extract Y cell coordinate from COORDINATE
]]
function Coord.Coord_YCell(coord)
    return band(rshift(coord, Coord.Y_CELL_SHIFT), Coord.CELL_MASK)
end

--[[
    Extract X lepton (sub-cell) from COORDINATE
]]
function Coord.Coord_XLepton(coord)
    return band(rshift(coord, Coord.X_LEPTON_SHIFT), Coord.LEPTON_MASK)
end

--[[
    Extract Y lepton (sub-cell) from COORDINATE
]]
function Coord.Coord_YLepton(coord)
    return band(rshift(coord, Coord.Y_LEPTON_SHIFT), Coord.LEPTON_MASK)
end

--[[
    Get full X position in leptons (cell * 256 + sub-cell)
]]
function Coord.Coord_X(coord)
    local cell_x = Coord.Coord_XCell(coord)
    local lepton_x = Coord.Coord_XLepton(coord)
    return cell_x * Coord.CELL_LEPTON_W + lepton_x
end

--[[
    Get full Y position in leptons (cell * 256 + sub-cell)
]]
function Coord.Coord_Y(coord)
    local cell_y = Coord.Coord_YCell(coord)
    local lepton_y = Coord.Coord_YLepton(coord)
    return cell_y * Coord.CELL_LEPTON_W + lepton_y
end

--[[
    Create COORDINATE from full lepton X, Y values
]]
function Coord.XY_Coord(lepton_x, lepton_y)
    local cell_x = math.floor(lepton_x / Coord.CELL_LEPTON_W)
    local cell_y = math.floor(lepton_y / Coord.CELL_LEPTON_W)
    local sub_x = lepton_x % Coord.CELL_LEPTON_W
    local sub_y = lepton_y % Coord.CELL_LEPTON_W
    return Coord.XYL_Coord(cell_x, cell_y, sub_x, sub_y)
end

--[[
    Snap coordinate to cell center
]]
function Coord.Coord_Snap(coord)
    local cell = Coord.Coord_Cell(coord)
    return Coord.Cell_Coord(cell)
end

--============================================================================
-- Distance and Direction
--============================================================================

--[[
    Calculate distance between two COORDINATEs (in leptons)
    Uses the original C&C approximation: max(dx, dy) + min(dx, dy)/2
]]
function Coord.Distance(coord1, coord2)
    local x1, y1 = Coord.Coord_X(coord1), Coord.Coord_Y(coord1)
    local x2, y2 = Coord.Coord_X(coord2), Coord.Coord_Y(coord2)

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)

    -- Original C&C distance approximation (faster than sqrt)
    if dx > dy then
        return dx + rshift(dy, 1)
    else
        return dy + rshift(dx, 1)
    end
end

--[[
    Calculate exact Euclidean distance (in leptons)
]]
function Coord.Distance_Exact(coord1, coord2)
    local x1, y1 = Coord.Coord_X(coord1), Coord.Coord_Y(coord1)
    local x2, y2 = Coord.Coord_X(coord2), Coord.Coord_Y(coord2)

    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

--[[
    Calculate cell distance between two CELLs
]]
function Coord.Cell_Distance(cell1, cell2)
    local x1, y1 = Coord.Cell_X(cell1), Coord.Cell_Y(cell1)
    local x2, y2 = Coord.Cell_X(cell2), Coord.Cell_Y(cell2)

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)

    return math.max(dx, dy)  -- Chebyshev distance for cell-based pathfinding
end

--[[
    Calculate direction from coord1 to coord2
    Returns 0-255 (256 directions, 0 = North)
]]
function Coord.Direction256(coord1, coord2)
    local x1, y1 = Coord.Coord_X(coord1), Coord.Coord_Y(coord1)
    local x2, y2 = Coord.Coord_X(coord2), Coord.Coord_Y(coord2)

    local dx = x2 - x1
    local dy = y2 - y1

    if dx == 0 and dy == 0 then
        return 0
    end

    -- Convert to angle and then to 0-255 direction
    local angle = math.atan2(dy, dx)
    -- Rotate so North (up) is 0
    angle = angle + math.pi / 2
    if angle < 0 then angle = angle + math.pi * 2 end

    return math.floor((angle / (math.pi * 2)) * 256) % 256
end

--[[
    Calculate direction from coord1 to coord2
    Returns 0-7 (8 cardinal directions, 0 = North)
]]
function Coord.Direction8(coord1, coord2)
    local dir256 = Coord.Direction256(coord1, coord2)
    return math.floor((dir256 + 16) / 32) % 8
end

--[[
    Calculate direction between two CELLs
    Returns 0-7 (8 cardinal directions)
]]
function Coord.Cell_Direction(cell1, cell2)
    local coord1 = Coord.Cell_Coord(cell1)
    local coord2 = Coord.Cell_Coord(cell2)
    return Coord.Direction8(coord1, coord2)
end

--============================================================================
-- Coordinate Movement
--============================================================================

--[[
    Move a coordinate by a delta (in leptons)
]]
function Coord.Coord_Move(coord, dx, dy)
    local x = Coord.Coord_X(coord) + dx
    local y = Coord.Coord_Y(coord) + dy

    -- Clamp to map bounds
    local max_x = (Coord.MAP_CELL_W - 1) * Coord.CELL_LEPTON_W + 255
    local max_y = (Coord.MAP_CELL_H - 1) * Coord.CELL_LEPTON_W + 255

    x = math.max(0, math.min(max_x, x))
    y = math.max(0, math.min(max_y, y))

    return Coord.XY_Coord(x, y)
end

--[[
    Move a coordinate in a direction by a distance.
    Port of Coord_Move(coord, dir, dist) from COORD.CPP

    @param coord - Starting COORDINATE
    @param direction - Direction (0-255, where 0=N, 64=E, 128=S, 192=W)
    @param distance - Distance to move in leptons
    @return New COORDINATE
]]
function Coord.Coord_Move_Dir(coord, direction, distance)
    if distance == 0 then return coord end

    -- Convert direction (0-255) to radians
    -- Direction 0 = North, 64 = East, 128 = South, 192 = West
    local radians = (direction / 256) * 2 * math.pi

    -- Calculate deltas (note: Y is inverted in screen coords)
    local dx = math.sin(radians) * distance
    local dy = -math.cos(radians) * distance

    local x = Coord.Coord_X(coord) + dx
    local y = Coord.Coord_Y(coord) + dy

    -- Clamp to map bounds
    local max_x = (Coord.MAP_CELL_W - 1) * Coord.CELL_LEPTON_W + 255
    local max_y = (Coord.MAP_CELL_H - 1) * Coord.CELL_LEPTON_W + 255

    x = math.max(0, math.min(max_x, x))
    y = math.max(0, math.min(max_y, y))

    return Coord.XY_Coord(math.floor(x), math.floor(y))
end

--[[
    Move coordinate toward target by specified distance (in leptons)
]]
function Coord.Coord_Move_Toward(coord, target, distance)
    local x1, y1 = Coord.Coord_X(coord), Coord.Coord_Y(coord)
    local x2, y2 = Coord.Coord_X(target), Coord.Coord_Y(target)

    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist <= distance then
        return target
    end

    local ratio = distance / dist
    local new_x = x1 + dx * ratio
    local new_y = y1 + dy * ratio

    return Coord.XY_Coord(new_x, new_y)
end

--============================================================================
-- Pixel Conversion
--============================================================================

-- Pixels per cell (for rendering)
Coord.CELL_PIXEL_W = Constants.CELL_PIXEL_W
Coord.CELL_PIXEL_H = Constants.CELL_PIXEL_H
Coord.LEPTON_PER_PIXEL = Coord.CELL_LEPTON_W / Coord.CELL_PIXEL_W

--[[
    Convert COORDINATE to screen pixel position
]]
function Coord.Coord_To_Pixel(coord)
    local x = Coord.Coord_X(coord)
    local y = Coord.Coord_Y(coord)
    return x / Coord.LEPTON_PER_PIXEL, y / Coord.LEPTON_PER_PIXEL
end

--[[
    Convert pixel position to COORDINATE
]]
function Coord.Pixel_To_Coord(pixel_x, pixel_y)
    local x = pixel_x * Coord.LEPTON_PER_PIXEL
    local y = pixel_y * Coord.LEPTON_PER_PIXEL
    return Coord.XY_Coord(x, y)
end

--[[
    Convert CELL to screen pixel position (top-left corner)
]]
function Coord.Cell_To_Pixel(cell)
    local x = Coord.Cell_X(cell)
    local y = Coord.Cell_Y(cell)
    return x * Coord.CELL_PIXEL_W, y * Coord.CELL_PIXEL_H
end

--[[
    Convert pixel position to CELL
]]
function Coord.Pixel_To_Cell(pixel_x, pixel_y)
    local x = math.floor(pixel_x / Coord.CELL_PIXEL_W)
    local y = math.floor(pixel_y / Coord.CELL_PIXEL_H)
    return Coord.XY_Cell(x, y)
end

--============================================================================
-- Debug Helpers
--============================================================================

--[[
    Format COORDINATE as string for debugging
]]
function Coord.Coord_String(coord)
    local cell_x = Coord.Coord_XCell(coord)
    local cell_y = Coord.Coord_YCell(coord)
    local lep_x = Coord.Coord_XLepton(coord)
    local lep_y = Coord.Coord_YLepton(coord)
    return string.format("(%d,%d)+(%d,%d)", cell_x, cell_y, lep_x, lep_y)
end

--[[
    Format CELL as string for debugging
]]
function Coord.Cell_String(cell)
    return string.format("(%d,%d)", Coord.Cell_X(cell), Coord.Cell_Y(cell))
end

return Coord
