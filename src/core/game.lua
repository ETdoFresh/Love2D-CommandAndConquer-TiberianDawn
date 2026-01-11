--[[
    Game - Main game state machine and controller
    Manages game states, updates, and rendering
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")
local ECS = require("src.ecs")
local Map = require("src.map")
local Systems = require("src.systems")
local Sidebar = require("src.ui.sidebar")
local Serialize = require("src.util.serialize")

local Game = {}
Game.__index = Game

-- Game states
Game.STATE = {
    NONE = "none",
    LOADING = "loading",
    MENU = "menu",
    CAMPAIGN_SELECT = "campaign_select",
    SKIRMISH_SETUP = "skirmish_setup",
    MULTIPLAYER_LOBBY = "multiplayer_lobby",
    PLAYING = "playing",
    PAUSED = "paused",
    EDITOR = "editor",
    OPTIONS = "options",
    SCENARIO_LOADING = "scenario_loading"
}

-- Game modes
Game.MODE = {
    NONE = "none",
    CAMPAIGN = "campaign",
    SKIRMISH = "skirmish",
    MULTIPLAYER = "multiplayer",
    EDITOR = "editor"
}

function Game.new()
    local self = setmetatable({}, Game)

    -- Current state
    self.state = Game.STATE.NONE
    self.mode = Game.MODE.NONE

    -- ECS world
    self.world = nil

    -- Map
    self.grid = nil
    self.theater = nil

    -- Core systems
    self.render_system = nil
    self.selection_system = nil
    self.movement_system = nil

    -- Phase 2 systems (Combat & AI)
    self.combat_system = nil
    self.ai_system = nil

    -- Phase 3 systems (Economy)
    self.production_system = nil
    self.harvest_system = nil
    self.power_system = nil

    -- Phase 6 systems (Polish)
    self.fog_system = nil
    self.cloak_system = nil
    self.audio_system = nil
    self.special_weapons = nil

    -- UI elements
    self.sidebar = nil
    self.show_sidebar = true

    -- Timing
    self.tick_accumulator = 0
    self.tick_count = 0
    self.paused = false
    self.game_speed = Constants.GAME_SPEED.NORMAL

    -- Graphics mode
    self.use_hd = false
    self.use_classic_audio = false

    -- Player info
    self.player_house = Constants.HOUSE.GOOD
    self.player_credits = 0

    -- Fog of war
    self.fog_enabled = true
    self.shroud_enabled = true

    -- Campaign/Scenario
    self.current_scenario = nil
    self.scenario_loader = nil

    -- Menu state
    self.menu_selection = 1
    self.menu_items = {"New Campaign", "Skirmish", "Multiplayer", "Map Editor", "Options", "Exit"}

    -- Controller/gamepad state
    self.gamepad = nil
    self.gamepad_cursor_x = 400
    self.gamepad_cursor_y = 300
    self.gamepad_cursor_speed = 300
    self.gamepad_deadzone = 0.2
    self.use_gamepad_cursor = false

    -- Trigger system (for scenarios)
    self.trigger_system = nil

    return self
end

-- Initialize game
function Game:init()
    self.state = Game.STATE.LOADING

    -- Create ECS world
    self.world = ECS.World.new()

    -- Create map
    self.grid = Map.Grid.new()
    self.theater = Map.Theater.new("TEMPERATE")
    self.theater:load()

    -- Create and add core systems (Phase 1)
    self.render_system = Systems.RenderSystem.new()
    self.render_system:set_priority(100)  -- Render last
    self.world:add_system(self.render_system)

    self.selection_system = Systems.SelectionSystem.new()
    self.selection_system:set_priority(10)
    self.selection_system.player_house = self.player_house
    self.world:add_system(self.selection_system)

    self.movement_system = Systems.MovementSystem.new(self.grid)
    self.movement_system:set_priority(20)
    self.world:add_system(self.movement_system)

    -- Create Phase 2 systems (Combat & AI)
    self.combat_system = Systems.CombatSystem.new()
    self.combat_system:set_priority(30)
    self.world:add_system(self.combat_system)

    self.ai_system = Systems.AISystem.new()
    self.ai_system:set_priority(25)
    self.world:add_system(self.ai_system)

    -- Create Phase 3 systems (Economy)
    self.production_system = Systems.ProductionSystem.new()
    self.production_system:set_priority(40)
    self.world:add_system(self.production_system)

    self.harvest_system = Systems.HarvestSystem.new(self.grid)
    self.harvest_system:set_priority(45)
    self.world:add_system(self.harvest_system)

    self.power_system = Systems.PowerSystem.new()
    self.power_system:set_priority(50)
    self.world:add_system(self.power_system)

    -- Create Phase 6 systems (Polish)
    self.fog_system = Systems.FogSystem.new(self.grid)
    self.fog_system:set_priority(90)
    self.fog_system:set_player_house(self.player_house)
    self.fog_system:set_fog_enabled(self.fog_enabled)
    self.fog_system:set_shroud_enabled(self.shroud_enabled)
    self.world:add_system(self.fog_system)

    self.cloak_system = Systems.CloakSystem.new()
    self.cloak_system:set_priority(55)
    self.world:add_system(self.cloak_system)

    self.audio_system = Systems.AudioSystem.new()
    self.audio_system:set_priority(95)
    self.world:add_system(self.audio_system)

    -- Create sidebar UI
    self.sidebar = Sidebar.new()
    self.sidebar:set_house(self.player_house)

    -- Create scenario loader
    local ScenarioLoader = require("src.scenario.loader")
    self.scenario_loader = ScenarioLoader.new(self.world, self.grid, self.production_system)

    -- Create trigger system
    local TriggerSystem = require("src.scenario.trigger")
    self.trigger_system = TriggerSystem.new(self.world, self)

    -- Create special weapons system
    self.special_weapons = Systems.SpecialWeapons.new(self.world, self.combat_system)

    -- Initialize systems that need world reference
    self:init_systems()

    self.state = Game.STATE.MENU
end

-- Initialize systems after world is set up
function Game:init_systems()
    -- Set world references for systems that need it
    if self.combat_system then
        self.combat_system.world = self.world
        self.combat_system:init()
    end

    if self.ai_system then
        self.ai_system.world = self.world
        self.ai_system:init()
    end

    if self.production_system then
        self.production_system.world = self.world
        self.production_system:init()
    end

    if self.harvest_system then
        self.harvest_system.world = self.world
        self.harvest_system:init()
    end

    if self.power_system then
        self.power_system.world = self.world
        self.power_system:init()
    end

    if self.fog_system then
        self.fog_system.world = self.world
    end

    if self.audio_system then
        self.audio_system.world = self.world
    end

    -- Initialize sidebar with system references
    if self.sidebar then
        self.sidebar:init(self.world)
    end
end

-- Start a new game
function Game:start_game()
    self.state = Game.STATE.PLAYING
    self.tick_count = 0
    self.tick_accumulator = 0

    -- Create some test entities
    self:create_test_entities()

    Events.emit(Events.EVENTS.GAME_START)
end

-- Create test entities for development
function Game:create_test_entities()
    local Component = ECS.Component

    -- Create a few test units
    for i = 1, 5 do
        local entity = self.world:create_entity()

        -- Position randomly on map
        local cell_x = 10 + i * 3
        local cell_y = 10

        entity:add("transform", Component.create("transform", {
            x = cell_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2,
            y = cell_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2,
            cell_x = cell_x,
            cell_y = cell_y,
            facing = 0
        }))

        entity:add("renderable", Component.create("renderable", {
            visible = true,
            layer = Constants.LAYER.GROUND,
            color = {0.2, 0.6, 0.2, 1}  -- Green for GDI
        }))

        entity:add("selectable", Component.create("selectable"))

        entity:add("mobile", Component.create("mobile", {
            speed = 20,  -- Leptons per tick
            locomotor = "track"
        }))

        entity:add("health", Component.create("health", {
            hp = 100,
            max_hp = 100
        }))

        entity:add("owner", Component.create("owner", {
            house = Constants.HOUSE.GOOD,
            color = Constants.PLAYER_COLOR.GOLD
        }))

        entity:add("vehicle", Component.create("vehicle", {
            vehicle_type = "MTANK"
        }))

        entity:add_tag("unit")
        entity:add_tag("vehicle")

        self.world:add_entity(entity)
    end

    -- Create an enemy unit
    local enemy = self.world:create_entity()
    enemy:add("transform", Component.create("transform", {
        x = 30 * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2,
        y = 15 * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2,
        cell_x = 30,
        cell_y = 15
    }))
    enemy:add("renderable", Component.create("renderable", {
        visible = true,
        layer = Constants.LAYER.GROUND,
        color = {0.8, 0.2, 0.2, 1}  -- Red for Nod
    }))
    enemy:add("selectable", Component.create("selectable"))
    enemy:add("health", Component.create("health", {
        hp = 80,
        max_hp = 100
    }))
    enemy:add("owner", Component.create("owner", {
        house = Constants.HOUSE.BAD,
        color = Constants.PLAYER_COLOR.RED
    }))
    enemy:add_tag("unit")
    self.world:add_entity(enemy)
end

-- Update game
function Game:update(dt)
    -- Always update gamepad input
    self:update_gamepad(dt)

    -- Update sidebar in any playing state
    if self.state == Game.STATE.PLAYING or self.state == Game.STATE.PAUSED then
        if self.sidebar then
            self.sidebar:update(dt)
        end
    end

    if self.state ~= Game.STATE.PLAYING or self.paused then
        return
    end

    -- Apply game speed multiplier
    local adjusted_dt = dt * self.game_speed

    -- Fixed timestep for game logic
    self.tick_accumulator = self.tick_accumulator + adjusted_dt

    while self.tick_accumulator >= Constants.TICK_DURATION do
        self:tick()
        self.tick_accumulator = self.tick_accumulator - Constants.TICK_DURATION
    end

    -- Update world (systems run at frame rate for smooth rendering)
    self.world:update(adjusted_dt)

    -- Update trigger system
    if self.trigger_system then
        self.trigger_system:update(adjusted_dt)
    end

    -- Update audio system listener position based on camera
    if self.audio_system and self.render_system then
        self.audio_system:set_listener_position(
            self.render_system.camera_x + love.graphics.getWidth() / 2,
            self.render_system.camera_y + love.graphics.getHeight() / 2
        )
    end
end

-- Game logic tick (15 FPS)
function Game:tick()
    self.tick_count = self.tick_count + 1
    Events.emit(Events.EVENTS.GAME_TICK, self.tick_count)
end

-- Draw game
function Game:draw()
    if self.state == Game.STATE.PLAYING or self.state == Game.STATE.PAUSED then
        -- Draw terrain
        self:draw_terrain()

        -- Draw entities
        self.world:draw()

        -- Draw fog of war
        if self.fog_system and self.fog_enabled then
            self.fog_system:draw(self.render_system)
        end

        -- Draw projectiles
        if self.combat_system then
            love.graphics.push()
            love.graphics.scale(self.render_system.scale, self.render_system.scale)
            love.graphics.translate(-self.render_system.camera_x, -self.render_system.camera_y)
            self.combat_system:draw_projectiles(self.render_system)
            love.graphics.pop()
        end

        -- Draw selection box (UI layer)
        self.selection_system:draw_selection_box()

        -- Draw sidebar
        if self.show_sidebar and self.sidebar then
            self.sidebar:set_position(love.graphics.getWidth() - self.sidebar.width, 0, love.graphics.getHeight())
            self.sidebar:draw()
        end

        -- Draw debug info
        self:draw_debug()

        -- Draw pause overlay
        if self.state == Game.STATE.PAUSED then
            self:draw_pause_overlay()
        end
        -- Draw gamepad cursor
        self:draw_gamepad_cursor()
    elseif self.state == Game.STATE.MENU then
        self:draw_menu()
    elseif self.state == Game.STATE.OPTIONS then
        self:draw_options()
    elseif self.state == Game.STATE.CAMPAIGN_SELECT then
        self:draw_campaign_select()
    elseif self.state == Game.STATE.SKIRMISH_SETUP then
        self:draw_skirmish_setup()
    elseif self.state == Game.STATE.MULTIPLAYER_LOBBY then
        self:draw_multiplayer_lobby()
    end
end

-- Draw terrain
function Game:draw_terrain()
    love.graphics.push()
    love.graphics.scale(self.render_system.scale, self.render_system.scale)
    love.graphics.translate(-self.render_system.camera_x, -self.render_system.camera_y)

    -- Draw visible cells
    local start_x = self.render_system.view_x
    local start_y = self.render_system.view_y
    local end_x = start_x + self.render_system.view_width
    local end_y = start_y + self.render_system.view_height

    for y = start_y, end_y do
        for x = start_x, end_x do
            local cell = self.grid:get_cell(x, y)
            if cell then
                local px = x * Constants.CELL_PIXEL_W
                local py = y * Constants.CELL_PIXEL_H

                -- Draw terrain tile
                local tile = self.theater:get_tile(cell.template_type, cell.template_icon)
                if tile then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(tile, px, py)
                end

                -- Draw overlay (tiberium, etc.)
                if cell.overlay >= 0 then
                    local overlay = self.theater:get_overlay(cell.overlay)
                    if overlay then
                        love.graphics.setColor(1, 1, 1, 0.7)
                        love.graphics.draw(overlay, px, py)
                    end
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Draw main menu
function Game:draw_menu()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Dark background with gradient effect
    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Decorative border
    love.graphics.setColor(0.3, 0.25, 0.1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 20, 20, w - 40, h - 40)

    -- Title
    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("COMMAND & CONQUER",
        0, 60, w, "center")

    love.graphics.setColor(0.8, 0.6, 0, 1)
    love.graphics.printf("TIBERIAN DAWN",
        0, 90, w, "center")

    -- Menu items
    local start_y = 180
    local item_height = 35

    for i, item in ipairs(self.menu_items) do
        local y = start_y + (i - 1) * item_height

        if i == self.menu_selection then
            -- Selected item
            love.graphics.setColor(0.3, 0.25, 0.1, 0.8)
            love.graphics.rectangle("fill", w/2 - 100, y - 5, 200, item_height - 5)
            love.graphics.setColor(1, 0.9, 0.3, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
        end

        love.graphics.printf(item, 0, y, w, "center")
    end

    -- Instructions
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.printf("Use UP/DOWN to navigate, ENTER to select",
        0, h - 70, w, "center")

    -- Version info
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.printf("Love2D Port - All Phases Integrated",
        0, h - 40, w, "center")
end

-- Draw pause overlay
function Game:draw_pause_overlay()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Pause text
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.printf("PAUSED",
        0, h/2 - 30, w, "center")

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("Press ESC to resume",
        0, h/2 + 10, w, "center")
end

-- Draw options menu
function Game:draw_options()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("OPTIONS", 0, 50, w, "center")

    local options = {
        {label = "Graphics Mode", value = self.use_hd and "HD (Remastered)" or "Classic"},
        {label = "Audio Mode", value = self.use_classic_audio and "Classic" or "Remastered"},
        {label = "Fog of War", value = self.fog_enabled and "On" or "Off"},
        {label = "Shroud", value = self.shroud_enabled and "On" or "Off"},
        {label = "Game Speed", value = self:get_speed_name()}
    }

    local start_y = 120
    local item_height = 40

    for i, opt in ipairs(options) do
        local y = start_y + (i - 1) * item_height

        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.printf(opt.label .. ":", w/2 - 200, y, 180, "right")

        love.graphics.setColor(0.9, 0.9, 0.5, 1)
        love.graphics.printf(opt.value, w/2 + 20, y, 200, "left")
    end

    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press ESC to return, H for HD toggle, F for Fog toggle",
        0, h - 50, w, "center")
end

-- Draw campaign selection
function Game:draw_campaign_select()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("SELECT CAMPAIGN", 0, 50, w, "center")

    local campaigns = {
        {name = "GDI Campaign", desc = "15 missions - Defend freedom", color = {0.9, 0.8, 0.2}},
        {name = "Nod Campaign", desc = "13 missions - Brotherhood of Nod", color = {0.8, 0.2, 0.2}},
        {name = "Covert Operations", desc = "15 bonus missions", color = {0.5, 0.5, 0.8}}
    }

    local start_y = 150
    local item_height = 60

    for i, camp in ipairs(campaigns) do
        local y = start_y + (i - 1) * item_height

        love.graphics.setColor(camp.color[1], camp.color[2], camp.color[3], 1)
        love.graphics.printf(camp.name, 0, y, w, "center")

        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        love.graphics.printf(camp.desc, 0, y + 25, w, "center")
    end

    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press 1, 2, or 3 to select, ESC to return",
        0, h - 50, w, "center")
end

-- Draw skirmish setup
function Game:draw_skirmish_setup()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("SKIRMISH SETUP", 0, 50, w, "center")

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("Map: Random", w/2 - 200, 120, 180, "right")
    love.graphics.printf("Players: 2", w/2 - 200, 150, 180, "right")
    love.graphics.printf("Your Faction: GDI", w/2 - 200, 180, 180, "right")
    love.graphics.printf("AI Difficulty: Normal", w/2 - 200, 210, 180, "right")

    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press ENTER to start, ESC to return",
        0, h - 50, w, "center")
end

-- Get speed name
function Game:get_speed_name()
    if self.game_speed == Constants.GAME_SPEED.SLOWEST then return "Slowest"
    elseif self.game_speed == Constants.GAME_SPEED.SLOWER then return "Slower"
    elseif self.game_speed == Constants.GAME_SPEED.NORMAL then return "Normal"
    elseif self.game_speed == Constants.GAME_SPEED.FASTER then return "Faster"
    elseif self.game_speed == Constants.GAME_SPEED.FASTEST then return "Fastest"
    end
    return "Normal"
end

-- Draw debug info
function Game:draw_debug()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("FPS: %d | Tick: %d | Entities: %d",
        love.timer.getFPS(),
        self.tick_count,
        self.world:entity_count()
    ), 10, 10)

    love.graphics.print(string.format("Selected: %d",
        self.selection_system:get_selection_count()
    ), 10, 30)

    love.graphics.print("WASD: Pan camera | Click: Select | Right-click: Move", 10, 50)
end

-- Input handling
function Game:keypressed(key)
    if self.state == Game.STATE.MENU then
        self:handle_menu_input(key)
    elseif self.state == Game.STATE.OPTIONS then
        self:handle_options_input(key)
    elseif self.state == Game.STATE.CAMPAIGN_SELECT then
        self:handle_campaign_select_input(key)
    elseif self.state == Game.STATE.SKIRMISH_SETUP then
        self:handle_skirmish_setup_input(key)
    elseif self.state == Game.STATE.PLAYING then
        self:handle_playing_input(key)
    elseif self.state == Game.STATE.PAUSED then
        if key == "escape" then
            self.state = Game.STATE.PLAYING
        end
    end
end

-- Handle main menu input
function Game:handle_menu_input(key)
    if key == "up" then
        self.menu_selection = self.menu_selection - 1
        if self.menu_selection < 1 then
            self.menu_selection = #self.menu_items
        end
    elseif key == "down" then
        self.menu_selection = self.menu_selection + 1
        if self.menu_selection > #self.menu_items then
            self.menu_selection = 1
        end
    elseif key == "return" or key == "space" then
        self:select_menu_item()
    elseif key == "escape" then
        love.event.quit()
    end
end

-- Select menu item
function Game:select_menu_item()
    local item = self.menu_items[self.menu_selection]

    if item == "New Campaign" then
        self.state = Game.STATE.CAMPAIGN_SELECT
    elseif item == "Skirmish" then
        self.state = Game.STATE.SKIRMISH_SETUP
    elseif item == "Multiplayer" then
        -- TODO: Multiplayer lobby
        self.state = Game.STATE.MULTIPLAYER_LOBBY
    elseif item == "Map Editor" then
        self.mode = Game.MODE.EDITOR
        self:start_editor()
    elseif item == "Options" then
        self.state = Game.STATE.OPTIONS
    elseif item == "Exit" then
        love.event.quit()
    end
end

-- Handle options input
function Game:handle_options_input(key)
    if key == "escape" then
        self.state = Game.STATE.MENU
    elseif key == "h" then
        self.use_hd = not self.use_hd
        if self.render_system then
            self.render_system:set_hd_mode(self.use_hd)
        end
    elseif key == "f" then
        self.fog_enabled = not self.fog_enabled
        if self.fog_system then
            self.fog_system:set_fog_enabled(self.fog_enabled)
        end
    elseif key == "s" then
        self.shroud_enabled = not self.shroud_enabled
        if self.fog_system then
            self.fog_system:set_shroud_enabled(self.shroud_enabled)
        end
    end
end

-- Handle campaign select input
function Game:handle_campaign_select_input(key)
    if key == "escape" then
        self.state = Game.STATE.MENU
    elseif key == "1" then
        self.player_house = Constants.HOUSE.GOOD
        self.mode = Game.MODE.CAMPAIGN
        self:start_campaign("gdi")
    elseif key == "2" then
        self.player_house = Constants.HOUSE.BAD
        self.mode = Game.MODE.CAMPAIGN
        self:start_campaign("nod")
    elseif key == "3" then
        self.mode = Game.MODE.CAMPAIGN
        self:start_campaign("covert_ops")
    end
end

-- Handle skirmish setup input
function Game:handle_skirmish_setup_input(key)
    if key == "escape" then
        self.state = Game.STATE.MENU
    elseif key == "return" then
        self.mode = Game.MODE.SKIRMISH
        self:start_skirmish()
    end
end

-- Handle playing input
function Game:handle_playing_input(key)
    if key == "escape" then
        self.state = Game.STATE.PAUSED
        return
    elseif key == "h" then
        -- Toggle HD mode
        self.use_hd = not self.use_hd
        self.render_system:set_hd_mode(self.use_hd)
    elseif key == "tab" then
        -- Toggle sidebar
        self.show_sidebar = not self.show_sidebar
    elseif key == "f5" then
        -- Quick save
        self:save_game("quicksave.sav")
    elseif key == "f9" then
        -- Quick load
        self:load_game("quicksave.sav")
    end

    -- Camera controls
    local camera_speed = 200
    if key == "w" then
        self.render_system:set_camera(
            self.render_system.camera_x,
            self.render_system.camera_y - camera_speed
        )
    elseif key == "s" then
        self.render_system:set_camera(
            self.render_system.camera_x,
            self.render_system.camera_y + camera_speed
        )
    elseif key == "a" then
        self.render_system:set_camera(
            self.render_system.camera_x - camera_speed,
            self.render_system.camera_y
        )
    elseif key == "d" then
        self.render_system:set_camera(
            self.render_system.camera_x + camera_speed,
            self.render_system.camera_y
        )
    end

    -- Zoom controls
    if key == "=" or key == "+" then
        self.render_system:set_scale(math.min(4, self.render_system.scale + 0.25))
    elseif key == "-" then
        self.render_system:set_scale(math.max(0.5, self.render_system.scale - 0.25))
    end

    -- Control groups (1-9)
    local num = tonumber(key)
    if num and num >= 1 and num <= 9 then
        if love.keyboard.isDown("lctrl", "rctrl") then
            self.selection_system:assign_control_group(num)
        else
            local shift = love.keyboard.isDown("lshift", "rshift")
            self.selection_system:select_control_group(num, shift)
        end
    end
end

-- Start campaign
function Game:start_campaign(campaign_name)
    self.state = Game.STATE.SCENARIO_LOADING

    -- Load first mission of campaign
    local scenario_path = "data/scenarios/" .. campaign_name .. "01.json"

    if self.scenario_loader then
        local success, err = pcall(function()
            self.current_scenario = self.scenario_loader:load_json(scenario_path)
        end)

        if not success then
            print("Failed to load scenario: " .. tostring(err))
            -- Start with test entities instead
            self:start_game()
            return
        end
    end

    self:start_game()
end

-- Start skirmish
function Game:start_skirmish()
    self.state = Game.STATE.SCENARIO_LOADING

    -- Set up skirmish game
    if self.harvest_system then
        self.harvest_system:set_credits(self.player_house, 5000)
    end

    self:start_game()
end

-- Start editor
function Game:start_editor()
    self.state = Game.STATE.EDITOR
    -- TODO: Initialize editor mode
end

-- Gamepad handling
function Game:gamepadpressed(joystick, button)
    -- Enable gamepad cursor mode
    if not self.gamepad then
        self.gamepad = joystick
        self.use_gamepad_cursor = true
    end

    if self.state == Game.STATE.MENU then
        if button == "dpup" then
            self.menu_selection = self.menu_selection - 1
            if self.menu_selection < 1 then
                self.menu_selection = #self.menu_items
            end
        elseif button == "dpdown" then
            self.menu_selection = self.menu_selection + 1
            if self.menu_selection > #self.menu_items then
                self.menu_selection = 1
            end
        elseif button == "a" then
            self:select_menu_item()
        elseif button == "b" then
            love.event.quit()
        end
    elseif self.state == Game.STATE.OPTIONS then
        if button == "b" then
            self.state = Game.STATE.MENU
        elseif button == "x" then
            self.use_hd = not self.use_hd
            if self.render_system then
                self.render_system:set_hd_mode(self.use_hd)
            end
        end
    elseif self.state == Game.STATE.CAMPAIGN_SELECT or
           self.state == Game.STATE.SKIRMISH_SETUP or
           self.state == Game.STATE.MULTIPLAYER_LOBBY then
        if button == "b" then
            self.state = Game.STATE.MENU
        elseif button == "a" then
            if self.state == Game.STATE.SKIRMISH_SETUP then
                self.mode = Game.MODE.SKIRMISH
                self:start_skirmish()
            end
        end
    elseif self.state == Game.STATE.PLAYING then
        if button == "start" then
            self.state = Game.STATE.PAUSED
        elseif button == "a" then
            -- Primary action (select/confirm)
            self:gamepad_primary_action()
        elseif button == "x" then
            -- Secondary action (move command)
            self:gamepad_secondary_action()
        elseif button == "leftshoulder" then
            -- Zoom out
            self.render_system:set_scale(math.max(0.5, self.render_system.scale - 0.25))
        elseif button == "rightshoulder" then
            -- Zoom in
            self.render_system:set_scale(math.min(4, self.render_system.scale + 0.25))
        end
    elseif self.state == Game.STATE.PAUSED then
        if button == "start" or button == "b" then
            self.state = Game.STATE.PLAYING
        end
    end
end

function Game:gamepad_primary_action()
    if self.use_gamepad_cursor then
        -- Convert cursor position to click
        self.selection_system:on_mouse_pressed(
            self.gamepad_cursor_x, self.gamepad_cursor_y, 1, self.render_system
        )
        self.selection_system:on_mouse_released(
            self.gamepad_cursor_x, self.gamepad_cursor_y, 1, self.render_system
        )
    end
end

function Game:gamepad_secondary_action()
    if self.use_gamepad_cursor then
        self:handle_right_click(self.gamepad_cursor_x, self.gamepad_cursor_y)
    end
end

function Game:update_gamepad(dt)
    if not self.gamepad then
        -- Check for any connected gamepad
        local joysticks = love.joystick.getJoysticks()
        if #joysticks > 0 then
            self.gamepad = joysticks[1]
        else
            return
        end
    end

    if not self.gamepad:isGamepad() then
        return
    end

    -- Update gamepad cursor position
    local left_x = self.gamepad:getGamepadAxis("leftx")
    local left_y = self.gamepad:getGamepadAxis("lefty")

    -- Apply deadzone
    if math.abs(left_x) < self.gamepad_deadzone then left_x = 0 end
    if math.abs(left_y) < self.gamepad_deadzone then left_y = 0 end

    -- Move cursor
    self.gamepad_cursor_x = self.gamepad_cursor_x + left_x * self.gamepad_cursor_speed * dt
    self.gamepad_cursor_y = self.gamepad_cursor_y + left_y * self.gamepad_cursor_speed * dt

    -- Clamp to screen
    self.gamepad_cursor_x = math.max(0, math.min(love.graphics.getWidth(), self.gamepad_cursor_x))
    self.gamepad_cursor_y = math.max(0, math.min(love.graphics.getHeight(), self.gamepad_cursor_y))

    -- Camera pan with right stick
    if self.state == Game.STATE.PLAYING then
        local right_x = self.gamepad:getGamepadAxis("rightx")
        local right_y = self.gamepad:getGamepadAxis("righty")

        if math.abs(right_x) < self.gamepad_deadzone then right_x = 0 end
        if math.abs(right_y) < self.gamepad_deadzone then right_y = 0 end

        if right_x ~= 0 or right_y ~= 0 then
            local camera_speed = 200 * dt
            self.render_system:set_camera(
                self.render_system.camera_x + right_x * camera_speed,
                self.render_system.camera_y + right_y * camera_speed
            )
        end
    end
end

-- Draw gamepad cursor
function Game:draw_gamepad_cursor()
    if self.use_gamepad_cursor and self.gamepad then
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("fill", self.gamepad_cursor_x, self.gamepad_cursor_y, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("line", self.gamepad_cursor_x, self.gamepad_cursor_y, 10)
    end
end

-- Draw multiplayer lobby
function Game:draw_multiplayer_lobby()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("MULTIPLAYER LOBBY", 0, 50, w, "center")

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("Players:", w/2 - 200, 120, 200, "left")
    love.graphics.printf("1. Player 1 (Host)", w/2 - 200, 145, 400, "left")
    love.graphics.printf("2. Waiting for player...", w/2 - 200, 170, 400, "left")

    love.graphics.printf("Map: Random", w/2 - 200, 220, 200, "left")
    love.graphics.printf("Game Speed: Normal", w/2 - 200, 245, 200, "left")

    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Multiplayer requires LAN or network connection",
        0, h - 80, w, "center")
    love.graphics.printf("Press ESC to return to menu",
        0, h - 50, w, "center")
end

function Game:mousepressed(x, y, button)
    if self.state == Game.STATE.PLAYING then
        self.selection_system:on_mouse_pressed(x, y, button, self.render_system)
    end
end

function Game:mousemoved(x, y, dx, dy)
    if self.state == Game.STATE.PLAYING then
        self.selection_system:on_mouse_moved(x, y)
    end
end

function Game:mousereleased(x, y, button)
    if self.state == Game.STATE.PLAYING then
        if button == 1 then
            self.selection_system:on_mouse_released(x, y, button, self.render_system)
        elseif button == 2 then
            -- Right click: move command
            self:handle_right_click(x, y)
        end
    end
end

function Game:handle_right_click(screen_x, screen_y)
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    local world_x, world_y = self.render_system:screen_to_world(screen_x, screen_y)

    -- Convert to leptons
    local dest_x = world_x * Constants.PIXEL_LEPTON_W
    local dest_y = world_y * Constants.PIXEL_LEPTON_H

    -- Issue move command to all selected units
    for _, entity in ipairs(selected) do
        if entity:has("mobile") then
            self.movement_system:move_to(entity, dest_x, dest_y)
        end
    end

    Events.emit(Events.EVENTS.COMMAND_MOVE, selected, dest_x, dest_y)
end

function Game:wheelmoved(x, y)
    if self.state == Game.STATE.PLAYING then
        local zoom = y * 0.1
        self.render_system:set_scale(
            math.max(0.5, math.min(4, self.render_system.scale + zoom))
        )
    end
end

function Game:resize(w, h)
    if self.render_system then
        self.render_system:update_viewport()
    end
end

-- Pause/resume
function Game:pause()
    self.paused = true
    Events.emit(Events.EVENTS.GAME_PAUSE)
end

function Game:resume()
    self.paused = false
    Events.emit(Events.EVENTS.GAME_RESUME)
end

-- Save game state
function Game:save_game(filename)
    local save_data = {
        version = 1,
        tick_count = self.tick_count,
        player_house = self.player_house,
        game_speed = self.game_speed,
        use_hd = self.use_hd,
        fog_enabled = self.fog_enabled,
        shroud_enabled = self.shroud_enabled,
        mode = self.mode,
        current_scenario = self.current_scenario,

        -- Save entity data
        entities = {},

        -- Save grid state
        grid = self.grid and self.grid:serialize() or nil,

        -- Save credits
        credits = {}
    }

    -- Serialize entities
    if self.world then
        local entities = self.world:get_all_entities()
        for _, entity in ipairs(entities) do
            table.insert(save_data.entities, entity:serialize())
        end
    end

    -- Save credits for each house
    if self.harvest_system then
        for i = 0, Constants.HOUSE.COUNT - 1 do
            save_data.credits[i] = self.harvest_system:get_credits(i)
        end
    end

    -- Write to file
    local filepath = love.filesystem.getSaveDirectory() .. "/" .. filename
    local success, err = Serialize.save_to_file(filepath, save_data)

    if success then
        print("Game saved to: " .. filename)
    else
        print("Failed to save game: " .. tostring(err))
    end

    return success
end

-- Load game state
function Game:load_game(filename)
    local filepath = love.filesystem.getSaveDirectory() .. "/" .. filename
    local save_data, err = Serialize.load_from_file(filepath)

    if not save_data then
        print("Failed to load game: " .. tostring(err))
        return false
    end

    -- Restore game state
    self.tick_count = save_data.tick_count or 0
    self.player_house = save_data.player_house or Constants.HOUSE.GOOD
    self.game_speed = save_data.game_speed or Constants.GAME_SPEED.NORMAL
    self.use_hd = save_data.use_hd or false
    self.fog_enabled = save_data.fog_enabled ~= false
    self.shroud_enabled = save_data.shroud_enabled ~= false
    self.mode = save_data.mode or Game.MODE.NONE
    self.current_scenario = save_data.current_scenario

    -- Update systems with new settings
    if self.render_system then
        self.render_system:set_hd_mode(self.use_hd)
    end

    if self.fog_system then
        self.fog_system:set_fog_enabled(self.fog_enabled)
        self.fog_system:set_shroud_enabled(self.shroud_enabled)
        self.fog_system:set_player_house(self.player_house)
    end

    if self.selection_system then
        self.selection_system.player_house = self.player_house
    end

    if self.sidebar then
        self.sidebar:set_house(self.player_house)
    end

    -- Restore grid
    if save_data.grid and self.grid then
        self.grid:deserialize(save_data.grid)
    end

    -- Clear and restore entities
    if self.world then
        self.world:clear()

        for _, entity_data in ipairs(save_data.entities or {}) do
            local entity = ECS.Entity.new()
            entity:deserialize(entity_data)
            self.world:add_entity(entity)
        end
    end

    -- Restore credits
    if self.harvest_system and save_data.credits then
        for house_id, credits in pairs(save_data.credits) do
            self.harvest_system:set_credits(tonumber(house_id), credits)
        end
    end

    self.state = Game.STATE.PLAYING
    print("Game loaded from: " .. filename)
    return true
end

-- Clean up
function Game:quit()
    if self.world then
        self.world:clear()
    end
    Events.emit(Events.EVENTS.GAME_END)
end

return Game
