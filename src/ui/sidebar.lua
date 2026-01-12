--[[
    Sidebar UI - Build menu and status display
    Matches original C&C sidebar layout
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")

local Sidebar = {}
Sidebar.__index = Sidebar

-- Sidebar dimensions (classic)
Sidebar.WIDTH = 80
Sidebar.BUTTON_SIZE = 32
Sidebar.BUTTON_MARGIN = 4
Sidebar.TABS_HEIGHT = 20

-- Tabs
Sidebar.TAB = {
    BUILDINGS = 1,
    UNITS = 2,
    SPECIAL = 3  -- Special weapons tab (only shown if weapons available)
}

function Sidebar.new()
    local self = setmetatable({}, Sidebar)

    self.x = 0
    self.y = 0
    self.width = Sidebar.WIDTH
    self.height = 400

    self.active_tab = Sidebar.TAB.BUILDINGS
    self.scroll_offset = 0

    -- Available items
    self.building_items = {}
    self.unit_items = {}

    -- Currently selected item
    self.selected_item = nil

    -- Production state
    self.building_progress = 0
    self.unit_progress = 0
    self.building_ready = false
    self.unit_ready = false
    self.building_in_production = nil  -- Name of building being built
    self.unit_in_production = nil      -- Name of unit being built

    -- House info
    self.house = Constants.HOUSE.GOOD
    self.credits = 0
    self.power_produced = 0
    self.power_consumed = 0

    -- References
    self.production_system = nil
    self.harvest_system = nil
    self.power_system = nil
    self.special_weapons_system = nil

    -- Special weapons
    self.special_weapons = {}
    self.special_weapons_available = false

    return self
end

function Sidebar:init(world)
    self.world = world
    self.production_system = world:get_system("production")
    self.harvest_system = world:get_system("harvest")
    self.power_system = world:get_system("power")
    self.special_weapons_system = world:get_system("special_weapons")

    -- Subscribe to events
    Events.on(Events.EVENTS.CREDITS_CHANGED, function(house, credits)
        if house == self.house then
            self.credits = credits
        end
    end)

    Events.on(Events.EVENTS.POWER_CHANGED, function(house, produced, consumed)
        if house == self.house then
            self.power_produced = produced
            self.power_consumed = consumed
        end
    end)

    Events.on(Events.EVENTS.PRODUCTION_COMPLETE, function(factory, item)
        -- Flash completion
    end)
end

function Sidebar:set_position(x, y, height)
    self.x = x
    self.y = y
    self.height = height
end

function Sidebar:set_house(house)
    self.house = house
    self:refresh_items()
end

function Sidebar:refresh_items()
    self.building_items = {}
    self.unit_items = {}

    if not self.production_system then
        return
    end

    -- Get available buildings
    -- We need a construction yard to check
    -- For now, use hardcoded list based on house

    local house_name = self.house == Constants.HOUSE.GOOD and "GDI" or "NOD"

    -- Building items
    local buildings = {
        {name = "NUKE", icon = "Power Plant", cost = 300},
        {name = "NUK2", icon = "Advanced Power", cost = 700},
        {name = "PROC", icon = "Refinery", cost = 2000},
        {name = "SILO", icon = "Silo", cost = 150},
        {name = "HQ", icon = "Comm Center", cost = 1000},
    }

    if house_name == "GDI" then
        table.insert(buildings, {name = "PYLE", icon = "Barracks", cost = 300})
        table.insert(buildings, {name = "GTWR", icon = "Guard Tower", cost = 500})
        table.insert(buildings, {name = "ATWR", icon = "Adv Guard Tower", cost = 1000})
        table.insert(buildings, {name = "EYE", icon = "Adv Comm Center", cost = 2800})
    else
        table.insert(buildings, {name = "HAND", icon = "Hand of Nod", cost = 300})
        table.insert(buildings, {name = "GUN", icon = "Turret", cost = 600})
        table.insert(buildings, {name = "SAM", icon = "SAM Site", cost = 750})
        table.insert(buildings, {name = "OBLI", icon = "Obelisk", cost = 1500})
        table.insert(buildings, {name = "TMPL", icon = "Temple of Nod", cost = 3000})
    end

    table.insert(buildings, {name = "WEAP", icon = "Weapons Factory", cost = 2000})
    table.insert(buildings, {name = "HPAD", icon = "Helipad", cost = 1500})
    table.insert(buildings, {name = "FIX", icon = "Repair Pad", cost = 1200})

    self.building_items = buildings

    -- Unit items
    local units = {
        {name = "E1", icon = "Minigunner", cost = 100, type = "infantry"},
        {name = "E3", icon = "Rocket Soldier", cost = 300, type = "infantry"},
        {name = "E6", icon = "Engineer", cost = 500, type = "infantry"},
    }

    if house_name == "GDI" then
        table.insert(units, {name = "E2", icon = "Grenadier", cost = 160, type = "infantry"})
        table.insert(units, {name = "RMBO", icon = "Commando", cost = 1000, type = "infantry"})
        table.insert(units, {name = "JEEP", icon = "Humvee", cost = 400, type = "vehicle"})
        table.insert(units, {name = "MTNK", icon = "Medium Tank", cost = 800, type = "vehicle"})
        table.insert(units, {name = "HTNK", icon = "Mammoth Tank", cost = 1500, type = "vehicle"})
        table.insert(units, {name = "MLRS", icon = "MLRS", cost = 800, type = "vehicle"})
        table.insert(units, {name = "MSAM", icon = "Mobile SAM", cost = 750, type = "vehicle"})
        table.insert(units, {name = "ORCA", icon = "Orca", cost = 1200, type = "aircraft"})
    else
        table.insert(units, {name = "E4", icon = "Flamethrower", cost = 200, type = "infantry"})
        table.insert(units, {name = "E5", icon = "Chem Warrior", cost = 300, type = "infantry"})
        table.insert(units, {name = "BGGY", icon = "Buggy", cost = 300, type = "vehicle"})
        table.insert(units, {name = "BIKE", icon = "Recon Bike", cost = 500, type = "vehicle"})
        table.insert(units, {name = "LTNK", icon = "Light Tank", cost = 600, type = "vehicle"})
        table.insert(units, {name = "FTNK", icon = "Flame Tank", cost = 800, type = "vehicle"})
        table.insert(units, {name = "STNK", icon = "Stealth Tank", cost = 900, type = "vehicle"})
        table.insert(units, {name = "ARTY", icon = "Artillery", cost = 450, type = "vehicle"})
        table.insert(units, {name = "HELI", icon = "Apache", cost = 1200, type = "aircraft"})
    end

    -- Common units
    table.insert(units, {name = "HARV", icon = "Harvester", cost = 1400, type = "vehicle"})
    table.insert(units, {name = "MCV", icon = "MCV", cost = 5000, type = "vehicle"})
    table.insert(units, {name = "APC", icon = "APC", cost = 700, type = "vehicle"})
    table.insert(units, {name = "TRAN", icon = "Chinook", cost = 1500, type = "aircraft"})

    self.unit_items = units
end

function Sidebar:update(dt)
    -- Update credits from harvest system or game
    if self.harvest_system then
        local credits = self.harvest_system:get_credits(self.house)
        if credits then
            self.credits = credits
        end
    end

    -- Update power display
    if self.power_system then
        local produced, consumed = self.power_system:get_power(self.house)
        if produced then
            self.power_produced = produced
            self.power_consumed = consumed or 0
        end
    end

    -- Update special weapons
    if self.special_weapons_system then
        self.special_weapons = self.special_weapons_system:get_available_weapons(self.house)
        self.special_weapons_available = #self.special_weapons > 0
    end
end

function Sidebar:set_credits(credits)
    self.credits = credits
end

-- Set production state for display
function Sidebar:set_production_state(production_type, item_name, progress)
    if production_type == "building" then
        self.building_in_production = item_name
        self.building_progress = progress or 0
        self.building_ready = progress >= 100
    else
        self.unit_in_production = item_name
        self.unit_progress = progress or 0
        self.unit_ready = progress >= 100
    end
end

-- Clear production state
function Sidebar:clear_production_state(production_type)
    if production_type == "building" then
        self.building_in_production = nil
        self.building_progress = 0
        self.building_ready = false
    else
        self.unit_in_production = nil
        self.unit_progress = 0
        self.unit_ready = false
    end
end

function Sidebar:draw()
    local x = self.x
    local y = self.y

    -- Background
    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", x, y, self.width, self.height)

    -- Border
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("line", x, y, self.width, self.height)

    -- Credits display
    love.graphics.setColor(1, 0.9, 0, 1)
    love.graphics.printf("$" .. tostring(self.credits),
        x + 4, y + 4, self.width - 8, "center")

    -- Power bar
    local power_y = y + 24
    self:draw_power_bar(x + 4, power_y, self.width - 8)

    -- Production progress display
    local prod_y = power_y + 16
    self:draw_production_status(x + 4, prod_y, self.width - 8)

    -- Tabs
    local tabs_y = prod_y + 28
    self:draw_tabs(x, tabs_y)

    -- Items
    local items_y = tabs_y + Sidebar.TABS_HEIGHT + 4
    self:draw_items(x, items_y)
end

function Sidebar:draw_production_status(x, y, width)
    -- Show what's currently being produced
    local item_name = nil
    local progress = 0

    if self.active_tab == Sidebar.TAB.BUILDINGS then
        item_name = self.building_in_production
        progress = self.building_progress
    else
        item_name = self.unit_in_production
        progress = self.unit_progress
    end

    if item_name then
        -- Draw production bar background
        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", x, y, width, 10)

        -- Progress fill
        local fill_width = (progress / 100) * width
        if progress >= 100 then
            love.graphics.setColor(0.2, 0.9, 0.2, 1)  -- Green when ready
        else
            love.graphics.setColor(0.2, 0.6, 0.9, 1)  -- Blue while building
        end
        love.graphics.rectangle("fill", x, y, fill_width, 10)

        -- Border
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("line", x, y, width, 10)

        -- Item name
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(item_name, x, y + 12, width, "center")
    else
        -- No production
        love.graphics.setColor(0.4, 0.4, 0.4, 1)
        love.graphics.printf("Ready", x, y + 4, width, "center")
    end
end

function Sidebar:draw_power_bar(x, y, width)
    local bar_height = 10

    -- Background
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", x, y, width, bar_height)

    -- Power ratio
    local ratio = 1.0
    if self.power_consumed > 0 then
        ratio = self.power_produced / self.power_consumed
    end
    local display_ratio = math.min(1.0, ratio)

    -- Power level color and status text
    local status_text = ""
    if ratio >= 1.0 then
        love.graphics.setColor(0.2, 0.8, 0.2, 1)
        status_text = "PWR OK"
    elseif ratio >= 0.5 then
        love.graphics.setColor(0.8, 0.8, 0.2, 1)
        status_text = "LOW PWR"
    else
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
        status_text = "NO PWR"
    end

    love.graphics.rectangle("fill", x, y, width * display_ratio, bar_height)

    -- Border
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.rectangle("line", x, y, width, bar_height)

    -- Power values text (produced/consumed)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    local power_text = string.format("%d/%d", self.power_produced, self.power_consumed)
    love.graphics.print(power_text, x + 2, y - 1, 0, 0.7, 0.7)

    -- Status indicator on the right
    if ratio < 1.0 then
        -- Flash warning text when power is low
        local flash = (math.floor(love.timer.getTime() * 3) % 2 == 0)
        if flash then
            love.graphics.setColor(1, 0.2, 0.2, 1)
            love.graphics.printf(status_text, x, y - 1, width - 2, "right", 0, 0.7, 0.7)
        end
    end
end

function Sidebar:draw_tabs(x, y)
    local num_tabs = self.special_weapons_available and 3 or 2
    local tab_width = self.width / num_tabs

    for i = 1, num_tabs do
        local tab_x = x + (i - 1) * tab_width

        if self.active_tab == i then
            love.graphics.setColor(0.3, 0.3, 0.4, 1)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 1)
        end

        love.graphics.rectangle("fill", tab_x, y, tab_width, Sidebar.TABS_HEIGHT)

        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("line", tab_x, y, tab_width, Sidebar.TABS_HEIGHT)

        love.graphics.setColor(1, 1, 1, 1)
        local label
        if i == 1 then
            label = "BUILD"
        elseif i == 2 then
            label = "UNITS"
        else
            label = "SPEC"
        end
        love.graphics.printf(label, tab_x, y + 4, tab_width, "center")
    end
end

function Sidebar:draw_items(x, y)
    -- Special weapons tab
    if self.active_tab == Sidebar.TAB.SPECIAL then
        self:draw_special_weapons(x, y)
        return
    end

    local items = self.active_tab == Sidebar.TAB.BUILDINGS and
                  self.building_items or self.unit_items

    local col = 0
    local row = 0
    local cols = 2
    local button_w = (self.width - Sidebar.BUTTON_MARGIN * 3) / cols
    local button_h = Sidebar.BUTTON_SIZE

    for i, item in ipairs(items) do
        local bx = x + Sidebar.BUTTON_MARGIN + col * (button_w + Sidebar.BUTTON_MARGIN)
        local by = y + row * (button_h + Sidebar.BUTTON_MARGIN) - self.scroll_offset

        -- Only draw visible buttons
        if by + button_h >= y and by < self.y + self.height then
            self:draw_button(bx, by, button_w, button_h, item)
        end

        col = col + 1
        if col >= cols then
            col = 0
            row = row + 1
        end
    end
end

-- Draw special weapons buttons
function Sidebar:draw_special_weapons(x, y)
    local button_w = self.width - Sidebar.BUTTON_MARGIN * 2
    local button_h = Sidebar.BUTTON_SIZE + 10

    for i, weapon in ipairs(self.special_weapons) do
        local by = y + (i - 1) * (button_h + Sidebar.BUTTON_MARGIN)

        -- Background
        if weapon.ready then
            -- Ready to fire - flash
            local flash = (math.floor(love.timer.getTime() * 3) % 2 == 0)
            if flash then
                love.graphics.setColor(0.3, 0.5, 0.3, 1)
            else
                love.graphics.setColor(0.4, 0.7, 0.4, 1)
            end
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 1)
        end
        love.graphics.rectangle("fill", x + Sidebar.BUTTON_MARGIN, by, button_w, button_h)

        -- Cooldown bar
        if not weapon.ready and weapon.max_cooldown > 0 then
            local cooldown_pct = weapon.cooldown / weapon.max_cooldown
            local bar_width = button_w * (1 - cooldown_pct)
            love.graphics.setColor(0.3, 0.5, 0.7, 0.7)
            love.graphics.rectangle("fill", x + Sidebar.BUTTON_MARGIN, by, bar_width, button_h)
        end

        -- Border
        if weapon.ready then
            love.graphics.setColor(0, 1, 0, 1)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.4, 0.4, 0.4, 1)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x + Sidebar.BUTTON_MARGIN, by, button_w, button_h)
        love.graphics.setLineWidth(1)

        -- Weapon name
        love.graphics.setColor(1, 1, 1, weapon.ready and 1 or 0.6)
        love.graphics.printf(weapon.name, x + Sidebar.BUTTON_MARGIN, by + 4, button_w, "center")

        -- Status
        if weapon.ready then
            love.graphics.setColor(0.2, 1, 0.2, 1)
            love.graphics.printf("READY", x + Sidebar.BUTTON_MARGIN, by + button_h - 14, button_w, "center")
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            local cooldown_sec = math.ceil(weapon.cooldown / 60)
            love.graphics.printf(cooldown_sec .. "s", x + Sidebar.BUTTON_MARGIN, by + button_h - 14, button_w, "center")
        end
    end

    -- If no weapons, show message
    if #self.special_weapons == 0 then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.printf("No special weapons\navailable", x + Sidebar.BUTTON_MARGIN, y + 20, button_w, "center")
    end
end

function Sidebar:draw_button(x, y, w, h, item)
    -- Can afford?
    local can_afford = self.credits >= item.cost

    -- Check if this item is currently being built
    local is_building = false
    local progress = 0
    local is_ready = false

    if self.active_tab == Sidebar.TAB.BUILDINGS then
        if self.building_in_production == item.name then
            is_building = true
            progress = self.building_progress
            is_ready = self.building_ready
        end
    else
        if self.unit_in_production == item.name then
            is_building = true
            progress = self.unit_progress
            is_ready = self.unit_ready
        end
    end

    -- Background
    if is_ready then
        -- Ready to place - flash green
        local flash = (math.floor(love.timer.getTime() * 4) % 2 == 0)
        if flash then
            love.graphics.setColor(0.2, 0.5, 0.2, 1)
        else
            love.graphics.setColor(0.3, 0.7, 0.3, 1)
        end
    elseif is_building then
        love.graphics.setColor(0.2, 0.3, 0.4, 1)  -- Building - blue tint
    elseif can_afford then
        love.graphics.setColor(0.25, 0.25, 0.3, 1)
    else
        love.graphics.setColor(0.2, 0.15, 0.15, 1)
    end
    love.graphics.rectangle("fill", x, y, w, h)

    -- Progress bar overlay if building
    if is_building and not is_ready then
        -- Draw progress bar across the button
        local progress_height = h * (progress / 100)
        love.graphics.setColor(0.2, 0.5, 0.8, 0.5)
        love.graphics.rectangle("fill", x, y + h - progress_height, w, progress_height)

        -- Clock/percentage overlay
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(math.floor(progress) .. "%", x, y + h/2 - 6, w, "center")
    end

    -- Border
    if self.selected_item == item.name then
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.setLineWidth(2)
    elseif is_building then
        love.graphics.setColor(0.4, 0.7, 1, 1)  -- Blue border when building
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(0.4, 0.4, 0.4, 1)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setLineWidth(1)

    -- Icon/name (don't show if building progress is displayed)
    if not is_building or is_ready then
        if can_afford then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.printf(item.name, x, y + 4, w, "center")
    else
        -- Show name at top when building
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.printf(item.name, x, y + 2, w, "center")
    end

    -- Cost (only if not building)
    if not is_building then
        love.graphics.setColor(1, 0.9, 0, can_afford and 1 or 0.5)
        love.graphics.printf("$" .. item.cost, x, y + h - 12, w, "center")
    elseif is_ready then
        -- Show "READY" when complete
        love.graphics.setColor(0.2, 1, 0.2, 1)
        love.graphics.printf("READY", x, y + h/2 - 6, w, "center")
    end
end

function Sidebar:mousepressed(mx, my, button)
    -- Check if click is on sidebar
    if mx < self.x or mx > self.x + self.width then
        return false
    end
    if my < self.y or my > self.y + self.height then
        return false
    end

    -- Check tabs
    local tabs_y = self.y + 44
    if my >= tabs_y and my < tabs_y + Sidebar.TABS_HEIGHT then
        local num_tabs = self.special_weapons_available and 3 or 2
        local tab_width = self.width / num_tabs
        local clicked_tab = math.floor((mx - self.x) / tab_width) + 1
        if clicked_tab >= 1 and clicked_tab <= num_tabs then
            self.active_tab = clicked_tab
        end
        return true
    end

    -- Check item clicks
    local items_y = tabs_y + Sidebar.TABS_HEIGHT + 4
    if my >= items_y then
        -- Special weapons tab
        if self.active_tab == Sidebar.TAB.SPECIAL then
            local button_w = self.width - Sidebar.BUTTON_MARGIN * 2
            local button_h = Sidebar.BUTTON_SIZE + 10

            for i, weapon in ipairs(self.special_weapons) do
                local by = items_y + (i - 1) * (button_h + Sidebar.BUTTON_MARGIN)

                if mx >= self.x + Sidebar.BUTTON_MARGIN and
                   mx < self.x + Sidebar.BUTTON_MARGIN + button_w and
                   my >= by and my < by + button_h then
                    -- Clicked on this weapon
                    if weapon.ready then
                        -- Start targeting mode
                        if self.special_weapons_system then
                            self.special_weapons_system:start_targeting(self.house, weapon.type)
                            if self.on_special_weapon_click then
                                self.on_special_weapon_click(weapon.type, weapon)
                            end
                        end
                    end
                    return true
                end
            end
            return true
        end

        local items = self.active_tab == Sidebar.TAB.BUILDINGS and
                      self.building_items or self.unit_items

        local col = 0
        local row = 0
        local cols = 2
        local button_w = (self.width - Sidebar.BUTTON_MARGIN * 3) / cols
        local button_h = Sidebar.BUTTON_SIZE

        for i, item in ipairs(items) do
            local bx = self.x + Sidebar.BUTTON_MARGIN + col * (button_w + Sidebar.BUTTON_MARGIN)
            local by = items_y + row * (button_h + Sidebar.BUTTON_MARGIN) - self.scroll_offset

            if mx >= bx and mx < bx + button_w and
               my >= by and my < by + button_h then
                -- Clicked on this item
                if self.credits >= item.cost then
                    -- For buildings, select for placement
                    -- For units, trigger production callback immediately
                    if self.active_tab == Sidebar.TAB.BUILDINGS then
                        self.selected_item = item.name
                    else
                        -- Units start production immediately via callback
                        if self.on_unit_click then
                            self.on_unit_click(item.name, item)
                        else
                            self.selected_item = item.name
                        end
                    end
                    return true
                end
            end

            col = col + 1
            if col >= cols then
                col = 0
                row = row + 1
            end
        end
    end

    return true
end

-- Set callback for special weapon clicks
function Sidebar:set_special_weapon_callback(callback)
    self.on_special_weapon_click = callback
end

-- Set callback for unit production
function Sidebar:set_unit_click_callback(callback)
    self.on_unit_click = callback
end

function Sidebar:wheelmoved(x, y)
    self.scroll_offset = self.scroll_offset - y * 20
    self.scroll_offset = math.max(0, self.scroll_offset)
end

function Sidebar:get_selected_item()
    return self.selected_item
end

function Sidebar:clear_selection()
    self.selected_item = nil
end

return Sidebar
