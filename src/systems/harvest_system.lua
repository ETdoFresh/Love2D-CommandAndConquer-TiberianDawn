--[[
    Harvest System - Tiberium collection and refinery processing
    Reference: CELL.CPP, MAP.CPP from original C&C source
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")
local Cell = require("src.map.cell")
local Theater = require("src.map.theater")
local Random = require("src.util.random")

local HarvestSystem = setmetatable({}, {__index = System})
HarvestSystem.__index = HarvestSystem

-- Tiberium values
HarvestSystem.TIBERIUM_VALUE = 25      -- Credits per load unit
HarvestSystem.HARVEST_RATE = 5          -- Load units per tick
HarvestSystem.UNLOAD_RATE = 10          -- Load units per tick at refinery

-- Tiberium growth/spread constants (from original C&C MAP.CPP)
HarvestSystem.TIBERIUM_GROWTH_INTERVAL = 450  -- Ticks between growth cycles (~30 sec at 15 FPS)
HarvestSystem.TIBERIUM_SPREAD_INTERVAL = 900  -- Ticks between spread cycles (~60 sec)
HarvestSystem.TIBERIUM_MAX_LEVEL = 11         -- Max overlay data level (0-11 = 12 levels)
HarvestSystem.TIBERIUM_SPREAD_THRESHOLD = 6   -- Min level to spread (high-value tiberium)
HarvestSystem.TIBERIUM_OVERLAY_BASE = 6       -- OVERLAY_TIBERIUM1 in DEFINES.H

-- Tiberium damage constants (from original INFANTRY.CPP Per_Cell_Process)
HarvestSystem.TIBERIUM_DAMAGE = 2           -- Damage per cell when standing on Tiberium
HarvestSystem.TIBERIUM_DAMAGE_INTERVAL = 15 -- Ticks between damage (~1 second at 15 FPS)

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

    -- Tiberium growth tracking (like original TiberiumGrowth/TiberiumSpread arrays)
    self.growth_cells = {}      -- Cells that can grow (increase overlay level)
    self.spread_cells = {}      -- Cells that can spread to neighbors
    self.growth_timer = 0
    self.spread_timer = 0
    self.tiberium_enabled = true  -- Can be disabled in scenario settings

    -- Tiberium damage tracking
    self.tiberium_damage_timer = 0

    return self
end

function HarvestSystem:init()
    -- Calculate initial storage from buildings
    self:recalculate_storage()

    -- Scan map for initial tiberium cells
    self:scan_tiberium()
end

-- Scan map for tiberium cells and categorize for growth/spread
function HarvestSystem:scan_tiberium()
    self.growth_cells = {}
    self.spread_cells = {}

    if not self.grid then return end

    for cell in self.grid:iterate() do
        if cell:has_tiberium() then
            self:categorize_tiberium_cell(cell)
        end
    end
end

-- Categorize a tiberium cell for growth or spread potential
function HarvestSystem:categorize_tiberium_cell(cell)
    local level = cell.overlay - HarvestSystem.TIBERIUM_OVERLAY_BASE

    -- Cells below max level can grow
    if level < HarvestSystem.TIBERIUM_MAX_LEVEL then
        table.insert(self.growth_cells, {x = cell.x, y = cell.y})
    end

    -- High-value cells can spread
    if level >= HarvestSystem.TIBERIUM_SPREAD_THRESHOLD then
        table.insert(self.spread_cells, {x = cell.x, y = cell.y})
    end
end

function HarvestSystem:update(dt, entities)
    -- Process harvesters
    for _, entity in ipairs(entities) do
        self:process_harvester(dt, entity)
    end

    -- Process tiberium growth/spread (only if enabled)
    if self.tiberium_enabled then
        self:update_tiberium_growth()
        self:update_tiberium_spread()
        self:update_tiberium_damage()
    end
end

-- Update tiberium growth (cells increase in value)
function HarvestSystem:update_tiberium_growth()
    self.growth_timer = self.growth_timer + 1

    if self.growth_timer < HarvestSystem.TIBERIUM_GROWTH_INTERVAL then
        return
    end
    self.growth_timer = 0

    -- Process growth - pick random cells from growth list (deterministic for multiplayer)
    -- Use density multiplier to process more cells in dense tiberium areas
    local max_tries = math.min(3, #self.growth_cells)
    for _ = 1, max_tries do
        if #self.growth_cells == 0 then break end

        local pick = Random.range(1, #self.growth_cells)
        local pos = self.growth_cells[pick]
        local cell = self.grid:get_cell(pos.x, pos.y)

        if cell and cell:has_tiberium() then
            local level = cell.overlay - HarvestSystem.TIBERIUM_OVERLAY_BASE

            -- Apply density-based growth multiplier (original behavior)
            -- Tiberium surrounded by more tiberium grows faster
            local density_mult = self:get_density_growth_multiplier(cell)
            local growth_chance = density_mult / 2.5  -- Normalize to 0.4 - 1.0 range

            if level < HarvestSystem.TIBERIUM_MAX_LEVEL and Random.percent(math.floor(growth_chance * 100)) then
                -- Grow tiberium (increase overlay level)
                cell.overlay = cell.overlay + 1
                level = level + 1

                -- Check if cell should now be in spread list
                if level >= HarvestSystem.TIBERIUM_SPREAD_THRESHOLD then
                    table.insert(self.spread_cells, {x = cell.x, y = cell.y})
                end

                -- If at max, remove from growth list
                if level >= HarvestSystem.TIBERIUM_MAX_LEVEL then
                    table.remove(self.growth_cells, pick)
                end
            else
                -- Already at max, remove from growth list
                table.remove(self.growth_cells, pick)
            end
        else
            -- Cell no longer has tiberium, remove from list
            table.remove(self.growth_cells, pick)
        end
    end
end

-- Update tiberium spread (cells spread to neighbors)
function HarvestSystem:update_tiberium_spread()
    self.spread_timer = self.spread_timer + 1

    if self.spread_timer < HarvestSystem.TIBERIUM_SPREAD_INTERVAL then
        return
    end
    self.spread_timer = 0

    -- Process spread - pick random cells from spread list (deterministic for multiplayer)
    local max_tries = math.min(2, #self.spread_cells)
    for _ = 1, max_tries do
        if #self.spread_cells == 0 then break end

        local pick = Random.range(1, #self.spread_cells)
        local pos = self.spread_cells[pick]
        local cell = self.grid:get_cell(pos.x, pos.y)

        if cell and cell:has_tiberium() then
            -- Try to spread to a random adjacent cell
            local spread_success = self:try_spread_tiberium(cell)

            -- Remove from spread list (will be re-added on next scan if still eligible)
            table.remove(self.spread_cells, pick)
        else
            -- Cell no longer has tiberium, remove from list
            table.remove(self.spread_cells, pick)
        end
    end

    -- Periodically rescan to repopulate lists
    if #self.growth_cells == 0 and #self.spread_cells == 0 then
        self:scan_tiberium()
    end
end

-- Try to spread tiberium from a source cell to an adjacent cell
function HarvestSystem:try_spread_tiberium(source_cell)
    if not self.grid then return false end

    -- Get all neighbors and try random directions (like original)
    local neighbors = self.grid:get_neighbors(source_cell.x, source_cell.y)
    if #neighbors == 0 then return false end

    -- Shuffle neighbors for random spread direction (deterministic for multiplayer)
    Random.shuffle(neighbors)

    for _, neighbor in ipairs(neighbors) do
        -- Check if cell is valid for tiberium spread
        if not neighbor:has_tiberium() and
           neighbor.overlay < 0 and                      -- No overlay
           not neighbor:has_flag_set(Cell.FLAG.BUILDING) and  -- No building
           neighbor.template_type == 0 then              -- Clear terrain

            -- Spread tiberium to this cell
            neighbor.overlay = HarvestSystem.TIBERIUM_OVERLAY_BASE  -- Start at level 0
            neighbor.overlay_data = 1

            -- Add new cell to growth list
            table.insert(self.growth_cells, {x = neighbor.x, y = neighbor.y})

            return true
        end
    end

    return false
end

-- Count adjacent tiberium cells for density-based growth bonus (original behavior)
function HarvestSystem:count_adjacent_tiberium(cell)
    if not self.grid then return 0 end

    local count = 0
    local neighbors = self.grid:get_neighbors(cell.x, cell.y)

    for _, neighbor in ipairs(neighbors) do
        if neighbor:has_tiberium() then
            count = count + 1
        end
    end

    return count
end

-- Get growth rate multiplier based on surrounding tiberium density
-- Original C&C: Tiberium grows faster when surrounded by more tiberium
function HarvestSystem:get_density_growth_multiplier(cell)
    local adjacent_count = self:count_adjacent_tiberium(cell)

    -- More adjacent tiberium = faster growth
    -- 0 adjacent: 1x (isolated, slow growth)
    -- 1-2 adjacent: 1.5x
    -- 3-4 adjacent: 2x
    -- 5+ adjacent: 2.5x (dense cluster, fast growth)
    if adjacent_count >= 5 then
        return 2.5
    elseif adjacent_count >= 3 then
        return 2.0
    elseif adjacent_count >= 1 then
        return 1.5
    else
        return 1.0
    end
end

-- Damage infantry standing on Tiberium (from original INFANTRY.CPP Per_Cell_Process)
-- Infantry takes 2 damage per tick when standing on Tiberium, except Chem Warriors (E5)
function HarvestSystem:update_tiberium_damage()
    self.tiberium_damage_timer = self.tiberium_damage_timer + 1

    if self.tiberium_damage_timer < HarvestSystem.TIBERIUM_DAMAGE_INTERVAL then
        return
    end
    self.tiberium_damage_timer = 0

    if not self.world or not self.grid then return end

    -- Get all infantry units
    local infantry = self.world:get_entities_with("infantry", "transform", "health")

    for _, entity in ipairs(infantry) do
        if entity:is_alive() then
            local infantry_data = entity:get("infantry")
            local transform = entity:get("transform")
            local health = entity:get("health")

            -- Check if immune to Tiberium (Chem Warriors)
            if infantry_data and infantry_data.immune_tiberium then
                goto continue
            end

            -- Get cell at infantry position
            local cell = self.grid:get_cell(transform.cell_x, transform.cell_y)
            if cell and cell:has_tiberium() then
                -- Apply Tiberium damage with WARHEAD_FIRE type
                local damage = HarvestSystem.TIBERIUM_DAMAGE

                -- Reduce health
                health.hp = health.hp - damage

                -- Check for death
                if health.hp <= 0 then
                    health.hp = 0
                    -- Emit death event (combat system will handle destruction)
                    Events.emit(Events.EVENTS.UNIT_KILLED, entity, nil, "tiberium")
                end
            end

            ::continue::
        end
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

-- Enable/disable tiberium growth (can be set by scenario)
function HarvestSystem:set_tiberium_enabled(enabled)
    self.tiberium_enabled = enabled
end

-- Get tiberium value for a cell based on overlay data
function HarvestSystem:get_tiberium_value(cell)
    if not cell or not cell:has_tiberium() then
        return 0
    end

    -- Get overlay data from Theater
    local overlay_data = Theater.get_overlay_by_id(cell.overlay)
    if overlay_data and overlay_data.tiberium_value then
        return overlay_data.tiberium_value
    end

    -- Fallback: calculate from level
    local level = cell.overlay - HarvestSystem.TIBERIUM_OVERLAY_BASE
    return (level + 1) * HarvestSystem.TIBERIUM_VALUE
end

-- Get growth params from data or use defaults
function HarvestSystem:get_growth_params()
    local params = Theater.get_tiberium_growth_params()
    return {
        growth_rate = params.growth_rate or 0.02,
        spread_chance = params.spread_chance or 0.001,
        max_spread_distance = params.max_spread_distance or 2,
        infantry_damage = params.infantry_damage_per_tick or HarvestSystem.TIBERIUM_DAMAGE
    }
end

return HarvestSystem
