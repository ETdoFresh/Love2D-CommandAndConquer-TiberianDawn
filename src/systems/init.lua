--[[
    Systems Compatibility Shim

    This module provides stub implementations of the old ECS systems
    to allow the game to load during the Phase 0->Phase 1 migration.

    TODO: Remove this shim once src/core/game.lua is fully migrated to
    use the C++ class hierarchy in src/objects/ (Phase 1 completion).

    Each system below is a minimal stub that implements the interface
    expected by game.lua but performs no actual game logic.
]]

-- Base system factory
local function create_stub_system(name)
    local System = {}
    System.__index = System
    System.name = name

    function System.new(...)
        local self = setmetatable({}, System)
        self.priority = 0
        self.world = nil
        self.enabled = true
        return self
    end

    function System:set_priority(priority)
        self.priority = priority or 0
    end

    function System:init()
        -- Stub: no-op
    end

    function System:update(dt)
        -- Stub: no-op
    end

    function System:draw()
        -- Stub: no-op
    end

    return System
end

-- RenderSystem stub
local RenderSystem = create_stub_system("RenderSystem")

RenderSystem.scale = 1.0
RenderSystem.camera_x = 0
RenderSystem.camera_y = 0

function RenderSystem:set_camera(x, y)
    if type(x) == "table" then
        self.camera = x
    else
        self.camera_x = x or 0
        self.camera_y = y or 0
    end
end

function RenderSystem:set_grid(grid)
    self.grid = grid
end

function RenderSystem:set_theater(theater)
    self.theater = theater
end

function RenderSystem:set_sidebar_visible(visible)
    self.sidebar_visible = visible
end

function RenderSystem:set_fog_system(fog_system)
    self.fog_system = fog_system
end

function RenderSystem:set_cloak_system(cloak_system)
    self.cloak_system = cloak_system
end

function RenderSystem:set_viewer_house(house)
    self.viewer_house = house
end

function RenderSystem:set_hd_mode(enabled)
    self.hd_mode = enabled
end

function RenderSystem:set_scale(scale)
    self.scale = scale or 1.0
end

function RenderSystem:update_viewport()
    -- Stub
end

function RenderSystem:screen_to_world(screen_x, screen_y)
    -- Simple conversion without actual camera transform
    return (screen_x / self.scale) + self.camera_x,
           (screen_y / self.scale) + self.camera_y
end

function RenderSystem:world_to_screen(world_x, world_y)
    return (world_x - self.camera_x) * self.scale,
           (world_y - self.camera_y) * self.scale
end

-- SelectionSystem stub
local SelectionSystem = create_stub_system("SelectionSystem")

function SelectionSystem:clear_selection()
    -- Stub
end

function SelectionSystem:get_selected_entities()
    return {}
end

function SelectionSystem:select_entity(entity)
    -- Stub
end

function SelectionSystem:set_player_house(house)
    self.player_house = house
end

-- MovementSystem stub
local MovementSystem = create_stub_system("MovementSystem")

function MovementSystem.new(grid)
    local self = setmetatable({}, MovementSystem)
    self.priority = 0
    self.world = nil
    self.grid = grid
    return self
end

function MovementSystem:set_trigger_system(trigger_system)
    self.trigger_system = trigger_system
end

function MovementSystem:move_entity_to(entity, target_x, target_y)
    -- Stub
end

function MovementSystem:stop_entity(entity)
    -- Stub
end

-- AnimationSystem stub
local AnimationSystem = create_stub_system("AnimationSystem")

-- CombatSystem stub
local CombatSystem = create_stub_system("CombatSystem")

function CombatSystem:set_fog_system(fog_system)
    self.fog_system = fog_system
end

function CombatSystem:attack_target(attacker, target)
    -- Stub
end

function CombatSystem:fire_special_weapon(house, weapon_type, target_x, target_y)
    -- Stub
end

-- AISystem stub
local AISystem = create_stub_system("AISystem")

function AISystem:set_house_data(house, data)
    -- Stub
end

function AISystem:set_fog_system(fog_system)
    self.fog_system = fog_system
end

function AISystem:get_house_ai(house)
    return nil
end

-- TurretSystem stub
local TurretSystem = create_stub_system("TurretSystem")

-- ProductionSystem stub
local ProductionSystem = create_stub_system("ProductionSystem")

function ProductionSystem:queue_production(house, item_type, category)
    -- Stub
end

function ProductionSystem:cancel_production(house, item_type, category)
    -- Stub
end

function ProductionSystem:get_queue(house, category)
    return {}
end

function ProductionSystem:get_production_progress(house, category)
    return 0
end

function ProductionSystem:create_unit(unit_type, house, x, y)
    return nil
end

function ProductionSystem:create_building(building_type, house, x, y)
    return nil
end

function ProductionSystem:create_infantry(infantry_type, house, x, y)
    return nil
end

function ProductionSystem:create_aircraft(aircraft_type, house, x, y)
    return nil
end

function ProductionSystem:set_credits_callback(callback)
    self.credits_callback = callback
end

function ProductionSystem:set_fog_system(fog_system)
    self.fog_system = fog_system
end

-- HarvestSystem stub
local HarvestSystem = create_stub_system("HarvestSystem")

function HarvestSystem.new(grid)
    local self = setmetatable({}, HarvestSystem)
    self.priority = 0
    self.world = nil
    self.grid = grid
    return self
end

function HarvestSystem:grow_tiberium(dt)
    -- Stub
end

-- PowerSystem stub
local PowerSystem = create_stub_system("PowerSystem")

function PowerSystem:get_power_status(house)
    return {
        production = 0,
        consumption = 0,
        ratio = 1.0
    }
end

function PowerSystem:recalculate(house)
    -- Stub
end

-- FogSystem stub
local FogSystem = create_stub_system("FogSystem")

function FogSystem.new(grid)
    local self = setmetatable({}, FogSystem)
    self.priority = 0
    self.world = nil
    self.grid = grid
    self.player_house = nil
    self.fog_enabled = true
    self.shroud_enabled = true
    return self
end

function FogSystem:set_player_house(house)
    self.player_house = house
end

function FogSystem:set_fog_enabled(enabled)
    self.fog_enabled = enabled
end

function FogSystem:set_shroud_enabled(enabled)
    self.shroud_enabled = enabled
end

function FogSystem:reveal_all(house)
    -- Stub
end

function FogSystem:reveal_area(house, x, y, radius)
    -- Stub
end

function FogSystem:is_visible(house, x, y)
    return true  -- Everything visible in stub
end

function FogSystem:is_revealed(house, x, y)
    return true
end

-- CloakSystem stub
local CloakSystem = create_stub_system("CloakSystem")

-- AudioSystem stub
local AudioSystem = create_stub_system("AudioSystem")

function AudioSystem:set_player_house(house)
    self.player_house = house
end

function AudioSystem:set_listener_position(x, y)
    self.listener_x = x
    self.listener_y = y
end

function AudioSystem:play_sound(sound_name, x, y)
    -- Stub
end

function AudioSystem:play_eva(eva_name)
    -- Stub
end

function AudioSystem:play_music(track_name)
    -- Stub
end

function AudioSystem:stop_music()
    -- Stub
end

-- SpecialWeapons stub
local SpecialWeapons = {}
SpecialWeapons.__index = SpecialWeapons

function SpecialWeapons.new(world, combat_system)
    local self = setmetatable({}, SpecialWeapons)
    self.world = world
    self.combat_system = combat_system
    return self
end

function SpecialWeapons:update(dt)
    -- Stub
end

function SpecialWeapons:fire(house, weapon_type, target_x, target_y)
    -- Stub
end

function SpecialWeapons:is_ready(house, weapon_type)
    return false
end

function SpecialWeapons:get_charge_progress(house, weapon_type)
    return 0
end

-- Export all systems
return {
    RenderSystem = RenderSystem,
    SelectionSystem = SelectionSystem,
    MovementSystem = MovementSystem,
    AnimationSystem = AnimationSystem,
    CombatSystem = CombatSystem,
    AISystem = AISystem,
    TurretSystem = TurretSystem,
    ProductionSystem = ProductionSystem,
    HarvestSystem = HarvestSystem,
    PowerSystem = PowerSystem,
    FogSystem = FogSystem,
    CloakSystem = CloakSystem,
    AudioSystem = AudioSystem,
    SpecialWeapons = SpecialWeapons
}
