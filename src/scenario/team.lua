--[[
    Team System - AI team management for scenarios
    Handles team creation, missions, and behavior matching original C&C
]]

local Constants = require("src.core.constants")
local Events = require("src.core.events")

local TeamSystem = {}
TeamSystem.__index = TeamSystem

-- Team missions (what the team does once formed)
TeamSystem.MISSION = {
    ATTACK_BASE = 0,      -- Attack enemy base
    ATTACK_UNITS = 1,     -- Attack enemy units
    ATTACK_CIVILIAN = 2,  -- Attack civilians
    RAMPAGE = 3,          -- Attack everything
    DEFEND_BASE = 4,      -- Defend own base
    MOVE = 5,             -- Move to waypoint
    MOVE_TO_CELL = 6,     -- Move to specific cell
    RETREAT = 7,          -- Retreat to base
    GUARD = 8,            -- Guard area
    LOOP = 9,             -- Loop through waypoints
    ATTACK_TARCOM = 10,   -- Attack specific target
    UNLOAD = 11,          -- Unload transport
    DEPLOY = 12           -- Deploy MCVs
}

function TeamSystem.new(world, ai_system)
    local self = setmetatable({}, TeamSystem)

    self.world = world
    self.ai_system = ai_system
    self.movement_system = nil  -- Set via set_movement_system()

    -- Team definitions (from scenario)
    self.team_types = {}

    -- Active teams
    self.active_teams = {}

    -- Next team ID
    self.next_team_id = 1

    -- Scenario waypoints reference
    self.scenario_waypoints = {}

    -- Register events
    self:register_events()

    return self
end

-- Set movement system reference
function TeamSystem:set_movement_system(movement_system)
    self.movement_system = movement_system
end

-- Set scenario waypoints (called by loader)
function TeamSystem:set_waypoints(waypoints)
    self.scenario_waypoints = waypoints or {}
end

-- Set production system reference (for spawning reinforcements)
function TeamSystem:set_production_system(production_system)
    self.production_system = production_system
end

-- Register event listeners
function TeamSystem:register_events()
    Events.on("CREATE_TEAM", function(team_type_name)
        self:create_team(team_type_name)
    end)

    Events.on("DESTROY_TEAM", function(team_type_name)
        self:destroy_teams_of_type(team_type_name)
    end)

    Events.on("ALL_TO_HUNT", function(house)
        self:all_to_hunt(house)
    end)

    Events.on("REINFORCEMENT", function(team_type_name, waypoint_name)
        self:spawn_reinforcement(team_type_name, waypoint_name)
    end)

    -- Listen for autocreate toggle from triggers
    Events.on("AUTOCREATE", function(house, enabled)
        self:set_autocreate_enabled(house, enabled)
    end)

    -- Listen for scenario start to spawn initial autocreate teams
    Events.on("SCENARIO_STARTED", function()
        self:spawn_autocreate_teams()
    end)
end

-- Autocreate state per house
TeamSystem.autocreate_enabled = {}

-- Enable or disable autocreate for a house
function TeamSystem:set_autocreate_enabled(house, enabled)
    TeamSystem.autocreate_enabled[house] = enabled
    if enabled then
        -- Immediately try to spawn any pending autocreate teams
        self:spawn_autocreate_teams_for_house(house)
    end
end

-- Spawn all autocreate teams at scenario start
function TeamSystem:spawn_autocreate_teams()
    for name, team_type in pairs(self.team_types) do
        if team_type.autocreate then
            -- Autocreate teams spawn at mission start
            local team = self:create_team(name)
            if team then
                Events.emit("TEAM_AUTOCREATED", name, team.id)
            end
        end
    end
end

-- Spawn autocreate teams for a specific house (when enabled via trigger)
function TeamSystem:spawn_autocreate_teams_for_house(house)
    -- Convert house constant to string for comparison
    local house_str = house
    if type(house) == "number" then
        if house == Constants.HOUSE.BAD then
            house_str = "BAD"
        elseif house == Constants.HOUSE.GOOD then
            house_str = "GOOD"
        end
    end

    for name, team_type in pairs(self.team_types) do
        if team_type.autocreate then
            local team_house = team_type.house
            if type(team_house) == "string" then
                if team_house == "BadGuy" then team_house = "BAD" end
                if team_house == "GoodGuy" then team_house = "GOOD" end
            end

            if team_house == house_str or team_house == house then
                -- Check if we already have an active team of this type
                local has_active = false
                for _, active_team in pairs(self.active_teams) do
                    if active_team.type_name == name then
                        has_active = true
                        break
                    end
                end

                if not has_active then
                    local team = self:create_team(name)
                    if team then
                        Events.emit("TEAM_AUTOCREATED", name, team.id)
                    end
                end
            end
        end
    end
end

-- Check if we should rebuild autocreate teams (called periodically by AI)
function TeamSystem:check_autocreate_rebuild()
    for house, enabled in pairs(TeamSystem.autocreate_enabled) do
        if enabled then
            self:spawn_autocreate_teams_for_house(house)
        end
    end
end

-- Spawn reinforcement team at specified waypoint or map edge
function TeamSystem:spawn_reinforcement(team_type_name, waypoint_name)
    local team_type = self.team_types[team_type_name]
    if not team_type then
        print("TeamSystem: Unknown team type for reinforcement: " .. tostring(team_type_name))
        return nil
    end

    if not self.production_system then
        print("TeamSystem: No production system for spawning reinforcements")
        return nil
    end

    -- Determine spawn location
    local spawn_x, spawn_y = 0, 0
    local map_width = 64 * Constants.LEPTON_PER_CELL
    local map_height = 64 * Constants.LEPTON_PER_CELL

    if waypoint_name and self.scenario_waypoints then
        -- Use specified waypoint
        local waypoint = self.scenario_waypoints[waypoint_name]
        if waypoint then
            spawn_x = waypoint.x * Constants.LEPTON_PER_CELL
            spawn_y = waypoint.y * Constants.LEPTON_PER_CELL
        else
            -- Waypoint not found, use map edge based on house
            spawn_x, spawn_y = self:get_edge_spawn_point(team_type.house)
        end
    else
        -- Default to map edge based on house (enemy from north/east, friendly from south/west)
        spawn_x, spawn_y = self:get_edge_spawn_point(team_type.house)
    end

    -- Convert house string to constant
    local house = team_type.house
    if type(house) == "string" then
        if house == "BadGuy" or house == "BAD" then
            house = Constants.HOUSE.BAD
        elseif house == "GoodGuy" or house == "GOOD" then
            house = Constants.HOUSE.GOOD
        else
            house = Constants.HOUSE.NEUTRAL
        end
    end

    -- Create team structure
    local team = {
        id = self.next_team_id,
        type_name = team_type_name,
        house = house,
        mission = team_type.mission,
        waypoints = team_type.waypoints,
        roundabout = team_type.roundabout,
        suicide = team_type.suicide,
        members = {},
        current_waypoint = 1,
        target = nil,
        formed = true
    }
    self.next_team_id = self.next_team_id + 1

    -- Spawn each unit type in the team
    local spawn_offset = 0
    for _, requirement in ipairs(team_type.members) do
        local unit_type = requirement.type
        local count = requirement.count or 1

        for i = 1, count do
            -- Calculate offset for this unit
            local offset_x = (spawn_offset % 4) * Constants.LEPTON_PER_CELL
            local offset_y = math.floor(spawn_offset / 4) * Constants.LEPTON_PER_CELL
            spawn_offset = spawn_offset + 1

            local unit_x = spawn_x + offset_x
            local unit_y = spawn_y + offset_y

            -- Create the unit
            local entity = self.production_system:create_unit(unit_type, house, unit_x, unit_y)
            if entity then
                entity.team_id = team.id
                table.insert(team.members, entity.id)

                -- Emit reinforcement spawn event
                Events.emit("UNIT_REINFORCED", entity, team_type_name)
            end
        end
    end

    -- Store team and assign mission
    self.active_teams[team.id] = team
    self:assign_team_mission(team)

    -- Play reinforcement audio
    Events.emit("PLAY_SPEECH", "Reinforcements have arrived")

    return team
end

-- Get spawn point at map edge based on house
function TeamSystem:get_edge_spawn_point(house)
    local map_width = 64 * Constants.LEPTON_PER_CELL
    local map_height = 64 * Constants.LEPTON_PER_CELL

    -- Enemy (BAD) spawns from north or east, friendly (GOOD) from south or west
    if house == "BadGuy" or house == "BAD" or house == Constants.HOUSE.BAD then
        -- Spawn from north edge (top of map)
        return map_width / 2, Constants.LEPTON_PER_CELL * 2
    else
        -- Spawn from south edge (bottom of map)
        return map_width / 2, map_height - Constants.LEPTON_PER_CELL * 4
    end
end

-- Load team definitions from scenario
function TeamSystem:load_team_types(team_data)
    self.team_types = {}

    for _, t in ipairs(team_data) do
        local team_type = {
            name = t.name,
            house = t.house or "BAD",

            -- Team behavior flags
            roundabout = t.roundabout or false,   -- Take indirect routes
            learning = t.learning or false,        -- Learn from defeats
            suicide = t.suicide or false,          -- Don't retreat
            autocreate = t.autocreate or false,    -- Auto-build by AI
            mercenary = t.mercenary or false,      -- Fight anyone
            prebuild = t.prebuild or false,        -- Prebuild before trigger
            reinforce = t.reinforce or false,      -- Can be reinforcements

            -- Team composition
            members = t.members or {},  -- {type = "MTNK", count = 3}

            -- Mission
            mission = t.mission or TeamSystem.MISSION.ATTACK_BASE,
            waypoints = t.waypoints or {},

            -- Priority
            priority = t.priority or 5
        }

        self.team_types[team_type.name] = team_type
    end
end

-- Create a new team from a team type
function TeamSystem:create_team(team_type_name)
    local team_type = self.team_types[team_type_name]
    if not team_type then
        return nil
    end

    local team = {
        id = self.next_team_id,
        type_name = team_type_name,
        house = team_type.house,
        mission = team_type.mission,
        waypoints = team_type.waypoints,

        -- Behavior
        roundabout = team_type.roundabout,
        suicide = team_type.suicide,

        -- Current state
        members = {},
        current_waypoint = 1,
        target = nil,
        formed = false
    }

    self.next_team_id = self.next_team_id + 1

    -- Find or create required units
    local units_found = self:recruit_units(team, team_type)

    if units_found then
        team.formed = true
        self.active_teams[team.id] = team
        self:assign_team_mission(team)
        return team
    end

    return nil
end

-- Recruit units for a team
function TeamSystem:recruit_units(team, team_type)
    local recruited = {}

    -- Convert house string to constant if needed
    local target_house = team_type.house
    if type(target_house) == "string" then
        if target_house == "BadGuy" or target_house == "BAD" then
            target_house = Constants.HOUSE.BAD
        elseif target_house == "GoodGuy" or target_house == "GOOD" then
            target_house = Constants.HOUSE.GOOD
        elseif target_house == "Neutral" then
            target_house = Constants.HOUSE.NEUTRAL
        end
    end

    for _, requirement in ipairs(team_type.members) do
        local unit_type = requirement.type
        local count = requirement.count

        -- Find available units of this type - try both infantry and vehicle tags
        local found = 0

        -- Check vehicles first
        local vehicles = self.world:get_entities_tagged("vehicle")
        for _, entity in ipairs(vehicles) do
            if found >= count then break end

            local owner = entity:get("owner")
            if owner and owner.house == target_house then
                local vehicle = entity:get("vehicle")
                if vehicle and vehicle.vehicle_type == unit_type and not entity.team_id then
                    table.insert(recruited, entity)
                    found = found + 1
                end
            end
        end

        -- Then check infantry
        if found < count then
            local infantry = self.world:get_entities_tagged("infantry")
            for _, entity in ipairs(infantry) do
                if found >= count then break end

                local owner = entity:get("owner")
                if owner and owner.house == target_house then
                    local inf = entity:get("infantry")
                    if inf and inf.infantry_type == unit_type and not entity.team_id then
                        table.insert(recruited, entity)
                        found = found + 1
                    end
                end
            end
        end

        if found < count then
            -- Couldn't find enough units
            return false
        end
    end

    -- Assign all recruited units to team
    for _, entity in ipairs(recruited) do
        entity.team_id = team.id
        table.insert(team.members, entity)
    end

    return true
end

-- Assign mission to formed team
function TeamSystem:assign_team_mission(team)
    local mission = team.mission

    for _, entity in ipairs(team.members) do
        if mission == TeamSystem.MISSION.ATTACK_BASE then
            -- Find enemy base and attack
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.ATTACK)
            end

        elseif mission == TeamSystem.MISSION.ATTACK_UNITS then
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.HUNT)
            end

        elseif mission == TeamSystem.MISSION.MOVE then
            -- Move to first waypoint
            local waypoint = team.waypoints[1]
            if waypoint and self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.MOVE)
                entity.target_x = waypoint.x
                entity.target_y = waypoint.y
            end

        elseif mission == TeamSystem.MISSION.GUARD then
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.GUARD)
            end

        elseif mission == TeamSystem.MISSION.DEFEND_BASE then
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.GUARD_AREA)
            end

        elseif mission == TeamSystem.MISSION.RAMPAGE then
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.HUNT)
            end

        elseif mission == TeamSystem.MISSION.DEPLOY then
            -- Deploy MCVs to create Construction Yards
            -- Reference: Original C&C - DEPLOY mission makes MCVs deploy at waypoint
            if entity:has("deployable") then
                -- Move to deployment waypoint first
                local waypoint = team.waypoints[1]
                if waypoint and self.ai_system then
                    self.ai_system:set_mission(entity, Constants.MISSION.MOVE)
                    entity.target_x = waypoint.x
                    entity.target_y = waypoint.y
                    entity.deploy_on_arrival = true  -- Flag to deploy when arriving
                end
            else
                -- Non-MCV units just guard
                if self.ai_system then
                    self.ai_system:set_mission(entity, Constants.MISSION.GUARD)
                end
            end

        elseif mission == TeamSystem.MISSION.UNLOAD then
            -- Unload transports at waypoint
            -- Reference: Original C&C - UNLOAD mission makes transports drop cargo
            if entity:has("transport") then
                local waypoint = team.waypoints[1]
                if waypoint and self.ai_system then
                    self.ai_system:set_mission(entity, Constants.MISSION.MOVE)
                    entity.target_x = waypoint.x
                    entity.target_y = waypoint.y
                    entity.unload_on_arrival = true  -- Flag to unload when arriving
                end
            else
                -- Non-transport units just guard
                if self.ai_system then
                    self.ai_system:set_mission(entity, Constants.MISSION.GUARD)
                end
            end
        end
    end
end

-- Update all active teams
function TeamSystem:update(dt)
    for team_id, team in pairs(self.active_teams) do
        if team.formed then
            self:update_team(team, dt)
        end
    end
end

-- Update a single team
function TeamSystem:update_team(team, dt)
    -- Remove dead members
    local alive_members = {}
    for _, entity in ipairs(team.members) do
        if not entity.destroyed then
            table.insert(alive_members, entity)
        end
    end
    team.members = alive_members

    -- Team is destroyed if no members
    if #team.members == 0 then
        self:destroy_team(team.id)
        return
    end

    -- Update based on mission type
    if team.mission == TeamSystem.MISSION.MOVE or
       team.mission == TeamSystem.MISSION.LOOP then
        self:update_waypoint_movement(team)

    elseif team.mission == TeamSystem.MISSION.ATTACK_BASE or
           team.mission == TeamSystem.MISSION.ATTACK_UNITS then
        self:update_coordinated_attack(team)

    elseif team.mission == TeamSystem.MISSION.DEPLOY then
        self:update_deploy_mission(team)

    elseif team.mission == TeamSystem.MISSION.UNLOAD then
        self:update_unload_mission(team)
    end
end

-- Update DEPLOY mission - deploy MCVs when they arrive at waypoint
-- Reference: Original C&C - AI deploys MCV at designated location
function TeamSystem:update_deploy_mission(team)
    for _, entity in ipairs(team.members) do
        if entity.deploy_on_arrival and entity:has("deployable") and entity:has("transform") then
            local transform = entity:get("transform")
            local waypoint = team.waypoints[1]

            if waypoint then
                -- Check if entity has arrived at waypoint (within 1 cell)
                local dx = transform.x - waypoint.x
                local dy = transform.y - waypoint.y
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < Constants.LEPTON_PER_CELL then
                    -- Try to deploy
                    Events.emit("DEPLOY_UNIT", entity)
                    entity.deploy_on_arrival = false
                end
            end
        end
    end
end

-- Update UNLOAD mission - unload transports when they arrive at waypoint
-- Reference: Original C&C - Chinooks and APCs unload at designated location
function TeamSystem:update_unload_mission(team)
    for _, entity in ipairs(team.members) do
        if entity.unload_on_arrival and entity:has("transport") and entity:has("transform") then
            local transform = entity:get("transform")
            local waypoint = team.waypoints[1]

            if waypoint then
                -- Check if entity has arrived at waypoint (within 1 cell)
                local dx = transform.x - waypoint.x
                local dy = transform.y - waypoint.y
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < Constants.LEPTON_PER_CELL then
                    -- Unload all passengers
                    Events.emit("UNLOAD_TRANSPORT", entity)
                    entity.unload_on_arrival = false
                end
            end
        end
    end
end

-- Update coordinated attack - wait for team to gather before attacking
function TeamSystem:update_coordinated_attack(team)
    if #team.members == 0 then return end

    -- Calculate team center
    local center_x, center_y = 0, 0
    local count = 0

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        if transform then
            center_x = center_x + transform.x
            center_y = center_y + transform.y
            count = count + 1
        end
    end

    if count == 0 then return end

    center_x = center_x / count
    center_y = center_y / count

    -- Check if team is gathered (all members within gather radius)
    local GATHER_RADIUS = 512  -- 2 cells
    local all_gathered = true
    local max_dist = 0

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        if transform then
            local dx = transform.x - center_x
            local dy = transform.y - center_y
            local dist = math.sqrt(dx * dx + dy * dy)
            max_dist = math.max(max_dist, dist)
            if dist > GATHER_RADIUS then
                all_gathered = false
            end
        end
    end

    -- Team behavior based on gather state
    if not team.gathering_started then
        -- First update - start gathering phase
        team.gathering_started = true
        team.gathered = false
        team.gather_time = 0

        -- Move all units toward center
        for _, entity in ipairs(team.members) do
            self:move_entity_to(entity, center_x, center_y)
        end

    elseif not team.gathered then
        -- Gathering phase - wait for units to group up
        team.gather_time = (team.gather_time or 0) + 1

        if all_gathered or team.gather_time > 150 then  -- Max 10 seconds at 15 FPS
            -- Team is gathered, start attack
            team.gathered = true

            -- Find target and attack as a group
            local target = self:find_team_target(team)
            if target then
                team.target = target
                for _, entity in ipairs(team.members) do
                    if self.ai_system then
                        -- Set shared target for focused fire
                        local mission = entity:get("mission")
                        if mission then
                            mission.target = target
                        end
                        self.ai_system:set_mission(entity, Constants.MISSION.ATTACK)
                    end
                end
            else
                -- No target found, hunt
                for _, entity in ipairs(team.members) do
                    if self.ai_system then
                        self.ai_system:set_mission(entity, Constants.MISSION.HUNT)
                    end
                end
            end
        else
            -- Still gathering - move stragglers toward center
            for _, entity in ipairs(team.members) do
                local transform = entity:get("transform")
                local mobile = entity:get("mobile")
                if transform and mobile and not mobile.is_moving then
                    local dx = transform.x - center_x
                    local dy = transform.y - center_y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > GATHER_RADIUS then
                        self:move_entity_to(entity, center_x, center_y)
                    end
                end
            end
        end

    else
        -- Already gathered and attacking - check for shared target
        if team.target and team.target.destroyed then
            -- Target destroyed, find new one
            local new_target = self:find_team_target(team)
            if new_target then
                team.target = new_target
                for _, entity in ipairs(team.members) do
                    local mission = entity:get("mission")
                    if mission then
                        mission.target = new_target
                    end
                end
            end
        end
    end
end

-- Find a target for the team to attack
function TeamSystem:find_team_target(team)
    if #team.members == 0 then return nil end

    -- Get team center for distance calculations
    local center_x, center_y = 0, 0
    local count = 0

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        if transform then
            center_x = center_x + transform.x
            center_y = center_y + transform.y
            count = count + 1
        end
    end

    if count == 0 then return nil end
    center_x = center_x / count
    center_y = center_y / count

    -- Convert team house to constant
    local team_house = team.house
    if type(team_house) == "string" then
        if team_house == "BadGuy" or team_house == "BAD" then
            team_house = Constants.HOUSE.BAD
        elseif team_house == "GoodGuy" or team_house == "GOOD" then
            team_house = Constants.HOUSE.GOOD
        end
    end

    -- Find closest enemy target
    local best_target = nil
    local best_dist = math.huge

    -- Priority: buildings first for ATTACK_BASE, units for ATTACK_UNITS
    local search_order
    if team.mission == TeamSystem.MISSION.ATTACK_BASE then
        search_order = {"building", "vehicle", "infantry"}
    else
        search_order = {"vehicle", "infantry", "building"}
    end

    for _, tag in ipairs(search_order) do
        local entities = self.world:get_entities_tagged(tag)

        for _, entity in ipairs(entities) do
            if not entity.destroyed then
                local owner = entity:get("owner")
                local transform = entity:get("transform")

                if owner and transform and owner.house ~= team_house then
                    local dx = transform.x - center_x
                    local dy = transform.y - center_y
                    local dist = math.sqrt(dx * dx + dy * dy)

                    if dist < best_dist then
                        best_dist = dist
                        best_target = entity
                    end
                end
            end
        end

        -- If we found a target in preferred category, use it
        if best_target then
            break
        end
    end

    return best_target
end

-- Update waypoint-based movement with cohesion
function TeamSystem:update_waypoint_movement(team)
    if #team.waypoints == 0 then return end

    -- Constants for team cohesion (matching original C&C behavior)
    local COHESION_RADIUS = 384   -- Units try to stay within 1.5 cells of each other
    local WAYPOINT_REACH = 256    -- 1 cell tolerance for reaching waypoint
    local GATHER_TIMEOUT = 120    -- 8 seconds max gather time at 15 FPS

    -- Resolve waypoint (can be index into scenario waypoints or direct coords)
    local waypoint = self:resolve_waypoint(team.waypoints[team.current_waypoint])
    if not waypoint then return end

    -- Calculate team center and check spread
    local center_x, center_y = 0, 0
    local count = 0
    local max_spread = 0

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        if transform then
            center_x = center_x + transform.x
            center_y = center_y + transform.y
            count = count + 1
        end
    end

    if count == 0 then return end
    center_x = center_x / count
    center_y = center_y / count

    -- Calculate how spread out the team is
    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        if transform then
            local dx = transform.x - center_x
            local dy = transform.y - center_y
            max_spread = math.max(max_spread, math.sqrt(dx * dx + dy * dy))
        end
    end

    -- Check if we need to gather first (team too spread out)
    if not team.waypoint_gathered and max_spread > COHESION_RADIUS * 2 then
        -- Team is too spread out, gather first
        team.waypoint_gather_time = (team.waypoint_gather_time or 0) + 1

        if team.waypoint_gather_time < GATHER_TIMEOUT then
            -- Move stragglers toward center
            for _, entity in ipairs(team.members) do
                local transform = entity:get("transform")
                local mobile = entity:get("mobile")
                if transform and mobile then
                    local dx = transform.x - center_x
                    local dy = transform.y - center_y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > COHESION_RADIUS and not mobile.is_moving then
                        self:move_entity_to(entity, center_x, center_y)
                    end
                end
            end
            return  -- Wait for gathering
        else
            -- Timeout - continue anyway
            team.waypoint_gathered = true
        end
    else
        team.waypoint_gathered = true
    end

    -- Check if all members reached waypoint
    local all_reached = true
    local any_moving = false
    local slowest_entity = nil
    local slowest_dist = 0

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        local mobile = entity:get("mobile")

        if transform then
            local dx = transform.x - waypoint.x
            local dy = transform.y - waypoint.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > WAYPOINT_REACH then
                all_reached = false

                -- Track who is furthest from waypoint
                if dist > slowest_dist then
                    slowest_dist = dist
                    slowest_entity = entity
                end

                -- Issue move command if not already moving
                if mobile and not mobile.is_moving then
                    self:move_entity_to(entity, waypoint.x, waypoint.y)
                else
                    any_moving = true
                end
            end
        end
    end

    -- Cohesive movement: faster units wait for slower ones
    if not all_reached and slowest_entity then
        for _, entity in ipairs(team.members) do
            if entity ~= slowest_entity then
                local transform = entity:get("transform")
                local mobile = entity:get("mobile")
                if transform and mobile then
                    local dx = transform.x - waypoint.x
                    local dy = transform.y - waypoint.y
                    local my_dist = math.sqrt(dx * dx + dy * dy)

                    -- If I'm much closer than the slowest, slow down by stopping briefly
                    if my_dist < slowest_dist * 0.5 and my_dist < COHESION_RADIUS then
                        -- I'm way ahead - wait for others
                        if mobile.is_moving then
                            mobile.is_moving = false
                            mobile.path = nil
                        end
                    end
                end
            end
        end
    end

    -- If not all reached and none moving, re-issue move commands
    if not all_reached and not any_moving then
        for _, entity in ipairs(team.members) do
            self:move_entity_to(entity, waypoint.x, waypoint.y)
        end
    end

    if all_reached then
        -- Reset gather state for next waypoint
        team.waypoint_gathered = false
        team.waypoint_gather_time = 0

        -- Move to next waypoint
        team.current_waypoint = team.current_waypoint + 1

        if team.current_waypoint > #team.waypoints then
            if team.mission == TeamSystem.MISSION.LOOP then
                team.current_waypoint = 1
            else
                -- Team mission complete - switch to guard
                for _, entity in ipairs(team.members) do
                    if self.ai_system then
                        self.ai_system:set_mission(entity, Constants.MISSION.GUARD)
                    end
                end
                return
            end
        end

        -- Issue move commands to new waypoint
        local next_wp = self:resolve_waypoint(team.waypoints[team.current_waypoint])
        if next_wp then
            for _, entity in ipairs(team.members) do
                self:move_entity_to(entity, next_wp.x, next_wp.y)
            end
        end
    end
end

-- Resolve waypoint reference to coordinates
-- Waypoint can be: {x=n, y=n}, or index into scenario waypoints
function TeamSystem:resolve_waypoint(waypoint)
    if not waypoint then return nil end

    -- Direct coordinates
    if waypoint.x and waypoint.y then
        return waypoint
    end

    -- Index into scenario waypoints
    if type(waypoint) == "number" then
        return self.scenario_waypoints[waypoint]
    end

    -- Named waypoint index
    if waypoint.index then
        return self.scenario_waypoints[waypoint.index]
    end

    return nil
end

-- Move entity to coordinates using movement system
function TeamSystem:move_entity_to(entity, x, y)
    if self.movement_system and entity:has("mobile") then
        self.movement_system:move_to(entity, x, y)
    end

    if self.ai_system then
        self.ai_system:set_mission(entity, Constants.MISSION.MOVE)
    end
end

-- Destroy a team
function TeamSystem:destroy_team(team_id)
    local team = self.active_teams[team_id]
    if team then
        -- Clear team assignment from members
        for _, entity in ipairs(team.members) do
            entity.team_id = nil
        end

        self.active_teams[team_id] = nil
    end
end

-- Destroy all teams of a type
function TeamSystem:destroy_teams_of_type(team_type_name)
    local to_destroy = {}
    for team_id, team in pairs(self.active_teams) do
        if team.type_name == team_type_name then
            table.insert(to_destroy, team_id)
        end
    end

    for _, team_id in ipairs(to_destroy) do
        self:destroy_team(team_id)
    end
end

-- Send all units of a house to hunt mode
function TeamSystem:all_to_hunt(house)
    -- Get all combat units (vehicles and infantry)
    local vehicles = self.world:get_entities_tagged("vehicle")
    local infantry = self.world:get_entities_tagged("infantry")

    local all_units = {}
    for _, e in ipairs(vehicles) do table.insert(all_units, e) end
    for _, e in ipairs(infantry) do table.insert(all_units, e) end

    for _, entity in ipairs(all_units) do
        local owner = entity:get("owner")
        if owner and owner.house == house then
            if self.ai_system then
                self.ai_system:set_mission(entity, Constants.MISSION.HUNT)
            end
        end
    end
end

-- Get team for an entity
function TeamSystem:get_entity_team(entity)
    if entity.team_id then
        return self.active_teams[entity.team_id]
    end
    return nil
end

-- Get all active teams for a house
function TeamSystem:get_teams_for_house(house)
    local result = {}
    for _, team in pairs(self.active_teams) do
        if team.house == house then
            table.insert(result, team)
        end
    end
    return result
end

-- Reset for new scenario
function TeamSystem:reset()
    self.team_types = {}
    self.active_teams = {}
    self.next_team_id = 1
end

--============================================================================
-- Debug
--============================================================================

--[[
    Debug dump of team system state.
    Reference: TEAM.H Debug_Dump() pattern
]]
function TeamSystem:Debug_Dump()
    print("TeamSystem:")
    print(string.format("  Team types: %d defined", self:count_team_types()))
    print(string.format("  Active teams: %d", self:count_active_teams()))
    print(string.format("  Next team ID: %d", self.next_team_id))

    -- Dump team types
    for name, team_type in pairs(self.team_types) do
        local member_str = ""
        for _, member in ipairs(team_type.members) do
            if member_str ~= "" then member_str = member_str .. ", " end
            member_str = member_str .. string.format("%s x%d", member.type, member.count or 1)
        end
        print(string.format("  TeamType[%s]: house=%s mission=%d autocreate=%s members=[%s]",
            name, tostring(team_type.house), team_type.mission,
            tostring(team_type.autocreate), member_str))
    end

    -- Dump active teams
    for team_id, team in pairs(self.active_teams) do
        local mission_name = self:get_mission_name(team.mission)
        print(string.format("  ActiveTeam[%d]: type=%s house=%s mission=%s members=%d formed=%s waypoint=%d/%d",
            team_id, team.type_name, tostring(team.house), mission_name,
            #team.members, tostring(team.formed),
            team.current_waypoint, #(team.waypoints or {})))
    end
end

-- Helper: Count team types
function TeamSystem:count_team_types()
    local count = 0
    for _ in pairs(self.team_types) do count = count + 1 end
    return count
end

-- Helper: Count active teams
function TeamSystem:count_active_teams()
    local count = 0
    for _ in pairs(self.active_teams) do count = count + 1 end
    return count
end

-- Helper: Get mission name
function TeamSystem:get_mission_name(mission)
    for name, value in pairs(TeamSystem.MISSION) do
        if value == mission then return name end
    end
    return "UNKNOWN"
end

return TeamSystem
