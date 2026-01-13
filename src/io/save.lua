--[[
    Save System - Game state serialization

    This module handles saving the complete game state to disk.
    It follows the original C&C save pattern:

    1. Call Code_Pointers() on all objects to convert references to indices
    2. Serialize all object data
    3. Write to file with version header

    Reference: SAVELOAD.CPP from original C&C source
]]

local json = require("lib.json") -- Or use love.filesystem for JSON
local Pointers = require("src.io.pointers")
local Random = require("src.core.random")

local Save = {}

--============================================================================
-- Constants
--============================================================================

-- Save file version for compatibility checking
Save.VERSION = 1
Save.MAGIC = "CNCTD"  -- Magic header to identify our save files

--============================================================================
-- Save State
--============================================================================

--[[
    Save the complete game state to a file.

    @param filename Save file path
    @param game_state Table containing all game state
    @return true on success, false on failure
]]
function Save.save_game(filename, game_state)
    local save_data = {
        -- Header
        magic = Save.MAGIC,
        version = Save.VERSION,
        timestamp = os.time(),

        -- Random state (critical for replay sync)
        random_seed = Random.Get_Seed(),

        -- Game frame
        frame = game_state.frame or 0,

        -- Scenario info
        scenario = Save.save_scenario(game_state.scenario),

        -- Houses
        houses = Save.save_houses(game_state.houses),

        -- All game objects
        objects = Save.save_objects(game_state),

        -- Map state
        map = Save.save_map(game_state.map),

        -- Triggers and teams
        triggers = Save.save_triggers(game_state.triggers),
        teams = Save.save_teams(game_state.teams),

        -- Session info (for multiplayer)
        session = Save.save_session(game_state.session),
    }

    -- Encode all object references to indices
    save_data = Pointers.code_all(save_data)

    -- Serialize to JSON
    local success, json_str = pcall(function()
        -- Use a JSON library or love.filesystem
        if json and json.encode then
            return json.encode(save_data)
        else
            -- Fallback: simple serialization
            return Save.serialize(save_data)
        end
    end)

    if not success then
        print("Save: JSON encoding failed: " .. tostring(json_str))
        return false
    end

    -- Write to file
    local file_success, err
    if love and love.filesystem then
        file_success, err = love.filesystem.write(filename, json_str)
    else
        local f = io.open(filename, "w")
        if f then
            f:write(json_str)
            f:close()
            file_success = true
        else
            file_success = false
            err = "Could not open file for writing"
        end
    end

    if not file_success then
        print("Save: File write failed: " .. tostring(err))
        return false
    end

    print(string.format("Save: Game saved to %s (frame %d)", filename, save_data.frame))
    return true
end

--============================================================================
-- Component Serializers
--============================================================================

--[[
    Save scenario state.
]]
function Save.save_scenario(scenario)
    if not scenario then return nil end

    return {
        name = scenario.name,
        theater = scenario.theater,
        win_condition = scenario.win_condition,
        lose_condition = scenario.lose_condition,
        brief = scenario.brief,
        -- Don't save full map data here, just reference
    }
end

--[[
    Save all houses.
]]
function Save.save_houses(houses)
    if not houses then return {} end

    local result = {}
    for i, house in ipairs(houses) do
        if house and house.serialize then
            result[i] = house:serialize()
        elseif house then
            result[i] = Save.save_house(house)
        end
    end
    return result
end

--[[
    Save a single house.
]]
function Save.save_house(house)
    return {
        type = house.type,
        name = house.name,
        side = house.side,
        credits = house.credits,
        power_output = house.power_output,
        power_drain = house.power_drain,
        tech_level = house.tech_level,
        is_defeated = house.is_defeated,
        is_player = house.is_player,
        is_human = house.is_human,
        stats = house.stats,
        special_weapons = house.special_weapons,
        -- Object references will be encoded by Pointers.code_all
    }
end

--[[
    Save all game objects (units, buildings, infantry, etc.)
]]
function Save.save_objects(game_state)
    local objects = {
        units = {},
        infantry = {},
        buildings = {},
        aircraft = {},
        bullets = {},
        anims = {},
        terrain = {},
        overlays = {},
        smudges = {},
    }

    -- Save each object type
    if game_state.units then
        for i, obj in ipairs(game_state.units) do
            objects.units[i] = Save.save_object(obj)
        end
    end

    if game_state.infantry then
        for i, obj in ipairs(game_state.infantry) do
            objects.infantry[i] = Save.save_object(obj)
        end
    end

    if game_state.buildings then
        for i, obj in ipairs(game_state.buildings) do
            objects.buildings[i] = Save.save_object(obj)
        end
    end

    if game_state.aircraft then
        for i, obj in ipairs(game_state.aircraft) do
            objects.aircraft[i] = Save.save_object(obj)
        end
    end

    if game_state.bullets then
        for i, obj in ipairs(game_state.bullets) do
            objects.bullets[i] = Save.save_object(obj)
        end
    end

    if game_state.anims then
        for i, obj in ipairs(game_state.anims) do
            objects.anims[i] = Save.save_object(obj)
        end
    end

    return objects
end

--[[
    Save a single game object.
    Objects with serialize() method use that; otherwise extract common fields.
]]
function Save.save_object(obj)
    if obj == nil then return nil end

    -- Use object's own serialize method if available
    if obj.serialize then
        return obj:serialize()
    end

    -- Generic serialization
    local data = {}

    -- AbstractClass fields
    data.coord = obj.Coord
    data.is_active = obj.IsActive

    -- ObjectClass fields
    data.is_down = obj.IsDown
    data.is_in_limbo = obj.IsInLimbo
    data.is_selected = obj.IsSelected
    data.strength = obj.Strength

    -- MissionClass fields
    data.mission = obj.Mission
    data.suspended_mission = obj.SuspendedMission
    data.mission_timer = obj.Timer

    -- TechnoClass fields
    data.house = obj.House  -- Will be encoded as pointer
    data.tarcom = obj.TarCom
    data.facing = obj.PrimaryFacing
    data.arm = obj.Arm
    data.ammo = obj.Ammo
    data.cloak_state = obj.CloakState

    -- FootClass fields (if applicable)
    data.navcom = obj.NavCom
    data.path = obj.Path
    data.group = obj.Group

    -- Type reference (by name for stability)
    if obj.Class then
        data.class_name = obj.Class.Name or obj.Class.ID
    end

    return data
end

--[[
    Save map state (cell data, shroud, etc.)
]]
function Save.save_map(map)
    if not map then return nil end

    local data = {
        width = map.width,
        height = map.height,
        cells = {},
    }

    -- Save each cell's state
    if map.cells then
        for y = 1, map.height do
            data.cells[y] = {}
            for x = 1, map.width do
                local cell = map:get_cell(x, y)
                if cell then
                    data.cells[y][x] = Save.save_cell(cell)
                end
            end
        end
    end

    return data
end

--[[
    Save cell state.
]]
function Save.save_cell(cell)
    if not cell then return nil end

    return {
        template = cell.Template,
        icon = cell.Icon,
        overlay = cell.Overlay,
        overlay_data = cell.OverlayData,
        smudge = cell.Smudge,
        smudge_data = cell.SmudgeData,
        flag = cell.Flag,
        -- Occupancy will be reconstructed from objects
    }
end

--[[
    Save triggers.
]]
function Save.save_triggers(triggers)
    if not triggers then return {} end

    local result = {}
    for i, trigger in ipairs(triggers) do
        if trigger then
            result[i] = {
                name = trigger.name,
                event_type = trigger.event_type,
                action_type = trigger.action_type,
                house = trigger.house,
                data = trigger.data,
                persistence = trigger.persistence,
                enabled = trigger.enabled,
                triggered = trigger.triggered,
            }
        end
    end
    return result
end

--[[
    Save teams.
]]
function Save.save_teams(teams)
    if not teams then return {} end

    local result = {}
    for id, team in pairs(teams) do
        result[id] = {
            type_name = team.type_name,
            house = team.house,
            mission = team.mission,
            members = team.members,  -- Will be encoded as pointers
            current_waypoint = team.current_waypoint,
            formed = team.formed,
        }
    end
    return result
end

--[[
    Save session state (multiplayer info).
]]
function Save.save_session(session)
    if not session then return nil end

    return {
        type = session.Type,
        num_players = session.NumPlayers,
        max_ahead = session.MaxAhead,
        frame_send_rate = session.FrameSendRate,
        options = session.Options,
    }
end

--============================================================================
-- Simple Serialization (fallback if no JSON library)
--============================================================================

--[[
    Simple table serialization to Lua-readable format.
]]
function Save.serialize(data, indent)
    indent = indent or 0
    local padding = string.rep("  ", indent)

    if type(data) == "nil" then
        return "nil"
    elseif type(data) == "boolean" then
        return tostring(data)
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "string" then
        return string.format("%q", data)
    elseif type(data) == "table" then
        local parts = {}
        local is_array = #data > 0

        table.insert(parts, "{\n")

        if is_array then
            for i, v in ipairs(data) do
                table.insert(parts, padding .. "  " .. Save.serialize(v, indent + 1) .. ",\n")
            end
        else
            for k, v in pairs(data) do
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k
                else
                    key = "[" .. Save.serialize(k, 0) .. "]"
                end
                table.insert(parts, padding .. "  " .. key .. " = " .. Save.serialize(v, indent + 1) .. ",\n")
            end
        end

        table.insert(parts, padding .. "}")
        return table.concat(parts)
    else
        return "nil -- unsupported type: " .. type(data)
    end
end

--============================================================================
-- Quick Save
--============================================================================

--[[
    Create a quick save with auto-generated filename.
]]
function Save.quick_save(game_state)
    local filename = string.format("quicksave_%d.sav", os.time())
    return Save.save_game(filename, game_state)
end

--============================================================================
-- Debug
--============================================================================

function Save.Debug_Dump()
    print("Save System:")
    print(string.format("  Version: %d", Save.VERSION))
    print(string.format("  Magic: %s", Save.MAGIC))
end

return Save
