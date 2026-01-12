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
local Radar = require("src.ui.radar")
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
    BRIEFING = "briefing",
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
    self.radar = nil
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

    -- Team system (for AI teams)
    self.team_system = nil

    -- Mission result state
    self.mission_result = nil  -- "victory" or "defeat"
    self.mission_result_message = nil

    -- In-game message display
    self.current_message = nil
    self.message_timer = 0

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

    self.animation_system = Systems.AnimationSystem.new()
    self.animation_system:set_priority(85)  -- After movement, before render
    self.world:add_system(self.animation_system)

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

    -- Set callback for unit production from sidebar
    self.sidebar:set_unit_click_callback(function(unit_type, item)
        self:start_unit_production(unit_type)
    end)

    -- Create radar/minimap UI
    self.radar = Radar.new()
    self.radar:set_house(self.player_house)

    -- Create scenario loader
    local ScenarioLoader = require("src.scenario.loader")
    self.scenario_loader = ScenarioLoader.new(self.world, self.grid, self.production_system)

    -- Create trigger system
    local TriggerSystem = require("src.scenario.trigger")
    self.trigger_system = TriggerSystem.new(self.world, self)

    -- Create team system (for AI team coordination)
    local TeamSystem = require("src.scenario.team")
    self.team_system = TeamSystem.new(self.world, self.ai_system)

    -- Link trigger, team, and AI systems to scenario loader
    self.scenario_loader:set_systems(self.trigger_system, self.team_system, self.ai_system)

    -- Link trigger system to movement system for cell entry detection
    self.movement_system:set_trigger_system(self.trigger_system)

    -- Create special weapons system
    self.special_weapons = Systems.SpecialWeapons.new(self.world, self.combat_system)

    -- Initialize systems that need world reference
    self:init_systems()

    -- Register game event handlers
    self:register_events()

    self.state = Game.STATE.MENU
end

-- Register for game events
function Game:register_events()
    -- Handle mission win
    Events.on(Events.EVENTS.GAME_WIN, function(house)
        self:on_game_win(house)
    end)

    -- Handle mission lose
    Events.on(Events.EVENTS.GAME_LOSE, function(house)
        self:on_game_lose(house)
    end)

    -- Handle reinforcement requests from triggers
    Events.on("REINFORCEMENT", function(team_name, waypoint)
        self:spawn_reinforcement(team_name, waypoint)
    end)

    -- Handle in-game text messages from triggers
    Events.on("SHOW_TEXT", function(text_id)
        self:show_message(text_id)
    end)

    -- Handle CREATE_TEAM from triggers (uses existing units)
    Events.on("CREATE_TEAM", function(team_name)
        if self.team_system then
            self.team_system:create_team(team_name)
        end
    end)

    -- Handle map reveal from triggers
    Events.on("REVEAL_MAP", function(house)
        if self.fog_system and house == self.player_house then
            self.fog_system:reveal_all(house)
        end
    end)

    -- Handle reveal zone from triggers (reveal around a waypoint)
    Events.on("REVEAL_ZONE", function(house, waypoint_index)
        if self.fog_system and house == self.player_house then
            local wp = self:get_waypoint(waypoint_index)
            if wp then
                self.fog_system:reveal_area(house, wp.x, wp.y, 10)  -- 10 cell radius
            end
        end
    end)
end

-- Get waypoint from current scenario
function Game:get_waypoint(index)
    if self.scenario_loader and self.scenario_loader.scenario then
        local waypoints = self.scenario_loader.scenario.waypoints
        if waypoints and waypoints[index] then
            return waypoints[index]
        end
    end
    return nil
end

-- Called when player wins a mission
function Game:on_game_win(house)
    if self.mode == Game.MODE.CAMPAIGN then
        self.state = Game.STATE.PAUSED
        self.mission_result = "victory"
        self.mission_result_message = "Mission Accomplished"
    end
end

-- Called when player loses a mission
function Game:on_game_lose(house)
    if self.mode == Game.MODE.CAMPAIGN then
        self.state = Game.STATE.PAUSED
        self.mission_result = "defeat"
        self.mission_result_message = "Mission Failed"
    end
end

-- Spawn reinforcement team at map edge
function Game:spawn_reinforcement(team_name, waypoint)
    if not self.team_system then return end

    -- Get the team type definition
    local team_type = self.team_system.team_types[team_name]
    if not team_type then
        print("Warning: Team type not found: " .. tostring(team_name))
        return
    end

    -- Determine spawn position from waypoint
    local spawn_x, spawn_y = 0, 0
    local wp = self:get_waypoint(waypoint)
    if wp then
        spawn_x = wp.x
        spawn_y = wp.y
    else
        -- Default to map edge based on house edge setting
        local edge = team_type.edge or "North"
        if edge == "North" then
            spawn_x = (self.grid.width / 2) * Constants.LEPTON_PER_CELL
            spawn_y = 0
        elseif edge == "South" then
            spawn_x = (self.grid.width / 2) * Constants.LEPTON_PER_CELL
            spawn_y = self.grid.height * Constants.LEPTON_PER_CELL
        elseif edge == "West" then
            spawn_x = 0
            spawn_y = (self.grid.height / 2) * Constants.LEPTON_PER_CELL
        elseif edge == "East" then
            spawn_x = self.grid.width * Constants.LEPTON_PER_CELL
            spawn_y = (self.grid.height / 2) * Constants.LEPTON_PER_CELL
        end
    end

    -- Convert house string to constant
    local house = self:string_to_house(team_type.house)

    -- Create units for the team
    local spawned_entities = {}
    if self.production_system then
        local offset = 0
        for _, member in ipairs(team_type.members or {}) do
            for i = 1, (member.count or 1) do
                local entity = self.production_system:create_unit(
                    member.type,
                    house,
                    spawn_x + offset,
                    spawn_y + ((i - 1) * 128)  -- Offset each unit slightly
                )
                if entity then
                    self.world:add_entity(entity)
                    table.insert(spawned_entities, entity)
                end
                offset = offset + 128
            end
        end
    end

    -- Create the team to coordinate these units
    if #spawned_entities > 0 then
        self.team_system:create_team(team_name)
    end

    return spawned_entities
end

-- Convert house string to constant
function Game:string_to_house(house_str)
    if type(house_str) == "number" then
        return house_str
    end

    local house_map = {
        GoodGuy = Constants.HOUSE.GOOD,
        BadGuy = Constants.HOUSE.BAD,
        Neutral = Constants.HOUSE.NEUTRAL,
        Special = Constants.HOUSE.SPECIAL,
        Multi1 = Constants.HOUSE.MULTI1,
        Multi2 = Constants.HOUSE.MULTI2,
        Multi3 = Constants.HOUSE.MULTI3,
        Multi4 = Constants.HOUSE.MULTI4,
        GOOD = Constants.HOUSE.GOOD,
        BAD = Constants.HOUSE.BAD
    }

    return house_map[house_str] or Constants.HOUSE.NEUTRAL
end

-- Show in-game message
function Game:show_message(text_id)
    -- Store message for display
    self.current_message = text_id
    self.message_timer = 5.0  -- Show for 5 seconds
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

    -- Initialize radar with world and grid references
    if self.radar then
        self.radar:init(self.world, self.grid)
        -- Set click callback to move camera
        self.radar:set_click_callback(function(x, y)
            if self.render_system then
                self.render_system:set_camera(x, y)
            end
        end)
    end
end

-- Start a new game
function Game:start_game()
    self.state = Game.STATE.PLAYING
    self.tick_count = 0
    self.tick_accumulator = 0

    -- Create some test entities
    self:create_test_entities()

    -- Center camera on first player unit
    self:center_camera_on_player()

    Events.emit(Events.EVENTS.GAME_START)
end

-- Center camera on first player-owned unit
function Game:center_camera_on_player()
    if not self.render_system or not self.world then return end

    local entities = self.world:get_all_entities()
    for _, entity in ipairs(entities) do
        local owner = entity:get("owner")
        local transform = entity:get("transform")
        if owner and owner.house == self.player_house and transform then
            -- Convert lepton position to pixels
            local px = transform.x / Constants.PIXEL_LEPTON_W
            local py = transform.y / Constants.PIXEL_LEPTON_H

            -- Center camera (offset by half screen)
            local screen_w, screen_h = love.graphics.getDimensions()
            local cam_x = px - screen_w / 2
            local cam_y = py - screen_h / 2

            -- Clamp to map bounds if we have grid info
            if self.grid then
                local max_x = self.grid.width * Constants.CELL_PIXEL_W - screen_w
                local max_y = self.grid.height * Constants.CELL_PIXEL_H - screen_h
                cam_x = math.max(0, math.min(cam_x, max_x))
                cam_y = math.max(0, math.min(cam_y, max_y))
            end

            self.render_system:set_camera(cam_x, cam_y)
            return
        end
    end
end

-- Create test entities for development
function Game:create_test_entities()
    -- Set initial credits through harvest system (the source of truth)
    if self.harvest_system then
        self.harvest_system:set_credits(self.player_house, 5000)
    end
    self.player_credits = 5000  -- Also sync local copy

    -- Set camera to origin
    if self.render_system then
        self.render_system:set_camera(0, 0)
    end

    -- Create some test units to show sprite rendering
    if self.production_system and self.world then
        -- Create GDI units (player house 1)
        -- Position in leptons (256 leptons = 1 cell)
        local spawn_x = 5 * Constants.LEPTON_PER_CELL
        local spawn_y = 5 * Constants.LEPTON_PER_CELL
        local cell_spacing = 2 * Constants.LEPTON_PER_CELL  -- 2 cells apart

        -- Helper to create and add to world
        local function spawn_unit(unit_type, house, x, y)
            local e = self.production_system:create_unit(unit_type, house, x, y)
            if e then self.world:add_entity(e) end
        end

        local function spawn_building(building_type, house, cell_x, cell_y)
            local e = self.production_system:create_building(building_type, house, cell_x, cell_y)
            if e then
                self.world:add_entity(e)
                -- Mark cells as occupied
                local building_data = self.production_system.building_data[building_type]
                if building_data and self.grid then
                    local size_x = building_data.size and building_data.size[1] or 1
                    local size_y = building_data.size and building_data.size[2] or 1
                    self.grid:place_building(cell_x, cell_y, size_x, size_y, e.id, house)
                end
            end
        end

        -- Create player units (GDI = house 0)
        local player = Constants.HOUSE.GOOD
        local enemy = Constants.HOUSE.BAD

        -- Construction Yard for the player at cell (3, 3)
        spawn_building("FACT", player, 3, 3)

        -- Power Plant at cell (6, 3) (adjacent to FACT)
        spawn_building("NUKE", player, 6, 3)

        -- Barracks for infantry production at cell (8, 3) (adjacent to Power Plant)
        spawn_building("PYLE", player, 8, 3)

        -- Communications Center for radar at cell (10, 3) (adjacent to Barracks)
        spawn_building("HQ", player, 10, 3)

        -- Weapons Factory for vehicle production at cell (3, 6) (adjacent to FACT)
        spawn_building("WEAP", player, 3, 6)

        -- Refinery for credits/harvesting at cell (6, 6) (adjacent to Power Plant)
        spawn_building("PROC", player, 6, 6)

        -- Medium Tank
        spawn_unit("MTNK", player, spawn_x, spawn_y)
        -- Humvee
        spawn_unit("JEEP", player, spawn_x + cell_spacing, spawn_y)
        -- APC
        spawn_unit("APC", player, spawn_x + cell_spacing * 2, spawn_y)
        -- Harvester
        spawn_unit("HARV", player, spawn_x, spawn_y + cell_spacing)
        -- Infantry
        spawn_unit("E1", player, spawn_x + cell_spacing, spawn_y + cell_spacing)
        spawn_unit("E2", player, spawn_x + cell_spacing + 128, spawn_y + cell_spacing)

        -- Nod building at cell (15, 5)
        spawn_building("HAND", enemy, 15, 5)

        -- Create Tiberium fields
        if self.grid then
            -- Create a tiberium field near the player base
            local tib_start_x, tib_start_y = 10, 8
            for dy = 0, 4 do
                for dx = 0, 5 do
                    local cell = self.grid:get_cell(tib_start_x + dx, tib_start_y + dy)
                    if cell then
                        -- Random tiberium density (overlay 6-17)
                        cell.overlay = 6 + math.random(0, 5)
                    end
                end
            end

            -- Create another tiberium field further away
            local tib2_x, tib2_y = 20, 12
            for dy = 0, 3 do
                for dx = 0, 4 do
                    local cell = self.grid:get_cell(tib2_x + dx, tib2_y + dy)
                    if cell then
                        cell.overlay = 6 + math.random(0, 8)
                    end
                end
            end
        end
    end
end

-- Update game
function Game:update(dt)
    -- Always update gamepad input
    self:update_gamepad(dt)

    -- Update sidebar and radar in any playing state
    if self.state == Game.STATE.PLAYING or self.state == Game.STATE.PAUSED then
        -- Sync credits from harvest system (the source of truth for economy)
        if self.harvest_system then
            self.player_credits = self.harvest_system:get_credits(self.player_house)
        end

        if self.sidebar then
            self.sidebar:set_credits(self.player_credits)
            self.sidebar:update(dt)

            -- Update production progress display
            self:update_production_display()
        end

        if self.radar then
            self.radar:update(dt)
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

    -- Process building repairs
    self:process_building_repairs(adjusted_dt)

    -- Update audio system listener position based on camera
    if self.audio_system and self.render_system then
        self.audio_system:set_listener_position(
            self.render_system.camera_x + love.graphics.getWidth() / 2,
            self.render_system.camera_y + love.graphics.getHeight() / 2
        )
    end

    -- Update message timer
    if self.message_timer > 0 then
        self.message_timer = self.message_timer - dt
        if self.message_timer <= 0 then
            self.current_message = nil
        end
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
        -- Debug: Always draw a test background
        love.graphics.setColor(0.15, 0.25, 0.15, 1)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

        -- Draw terrain first (under everything)
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

        -- Draw radar (position it above the sidebar at bottom-right)
        if self.show_sidebar and self.radar then
            local radar_x = love.graphics.getWidth() - self.radar.size - 10
            local radar_y = love.graphics.getHeight() - self.radar.size - 10
            self.radar:set_position(radar_x, radar_y)

            -- Get camera and viewport info for radar display
            local cam_x, cam_y = 0, 0
            local vw, vh = love.graphics.getWidth(), love.graphics.getHeight()
            if self.render_system then
                cam_x = self.render_system.camera_x
                cam_y = self.render_system.camera_y
                -- Account for sidebar width in viewport
                if self.sidebar then
                    vw = vw - self.sidebar.width
                end
            end
            self.radar:draw(cam_x, cam_y, vw, vh)
        end

        -- Draw debug info
        self:draw_debug()

        -- Draw in-game messages
        self:draw_messages()

        -- Draw special weapon targeting cursor
        self:draw_targeting_cursor()

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
    elseif self.state == Game.STATE.BRIEFING then
        self:draw_briefing()
    elseif self.state == Game.STATE.SKIRMISH_SETUP then
        self:draw_skirmish_setup()
    elseif self.state == Game.STATE.MULTIPLAYER_LOBBY then
        self:draw_multiplayer_lobby()
    end
end

-- Draw terrain
function Game:draw_terrain()
    -- Draw a dark green background first (no transforms)
    love.graphics.setColor(0.1, 0.2, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Simple terrain draw - just colored rectangles for now
    love.graphics.push()
    love.graphics.scale(self.render_system.scale, self.render_system.scale)
    love.graphics.translate(-self.render_system.camera_x, -self.render_system.camera_y)

    -- Calculate visible cells
    local screen_w, screen_h = love.graphics.getDimensions()
    local cam_cell_x = math.floor(self.render_system.camera_x / Constants.CELL_PIXEL_W)
    local cam_cell_y = math.floor(self.render_system.camera_y / Constants.CELL_PIXEL_H)
    local cells_x = math.ceil(screen_w / Constants.CELL_PIXEL_W) + 2
    local cells_y = math.ceil(screen_h / Constants.CELL_PIXEL_H) + 2

    for y = math.max(0, cam_cell_y), math.min(self.grid.height - 1, cam_cell_y + cells_y) do
        for x = math.max(0, cam_cell_x), math.min(self.grid.width - 1, cam_cell_x + cells_x) do
            local cell = self.grid:get_cell(x, y)
            if cell then
                local px = x * Constants.CELL_PIXEL_W
                local py = y * Constants.CELL_PIXEL_H

                -- Draw terrain as colored rectangle
                local r = 0.3 + (x % 2) * 0.05
                local g = 0.5 + (y % 2) * 0.05
                love.graphics.setColor(r, g, 0.2, 1)
                love.graphics.rectangle("fill", px, py, Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)

                -- Grid outline
                love.graphics.setColor(0.2, 0.35, 0.15, 1)
                love.graphics.rectangle("line", px, py, Constants.CELL_PIXEL_W, Constants.CELL_PIXEL_H)

                -- Draw tiberium overlay
                if cell.overlay and cell.overlay >= 0 then
                    love.graphics.setColor(0.2, 0.9, 0.3, 0.8)
                    love.graphics.rectangle("fill", px + 4, py + 4, 16, 16)
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

    -- Check if mission ended - show result screen instead of pause
    if self.mission_result then
        self:draw_mission_result()
        return
    end

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

-- Draw mission result screen (victory or defeat)
function Game:draw_mission_result()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Darken background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Draw result panel
    local panel_w, panel_h = 500, 350
    local panel_x = (w - panel_w) / 2
    local panel_y = (h - panel_h) / 2

    -- Panel background
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h)

    -- Panel border
    if self.mission_result == "victory" then
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
    else
        love.graphics.setColor(0.6, 0.2, 0.2, 1)
    end
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h)

    -- Title
    local title_y = panel_y + 30
    if self.mission_result == "victory" then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.printf("MISSION ACCOMPLISHED", panel_x, title_y, panel_w, "center")
    else
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.printf("MISSION FAILED", panel_x, title_y, panel_w, "center")
    end

    -- Mission statistics
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    local stats_y = title_y + 60

    -- Calculate statistics
    local player_units = 0
    local enemy_units = 0
    local player_buildings = 0
    local enemy_buildings = 0

    if self.world then
        for _, entity in ipairs(self.world:get_all_entities()) do
            local owner = entity:get("owner")
            local unit_type = entity:get("unit_type")
            local building = entity:get("building")

            if owner then
                if owner.house == self.player_house then
                    if building then
                        player_buildings = player_buildings + 1
                    elseif unit_type then
                        player_units = player_units + 1
                    end
                else
                    if building then
                        enemy_buildings = enemy_buildings + 1
                    elseif unit_type then
                        enemy_units = enemy_units + 1
                    end
                end
            end
        end
    end

    local stats = {
        {label = "Your Units Remaining", value = player_units},
        {label = "Your Buildings Remaining", value = player_buildings},
        {label = "Enemy Units Remaining", value = enemy_units},
        {label = "Enemy Buildings Remaining", value = enemy_buildings},
        {label = "Game Time", value = string.format("%d:%02d", math.floor(self.tick_count / 15 / 60), math.floor(self.tick_count / 15) % 60)}
    }

    for i, stat in ipairs(stats) do
        local y = stats_y + (i - 1) * 28
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.printf(stat.label .. ":", panel_x + 40, y, 250, "left")
        love.graphics.setColor(1, 0.9, 0.5, 1)
        love.graphics.printf(tostring(stat.value), panel_x + 300, y, 150, "left")
    end

    -- Menu options
    local menu_y = panel_y + panel_h - 100
    local menu_items = {}

    if self.mode == Game.MODE.CAMPAIGN and self.mission_result == "victory" then
        menu_items = {"Continue Campaign", "Replay Mission", "Main Menu"}
    else
        menu_items = {"Replay Mission", "Main Menu"}
    end

    -- Initialize result_menu_index if not set
    if not self.result_menu_index then
        self.result_menu_index = 1
    end

    for i, item in ipairs(menu_items) do
        local y = menu_y + (i - 1) * 30
        if i == self.result_menu_index then
            love.graphics.setColor(1, 0.9, 0.3, 1)
            love.graphics.printf("> " .. item .. " <", panel_x, y, panel_w, "center")
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            love.graphics.printf(item, panel_x, y, panel_w, "center")
        end
    end

    -- Store menu items for input handling
    self.result_menu_items = menu_items
end

-- Handle mission result menu input
function Game:handle_result_input(key)
    if not self.mission_result or not self.result_menu_items then return false end

    if key == "up" then
        self.result_menu_index = self.result_menu_index - 1
        if self.result_menu_index < 1 then
            self.result_menu_index = #self.result_menu_items
        end
        return true
    elseif key == "down" then
        self.result_menu_index = self.result_menu_index + 1
        if self.result_menu_index > #self.result_menu_items then
            self.result_menu_index = 1
        end
        return true
    elseif key == "return" or key == "space" then
        local selected = self.result_menu_items[self.result_menu_index]
        if selected == "Continue Campaign" then
            self:advance_campaign()
        elseif selected == "Replay Mission" then
            self:replay_mission()
        elseif selected == "Main Menu" then
            self:return_to_menu()
        end
        return true
    end

    return false
end

-- Advance to next campaign mission
function Game:advance_campaign()
    -- Clear result state
    self.mission_result = nil
    self.mission_result_message = nil
    self.result_menu_index = 1

    -- Increment mission number and load next
    if self.current_mission then
        local faction = self.current_mission:match("^(%a+)")
        local num = tonumber(self.current_mission:match("(%d+)$")) or 1
        self.current_mission = faction .. string.format("%02d", num + 1)
    end

    -- Return to campaign select for now (could auto-load next mission)
    self.state = Game.STATE.CAMPAIGN_SELECT
end

-- Replay current mission
function Game:replay_mission()
    -- Clear result state
    self.mission_result = nil
    self.mission_result_message = nil
    self.result_menu_index = 1

    -- Reload current scenario
    if self.current_mission and self.scenario_loader then
        self:reset_game_state()
        self.scenario_loader:load_scenario("data/scenarios/" .. self.current_mission .. ".json")
        self.state = Game.STATE.PLAYING
    end
end

-- Return to main menu
function Game:return_to_menu()
    -- Clear all game state
    self.mission_result = nil
    self.mission_result_message = nil
    self.result_menu_index = 1
    self:reset_game_state()
    self.state = Game.STATE.MENU
end

-- Reset game state for new mission
function Game:reset_game_state()
    -- Clear world entities
    if self.world then
        self.world:clear()
    end

    -- Reset systems
    if self.trigger_system then
        self.trigger_system:reset()
    end
    if self.team_system then
        self.team_system:reset()
    end

    -- Reset tick counter
    self.tick_count = 0
    self.tick_accumulator = 0
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

-- Draw mission briefing screen
function Game:draw_briefing()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Dark background
    love.graphics.setColor(0.02, 0.02, 0.05, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Get briefing data
    local briefing = self.current_briefing or {}
    local faction = briefing.faction or "GDI"
    local mission_num = briefing.mission or 1
    local title = briefing.title or string.format("%s Mission %d", faction, mission_num)
    local text = briefing.text or "No briefing available."

    -- Faction color
    local faction_color = faction == "NOD" and {0.8, 0.2, 0.2, 1} or {0.9, 0.7, 0.2, 1}

    -- Draw faction emblem area (placeholder)
    love.graphics.setColor(faction_color)
    love.graphics.rectangle("fill", 50, 50, 100, 100)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.printf(faction, 50, 85, 100, "center")

    -- Mission title
    love.graphics.setColor(faction_color)
    love.graphics.printf(title, 180, 70, w - 230, "left")

    -- Briefing text box
    local text_x = 50
    local text_y = 180
    local text_w = w - 100
    local text_h = h - 300

    -- Text background
    love.graphics.setColor(0.05, 0.05, 0.1, 0.9)
    love.graphics.rectangle("fill", text_x, text_y, text_w, text_h)

    -- Text border
    love.graphics.setColor(faction_color[1] * 0.5, faction_color[2] * 0.5, faction_color[3] * 0.5, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", text_x, text_y, text_w, text_h)

    -- Briefing text (with scrolling support if needed)
    love.graphics.setColor(0.8, 0.8, 0.7, 1)
    love.graphics.printf(text, text_x + 20, text_y + 20, text_w - 40, "left")

    -- Objectives section
    local obj_y = text_y + text_h + 20
    love.graphics.setColor(faction_color)
    love.graphics.printf("OBJECTIVES:", text_x, obj_y, text_w, "left")

    local objectives = briefing.objectives or {"Destroy all enemy forces"}
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    for i, obj in ipairs(objectives) do
        love.graphics.printf("- " .. obj, text_x + 20, obj_y + 20 + (i - 1) * 20, text_w - 40, "left")
    end

    -- Instructions
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press ENTER to begin mission | ESC to return", 0, h - 40, w, "center")
end

-- Handle briefing screen input
function Game:handle_briefing_input(key)
    if key == "return" or key == "space" then
        -- Start the mission
        self:start_mission_from_briefing()
    elseif key == "escape" then
        -- Return to campaign select
        self.state = Game.STATE.CAMPAIGN_SELECT
    end
end

-- Start mission after briefing
function Game:start_mission_from_briefing()
    if not self.current_mission then
        self.state = Game.STATE.CAMPAIGN_SELECT
        return
    end

    -- Reset game state for new mission
    self:reset_game_state()

    -- Load the scenario
    local scenario_path = "data/scenarios/" .. self.current_mission .. ".json"
    if self.scenario_loader then
        local success = self.scenario_loader:load_scenario(scenario_path)
        if success then
            self.state = Game.STATE.PLAYING
            -- Center camera on player start position
            self:center_camera_on_player()
        else
            -- Scenario doesn't exist yet - show error and return
            self.current_message = "Scenario not yet available: " .. self.current_mission
            self.message_timer = 3.0
            self.state = Game.STATE.CAMPAIGN_SELECT
        end
    else
        self.state = Game.STATE.CAMPAIGN_SELECT
    end
end

-- Show briefing for a mission
function Game:show_briefing(faction, mission_num)
    self.current_mission = string.lower(faction) .. string.format("%02d", mission_num)
    self.mode = Game.MODE.CAMPAIGN

    -- Build briefing data
    self.current_briefing = {
        faction = faction,
        mission = mission_num,
        title = faction .. " Mission " .. mission_num,
        text = self:get_mission_briefing_text(faction, mission_num),
        objectives = self:get_mission_objectives(faction, mission_num)
    }

    self.state = Game.STATE.BRIEFING
end

-- Get mission briefing text (placeholder - would come from scenario files)
function Game:get_mission_briefing_text(faction, mission_num)
    local briefings = {
        GDI = {
            [1] = "Commander, welcome to the Global Defense Initiative. We have received reports of Nod activity in the region. Your first mission is to establish a foothold and eliminate all hostile forces. A small strike team has been deployed to the area. Good luck.",
            [2] = "Intelligence reports indicate a Nod base in the area. We need you to locate and destroy their command center. Reinforcements will be available once you secure a position.",
            [3] = "The Nod forces are expanding their operations. We must stop them before they gain a strategic advantage. Destroy all enemy structures and units in the area."
        },
        NOD = {
            [1] = "Brother, the Brotherhood of Nod welcomes you. Kane has a special mission for you. Eliminate the GDI presence in this sector and secure the Tiberium fields for our use.",
            [2] = "GDI forces have established a base near our operations. Kane demands their destruction. Show no mercy to the enemies of Nod.",
            [3] = "The infidels must be purged from our lands. Destroy their base and recover any technology that may be useful to the Brotherhood."
        }
    }

    local faction_briefings = briefings[faction] or briefings.GDI
    return faction_briefings[mission_num] or "Mission briefing data not available."
end

-- Get mission objectives (placeholder - would come from scenario files)
function Game:get_mission_objectives(faction, mission_num)
    return {
        "Destroy all enemy forces",
        "Secure the area"
    }
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
    love.graphics.print(string.format("FPS: %d | Tick: %d | Entities: %d | Credits: $%d",
        love.timer.getFPS(),
        self.tick_count,
        self.world:entity_count(),
        self.player_credits
    ), 10, 10)

    love.graphics.print(string.format("Selected: %d | Camera: %.0f, %.0f | Scale: %.2f",
        self.selection_system:get_selection_count(),
        self.render_system.camera_x,
        self.render_system.camera_y,
        self.render_system.scale
    ), 10, 30)

    love.graphics.print("WASD: Pan camera | Click: Select | Right-click: Move | +/-: Zoom", 10, 50)
end

-- Draw in-game messages from triggers
function Game:draw_messages()
    if not self.current_message or self.message_timer <= 0 then
        return
    end

    local w = love.graphics.getWidth()
    local sidebar_w = self.sidebar and self.sidebar.width or 0

    -- Message box at top center of game area
    local msg_w = 400
    local msg_h = 60
    local msg_x = (w - sidebar_w - msg_w) / 2
    local msg_y = 80

    -- Background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", msg_x, msg_y, msg_w, msg_h)

    -- Border
    love.graphics.setColor(0.6, 0.5, 0.2, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", msg_x, msg_y, msg_w, msg_h)

    -- Text
    love.graphics.setColor(1, 0.9, 0.5, 1)
    love.graphics.printf(self.current_message, msg_x + 10, msg_y + 20, msg_w - 20, "center")
end

-- Draw special weapon targeting cursor
function Game:draw_targeting_cursor()
    if not self.special_weapons or not self.special_weapons.targeting then
        return
    end

    local mx, my = love.mouse.getPosition()

    -- Get weapon data for targeting circle radius
    local weapon_type = self.special_weapons.targeting
    local weapon_data = self.special_weapons.DATA[weapon_type]
    local radius = weapon_data and weapon_data.radius or 3

    -- Convert cell radius to pixel radius at current scale
    local pixel_radius = radius * Constants.CELL_PIXEL_W * self.render_system.scale

    -- Draw targeting circle
    love.graphics.setColor(1, 0, 0, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", mx, my, pixel_radius)

    -- Inner crosshair
    love.graphics.setColor(1, 0, 0, 0.8)
    love.graphics.line(mx - 15, my, mx + 15, my)
    love.graphics.line(mx, my - 15, mx, my + 15)

    -- Weapon name label
    love.graphics.setColor(1, 0.3, 0.3, 1)
    love.graphics.printf(weapon_type:upper(), mx - 50, my + pixel_radius + 10, 100, "center")

    -- Instructions
    love.graphics.setColor(0.8, 0.8, 0.8, 0.8)
    love.graphics.printf("Right-click to fire | ESC to cancel", mx - 100, my + pixel_radius + 30, 200, "center")
end

-- Input handling
function Game:keypressed(key)
    if self.state == Game.STATE.MENU then
        self:handle_menu_input(key)
    elseif self.state == Game.STATE.OPTIONS then
        self:handle_options_input(key)
    elseif self.state == Game.STATE.CAMPAIGN_SELECT then
        self:handle_campaign_select_input(key)
    elseif self.state == Game.STATE.BRIEFING then
        self:handle_briefing_input(key)
    elseif self.state == Game.STATE.SKIRMISH_SETUP then
        self:handle_skirmish_setup_input(key)
    elseif self.state == Game.STATE.MULTIPLAYER_LOBBY then
        self:handle_multiplayer_lobby_input(key)
    elseif self.state == Game.STATE.PLAYING then
        self:handle_playing_input(key)
    elseif self.state == Game.STATE.PAUSED then
        -- Check if in mission result screen first
        if self.mission_result then
            self:handle_result_input(key)
        elseif key == "escape" then
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
        self:show_briefing("GDI", 1)
    elseif key == "2" then
        self.player_house = Constants.HOUSE.BAD
        self:show_briefing("NOD", 1)
    elseif key == "3" then
        -- Covert Ops - start with GDI covert ops mission 1
        self.player_house = Constants.HOUSE.GOOD
        self:show_briefing("GDI", 1)  -- TODO: Covert ops missions
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

-- Handle multiplayer lobby input
function Game:handle_multiplayer_lobby_input(key)
    if key == "escape" then
        self.state = Game.STATE.MENU
    end
end

-- Handle playing input
function Game:handle_playing_input(key)
    if key == "escape" then
        -- Cancel special weapon targeting first
        if self.special_weapons and self.special_weapons.targeting then
            self.special_weapons:cancel_targeting()
            return
        end
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
    elseif key == "home" then
        -- Reset camera to origin
        self.render_system:set_camera(0, 0)
    end

    -- Camera controls (arrow keys and WASD)
    local camera_speed = 48  -- 2 cells per keypress
    if key == "up" or key == "w" then
        self.render_system:set_camera(
            self.render_system.camera_x,
            self.render_system.camera_y - camera_speed
        )
    elseif key == "down" then
        self.render_system:set_camera(
            self.render_system.camera_x,
            self.render_system.camera_y + camera_speed
        )
    elseif key == "left" or key == "a" then
        self.render_system:set_camera(
            self.render_system.camera_x - camera_speed,
            self.render_system.camera_y
        )
    elseif key == "right" or key == "d" then
        self.render_system:set_camera(
            self.render_system.camera_x + camera_speed,
            self.render_system.camera_y
        )
    end

    -- Stop command (S key) - stop all selected units
    if key == "s" then
        self:issue_stop_command()
    end

    -- Guard command (G key) - put selected units in guard mode
    if key == "g" then
        self:issue_guard_command()
    end

    -- Sell building (Delete key) - sell selected buildings for credits
    if key == "delete" then
        self:sell_selected_buildings()
    end

    -- Deploy command (D key) - deploy MCV to Construction Yard
    if key == "d" then
        self:deploy_selected_units()
    end

    -- Repair command (R key) - toggle repair mode on selected buildings
    if key == "r" then
        self:toggle_repair_selected_buildings()
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
        -- Check sidebar first
        if self.show_sidebar and self.sidebar then
            if self.sidebar:mousepressed(x, y, button) then
                return  -- Sidebar handled the click
            end
        end

        -- Check radar clicks
        if self.show_sidebar and self.radar then
            if self.radar:mousepressed(x, y, button) then
                return  -- Radar handled the click
            end
        end

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

-- Check if player has any buildings
function Game:player_has_buildings()
    local entities = self.world:get_all_entities()
    for _, entity in ipairs(entities) do
        if entity:has("building") and entity:has("owner") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                return true
            end
        end
    end
    return false
end

-- Find a factory that can build a specific unit type
function Game:find_factory_for_unit(unit_type)
    local unit_data = self.production_system.unit_data[unit_type]
    if not unit_data then return nil end

    local required_factory_type = unit_data.type  -- "infantry", "vehicle", "aircraft"

    local entities = self.world:get_all_entities()
    for _, entity in ipairs(entities) do
        if entity:has("production") and entity:has("owner") then
            local owner = entity:get("owner")
            local production = entity:get("production")

            if owner.house == self.player_house and
               production.factory_type == required_factory_type then
                return entity
            end
        end
    end
    return nil
end

-- Find the construction yard for building production
function Game:find_construction_yard()
    local entities = self.world:get_all_entities()
    for _, entity in ipairs(entities) do
        if entity:has("building") and entity:has("production") and entity:has("owner") then
            local owner = entity:get("owner")
            local building = entity:get("building")

            if owner.house == self.player_house and building.structure_type == "FACT" then
                return entity
            end
        end
    end
    return nil
end

-- Start production of a unit at the appropriate factory
function Game:start_unit_production(unit_type)
    local factory = self:find_factory_for_unit(unit_type)
    if not factory then
        print("No factory available for " .. unit_type)
        return false
    end

    local unit_data = self.production_system.unit_data[unit_type]
    local cost = unit_data.cost or 0

    if self.player_credits < cost then
        print("Not enough credits for " .. unit_type)
        return false
    end

    local success, err = self.production_system:queue_unit(factory, unit_type)
    if success then
        -- Spend credits through harvest system (source of truth)
        if self.harvest_system then
            self.harvest_system:spend_credits(self.player_house, cost)
        end
        self.player_credits = self.player_credits - cost
        print(string.format("Started production of %s ($%d)", unit_type, cost))
        return true
    else
        print("Cannot build " .. unit_type .. ": " .. (err or "unknown error"))
        return false
    end
end

-- Update sidebar production display
function Game:update_production_display()
    if not self.sidebar or not self.production_system then return end

    -- Check building production (construction yard)
    local cy = self:find_construction_yard()
    if cy and cy:has("production") then
        local production = cy:get("production")
        if #production.queue > 0 then
            local item = production.queue[1]
            self.sidebar:set_production_state("building", item.name, production.progress)
        else
            self.sidebar:clear_production_state("building")
        end
    else
        self.sidebar:clear_production_state("building")
    end

    -- Check unit production (find any active factory)
    local unit_factory = nil
    local entities = self.world:get_all_entities()
    for _, entity in ipairs(entities) do
        if entity:has("production") and entity:has("owner") then
            local owner = entity:get("owner")
            local production = entity:get("production")

            if owner.house == self.player_house and
               production.factory_type ~= nil and
               production.factory_type ~= "building" and
               #production.queue > 0 then
                unit_factory = entity
                break
            end
        end
    end

    if unit_factory then
        local production = unit_factory:get("production")
        local item = production.queue[1]
        self.sidebar:set_production_state("unit", item.name, production.progress)
    else
        self.sidebar:clear_production_state("unit")
    end
end

-- Start production of a building at the construction yard
function Game:start_building_production(building_type)
    local cy = self:find_construction_yard()
    if not cy then
        print("No Construction Yard available")
        return false
    end

    local building_data = self.production_system.building_data[building_type]
    local cost = building_data.cost or 0

    if self.player_credits < cost then
        print("Not enough credits for " .. building_type)
        return false
    end

    local success, err = self.production_system:queue_building(cy, building_type)
    if success then
        self.player_credits = self.player_credits - cost
        print(string.format("Started production of %s ($%d)", building_type, cost))
        return true
    else
        print("Cannot build " .. building_type .. ": " .. (err or "unknown error"))
        return false
    end
end

function Game:handle_right_click(screen_x, screen_y)
    local world_x, world_y = self.render_system:screen_to_world(screen_x, screen_y)

    -- Check if in special weapon targeting mode
    if self.special_weapons and self.special_weapons.targeting then
        -- Fire the weapon at clicked location
        local target_x = world_x * Constants.PIXEL_LEPTON_W
        local target_y = world_y * Constants.PIXEL_LEPTON_H
        self.special_weapons:fire(self.player_house, self.special_weapons.targeting, target_x, target_y)
        return
    end

    -- Check if placing a building from sidebar
    if self.sidebar and self.sidebar:get_selected_item() then
        local item = self.sidebar:get_selected_item()
        local cell_x = math.floor(world_x / Constants.CELL_PIXEL_W)
        local cell_y = math.floor(world_y / Constants.CELL_PIXEL_H)

        -- Check if this is a building or unit
        local building_data = self.production_system.building_data[item]
        local unit_data = self.production_system.unit_data[item]

        if building_data then
            -- Place building
            local cost = building_data.cost or 0
            if self.player_credits >= cost then
                -- Check placement validity (with adjacency requirement)
                local size_x = building_data.size and building_data.size[1] or 1
                local size_y = building_data.size and building_data.size[2] or 1

                -- First building doesn't require adjacency (construction yard/MCV deploy)
                local has_buildings = self:player_has_buildings()
                local can_place, reason = self.grid:can_place_building(
                    cell_x, cell_y, size_x, size_y,
                    self.player_house, has_buildings
                )

                if can_place then
                    local entity = self.production_system:create_building(item, self.player_house, cell_x, cell_y)
                    if entity then
                        self.world:add_entity(entity)
                        -- Mark cells as occupied
                        self.grid:place_building(cell_x, cell_y, size_x, size_y, entity.id, self.player_house)
                        -- Spend credits through harvest system
                        if self.harvest_system then
                            self.harvest_system:spend_credits(self.player_house, cost)
                        end
                        self.player_credits = self.player_credits - cost
                        self.sidebar:clear_selection()
                        print(string.format("Built %s at (%d,%d)", item, cell_x, cell_y))
                    end
                else
                    print(string.format("Cannot place %s: %s", item, reason or "invalid location"))
                end
            end
        elseif unit_data then
            -- Create unit at location
            local cost = unit_data.cost or 0
            if self.player_credits >= cost then
                local dest_x = cell_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
                local dest_y = cell_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
                local entity = self.production_system:create_unit(item, self.player_house, dest_x, dest_y)
                if entity then
                    self.world:add_entity(entity)
                    -- Spend credits through harvest system
                    if self.harvest_system then
                        self.harvest_system:spend_credits(self.player_house, cost)
                    end
                    self.player_credits = self.player_credits - cost
                    self.sidebar:clear_selection()
                    print(string.format("Created %s at (%d,%d)", item, cell_x, cell_y))
                end
            end
        end
        return
    end

    -- Normal movement command
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    -- Convert to leptons
    local dest_x = world_x * Constants.PIXEL_LEPTON_W
    local dest_y = world_y * Constants.PIXEL_LEPTON_H

    -- Check for command modifiers
    local ctrl_held = love.keyboard.isDown("lctrl", "rctrl")
    local a_key_held = love.keyboard.isDown("a")

    -- Check if there's a target entity under the click
    local target_entity = self:get_entity_at_position(dest_x, dest_y)

    if ctrl_held and target_entity then
        -- Force-fire: Attack the target regardless of allegiance
        self:issue_force_attack(selected, target_entity)
        return
    end

    if ctrl_held and not target_entity then
        -- Force-fire on ground: Attack ground position
        self:issue_attack_ground(selected, dest_x, dest_y)
        return
    end

    if a_key_held then
        -- Attack-move: Move to destination but engage enemies along the way
        self:issue_attack_move(selected, dest_x, dest_y)
        return
    end

    -- Check if target is an enemy - issue attack command
    if target_entity and target_entity:has("owner") then
        local target_owner = target_entity:get("owner")
        if target_owner.house ~= self.player_house then
            -- Right-click on enemy = attack
            self:issue_attack(selected, target_entity)
            return
        end
    end

    -- Normal move command
    for _, entity in ipairs(selected) do
        if entity:has("mobile") then
            self.movement_system:move_to(entity, dest_x, dest_y)
            -- Clear any attack target when issuing move
            if entity:has("combat") then
                entity:get("combat").target = nil
            end
            -- Set mission to move
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.MOVE
            end
        end
    end

    Events.emit(Events.EVENTS.COMMAND_MOVE, selected, dest_x, dest_y)
end

-- Get entity at a position (for targeting)
function Game:get_entity_at_position(lx, ly)
    local click_radius = Constants.LEPTON_PER_CELL / 2
    local best_entity = nil
    local best_dist = click_radius

    local entities = self.world:get_entities_with("transform", "health")
    for _, entity in ipairs(entities) do
        local transform = entity:get("transform")
        local dx = transform.x - lx
        local dy = transform.y - ly
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < best_dist then
            best_dist = dist
            best_entity = entity
        end
    end

    return best_entity
end

-- Issue normal attack command (right-click on enemy)
function Game:issue_attack(units, target)
    for _, entity in ipairs(units) do
        if entity:has("combat") then
            local combat = entity:get("combat")
            combat.target = target.id
            combat.force_fire = false

            -- Set mission to attack
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.ATTACK
            end

            -- Move towards target if mobile
            if entity:has("mobile") then
                local target_transform = target:get("transform")
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end

    Events.emit(Events.EVENTS.COMMAND_ATTACK, units, target)
end

-- Issue force attack command (attack regardless of allegiance)
function Game:issue_force_attack(units, target)
    for _, entity in ipairs(units) do
        if entity:has("combat") then
            local combat = entity:get("combat")
            combat.target = target.id
            combat.force_fire = true  -- Flag to allow attacking anything

            -- Set mission to attack
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.ATTACK
            end

            -- Move towards target if mobile
            if entity:has("mobile") then
                local target_transform = target:get("transform")
                self.movement_system:move_to(entity, target_transform.x, target_transform.y)
            end
        end
    end

    Events.emit(Events.EVENTS.COMMAND_ATTACK, units, target)
end

-- Issue attack ground command (attack a position)
function Game:issue_attack_ground(units, dest_x, dest_y)
    for _, entity in ipairs(units) do
        if entity:has("combat") then
            local combat = entity:get("combat")
            combat.target = nil
            combat.attack_ground_x = dest_x
            combat.attack_ground_y = dest_y
            combat.force_fire = true

            -- Set mission to attack
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.ATTACK
            end

            -- Move in range if mobile
            if entity:has("mobile") then
                self.movement_system:move_to(entity, dest_x, dest_y)
            end
        end
    end

    Events.emit(Events.EVENTS.COMMAND_ATTACK_GROUND, units, dest_x, dest_y)
end

-- Issue attack-move command (move but engage enemies)
function Game:issue_attack_move(units, dest_x, dest_y)
    for _, entity in ipairs(units) do
        if entity:has("mobile") then
            local mobile = entity:get("mobile")
            self.movement_system:move_to(entity, dest_x, dest_y)

            -- Set attack-move flag
            mobile.attack_move = true

            -- Set mission to hunt (will engage enemies while moving)
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.HUNT
            end
        end
    end

    Events.emit(Events.EVENTS.COMMAND_ATTACK_MOVE, units, dest_x, dest_y)
end

-- Issue stop command to selected units
function Game:issue_stop_command()
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    for _, entity in ipairs(selected) do
        -- Stop movement
        if entity:has("mobile") then
            local mobile = entity:get("mobile")
            mobile.is_moving = false
            mobile.path = {}
            mobile.path_index = 0
            mobile.attack_move = false
        end

        -- Clear attack target
        if entity:has("combat") then
            local combat = entity:get("combat")
            combat.target = nil
            combat.force_fire = false
            combat.attack_ground_x = nil
            combat.attack_ground_y = nil
        end

        -- Set mission to stop/guard
        if entity:has("mission") then
            entity:get("mission").mission_type = Constants.MISSION.STOP
        end
    end

    Events.emit(Events.EVENTS.COMMAND_STOP, selected)
end

-- Issue guard command to selected units
function Game:issue_guard_command()
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    for _, entity in ipairs(selected) do
        -- Stop movement but keep position
        if entity:has("mobile") then
            local mobile = entity:get("mobile")
            mobile.is_moving = false
            mobile.path = {}
            mobile.attack_move = false
        end

        -- Set mission to guard (will auto-attack enemies in range)
        if entity:has("mission") then
            entity:get("mission").mission_type = Constants.MISSION.GUARD
        end
    end

    Events.emit(Events.EVENTS.COMMAND_GUARD, selected)
end

-- Sell selected buildings for credits (50% refund)
function Game:sell_selected_buildings()
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    local total_refund = 0
    local sold_any = false

    for _, entity in ipairs(selected) do
        -- Only sell buildings owned by player
        if entity:has("building") and entity:has("owner") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                local building_data = entity:get("building")
                local structure_type = building_data.structure_type

                -- Get building cost from data
                local cost = 0
                if self.production_system and self.production_system.building_data[structure_type] then
                    cost = self.production_system.building_data[structure_type].cost or 0
                end

                -- Calculate refund (50% of original cost)
                local refund = math.floor(cost * 0.5)
                total_refund = total_refund + refund

                -- Clear the building's cells from the grid
                if self.grid then
                    local transform = entity:get("transform")
                    local size_x = building_data.size_x or 1
                    local size_y = building_data.size_y or 1
                    self.grid:remove_building(transform.cell_x, transform.cell_y, size_x, size_y)
                end

                -- Remove from selection before destroying
                self.selection_system:deselect(entity)

                -- Destroy the building
                self.world:destroy_entity(entity)
                sold_any = true

                print(string.format("Sold %s for $%d", structure_type, refund))
            end
        end
    end

    -- Add refund to credits
    if total_refund > 0 and self.harvest_system then
        self.harvest_system:add_credits(self.player_house, total_refund)
        self.player_credits = self.player_credits + total_refund
    end

    if sold_any then
        -- Recalculate power after selling
        if self.power_system then
            self.power_system:recalculate_power()
        end

        -- Recalculate storage after selling refineries/silos
        if self.harvest_system then
            self.harvest_system:recalculate_storage()
        end

        Events.emit(Events.EVENTS.BUILDING_SOLD, total_refund)
    end
end

-- Deploy selected deployable units (MCV -> Construction Yard)
function Game:deploy_selected_units()
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    local deployed_any = false

    for _, entity in ipairs(selected) do
        -- Only deploy units owned by player that have deployable component
        if entity:has("deployable") and entity:has("owner") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                -- Try to deploy via production system
                if self.production_system then
                    local building, err = self.production_system:deploy_unit(entity, self.grid)
                    if building then
                        deployed_any = true
                        print("Deployed MCV to Construction Yard")

                        -- Recalculate power after deployment
                        if self.power_system then
                            self.power_system:recalculate_power()
                        end
                    else
                        print("Cannot deploy: " .. tostring(err))
                    end
                end
            end
        end
    end

    if deployed_any then
        -- Clear selection since MCV was destroyed
        self.selection_system:clear_selection()
    end
end

-- Toggle repair mode on selected buildings
function Game:toggle_repair_selected_buildings()
    local selected = self.selection_system:get_selected_entities()
    if #selected == 0 then return end

    for _, entity in ipairs(selected) do
        -- Only toggle repair on buildings owned by player
        if entity:has("building") and entity:has("owner") and entity:has("health") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                local building = entity:get("building")
                local health = entity:get("health")

                -- Only allow repair if damaged
                if health.hp < health.max_hp then
                    if building.repairing then
                        -- Stop repairing
                        if self.production_system then
                            self.production_system:stop_repair(entity)
                        end
                        print("Stopped repairing " .. (building.structure_type or "building"))
                    else
                        -- Start repairing
                        if self.production_system then
                            self.production_system:start_repair(entity)
                        end
                        print("Started repairing " .. (building.structure_type or "building"))
                    end
                else
                    print("Building is already at full health")
                end
            end
        end
    end
end

-- Process repair for all buildings that are in repair mode
function Game:process_building_repairs(dt)
    if not self.production_system then return end

    -- Get all building entities
    local buildings = self.world:get_entities_with("building")
    for _, entity in ipairs(buildings) do
        local building = entity:get("building")
        if building and building.repairing then
            self.production_system:process_repair(entity, dt)
        end
    end
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
        self.world:reset()  -- Full reset on quit
    end
    Events.emit(Events.EVENTS.GAME_END)
end

return Game
