--[[
    Aircraft System - Handles aircraft landing, takeoff, and rearming
    Reference: Original C&C AIRCRAFT.CPP, AIRCRAFT.H

    Key behaviors from original:
    - FLIGHT_LEVEL = 24 pixels altitude for cruising
    - Aircraft land on helipads to rearm/repair
    - Fixed-wing aircraft (A10) fly straight, helicopters hover
    - Helicopters bob/jitter during flight
    - Landing/takeoff is gradual altitude change
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")

local AircraftSystem = setmetatable({}, {__index = System})
AircraftSystem.__index = AircraftSystem

-- Constants from original C&C (AIRCRAFT.H)
AircraftSystem.FLIGHT_LEVEL = 24           -- Cruising altitude in pixels
AircraftSystem.TAKEOFF_SPEED = 2           -- Pixels per tick during takeoff
AircraftSystem.LANDING_SPEED = 1           -- Pixels per tick during landing
AircraftSystem.HOVER_JITTER_PERIOD = 16    -- Frames for hover bob cycle

-- Aircraft states
AircraftSystem.STATE = {
    GROUNDED = "grounded",       -- On helipad, landed
    TAKING_OFF = "taking_off",   -- Ascending from helipad
    FLYING = "flying",           -- At cruise altitude
    LANDING = "landing",         -- Descending to land
    HOVERING = "hovering",       -- Helicopter hovering in place
    RETURNING = "returning"      -- Flying back to helipad for rearm
}

function AircraftSystem.new()
    local self = System.new("aircraft", {"aircraft", "transform"})
    setmetatable(self, AircraftSystem)

    -- Track helipad assignments
    self.helipad_aircraft = {}  -- helipad_entity_id -> aircraft_entity_id
    self.aircraft_helipad = {}  -- aircraft_entity_id -> helipad_entity_id

    -- Jitter tracking for helicopter hover
    self.jitter_timers = {}  -- entity_id -> jitter_frame

    return self
end

function AircraftSystem:init()
    -- Listen for aircraft spawned events
    Events.on(Events.EVENTS.UNIT_BUILT, function(entity, house)
        if entity:has("aircraft") then
            self:on_aircraft_built(entity, house)
        end
    end)

    -- Listen for helipad destroyed
    Events.on(Events.EVENTS.ENTITY_DESTROYED, function(entity)
        if entity:has("building") then
            local building = entity:get("building")
            if building.building_type == "HPAD" then
                self:on_helipad_destroyed(entity)
            end
        end
    end)
end

-- Called when a new aircraft is built
function AircraftSystem:on_aircraft_built(aircraft, house)
    local aircraft_comp = aircraft:get("aircraft")

    -- Find an available helipad for this aircraft
    local helipad = self:find_available_helipad(house)
    if helipad then
        self:assign_helipad(aircraft, helipad)
        aircraft_comp.landed = true
        aircraft_comp.altitude = 0
    else
        -- No helipad, start in flight
        aircraft_comp.landed = false
        aircraft_comp.altitude = AircraftSystem.FLIGHT_LEVEL
    end
end

-- Called when a helipad is destroyed
function AircraftSystem:on_helipad_destroyed(helipad)
    local helipad_id = helipad.id
    local aircraft_id = self.helipad_aircraft[helipad_id]

    if aircraft_id then
        -- Clear the assignment
        self.helipad_aircraft[helipad_id] = nil
        self.aircraft_helipad[aircraft_id] = nil

        -- Aircraft needs to find a new helipad
        local aircraft = self.world and self.world:get_entity(aircraft_id)
        if aircraft and aircraft:is_alive() then
            local aircraft_comp = aircraft:get("aircraft")
            aircraft_comp.helipad = nil

            -- Find a new helipad
            local owner = aircraft:get("owner")
            if owner then
                local new_helipad = self:find_available_helipad(owner.house)
                if new_helipad then
                    self:assign_helipad(aircraft, new_helipad)
                end
            end
        end
    end
end

-- Find an available helipad for a house
function AircraftSystem:find_available_helipad(house)
    if not self.world then return nil end

    local buildings = self.world:get_entities_with("building")
    for _, building in ipairs(buildings) do
        local building_comp = building:get("building")
        local owner = building:get("owner")

        if building_comp.building_type == "HPAD" and
           owner and owner.house == house and
           not self.helipad_aircraft[building.id] then
            return building
        end
    end

    return nil
end

-- Assign a helipad to an aircraft
function AircraftSystem:assign_helipad(aircraft, helipad)
    local aircraft_comp = aircraft:get("aircraft")

    -- Clear any previous assignment
    local old_helipad = self.aircraft_helipad[aircraft.id]
    if old_helipad then
        self.helipad_aircraft[old_helipad] = nil
    end

    -- Set new assignment
    aircraft_comp.helipad = helipad.id
    self.helipad_aircraft[helipad.id] = aircraft.id
    self.aircraft_helipad[aircraft.id] = helipad.id
end

-- Update all aircraft
function AircraftSystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:update_aircraft(dt, entity)
    end
end

-- Update a single aircraft
function AircraftSystem:update_aircraft(dt, entity)
    local aircraft = entity:get("aircraft")
    local transform = entity:get("transform")

    -- Update altitude based on state
    if aircraft.landed then
        -- On the ground, no altitude updates needed
        aircraft.altitude = 0
        return
    end

    -- Handle landing
    if aircraft.is_landing then
        self:process_landing(entity, aircraft, transform)
        return
    end

    -- Handle takeoff
    if aircraft.is_taking_off then
        self:process_takeoff(entity, aircraft, transform)
        return
    end

    -- In flight - check if needs to return for rearm
    if aircraft.altitude >= AircraftSystem.FLIGHT_LEVEL then
        -- Apply helicopter jitter if applicable
        local unit_data = self:get_aircraft_data(aircraft.aircraft_type)
        if unit_data and unit_data.rotors then
            self:apply_hover_jitter(entity, aircraft)
        end

        -- Check ammo - if out, return to helipad
        if entity:has("combat") then
            local combat = entity:get("combat")
            if combat.ammo and combat.ammo <= 0 then
                self:return_to_helipad(entity, aircraft)
            end
        end
    end
end

-- Process landing sequence
function AircraftSystem:process_landing(entity, aircraft, transform)
    aircraft.altitude = aircraft.altitude - AircraftSystem.LANDING_SPEED

    if aircraft.altitude <= 0 then
        aircraft.altitude = 0
        aircraft.is_landing = false
        aircraft.landed = true

        -- Snap to helipad position if assigned
        local helipad = self:get_assigned_helipad(entity)
        if helipad then
            local helipad_transform = helipad:get("transform")
            transform.x = helipad_transform.x
            transform.y = helipad_transform.y
        end

        -- Trigger rearm
        self:rearm_aircraft(entity, aircraft)

        -- Emit landed event
        Events.emit("AIRCRAFT_LANDED", entity)
    end
end

-- Process takeoff sequence
function AircraftSystem:process_takeoff(entity, aircraft, transform)
    aircraft.altitude = aircraft.altitude + AircraftSystem.TAKEOFF_SPEED

    -- Adjust speed during takeoff (from original)
    local speed_pct = aircraft.altitude / AircraftSystem.FLIGHT_LEVEL

    if entity:has("mobile") then
        local mobile = entity:get("mobile")
        local unit_data = self:get_aircraft_data(aircraft.aircraft_type)
        if unit_data then
            mobile.speed = unit_data.speed * speed_pct
        end
    end

    if aircraft.altitude >= AircraftSystem.FLIGHT_LEVEL then
        aircraft.altitude = AircraftSystem.FLIGHT_LEVEL
        aircraft.is_taking_off = false
        aircraft.landed = false

        -- Full speed
        if entity:has("mobile") then
            local mobile = entity:get("mobile")
            local unit_data = self:get_aircraft_data(aircraft.aircraft_type)
            if unit_data then
                mobile.speed = unit_data.speed
            end
        end

        -- Emit takeoff complete event
        Events.emit("AIRCRAFT_AIRBORNE", entity)
    end
end

-- Apply hover jitter for helicopters
function AircraftSystem:apply_hover_jitter(entity, aircraft)
    local jitter_frame = self.jitter_timers[entity.id] or 0
    jitter_frame = (jitter_frame + 1) % AircraftSystem.HOVER_JITTER_PERIOD

    self.jitter_timers[entity.id] = jitter_frame

    -- Jitter pattern from original: {0,0,0,0,1,1,1,0,0,0,0,0,-1,-1,-1,0}
    local jitter_pattern = {0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, -1, -1, -1, 0}
    local jitter = jitter_pattern[jitter_frame + 1] or 0

    -- Apply altitude jitter
    aircraft.visual_altitude_offset = jitter
end

-- Get aircraft data from production system
function AircraftSystem:get_aircraft_data(aircraft_type)
    if not self.world then return nil end

    local production = self.world:get_system("production")
    if production and production.unit_data then
        return production.unit_data[aircraft_type]
    end

    return nil
end

-- Get the helipad assigned to this aircraft
function AircraftSystem:get_assigned_helipad(aircraft)
    local aircraft_comp = aircraft:get("aircraft")
    if not aircraft_comp.helipad then return nil end

    return self.world and self.world:get_entity(aircraft_comp.helipad)
end

-- Order aircraft to return to helipad
function AircraftSystem:return_to_helipad(entity, aircraft)
    local helipad = self:get_assigned_helipad(entity)

    if not helipad then
        -- Try to find a new helipad
        local owner = entity:get("owner")
        if owner then
            helipad = self:find_available_helipad(owner.house)
            if helipad then
                self:assign_helipad(entity, helipad)
            end
        end
    end

    if helipad then
        -- Set destination to helipad
        local helipad_transform = helipad:get("transform")

        if entity:has("mission") then
            local mission = entity:get("mission")
            mission.mission_type = Constants.MISSION.ENTER
            mission.target = helipad.id
        end

        -- Signal to AI system to handle return
        Events.emit("AIRCRAFT_RETURNING", entity, helipad)
    end
end

-- Command aircraft to take off
function AircraftSystem:takeoff(entity)
    local aircraft = entity:get("aircraft")

    if not aircraft.landed then return false end

    aircraft.landed = false
    aircraft.is_taking_off = true
    aircraft.is_landing = false

    -- Break helipad radio contact (original behavior)
    Events.emit("AIRCRAFT_TAKEOFF", entity)

    return true
end

-- Command aircraft to land at target
function AircraftSystem:land(entity, target_x, target_y)
    local aircraft = entity:get("aircraft")

    if aircraft.landed then return false end
    if aircraft.altitude < AircraftSystem.FLIGHT_LEVEL then return false end

    aircraft.is_landing = true
    aircraft.is_taking_off = false

    -- Set destination
    if entity:has("mobile") then
        local mobile = entity:get("mobile")
        mobile.destination_x = target_x
        mobile.destination_y = target_y
    end

    Events.emit("AIRCRAFT_LANDING", entity)

    return true
end

-- Rearm aircraft at helipad
function AircraftSystem:rearm_aircraft(entity, aircraft)
    local unit_data = self:get_aircraft_data(aircraft.aircraft_type)
    if not unit_data then return end

    -- Restore ammo
    if entity:has("combat") and unit_data.ammo then
        local combat = entity:get("combat")
        combat.ammo = unit_data.ammo
    end

    -- Repair damage (helipads repair aircraft)
    if entity:has("health") then
        local health = entity:get("health")
        local max_hp = unit_data.hitpoints or health.max_hp
        health.hp = max_hp
        health.max_hp = max_hp
    end

    Events.emit("AIRCRAFT_REARMED", entity)
end

-- Check if aircraft needs rearm (out of ammo)
function AircraftSystem:needs_rearm(entity)
    if not entity:has("combat") then return false end

    local combat = entity:get("combat")
    return combat.ammo and combat.ammo <= 0
end

-- Check if aircraft is in flight
function AircraftSystem:is_flying(entity)
    local aircraft = entity:get("aircraft")
    return aircraft.altitude >= AircraftSystem.FLIGHT_LEVEL and
           not aircraft.is_landing and
           not aircraft.is_taking_off
end

-- Check if aircraft is on ground
function AircraftSystem:is_grounded(entity)
    local aircraft = entity:get("aircraft")
    return aircraft.landed and aircraft.altitude == 0
end

-- Get visual altitude (includes jitter)
function AircraftSystem:get_visual_altitude(entity)
    local aircraft = entity:get("aircraft")
    local base_altitude = aircraft.altitude or 0
    local jitter = aircraft.visual_altitude_offset or 0
    return base_altitude + jitter
end

return AircraftSystem
