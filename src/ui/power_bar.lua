--[[
    Power Bar - Power production/consumption indicator
    Shows power status on the sidebar matching original C&C style
    Reference: Original C&C power bar UI
]]

local Events = require("src.core.events")

local PowerBar = {}
PowerBar.__index = PowerBar

function PowerBar.new()
    local self = setmetatable({}, PowerBar)

    -- Power values
    self.power_output = 0      -- Total power produced
    self.power_drain = 0       -- Total power consumed
    self.max_display = 1000    -- Max power to display (scales)

    -- Display settings
    self.x = 0
    self.y = 0
    self.width = 16
    self.height = 200

    -- Colors (matching original C&C)
    self.colors = {
        background = {0.1, 0.1, 0.1, 0.9},
        border = {0.3, 0.3, 0.3, 1},
        output_high = {0, 0.8, 0, 1},       -- Green when power good
        output_low = {1, 0.8, 0, 1},        -- Yellow when power marginal
        output_critical = {0.8, 0, 0, 1},   -- Red when low power
        drain = {0.8, 0.3, 0, 1},           -- Orange for drain indicator
        tick_mark = {0.5, 0.5, 0.5, 1},     -- Gray tick marks
        text = {1, 1, 1, 1}
    }

    -- Animation
    self.flash_timer = 0
    self.flash_rate = 2.0      -- Flashes per second when critical
    self.flashing = false

    -- Vertical orientation (bar fills from bottom)
    self.vertical = true

    -- Labels
    self.show_values = true

    -- House reference
    self.house = nil

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function PowerBar:register_events()
    Events.on("POWER_CHANGED", function(house, output, drain)
        if house == self.house then
            self:set_power(output, drain)
        end
    end)

    Events.on("LOW_POWER", function()
        self.flashing = true
    end)
end

-- Set house to track
function PowerBar:set_house(house)
    self.house = house
    if house then
        self:set_power(house.power_output or 0, house.power_drain or 0)
    end
end

-- Set power values
function PowerBar:set_power(output, drain)
    self.power_output = output or 0
    self.power_drain = drain or 0

    -- Update max display to scale appropriately
    local max_val = math.max(self.power_output, self.power_drain)
    if max_val > self.max_display * 0.9 then
        self.max_display = math.ceil(max_val / 100) * 100 + 100
    elseif max_val < self.max_display * 0.5 and self.max_display > 500 then
        self.max_display = math.max(500, math.ceil(max_val / 100) * 100 + 200)
    end

    -- Check for low power
    self.flashing = self.power_output < self.power_drain
end

-- Get power ratio (0-1, capped at 1)
function PowerBar:get_power_ratio()
    if self.power_drain == 0 then return 1 end
    return math.min(1, self.power_output / self.power_drain)
end

-- Is power critical?
function PowerBar:is_critical()
    return self.power_output < self.power_drain
end

-- Update animation
function PowerBar:update(dt)
    if self.flashing then
        self.flash_timer = self.flash_timer + dt * self.flash_rate * math.pi * 2
    end

    -- Update from house if set
    if self.house then
        self.power_output = self.house.power_output or 0
        self.power_drain = self.house.power_drain or 0
        self.flashing = self.power_output < self.power_drain
    end
end

-- Draw power bar
function PowerBar:draw()
    local x, y, w, h = self.x, self.y, self.width, self.height

    -- Background
    love.graphics.setColor(unpack(self.colors.background))
    love.graphics.rectangle("fill", x, y, w, h)

    -- Calculate fill heights
    local output_fill = self.power_output / self.max_display
    local drain_fill = self.power_drain / self.max_display

    output_fill = math.min(1, output_fill)
    drain_fill = math.min(1, drain_fill)

    -- Determine output bar color
    local ratio = self:get_power_ratio()
    local output_color

    if ratio >= 1 then
        output_color = self.colors.output_high
    elseif ratio >= 0.5 then
        output_color = self.colors.output_low
    else
        output_color = self.colors.output_critical
    end

    -- Flash effect when critical
    if self.flashing then
        local flash_alpha = 0.5 + 0.5 * math.sin(self.flash_timer)
        output_color = {output_color[1], output_color[2], output_color[3], flash_alpha}
    end

    if self.vertical then
        -- Vertical bar (fills from bottom)
        local output_height = h * output_fill
        local drain_height = h * drain_fill

        -- Output bar (green/yellow/red)
        love.graphics.setColor(unpack(output_color))
        love.graphics.rectangle("fill",
            x + 2,
            y + h - output_height,
            w / 2 - 3,
            output_height
        )

        -- Drain bar (orange)
        love.graphics.setColor(unpack(self.colors.drain))
        love.graphics.rectangle("fill",
            x + w / 2 + 1,
            y + h - drain_height,
            w / 2 - 3,
            drain_height
        )

        -- Drain line indicator (horizontal line showing consumption level)
        if self.power_drain > 0 then
            local drain_y = y + h - drain_height
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(x, drain_y, x + w, drain_y)
            love.graphics.setLineWidth(1)
        end

        -- Tick marks
        love.graphics.setColor(unpack(self.colors.tick_mark))
        local num_ticks = 10
        for i = 1, num_ticks - 1 do
            local tick_y = y + (h / num_ticks) * i
            love.graphics.line(x, tick_y, x + 3, tick_y)
            love.graphics.line(x + w - 3, tick_y, x + w, tick_y)
        end

    else
        -- Horizontal bar
        local output_width = w * output_fill
        local drain_width = w * drain_fill

        -- Output bar
        love.graphics.setColor(unpack(output_color))
        love.graphics.rectangle("fill",
            x,
            y + 2,
            output_width,
            h / 2 - 3
        )

        -- Drain bar
        love.graphics.setColor(unpack(self.colors.drain))
        love.graphics.rectangle("fill",
            x,
            y + h / 2 + 1,
            drain_width,
            h / 2 - 3
        )

        -- Drain line indicator
        if self.power_drain > 0 then
            local drain_x = x + drain_width
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(drain_x, y, drain_x, y + h)
            love.graphics.setLineWidth(1)
        end
    end

    -- Border
    love.graphics.setColor(unpack(self.colors.border))
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)

    -- Labels
    if self.show_values then
        love.graphics.setColor(unpack(self.colors.text))

        if self.vertical then
            -- Top label (power output)
            local output_text = tostring(math.floor(self.power_output))
            local font = love.graphics.getFont()
            local text_w = font:getWidth(output_text)
            love.graphics.print(output_text, x + (w - text_w) / 2, y - 18)

            -- Bottom label (power drain)
            local drain_text = tostring(math.floor(self.power_drain))
            text_w = font:getWidth(drain_text)
            love.graphics.print(drain_text, x + (w - text_w) / 2, y + h + 4)
        else
            -- Left label
            love.graphics.print(tostring(math.floor(self.power_output)), x - 30, y + h / 4)
            love.graphics.print(tostring(math.floor(self.power_drain)), x - 30, y + h * 3 / 4)
        end
    end

    -- Power status icon/text
    if self:is_critical() then
        love.graphics.setColor(1, 0.3, 0.3, 0.5 + 0.5 * math.sin(self.flash_timer))
        local warning_text = "!"
        local font = love.graphics.getFont()
        local text_w = font:getWidth(warning_text)
        love.graphics.print(warning_text, x + (w - text_w) / 2, y + h / 2 - 8)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Set display position
function PowerBar:set_position(x, y)
    self.x = x
    self.y = y
end

-- Set display size
function PowerBar:set_size(width, height)
    self.width = width
    self.height = height
end

-- Set orientation
function PowerBar:set_vertical(vertical)
    self.vertical = vertical
end

-- Set whether to show value labels
function PowerBar:set_show_values(show)
    self.show_values = show
end

-- Draw compact power indicator (just a colored bar)
function PowerBar:draw_compact(x, y, w, h)
    local ratio = self:get_power_ratio()

    -- Background
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Fill color based on ratio
    local r, g, b
    if ratio >= 1 then
        r, g, b = 0, 0.8, 0
    elseif ratio >= 0.5 then
        r, g, b = 1, 0.8, 0
    else
        r, g, b = 0.8, 0, 0
        -- Flash when critical
        if self.flashing then
            local flash = 0.5 + 0.5 * math.sin(self.flash_timer)
            r = r * flash + 0.3
        end
    end

    -- Draw fill
    love.graphics.setColor(r, g, b, 1)
    love.graphics.rectangle("fill", x + 1, y + 1, (w - 2) * math.min(1, ratio), h - 2)

    -- Border
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("line", x, y, w, h)

    love.graphics.setColor(1, 1, 1, 1)
end

return PowerBar
