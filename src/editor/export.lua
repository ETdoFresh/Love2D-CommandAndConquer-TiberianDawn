--[[
    Scenario Export - Export scenarios to various formats
]]

local json = require("src.util.serialize")

local Export = {}
Export.__index = Export

function Export.new()
    local self = setmetatable({}, Export)
    return self
end

-- Export scenario to JSON format
function Export:to_json(scenario_data)
    return json.encode(scenario_data)
end

-- Export scenario to INI format (matching original C&C scenario files)
function Export:to_ini(scenario_data)
    local lines = {}

    -- Basic section
    table.insert(lines, "[Basic]")
    table.insert(lines, "Name=" .. (scenario_data.name or "Untitled"))
    table.insert(lines, "Intro=" .. (scenario_data.intro or "NONE"))
    table.insert(lines, "BuildLevel=" .. (scenario_data.build_level or 99))
    table.insert(lines, "Theme=" .. (scenario_data.theme or "NONE"))
    table.insert(lines, "Win=" .. (scenario_data.win_movie or "NONE"))
    table.insert(lines, "Lose=" .. (scenario_data.lose_movie or "NONE"))
    table.insert(lines, "Action=" .. (scenario_data.action_movie or "NONE"))
    table.insert(lines, "Brief=" .. (scenario_data.brief or "NONE"))
    table.insert(lines, "Player=" .. (scenario_data.player or "GoodGuy"))
    table.insert(lines, "")

    -- Map section
    table.insert(lines, "[Map]")
    table.insert(lines, "X=" .. (scenario_data.map_x or 0))
    table.insert(lines, "Y=" .. (scenario_data.map_y or 0))
    table.insert(lines, "Width=" .. (scenario_data.map_width or 64))
    table.insert(lines, "Height=" .. (scenario_data.map_height or 64))
    table.insert(lines, "Theater=" .. (scenario_data.theater or "TEMPERATE"))
    table.insert(lines, "")

    -- Houses (players)
    if scenario_data.houses then
        for name, house in pairs(scenario_data.houses) do
            table.insert(lines, "[" .. name .. "]")
            table.insert(lines, "Credits=" .. (house.credits or 0))
            table.insert(lines, "Edge=" .. (house.edge or "North"))
            table.insert(lines, "MaxUnit=" .. (house.max_unit or 150))
            table.insert(lines, "MaxBuilding=" .. (house.max_building or 150))
            table.insert(lines, "MaxInfantry=" .. (house.max_infantry or 150))
            if house.allies then
                table.insert(lines, "Allies=" .. table.concat(house.allies, ","))
            end
            table.insert(lines, "")
        end
    end

    -- Terrain
    if scenario_data.terrain then
        table.insert(lines, "[TERRAIN]")
        for _, t in ipairs(scenario_data.terrain) do
            local cell = t.cell_y * 64 + t.cell_x
            table.insert(lines, cell .. "=" .. t.type)
        end
        table.insert(lines, "")
    end

    -- Structures
    if scenario_data.structures then
        table.insert(lines, "[STRUCTURES]")
        local id = 0
        for _, s in ipairs(scenario_data.structures) do
            local cell = s.cell_y * 64 + s.cell_x
            local line = string.format("%03d=%s,%s,%d,%d,%s,%s",
                id, s.house, s.type, s.health or 256, cell,
                s.facing or 0, s.trigger or "None")
            table.insert(lines, line)
            id = id + 1
        end
        table.insert(lines, "")
    end

    -- Units
    if scenario_data.units then
        table.insert(lines, "[UNITS]")
        local id = 0
        for _, u in ipairs(scenario_data.units) do
            local cell = u.cell_y * 64 + u.cell_x
            local line = string.format("%03d=%s,%s,%d,%d,%d,%s,%s",
                id, u.house, u.type, u.health or 256, cell,
                u.facing or 0, u.mission or "Guard", u.trigger or "None")
            table.insert(lines, line)
            id = id + 1
        end
        table.insert(lines, "")
    end

    -- Infantry
    if scenario_data.infantry then
        table.insert(lines, "[INFANTRY]")
        local id = 0
        for _, i in ipairs(scenario_data.infantry) do
            local cell = i.cell_y * 64 + i.cell_x
            local line = string.format("%03d=%s,%s,%d,%d,%d,%s,%d,%s",
                id, i.house, i.type, i.health or 256, cell,
                i.subcell or 0, i.mission or "Guard", i.facing or 0, i.trigger or "None")
            table.insert(lines, line)
            id = id + 1
        end
        table.insert(lines, "")
    end

    -- Triggers
    if scenario_data.triggers then
        table.insert(lines, "[TRIGS]")
        for _, t in ipairs(scenario_data.triggers) do
            local persist = t.persistent and 1 or 0
            local repeat_flag = t.repeatable and 1 or 0
            local line = string.format("%s=%s,%d,%d,%d,%d,%d,%d",
                t.name, t.house,
                t.event, t.event_param or 0,
                t.action, t.action_param or 0,
                persist, repeat_flag)
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end

    -- Teams
    if scenario_data.teams then
        table.insert(lines, "[TEAMS]")
        for _, team in ipairs(scenario_data.teams) do
            local members = {}
            for _, m in ipairs(team.members or {}) do
                table.insert(members, m.type .. ":" .. m.count)
            end
            local line = string.format("%s=%s,%d,%d,%d,%d,%d,%d,%d,%s",
                team.name, team.house,
                team.roundabout and 1 or 0,
                team.learning and 1 or 0,
                team.suicide and 1 or 0,
                team.autocreate and 1 or 0,
                team.mercenary and 1 or 0,
                team.prebuild and 1 or 0,
                team.reinforce and 1 or 0,
                table.concat(members, ","))
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end

    -- Waypoints
    if scenario_data.waypoints then
        table.insert(lines, "[WAYPOINTS]")
        for i, wp in ipairs(scenario_data.waypoints) do
            local cell = wp.y * 64 + wp.x
            table.insert(lines, (i - 1) .. "=" .. cell)
        end
        table.insert(lines, "")
    end

    -- CellTriggers
    if scenario_data.cell_triggers then
        table.insert(lines, "[CELLTRIGGERS]")
        for _, ct in ipairs(scenario_data.cell_triggers) do
            local cell = ct.cell_y * 64 + ct.cell_x
            table.insert(lines, cell .. "=" .. ct.trigger)
        end
        table.insert(lines, "")
    end

    -- MapPack (terrain data as Base64)
    if scenario_data.map_pack then
        table.insert(lines, "[MapPack]")
        table.insert(lines, "1=" .. scenario_data.map_pack)
        table.insert(lines, "")
    end

    -- OverlayPack (overlay data as Base64)
    if scenario_data.overlay_pack then
        table.insert(lines, "[OverlayPack]")
        table.insert(lines, "1=" .. scenario_data.overlay_pack)
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

-- Build scenario data from editor state
function Export:build_scenario_data(options)
    local data = {
        name = options.name or "Untitled Scenario",
        intro = options.intro or "NONE",
        build_level = options.build_level or 99,
        theme = options.theme or "NONE",
        win_movie = options.win_movie or "NONE",
        lose_movie = options.lose_movie or "NONE",
        action_movie = options.action_movie or "NONE",
        brief = options.brief or "NONE",
        player = options.player or "GoodGuy",

        map_x = options.map_x or 0,
        map_y = options.map_y or 0,
        map_width = options.map_width or 64,
        map_height = options.map_height or 64,
        theater = options.theater or "TEMPERATE",

        houses = options.houses or {},
        terrain = options.terrain or {},
        structures = options.structures or {},
        units = options.units or {},
        infantry = options.infantry or {},
        triggers = options.triggers or {},
        teams = options.teams or {},
        waypoints = options.waypoints or {},
        cell_triggers = options.cell_triggers or {}
    }

    return data
end

-- Save scenario to file
function Export:save_to_file(filepath, scenario_data, format)
    format = format or "json"

    local content
    if format == "json" then
        content = self:to_json(scenario_data)
    elseif format == "ini" then
        content = self:to_ini(scenario_data)
    else
        return false, "Unknown format: " .. format
    end

    local file, err = io.open(filepath, "w")
    if not file then
        return false, "Could not open file: " .. err
    end

    file:write(content)
    file:close()

    return true
end

-- Create scenario from grid and entities
function Export:from_world(world, grid, triggers)
    local data = self:build_scenario_data({})

    -- Export terrain from grid
    if grid then
        for y = 0, grid.height - 1 do
            for x = 0, grid.width - 1 do
                local cell = grid:get_cell(x, y)
                if cell and cell.template_type ~= 0 then
                    table.insert(data.terrain, {
                        cell_x = x,
                        cell_y = y,
                        type = cell.template_type,
                        icon = cell.template_icon
                    })
                end
            end
        end
    end

    -- Export entities from world
    if world then
        local entities = world:get_all_entities()

        for _, entity in ipairs(entities) do
            local transform = entity:get("transform")
            local owner = entity:get("owner")
            local health = entity:get("health")

            if transform then
                local cell_x = transform.cell_x or math.floor(transform.x / 256)
                local cell_y = transform.cell_y or math.floor(transform.y / 256)
                local house = owner and owner.house or "GOOD"
                local hp = health and math.floor(health.hp / health.max_hp * 256) or 256

                if entity:has_tag("building") then
                    local building = entity:get("building")
                    table.insert(data.structures, {
                        house = house,
                        type = building and building.building_type or "UNKNOWN",
                        health = hp,
                        cell_x = cell_x,
                        cell_y = cell_y,
                        facing = transform.facing or 0
                    })
                elseif entity:has_tag("vehicle") then
                    local vehicle = entity:get("vehicle")
                    table.insert(data.units, {
                        house = house,
                        type = vehicle and vehicle.vehicle_type or "UNKNOWN",
                        health = hp,
                        cell_x = cell_x,
                        cell_y = cell_y,
                        facing = transform.facing or 0,
                        mission = "Guard"
                    })
                elseif entity:has_tag("infantry") then
                    local infantry = entity:get("infantry")
                    table.insert(data.infantry, {
                        house = house,
                        type = infantry and infantry.infantry_type or "UNKNOWN",
                        health = hp,
                        cell_x = cell_x,
                        cell_y = cell_y,
                        subcell = 0,
                        facing = transform.facing or 0,
                        mission = "Guard"
                    })
                end
            end
        end
    end

    -- Export triggers
    if triggers then
        data.triggers = triggers:serialize().triggers

        -- Build cell triggers from trigger attachments
        for _, trigger in ipairs(data.triggers) do
            if trigger.cell_x >= 0 and trigger.cell_y >= 0 then
                table.insert(data.cell_triggers, {
                    cell_x = trigger.cell_x,
                    cell_y = trigger.cell_y,
                    trigger = trigger.name
                })
            end
        end
    end

    return data
end

return Export
