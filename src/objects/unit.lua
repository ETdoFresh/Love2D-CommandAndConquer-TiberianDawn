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
    Find and return to nearest refinery.
]]
function UnitClass:Find_Refinery()
    if not self.House then
        return false
    end

    -- Would search for nearest refinery
    -- self.ArchiveTarget = refinery:As_Target()
    -- self:Assign_Destination(self.ArchiveTarget)
    -- self:Assign_Mission(self.MISSION.ENTER)

    return false
end

--[[
    Find and harvest from nearest tiberium.
]]
function UnitClass:Find_Tiberium()
    -- Would search for nearest tiberium field
    -- self:Assign_Destination(tiberium_coord)
    -- self:Assign_Mission(self.MISSION.HARVEST)

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
]]
function UnitClass:Complete_Deploy()
    if not self.IsDeploying then
        return false
    end

    -- Create construction yard at this location
    -- local coord = self:Center_Coord()
    -- local building = BuildingClass:new(BuildingTypeClass.FACT, self.House)
    -- building:Unlimbo(coord, 0)

    -- Remove self
    self:Limbo()

    return true
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
    Mission_Harvest - Harvester behavior.
]]
function UnitClass:Mission_Harvest()
    if not self:Is_Harvester() then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Full? Return to refinery
    if self:Is_Full() then
        self:Find_Refinery()
        return 15
    end

    -- Try to harvest
    if self:Harvest() then
        return UnitClass.HARVEST_DELAY
    end

    -- No tiberium here, find more
    self:Find_Tiberium()

    return 15
end

--[[
    Mission_Unload - Harvester unloading at refinery.
]]
function UnitClass:Mission_Unload()
    if not self:Is_Harvester() then
        self:Enter_Idle_Mode()
        return 15
    end

    -- Empty? Go back to harvesting
    if self:Is_Empty() then
        self:Find_Tiberium()
        return 15
    end

    -- Unload one bail
    local credits = self:Offload_Tiberium_Bail()
    if credits > 0 and self.House then
        -- self.House:Refund_Money(credits)
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
