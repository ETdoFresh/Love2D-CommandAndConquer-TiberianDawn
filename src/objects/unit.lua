--[[
    UnitClass - Ground vehicle unit implementation

    Port of UNIT.H/CPP from the original C&C source.

    Units are ground vehicles that include:
    - Tanks (Medium Tank, Light Tank, Mammoth Tank)
    - APCs and transports
    - Harvesters
    - MCVs (Mobile Construction Vehicle)
    - Artillery and rocket launchers
    - Specialized vehicles (Stealth Tank, Flame Tank, etc.)

    Key systems:
    - Track-based movement (inherited from DriveClass)
    - Turret rotation (inherited from TurretClass)
    - Targeting computer (inherited from TarComClass)
    - Harvester logic (loading/unloading Tiberium)
    - MCV deployment

    Reference: temp/CnC_Remastered_Collection/TIBERIANDAWN/UNIT.H/CPP
]]

local Class = require("src.objects.class")
local TarComClass = require("src.objects.drive.tarcom")
local Target = require("src.core.target")
local Coord = require("src.core.coord")

-- Create UnitClass extending TarComClass
local UnitClass = Class.extend(TarComClass, "UnitClass")

--============================================================================
-- Constants
--============================================================================

-- Unit types (for identification)
UnitClass.UNIT = {
    NONE = -1,
    HTANK = 0,      -- Mammoth Tank
    MTANK = 1,      -- Medium Tank
    LTANK = 2,      -- Light Tank
    STANK = 3,      -- Stealth Tank
    FTANK = 4,      -- Flame Tank
    MCV = 5,        -- Mobile Construction Vehicle
    HARVESTER = 6,  -- Tiberium Harvester
    APC = 7,        -- Armored Personnel Carrier
    MLRS = 8,       -- Multiple Launch Rocket System
    ARTY = 9,       -- Artillery
    JEEP = 10,      -- Humvee/Nod Buggy
    BIKE = 11,      -- Recon Bike
    SSM = 12,       -- SSM Launcher
    MSAM = 13,      -- Mobile SAM
    HOVERCRAFT = 14,-- Hovercraft transport
    GUNBOAT = 15,   -- Gunboat
}

-- Harvester constants
UnitClass.TIBERIUM_CAPACITY = 28    -- Bails of tiberium a harvester can hold
UnitClass.HARVEST_DELAY = 5         -- Ticks between harvest operations
UnitClass.UNLOAD_DELAY = 8          -- Ticks between unload operations

-- MCV deployment constants
UnitClass.DEPLOY_TIME = 30          -- Ticks to deploy MCV

--============================================================================
-- Constructor
--============================================================================

--[[
    Create a new UnitClass.

    @param type - UnitTypeClass defining this unit
    @param house - HouseClass owner
]]
function UnitClass:init(type, house)
    -- Call parent constructor
    TarComClass.init(self, house)

    -- Store type reference
    self.Class = type

    --[[
        Tiberium load carried by harvesters.
        Each "bail" is worth credits when returned to refinery.
    ]]
    self.Tiberium = 0

    --[[
        Timer for harvesting operations.
    ]]
    self.HarvestTimer = 0

    --[[
        Timer for unloading at refinery.
    ]]
    self.UnloadTimer = 0

    --[[
        Flagged for CTF mode (capture the flag).
    ]]
    self.Flagged = false

    --[[
        Is this unit deploying? (MCV becoming construction yard)
    ]]
    self.IsDeploying = false

    --[[
        Deploy countdown timer.
    ]]
    self.DeployTimer = 0

    --[[
        Animation timer for unit graphics.
    ]]
    self.AnimTimer = 0

    --[[
        Is this a unit that can rotate/has rotations?
    ]]
    self.IsRotating = false

    --[[
        Jitter count for stuck detection.
    ]]
    self.JitterCount = 0

    -- Set initial type-based properties
    if type then
        self.Ammo = type.MaxAmmo or -1

        -- Set turret equipped flag from type
        if type.IsTurretEquipped then
            self.IsTurretEquipped = true
        end

        -- Set transport capacity
        if type.IsTransporter then
            self.IsTransporter = true
        end
    end
end

--============================================================================
-- Type Access
--============================================================================

--[[
    Get the UnitTypeClass for this unit.
]]
function UnitClass:Techno_Type_Class()
    return self.Class
end

--[[
    Get the unit type class (alias).
]]
function UnitClass:Class_Of()
    return self.Class
end

--============================================================================
-- Harvester System
--============================================================================

--[[
    Check if this is a harvester.
]]
function UnitClass:Is_Harvester()
    return self.Class and self.Class.IsHarvester
end

--[[
    Get current tiberium load.
]]
function UnitClass:Tiberium_Load()
    return self.Tiberium
end

--[[
    Check if harvester is full.
]]
function UnitClass:Is_Full()
    return self.Tiberium >= UnitClass.TIBERIUM_CAPACITY
end

--[[
    Check if harvester is empty.
]]
function UnitClass:Is_Empty()
    return self.Tiberium <= 0
end

--[[
    Harvest tiberium from current cell.

    @return true if successfully harvested
]]
function UnitClass:Harvest()
    if not self:Is_Harvester() then
        return false
    end

    if self:Is_Full() then
        return false
    end

    -- Check harvest timer
    if self.HarvestTimer > 0 then
        return false
    end

    -- Reset timer
    self.HarvestTimer = UnitClass.HARVEST_DELAY

    -- Get current cell (would check for tiberium)
    -- local cell = Coord.Coord_Cell(self:Center_Coord())
    -- local has_tiberium = Map.Cell_Has_Tiberium(cell)

    -- Simplified: assume we can harvest
    self.Tiberium = self.Tiberium + 1

    -- Mark as harvesting
    self.IsHarvesting = true

    return true
end

--[[
    Unload one bail of tiberium at refinery.

    @return Credits value of the bail, or 0 if empty
]]
function UnitClass:Offload_Tiberium_Bail()
    if self.Tiberium <= 0 then
        return 0
    end

    -- Check unload timer
    if self.UnloadTimer > 0 then
        return 0
    end

    -- Reset timer
    self.UnloadTimer = UnitClass.UNLOAD_DELAY

    -- Remove one bail
    self.Tiberium = self.Tiberium - 1

    -- Return credits value (typically 25-100 per bail)
    return 25
end

--[[
    Find and head to nearest refinery.

    Reference: UnitClass::Find_Best_Refinery from UNIT.CPP

    Searches for the nearest available refinery owned by this unit's house.
    Establishes radio contact with the refinery and assigns ENTER mission.

    @return true if refinery found and destination assigned
]]
function UnitClass:Find_Refinery()
    if not self.House then
        return false
    end

    -- Get the global game reference to search for buildings
    local Game = require("src.core.game")
    if not Game or not Game.buildings then
        return false
    end

    local my_coord = self:Center_Coord()
    local my_x, my_y = Coord.From_Lepton(my_coord)

    local best_refinery = nil
    local best_distance = math.huge

    -- Search all buildings for refineries owned by our house
    for _, building in pairs(Game.buildings) do
        if building and building.IsActive and building.House == self.House then
            local type_class = building.Class
            if type_class and type_class.IsRefinery then
                -- Calculate distance
                local bx, by = Coord.From_Lepton(building:Center_Coord())
                local dx = bx - my_x
                local dy = by - my_y
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < best_distance then
                    best_distance = dist
                    best_refinery = building
                end
            end
        end
    end

    if best_refinery then
        -- Establish radio contact with refinery
        local response = self:Transmit_Message(self.RADIO.HELLO, best_refinery)
        if response == self.RADIO.ROGER then
            -- Refinery acknowledged, head there
            self.ArchiveTarget = Target.As_Target(best_refinery)
            self:Assign_Destination(self.ArchiveTarget)
            self:Assign_Mission(self.MISSION.ENTER)
            return true
        else
            -- Refinery busy, just move toward it
            local near_coord = best_refinery:Center_Coord()
            self:Assign_Destination(Target.As_Target_Coord(near_coord))
            return true
        end
    end

    return false
end

--[[
    Find and harvest from nearest tiberium.

    Reference: UnitClass::Goto_Tiberium from UNIT.CPP

    Searches for the nearest tiberium cell within scanning range.
    Uses spiral search pattern outward from current position.

    @return true if tiberium found and destination assigned
]]
function UnitClass:Find_Tiberium()
    local Game = require("src.core.game")
    if not Game or not Game.grid then
        return false
    end

    local grid = Game.grid
    local my_coord = self:Center_Coord()
    local cell_x = Coord.Cell_X(Coord.Coord_Cell(my_coord))
    local cell_y = Coord.Cell_Y(Coord.Coord_Cell(my_coord))

    -- Search radius (in cells) - start small and expand
    local max_radius = 32  -- Maximum search distance

    -- Spiral search outward from current position
    for radius = 1, max_radius do
        -- Check cells at this radius
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Only check cells on the perimeter of this radius
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local cx = cell_x + dx
                    local cy = cell_y + dy

                    local cell = grid:get_cell(cx, cy)
                    if cell and cell:has_tiberium() then
                        -- Found tiberium! Calculate destination coordinate
                        local dest_coord = Coord.XY_Coord(
                            cx * 256 + 128,  -- Cell center in leptons
                            cy * 256 + 128
                        )

                        -- Remember where we found tiberium for future reference
                        self.ArchiveTarget = Target.As_Target_Coord(dest_coord)

                        -- Assign destination and stay in harvest mission
                        self:Assign_Destination(self.ArchiveTarget)
                        return true
                    end
                end
            end
        end
    end

    -- No tiberium found - check archive target (last known location)
    if Target.Is_Valid(self.ArchiveTarget) then
        self:Assign_Destination(self.ArchiveTarget)
        return true
    end

    return false
end

--[[
    Check if harvester is currently on a tiberium cell.

    @return true if current cell has tiberium
]]
function UnitClass:On_Tiberium()
    local Game = require("src.core.game")
    if not Game or not Game.grid then
        return false
    end

    local my_coord = self:Center_Coord()
    local cell_x = Coord.Cell_X(Coord.Coord_Cell(my_coord))
    local cell_y = Coord.Cell_Y(Coord.Coord_Cell(my_coord))
    local cell = Game.grid:get_cell(cell_x, cell_y)

    return cell and cell:has_tiberium()
end

--[[
    Perform actual harvest operation from current cell.

    Called from Mission_Harvest when on tiberium. Extracts tiberium
    from the cell and adds it to the harvester's cargo.

    @return true if successfully harvested
]]
function UnitClass:Harvesting()
    if not self:Is_Harvester() then
        return false
    end

    if self:Is_Full() then
        return false
    end

    -- Must be on tiberium
    if not self:On_Tiberium() then
        return false
    end

    local Game = require("src.core.game")
    if not Game or not Game.grid then
        return false
    end

    local my_coord = self:Center_Coord()
    local cell_x = Coord.Cell_X(Coord.Coord_Cell(my_coord))
    local cell_y = Coord.Cell_Y(Coord.Coord_Cell(my_coord))
    local cell = Game.grid:get_cell(cell_x, cell_y)

    if cell then
        -- Extract one unit of tiberium from cell
        local harvested = cell:harvest_tiberium(1)
        if harvested > 0 then
            -- Add to cargo
            self.Tiberium = self.Tiberium + 1
            return true
        end
    end

    return false
end

--============================================================================
-- MCV Deployment
--============================================================================

--[[
    Check if this is an MCV that can deploy.
]]
function UnitClass:Can_Deploy()
    if not self.Class then
        return false
    end

    -- Check if this is an MCV type
    if not self.Class.IsDeployable then
        return false
    end

    -- Check if already deploying
    if self.IsDeploying then
        return false
    end

    -- Check if cell is suitable (would check terrain, obstacles)
    -- local cell = Coord.Coord_Cell(self:Center_Coord())
    -- if not Map.Can_Build_Here(cell) then return false end

    return true
end

--[[
    Start deployment process (MCV to Construction Yard).

    @return true if deployment started
]]
function UnitClass:Deploy()
    if not self:Can_Deploy() then
        return false
    end

    self.IsDeploying = true
    self.DeployTimer = UnitClass.DEPLOY_TIME

    -- Stop movement
    self:Stop_Driver()
    self.NavCom = Target.TARGET_NONE

    -- Start deploy animation
    -- Would set animation state

    return true
end

--[[
    Complete deployment (called when timer expires).

    Reference: UnitClass::Try_To_Deploy from UNIT.CPP

    When the MCV finishes its deployment animation, this creates the
    Construction Yard building at the MCV's location and removes the MCV.

    @return true if deployment succeeded
]]
function UnitClass:Complete_Deploy()
    if not self.IsDeploying then
        return false
    end

    self.IsDeploying = false

    -- Get current coordinates
    local coord = self:Center_Coord()
    local cell = Coord.Coord_Cell(coord)
    local cell_x = Coord.Cell_X(cell)
    local cell_y = Coord.Cell_Y(cell)

    -- Create construction yard at this location
    local Game = require("src.core.game")
    local BuildingClass = require("src.objects.building")
    local BuildingTypeClass = require("src.objects.types.buildingtype")

    -- Get Construction Yard type (STRUCT_FACT = 9 typically)
    local fact_type = BuildingTypeClass.As_Reference(BuildingTypeClass.STRUCT.FACT)
    if not fact_type then
        -- Fallback: try to create by name
        fact_type = BuildingTypeClass.Create("FACT")
    end

    if fact_type then
        -- Create the building
        local building = BuildingClass:new(fact_type, self.House)
        if building then
            -- Place it at this location
            if building:Unlimbo(coord, 0) then
                -- Add to game tracking
                if Game and Game.buildings then
                    Game.buildings[building] = building
                end

                -- Transfer ownership attributes
                if self.House then
                    self.House:add_building(building)
                end

                -- Remove the MCV
                self:Limbo()

                -- If game has units tracking, remove from it
                if Game and Game.units then
                    Game.units[self] = nil
                end

                return true
            else
                -- Failed to place building, delete it
                building:Limbo()
            end
        end
    end

    -- Deployment failed - abort
    self.IsDeploying = false
    return false
end

--============================================================================
-- Transport System
--============================================================================

--[[
    Check if this unit can transport.
]]
function UnitClass:Can_Transport()
    return self.Class and self.Class.IsTransporter
end

--[[
    Get the maximum passenger count.
]]
function UnitClass:Max_Passengers()
    if self.Class and self.Class.Max_Passengers then
        return self.Class:Max_Passengers()
    end
    return 0
end

--============================================================================
-- Movement
--============================================================================

--[[
    Override movement speed for special cases.
]]
function UnitClass:Get_Speed_Factor()
    -- Harvester moves slower when full
    if self:Is_Harvester() and self.Tiberium > 0 then
        return 0.8  -- 80% speed when carrying
    end

    return 1.0
end

--[[
    Handle entering a cell.
]]
function UnitClass:Per_Cell_Process(center)
    TarComClass.Per_Cell_Process(self, center)

    if center then
        -- Harvester auto-harvest
        if self:Is_Harvester() and not self:Is_Full() then
            self:Harvest()
        end

        -- Clear jitter count
        self.JitterCount = 0
    end
end

--============================================================================
-- Combat
--============================================================================

--[[
    Select death animation based on damage type.

    @param warhead - WarheadType that destroyed us
]]
function UnitClass:Death_Announcement(source)
    -- Play explosion animation
    -- Would spawn appropriate death animation/explosion

    -- For transports, kill cargo
    if self:Can_Transport() then
        self:Kill_Cargo(source)
    end

    -- Harvesters spill tiberium
    if self:Is_Harvester() and self.Tiberium > 0 then
        -- Would spawn tiberium at location
        self.Tiberium = 0
    end
end

--============================================================================
-- Mission Implementations
--============================================================================

--[[
    Mission_Harvest - Harvester AI state machine.

    Reference: UnitClass::Mission_Harvest from UNIT.CPP

    Implements the full harvester behavior loop:
    - LOOKING: Find tiberium field
    - HARVESTING: Collect tiberium from current cell
    - FINDHOME: Locate nearest refinery
    - HEADINGHOME: Navigate to refinery
    - GOINGTOIDLE: No tiberium available, go idle

    The Status field tracks which phase we're in.
]]
function UnitClass:Mission_Harvest()
    -- Status values (matches original C++ enum)
    local LOOKING = 0
    local HARVESTING = 1
    local FINDHOME = 2
    local HEADINGHOME = 3
    local GOINGTOIDLE = 4

    -- Non-harvesting units just sit idle
    if not self:Is_Harvester() then
        return 15 * 30  -- Long delay
    end

    -- Initialize status if needed
    if not self.Status then
        self.Status = LOOKING
    end

    if self.Status == LOOKING then
        -- Go and find a Tiberium field to harvest
        self.IsHarvesting = false

        -- If TarCom is set, skip to finding home (used when ordered to return)
        if Target.Is_Valid(self.TarCom) then
            self:Assign_Target(Target.TARGET_NONE)
            self.Status = FINDHOME
            return 1
        end

        -- Try to find and move to tiberium
        if self:On_Tiberium() then
            -- Already on tiberium, start harvesting
            self.IsHarvesting = true
            self.Status = HARVESTING
            self.ArchiveTarget = Target.As_Target_Coord(self:Center_Coord())
            return 1
        elseif self:Find_Tiberium() then
            -- Found tiberium, will move there
            -- Stay in LOOKING until we arrive
            return 15
        else
            -- No tiberium found anywhere
            if not Target.Is_Valid(self.NavCom) then
                -- No destination and no tiberium - try archive or go idle
                if Target.Is_Valid(self.ArchiveTarget) then
                    self:Assign_Destination(self.ArchiveTarget)
                else
                    self.Status = GOINGTOIDLE
                    return 15 * 15
                end
            end
        end

    elseif self.Status == HARVESTING then
        -- Harvest at current location until full or tiberium exhausted
        if not self:Harvesting() then
            self.IsHarvesting = false
            if self:Is_Full() then
                -- Full load, head home
                self.Status = FINDHOME
            else
                -- Not full but can't harvest here anymore
                if not self:Find_Tiberium() and not Target.Is_Valid(self.NavCom) then
                    -- No more tiberium available, go home with partial load
                    self.ArchiveTarget = Target.TARGET_NONE
                    self.Status = FINDHOME
                else
                    -- Found more tiberium, continue harvesting after we get there
                    self.Status = LOOKING
                end
            end
            return 1
        else
            -- Remember this location for future reference
            if not Target.Is_Valid(self.NavCom) and self.ArchiveTarget == Target.TARGET_NONE then
                self.ArchiveTarget = Target.As_Target_Coord(self:Center_Coord())
            end
        end
        return UnitClass.HARVEST_DELAY

    elseif self.Status == FINDHOME then
        -- Find and head to refinery
        if not Target.Is_Valid(self.NavCom) then
            if self:Find_Refinery() then
                self.Status = HEADINGHOME
            else
                -- No refinery found, keep looking
                return 15
            end
        end
        return 1

    elseif self.Status == HEADINGHOME then
        -- In communication with refinery, let Mission_Enter handle docking
        self:Assign_Mission(self.MISSION.ENTER)
        return 1

    elseif self.Status == GOINGTOIDLE then
        -- No tiberium anywhere, go into guard mode
        self:Enter_Idle_Mode()
        return 1
    end

    return 15
end

--[[
    Mission_Unload - Harvester unloading at refinery.

    Reference: UnitClass::Mission_Unload from UNIT.CPP

    Called when harvester is docked at refinery. Offloads tiberium
    one bail at a time, crediting the owning house for each bail.
    When empty, returns to harvesting.
]]
function UnitClass:Mission_Unload()
    if not self:Is_Harvester() then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Empty? Go back to harvesting
    if self:Is_Empty() then
        -- Reset harvest status for new cycle
        self.Status = 0  -- LOOKING state
        self.IsHarvesting = false

        -- Break radio contact with refinery
        if self:In_Radio_Contact() then
            self:Transmit_Message(self.RADIO.OVER_OUT)
        end

        -- Find tiberium to harvest
        if self:Find_Tiberium() then
            self:Assign_Mission(self.MISSION.HARVEST)
        else
            self:Enter_Idle_Mode()
        end
        return 15
    end

    -- Unload one bail of tiberium
    local credits = self:Offload_Tiberium_Bail()
    if credits > 0 and self.House then
        -- Credit the owning house for tiberium value
        self.House:add_credits(credits)
    end

    return UnitClass.UNLOAD_DELAY
end

--[[
    Mission_Move - Override for harvester behavior.
]]
function UnitClass:Mission_Move()
    -- Check for stuck condition
    if self.IsDriving then
        -- Would check for progress
    end

    return TarComClass.Mission_Move(self)
end

--[[
    Mission_Guard - Guard behavior for units.
]]
function UnitClass:Mission_Guard()
    -- Harvesters should auto-harvest
    if self:Is_Harvester() and not self:Is_Full() then
        self:Assign_Mission(self.MISSION.HARVEST)
        return 1
    end

    return TarComClass.Mission_Guard(self)
end

--============================================================================
-- Idle Mode
--============================================================================

--[[
    Enter idle mode - harvesters start harvesting.
]]
function UnitClass:Enter_Idle_Mode(initial)
    if self:Is_Harvester() then
        if not self:Is_Full() then
            self:Assign_Mission(self.MISSION.HARVEST)
        else
            -- Full, return to refinery
            self:Find_Refinery()
        end
    else
        TarComClass.Enter_Idle_Mode(self, initial)
    end
end

--============================================================================
-- Voice Responses
--============================================================================

--[[
    Voice response when selected.
]]
function UnitClass:Response_Select()
    -- Would play selection voice
end

--[[
    Voice response when given move order.
]]
function UnitClass:Response_Move()
    -- Would play movement acknowledgment
end

--[[
    Voice response when given attack order.
]]
function UnitClass:Response_Attack()
    -- Would play attack acknowledgment
end

--============================================================================
-- AI Processing
--============================================================================

--[[
    AI processing for units.
]]
function UnitClass:AI()
    -- Call parent AI
    TarComClass.AI(self)

    -- Decrement timers
    if self.HarvestTimer > 0 then
        self.HarvestTimer = self.HarvestTimer - 1
    end

    if self.UnloadTimer > 0 then
        self.UnloadTimer = self.UnloadTimer - 1
    end

    -- Process deployment
    if self.IsDeploying then
        self.DeployTimer = self.DeployTimer - 1
        if self.DeployTimer <= 0 then
            self:Complete_Deploy()
        end
    end

    -- Animation timer
    if self.AnimTimer > 0 then
        self.AnimTimer = self.AnimTimer - 1
    end
end

--============================================================================
-- File I/O (Save/Load)
--============================================================================

function UnitClass:Code_Pointers()
    local data = TarComClass.Code_Pointers(self)

    -- Unit specific
    data.Tiberium = self.Tiberium
    data.HarvestTimer = self.HarvestTimer
    data.UnloadTimer = self.UnloadTimer
    data.Flagged = self.Flagged
    data.IsDeploying = self.IsDeploying
    data.DeployTimer = self.DeployTimer
    data.AnimTimer = self.AnimTimer
    data.JitterCount = self.JitterCount

    -- Type (store as name for lookup)
    if self.Class then
        data.TypeName = self.Class.IniName
    end

    return data
end

function UnitClass:Decode_Pointers(data, heap_lookup)
    TarComClass.Decode_Pointers(self, data, heap_lookup)

    if data then
        self.Tiberium = data.Tiberium or 0
        self.HarvestTimer = data.HarvestTimer or 0
        self.UnloadTimer = data.UnloadTimer or 0
        self.Flagged = data.Flagged or false
        self.IsDeploying = data.IsDeploying or false
        self.DeployTimer = data.DeployTimer or 0
        self.AnimTimer = data.AnimTimer or 0
        self.JitterCount = data.JitterCount or 0

        -- Type lookup would happen later
        self._decode_type_name = data.TypeName
    end
end

--============================================================================
-- Debug Support
--============================================================================

function UnitClass:Debug_Dump()
    TarComClass.Debug_Dump(self)

    print(string.format("UnitClass: Tiberium=%d/%d Flagged=%s",
        self.Tiberium,
        UnitClass.TIBERIUM_CAPACITY,
        tostring(self.Flagged)))

    print(string.format("  Timers: Harvest=%d Unload=%d Deploy=%d",
        self.HarvestTimer,
        self.UnloadTimer,
        self.DeployTimer))

    print(string.format("  State: Deploying=%s Jitter=%d",
        tostring(self.IsDeploying),
        self.JitterCount))
end

return UnitClass
