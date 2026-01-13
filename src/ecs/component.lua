--[[
    Component Registry - Defines and creates component data structures
    Components are plain data tables with no behavior
]]

local Component = {}

-- Registry of component definitions
local definitions = {}

-- Register a component type with default values
function Component.register(name, defaults)
    if definitions[name] then
        error("Component already registered: " .. name)
    end
    definitions[name] = defaults or {}
end

-- Create a new component instance with optional overrides
function Component.create(name, overrides)
    local defaults = definitions[name]
    if not defaults then
        error("Unknown component type: " .. name)
    end

    -- Create new component with defaults
    local component = {}
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            -- Deep copy tables
            component[k] = {}
            for k2, v2 in pairs(v) do
                component[k][k2] = v2
            end
        else
            component[k] = v
        end
    end

    -- Apply overrides
    if overrides then
        for k, v in pairs(overrides) do
            component[k] = v
        end
    end

    return component
end

-- Check if a component type exists
function Component.exists(name)
    return definitions[name] ~= nil
end

-- Get list of all registered component types
function Component.get_types()
    local types = {}
    for name in pairs(definitions) do
        table.insert(types, name)
    end
    return types
end

-- Get default values for a component type
function Component.get_defaults(name)
    return definitions[name]
end

-- Clear all registrations (for testing)
function Component.clear()
    definitions = {}
end

-- Register all standard game components
function Component.register_all()
    -- Transform: Position in the world
    Component.register("transform", {
        x = 0,              -- X position in leptons
        y = 0,              -- Y position in leptons
        cell_x = 0,         -- Cell X coordinate
        cell_y = 0,         -- Cell Y coordinate
        facing = 0,         -- 8-direction facing (0 = North)
        facing_full = 0     -- 32-direction facing for turrets
    })

    -- Renderable: Visual representation
    Component.register("renderable", {
        sprite = nil,       -- Sprite sheet name
        frame = 0,          -- Current animation frame
        animation = nil,    -- Current animation name
        layer = 0,          -- Render layer (GROUND, AIR, TOP)
        visible = true,     -- Is visible
        flash = false,      -- Flash white (damage indicator)
        scale_x = 1,
        scale_y = 1,
        offset_x = 0,       -- Render offset from position
        offset_y = 0,
        color = {1, 1, 1, 1}  -- RGBA tint
    })

    -- Health: Hit points and damage
    Component.register("health", {
        hp = 100,           -- Current hit points
        max_hp = 100,       -- Maximum hit points
        armor = 0,          -- Armor type (affects damage calculation)
        regenerate = 0      -- HP regeneration per tick
    })

    -- Owner: Faction ownership
    Component.register("owner", {
        house = 0,          -- House/faction ID
        color = 0,          -- Player color remap
        discovered_by = {}  -- Set of houses that have seen this unit
    })

    -- Selectable: Can be selected by player
    Component.register("selectable", {
        selected = false,   -- Currently selected
        group = 0,          -- Control group (1-9, 0 = none)
        select_priority = 0 -- Priority when multiple units selected
    })

    -- Mobile: Can move
    Component.register("mobile", {
        speed = 0,          -- Movement speed (leptons per tick)
        speed_type = 0,     -- Speed category (for terrain modifiers)
        locomotor = "foot", -- Movement type: foot, track, wheel, float, fly
        path = {},          -- Current path (list of cells)
        path_index = 0,     -- Current position in path
        destination_x = 0,  -- Final destination X
        destination_y = 0,  -- Final destination Y
        is_moving = false   -- Currently in motion
    })

    -- Combat: Can attack
    Component.register("combat", {
        primary_weapon = nil,   -- Primary weapon name
        secondary_weapon = nil, -- Secondary weapon name
        target = nil,           -- Current target entity ID
        ammo = -1,              -- Ammo count (-1 = infinite)
        rearm_timer = 0,        -- Ticks until can fire again
        attack_range = 0        -- Range in leptons
    })

    -- Production: Can build units/buildings
    Component.register("production", {
        queue = {},         -- Build queue (list of type names)
        progress = 0,       -- Build progress (0-100)
        factory_type = nil, -- What this factory produces
        is_primary = false  -- Is primary factory for type
    })

    -- Harvester: Collects resources
    Component.register("harvester", {
        tiberium_load = 0,      -- Current load (0-100)
        max_load = 100,         -- Maximum capacity
        refinery = nil,         -- Assigned refinery entity ID
        dock_timer = 0          -- Time spent docking
    })

    -- Mission: AI behavior state
    Component.register("mission", {
        mission_type = 0,   -- Current mission (MISSION enum)
        target = nil,       -- Mission target
        timer = 0,          -- Mission-specific timer
        waypoint = nil      -- Target waypoint
    })

    -- Turret: Rotating turret
    Component.register("turret", {
        facing = 0,         -- Turret facing (separate from body)
        rotation_speed = 1, -- Facing change per tick
        has_turret = true   -- Actually has a turret
    })

    -- Power: Produces or consumes power
    Component.register("power", {
        produces = 0,       -- Power produced
        consumes = 0        -- Power consumed
    })

    -- Cloakable: Can become invisible
    Component.register("cloakable", {
        cloak_state = 0,    -- CLOAK enum value
        cloak_timer = 0,    -- Timer for cloak transition
        cloak_delay = 150   -- Ticks before cloaking starts
    })

    -- Building: Structure-specific properties
    Component.register("building", {
        structure_type = nil,   -- Structure type name
        size_x = 1,             -- Width in cells
        size_y = 1,             -- Height in cells
        foundation = {},        -- Occupied cells
        bibbed = false,         -- Has ground bib
        repairing = false,      -- Being repaired
        repair_timer = 0,       -- Repair tick counter
        upgrading = false,      -- Being upgraded
        selling = false,        -- Being sold (animation in progress)
        sell_progress = 0       -- Sell animation progress (0-100)
    })

    -- Deployable: Can transform into a building (like MCV -> Construction Yard)
    Component.register("deployable", {
        deploys_to = nil,       -- Building type this unit deploys into
        deploying = false,      -- Currently deploying
        deploy_progress = 0     -- Deploy animation progress (0-100)
    })

    -- Infantry: Infantry-specific properties
    Component.register("infantry", {
        infantry_type = nil,    -- Infantry type name
        sub_position = 0,       -- Position within cell (0-4: center, NW, NE, SW, SE)
        prone = false,          -- Is prone
        can_capture = false,    -- Can capture buildings
        immune_tiberium = false -- Immune to Tiberium damage (Chem Warriors)
    })

    -- Vehicle: Vehicle-specific properties
    Component.register("vehicle", {
        vehicle_type = nil,     -- Vehicle type name
        rotating = false,       -- Is rotating in place
        crushing = false        -- Is crushing infantry
    })

    -- Aircraft: Aircraft-specific properties
    -- Reference: AIRCRAFT.H - FLIGHT_LEVEL = 24 pixels altitude
    Component.register("aircraft", {
        aircraft_type = nil,        -- Aircraft type name
        altitude = 0,               -- Current altitude in pixels (0 = landed, 24 = cruise)
        max_altitude = 24,          -- Max flight altitude (FLIGHT_LEVEL)
        landed = true,              -- On ground at helipad
        helipad = nil,              -- Assigned helipad entity ID
        is_landing = false,         -- Currently descending to land
        is_taking_off = false,      -- Currently ascending from helipad
        is_homing = false,          -- Adjusting heading toward target
        is_hovering = false,        -- Helicopter hovering to position
        visual_altitude_offset = 0  -- Jitter offset for helicopter bob effect
    })

    -- Cargo: Can carry other units
    Component.register("cargo", {
        capacity = 0,           -- Max passengers
        passengers = {},        -- List of passenger entity IDs
        unload_timer = 0        -- Unload delay
    })

    -- Spawner: Spawns other units
    Component.register("spawner", {
        spawn_type = nil,       -- What to spawn
        spawn_count = 0,        -- How many to spawn
        spawn_timer = 0,        -- Spawn delay
        spawn_limit = -1        -- Max spawns (-1 = infinite)
    })

    -- Animation: Animation state
    Component.register("animation", {
        animations = {},        -- Available animations
        current = nil,          -- Current animation name
        frame = 0,              -- Current frame
        timer = 0,              -- Frame timer
        looping = true,         -- Loop animation
        playing = true          -- Is playing
    })

    -- Audio: Sound properties
    Component.register("audio", {
        select_sounds = {},     -- Sounds when selected
        command_sounds = {},    -- Sounds when given orders
        attack_sounds = {},     -- Sounds when attacking
        die_sounds = {}         -- Sounds when destroyed
    })
end

return Component
