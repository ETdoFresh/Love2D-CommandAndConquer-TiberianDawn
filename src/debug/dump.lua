--[[
    Debug Dump System - Port of original C&C Debug_Dump() functionality

    Reference: TECHNO.CPP:453, OBJECT.CPP, RADIO.CPP, FOOT.CPP
    Each class in the original had a Debug_Dump(MonoClass*) method that
    displayed state information to the monochrome debug screen.

    This Lua port provides equivalent functionality using a formatted
    text output that can be displayed in-game or logged to file.
]]

local Dump = {}

-- Output buffer for dump operations
Dump.buffer = {}
Dump.enabled = true
Dump.log_file = nil
Dump.log_to_console = true
Dump.log_to_file = false

--[[
    Initialize the dump system.

    @param options - Table with optional settings:
        - log_to_console: boolean (default true)
        - log_to_file: boolean (default false)
        - log_path: string (default "debug_dump.log")
]]
function Dump.init(options)
    options = options or {}
    Dump.log_to_console = options.log_to_console ~= false
    Dump.log_to_file = options.log_to_file or false

    if Dump.log_to_file then
        local path = options.log_path or "debug_dump.log"
        Dump.log_file = io.open(path, "w")
        if Dump.log_file then
            Dump.log_file:write("=== C&C Tiberian Dawn Debug Dump ===\n")
            Dump.log_file:write("Started: " .. os.date() .. "\n\n")
        end
    end
end

--[[
    Enable or disable dump output.
]]
function Dump.set_enabled(enabled)
    Dump.enabled = enabled
end

--[[
    Clear the output buffer.
]]
function Dump.clear()
    Dump.buffer = {}
end

--[[
    Add a line to the dump buffer.

    @param text - Text to add
    @param indent - Indentation level (default 0)
]]
function Dump.print(text, indent)
    if not Dump.enabled then return end

    indent = indent or 0
    local prefix = string.rep("  ", indent)
    local line = prefix .. tostring(text)

    table.insert(Dump.buffer, line)

    if Dump.log_to_console then
        print(line)
    end

    if Dump.log_to_file and Dump.log_file then
        Dump.log_file:write(line .. "\n")
        Dump.log_file:flush()
    end
end

--[[
    Printf-style output to dump buffer.

    @param format - Format string
    @param ... - Format arguments
]]
function Dump.printf(format, ...)
    if not Dump.enabled then return end
    Dump.print(string.format(format, ...))
end

--[[
    Print a separator line.
]]
function Dump.separator(char, width)
    char = char or "-"
    width = width or 60
    Dump.print(string.rep(char, width))
end

--[[
    Print a section header.

    @param title - Section title
]]
function Dump.section(title)
    Dump.print("")
    Dump.separator("=")
    Dump.printf("  %s", title)
    Dump.separator("=")
end

--[[
    Print a flag value with X marker like original.

    Reference: TECHNO.CPP:457-464 used Text_Print("X", col, row) format
]]
function Dump.flag(name, value)
    local marker = value and "[X]" or "[ ]"
    Dump.printf("  %s %s", marker, name)
end

--[[
    Print a key-value pair.
]]
function Dump.field(name, value, format)
    if format then
        Dump.printf("  %-20s: " .. format, name, value)
    else
        Dump.printf("  %-20s: %s", name, tostring(value))
    end
end

--[[
    Print a hex value.
]]
function Dump.hex(name, value)
    if type(value) == "number" then
        Dump.printf("  %-20s: 0x%04X (%d)", name, value, value)
    else
        Dump.printf("  %-20s: %s", name, tostring(value))
    end
end

--[[
    Dump an AbstractClass object.

    Reference: ABSTRACT.CPP Debug_Dump()
]]
function Dump.abstract(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("AbstractClass")
    Dump.field("IsActive", obj.is_active or obj.IsActive)

    -- Coordinate info
    if obj.coord then
        Dump.field("Coord.x", obj.coord.x)
        Dump.field("Coord.y", obj.coord.y)
    elseif obj.Coord then
        Dump.field("Coord", obj.Coord)
    end

    Dump.flag("IsRecentlyCreated", obj.IsRecentlyCreated or obj.is_recently_created)
end

--[[
    Dump an ObjectClass object.

    Reference: OBJECT.CPP Debug_Dump()
]]
function Dump.object(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("ObjectClass")

    -- Basic object flags
    Dump.flag("IsDown", obj.IsDown or obj.is_down)
    Dump.flag("IsInLimbo", obj.IsInLimbo or obj.in_limbo)
    Dump.flag("IsSelected", obj.IsSelected or obj.is_selected)

    -- Health
    if obj.health then
        Dump.field("Strength", string.format("%d/%d", obj.health.current or 0, obj.health.max or 0))
    elseif obj.Strength then
        Dump.field("Strength", obj.Strength)
    end

    -- Next object in list
    if obj.Next then
        Dump.hex("Next", obj.Next)
    end

    -- Trigger reference
    if obj.Trigger then
        Dump.field("Trigger", obj.Trigger)
    end

    -- Call parent dump
    Dump.abstract(obj)
end

--[[
    Dump a MissionClass object.

    Reference: MISSION.CPP Debug_Dump()
]]
function Dump.mission(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("MissionClass")

    -- Mission state
    Dump.field("Mission", obj.Mission or obj.mission or "NONE")
    Dump.field("SuspendedMission", obj.SuspendedMission or obj.suspended_mission or "NONE")

    -- Timer
    if obj.Timer then
        Dump.field("Timer", obj.Timer)
    end

    -- Mission queue
    if obj.MissionQueue then
        Dump.field("MissionQueue", obj.MissionQueue)
    end

    -- Call parent dump
    Dump.object(obj)
end

--[[
    Dump a RadioClass object.

    Reference: RADIO.CPP Debug_Dump()
]]
function Dump.radio(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("RadioClass")

    -- Radio contact
    if obj.Radio then
        Dump.field("Radio", obj.Radio)
    end

    Dump.field("LastMessage", obj.LastMessage or obj.last_message or "NONE")

    -- Call parent dump
    Dump.mission(obj)
end

--[[
    Dump a TechnoClass object.

    Reference: TECHNO.CPP:453-472 Debug_Dump()

    Original output format:
    - Power fraction, power, drain at (0,0)
    - Various flags with X markers
    - Arm countdown, TarCom, PrimaryFacing values
]]
function Dump.techno(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("TechnoClass")

    -- House info (original: Power_Fraction, Power, Drain)
    if obj.house then
        Dump.field("House", obj.house)
    elseif obj.House then
        Dump.field("House", obj.House and obj.House:Get_Name() or "none")
    end

    -- Owner component
    if obj.has and obj:has("owner") then
        local owner = obj:get("owner")
        Dump.field("Owner.house", owner.house)
    end

    -- TechnoClass flags (Reference: TECHNO.CPP:457-464)
    Dump.print("")
    Dump.print("  Flags:")
    Dump.flag("IsALoaner", obj.IsALoaner or obj.is_loaner)
    Dump.flag("IsLocked", obj.IsLocked or obj.is_locked)
    Dump.flag("IsInRecoilState", obj.IsInRecoilState or obj.in_recoil)
    Dump.flag("IsTethered", obj.IsTethered or obj.is_tethered)
    Dump.flag("IsOwnedByPlayer", obj.IsOwnedByPlayer or obj.owned_by_player)
    Dump.flag("IsDiscoveredByPlayer", obj.IsDiscoveredByPlayer or obj.discovered_by_player)
    Dump.flag("IsALemon", obj.IsALemon or obj.is_lemon)
    Dump.flag("IsCloakable", obj.IsCloakable or obj.is_cloakable)
    Dump.flag("IsLeader", obj.IsLeader or obj.is_leader)

    -- Combat stats (Reference: TECHNO.CPP:465-467)
    Dump.print("")
    Dump.print("  Combat:")
    Dump.field("Arm", obj.Arm or obj.arm or 0)
    Dump.hex("TarCom", obj.TarCom or obj.tarcom or 0)
    Dump.hex("PrimaryFacing", obj.PrimaryFacing or obj.primary_facing or 0)
    Dump.field("Ammo", obj.Ammo or obj.ammo or -1)

    -- Cloak state
    Dump.field("Cloak", obj.Cloak or obj.cloak_state or "UNCLOAKED")

    -- Call parent dump
    Dump.radio(obj)
end

--[[
    Dump a FootClass object.

    Reference: FOOT.CPP Debug_Dump()
]]
function Dump.foot(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("FootClass")

    -- Navigation
    Dump.hex("NavCom", obj.NavCom or obj.navcom or 0)

    -- Path info
    if obj.Path then
        Dump.field("PathLength", #obj.Path)
    end

    Dump.field("PathDelay", obj.PathDelay or obj.path_delay or 0)

    -- Team membership
    if obj.Team then
        Dump.field("Team", obj.Team)
    end

    -- Group assignment (1-9)
    Dump.field("Group", obj.Group or obj.group or 0)

    -- Movement flags
    Dump.print("")
    Dump.print("  Movement Flags:")
    Dump.flag("IsInitiated", obj.IsInitiated or obj.is_initiated)
    Dump.flag("IsDriving", obj.IsDriving or obj.is_driving)
    Dump.flag("IsRotating", obj.IsRotating or obj.is_rotating)

    -- Speed and heading
    Dump.field("Speed", obj.Speed or obj.speed or 0)
    Dump.hex("HeadTo", obj.HeadTo or obj.head_to or 0)

    -- Call parent dump
    Dump.techno(obj)
end

--[[
    Dump an InfantryClass object.

    Reference: INFANTRY.CPP Debug_Dump()
]]
function Dump.infantry(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("InfantryClass")

    -- Infantry-specific fields
    Dump.field("Fear", obj.Fear or obj.fear or 0)
    Dump.field("Doing", obj.Doing or obj.doing or "NOTHING")

    -- Prone state
    Dump.flag("IsProne", obj.IsProne or obj.is_prone)

    -- Occupy spot
    Dump.field("OccupySpot", obj.OccupySpot or obj.occupy_spot or 0)

    -- Call parent dump
    Dump.foot(obj)
end

--[[
    Dump a UnitClass object.

    Reference: UNIT.CPP Debug_Dump()
]]
function Dump.unit(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("UnitClass")

    -- Unit-specific fields
    Dump.flag("IsHarvesting", obj.IsHarvesting or obj.is_harvesting)
    Dump.flag("IsReturning", obj.IsReturning or obj.is_returning)

    -- Turret facing (if applicable)
    if obj.TurretFacing or obj.turret_facing then
        Dump.hex("TurretFacing", obj.TurretFacing or obj.turret_facing)
    end

    -- Tiberium load
    Dump.field("Tiberium", obj.Tiberium or obj.tiberium or 0)

    -- Call parent dump
    Dump.foot(obj)
end

--[[
    Dump a BuildingClass object.

    Reference: BUILDING.CPP Debug_Dump()
]]
function Dump.building(obj)
    if not obj then
        Dump.print("(nil)")
        return
    end

    Dump.section("BuildingClass")

    -- Building type
    if obj.has and obj:has("building") then
        local building = obj:get("building")
        Dump.field("StructureType", building.structure_type)
    end

    -- Production state
    if obj.has and obj:has("production") then
        local prod = obj:get("production")
        Dump.flag("IsPrimary", prod.is_primary)
        Dump.flag("IsRepairing", prod.is_repairing)
        Dump.field("QueueLength", #prod.queue)
        Dump.field("Progress", string.format("%.1f%%", (prod.progress or 0) * 100))
    end

    -- Power
    Dump.field("Power", obj.Power or obj.power or 0)
    Dump.field("Drain", obj.Drain or obj.drain or 0)

    -- Building flags
    Dump.flag("IsCharging", obj.IsCharging or obj.is_charging)
    Dump.flag("IsReady", obj.IsReady or obj.is_ready)

    -- Call parent dump
    Dump.techno(obj)
end

--[[
    Dump an ECS entity with all components.

    This provides a complete dump of an entity in the ECS architecture.
]]
function Dump.entity(entity)
    if not entity then
        Dump.print("(nil entity)")
        return
    end

    Dump.section("Entity")
    Dump.field("ID", entity.id or "unknown")

    -- Check for specific component types and dump accordingly
    if entity.has then
        -- Transform component
        if entity:has("transform") then
            local t = entity:get("transform")
            Dump.print("")
            Dump.print("  [Transform]")
            Dump.field("Position", string.format("(%.1f, %.1f)", t.x or 0, t.y or 0))
            Dump.field("Cell", string.format("(%d, %d)", t.cell_x or 0, t.cell_y or 0))
            Dump.hex("Facing", t.facing or 0)
        end

        -- Health component
        if entity:has("health") then
            local h = entity:get("health")
            Dump.print("")
            Dump.print("  [Health]")
            Dump.field("HP", string.format("%d/%d", h.current or 0, h.max or 0))
            Dump.flag("IsDead", h.is_dead or (h.current <= 0))
            Dump.flag("IsRepairing", h.repairing)
        end

        -- Owner component
        if entity:has("owner") then
            local o = entity:get("owner")
            Dump.print("")
            Dump.print("  [Owner]")
            Dump.field("House", o.house)
        end

        -- Combat component
        if entity:has("combat") then
            local c = entity:get("combat")
            Dump.print("")
            Dump.print("  [Combat]")
            Dump.field("Weapon", c.weapon_type or "none")
            Dump.field("Range", c.range or 0)
            Dump.field("Cooldown", string.format("%.1f", c.cooldown or 0))
            if c.target then
                Dump.field("Target", c.target)
            end
        end

        -- Movement component
        if entity:has("movement") then
            local m = entity:get("movement")
            Dump.print("")
            Dump.print("  [Movement]")
            Dump.field("Speed", m.speed or 0)
            Dump.flag("IsMoving", m.is_moving)
            if m.destination then
                Dump.field("Destination", string.format("(%.1f, %.1f)",
                    m.destination.x or 0, m.destination.y or 0))
            end
        end

        -- Mission component
        if entity:has("mission") then
            local m = entity:get("mission")
            Dump.print("")
            Dump.print("  [Mission]")
            Dump.field("Current", m.current or "NONE")
            Dump.field("Suspended", m.suspended or "NONE")
        end

        -- Building component
        if entity:has("building") then
            local b = entity:get("building")
            Dump.print("")
            Dump.print("  [Building]")
            Dump.field("Type", b.structure_type)
            Dump.field("Power", b.power or 0)
            Dump.field("Drain", b.drain or 0)
        end

        -- Production component
        if entity:has("production") then
            local p = entity:get("production")
            Dump.print("")
            Dump.print("  [Production]")
            Dump.flag("IsPrimary", p.is_primary)
            Dump.field("QueueSize", #p.queue)
            Dump.field("Progress", string.format("%.1f%%", (p.progress or 0) * 100))
            Dump.flag("ReadyToPlace", p.ready_to_place)
        end

        -- Cloak component
        if entity:has("cloak") then
            local c = entity:get("cloak")
            Dump.print("")
            Dump.print("  [Cloak]")
            Dump.field("State", c.state or "UNCLOAKED")
            Dump.field("Timer", c.timer or 0)
        end

        -- Cargo component
        if entity:has("cargo") then
            local c = entity:get("cargo")
            Dump.print("")
            Dump.print("  [Cargo]")
            Dump.field("Capacity", c.capacity or 0)
            Dump.field("Passengers", c.count or 0)
        end
    end

    Dump.separator()
end

--[[
    Dump game world state summary.
]]
function Dump.world(world)
    if not world then
        Dump.print("(nil world)")
        return
    end

    Dump.section("World State")

    local entities = world:get_all_entities()
    Dump.field("Total Entities", #entities)

    -- Count by type
    local counts = {
        infantry = 0,
        unit = 0,
        building = 0,
        aircraft = 0,
        bullet = 0,
        other = 0
    }

    for _, entity in ipairs(entities) do
        if entity:has("infantry") then
            counts.infantry = counts.infantry + 1
        elseif entity:has("unit") then
            counts.unit = counts.unit + 1
        elseif entity:has("building") then
            counts.building = counts.building + 1
        elseif entity:has("aircraft") then
            counts.aircraft = counts.aircraft + 1
        elseif entity:has("bullet") then
            counts.bullet = counts.bullet + 1
        else
            counts.other = counts.other + 1
        end
    end

    Dump.print("")
    Dump.print("  Entity Counts:")
    Dump.field("Infantry", counts.infantry)
    Dump.field("Units", counts.unit)
    Dump.field("Buildings", counts.building)
    Dump.field("Aircraft", counts.aircraft)
    Dump.field("Bullets", counts.bullet)
    Dump.field("Other", counts.other)

    Dump.separator()
end

--[[
    Dump house/faction state.
]]
function Dump.house(house_data)
    if not house_data then
        Dump.print("(nil house)")
        return
    end

    Dump.section("HouseClass")

    Dump.field("Name", house_data.name or house_data.Name or "unknown")
    Dump.field("ActLike", house_data.act_like or house_data.ActLike)

    -- Economy
    Dump.print("")
    Dump.print("  Economy:")
    Dump.field("Credits", house_data.credits or house_data.Credits or 0)
    Dump.field("Capacity", house_data.capacity or house_data.Capacity or 0)
    Dump.field("Tiberium", house_data.tiberium or house_data.Tiberium or 0)

    -- Power
    Dump.print("")
    Dump.print("  Power:")
    Dump.field("Power", house_data.power or house_data.Power or 0)
    Dump.field("Drain", house_data.drain or house_data.Drain or 0)
    if house_data.power and house_data.drain then
        local ratio = house_data.drain > 0 and (house_data.power / house_data.drain) or 1.0
        Dump.field("PowerRatio", string.format("%.2f", ratio))
    end

    -- Allies
    if house_data.allies or house_data.Allies then
        Dump.field("Allies", house_data.allies or house_data.Allies)
    end

    Dump.separator()
end

--[[
    Get the current buffer contents as a string.
]]
function Dump.get_output()
    return table.concat(Dump.buffer, "\n")
end

--[[
    Shutdown and close log file.
]]
function Dump.shutdown()
    if Dump.log_file then
        Dump.log_file:write("\n=== End Debug Dump ===\n")
        Dump.log_file:close()
        Dump.log_file = nil
    end
end

return Dump
