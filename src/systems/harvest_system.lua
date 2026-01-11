--[[
    Harvest System - Tiberium collection and refinery processing
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")

local HarvestSystem = setmetatable({}, {__index = System})
HarvestSystem.__index = HarvestSystem

-- Tiberium values
HarvestSystem.TIBERIUM_VALUE = 25      -- Credits per load unit
HarvestSystem.HARVEST_RATE = 5          -- Load units per tick
HarvestSystem.UNLOAD_RATE = 10          -- Load units per tick at refinery

function HarvestSystem.new(grid)
    local self = System.new("harvest", {"harvester"})
    setmetatable(self, HarvestSystem)

    self.grid = grid

    -- House credits (indexed by house ID)
    self.credits = {}
    self.storage = {}  -- Maximum storage capacity

    -- Initialize for standard houses
    for i = 0, Constants.HOUSE.COUNT - 1 do
        self.credits[i] = 0
        self.storage[i] = 0
    end

    return self
end

function HarvestSystem:init()
    -- Calculate initial storage from buildings
    self:recalculate_storage()
end

function HarvestSystem:update(dt, entities)
    for _, entity in ipairs(entities) do
        self:process_harvester(dt, entity)
    end
end

function HarvestSystem:process_harvester(dt, entity)
    local harvester = entity:get("harvester")
    local transform = entity:get("transform")
    local owner = entity:get("owner")
    local mobile = entity:has("mobile") and entity:get("mobile") or nil

    if not transform or not owner then
        return
    end

    -- Check if at refinery
    if harvester.refinery then
        local refinery = self.world:get_entity(harvester.refinery)
        if refinery and refinery:is_alive() then
            self:process_at_refinery(entity, harvester, refinery, owner)
            return
        else
            -- Refinery destroyed, find new one
            harvester.refinery = nil
        end
    end

    -- Check if full
    if harvester.tiberium_load >= harvester.max_load then
        -- Find refinery to return to
        local refinery = self:find_refinery(entity)
        if refinery then
            harvester.refinery = refinery.id

            -- Set mission to return
            if entity:has("mission") then
                entity:get("mission").mission_type = Constants.MISSION.RETURN
            end

            -- Move to refinery
            if mobile then
                local ref_transform = refinery:get("transform")
                local movement_system = self.world:get_system("movement")
                if movement_system then
                    movement_system:move_to(entity, ref_transform.x, ref_transform.y)
                end
            end
        end
        return
    end

    -- Try to harvest from current cell
    if self.grid and not (mobile and mobile.is_moving) then
        local cell = self.grid:get_cell(transform.cell_x, transform.cell_y)
        if cell and cell:has_tiberium() then
            local harvested = cell:harvest_tiberium(HarvestSystem.HARVEST_RATE)
            harvester.tiberium_load = harvester.tiberium_load + harvested
        else
            -- No tiberium here, look for some
            local tib_cell = self:find_tiberium(transform.cell_x, transform.cell_y)
            if tib_cell and mobile then
                local movement_system = self.world:get_system("movement")
                if movement_system then
                    local lx, ly = tib_cell:to_leptons()
                    movement_system:move_to(entity, lx, ly)
                end
            end
        end
    end
end

function HarvestSystem:process_at_refinery(entity, harvester, refinery, owner)
    -- Dock timer for animation
    if harvester.dock_timer > 0 then
        harvester.dock_timer = harvester.dock_timer - 1
        return
    end

    -- Unload tiberium
    if harvester.tiberium_load > 0 then
        local unload = math.min(harvester.tiberium_load, HarvestSystem.UNLOAD_RATE)
        harvester.tiberium_load = harvester.tiberium_load - unload

        -- Add credits
        local credits_earned = unload * HarvestSystem.TIBERIUM_VALUE
        self:add_credits(owner.house, credits_earned)
    else
        -- Done unloading, go back to harvesting
        harvester.refinery = nil

        if entity:has("mission") then
            entity:get("mission").mission_type = Constants.MISSION.HARVEST
        end
    end
end

function HarvestSystem:find_refinery(harvester_entity)
    local owner = harvester_entity:get("owner")
    local transform = harvester_entity:get("transform")

    if not owner or not transform then
        return nil
    end

    local best_refinery = nil
    local best_dist = math.huge

    local buildings = self.world:get_entities_with("building", "owner", "transform")

    for _, building in ipairs(buildings) do
        local building_data = building:get("building")
        local building_owner = building:get("owner")

        if building_owner.house == owner.house then
            -- Check if it's a refinery
            if building_data.structure_type == "PROC" then
                local building_transform = building:get("transform")
                local dx = building_transform.x - transform.x
                local dy = building_transform.y - transform.y
                local dist = dx * dx + dy * dy

                if dist < best_dist then
                    best_dist = dist
                    best_refinery = building
                end
            end
        end
    end

    return best_refinery
end

function HarvestSystem:find_tiberium(start_x, start_y)
    if not self.grid then
        return nil
    end

    -- Search in expanding circles
    for radius = 1, 20 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local cell = self.grid:get_cell(start_x + dx, start_y + dy)
                    if cell and cell:has_tiberium() then
                        return cell
                    end
                end
            end
        end
    end

    return nil
end

function HarvestSystem:add_credits(house, amount)
    self.credits[house] = (self.credits[house] or 0) + amount

    -- Cap at storage
    local max_storage = self.storage[house] or 0
    if max_storage > 0 and self.credits[house] > max_storage then
        self.credits[house] = max_storage
    end

    self:emit(Events.EVENTS.CREDITS_CHANGED, house, self.credits[house])
end

function HarvestSystem:spend_credits(house, amount)
    local current = self.credits[house] or 0
    if current >= amount then
        self.credits[house] = current - amount
        self:emit(Events.EVENTS.CREDITS_CHANGED, house, self.credits[house])
        return true
    end
    return false
end

function HarvestSystem:get_credits(house)
    return self.credits[house] or 0
end

function HarvestSystem:set_credits(house, amount)
    self.credits[house] = amount
    self:emit(Events.EVENTS.CREDITS_CHANGED, house, amount)
end

function HarvestSystem:recalculate_storage()
    -- Reset storage
    for i = 0, Constants.HOUSE.COUNT - 1 do
        self.storage[i] = 0
    end

    -- Find all silos and refineries
    local buildings = self.world:get_entities_with("building", "owner")

    for _, building in ipairs(buildings) do
        local building_data = building:get("building")
        local owner = building:get("owner")

        if building_data.structure_type == "PROC" then
            -- Refinery provides 1000 storage
            self.storage[owner.house] = (self.storage[owner.house] or 0) + 1000
        elseif building_data.structure_type == "SILO" then
            -- Silo provides 1500 storage
            self.storage[owner.house] = (self.storage[owner.house] or 0) + 1500
        end
    end
end

function HarvestSystem:get_storage(house)
    return self.storage[house] or 0
end

-- Grow tiberium over time
function HarvestSystem:grow_tiberium()
    if not self.grid then
        return
    end

    -- This would be called periodically (every few seconds)
    for cell in self.grid:iterate() do
        if cell:has_tiberium() then
            -- Chance to spread to adjacent cells
            if math.random() < 0.01 then  -- 1% chance per tick
                local neighbors = self.grid:get_neighbors(cell.x, cell.y)
                for _, neighbor in ipairs(neighbors) do
                    if not neighbor:has_tiberium() and
                       neighbor.template_type == 0 and  -- Clear terrain
                       neighbor.overlay < 0 then
                        -- Spread tiberium
                        neighbor.overlay = 6  -- OVERLAY_TIBERIUM1
                        break
                    end
                end
            end
        end
    end
end

return HarvestSystem
