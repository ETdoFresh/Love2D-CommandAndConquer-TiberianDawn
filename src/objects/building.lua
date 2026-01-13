--[[
    BuildingClass - Building/structure implementation

    Port of BUILDING.H/CPP from the original C&C source.

    Buildings are stationary structures that include:
    - Production buildings (Barracks, War Factory, Airstrip)
    - Power buildings (Power Plant, Advanced Power Plant)
    - Defense buildings (Guard Tower, Obelisk, SAM Site)
    - Support buildings (Refinery, Repair Facility, Helipad)
    - Special buildings (Construction Yard, Temple of Nod, Ion Cannon)

    Key systems:
    - BState state machine for building states
    - Power production/consumption
    - Factory integration for unit production
    - Repair system
    - Capture system (engineers)

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/BUILDING.H/CPP
]]

local Class = require("src.objects.class")
local TechnoClass = require("src.objects.techno")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create BuildingClass extending TechnoClass
local BuildingClass = Class.extend(TechnoClass, "BuildingClass")

--============================================================================
-- Constants
--============================================================================

-- Building state machine states
BuildingClass.BSTATE = {
    NONE = -1,          -- No state
    CONSTRUCTION = 0,   -- Being built
    IDLE = 1,           -- Idle, not doing anything
    ACTIVE = 2,         -- Active/operating
    FULL = 3,           -- Full (refinery with harvester, etc.)
    AUX1 = 4,           -- Auxiliary state 1
    AUX2 = 5,           -- Auxiliary state 2
}

-- Building types (common ones)
BuildingClass.BUILDING = {
    NONE = -1,
    WEAP = 0,           -- Weapons Factory
    GTWR = 1,           -- Guard Tower
    ATWR = 2,           -- Advanced Guard Tower
    OBLI = 3,           -- Obelisk of Light
    FACT = 4,           -- Construction Yard
    PROC = 5,           -- Refinery
    SILO = 6,           -- Tiberium Silo
    HPAD = 7,           -- Helipad
    SAM = 8,            -- SAM Site
    AFLD = 9,           -- Airstrip
    NUKE = 10,          -- Power Plant
    NUK2 = 11,          -- Advanced Power Plant
    HOSP = 12,          -- Hospital
    BARR = 13,          -- Barracks/Hand of Nod
    TMPL = 14,          -- Temple of Nod
    EYE = 15,           -- Advanced Comm Center
    FIX = 16,           -- Repair Facility
}

-- Power constants
BuildingClass.POWER = {
    NONE = 0,
    LOW = 50,
    MEDIUM = 100,
    HIGH = 200,
}

-- Repair constants
BuildingClass.REPAIR_RATE = 2       -- Health per repair tick
BuildingClass.REPAIR_COST = 1       -- Credits per repair tick

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new BuildingClass.

    @param type - BuildingTypeClass defining this building
    @param house - HouseClass owner
]]
function BuildingClass:init(type, house)
    -- Call parent constructor
    TechnoClass.init(self, house)

    -- Store type reference
    self.Class = type

    --[[
        Current building state.
        Default to IDLE; CONSTRUCTION is only for buildings being placed.
    ]]
    self.BState = BuildingClass.BSTATE.IDLE

    --[[
        Animation frame for current state.
    ]]
    self.StateFrame = 0

    --[[
        Pointer to factory object (for production buildings).
    ]]
    self.Factory = nil

    --[[
        Power output (for power plants).
    ]]
    self.PowerOutput = 0

    --[[
        Power drain (consumption).
    ]]
    self.PowerDrain = 0

    --[[
        Is this building currently repairing?
    ]]
    self.IsRepairing = false

    --[[
        Repair countdown timer.
    ]]
    self.RepairTimer = 0

    --[[
        Last strength value (for detecting damage).
    ]]
    self.LastStrength = 0

    --[[
        Stored Tiberium (for refineries and silos).
    ]]
    self.TiberiumStored = 0

    --[[
        Maximum Tiberium storage capacity.
    ]]
    self.TiberiumCapacity = 0

    --[[
        Is this building captured? (has enemy infiltrated)
    ]]
    self.IsCaptured = false

    --[[
        Is this building sold/selling?
    ]]
    self.IsSelling = false

    --[[
        Sell countdown timer.
    ]]
    self.SellTimer = 0

    --[[
        Construction/upgrade progress (0-100%).
    ]]
    self.BuildProgress = 0

    --[[
        Target building is firing at (for defenses).
    ]]
    self.FireTarget = Target.TARGET_NONE

    --[[
        Turret facing (for turrets that rotate).
    ]]
    self.TurretFacing = 0

    --[[
        Animation timer.
    ]]
    self.AnimTimer = 0

    --[[
        Sabotage countdown (C4 attached).
    ]]
    self.SabotageTimer = 0

    -- Set initial type-based properties
    if type then
        self.Strength = type.MaxStrength or 100
        self.MaxStrength = self.Strength
        self.LastStrength = self.Strength

        -- Set power properties
        self.PowerOutput = type.PowerOutput or 0
        self.PowerDrain = type.PowerDrain or 0

        -- Set storage capacity
        self.TiberiumCapacity = type.StorageCapacity or 0

        -- Buildings start as completed
        self.BuildProgress = 100
    else
        -- Default values when no type provided
        self.Strength = 100
        self.MaxStrength = 100
        self.LastStrength = 100
        self.BuildProgress = 100
    end
end

--============================================================================
-- Type Access
--============================================================================

--[[
    Get the BuildingTypeClass for this building.
]]
function BuildingClass:Techno_Type_Class()
    return self.Class
end

--[[
    Get the building type class (alias).
]]
function BuildingClass:Class_Of()
    return self.Class
end

--============================================================================
-- State Machine
--============================================================================

--[[
    Get current building state.
]]
function BuildingClass:Get_State()
    return self.BState
end

--[[
    Set building state.

    @param state - BStateType to set
]]
function BuildingClass:Set_State(state)
    if self.BState ~= state then
        self.BState = state
        self.StateFrame = 0

        -- State change callbacks
        self:On_State_Change(state)
    end
end

--[[
    Called when state changes.
    Override for specific building behaviors.

    @param state - New state
]]
function BuildingClass:On_State_Change(state)
    -- Override in derived building types
end

--[[
    Check if building is operational.
]]
function BuildingClass:Is_Operational()
    return self.BState ~= BuildingClass.BSTATE.CONSTRUCTION and
           self.BState ~= BuildingClass.BSTATE.NONE and
           self.Strength > 0
end

--[[
    Check if building is being constructed.
]]
function BuildingClass:Is_Under_Construction()
    return self.BState == BuildingClass.BSTATE.CONSTRUCTION
end

--============================================================================
-- Power System
--============================================================================

--[[
    Get power output.
]]
function BuildingClass:Power_Output()
    if not self:Is_Operational() then
        return 0
    end

    -- Damaged buildings produce less power
    local health_ratio = self.Strength / self.MaxStrength
    return math.floor(self.PowerOutput * health_ratio)
end

--[[
    Get power drain.
]]
function BuildingClass:Power_Drain()
    if not self:Is_Operational() then
        return 0
    end
    return self.PowerDrain
end

--[[
    Check if building has enough power to operate.

    Reference: BuildingClass::Has_Power from BUILDING.CPP

    Returns true if the building has sufficient power to function.
    Buildings that don't require power (like walls) always return true.
    Production and defensive buildings require adequate power.

    @return true if building can operate normally
]]
function BuildingClass:Has_Power()
    if not self.House then
        return true
    end

    -- Check if this building type requires power
    local type_class = self.Class
    if type_class then
        -- Power plants themselves always "have power" for basic operation
        if type_class.IsPowerPlant then
            return true
        end

        -- Buildings with no power drain don't need power
        if (type_class.PowerDrain or 0) <= 0 then
            return true
        end
    end

    -- Check house power ratio
    local power_ratio = self.House:get_power_ratio()

    -- Full power if ratio >= 1.0
    if power_ratio >= 1.0 then
        return true
    end

    -- Low power affects operation
    return false
end

--[[
    Get power efficiency multiplier for this building.

    Reference: Based on original C&C power mechanics

    Returns a value 0.0-1.0 indicating operational efficiency.
    At full power: 1.0 (100% efficiency)
    At low power: reduced based on power ratio
    At no power: 0.0 (building offline)

    @return efficiency multiplier (0.0 to 1.0)
]]
function BuildingClass:Power_Efficiency()
    if not self.House then
        return 1.0
    end

    -- Check if building requires power at all
    local type_class = self.Class
    if type_class then
        if type_class.IsPowerPlant then
            return 1.0
        end
        if (type_class.PowerDrain or 0) <= 0 then
            return 1.0
        end
    end

    local power_ratio = self.House:get_power_ratio()

    -- Full efficiency at or above 100% power
    if power_ratio >= 1.0 then
        return 1.0
    end

    -- Efficiency scales with power ratio (minimum 25% if any power)
    if power_ratio > 0 then
        return 0.25 + (power_ratio * 0.75)
    end

    -- No power means offline
    return 0.0
end

--[[
    Check if building can produce/fire due to power status.

    Reference: Original C&C required adequate power for production

    @return true if building can perform active operations
]]
function BuildingClass:Can_Operate()
    -- Must be operational (not destroyed, not in limbo)
    if not self:Is_Operational() then
        return false
    end

    -- Check power status
    return self:Has_Power()
end

--============================================================================
-- Tiberium Storage
--============================================================================

--[[
    Get stored Tiberium amount.
]]
function BuildingClass:Tiberium_Stored()
    return self.TiberiumStored
end

--[[
    Get storage capacity.
]]
function BuildingClass:Storage_Capacity()
    return self.TiberiumCapacity
end

--[[
    Check if storage is full.
]]
function BuildingClass:Is_Storage_Full()
    return self.TiberiumCapacity > 0 and
           self.TiberiumStored >= self.TiberiumCapacity
end

--[[
    Add Tiberium to storage.

    @param amount - Amount to add
    @return Amount actually stored
]]
function BuildingClass:Store_Tiberium(amount)
    if self.TiberiumCapacity <= 0 then
        return 0
    end

    local space = self.TiberiumCapacity - self.TiberiumStored
    local stored = math.min(amount, space)

    self.TiberiumStored = self.TiberiumStored + stored

    -- Update state based on fill level
    if self.TiberiumStored >= self.TiberiumCapacity then
        self:Set_State(BuildingClass.BSTATE.FULL)
    elseif self.TiberiumStored > 0 then
        self:Set_State(BuildingClass.BSTATE.ACTIVE)
    end

    return stored
end

--[[
    Remove Tiberium from storage.

    @param amount - Amount to remove
    @return Amount actually removed
]]
function BuildingClass:Remove_Tiberium(amount)
    local removed = math.min(amount, self.TiberiumStored)
    self.TiberiumStored = self.TiberiumStored - removed

    -- Update state
    if self.TiberiumStored <= 0 then
        self:Set_State(BuildingClass.BSTATE.IDLE)
    end

    return removed
end

--============================================================================
-- Production (Factory)
--============================================================================

--[[
    Check if this building can produce units.
]]
function BuildingClass:Can_Produce()
    if not self:Is_Operational() then
        return false
    end

    -- Check if has production capability
    if self.Class then
        return self.Class.IsFactory
    end

    return false
end

--[[
    Get the factory object.
]]
function BuildingClass:Get_Factory()
    return self.Factory
end

--[[
    Set the factory object.

    @param factory - FactoryClass instance
]]
function BuildingClass:Set_Factory(factory)
    self.Factory = factory
end

--[[
    Start production of an item.

    @param type - Type to produce
    @return true if production started
]]
function BuildingClass:Start_Production(type)
    if not self:Can_Produce() then
        return false
    end

    -- Would create/use factory object
    -- self.Factory = FactoryClass:new(type, self.House)

    self:Set_State(BuildingClass.BSTATE.ACTIVE)

    return true
end

--============================================================================
-- Repair System
--============================================================================

--[[
    Check if building can be repaired.
]]
function BuildingClass:Can_Repair()
    return self.Strength < self.MaxStrength and
           not self:Is_Under_Construction() and
           not self.IsSelling
end

--[[
    Start repairing this building.
]]
function BuildingClass:Start_Repair()
    if self:Can_Repair() then
        self.IsRepairing = true
        self.RepairTimer = 15  -- 1 second delay between repairs
    end
end

--[[
    Stop repairing this building.
]]
function BuildingClass:Stop_Repair()
    self.IsRepairing = false
end

--[[
    Process one repair tick.
]]
function BuildingClass:Process_Repair()
    if not self.IsRepairing then
        return
    end

    -- Check if repair complete
    if self.Strength >= self.MaxStrength then
        self:Stop_Repair()
        return
    end

    -- Decrement timer
    self.RepairTimer = self.RepairTimer - 1
    if self.RepairTimer > 0 then
        return
    end

    -- Reset timer
    self.RepairTimer = 15

    -- Check if house can afford repair
    if self.House then
        -- Would check credits
        -- if self.House.Credits < BuildingClass.REPAIR_COST then
        --     return
        -- end
        -- self.House.Credits = self.House.Credits - BuildingClass.REPAIR_COST
    end

    -- Apply repair
    self.Strength = math.min(self.Strength + BuildingClass.REPAIR_RATE,
                             self.MaxStrength)
end

--============================================================================
-- Sell System
--============================================================================

--[[
    Check if building can be sold.
]]
function BuildingClass:Can_Sell()
    return self:Is_Operational() and not self.IsSelling
end

--[[
    Start selling this building.
]]
function BuildingClass:Sell()
    if not self:Can_Sell() then
        return false
    end

    self.IsSelling = true
    self.SellTimer = 30  -- 2 seconds to sell

    -- Would play sell animation
    self:Set_State(BuildingClass.BSTATE.AUX1)

    return true
end

--[[
    Complete the sell process.
]]
function BuildingClass:Complete_Sell()
    -- Refund credits
    if self.House then
        local refund = self:Refund_Amount()
        -- self.House:Refund_Money(refund)
    end

    -- Possibly spawn infantry (crew survivors)
    -- (Would check if building has crew)

    -- Remove building
    self:Limbo()
end

--============================================================================
-- Capture System
--============================================================================

--[[
    Check if building can be captured.
]]
function BuildingClass:Can_Capture()
    if not self.Class then
        return false
    end

    return self.Class.IsCaptureable
end

--[[
    Capture this building for a new owner.

    @param newowner - HouseClass of new owner
    @return true if captured successfully
]]
function BuildingClass:Capture(newowner)
    if not self:Can_Capture() then
        return false
    end

    if newowner == self.House then
        return false
    end

    -- Change ownership
    local oldowner = self.House
    self.House = newowner
    self.IsCaptured = true

    -- Update player ownership flag
    if newowner then
        self.IsOwnedByPlayer = newowner:Is_Player_Control()
    end

    -- Captured buildings go to half health
    self.Strength = math.floor(self.MaxStrength / 2)

    return true
end

--============================================================================
-- Sabotage System
--============================================================================

--[[
    Plant C4 on this building.

    @param timer - Ticks until explosion
]]
function BuildingClass:Plant_C4(timer)
    timer = timer or 150  -- Default 10 seconds

    self.SabotageTimer = timer

    -- Play alarm sound
    -- Would trigger C4 planted voice/sound
end

--[[
    Process sabotage countdown.
]]
function BuildingClass:Process_Sabotage()
    if self.SabotageTimer <= 0 then
        return
    end

    self.SabotageTimer = self.SabotageTimer - 1

    if self.SabotageTimer <= 0 then
        -- BOOM!
        self:Take_Damage(10000, 0, 0, nil)  -- Instant destruction
    end
end

--============================================================================
-- Combat
--============================================================================

--[[
    Take damage.
]]
function BuildingClass:Take_Damage(damage, distance, warhead, source)
    self.LastStrength = self.Strength

    local result = TechnoClass.Take_Damage(self, damage, distance, warhead, source)

    -- Check for destruction
    if self.Strength <= 0 then
        self:Death_Announcement(source)
    end

    -- Update visual state based on damage
    -- (Would update building animation frame)

    return result
end

--[[
    Death announcement when destroyed.
]]
function BuildingClass:Death_Announcement(source)
    -- Spawn explosion
    -- Kill any cargo/contents

    -- Special handling for Construction Yard
    if self.Class and self.Class.IniName == "FACT" then
        -- House loses ability to build
        -- self.House:Flag_No_Build()
    end
end

--[[
    Get weapon range for defense buildings.
]]
function BuildingClass:Weapon_Range(which)
    if self.Class and self.Class.PrimaryWeapon then
        return self.Class.PrimaryWeapon.Range or 0
    end
    return 0
end

--============================================================================
-- Mission Implementations
--============================================================================

--[[
    Mission_Guard - Defense buildings look for targets.
]]
function BuildingClass:Mission_Guard()
    -- Only defense buildings actively guard
    if not self.Class or not self.Class.IsDefense then
        return 15
    end

    -- Look for threats
    local threat = self:Greatest_Threat(0)
    if Target.Is_Valid(threat) then
        self:Assign_Target(threat)
        self:Assign_Mission(self.MISSION.ATTACK)
        return 1
    end

    return 15
end

--[[
    Mission_Attack - Fire at target.
]]
function BuildingClass:Mission_Attack()
    if not Target.Is_Valid(self.TarCom) then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Check range
    if not self:In_Range(self.TarCom, 0) then
        -- Target out of range
        self:Assign_Target(Target.TARGET_NONE)
        self:Enter_Idle_Mode()
        return 15
    end

    -- Rotate turret if applicable
    if self.Class and self.Class.IsTurretEquipped then
        -- Would rotate turret to face target
    end

    -- Fire
    self:Fire_At(self.TarCom, 0)

    return self:Rearm_Delay(false)
end

--============================================================================
-- Idle Mode
--============================================================================

--[[
    Enter idle mode.
]]
function BuildingClass:Enter_Idle_Mode(initial)
    self:Set_State(BuildingClass.BSTATE.IDLE)
    self:Assign_Mission(self.MISSION.GUARD)
end

--============================================================================
-- Map Operations
--============================================================================

--[[
    Place building on the map.
]]
function BuildingClass:Unlimbo(coord, facing)
    if not TechnoClass.Unlimbo(self, coord, facing) then
        return false
    end

    -- Mark cells as occupied
    -- (Would use Occupy_List from type)

    -- Register with house
    if self.House then
        -- self.House:Add_Building(self)
    end

    return true
end

--[[
    Remove building from map.
]]
function BuildingClass:Limbo()
    -- Unmark occupied cells

    -- Unregister from house
    if self.House then
        -- self.House:Remove_Building(self)
    end

    return TechnoClass.Limbo(self)
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for buildings.
]]
function BuildingClass:AI()
    -- Call parent AI
    TechnoClass.AI(self)

    -- Process repair
    self:Process_Repair()

    -- Process sell
    if self.IsSelling then
        self.SellTimer = self.SellTimer - 1
        if self.SellTimer <= 0 then
            self:Complete_Sell()
            return  -- Building is gone
        end
    end

    -- Process sabotage
    self:Process_Sabotage()

    -- Animation timer
    if self.AnimTimer > 0 then
        self.AnimTimer = self.AnimTimer - 1
    else
        -- Update animation frame
        self.StateFrame = self.StateFrame + 1
        self.AnimTimer = 4  -- Animation speed
    end

    -- Process factory
    if self.Factory then
        -- self.Factory:AI()
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function BuildingClass:Code_Pointers()
    local data = TechnoClass.Code_Pointers(self)

    -- Building specific
    data.BState = self.BState
    data.StateFrame = self.StateFrame
    data.PowerOutput = self.PowerOutput
    data.PowerDrain = self.PowerDrain
    data.IsRepairing = self.IsRepairing
    data.RepairTimer = self.RepairTimer
    data.TiberiumStored = self.TiberiumStored
    data.TiberiumCapacity = self.TiberiumCapacity
    data.IsCaptured = self.IsCaptured
    data.IsSelling = self.IsSelling
    data.SellTimer = self.SellTimer
    data.BuildProgress = self.BuildProgress
    data.TurretFacing = self.TurretFacing
    data.AnimTimer = self.AnimTimer
    data.SabotageTimer = self.SabotageTimer

    -- Type (store as name for lookup)
    if self.Class then
        data.TypeName = self.Class.IniName
    end

    return data
end

function BuildingClass:Decode_Pointers(data, heap_lookup)
    TechnoClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.BState = data.BState or BuildingClass.BSTATE.IDLE
        self.StateFrame = data.StateFrame or 0
        self.PowerOutput = data.PowerOutput or 0
        self.PowerDrain = data.PowerDrain or 0
        self.IsRepairing = data.IsRepairing or false
        self.RepairTimer = data.RepairTimer or 0
        self.TiberiumStored = data.TiberiumStored or 0
        self.TiberiumCapacity = data.TiberiumCapacity or 0
        self.IsCaptured = data.IsCaptured or false
        self.IsSelling = data.IsSelling or false
        self.SellTimer = data.SellTimer or 0
        self.BuildProgress = data.BuildProgress or 100
        self.TurretFacing = data.TurretFacing or 0
        self.AnimTimer = data.AnimTimer or 0
        self.SabotageTimer = data.SabotageTimer or 0

        -- Type lookup would happen later
        self._decode_type_name = data.TypeName
    end
end

--============================================================================
-- Placement Validation
--============================================================================

-- Adjacent cell offsets (8 directions)
local ADJACENT_OFFSETS = {
    {dx = 0, dy = -1},   -- N
    {dx = 1, dy = -1},   -- NE
    {dx = 1, dy = 0},    -- E
    {dx = 1, dy = 1},    -- SE
    {dx = 0, dy = 1},    -- S
    {dx = -1, dy = 1},   -- SW
    {dx = -1, dy = 0},   -- W
    {dx = -1, dy = -1},  -- NW
}

--[[
    Check if a cell is adjacent to any owned building.

    @param cell_x - Cell X coordinate
    @param cell_y - Cell Y coordinate
    @param house - HouseClass to check buildings for
    @return true if adjacent to owned building
]]
function BuildingClass.Is_Adjacent_To_Building(cell_x, cell_y, house)
    if not house or not house.buildings then
        return false
    end

    for _, building in ipairs(house.buildings) do
        -- Get building cells
        local bld_coord = building.Coord
        if bld_coord then
            local bld_cell_x = Coord.Cell_X(Coord.Coord_Cell(bld_coord))
            local bld_cell_y = Coord.Cell_Y(Coord.Coord_Cell(bld_coord))

            -- Get building size (default 1x1)
            local width = 1
            local height = 1
            if building.Class then
                width = building.Class.Width or 1
                height = building.Class.Height or 1
            end

            -- Check if placement cell is adjacent to any building cell
            for by = 0, height - 1 do
                for bx = 0, width - 1 do
                    local check_x = bld_cell_x + bx
                    local check_y = bld_cell_y + by

                    -- Check all 8 adjacent positions
                    for _, offset in ipairs(ADJACENT_OFFSETS) do
                        if cell_x == check_x + offset.dx and
                           cell_y == check_y + offset.dy then
                            return true
                        end
                    end

                    -- Also allow placement ON the building edge (for adjacency)
                    if cell_x == check_x and cell_y == check_y then
                        return false  -- Can't place ON building
                    end
                end
            end
        end
    end

    return false
end

--[[
    Check if placement at a cell is legal for a building.

    @param cell_x - Cell X coordinate
    @param cell_y - Cell Y coordinate
    @param building_type - BuildingTypeClass
    @param house - HouseClass placing the building
    @param map - Map object for cell checks
    @return true if placement is legal, false with reason otherwise
]]
function BuildingClass.Can_Place_Building(cell_x, cell_y, building_type, house, map)
    if not building_type then
        return false, "No building type"
    end

    -- Get building size
    local width = building_type.Width or 1
    local height = building_type.Height or 1

    -- Check adjacency requirement
    local needs_adjacency = not building_type.IsBridgeHead  -- Most buildings need adjacency
    local is_adjacent = false

    -- Check each cell the building will occupy
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            local check_x = cell_x + dx
            local check_y = cell_y + dy

            -- Check map bounds
            if map then
                local map_width = map.width or 64
                local map_height = map.height or 64
                if check_x < 0 or check_x >= map_width or
                   check_y < 0 or check_y >= map_height then
                    return false, "Out of bounds"
                end

                -- Check cell passability
                local cell = map:get_cell(check_x, check_y)
                if cell then
                    -- Can't build on water, cliffs, or occupied cells
                    if cell.terrain == "water" or cell.terrain == "cliff" then
                        return false, "Invalid terrain"
                    end
                    if cell.building then
                        return false, "Cell occupied"
                    end
                end
            end

            -- Check adjacency for each cell
            if needs_adjacency and not is_adjacent then
                is_adjacent = BuildingClass.Is_Adjacent_To_Building(check_x, check_y, house)
            end
        end
    end

    -- Check adjacency requirement (except for first building/Construction Yard)
    if needs_adjacency then
        -- Allow if house has no buildings (first building)
        if house and #house.buildings > 0 and not is_adjacent then
            return false, "Must be adjacent to existing building"
        end
    end

    return true, nil
end

--[[
    Get list of valid placement cells around owned buildings.

    @param house - HouseClass
    @param building_type - BuildingTypeClass to place
    @param map - Map object
    @return Table of {x, y} valid cells
]]
function BuildingClass.Get_Valid_Placement_Cells(house, building_type, map)
    local valid_cells = {}
    local checked = {}

    if not house or not house.buildings then
        return valid_cells
    end

    local width = building_type and building_type.Width or 1
    local height = building_type and building_type.Height or 1

    -- For each owned building
    for _, building in ipairs(house.buildings) do
        local bld_coord = building.Coord
        if bld_coord then
            local bld_cell_x = Coord.Cell_X(Coord.Coord_Cell(bld_coord))
            local bld_cell_y = Coord.Cell_Y(Coord.Coord_Cell(bld_coord))

            local bld_width = 1
            local bld_height = 1
            if building.Class then
                bld_width = building.Class.Width or 1
                bld_height = building.Class.Height or 1
            end

            -- Check all adjacent cells
            for by = -1, bld_height do
                for bx = -1, bld_width do
                    -- Skip interior cells
                    if bx < 0 or bx >= bld_width or by < 0 or by >= bld_height then
                        local check_x = bld_cell_x + bx
                        local check_y = bld_cell_y + by
                        local key = check_x .. "," .. check_y

                        if not checked[key] then
                            checked[key] = true

                            local can_place, _ = BuildingClass.Can_Place_Building(
                                check_x, check_y, building_type, house, map)

                            if can_place then
                                table.insert(valid_cells, {x = check_x, y = check_y})
                            end
                        end
                    end
                end
            end
        end
    end

    return valid_cells
end

--============================================================================
-- Debug Support
--============================================================================

local BSTATE_NAMES = {
    [-1] = "NONE",
    [0] = "CONSTRUCTION",
    [1] = "IDLE",
    [2] = "ACTIVE",
    [3] = "FULL",
    [4] = "AUX1",
    [5] = "AUX2",
}

function BuildingClass:Debug_Dump()
    TechnoClass.Debug_Dump(self)

    print(string.format("BuildingClass: State=%s Frame=%d Progress=%d%%",
        BSTATE_NAMES[self.BState] or "?",
        self.StateFrame,
        self.BuildProgress))

    print(string.format("  Power: Output=%d Drain=%d",
        self.PowerOutput,
        self.PowerDrain))

    print(string.format("  Storage: %d/%d",
        self.TiberiumStored,
        self.TiberiumCapacity))

    print(string.format("  Flags: Repairing=%s Selling=%s Captured=%s",
        tostring(self.IsRepairing),
        tostring(self.IsSelling),
        tostring(self.IsCaptured)))

    if self.SabotageTimer > 0 then
        print(string.format("  SABOTAGE: %d ticks remaining!", self.SabotageTimer))
    end
end

--============================================================================
-- Radio Communication
--============================================================================

--[[
    Handle incoming radio messages.

    Reference: BuildingClass::Receive_Message from BUILDING.CPP

    Buildings respond to various radio messages from units, especially
    refineries responding to harvesters requesting docking.

    @param from - The object sending the message
    @param message - The radio message type
    @param param - Optional parameter
    @return Response message
]]
function BuildingClass:Receive_Message(from, message, param)
    -- Let parent handle basic messages first
    local response = TechnoClass.Receive_Message(self, from, message, param)

    -- If parent didn't handle it (returned STATIC), try building-specific handling
    if response ~= self.RADIO.STATIC then
        return response
    end

    local type_class = self.Class

    -- Refinery-specific handling
    if type_class and type_class.IsRefinery then
        -- HELLO from harvester - request to dock
        if message == self.RADIO.HELLO then
            -- Check if we're already busy with another harvester
            if self:In_Radio_Contact() and self.Radio ~= from then
                return self.RADIO.NEGATIVE
            end

            -- Check if refinery is operational
            if not self:Is_Operational() then
                return self.RADIO.NEGATIVE
            end

            -- Accept the harvester
            self.Radio = from
            return self.RADIO.ROGER
        end

        -- DOCKING - harvester is arriving to dock
        if message == self.RADIO.DOCKING then
            if self.Radio == from then
                -- Set building state to FULL (harvester docking)
                self:Begin_Mode(BuildingClass.BSTATE.FULL)
                return self.RADIO.ROGER
            end
            return self.RADIO.NEGATIVE
        end

        -- IM_IN - harvester has entered/docked
        if message == self.RADIO.IM_IN then
            if self.Radio == from then
                -- Harvester is now inside, ready to unload
                return self.RADIO.ROGER
            end
            return self.RADIO.NEGATIVE
        end

        -- OVER_OUT - harvester is leaving
        if message == self.RADIO.OVER_OUT then
            if self.Radio == from then
                self.Radio = nil
                -- Return to idle state
                self:Begin_Mode(BuildingClass.BSTATE.IDLE)
            end
            return self.RADIO.ROGER
        end
    end

    -- Repair facility specific handling
    if type_class and type_class.IsRepairFacility then
        if message == self.RADIO.HELLO then
            if self:In_Radio_Contact() and self.Radio ~= from then
                return self.RADIO.NEGATIVE
            end
            if not self:Is_Operational() then
                return self.RADIO.NEGATIVE
            end
            self.Radio = from
            return self.RADIO.ROGER
        end
    end

    -- Helipad specific handling
    if type_class and type_class.IsHelipad then
        if message == self.RADIO.HELLO then
            if self:In_Radio_Contact() and self.Radio ~= from then
                return self.RADIO.NEGATIVE
            end
            if not self:Is_Operational() then
                return self.RADIO.NEGATIVE
            end
            self.Radio = from
            return self.RADIO.ROGER
        end
    end

    return self.RADIO.STATIC
end

return BuildingClass
