--[[
    MonoClass - Port of original C&C monochrome debug display

    Reference: MONOC.H, MONOC.CPP
    The original MonoClass provided a separate monochrome display for
    debugging information during development. This port provides
    equivalent functionality using a virtual text buffer that can be
    rendered as an overlay or logged to file.

    Original features:
    - 80x25 character display
    - Multiple pages (up to 16)
    - Box drawing with different styles
    - Cursor positioning
    - Printf-style output
]]

local Mono = {}
Mono.__index = Mono

-- Constants matching original (MONOC.H:73-79)
Mono.COLUMNS = 80
Mono.LINES = 25
Mono.MAX_MONO_PAGES = 16
Mono.DEFAULT_ATTRIBUTE = 0x02  -- Normal white on black

-- Box styles (MONOC.H:91-97)
Mono.BOX_STYLE = {
    SINGLE = 1,       -- Single thickness
    DOUBLE_HORZ = 2,  -- Double thick on horizontal
    DOUBLE_VERT = 3,  -- Double thick on vertical
    DOUBLE = 4        -- Double thickness
}

-- Box drawing characters for each style
Mono.BOX_CHARS = {
    [1] = {  -- SINGLE
        upper_left = "┌",
        top_edge = "─",
        upper_right = "┐",
        right_edge = "│",
        bottom_right = "┘",
        bottom_edge = "─",
        bottom_left = "└",
        left_edge = "│"
    },
    [2] = {  -- DOUBLE_HORZ
        upper_left = "╒",
        top_edge = "═",
        upper_right = "╕",
        right_edge = "│",
        bottom_right = "╛",
        bottom_edge = "═",
        bottom_left = "╘",
        left_edge = "│"
    },
    [3] = {  -- DOUBLE_VERT
        upper_left = "╓",
        top_edge = "─",
        upper_right = "╖",
        right_edge = "║",
        bottom_right = "╜",
        bottom_edge = "─",
        bottom_left = "╙",
        left_edge = "║"
    },
    [4] = {  -- DOUBLE
        upper_left = "╔",
        top_edge = "═",
        upper_right = "╗",
        right_edge = "║",
        bottom_right = "╝",
        bottom_edge = "═",
        bottom_left = "╚",
        left_edge = "║"
    }
}

-- Class-level state (static in original)
Mono.Enabled = false
Mono.PageUsage = {}  -- Maps page index to MonoClass instance
Mono.CurrentPage = nil

--[[
    Enable monochrome output globally.

    Reference: MONOC.H:103
]]
function Mono.Enable()
    Mono.Enabled = true
end

--[[
    Disable monochrome output globally.

    Reference: MONOC.H:104
]]
function Mono.Disable()
    Mono.Enabled = false
end

--[[
    Check if monochrome output is enabled.

    Reference: MONOC.H:105
]]
function Mono.Is_Enabled()
    return Mono.Enabled
end

--[[
    Get the currently visible mono page.

    Reference: MONOC.H:106
]]
function Mono.Get_Current()
    return Mono.PageUsage[1]
end

--[[
    Create a new MonoClass instance.

    Reference: MONOC.CPP constructor
]]
function Mono.new()
    local self = setmetatable({}, Mono)

    -- Instance state (MONOC.H:135-138)
    self.X = 0           -- Cursor X position
    self.Y = 0           -- Cursor Y position
    self.Attrib = Mono.DEFAULT_ATTRIBUTE
    self.Page = 0        -- Current page number

    -- Screen buffer (80x25 cells)
    self.buffer = {}
    for y = 0, Mono.LINES - 1 do
        self.buffer[y] = {}
        for x = 0, Mono.COLUMNS - 1 do
            self.buffer[y][x] = {
                char = " ",
                attrib = self.Attrib
            }
        end
    end

    -- Find an available page
    for i = 1, Mono.MAX_MONO_PAGES do
        if not Mono.PageUsage[i] then
            self.Page = i - 1
            Mono.PageUsage[i] = self
            break
        end
    end

    return self
end

--[[
    Destructor - release page.
]]
function Mono:destroy()
    for i, page in pairs(Mono.PageUsage) do
        if page == self then
            Mono.PageUsage[i] = nil
            break
        end
    end
end

--[[
    Clear the screen.

    Reference: MONOC.CPP Clear()
]]
function Mono:Clear()
    for y = 0, Mono.LINES - 1 do
        for x = 0, Mono.COLUMNS - 1 do
            self.buffer[y][x] = {
                char = " ",
                attrib = self.Attrib
            }
        end
    end
    self.X = 0
    self.Y = 0
end

--[[
    Set cursor position.

    Reference: MONOC.CPP Set_Cursor()
]]
function Mono:Set_Cursor(x, y)
    self.X = math.max(0, math.min(x, Mono.COLUMNS - 1))
    self.Y = math.max(0, math.min(y, Mono.LINES - 1))
end

--[[
    Get cursor X position.

    Reference: MONOC.H:119
]]
function Mono:Get_X()
    return self.X
end

--[[
    Get cursor Y position.

    Reference: MONOC.H:120
]]
function Mono:Get_Y()
    return self.Y
end

--[[
    Set the default attribute.

    Reference: MONOC.H:109
]]
function Mono:Set_Default_Attribute(attrib)
    self.Attrib = attrib
end

--[[
    Store a cell at position.

    Reference: MONOC.H:145-147
]]
function Mono:Store_Cell(char, x, y, attrib)
    if x >= 0 and x < Mono.COLUMNS and y >= 0 and y < Mono.LINES then
        self.buffer[y][x] = {
            char = char,
            attrib = attrib or self.Attrib
        }
    end
end

--[[
    Scroll the display.

    Reference: MONOC.CPP Scroll()
]]
function Mono:Scroll(lines)
    if lines <= 0 then return end

    -- Move lines up
    for y = 0, Mono.LINES - 1 - lines do
        self.buffer[y] = self.buffer[y + lines]
    end

    -- Clear bottom lines
    for y = Mono.LINES - lines, Mono.LINES - 1 do
        self.buffer[y] = {}
        for x = 0, Mono.COLUMNS - 1 do
            self.buffer[y][x] = {
                char = " ",
                attrib = self.Attrib
            }
        end
    end
end

--[[
    Print text at current cursor position.

    Reference: MONOC.CPP Print()
]]
function Mono:Print(text)
    if not Mono.Enabled then return end

    text = tostring(text)
    for i = 1, #text do
        local c = text:sub(i, i)

        if c == "\n" then
            self.X = 0
            self.Y = self.Y + 1
            if self.Y >= Mono.LINES then
                self:Scroll(1)
                self.Y = Mono.LINES - 1
            end
        elseif c == "\r" then
            self.X = 0
        elseif c == "\t" then
            self.X = math.floor((self.X + 8) / 8) * 8
            if self.X >= Mono.COLUMNS then
                self.X = 0
                self.Y = self.Y + 1
                if self.Y >= Mono.LINES then
                    self:Scroll(1)
                    self.Y = Mono.LINES - 1
                end
            end
        else
            self:Store_Cell(c, self.X, self.Y)
            self.X = self.X + 1
            if self.X >= Mono.COLUMNS then
                self.X = 0
                self.Y = self.Y + 1
                if self.Y >= Mono.LINES then
                    self:Scroll(1)
                    self.Y = Mono.LINES - 1
                end
            end
        end
    end
end

--[[
    Printf-style output.

    Reference: MONOC.CPP Printf()
]]
function Mono:Printf(format, ...)
    if not Mono.Enabled then return end
    self:Print(string.format(format, ...))
end

--[[
    Print text at specific position.

    Reference: MONOC.CPP Text_Print()
]]
function Mono:Text_Print(text, x, y, attrib)
    if not Mono.Enabled then return end

    attrib = attrib or self.Attrib
    text = tostring(text)

    for i = 1, #text do
        local c = text:sub(i, i)
        local px = x + i - 1
        if px >= 0 and px < Mono.COLUMNS and y >= 0 and y < Mono.LINES then
            self:Store_Cell(c, px, y, attrib)
        end
    end
end

--[[
    Draw a box.

    Reference: MONOC.CPP Draw_Box()
]]
function Mono:Draw_Box(x, y, w, h, attrib, style)
    if not Mono.Enabled then return end

    attrib = attrib or self.Attrib
    style = style or Mono.BOX_STYLE.SINGLE
    local chars = Mono.BOX_CHARS[style] or Mono.BOX_CHARS[1]

    -- Top edge
    self:Store_Cell(chars.upper_left, x, y, attrib)
    for i = 1, w - 2 do
        self:Store_Cell(chars.top_edge, x + i, y, attrib)
    end
    self:Store_Cell(chars.upper_right, x + w - 1, y, attrib)

    -- Sides
    for i = 1, h - 2 do
        self:Store_Cell(chars.left_edge, x, y + i, attrib)
        self:Store_Cell(chars.right_edge, x + w - 1, y + i, attrib)
    end

    -- Bottom edge
    self:Store_Cell(chars.bottom_left, x, y + h - 1, attrib)
    for i = 1, w - 2 do
        self:Store_Cell(chars.bottom_edge, x + i, y + h - 1, attrib)
    end
    self:Store_Cell(chars.bottom_right, x + w - 1, y + h - 1, attrib)
end

--[[
    Make this page visible.

    Reference: MONOC.CPP View()
]]
function Mono:View()
    -- Move this page to front of PageUsage
    local page_index = nil
    for i, page in pairs(Mono.PageUsage) do
        if page == self then
            page_index = i
            break
        end
    end

    if page_index and page_index ~= 1 then
        -- Swap with front
        Mono.PageUsage[page_index] = Mono.PageUsage[1]
        Mono.PageUsage[1] = self
    end

    Mono.CurrentPage = self
end

--[[
    Get the buffer as a string for display.
]]
function Mono:Get_Buffer_String()
    local lines = {}
    for y = 0, Mono.LINES - 1 do
        local line = ""
        for x = 0, Mono.COLUMNS - 1 do
            line = line .. self.buffer[y][x].char
        end
        -- Trim trailing spaces
        line = line:gsub("%s+$", "")
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

--[[
    Render the mono display using Love2D graphics.

    @param x, y - Screen position to render at
    @param font - Love2D font to use (should be monospace)
    @param scale - Scale factor (default 1)
]]
function Mono:Render(x, y, font, scale)
    if not Mono.Enabled or not love then return end

    x = x or 0
    y = y or 0
    scale = scale or 1

    local char_width = font and font:getWidth("M") or 8
    local char_height = font and font:getHeight() or 16

    -- Draw background
    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", x, y,
        Mono.COLUMNS * char_width * scale,
        Mono.LINES * char_height * scale)

    -- Draw text
    if font then
        love.graphics.setFont(font)
    end

    for row = 0, Mono.LINES - 1 do
        for col = 0, Mono.COLUMNS - 1 do
            local cell = self.buffer[row][col]
            if cell.char ~= " " then
                -- Set color based on attribute (simplified)
                local attrib = cell.attrib
                if attrib == 0x02 then
                    love.graphics.setColor(0, 1, 0)  -- Green
                elseif attrib == 0x04 then
                    love.graphics.setColor(1, 0, 0)  -- Red
                elseif attrib == 0x0E then
                    love.graphics.setColor(1, 1, 0)  -- Yellow
                else
                    love.graphics.setColor(0.8, 0.8, 0.8)  -- White
                end

                love.graphics.print(cell.char,
                    x + col * char_width * scale,
                    y + row * char_height * scale,
                    0, scale, scale)
            end
        end
    end

    love.graphics.setColor(1, 1, 1)
end

--[[
    Global convenience functions matching original C API.

    Reference: MONOC.H:178-185
]]
function Mono_Set_Cursor(x, y)
    local current = Mono.Get_Current()
    if current then
        current:Set_Cursor(x, y)
    end
end

function Mono_Printf(format, ...)
    local current = Mono.Get_Current()
    if current then
        current:Printf(format, ...)
    end
end

function Mono_Clear_Screen()
    local current = Mono.Get_Current()
    if current then
        current:Clear()
    end
end

function Mono_Text_Print(text, x, y, attrib)
    local current = Mono.Get_Current()
    if current then
        current:Text_Print(text, x, y, attrib)
    end
end

function Mono_Draw_Rect(x, y, w, h, attrib, style)
    local current = Mono.Get_Current()
    if current then
        current:Draw_Box(x, y, w, h, attrib, style)
    end
end

function Mono_Print(text)
    local current = Mono.Get_Current()
    if current then
        current:Print(text)
    end
end

function Mono_X()
    local current = Mono.Get_Current()
    return current and current:Get_X() or 0
end

function Mono_Y()
    local current = Mono.Get_Current()
    return current and current:Get_Y() or 0
end

-- Export global functions
Mono.Mono_Set_Cursor = Mono_Set_Cursor
Mono.Mono_Printf = Mono_Printf
Mono.Mono_Clear_Screen = Mono_Clear_Screen
Mono.Mono_Text_Print = Mono_Text_Print
Mono.Mono_Draw_Rect = Mono_Draw_Rect
Mono.Mono_Print = Mono_Print
Mono.Mono_X = Mono_X
Mono.Mono_Y = Mono_Y

return Mono
