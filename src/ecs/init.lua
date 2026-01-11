--[[
    ECS Module - Entity Component System
    Lightweight ECS implementation for game logic
]]

local ECS = {
    Entity = require("src.ecs.entity"),
    Component = require("src.ecs.component"),
    System = require("src.ecs.system"),
    World = require("src.ecs.world")
}

-- Initialize component registry
ECS.Component.register_all()

return ECS
