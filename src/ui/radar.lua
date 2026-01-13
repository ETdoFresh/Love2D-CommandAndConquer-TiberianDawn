--[[
    Radar/Minimap UI - Shows tactical overview of the map
    Requires power and Communications Center (HQ) to function
    Reference: Original C&C radar implementation
]]

local Constants = require("src.core.constants")

local Radar = {}
Radar.__index = Radar

-- Radar dimensions
Radar.SIZE = 128  -- Square minimap

function Radar.new()
    local self = setmetatable({}, Radar)

    self.x = 0
    self.y = 0
    self.size = Radar.SIZE

    -- Map reference
    self.grid = nil

    -- Systems reference
    self.power_system = nil
    self.fog_system = nil

    -- Player info
    self.house = Constants.HOUSE.GOOD

    -- Radar state
    self.is_active = false
    self.has_comm_center = false
    self.has_power = false

    -- Cached minimap image
    self.minimap_canvas = nil
    self.needs_update = true

    -- Colors for different elements
    self.colors = {
        terrain = {0.3, 0.35, 0.25, 1},     -- Green terrain
        tiberium = {0.2, 0.8, 0.2, 1},       -- Bright green tiberium
        water = {0.2, 0.3, 0.6, 1},          -- Blue water
        rock = {0.4, 0.35, 0.3, 1},          -- Brown rock
        building_friendly = {0, 1, 0, 1},    -- Green friendly buildings
        building_enemy = {1, 0, 0, 1},       -- Red enemy buildings
        unit_friendly = {0.8, 1, 0.8, 1},    -- Light green friendly units
        unit_enemy = {1, 0.5, 0.5, 1},       -- Light red enemy units
        fog = {0.1, 0.1, 0.1, 0.9},          -- Dark fog
        shroud = {0, 0, 0, 1},               -- Black shroud
        viewport = {1, 1, 1, 0.8},           -- White viewport box
        offline = {0.2, 0.2, 0.2, 1},        -- Offline background
    }

    -- Animation for radar sweep
    self.sweep_angle = 0
    self.sweep_speed = math.pi  -- Radians per second

    -- Low power flickering effect
    -- Reference: Original C&C - radar flickered at low power before going offline
    self.flicker_timer = 0
    self.flicker_rate = 0.15    -- Seconds between flickers at low power
    self.flicker_state = true   -- On/off for flicker effect
    self.is_low_power = false   -- Power between 50-100% (still active but flickering)

    -- World reference for entity queries
    self.world = nil

    return self
end

function Radar:init(world, grid)
    self.world = world
    self.grid = grid
    self.power_system = world:get_system("power")
    self.fog_system = world:get_system("fog")

    -- Create canvas for minimap
    self.minimap_canvas = love.graphics.newCanvas(self.size, self.size)
    self.needs_update = true
end

function Radar:set_position(x, y)
    self.x = x
    self.y = y
end

function Radar:set_house(house)
    self.house = house
end

function Radar:update(dt)
    -- Check if player has Communications Center
    self:check_comm_center()

    -- Check power status
    if self.power_system then
        self.has_power = self.power_system:is_radar_active(self.house)

        -- Check for low power (50-100%) - still active but flickering
        local power_level = self.power_system:get_power_level(self.house)
        self.is_low_power = (power_level == "low")
    else
        self.has_power = true  -- Assume power OK if no system
        self.is_low_power = false
    end

    -- Radar is active if we have both comm center and power
    self.is_active = self.has_comm_center and self.has_power

    -- Update sweep animation
    if self.is_active then
        self.sweep_angle = self.sweep_angle + self.sweep_speed * dt
        if self.sweep_angle > math.pi * 2 then
            self.sweep_angle = self.sweep_angle - math.pi * 2
        end

        -- Update low power flicker effect
        -- Reference: Original C&C - radar flickered/glitched at low power
        if self.is_low_power then
            self.flicker_timer = self.flicker_timer + dt
            if self.flicker_timer >= self.flicker_rate then
                self.flicker_timer = self.flicker_timer - self.flicker_rate
                self.flicker_state = not self.flicker_state
            end
        else
            self.flicker_state = true  -- Always on when full power
        end
    end

    -- Update minimap periodically
    if self.is_active and self.needs_update then
        self:update_minimap()
        self.needs_update = false
    end
end

function Radar:check_comm_center()
    if not self.world then
        self.has_comm_center = false
        return
    end

    -- Look for HQ (Comm Center) owned by player
    local buildings = self.world:get_entities_with("building", "owner")
    self.has_comm_center = false

    for _, building in ipairs(buildings) do
        local building_data = building:get("building")
        local owner = building:get("owner")

        if owner.house == self.house then
            -- HQ is the Communications Center
            if building_data.structure_type == "HQ" then
                self.has_comm_center = true
                return
            end
        end
    end
end

function Radar:update_minimap()
    if not self.grid or not self.minimap_canvas then
        return
    end

    local prev_canvas = love.graphics.getCanvas()
    love.graphics.setCanvas(self.minimap_canvas)
    love.graphics.clear(0, 0, 0, 1)

    -- Calculate scale
    local map_width = self.grid.width
    local map_height = self.grid.height
    local scale_x = self.size / map_width
    local scale_y = self.size / map_height

    -- Draw terrain
    for cy = 0, map_height - 1 do
        for cx = 0, map_width - 1 do
            local cell = self.grid:get_cell(cx, cy)
            if cell then
                local px = cx * scale_x
                local py = cy * scale_y

                -- Choose color based on cell type
                if cell:has_tiberium() then
                    love.graphics.setColor(self.colors.tiberium)
                elseif cell.template_type == 2 then  -- Water
                    love.graphics.setColor(self.colors.water)
                elseif cell.template_type == 1 then  -- Rock
                    love.graphics.setColor(self.colors.rock)
                else
                    love.graphics.setColor(self.colors.terrain)
                end

                love.graphics.rectangle("fill", px, py, math.max(1, scale_x), math.max(1, scale_y))
            end
        end
    end

    love.graphics.setCanvas(prev_canvas)
end

function Radar:draw(camera_x, camera_y, viewport_w, viewport_h)
    local x = self.x
    local y = self.y

    -- Draw border
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("line", x - 1, y - 1, self.size + 2, self.size + 2)

    if self.is_active then
        -- Apply low power flicker effect
        -- Reference: Original C&C - radar flickered and had scan lines at low power
        local alpha = 1.0
        if self.is_low_power and not self.flicker_state then
            alpha = 0.3  -- Dim during flicker
        end

        -- Draw minimap
        if self.minimap_canvas then
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(self.minimap_canvas, x, y)
        end

        -- Draw entities (buildings and units)
        if alpha > 0.5 then
            self:draw_entities()
        end

        -- Draw viewport indicator
        self:draw_viewport(camera_x, camera_y, viewport_w, viewport_h)

        -- Draw radar sweep line for visual effect
        self:draw_sweep()

        -- Draw low power scan line effect
        if self.is_low_power then
            self:draw_power_interference()
        end
    else
        -- Radar is offline - show static or dark screen
        love.graphics.setColor(self.colors.offline)
        love.graphics.rectangle("fill", x, y, self.size, self.size)

        -- Show offline message
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        local msg = not self.has_comm_center and "NO RADAR" or "LOW POWER"
        love.graphics.printf(msg, x, y + self.size / 2 - 8, self.size, "center")

        -- Static noise effect
        self:draw_static()
    end
end

function Radar:draw_entities()
    if not self.world or not self.grid then
        return
    end

    local scale_x = self.size / self.grid.width
    local scale_y = self.size / self.grid.height

    -- Draw buildings
    local buildings = self.world:get_entities_with("building", "owner", "transform")
    for _, building in ipairs(buildings) do
        local transform = building:get("transform")
        local owner = building:get("owner")
        local building_data = building:get("building")

        local px = self.x + (transform.cell_x * scale_x)
        local py = self.y + (transform.cell_y * scale_y)
        local bw = (building_data.size_x or 1) * scale_x
        local bh = (building_data.size_y or 1) * scale_y

        if owner.house == self.house then
            love.graphics.setColor(self.colors.building_friendly)
        else
            love.graphics.setColor(self.colors.building_enemy)
        end

        love.graphics.rectangle("fill", px, py, math.max(2, bw), math.max(2, bh))
    end

    -- Draw units
    local units = self.world:get_entities_with("transform", "owner", "mobile")
    for _, unit in ipairs(units) do
        local transform = unit:get("transform")
        local owner = unit:get("owner")

        local cell_x = math.floor(transform.x / Constants.LEPTON_PER_CELL)
        local cell_y = math.floor(transform.y / Constants.LEPTON_PER_CELL)
        local px = self.x + (cell_x * scale_x)
        local py = self.y + (cell_y * scale_y)

        if owner.house == self.house then
            love.graphics.setColor(self.colors.unit_friendly)
        else
            love.graphics.setColor(self.colors.unit_enemy)
        end

        love.graphics.rectangle("fill", px, py, 2, 2)
    end
end

function Radar:draw_viewport(camera_x, camera_y, viewport_w, viewport_h)
    if not self.grid then
        return
    end

    local scale_x = self.size / self.grid.width
    local scale_y = self.size / self.grid.height

    -- Convert camera position (in pixels) to cells
    local cam_cell_x = camera_x / Constants.CELL_PIXEL_W
    local cam_cell_y = camera_y / Constants.CELL_PIXEL_H
    local view_cells_w = viewport_w / Constants.CELL_PIXEL_W
    local view_cells_h = viewport_h / Constants.CELL_PIXEL_H

    local vx = self.x + (cam_cell_x * scale_x)
    local vy = self.y + (cam_cell_y * scale_y)
    local vw = view_cells_w * scale_x
    local vh = view_cells_h * scale_y

    love.graphics.setColor(self.colors.viewport)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", vx, vy, vw, vh)
end

function Radar:draw_sweep()
    -- Radar sweep line effect
    local cx = self.x + self.size / 2
    local cy = self.y + self.size / 2
    local radius = self.size / 2

    love.graphics.setColor(0, 1, 0, 0.3)
    local sweep_x = cx + math.cos(self.sweep_angle) * radius
    local sweep_y = cy + math.sin(self.sweep_angle) * radius
    love.graphics.line(cx, cy, sweep_x, sweep_y)
end

function Radar:draw_static()
    -- Random static noise when radar is offline
    love.graphics.setColor(0.3, 0.3, 0.3, 0.5)
    for i = 1, 20 do
        local sx = self.x + math.random(0, self.size)
        local sy = self.y + math.random(0, self.size)
        local sw = math.random(1, 4)
        local sh = math.random(1, 4)
        love.graphics.rectangle("fill", sx, sy, sw, sh)
    end
end

-- Draw power interference effect (scan lines and static at low power)
-- Reference: Original C&C - radar had interference patterns at low power
function Radar:draw_power_interference()
    -- Horizontal scan lines
    love.graphics.setColor(0, 0.5, 0, 0.2)
    local time = love.timer.getTime()
    local scan_offset = (time * 50) % self.size

    -- Draw moving scan line
    love.graphics.rectangle("fill", self.x, self.y + scan_offset, self.size, 2)

    -- Random interference spots
    love.graphics.setColor(0, 0.8, 0, 0.3)
    for i = 1, 5 do
        local sx = self.x + math.random(0, self.size)
        local sy = self.y + math.random(0, self.size)
        love.graphics.rectangle("fill", sx, sy, math.random(2, 8), 1)
    end

    -- "LOW POWER" text overlay
    love.graphics.setColor(1, 0.5, 0, 0.8)
    love.graphics.printf("LOW POWER", self.x, self.y + 5, self.size, "center")
end

function Radar:mousepressed(mx, my, button)
    -- Check if click is on radar
    if mx < self.x or mx > self.x + self.size then
        return false
    end
    if my < self.y or my > self.y + self.size then
        return false
    end

    if not self.is_active or not self.grid then
        return true  -- Consume click but don't do anything
    end

    -- Calculate clicked map position
    local scale_x = self.size / self.grid.width
    local scale_y = self.size / self.grid.height

    local cell_x = (mx - self.x) / scale_x
    local cell_y = (my - self.y) / scale_y

    -- Emit camera move request
    if self.on_click then
        self.on_click(cell_x * Constants.CELL_PIXEL_W, cell_y * Constants.CELL_PIXEL_H)
    end

    return true
end

function Radar:set_click_callback(callback)
    self.on_click = callback
end

function Radar:request_update()
    self.needs_update = true
end

return Radar
