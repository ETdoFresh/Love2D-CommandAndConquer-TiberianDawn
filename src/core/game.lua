--[[
    Game - Main game state machine and controller
    Manages game states, updates, and rendering
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")
local ECS = require("src.ecs")
local Map = require("src.map")
local Systems = require("src.systems")

local Game = {}
Game.__index = Game

-- Game states
Game.STATE = {
    NONE = "none",
    LOADING = "loading",
    MENU = "menu",
    PLAYING = "playing",
    PAUSED = "paused",
    SCENARIO_LOADING = "scenario_loading"
}

function Game.new()
    local self = setmetatable({}, Game)

    -- Current state
    self.state = Game.STATE.NONE

    -- ECS world
    self.world = nil

    -- Map
    self.grid = nil
    self.theater = nil

    -- Systems references
    self.render_system = nil
    self.selection_system = nil
    self.movement_system = nil

    -- Timing
    self.tick_accumulator = 0
    self.tick_count = 0
    self.paused = false

    -- Graphics mode
    self.use_hd = false

    -- Player info
    self.player_house = Constants.HOUSE.GOOD

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

    -- Create and add systems
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

    self.state = Game.STATE.MENU
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
    if self.state ~= Game.STATE.PLAYING or self.paused then
        return
    end

    -- Fixed timestep for game logic
    self.tick_accumulator = self.tick_accumulator + dt

    while self.tick_accumulator >= Constants.TICK_DURATION do
        self:tick()
        self.tick_accumulator = self.tick_accumulator - Constants.TICK_DURATION
    end

    -- Update world (systems run at frame rate for smooth rendering)
    self.world:update(dt)
end

-- Game logic tick (15 FPS)
function Game:tick()
    self.tick_count = self.tick_count + 1
    Events.emit(Events.EVENTS.GAME_TICK, self.tick_count)
end

-- Draw game
function Game:draw()
    if self.state == Game.STATE.PLAYING then
        -- Draw terrain
        self:draw_terrain()

        -- Draw entities
        self.world:draw()

        -- Draw selection box (UI layer)
        self.selection_system:draw_selection_box()

        -- Draw debug info
        self:draw_debug()
    elseif self.state == Game.STATE.MENU then
        self:draw_menu()
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
    love.graphics.setColor(0.1, 0.1, 0.15, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 0.8, 0, 1)
    love.graphics.printf("COMMAND & CONQUER",
        0, 100, love.graphics.getWidth(), "center")

    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("TIBERIAN DAWN",
        0, 130, love.graphics.getWidth(), "center")

    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press SPACE to start",
        0, 200, love.graphics.getWidth(), "center")

    love.graphics.printf("Love2D Port - Phase 1 Foundation",
        0, love.graphics.getHeight() - 50, love.graphics.getWidth(), "center")
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
        if key == "space" then
            self:start_game()
        end
    elseif self.state == Game.STATE.PLAYING then
        if key == "escape" then
            self.paused = not self.paused
        elseif key == "h" then
            -- Toggle HD mode
            self.use_hd = not self.use_hd
            self.render_system:set_hd_mode(self.use_hd)
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

-- Clean up
function Game:quit()
    if self.world then
        self.world:clear()
    end
    Events.emit(Events.EVENTS.GAME_END)
end

return Game
