--[[
    Campaign Map - World map mission selection UI
    Faithful recreation of original C&C world map with mission markers and branching paths
    Reference: Original C&C campaign selection with regional zones
]]

local Events = require("src.core.events")

local CampaignMap = {}
CampaignMap.__index = CampaignMap

-- Mission node positions on world map (normalized 0-1 coordinates)
-- Based on original C&C mission locations in Eastern Europe/Africa
CampaignMap.GDI_MISSIONS = {
    {id = 1, name = "Estonia", x = 0.55, y = 0.18, file = "gdi01", region = "baltic"},
    {id = 2, name = "Latvia", x = 0.52, y = 0.22, file = "gdi02", region = "baltic", requires = {1}},
    {id = 3, name = "Belarus", x = 0.58, y = 0.28, file = "gdi03", region = "eastern_europe", requires = {2}},
    {id = 4, name = "Poland", x = 0.48, y = 0.25, file = "gdi04", region = "eastern_europe", requires = {3}, branch = "A"},
    {id = 5, name = "Ukraine", x = 0.62, y = 0.32, file = "gdi05", region = "eastern_europe", requires = {3}, branch = "B"},
    {id = 6, name = "Germany", x = 0.42, y = 0.28, file = "gdi06", region = "western_europe", requires = {4, 5}},
    {id = 7, name = "Czech Republic", x = 0.47, y = 0.32, file = "gdi07", region = "western_europe", requires = {6}},
    {id = 8, name = "Austria", x = 0.45, y = 0.38, file = "gdi08", region = "western_europe", requires = {7}, branch = "A"},
    {id = 9, name = "Hungary", x = 0.52, y = 0.38, file = "gdi09", region = "balkans", requires = {7}, branch = "B"},
    {id = 10, name = "Slovenia", x = 0.44, y = 0.42, file = "gdi10", region = "balkans", requires = {8, 9}},
    {id = 11, name = "Croatia", x = 0.46, y = 0.46, file = "gdi11", region = "balkans", requires = {10}},
    {id = 12, name = "Bosnia", x = 0.48, y = 0.50, file = "gdi12", region = "balkans", requires = {11}},
    {id = 13, name = "Serbia", x = 0.52, y = 0.48, file = "gdi13", region = "balkans", requires = {12}},
    {id = 14, name = "Albania", x = 0.50, y = 0.54, file = "gdi14", region = "balkans", requires = {13}},
    {id = 15, name = "Sarajevo", x = 0.49, y = 0.52, file = "gdi15", region = "balkans", requires = {14}, final = true}
}

CampaignMap.NOD_MISSIONS = {
    {id = 1, name = "Libya", x = 0.45, y = 0.58, file = "nod01", region = "north_africa"},
    {id = 2, name = "Egypt", x = 0.55, y = 0.60, file = "nod02", region = "north_africa", requires = {1}},
    {id = 3, name = "Sudan", x = 0.58, y = 0.68, file = "nod03", region = "north_africa", requires = {2}},
    {id = 4, name = "Chad", x = 0.48, y = 0.70, file = "nod04", region = "central_africa", requires = {3}, branch = "A"},
    {id = 5, name = "Kenya", x = 0.62, y = 0.75, file = "nod05", region = "east_africa", requires = {3}, branch = "B"},
    {id = 6, name = "Nigeria", x = 0.40, y = 0.72, file = "nod06", region = "west_africa", requires = {4, 5}},
    {id = 7, name = "Cameroon", x = 0.45, y = 0.76, file = "nod07", region = "central_africa", requires = {6}},
    {id = 8, name = "Zaire", x = 0.52, y = 0.80, file = "nod08", region = "central_africa", requires = {7}},
    {id = 9, name = "Gabon", x = 0.42, y = 0.78, file = "nod09", region = "central_africa", requires = {7}, branch = "A"},
    {id = 10, name = "Congo", x = 0.48, y = 0.82, file = "nod10", region = "central_africa", requires = {8, 9}},
    {id = 11, name = "Tanzania", x = 0.60, y = 0.82, file = "nod11", region = "east_africa", requires = {10}},
    {id = 12, name = "Mozambique", x = 0.62, y = 0.88, file = "nod12", region = "south_africa", requires = {11}},
    {id = 13, name = "South Africa", x = 0.55, y = 0.92, file = "nod13", region = "south_africa", requires = {12}, final = true}
}

-- Covert Operations expansion missions (standalone, no prerequisites)
-- Original expansion had 7 GDI missions and 8 NOD missions
CampaignMap.COVERT_OPS_GDI = {
    {id = 1, name = "Blackout", file = "scg20ea", region = "covert", standalone = true},
    {id = 2, name = "Hell's Fury", file = "scg21ea", region = "covert", standalone = true},
    {id = 3, name = "Infiltrated!", file = "scg22ea", region = "covert", standalone = true},
    {id = 4, name = "Elemental Imperative", file = "scg23ea", region = "covert", standalone = true},
    {id = 5, name = "Ground Zero", file = "scg24ea", region = "covert", standalone = true},
    {id = 6, name = "Twist of Fate", file = "scg25ea", region = "covert", standalone = true},
    {id = 7, name = "Blindsided", file = "scg26ea", region = "covert", standalone = true}
}

CampaignMap.COVERT_OPS_NOD = {
    {id = 1, name = "Bad Neighborhood", file = "scb20ea", region = "covert", standalone = true},
    {id = 2, name = "Deceit", file = "scb21ea", region = "covert", standalone = true},
    {id = 3, name = "Eviction Notice", file = "scb22ea", region = "covert", standalone = true},
    {id = 4, name = "The Tiberium Strain", file = "scb23ea", region = "covert", standalone = true},
    {id = 5, name = "Cloak and Dagger", file = "scb24ea", region = "covert", standalone = true},
    {id = 6, name = "Hostile Takeover", file = "scb25ea", region = "covert", standalone = true},
    {id = 7, name = "Under Siege: C&C", file = "scb26ea", region = "covert", standalone = true},
    {id = 8, name = "No Mercy", file = "scb27ea", region = "covert", standalone = true}
}

-- Region colors for map rendering
CampaignMap.REGION_COLORS = {
    baltic = {0.4, 0.5, 0.3},
    eastern_europe = {0.35, 0.45, 0.3},
    western_europe = {0.3, 0.4, 0.25},
    balkans = {0.4, 0.35, 0.25},
    north_africa = {0.6, 0.5, 0.3},
    central_africa = {0.5, 0.55, 0.3},
    east_africa = {0.45, 0.5, 0.25},
    west_africa = {0.55, 0.5, 0.35},
    south_africa = {0.5, 0.45, 0.25}
}

function CampaignMap.new(faction)
    local self = setmetatable({}, CampaignMap)

    self.faction = faction or "gdi"
    self.missions = self.faction == "gdi" and CampaignMap.GDI_MISSIONS or CampaignMap.NOD_MISSIONS

    -- Completed missions tracking (would be loaded from save)
    self.completed = {}
    self.selected_mission = 1
    self.hovered_mission = nil

    -- Animation state
    self.time = 0
    self.camera_x = 0.5
    self.camera_y = 0.5
    self.camera_zoom = 1.0
    self.target_camera_x = 0.5
    self.target_camera_y = 0.5

    -- Tiberium spread animation
    self.tiberium_nodes = {}
    self:generate_tiberium_spread()

    -- Scan line effect
    self.scan_line_y = 0

    -- Callbacks
    self.on_mission_select = nil
    self.on_back = nil

    return self
end

-- Generate tiberium spread visualization on map
function CampaignMap:generate_tiberium_spread()
    for i = 1, 50 do
        table.insert(self.tiberium_nodes, {
            x = math.random() * 0.6 + 0.2,
            y = math.random() * 0.8 + 0.1,
            size = math.random() * 15 + 5,
            pulse_offset = math.random() * math.pi * 2,
            growth_rate = math.random() * 0.5 + 0.5
        })
    end
end

-- Check if a mission is available (all prerequisites met)
function CampaignMap:is_mission_available(mission)
    if not mission.requires then
        return true  -- First mission always available
    end

    for _, req_id in ipairs(mission.requires) do
        if not self.completed[req_id] then
            return false
        end
    end

    return true
end

-- Get available missions (for selection)
function CampaignMap:get_available_missions()
    local available = {}
    for _, mission in ipairs(self.missions) do
        if self:is_mission_available(mission) and not self.completed[mission.id] then
            table.insert(available, mission)
        end
    end
    return available
end

-- Select next available mission
function CampaignMap:select_next()
    local available = self:get_available_missions()
    if #available == 0 then return end

    local current_idx = 1
    for i, m in ipairs(available) do
        if m.id == self.selected_mission then
            current_idx = i
            break
        end
    end

    current_idx = current_idx + 1
    if current_idx > #available then
        current_idx = 1
    end

    self.selected_mission = available[current_idx].id
    self:focus_on_mission(self.selected_mission)
    Events.emit("PLAY_SOUND", "button1")
end

-- Select previous available mission
function CampaignMap:select_prev()
    local available = self:get_available_missions()
    if #available == 0 then return end

    local current_idx = 1
    for i, m in ipairs(available) do
        if m.id == self.selected_mission then
            current_idx = i
            break
        end
    end

    current_idx = current_idx - 1
    if current_idx < 1 then
        current_idx = #available
    end

    self.selected_mission = available[current_idx].id
    self:focus_on_mission(self.selected_mission)
    Events.emit("PLAY_SOUND", "button1")
end

-- Focus camera on a mission
function CampaignMap:focus_on_mission(mission_id)
    for _, mission in ipairs(self.missions) do
        if mission.id == mission_id then
            self.target_camera_x = mission.x
            self.target_camera_y = mission.y
            break
        end
    end
end

-- Mark mission as completed
function CampaignMap:complete_mission(mission_id, success)
    if success then
        self.completed[mission_id] = true
    end
    -- Find next available mission
    local available = self:get_available_missions()
    if #available > 0 then
        self.selected_mission = available[1].id
        self:focus_on_mission(self.selected_mission)
    end
end

-- Update
function CampaignMap:update(dt)
    self.time = self.time + dt

    -- Smooth camera movement
    self.camera_x = self.camera_x + (self.target_camera_x - self.camera_x) * dt * 3
    self.camera_y = self.camera_y + (self.target_camera_y - self.camera_y) * dt * 3

    -- Scan line effect
    self.scan_line_y = (self.scan_line_y + dt * 50) % love.graphics.getHeight()
end

-- Handle input
function CampaignMap:keypressed(key)
    if key == "left" or key == "up" then
        self:select_prev()
    elseif key == "right" or key == "down" then
        self:select_next()
    elseif key == "return" or key == "space" then
        self:confirm_selection()
    elseif key == "escape" then
        if self.on_back then
            self.on_back()
        end
    end
end

-- Confirm mission selection
function CampaignMap:confirm_selection()
    for _, mission in ipairs(self.missions) do
        if mission.id == self.selected_mission and self:is_mission_available(mission) then
            Events.emit("PLAY_SOUND", "button2")
            if self.on_mission_select then
                self.on_mission_select(mission.file, mission)
            end
            return
        end
    end
end

-- Handle mouse
function CampaignMap:mousepressed(x, y, button)
    if button == 1 then
        -- Check if clicking on a mission node
        local w, h = love.graphics.getDimensions()

        for _, mission in ipairs(self.missions) do
            local mx = mission.x * w
            local my = mission.y * h
            local dist = math.sqrt((x - mx)^2 + (y - my)^2)

            if dist < 20 and self:is_mission_available(mission) then
                self.selected_mission = mission.id
                self:focus_on_mission(mission.id)
                self:confirm_selection()
                return
            end
        end
    end
end

function CampaignMap:mousemoved(x, y)
    local w, h = love.graphics.getDimensions()
    self.hovered_mission = nil

    for _, mission in ipairs(self.missions) do
        local mx = mission.x * w
        local my = mission.y * h
        local dist = math.sqrt((x - mx)^2 + (y - my)^2)

        if dist < 20 then
            self.hovered_mission = mission.id
            break
        end
    end
end

-- Draw the campaign map
function CampaignMap:draw()
    local w, h = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(0.02, 0.02, 0.05, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw world map outline
    self:draw_world_map(w, h)

    -- Draw tiberium spread
    self:draw_tiberium_spread(w, h)

    -- Draw connection lines between missions
    self:draw_mission_connections(w, h)

    -- Draw mission nodes
    self:draw_mission_nodes(w, h)

    -- Draw scan line effect
    self:draw_scan_lines(w, h)

    -- Draw UI overlay
    self:draw_ui_overlay(w, h)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw simplified world map
function CampaignMap:draw_world_map(w, h)
    -- Faction-specific coloring
    local base_color = self.faction == "gdi" and {0.15, 0.2, 0.15} or {0.2, 0.12, 0.1}

    -- Draw grid
    love.graphics.setColor(base_color[1] * 0.5, base_color[2] * 0.5, base_color[3] * 0.5, 0.3)
    local grid_size = 40
    for x = 0, w, grid_size do
        love.graphics.line(x, 0, x, h)
    end
    for y = 0, h, grid_size do
        love.graphics.line(0, y, w, y)
    end

    -- Draw continental shapes (simplified)
    love.graphics.setColor(base_color[1], base_color[2], base_color[3], 0.6)

    -- Europe outline
    local europe = {
        {0.35, 0.15}, {0.65, 0.15}, {0.70, 0.25}, {0.68, 0.35},
        {0.60, 0.45}, {0.55, 0.55}, {0.45, 0.55}, {0.38, 0.45},
        {0.32, 0.35}, {0.30, 0.25}, {0.35, 0.15}
    }

    local points = {}
    for _, p in ipairs(europe) do
        table.insert(points, p[1] * w)
        table.insert(points, p[2] * h)
    end
    if #points >= 6 then
        love.graphics.polygon("fill", points)
    end

    -- Africa outline
    love.graphics.setColor(base_color[1] * 1.2, base_color[2] * 1.1, base_color[3], 0.5)
    local africa = {
        {0.35, 0.55}, {0.55, 0.55}, {0.65, 0.60}, {0.68, 0.75},
        {0.60, 0.95}, {0.45, 0.95}, {0.35, 0.80}, {0.32, 0.65},
        {0.35, 0.55}
    }

    points = {}
    for _, p in ipairs(africa) do
        table.insert(points, p[1] * w)
        table.insert(points, p[2] * h)
    end
    if #points >= 6 then
        love.graphics.polygon("fill", points)
    end

    -- Draw coastlines
    love.graphics.setColor(0.3, 0.4, 0.5, 0.4)
    love.graphics.setLineWidth(2)

    points = {}
    for _, p in ipairs(europe) do
        table.insert(points, p[1] * w)
        table.insert(points, p[2] * h)
    end
    if #points >= 4 then
        love.graphics.line(points)
    end

    points = {}
    for _, p in ipairs(africa) do
        table.insert(points, p[1] * w)
        table.insert(points, p[2] * h)
    end
    if #points >= 4 then
        love.graphics.line(points)
    end

    love.graphics.setLineWidth(1)
end

-- Draw tiberium spread effect
function CampaignMap:draw_tiberium_spread(w, h)
    for _, node in ipairs(self.tiberium_nodes) do
        local pulse = 0.5 + 0.5 * math.sin(self.time * node.growth_rate + node.pulse_offset)
        local size = node.size * (0.8 + 0.4 * pulse)

        love.graphics.setColor(0.1, 0.4 * pulse, 0.15, 0.3 * pulse)
        love.graphics.circle("fill", node.x * w, node.y * h, size)

        love.graphics.setColor(0.2, 0.6 * pulse, 0.2, 0.5 * pulse)
        love.graphics.circle("fill", node.x * w, node.y * h, size * 0.5)
    end
end

-- Draw connection lines between missions
function CampaignMap:draw_mission_connections(w, h)
    for _, mission in ipairs(self.missions) do
        if mission.requires then
            for _, req_id in ipairs(mission.requires) do
                -- Find required mission
                for _, req_mission in ipairs(self.missions) do
                    if req_mission.id == req_id then
                        local x1, y1 = req_mission.x * w, req_mission.y * h
                        local x2, y2 = mission.x * w, mission.y * h

                        -- Color based on completion status
                        if self.completed[req_id] then
                            if self:is_mission_available(mission) then
                                -- Available path - bright
                                love.graphics.setColor(0.4, 0.8, 0.4, 0.8)
                            else
                                -- Completed connection
                                love.graphics.setColor(0.3, 0.6, 0.3, 0.6)
                            end
                        else
                            -- Locked path - dim
                            love.graphics.setColor(0.2, 0.2, 0.2, 0.4)
                        end

                        love.graphics.setLineWidth(2)
                        love.graphics.line(x1, y1, x2, y2)
                        love.graphics.setLineWidth(1)

                        break
                    end
                end
            end
        end
    end
end

-- Draw mission nodes on map
function CampaignMap:draw_mission_nodes(w, h)
    local faction_color = self.faction == "gdi" and {0.9, 0.7, 0.2} or {0.9, 0.2, 0.2}

    for _, mission in ipairs(self.missions) do
        local x, y = mission.x * w, mission.y * h
        local is_available = self:is_mission_available(mission)
        local is_completed = self.completed[mission.id]
        local is_selected = mission.id == self.selected_mission
        local is_hovered = mission.id == self.hovered_mission

        -- Node size
        local base_size = 12
        local size = base_size

        if is_selected then
            size = base_size + 4 + 2 * math.sin(self.time * 4)
        elseif is_hovered then
            size = base_size + 2
        end

        -- Draw glow for available/selected missions
        if is_available and not is_completed then
            local glow_alpha = 0.3 + 0.2 * math.sin(self.time * 3)
            love.graphics.setColor(faction_color[1], faction_color[2], faction_color[3], glow_alpha)
            love.graphics.circle("fill", x, y, size + 8)
        end

        -- Node background
        if is_completed then
            love.graphics.setColor(0.3, 0.5, 0.3, 1)
        elseif is_available then
            love.graphics.setColor(faction_color[1] * 0.7, faction_color[2] * 0.7, faction_color[3] * 0.7, 1)
        else
            love.graphics.setColor(0.15, 0.15, 0.15, 0.8)
        end
        love.graphics.circle("fill", x, y, size)

        -- Node border
        if is_selected then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(3)
        elseif is_available then
            love.graphics.setColor(faction_color[1], faction_color[2], faction_color[3], 1)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.3, 0.3, 0.3, 0.6)
            love.graphics.setLineWidth(1)
        end
        love.graphics.circle("line", x, y, size)
        love.graphics.setLineWidth(1)

        -- Mission number
        love.graphics.setColor(1, 1, 1, is_available and 1 or 0.4)
        local num_str = tostring(mission.id)
        local font = love.graphics.getFont()
        local text_w = font:getWidth(num_str)
        love.graphics.print(num_str, x - text_w/2, y - font:getHeight()/2)

        -- Completion checkmark
        if is_completed then
            love.graphics.setColor(0.2, 0.8, 0.2, 1)
            love.graphics.circle("fill", x + size, y - size, 6)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("✓", x + size - 4, y - size - 6)
        end

        -- Final mission star
        if mission.final then
            love.graphics.setColor(1, 0.8, 0, 0.8 + 0.2 * math.sin(self.time * 2))
            self:draw_star(x, y - size - 10, 6)
        end

        -- Mission name label (for selected/hovered)
        if is_selected or is_hovered then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.printf(mission.name, x - 60, y + size + 5, 120, "center")
        end
    end
end

-- Draw a star shape
function CampaignMap:draw_star(x, y, size)
    local points = {}
    for i = 0, 9 do
        local angle = (i / 10) * math.pi * 2 - math.pi/2
        local r = (i % 2 == 0) and size or size * 0.4
        table.insert(points, x + math.cos(angle) * r)
        table.insert(points, y + math.sin(angle) * r)
    end
    love.graphics.polygon("fill", points)
end

-- Draw scan line effect
function CampaignMap:draw_scan_lines(w, h)
    -- Horizontal scan lines
    love.graphics.setColor(0, 0.3, 0, 0.03)
    for y = 0, h, 4 do
        love.graphics.line(0, y, w, y)
    end

    -- Moving scan bar
    love.graphics.setColor(0.2, 0.5, 0.2, 0.1)
    love.graphics.rectangle("fill", 0, self.scan_line_y, w, 3)
    love.graphics.setColor(0.4, 0.8, 0.4, 0.2)
    love.graphics.rectangle("fill", 0, self.scan_line_y + 1, w, 1)
end

-- Draw UI overlay
function CampaignMap:draw_ui_overlay(w, h)
    local faction_color = self.faction == "gdi" and {0.9, 0.7, 0.2} or {0.9, 0.2, 0.2}
    local faction_name = self.faction == "gdi" and "GLOBAL DEFENSE INITIATIVE" or "BROTHERHOOD OF NOD"

    -- Top bar
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, 50)
    love.graphics.setColor(faction_color[1] * 0.5, faction_color[2] * 0.5, faction_color[3] * 0.5, 0.8)
    love.graphics.rectangle("fill", 0, 48, w, 2)

    -- Faction title
    love.graphics.setColor(faction_color[1], faction_color[2], faction_color[3], 1)
    love.graphics.printf(faction_name, 0, 10, w, "center")
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("THEATER OF OPERATIONS", 0, 28, w, "center")

    -- Bottom info panel
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, h - 100, w, 100)
    love.graphics.setColor(faction_color[1] * 0.5, faction_color[2] * 0.5, faction_color[3] * 0.5, 0.8)
    love.graphics.rectangle("fill", 0, h - 100, w, 2)

    -- Selected mission info
    local selected = nil
    for _, mission in ipairs(self.missions) do
        if mission.id == self.selected_mission then
            selected = mission
            break
        end
    end

    if selected then
        love.graphics.setColor(faction_color[1], faction_color[2], faction_color[3], 1)
        love.graphics.printf("MISSION " .. selected.id .. ": " .. string.upper(selected.name), 0, h - 90, w, "center")

        local status = "LOCKED"
        local status_color = {0.5, 0.5, 0.5}
        if self.completed[selected.id] then
            status = "COMPLETED"
            status_color = {0.3, 0.7, 0.3}
        elseif self:is_mission_available(selected) then
            status = "AVAILABLE"
            status_color = {0.9, 0.9, 0.2}
        end

        love.graphics.setColor(status_color[1], status_color[2], status_color[3], 1)
        love.graphics.printf("STATUS: " .. status, 0, h - 70, w, "center")

        -- Branch indicator
        if selected.branch then
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            love.graphics.printf("ROUTE " .. selected.branch, 0, h - 55, w, "center")
        end
    end

    -- Instructions
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Arrow Keys: Select Mission | ENTER: Start Mission | ESC: Back", 0, h - 25, w, "center")

    -- Progress indicator
    local completed_count = 0
    for _ in pairs(self.completed) do
        completed_count = completed_count + 1
    end
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.printf(string.format("Progress: %d / %d missions", completed_count, #self.missions),
        w - 200, h - 90, 180, "right")
end

return CampaignMap
