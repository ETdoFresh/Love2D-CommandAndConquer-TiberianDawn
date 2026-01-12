--[[
    AI Controller - Computer player decision making
    Implements original C&C AI behavior patterns
    Reference: HOUSE.CPP AI functions, MISSION.H
]]

local Events = require("src.core.events")

local AIController = {}
AIController.__index = AIController

-- AI difficulty settings
AIController.DIFFICULTY = {
    EASY = 1,
    NORMAL = 2,
    HARD = 3
}

-- AI states
AIController.STATE = {
    BUILDING = "building",      -- Building up base
    DEFENDING = "defending",    -- Under attack
    ATTACKING = "attacking",    -- Launching attack
    HARVESTING = "harvesting",  -- Focus on economy
    RETREATING = "retreating"   -- Falling back
}

-- Build priorities
AIController.BUILD_PRIORITY = {
    POWER = 1,
    REFINERY = 2,
    BARRACKS = 3,
    FACTORY = 4,
    DEFENSE = 5,
    TECH = 6,
    SUPERWEAPON = 7
}

function AIController.new(house)
    local self = setmetatable({}, AIController)

    -- Parent house
    self.house = house

    -- AI settings
    self.difficulty = AIController.DIFFICULTY.NORMAL
    self.enabled = true
    self.iq = 100  -- AI intelligence (0-200)

    -- Current state
    self.state = AIController.STATE.BUILDING

    -- Timers
    self.think_timer = 0
    self.think_interval = 1.0  -- Seconds between AI decisions
    self.attack_timer = 0
    self.attack_interval = 120  -- Seconds between attacks

    -- Build queue management
    self.build_list = {}
    self.current_build = nil

    -- Attack management
    self.attack_force = {}
    self.min_attack_force = 5
    self.attack_target = nil

    -- Defense tracking
    self.threat_level = 0
    self.last_attack_time = 0

    -- Harvester management
    self.desired_harvesters = 2

    -- Team management
    self.teams = {}

    return self
end

-- Update AI (call each game tick)
function AIController:update(dt)
    if not self.enabled or not self.house then return end

    -- Update think timer
    self.think_timer = self.think_timer + dt
    if self.think_timer >= self.think_interval then
        self.think_timer = 0
        self:think()
    end

    -- Update attack timer
    self.attack_timer = self.attack_timer + dt
end

-- Main AI decision loop
function AIController:think()
    -- Update state based on situation
    self:update_state()

    -- Make decisions based on state
    if self.state == AIController.STATE.BUILDING then
        self:think_building()
    elseif self.state == AIController.STATE.DEFENDING then
        self:think_defending()
    elseif self.state == AIController.STATE.ATTACKING then
        self:think_attacking()
    elseif self.state == AIController.STATE.HARVESTING then
        self:think_harvesting()
    end

    -- Always consider production
    self:manage_production()
end

-- Update AI state based on situation
function AIController:update_state()
    -- Check if under attack
    if self.threat_level > 50 then
        self.state = AIController.STATE.DEFENDING
        return
    end

    -- Check if should attack
    if self.attack_timer >= self.attack_interval and #self.attack_force >= self.min_attack_force then
        self.state = AIController.STATE.ATTACKING
        return
    end

    -- Check economy
    local harvester_count = self:count_harvesters()
    if harvester_count < self.desired_harvesters then
        self.state = AIController.STATE.HARVESTING
        return
    end

    -- Default to building
    self.state = AIController.STATE.BUILDING
end

-- Building phase logic
function AIController:think_building()
    -- Check what we need
    if not self.house:has_building_type("NUKE") and not self.house:has_building_type("NUK2") then
        -- Need power
        self:queue_build("NUKE", AIController.BUILD_PRIORITY.POWER)
    end

    if not self.house:has_building_type("PROC") then
        -- Need refinery
        self:queue_build("PROC", AIController.BUILD_PRIORITY.REFINERY)
    end

    -- Check for barracks
    local barracks = self.house.side == "GDI" and "PYLE" or "HAND"
    if not self.house:has_building_type(barracks) then
        self:queue_build(barracks, AIController.BUILD_PRIORITY.BARRACKS)
    end

    -- Check for war factory
    if not self.house:has_building_type("WEAP") then
        self:queue_build("WEAP", AIController.BUILD_PRIORITY.FACTORY)
    end

    -- Add defenses
    local defense_count = self:count_defenses()
    if defense_count < 3 then
        local defense = self.house.side == "GDI" and "GTWR" or "ATWR"
        self:queue_build(defense, AIController.BUILD_PRIORITY.DEFENSE)
    end
end

-- Defense phase logic
function AIController:think_defending()
    -- Rally units to defend base
    local base_x, base_y = self:get_base_center()

    for _, unit in ipairs(self.house.units) do
        -- Don't pull harvesters
        if unit.unit_type ~= "HARV" then
            -- Send to defend
            Events.emit("AI_ORDER_UNIT", unit, "guard_area", base_x, base_y)
        end
    end

    -- Reduce threat over time
    self.threat_level = self.threat_level - 1
    if self.threat_level < 0 then
        self.threat_level = 0
    end
end

-- Attack phase logic
function AIController:think_attacking()
    -- Find target
    if not self.attack_target then
        self.attack_target = self:find_attack_target()
    end

    if self.attack_target then
        -- Send attack force
        for _, unit in ipairs(self.attack_force) do
            Events.emit("AI_ORDER_UNIT", unit, "attack", self.attack_target)
        end

        -- Reset attack timer
        self.attack_timer = 0
        self.attack_force = {}
        self.attack_target = nil

        -- Return to building state
        self.state = AIController.STATE.BUILDING
    end
end

-- Harvesting focus logic
function AIController:think_harvesting()
    -- Build harvesters
    if self.house:has_building_type("PROC") then
        self:queue_unit_build("HARV")
    end
end

-- Manage unit production
function AIController:manage_production()
    -- Build units for attack force
    if #self.attack_force < self.min_attack_force * 2 then
        -- Infantry
        self:queue_unit_build("E1")

        -- Vehicles based on side
        if self.house.side == "GDI" then
            self:queue_unit_build("MTNK")
        else
            self:queue_unit_build("LTNK")
        end
    end
end

-- Queue a building for construction
function AIController:queue_build(building_type, priority)
    -- Check if already in queue
    for _, item in ipairs(self.build_list) do
        if item.type == building_type then
            return
        end
    end

    -- Check if we can build it
    if self.house.tech_tree and not self.house.tech_tree:can_build_building(building_type) then
        return
    end

    table.insert(self.build_list, {
        type = building_type,
        priority = priority,
        category = "building"
    })

    -- Sort by priority
    table.sort(self.build_list, function(a, b)
        return a.priority < b.priority
    end)

    Events.emit("AI_QUEUE_BUILD", self.house, building_type)
end

-- Queue a unit for construction
function AIController:queue_unit_build(unit_type)
    Events.emit("AI_QUEUE_UNIT", self.house, unit_type)
end

-- Count harvesters
function AIController:count_harvesters()
    local count = 0
    for _, unit in ipairs(self.house.units) do
        if unit.unit_type == "HARV" then
            count = count + 1
        end
    end
    return count
end

-- Count defense buildings
function AIController:count_defenses()
    local count = 0
    local defense_types = {"GTWR", "ATWR", "GUN", "OBLI", "SAM"}

    for _, building in ipairs(self.house.buildings) do
        for _, def_type in ipairs(defense_types) do
            if building.building_type == def_type then
                count = count + 1
                break
            end
        end
    end
    return count
end

-- Get base center position
function AIController:get_base_center()
    local x, y, count = 0, 0, 0

    for _, building in ipairs(self.house.buildings) do
        if building.x and building.y then
            x = x + building.x
            y = y + building.y
            count = count + 1
        end
    end

    if count > 0 then
        return x / count, y / count
    end

    return 0, 0
end

-- Find attack target (enemy building or unit)
function AIController:find_attack_target()
    -- This would be implemented by the game to find enemy entities
    Events.emit("AI_FIND_TARGET", self.house)
    return nil  -- Will be set by event handler
end

-- Set attack target (called by game)
function AIController:set_attack_target(target)
    self.attack_target = target
end

-- Report threat (called when attacked)
function AIController:report_threat(attacker, target)
    self.threat_level = self.threat_level + 25
    if self.threat_level > 100 then
        self.threat_level = 100
    end
    self.last_attack_time = love.timer.getTime()
end

-- Add unit to attack force
function AIController:add_to_attack_force(unit)
    table.insert(self.attack_force, unit)
end

-- Remove unit from attack force
function AIController:remove_from_attack_force(unit)
    for i, u in ipairs(self.attack_force) do
        if u == unit then
            table.remove(self.attack_force, i)
            return
        end
    end
end

-- Set difficulty
function AIController:set_difficulty(difficulty)
    self.difficulty = difficulty

    -- Adjust parameters based on difficulty
    if difficulty == AIController.DIFFICULTY.EASY then
        self.think_interval = 2.0
        self.attack_interval = 180
        self.min_attack_force = 3
        self.iq = 50
    elseif difficulty == AIController.DIFFICULTY.NORMAL then
        self.think_interval = 1.0
        self.attack_interval = 120
        self.min_attack_force = 5
        self.iq = 100
    elseif difficulty == AIController.DIFFICULTY.HARD then
        self.think_interval = 0.5
        self.attack_interval = 60
        self.min_attack_force = 8
        self.iq = 150
    end
end

-- Enable/disable AI
function AIController:set_enabled(enabled)
    self.enabled = enabled
end

-- Get current state
function AIController:get_state()
    return self.state
end

return AIController
