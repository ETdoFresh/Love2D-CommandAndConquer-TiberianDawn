--[[
    Scenario Loader - Load and initialize scenario data
    Handles INI and JSON format scenarios
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")

local ScenarioLoader = {}
ScenarioLoader.__index = ScenarioLoader

function ScenarioLoader.new(world, grid, production_system)
    local self = setmetatable({}, ScenarioLoader)

    self.world = world
    self.grid = grid
    self.production_system = production_system

    -- Current scenario data
    self.scenario = nil

    return self
end

-- Load scenario from JSON file
function ScenarioLoader:load_json(filepath)
    local file = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    local content = file:read("*all")
    file:close()

    -- Parse JSON (simple parser)
    local ok, data = pcall(function()
        return self:parse_json(content)
    end)

    if not ok then
        return nil, "JSON parse error: " .. tostring(data)
    end

    return self:load_scenario_data(data)
end

-- Load scenario from INI file (original C&C format)
function ScenarioLoader:load_ini(filepath)
    local file = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    local content = file:read("*all")
    file:close()

    local data = self:parse_ini(content)
    return self:load_scenario_data(data)
end

-- Parse INI format
function ScenarioLoader:parse_ini(content)
    local data = {}
    local current_section = nil

    for line in content:gmatch("[^\r\n]+") do
        -- Remove comments and trim
        line = line:gsub(";.*", ""):match("^%s*(.-)%s*$")

        if #line > 0 then
            -- Check for section header
            local section = line:match("^%[(.-)%]$")
            if section then
                current_section = section
                data[current_section] = data[current_section] or {}
            elseif current_section then
                -- Parse key=value
                local key, value = line:match("^([^=]+)=(.*)$")
                if key and value then
                    key = key:match("^%s*(.-)%s*$")
                    value = value:match("^%s*(.-)%s*$")
                    data[current_section][key] = value
                end
            end
        end
    end

    return self:convert_ini_to_scenario(data)
end

-- Convert INI sections to scenario data format
function ScenarioLoader:convert_ini_to_scenario(ini)
    local scenario = {
        name = "Untitled",
        theater = "TEMPERATE",
        map_width = 64,
        map_height = 64,
        houses = {},
        structures = {},
        units = {},
        infantry = {},
        triggers = {},
        teams = {},
        waypoints = {},
        cell_triggers = {}
    }

    -- Basic info
    if ini.Basic then
        scenario.name = ini.Basic.Name or scenario.name
        scenario.intro = ini.Basic.Intro
        scenario.brief = ini.Basic.Brief
        scenario.win_movie = ini.Basic.Win
        scenario.lose_movie = ini.Basic.Lose
        scenario.player = ini.Basic.Player or "GoodGuy"
        scenario.build_level = tonumber(ini.Basic.BuildLevel) or 99
    end

    -- Map info
    if ini.Map then
        scenario.theater = ini.Map.Theater or scenario.theater
        scenario.map_x = tonumber(ini.Map.X) or 0
        scenario.map_y = tonumber(ini.Map.Y) or 0
        scenario.map_width = tonumber(ini.Map.Width) or 64
        scenario.map_height = tonumber(ini.Map.Height) or 64
    end

    -- Houses
    for house_name, _ in pairs({GoodGuy = true, BadGuy = true, Neutral = true,
                                 Special = true, Multi1 = true, Multi2 = true,
                                 Multi3 = true, Multi4 = true}) do
        if ini[house_name] then
            local house_data = ini[house_name]
            scenario.houses[house_name] = {
                credits = tonumber(house_data.Credits) or 0,
                edge = house_data.Edge or "North",
                max_unit = tonumber(house_data.MaxUnit) or 150,
                max_building = tonumber(house_data.MaxBuilding) or 150
            }
        end
    end

    -- Structures
    if ini.STRUCTURES then
        for key, value in pairs(ini.STRUCTURES) do
            local parts = {}
            for part in value:gmatch("[^,]+") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end

            if #parts >= 5 then
                local cell = tonumber(parts[4]) or 0
                table.insert(scenario.structures, {
                    house = parts[1],
                    type = parts[2],
                    health = tonumber(parts[3]) or 256,
                    cell_x = cell % 64,
                    cell_y = math.floor(cell / 64),
                    facing = tonumber(parts[5]) or 0,
                    trigger = parts[6]
                })
            end
        end
    end

    -- Units
    if ini.UNITS then
        for key, value in pairs(ini.UNITS) do
            local parts = {}
            for part in value:gmatch("[^,]+") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end

            if #parts >= 6 then
                local cell = tonumber(parts[4]) or 0
                table.insert(scenario.units, {
                    house = parts[1],
                    type = parts[2],
                    health = tonumber(parts[3]) or 256,
                    cell_x = cell % 64,
                    cell_y = math.floor(cell / 64),
                    facing = tonumber(parts[5]) or 0,
                    mission = parts[6],
                    trigger = parts[7]
                })
            end
        end
    end

    -- Infantry
    if ini.INFANTRY then
        for key, value in pairs(ini.INFANTRY) do
            local parts = {}
            for part in value:gmatch("[^,]+") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end

            if #parts >= 7 then
                local cell = tonumber(parts[4]) or 0
                table.insert(scenario.infantry, {
                    house = parts[1],
                    type = parts[2],
                    health = tonumber(parts[3]) or 256,
                    cell_x = cell % 64,
                    cell_y = math.floor(cell / 64),
                    subcell = tonumber(parts[5]) or 0,
                    mission = parts[6],
                    facing = tonumber(parts[7]) or 0,
                    trigger = parts[8]
                })
            end
        end
    end

    -- Triggers
    if ini.TRIGS then
        for name, value in pairs(ini.TRIGS) do
            local parts = {}
            for part in value:gmatch("[^,]+") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end

            if #parts >= 6 then
                table.insert(scenario.triggers, {
                    name = name,
                    house = parts[1],
                    event = tonumber(parts[2]) or 0,
                    event_param = tonumber(parts[3]) or 0,
                    action = tonumber(parts[4]) or 0,
                    action_param = tonumber(parts[5]) or 0,
                    persistent = parts[6] == "1",
                    repeatable = parts[7] == "1"
                })
            end
        end
    end

    -- Teams
    if ini.TEAMS then
        for name, value in pairs(ini.TEAMS) do
            local parts = {}
            for part in value:gmatch("[^,]+") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end

            if #parts >= 9 then
                local members = {}
                for i = 10, #parts do
                    local unit_type, count = parts[i]:match("([^:]+):(%d+)")
                    if unit_type and count then
                        table.insert(members, {
                            type = unit_type,
                            count = tonumber(count)
                        })
                    end
                end

                table.insert(scenario.teams, {
                    name = name,
                    house = parts[1],
                    roundabout = parts[2] == "1",
                    learning = parts[3] == "1",
                    suicide = parts[4] == "1",
                    autocreate = parts[5] == "1",
                    mercenary = parts[6] == "1",
                    prebuild = parts[7] == "1",
                    reinforce = parts[8] == "1",
                    members = members
                })
            end
        end
    end

    -- Waypoints
    if ini.WAYPOINTS then
        for index, value in pairs(ini.WAYPOINTS) do
            local cell = tonumber(value) or 0
            local idx = tonumber(index) or 0
            scenario.waypoints[idx + 1] = {
                x = (cell % 64) * Constants.LEPTON_PER_CELL,
                y = math.floor(cell / 64) * Constants.LEPTON_PER_CELL
            }
        end
    end

    -- Cell triggers
    if ini.CELLTRIGGERS then
        for cell_str, trigger in pairs(ini.CELLTRIGGERS) do
            local cell = tonumber(cell_str) or 0
            table.insert(scenario.cell_triggers, {
                cell_x = cell % 64,
                cell_y = math.floor(cell / 64),
                trigger = trigger
            })
        end
    end

    return scenario
end

-- Load scenario data (from any format)
function ScenarioLoader:load_scenario_data(data)
    self.scenario = data

    -- Initialize grid if needed
    if self.grid then
        self.grid:init(data.map_width or 64, data.map_height or 64)

        -- Set theater
        if data.theater then
            self.grid.theater = data.theater
        end
    end

    -- Clear existing entities
    if self.world then
        self.world:clear()
    end

    -- Create entities
    self:create_structures(data.structures or {})
    self:create_units(data.units or {})
    self:create_infantry(data.infantry or {})

    -- Store scenario info
    Events.emit("SCENARIO_LOADED", data)

    return data
end

-- Create structure entities
function ScenarioLoader:create_structures(structures)
    for _, s in ipairs(structures) do
        if self.production_system then
            local entity = self.production_system:create_building(
                s.type,
                self:house_to_constant(s.house),
                s.cell_x,
                s.cell_y
            )

            if entity then
                -- Set health
                local health = entity:get("health")
                if health and s.health then
                    health.hp = math.floor(health.max_hp * s.health / 256)
                end

                -- Store trigger reference
                if s.trigger and s.trigger ~= "None" then
                    entity.trigger_name = s.trigger
                end

                self.world:add_entity(entity)
            end
        end
    end
end

-- Create unit entities
function ScenarioLoader:create_units(units)
    for _, u in ipairs(units) do
        if self.production_system then
            local x = u.cell_x * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2
            local y = u.cell_y * Constants.LEPTON_PER_CELL + Constants.LEPTON_PER_CELL / 2

            local entity = self.production_system:create_unit(
                u.type,
                self:house_to_constant(u.house),
                x, y
            )

            if entity then
                -- Set health
                local health = entity:get("health")
                if health and u.health then
                    health.hp = math.floor(health.max_hp * u.health / 256)
                end

                -- Set facing
                local transform = entity:get("transform")
                if transform and u.facing then
                    transform.facing = u.facing
                end

                -- Set mission
                if u.mission then
                    entity.initial_mission = u.mission
                end

                -- Store trigger reference
                if u.trigger and u.trigger ~= "None" then
                    entity.trigger_name = u.trigger
                end

                self.world:add_entity(entity)
            end
        end
    end
end

-- Create infantry entities
function ScenarioLoader:create_infantry(infantry)
    for _, i in ipairs(infantry) do
        if self.production_system then
            -- Calculate position with subcell offset
            local base_x = i.cell_x * Constants.LEPTON_PER_CELL
            local base_y = i.cell_y * Constants.LEPTON_PER_CELL

            -- Subcell positions (0-4, center and four corners)
            local subcell_offsets = {
                [0] = {128, 128},  -- Center
                [1] = {64, 64},    -- Top-left
                [2] = {192, 64},   -- Top-right
                [3] = {64, 192},   -- Bottom-left
                [4] = {192, 192}   -- Bottom-right
            }

            local offset = subcell_offsets[i.subcell or 0] or subcell_offsets[0]
            local x = base_x + offset[1]
            local y = base_y + offset[2]

            local entity = self.production_system:create_unit(
                i.type,
                self:house_to_constant(i.house),
                x, y
            )

            if entity then
                -- Set health
                local health = entity:get("health")
                if health and i.health then
                    health.hp = math.floor(health.max_hp * i.health / 256)
                end

                -- Set facing
                local transform = entity:get("transform")
                if transform and i.facing then
                    transform.facing = i.facing
                end

                -- Set mission
                if i.mission then
                    entity.initial_mission = i.mission
                end

                -- Store trigger reference
                if i.trigger and i.trigger ~= "None" then
                    entity.trigger_name = i.trigger
                end

                self.world:add_entity(entity)
            end
        end
    end
end

-- Convert house string to constant
function ScenarioLoader:house_to_constant(house_str)
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

-- Simple JSON parser (for basic scenario files)
function ScenarioLoader:parse_json(str)
    -- This is a minimal JSON parser for scenario files
    -- For production, use a full JSON library

    local pos = 1

    local function skip_whitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parse_value()
        skip_whitespace()
        local char = str:sub(pos, pos)

        if char == "{" then
            return parse_object()
        elseif char == "[" then
            return parse_array()
        elseif char == '"' then
            return parse_string()
        elseif char:match("[%d%-]") then
            return parse_number()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        error("Unexpected character at position " .. pos)
    end

    function parse_object()
        local obj = {}
        pos = pos + 1  -- skip {
        skip_whitespace()

        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end

        while true do
            skip_whitespace()
            local key = parse_string()
            skip_whitespace()
            pos = pos + 1  -- skip :
            local value = parse_value()
            obj[key] = value
            skip_whitespace()

            local char = str:sub(pos, pos)
            if char == "}" then
                pos = pos + 1
                return obj
            end
            pos = pos + 1  -- skip ,
        end
    end

    function parse_array()
        local arr = {}
        pos = pos + 1  -- skip [
        skip_whitespace()

        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end

        while true do
            table.insert(arr, parse_value())
            skip_whitespace()

            local char = str:sub(pos, pos)
            if char == "]" then
                pos = pos + 1
                return arr
            end
            pos = pos + 1  -- skip ,
        end
    end

    function parse_string()
        pos = pos + 1  -- skip opening "
        local start = pos

        while str:sub(pos, pos) ~= '"' do
            if str:sub(pos, pos) == "\\" then
                pos = pos + 2  -- skip escape sequence
            else
                pos = pos + 1
            end
        end

        local s = str:sub(start, pos - 1)
        pos = pos + 1  -- skip closing "

        -- Handle escape sequences
        s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\\\", "\\"):gsub('\\"', '"')

        return s
    end

    function parse_number()
        local start = pos
        if str:sub(pos, pos) == "-" then
            pos = pos + 1
        end

        while str:sub(pos, pos):match("[%d%.eE%+%-]") do
            pos = pos + 1
        end

        return tonumber(str:sub(start, pos - 1))
    end

    return parse_value()
end

-- Get current scenario info
function ScenarioLoader:get_scenario_info()
    if not self.scenario then
        return nil
    end

    return {
        name = self.scenario.name,
        theater = self.scenario.theater,
        player = self.scenario.player,
        map_width = self.scenario.map_width,
        map_height = self.scenario.map_height
    }
end

return ScenarioLoader
