--[[
    Systems Module - Exports all game systems
]]

local Systems = {
    -- Core systems
    RenderSystem = require("src.systems.render_system"),
    SelectionSystem = require("src.systems.selection_system"),
    MovementSystem = require("src.systems.movement_system"),
    AnimationSystem = require("src.systems.animation_system"),

    -- Combat
    CombatSystem = require("src.systems.combat_system"),
    AISystem = require("src.systems.ai_system"),
    TurretSystem = require("src.systems.turret_system"),

    -- Economy
    ProductionSystem = require("src.systems.production_system"),
    HarvestSystem = require("src.systems.harvest_system"),
    PowerSystem = require("src.systems.power_system"),

    -- Aircraft
    AircraftSystem = require("src.systems.aircraft_system"),

    -- Phase 6: Polish
    FogSystem = require("src.systems.fog_system"),
    SpecialWeapons = require("src.systems.special_weapons"),
    CloakSystem = require("src.systems.cloak_system"),
    AudioSystem = require("src.systems.audio_system")
}

return Systems
