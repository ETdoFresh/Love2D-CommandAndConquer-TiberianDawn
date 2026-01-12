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

    -- Update waypoint following
    if team.mission == TeamSystem.MISSION.MOVE or
       team.mission == TeamSystem.MISSION.LOOP then
        self:update_waypoint_movement(team)
    end
end

-- Update waypoint-based movement
function TeamSystem:update_waypoint_movement(team)
    if #team.waypoints == 0 then return end

    -- Resolve waypoint (can be index into scenario waypoints or direct coords)
    local waypoint = self:resolve_waypoint(team.waypoints[team.current_waypoint])
    if not waypoint then return end

    -- Check if all members reached waypoint
    local all_reached = true
    local any_moving = false

    for _, entity in ipairs(team.members) do
        local transform = entity:get("transform")
        local mobile = entity:get("mobile")

        if transform then
            local dx = transform.x - waypoint.x
            local dy = transform.y - waypoint.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > 256 then  -- 1 cell tolerance
                all_reached = false

                -- Issue move command if not already moving
                if mobile and not mobile.is_moving then
                    self:move_entity_to(entity, waypoint.x, waypoint.y)
                else
                    any_moving = true
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

return TeamSystem
