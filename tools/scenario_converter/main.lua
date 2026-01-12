--[[
    Scenario Converter - Convert original C&C INI scenarios to JSON
    Usage: lua main.lua input.ini output.json
    Reference: Original C&C scenario format (SCENARIO.CPP)
]]

local INIParser = require("tools.scenario_converter.ini_parser")

-- JSON encoder (simple implementation)
local function encode_json(value, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    local t = type(value)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\')
                             :gsub('"', '\\"')
                             :gsub('\n', '\\n')
                             :gsub('\r', '\\r')
                             :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if array
        local is_array = #value > 0 or next(value) == nil
        if is_array then
            local items = {}
            for i, v in ipairs(value) do
                table.insert(items, encode_json(v, indent + 1))
            end
            if #items == 0 then
                return "[]"
            elseif #items <= 3 and not items[1]:find("\n") then
                return "[" .. table.concat(items, ", ") .. "]"
            else
                return "[\n" .. spacing .. "  " ..
                       table.concat(items, ",\n" .. spacing .. "  ") ..
                       "\n" .. spacing .. "]"
            end
        else
            local items = {}
            -- Sort keys for consistent output
            local keys = {}
            for k in pairs(value) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)

            for _, k in ipairs(keys) do
                local v = value[k]
                local key_str = encode_json(tostring(k))
                local val_str = encode_json(v, indent + 1)
                table.insert(items, key_str .. ": " .. val_str)
            end

            if #items == 0 then
                return "{}"
            else
                return "{\n" .. spacing .. "  " ..
                       table.concat(items, ",\n" .. spacing .. "  ") ..
                       "\n" .. spacing .. "}"
            end
        end
    else
        return '"' .. tostring(value) .. '"'
    end
end

-- Scenario converter
local ScenarioConverter = {}
ScenarioConverter.__index = ScenarioConverter

-- House name mapping
ScenarioConverter.HOUSE_MAP = {
    GoodGuy = "GDI",
    BadGuy = "Nod",
    Neutral = "Neutral",
    Special = "Special",
    Multi1 = "Multi1",
    Multi2 = "Multi2",
    Multi3 = "Multi3",
    Multi4 = "Multi4",
    Multi5 = "Multi5",
    Multi6 = "Multi6"
}

-- Trigger event types
ScenarioConverter.TRIGGER_EVENTS = {
    [0] = "none",
    [1] = "entered_by",
    [2] = "spied_by",
    [3] = "thieved_by",
    [4] = "discovered_by_player",
    [5] = "house_discovered",
    [6] = "attacked",
    [7] = "destroyed",
    [8] = "any_event",
    [9] = "all_destroyed",
    [10] = "all_units_destroyed",
    [11] = "all_buildings_destroyed",
    [12] = "credits_exceed",
    [13] = "time_elapsed",
    [14] = "mission_timer_expired",
    [15] = "no_factories",
    [16] = "civilian_evacuated",
    [17] = "build_building",
    [18] = "build_unit",
    [19] = "build_infantry",
    [20] = "build_aircraft",
    [21] = "nofires",
    [22] = "player_entered",
    [23] = "crosses_horizontal",
    [24] = "crosses_vertical",
    [25] = "global_set",
    [26] = "global_cleared",
    [27] = "destroyed_fakes_all",
    [28] = "low_power",
    [29] = "bridge_destroyed",
    [30] = "building_exists"
}

-- Trigger action types
ScenarioConverter.TRIGGER_ACTIONS = {
    [0] = "none",
    [1] = "winner",
    [2] = "loser",
    [3] = "production",
    [4] = "create_team",
    [5] = "destroy_team",
    [6] = "all_to_hunt",
    [7] = "reinforcement",
    [8] = "drop_zone_flare",
    [9] = "fire_sale",
    [10] = "play_movie",
    [11] = "text",
    [12] = "destroy_trigger",
    [13] = "autocreate",
    [14] = "win_lose_check",
    [15] = "force_trigger",
    [16] = "destroy_all",
    [17] = "ion_cannon_strike",
    [18] = "nuke_strike",
    [19] = "allow_win",
    [20] = "reveal_map",
    [21] = "reveal_zone",
    [22] = "play_sound",
    [23] = "play_music",
    [24] = "play_speech",
    [25] = "set_timer",
    [26] = "add_timer",
    [27] = "sub_timer",
    [28] = "set_global",
    [29] = "clear_global",
    [30] = "base_building",
    [31] = "airstrike"
}

function ScenarioConverter.new()
    local self = setmetatable({}, ScenarioConverter)
    self.parser = INIParser.new()
    return self
end

-- Convert INI scenario to JSON format
function ScenarioConverter:convert(ini_data)
    local scenario = {
        meta = {},
        map = {},
        houses = {},
        units = {},
        infantry = {},
        structures = {},
        terrain = {},
        overlays = {},
        smudge = {},
        waypoints = {},
        triggers = {},
        teams = {},
        celltriggers = {},
        base = {}
    }

    -- Parse Basic section
    self:parse_basic(ini_data, scenario)

    -- Parse Map section
    self:parse_map(ini_data, scenario)

    -- Parse houses
    self:parse_houses(ini_data, scenario)

    -- Parse units
    self:parse_units(ini_data, scenario)

    -- Parse infantry
    self:parse_infantry(ini_data, scenario)

    -- Parse structures
    self:parse_structures(ini_data, scenario)

    -- Parse terrain objects
    self:parse_terrain(ini_data, scenario)

    -- Parse overlays (tiberium, etc.)
    self:parse_overlays(ini_data, scenario)

    -- Parse smudge (craters, etc.)
    self:parse_smudge(ini_data, scenario)

    -- Parse waypoints
    self:parse_waypoints(ini_data, scenario)

    -- Parse triggers
    self:parse_triggers(ini_data, scenario)

    -- Parse teams
    self:parse_teams(ini_data, scenario)

    -- Parse cell triggers
    self:parse_celltriggers(ini_data, scenario)

    -- Parse base (AI base layout)
    self:parse_base(ini_data, scenario)

    return scenario
end

-- Parse [Basic] section
function ScenarioConverter:parse_basic(ini_data, scenario)
    local basic = ini_data.sections["Basic"] or {}

    scenario.meta = {
        name = basic.Name or "Unknown",
        brief = basic.Brief or "",
        win = basic.Win or "",
        lose = basic.Lose or "",
        action = basic.Action or "",
        player = self.HOUSE_MAP[basic.Player] or basic.Player or "GDI",
        theme = basic.Theme or "No Theme",
        carry_over_money = basic.CarryOverMoney or 0,
        build_level = basic.BuildLevel or 1,
        new_ini_format = basic.NewINIFormat or 0,
        percent = basic.Percent or 0,
        nospyplane = basic.NoSpyPlane or false,
        skip_score = basic.SkipScore or false,
        one_time_only = basic.OneTimeOnly or false,
        skip_mapselect = basic.SkipMapSelect or false,
        official = basic.Official or true,
        end_of_game = basic.EndOfGame or false,
        intro_movie = basic.Intro or "",
        win_movie = basic.Win or "",
        lose_movie = basic.Lose or "",
        action_movie = basic.Action or ""
    }
end

-- Parse [Map] section
function ScenarioConverter:parse_map(ini_data, scenario)
    local map_section = ini_data.sections["Map"] or {}

    scenario.map = {
        theater = map_section.Theater or "TEMPERATE",
        x = map_section.X or 0,
        y = map_section.Y or 0,
        width = map_section.Width or 64,
        height = map_section.Height or 64
    }

    -- Parse MapPack if exists (terrain data)
    local mappack = ini_data.sections["MapPack"]
    if mappack then
        scenario.map.packed_terrain = mappack
    end
end

-- Parse house sections
function ScenarioConverter:parse_houses(ini_data, scenario)
    local house_names = {"GoodGuy", "BadGuy", "Neutral", "Special",
                         "Multi1", "Multi2", "Multi3", "Multi4", "Multi5", "Multi6"}

    for _, house_name in ipairs(house_names) do
        local house_data = ini_data.sections[house_name]
        if house_data then
            local mapped_name = self.HOUSE_MAP[house_name] or house_name
            scenario.houses[mapped_name] = {
                allies = house_data.Allies,
                credits = house_data.Credits or 0,
                edge = house_data.Edge,
                max_unit = house_data.MaxUnit or 0,
                max_building = house_data.MaxBuilding or 0,
                max_infantry = house_data.MaxInfantry or 0,
                max_vessel = house_data.MaxVessel or 0,
                iq = house_data.IQ or 0,
                tech_level = house_data.TechLevel or 1,
                player_control = house_data.PlayerControl or false
            }
        end
    end
end

-- Parse [UNITS] section
function ScenarioConverter:parse_units(ini_data, scenario)
    local units_section = ini_data.sections["UNITS"] or {}

    for key, value in pairs(units_section) do
        if type(value) == "table" and #value >= 6 then
            local unit = {
                id = key,
                owner = self.HOUSE_MAP[value[1]] or value[1],
                type = value[2],
                health = tonumber(value[3]) or 256,
                cell = tonumber(value[4]),
                facing = tonumber(value[5]) or 0,
                mission = value[6] or "Guard",
                trigger = value[7]
            }

            -- Convert cell to x, y
            if unit.cell then
                unit.x = unit.cell % (scenario.map.width or 64)
                unit.y = math.floor(unit.cell / (scenario.map.width or 64))
            end

            table.insert(scenario.units, unit)
        end
    end
end

-- Parse [INFANTRY] section
function ScenarioConverter:parse_infantry(ini_data, scenario)
    local infantry_section = ini_data.sections["INFANTRY"] or {}

    for key, value in pairs(infantry_section) do
        if type(value) == "table" and #value >= 7 then
            local infantry = {
                id = key,
                owner = self.HOUSE_MAP[value[1]] or value[1],
                type = value[2],
                health = tonumber(value[3]) or 256,
                cell = tonumber(value[4]),
                sub_cell = tonumber(value[5]) or 0,
                mission = value[6] or "Guard",
                facing = tonumber(value[7]) or 0,
                trigger = value[8]
            }

            -- Convert cell to x, y
            if infantry.cell then
                infantry.x = infantry.cell % (scenario.map.width or 64)
                infantry.y = math.floor(infantry.cell / (scenario.map.width or 64))
            end

            table.insert(scenario.infantry, infantry)
        end
    end
end

-- Parse [STRUCTURES] section
function ScenarioConverter:parse_structures(ini_data, scenario)
    local structures_section = ini_data.sections["STRUCTURES"] or {}

    for key, value in pairs(structures_section) do
        if type(value) == "table" and #value >= 5 then
            local structure = {
                id = key,
                owner = self.HOUSE_MAP[value[1]] or value[1],
                type = value[2],
                health = tonumber(value[3]) or 256,
                cell = tonumber(value[4]),
                facing = tonumber(value[5]) or 0,
                trigger = value[6],
                sellable = value[7] ~= 0,
                rebuild = value[8] == 1
            }

            -- Convert cell to x, y
            if structure.cell then
                structure.x = structure.cell % (scenario.map.width or 64)
                structure.y = math.floor(structure.cell / (scenario.map.width or 64))
            end

            table.insert(scenario.structures, structure)
        end
    end
end

-- Parse [TERRAIN] section
function ScenarioConverter:parse_terrain(ini_data, scenario)
    local terrain_section = ini_data.sections["TERRAIN"] or {}

    for cell_str, terrain_type in pairs(terrain_section) do
        local cell = tonumber(cell_str)
        if cell and terrain_type then
            local terrain = {
                type = terrain_type,
                cell = cell,
                x = cell % (scenario.map.width or 64),
                y = math.floor(cell / (scenario.map.width or 64))
            }
            table.insert(scenario.terrain, terrain)
        end
    end
end

-- Parse [OVERLAY] section
function ScenarioConverter:parse_overlays(ini_data, scenario)
    local overlay_section = ini_data.sections["OVERLAY"] or {}

    for cell_str, overlay_type in pairs(overlay_section) do
        local cell = tonumber(cell_str)
        if cell and overlay_type then
            local overlay = {
                type = overlay_type,
                cell = cell,
                x = cell % (scenario.map.width or 64),
                y = math.floor(cell / (scenario.map.width or 64))
            }
            table.insert(scenario.overlays, overlay)
        end
    end
end

-- Parse [SMUDGE] section
function ScenarioConverter:parse_smudge(ini_data, scenario)
    local smudge_section = ini_data.sections["SMUDGE"] or {}

    for cell_str, smudge_type in pairs(smudge_section) do
        local cell = tonumber(cell_str)
        if cell and smudge_type then
            local smudge = {
                type = smudge_type,
                cell = cell,
                x = cell % (scenario.map.width or 64),
                y = math.floor(cell / (scenario.map.width or 64))
            }
            table.insert(scenario.smudge, smudge)
        end
    end
end

-- Parse [Waypoints] section
function ScenarioConverter:parse_waypoints(ini_data, scenario)
    local waypoints_section = ini_data.sections["Waypoints"] or {}

    for wp_num, cell in pairs(waypoints_section) do
        local num = tonumber(wp_num)
        local cell_num = tonumber(cell)
        if num and cell_num then
            local waypoint = {
                id = num,
                cell = cell_num,
                x = cell_num % (scenario.map.width or 64),
                y = math.floor(cell_num / (scenario.map.width or 64))
            }

            -- Special waypoints
            if num == 98 then
                waypoint.name = "player_start"
            elseif num == 99 then
                waypoint.name = "enemy_start"
            end

            table.insert(scenario.waypoints, waypoint)
        end
    end
end

-- Parse [Triggers] section
function ScenarioConverter:parse_triggers(ini_data, scenario)
    local triggers_section = ini_data.sections["Triggers"] or {}

    for name, value in pairs(triggers_section) do
        if type(value) == "table" and #value >= 5 then
            local trigger = {
                name = name,
                persistent = value[1] == 1 or value[1] == 2,
                semi_persistent = value[1] == 2,
                house = self.HOUSE_MAP[value[2]] or value[2],
                event_type = self.TRIGGER_EVENTS[tonumber(value[3])] or value[3],
                event_param = tonumber(value[4]) or 0,
                action_type = self.TRIGGER_ACTIONS[tonumber(value[5])] or value[5],
                action_param = value[6]
            }
            table.insert(scenario.triggers, trigger)
        end
    end
end

-- Parse [TeamTypes] section
function ScenarioConverter:parse_teams(ini_data, scenario)
    local teams_section = ini_data.sections["TeamTypes"] or {}

    for name, value in pairs(teams_section) do
        if type(value) == "table" then
            local team = {
                name = name,
                house = self.HOUSE_MAP[value[1]] or value[1],
                priority = tonumber(value[2]) or 0,
                max = tonumber(value[3]) or 0,
                num = tonumber(value[4]) or 0,
                fear = tonumber(value[5]) or 0,
                waypoint = tonumber(value[6]),
                trigger = value[7],
                options = {}
            }

            -- Parse team composition and orders (complex format)
            -- This is simplified - full implementation would parse all fields
            table.insert(scenario.teams, team)
        end
    end
end

-- Parse [CellTriggers] section
function ScenarioConverter:parse_celltriggers(ini_data, scenario)
    local celltriggers_section = ini_data.sections["CellTriggers"] or {}

    for cell_str, trigger_name in pairs(celltriggers_section) do
        local cell = tonumber(cell_str)
        if cell and trigger_name then
            local celltrigger = {
                cell = cell,
                trigger = trigger_name,
                x = cell % (scenario.map.width or 64),
                y = math.floor(cell / (scenario.map.width or 64))
            }
            table.insert(scenario.celltriggers, celltrigger)
        end
    end
end

-- Parse [Base] section (AI base layout)
function ScenarioConverter:parse_base(ini_data, scenario)
    local base_section = ini_data.sections["Base"] or {}

    scenario.base = {
        count = tonumber(base_section.Count) or 0,
        player = base_section.Player,
        buildings = {}
    }

    -- Parse building entries (001, 002, etc.)
    for key, value in pairs(base_section) do
        local num = tonumber(key)
        if num and type(value) == "table" then
            table.insert(scenario.base.buildings, {
                priority = num,
                type = value[1],
                cell = tonumber(value[2])
            })
        end
    end
end

-- Convert file
function ScenarioConverter:convert_file(input_path, output_path)
    local ini_data, err = self.parser:parse_file(input_path)
    if not ini_data then
        return false, err
    end

    local scenario = self:convert(ini_data)
    local json = encode_json(scenario)

    local file = io.open(output_path, "w")
    if not file then
        return false, "Could not write to: " .. output_path
    end

    file:write(json)
    file:close()

    return true
end

-- Main function for command line usage
local function main()
    local args = {...}

    if #args < 2 then
        print("Usage: lua main.lua <input.ini> <output.json>")
        print("")
        print("Converts Command & Conquer scenario INI files to JSON format")
        print("")
        print("Example:")
        print("  lua main.lua SCG01EA.INI gdi01.json")
        return
    end

    local input_path = args[1]
    local output_path = args[2]

    local converter = ScenarioConverter.new()
    local success, err = converter:convert_file(input_path, output_path)

    if success then
        print("Successfully converted " .. input_path .. " to " .. output_path)
    else
        print("Error: " .. (err or "Unknown error"))
    end
end

-- Export for module usage
return {
    INIParser = INIParser,
    ScenarioConverter = ScenarioConverter,
    main = main
}
