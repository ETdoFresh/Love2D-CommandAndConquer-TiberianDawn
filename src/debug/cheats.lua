--[[
    Cheat Command System - Debug cheats for testing

    Reference: Original C&C cheat codes and debug commands
    The original game had various debug/cheat commands for testing.

    Classic C&C Cheats:
    - Give credits
    - Reveal map
    - Instant build
    - God mode (invulnerability)
    - Spawn units/buildings

    This system provides equivalent functionality for testing.
]]

local Cheats = {}

-- Cheat state
Cheats.enabled = false
Cheats.god_mode = false
Cheats.instant_build = false
Cheats.reveal_map = false
Cheats.unlimited_credits = false
Cheats.no_fog = false

-- Callback references (set by game)
Cheats.game = nil
Cheats.world = nil
Cheats.harvest_system = nil
Cheats.production_system = nil
Cheats.fog_system = nil

--[[
    Initialize the cheat system with game references.

    @param game - Game instance
]]
function Cheats.init(game)
    Cheats.game = game
    if game then
        Cheats.world = game.world
        Cheats.harvest_system = game.harvest_system
        Cheats.production_system = game.production_system
        Cheats.fog_system = game.fog_system
    end
    Cheats.enabled = true
end

--[[
    Enable or disable cheats globally.
]]
function Cheats.set_enabled(enabled)
    Cheats.enabled = enabled
    if not enabled then
        -- Reset all active cheats
        Cheats.god_mode = false
        Cheats.instant_build = false
        Cheats.reveal_map = false
        Cheats.unlimited_credits = false
        Cheats.no_fog = false
    end
end

--[[
    Check if cheats are enabled.
]]
function Cheats.is_enabled()
    return Cheats.enabled
end

-- ============================================================================
-- Credit Cheats
-- ============================================================================

--[[
    Add credits to the player's house.

    @param amount - Credits to add (default 10000)
]]
function Cheats.add_credits(amount)
    if not Cheats.enabled then return false, "Cheats disabled" end

    amount = amount or 10000

    if Cheats.harvest_system and Cheats.game then
        Cheats.harvest_system:add_credits(Cheats.game.player_house, amount)
        return true, string.format("Added %d credits", amount)
    elseif Cheats.game then
        Cheats.game.player_credits = (Cheats.game.player_credits or 0) + amount
        return true, string.format("Added %d credits", amount)
    end

    return false, "No game reference"
end

--[[
    Set credits to specific amount.

    @param amount - Credits to set
]]
function Cheats.set_credits(amount)
    if not Cheats.enabled then return false, "Cheats disabled" end

    amount = amount or 50000

    if Cheats.harvest_system and Cheats.game then
        local current = Cheats.harvest_system:get_credits(Cheats.game.player_house)
        local diff = amount - current
        if diff > 0 then
            Cheats.harvest_system:add_credits(Cheats.game.player_house, diff)
        elseif diff < 0 then
            Cheats.harvest_system:spend_credits(Cheats.game.player_house, -diff)
        end
        return true, string.format("Set credits to %d", amount)
    elseif Cheats.game then
        Cheats.game.player_credits = amount
        return true, string.format("Set credits to %d", amount)
    end

    return false, "No game reference"
end

--[[
    Toggle unlimited credits mode.
]]
function Cheats.toggle_unlimited_credits()
    if not Cheats.enabled then return false, "Cheats disabled" end

    Cheats.unlimited_credits = not Cheats.unlimited_credits
    return true, "Unlimited credits: " .. (Cheats.unlimited_credits and "ON" or "OFF")
end

-- ============================================================================
-- Combat Cheats
-- ============================================================================

--[[
    Toggle god mode (invulnerability for player units).
]]
function Cheats.toggle_god_mode()
    if not Cheats.enabled then return false, "Cheats disabled" end

    Cheats.god_mode = not Cheats.god_mode
    return true, "God mode: " .. (Cheats.god_mode and "ON" or "OFF")
end

--[[
    Damage or destroy selected units.

    @param amount - Damage amount (nil = instant kill)
]]
function Cheats.damage_selected(amount)
    if not Cheats.enabled then return false, "Cheats disabled" end
    if not Cheats.world then return false, "No world reference" end

    local count = 0
    local entities = Cheats.world:get_all_entities()

    for _, entity in ipairs(entities) do
        if entity:has("selectable") and entity:has("health") then
            local sel = entity:get("selectable")
            if sel.is_selected then
                local health = entity:get("health")
                if amount then
                    health.current = math.max(0, health.current - amount)
                else
                    health.current = 0
                end
                count = count + 1
            end
        end
    end

    return true, string.format("Damaged %d units", count)
end

--[[
    Heal selected units to full health.
]]
function Cheats.heal_selected()
    if not Cheats.enabled then return false, "Cheats disabled" end
    if not Cheats.world then return false, "No world reference" end

    local count = 0
    local entities = Cheats.world:get_all_entities()

    for _, entity in ipairs(entities) do
        if entity:has("selectable") and entity:has("health") then
            local sel = entity:get("selectable")
            if sel.is_selected then
                local health = entity:get("health")
                health.current = health.max
                count = count + 1
            end
        end
    end

    return true, string.format("Healed %d units", count)
end

-- ============================================================================
-- Vision Cheats
-- ============================================================================

--[[
    Reveal the entire map.
]]
function Cheats.reveal_all()
    if not Cheats.enabled then return false, "Cheats disabled" end

    if Cheats.fog_system and Cheats.game then
        Cheats.fog_system:reveal_all(Cheats.game.player_house)
        Cheats.reveal_map = true
        return true, "Map revealed"
    end

    return false, "No fog system"
end

--[[
    Toggle fog of war.
]]
function Cheats.toggle_fog()
    if not Cheats.enabled then return false, "Cheats disabled" end

    Cheats.no_fog = not Cheats.no_fog

    if Cheats.fog_system then
        Cheats.fog_system:set_enabled(not Cheats.no_fog)
    end

    return true, "Fog of war: " .. (Cheats.no_fog and "OFF" or "ON")
end

-- ============================================================================
-- Production Cheats
-- ============================================================================

--[[
    Toggle instant build mode.
]]
function Cheats.toggle_instant_build()
    if not Cheats.enabled then return false, "Cheats disabled" end

    Cheats.instant_build = not Cheats.instant_build
    return true, "Instant build: " .. (Cheats.instant_build and "ON" or "OFF")
end

--[[
    Complete all current production immediately.
]]
function Cheats.complete_production()
    if not Cheats.enabled then return false, "Cheats disabled" end
    if not Cheats.world then return false, "No world reference" end

    local count = 0
    local entities = Cheats.world:get_all_entities()

    for _, entity in ipairs(entities) do
        if entity:has("production") and entity:has("owner") then
            local owner = entity:get("owner")
            if Cheats.game and owner.house == Cheats.game.player_house then
                local prod = entity:get("production")
                if #prod.queue > 0 then
                    prod.progress = 1.0  -- Complete immediately
                    count = count + 1
                end
            end
        end
    end

    return true, string.format("Completed %d productions", count)
end

-- ============================================================================
-- Spawn Cheats
-- ============================================================================

--[[
    Spawn a unit at cursor position or specified cell.

    @param unit_type - Unit type string (e.g., "HTNK", "E1")
    @param cell_x, cell_y - Cell coordinates (optional)
    @param house - House ID (optional, defaults to player)
]]
function Cheats.spawn_unit(unit_type, cell_x, cell_y, house)
    if not Cheats.enabled then return false, "Cheats disabled" end
    if not Cheats.game then return false, "No game reference" end

    -- Default to center of map if no position
    cell_x = cell_x or 32
    cell_y = cell_y or 32
    house = house or Cheats.game.player_house

    -- Try to spawn via game's spawn method if available
    if Cheats.game.spawn_unit then
        local entity = Cheats.game:spawn_unit(unit_type, cell_x, cell_y, house)
        if entity then
            return true, string.format("Spawned %s at (%d, %d)", unit_type, cell_x, cell_y)
        end
    end

    return false, "Could not spawn unit"
end

--[[
    Spawn a building at specified cell.

    @param building_type - Building type string (e.g., "NUKE", "FACT")
    @param cell_x, cell_y - Cell coordinates
    @param house - House ID (optional, defaults to player)
]]
function Cheats.spawn_building(building_type, cell_x, cell_y, house)
    if not Cheats.enabled then return false, "Cheats disabled" end
    if not Cheats.game then return false, "No game reference" end

    cell_x = cell_x or 32
    cell_y = cell_y or 32
    house = house or Cheats.game.player_house

    if Cheats.game.spawn_building then
        local entity = Cheats.game:spawn_building(building_type, cell_x, cell_y, house)
        if entity then
            return true, string.format("Spawned %s at (%d, %d)", building_type, cell_x, cell_y)
        end
    end

    return false, "Could not spawn building"
end

-- ============================================================================
-- AI Cheats
-- ============================================================================

--[[
    Force AI to attack now.
]]
function Cheats.ai_attack_now()
    if not Cheats.enabled then return false, "Cheats disabled" end

    -- Find AI controller and trigger attack
    if Cheats.game and Cheats.game.ai_system then
        -- Reset attack timer to trigger immediate attack
        local controllers = Cheats.game.ai_system.controllers or {}
        for _, controller in pairs(controllers) do
            if controller.attack_timer then
                controller.attack_timer = controller.attack_interval or 9999
            end
        end
        return true, "AI attack triggered"
    end

    return false, "No AI system"
end

--[[
    Disable all AI.
]]
function Cheats.disable_ai()
    if not Cheats.enabled then return false, "Cheats disabled" end

    if Cheats.game and Cheats.game.ai_system then
        Cheats.game.ai_system.enabled = false
        return true, "AI disabled"
    end

    return false, "No AI system"
end

--[[
    Enable AI.
]]
function Cheats.enable_ai()
    if not Cheats.enabled then return false, "Cheats disabled" end

    if Cheats.game and Cheats.game.ai_system then
        Cheats.game.ai_system.enabled = true
        return true, "AI enabled"
    end

    return false, "No AI system"
end

-- ============================================================================
-- Mission Cheats
-- ============================================================================

--[[
    Win the current mission.
]]
function Cheats.win_mission()
    if not Cheats.enabled then return false, "Cheats disabled" end

    local Events = require("src.core.events")
    if Events and Cheats.game then
        Events.emit(Events.EVENTS.GAME_WIN, Cheats.game.player_house)
        return true, "Mission won"
    end

    return false, "Could not trigger win"
end

--[[
    Lose the current mission.
]]
function Cheats.lose_mission()
    if not Cheats.enabled then return false, "Cheats disabled" end

    local Events = require("src.core.events")
    if Events and Cheats.game then
        Events.emit(Events.EVENTS.GAME_LOSE, Cheats.game.player_house)
        return true, "Mission lost"
    end

    return false, "Could not trigger lose"
end

-- ============================================================================
-- Special Weapons Cheats
-- ============================================================================

--[[
    Grant all special weapons.
]]
function Cheats.grant_special_weapons()
    if not Cheats.enabled then return false, "Cheats disabled" end

    if Cheats.game and Cheats.game.special_weapons then
        local sw = Cheats.game.special_weapons
        if Cheats.game.player_house then
            sw:grant_weapon(Cheats.game.player_house, "ion_cannon")
            sw:grant_weapon(Cheats.game.player_house, "nuclear_strike")
            sw:grant_weapon(Cheats.game.player_house, "airstrike")
            sw:reset_cooldowns(Cheats.game.player_house)
            return true, "All special weapons granted"
        end
    end

    return false, "No special weapons system"
end

--[[
    Reset special weapon cooldowns.
]]
function Cheats.reset_weapon_cooldowns()
    if not Cheats.enabled then return false, "Cheats disabled" end

    if Cheats.game and Cheats.game.special_weapons then
        Cheats.game.special_weapons:reset_cooldowns(Cheats.game.player_house)
        return true, "Weapon cooldowns reset"
    end

    return false, "No special weapons system"
end

-- ============================================================================
-- Command Parser
-- ============================================================================

-- Command registry
Cheats.commands = {
    -- Credits
    credits = { fn = Cheats.add_credits, help = "Add 10000 credits (or specify amount)" },
    setcredits = { fn = Cheats.set_credits, help = "Set credits to amount" },
    money = { fn = function() return Cheats.add_credits(50000) end, help = "Add 50000 credits" },
    rich = { fn = function() return Cheats.set_credits(999999) end, help = "Set credits to 999999" },

    -- Combat
    god = { fn = Cheats.toggle_god_mode, help = "Toggle god mode (invulnerability)" },
    damage = { fn = Cheats.damage_selected, help = "Damage selected units" },
    kill = { fn = function() return Cheats.damage_selected(nil) end, help = "Kill selected units" },
    heal = { fn = Cheats.heal_selected, help = "Heal selected units" },

    -- Vision
    reveal = { fn = Cheats.reveal_all, help = "Reveal entire map" },
    fog = { fn = Cheats.toggle_fog, help = "Toggle fog of war" },

    -- Production
    instant = { fn = Cheats.toggle_instant_build, help = "Toggle instant build" },
    complete = { fn = Cheats.complete_production, help = "Complete all production" },

    -- AI
    aiattack = { fn = Cheats.ai_attack_now, help = "Force AI to attack" },
    noai = { fn = Cheats.disable_ai, help = "Disable AI" },
    ai = { fn = Cheats.enable_ai, help = "Enable AI" },

    -- Mission
    win = { fn = Cheats.win_mission, help = "Win current mission" },
    lose = { fn = Cheats.lose_mission, help = "Lose current mission" },

    -- Special weapons
    superweapons = { fn = Cheats.grant_special_weapons, help = "Grant all special weapons" },
    cooldown = { fn = Cheats.reset_weapon_cooldowns, help = "Reset weapon cooldowns" },

    -- Help
    help = { fn = function() return Cheats.show_help() end, help = "Show cheat commands" }
}

--[[
    Show help for all commands.
]]
function Cheats.show_help()
    local lines = {"Available cheat commands:"}
    for name, cmd in pairs(Cheats.commands) do
        table.insert(lines, string.format("  %-15s - %s", name, cmd.help))
    end
    return true, table.concat(lines, "\n")
end

--[[
    Execute a cheat command string.

    @param input - Command string (e.g., "credits 50000")
    @return success, message
]]
function Cheats.execute(input)
    if not Cheats.enabled then
        return false, "Cheats are disabled"
    end

    -- Parse command and arguments
    local parts = {}
    for part in input:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        return false, "No command specified"
    end

    local cmd_name = parts[1]:lower()
    local cmd = Cheats.commands[cmd_name]

    if not cmd then
        return false, "Unknown command: " .. cmd_name
    end

    -- Convert numeric arguments
    local args = {}
    for i = 2, #parts do
        local num = tonumber(parts[i])
        table.insert(args, num or parts[i])
    end

    -- Execute command
    return cmd.fn(table.unpack(args))
end

--[[
    Get current cheat status.
]]
function Cheats.get_status()
    return {
        enabled = Cheats.enabled,
        god_mode = Cheats.god_mode,
        instant_build = Cheats.instant_build,
        reveal_map = Cheats.reveal_map,
        unlimited_credits = Cheats.unlimited_credits,
        no_fog = Cheats.no_fog
    }
end

return Cheats
