--[[
    Load System - Game state deserialization

    This module handles loading saved game state from disk.
    It follows the original C&C load pattern:

    1. Read file and deserialize
    2. Validate version and integrity
    3. Reconstruct all objects
    4. Call Decode_Pointers() to convert indices back to references

    Reference: SAVELOAD.CPP from original C&C source
]]

local json = require("lib.json") -- Or use love.filesystem for JSON
local Pointers = require("src.io.pointers")
local Random = require("src.core.random")

local Load = {}

--============================================================================
-- Constants (must match save.lua)
--============================================================================

Load.VERSION = 1
Load.MAGIC = "CNCTD"

--============================================================================
-- Load State
--============================================================================

--[[
    Load a game state from file.

    @param filename Save file path
    @return Table containing loaded game state, or nil on failure
]]
function Load.load_game(filename)
    -- Read file
    local file_content, err
    if love and love.filesystem then
        file_content, err = love.filesystem.read(filename)
    else
        local f = io.open(filename, "r")
        if f then
            file_content = f:read("*all")
            f:close()
        else
            err = "Could not open file for reading"
        end
    end

    if not file_content then
        print("Load: File read failed: " .. tostring(err))
        return nil
    end

    -- Parse JSON
    local save_data
    local success, result = pcall(function()
        if json and json.decode then
            return json.decode(file_content)
        else
            -- Fallback: try loading as Lua
            return Load.deserialize(file_content)
        end
    end)

    if not success then
        print("Load: JSON decoding failed: " .. tostring(result))
        return nil
    end

    save_data = result

    -- Validate header
    if not Load.validate_header(save_data) then
        return nil
    end

    -- Restore random state FIRST (critical for determinism)
    if save_data.random_seed then
        Random.Set_Seed(save_data.random_seed)
    end

    -- Reconstruct game state
    local game_state = {
        frame = save_data.frame or 0,
        scenario = Load.load_scenario(save_data.scenario),
        houses = {},
        units = {},
        infantry = {},
        buildings = {},
        aircraft = {},
        bullets = {},
        anims = {},
        triggers = {},
        teams = {},
        map = nil,
        session = nil,
    }

    -- Load houses first (they're referenced by objects)
    game_state.houses = Load.load_houses(save_data.houses)

    -- Register houses with Pointers system
    Pointers.register_heap(Pointers.RTTI.HOUSE, game_state.houses)

    -- Load all objects
    if save_data.objects then
        game_state.units = Load.load_object_list(save_data.objects.units, "unit")
        game_state.infantry = Load.load_object_list(save_data.objects.infantry, "infantry")
        game_state.buildings = Load.load_object_list(save_data.objects.buildings, "building")
        game_state.aircraft = Load.load_object_list(save_data.objects.aircraft, "aircraft")
        game_state.bullets = Load.load_object_list(save_data.objects.bullets, "bullet")
        game_state.anims = Load.load_object_list(save_data.objects.anims, "anim")
    end

    -- Register object heaps with Pointers system
    Pointers.register_heap(Pointers.RTTI.UNIT, game_state.units)
    Pointers.register_heap(Pointers.RTTI.INFANTRY, game_state.infantry)
    Pointers.register_heap(Pointers.RTTI.BUILDING, game_state.buildings)
    Pointers.register_heap(Pointers.RTTI.AIRCRAFT, game_state.aircraft)
    Pointers.register_heap(Pointers.RTTI.BULLET, game_state.bullets)
    Pointers.register_heap(Pointers.RTTI.ANIM, game_state.anims)

    -- Load map
    game_state.map = Load.load_map(save_data.map)

    -- Load triggers and teams
    game_state.triggers = Load.load_triggers(save_data.triggers)
    game_state.teams = Load.load_teams(save_data.teams)

    Pointers.register_heap(Pointers.RTTI.TRIGGER, game_state.triggers)
    Pointers.register_heap(Pointers.RTTI.TEAM, game_state.teams)

    -- Load session info
    game_state.session = Load.load_session(save_data.session)

    -- Decode all pointers (convert indices back to references)
    game_state = Pointers.decode_all(game_state)

    -- Post-load: call Decode_Pointers on objects that need it
    Load.post_load_decode(game_state)

    print(string.format("Load: Game loaded from %s (frame %d)", filename, game_state.frame))
    return game_state
end

--============================================================================
-- Validation
--============================================================================

--[[
    Validate save file header.
]]
function Load.validate_header(save_data)
    if not save_data then
        print("Load: No save data")
        return false
    end

    if save_data.magic ~= Load.MAGIC then
        print(string.format("Load: Invalid magic header: %s (expected %s)",
            tostring(save_data.magic), Load.MAGIC))
        return false
    end

    if save_data.version ~= Load.VERSION then
        print(string.format("Load: Version mismatch: %d (expected %d)",
            save_data.version or 0, Load.VERSION))
        -- Could implement version migration here
        return false
    end

    return true
end

--============================================================================
-- Component Loaders
--============================================================================

--[[
    Load scenario info.
]]
function Load.load_scenario(data)
    if not data then return nil end

    return {
        name = data.name,
        theater = data.theater,
        win_condition = data.win_condition,
        lose_condition = data.lose_condition,
        brief = data.brief,
    }
end

--[[
    Load all houses.
]]
function Load.load_houses(data)
    if not data then return {} end

    local houses = {}
    for i, house_data in ipairs(data) do
        houses[i] = Load.load_house(house_data)
    end
    return houses
end

--[[
    Load a single house.
]]
function Load.load_house(data)
    if not data then return nil end

    -- Try to use HouseClass if available
    local HouseClass = package.loaded["src.house.house"]
    if HouseClass and HouseClass.deserialize then
        return HouseClass.deserialize(data)
    end

    -- Basic reconstruction
    return {
        type = data.type,
        name = data.name,
        side = data.side,
        credits = data.credits,
        power_output = data.power_output,
        power_drain = data.power_drain,
        tech_level = data.tech_level,
        is_defeated = data.is_defeated,
        is_player = data.is_player,
        is_human = data.is_human,
        stats = data.stats or {},
        special_weapons = data.special_weapons or {},
    }
end

--[[
    Load a list of game objects.
]]
function Load.load_object_list(data, object_type)
    if not data then return {} end

    local objects = {}
    for i, obj_data in ipairs(data) do
        objects[i] = Load.load_object(obj_data, object_type)
    end
    return objects
end

--[[
    Load a single game object.
]]
function Load.load_object(data, object_type)
    if not data then return nil end

    -- Try to find the appropriate class
    local class_map = {
        unit = "src.objects.unit",
        infantry = "src.objects.infantry",
        building = "src.objects.building",
        aircraft = "src.objects.aircraft",
        bullet = "src.objects.bullet",
        anim = "src.objects.anim",
    }

    local class_path = class_map[object_type]
    if class_path then
        local Class = package.loaded[class_path]
        if Class and Class.deserialize then
            return Class.deserialize(data)
        end
    end

    -- Basic object reconstruction
    local obj = {
        -- AbstractClass
        Coord = data.coord,
        IsActive = data.is_active,

        -- ObjectClass
        IsDown = data.is_down,
        IsInLimbo = data.is_in_limbo,
        IsSelected = data.is_selected,
        Strength = data.strength,

        -- MissionClass
        Mission = data.mission,
        SuspendedMission = data.suspended_mission,
        Timer = data.mission_timer,

        -- TechnoClass
        House = data.house,  -- Will be decoded as pointer
        TarCom = data.tarcom,
        PrimaryFacing = data.facing,
        Arm = data.arm,
        Ammo = data.ammo,
        CloakState = data.cloak_state,

        -- FootClass
        NavCom = data.navcom,
        Path = data.path,
        Group = data.group,

        -- Type info
        _class_name = data.class_name,
    }

    return obj
end

--[[
    Load map state.
]]
function Load.load_map(data)
    if not data then return nil end

    local map = {
        width = data.width,
        height = data.height,
        cells = {},
    }

    -- Load cells
    if data.cells then
        for y = 1, map.height do
            map.cells[y] = {}
            for x = 1, map.width do
                if data.cells[y] and data.cells[y][x] then
                    map.cells[y][x] = Load.load_cell(data.cells[y][x])
                end
            end
        end
    end

    -- Add cell access method
    function map:get_cell(x, y)
        if self.cells[y] then
            return self.cells[y][x]
        end
        return nil
    end

    return map
end

--[[
    Load cell state.
]]
function Load.load_cell(data)
    if not data then return nil end

    return {
        Template = data.template,
        Icon = data.icon,
        Overlay = data.overlay,
        OverlayData = data.overlay_data,
        Smudge = data.smudge,
        SmudgeData = data.smudge_data,
        Flag = data.flag,
    }
end

--[[
    Load triggers.
]]
function Load.load_triggers(data)
    if not data then return {} end

    local triggers = {}
    for i, trig_data in ipairs(data) do
        triggers[i] = {
            name = trig_data.name,
            event_type = trig_data.event_type,
            action_type = trig_data.action_type,
            house = trig_data.house,
            data = trig_data.data,
            persistence = trig_data.persistence,
            enabled = trig_data.enabled,
            triggered = trig_data.triggered,
        }
    end
    return triggers
end

--[[
    Load teams.
]]
function Load.load_teams(data)
    if not data then return {} end

    local teams = {}
    for id, team_data in pairs(data) do
        teams[id] = {
            type_name = team_data.type_name,
            house = team_data.house,
            mission = team_data.mission,
            members = team_data.members,
            current_waypoint = team_data.current_waypoint,
            formed = team_data.formed,
        }
    end
    return teams
end

--[[
    Load session state.
]]
function Load.load_session(data)
    if not data then return nil end

    return {
        Type = data.type,
        NumPlayers = data.num_players,
        MaxAhead = data.max_ahead,
        FrameSendRate = data.frame_send_rate,
        Options = data.options,
    }
end

--============================================================================
-- Post-Load Processing
--============================================================================

--[[
    Call Decode_Pointers on all objects that need it.
    This is the second pass after basic deserialization.
]]
function Load.post_load_decode(game_state)
    -- Call Decode_Pointers on objects that implement it
    local object_lists = {
        game_state.units,
        game_state.infantry,
        game_state.buildings,
        game_state.aircraft,
        game_state.bullets,
        game_state.anims,
    }

    for _, list in ipairs(object_lists) do
        if list then
            for _, obj in ipairs(list) do
                if obj and obj.Decode_Pointers then
                    obj:Decode_Pointers()
                end
            end
        end
    end

    -- Decode pointers for houses
    if game_state.houses then
        for _, house in ipairs(game_state.houses) do
            if house and house.Decode_Pointers then
                house:Decode_Pointers()
            end
        end
    end
end

--============================================================================
-- Simple Deserialization (fallback if no JSON library)
--============================================================================

--[[
    Deserialize Lua-format save data.
]]
function Load.deserialize(str)
    -- Try to load as Lua code
    local chunk, err = loadstring("return " .. str)
    if not chunk then
        error("Failed to parse save data: " .. tostring(err))
    end

    -- Execute in sandbox
    setfenv(chunk, {})
    return chunk()
end

--============================================================================
-- Debug
--============================================================================

function Load.Debug_Dump()
    print("Load System:")
    print(string.format("  Version: %d", Load.VERSION))
    print(string.format("  Magic: %s", Load.MAGIC))
end

return Load
