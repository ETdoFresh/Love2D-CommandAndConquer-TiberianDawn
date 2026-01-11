# Command & Conquer Tiberian Dawn - Love2D Port

## Overview
Port the original C&C Tiberian Dawn (~210,000 lines of C++) to Love2D with:
- Full GDI and Nod campaigns
- Multiplayer support (deterministic lockstep)
- Asset extraction pipeline from original MIX files
- Data-driven design with JSON configuration

## Naming Conventions
- **Files/directories**: `snake_case` (e.g., `movement_system.lua`, `src/systems/`)
- **Class tables**: `PascalCase` (e.g., `local MovementSystem = {}`)
- **Functions/variables**: `snake_case` (e.g., `function Entity:get_component()`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `CELL_SIZE = 24`)

---

## Project Structure

```
LoveCommandAndConquer2D/
├── main.lua
├── conf.lua
│
├── src/
│   ├── core/
│   │   ├── init.lua
│   │   ├── game.lua              # Main game state machine
│   │   ├── constants.lua         # CELL_SIZE, TICK_RATE, etc.
│   │   ├── events.lua            # Event bus
│   │   └── pool.lua              # Object pooling
│   │
│   ├── ecs/
│   │   ├── init.lua              # ECS manager
│   │   ├── entity.lua            # Entity factory
│   │   ├── component.lua         # Component registry
│   │   ├── system.lua            # System base
│   │   └── world.lua             # World container
│   │
│   ├── components/
│   │   ├── transform.lua         # x, y, cell, facing
│   │   ├── renderable.lua        # sprite, frame, animation
│   │   ├── health.lua            # hp, armor_type
│   │   ├── owner.lua             # house, discovered_by
│   │   ├── selectable.lua        # is_selected, group
│   │   ├── mobile.lua            # speed, path, destination
│   │   ├── combat.lua            # weapons, target, ammo
│   │   ├── production.lua        # queue, progress
│   │   ├── harvester.lua         # tiberium_load, refinery
│   │   ├── mission.lua           # current_mission, timer
│   │   ├── turret.lua            # turret_facing
│   │   ├── power.lua             # produces, consumes
│   │   └── cloakable.lua         # cloak_state, cloak_timer
│   │
│   ├── systems/
│   │   ├── render_system.lua
│   │   ├── movement_system.lua
│   │   ├── combat_system.lua
│   │   ├── ai_system.lua
│   │   ├── production_system.lua
│   │   ├── harvest_system.lua
│   │   ├── animation_system.lua
│   │   ├── selection_system.lua
│   │   ├── trigger_system.lua
│   │   ├── power_system.lua
│   │   ├── fog_system.lua
│   │   └── cloak_system.lua
│   │
│   ├── map/
│   │   ├── init.lua
│   │   ├── cell.lua              # Cell data structure
│   │   ├── grid.lua              # 64x64 cell grid
│   │   ├── terrain.lua           # Templates, overlays
│   │   ├── pathfinding.lua       # A* implementation
│   │   ├── theater.lua           # Temperate/Winter/Desert
│   │   └── shroud.lua            # Fog of war
│   │
│   ├── house/
│   │   ├── init.lua
│   │   ├── house.lua             # Faction class
│   │   ├── economy.lua           # Credits, capacity
│   │   ├── tech_tree.lua         # Prerequisites
│   │   └── ai_controller.lua     # Computer player AI
│   │
│   ├── scenario/
│   │   ├── init.lua
│   │   ├── loader.lua            # Scenario loader
│   │   ├── trigger.lua           # Trigger system
│   │   ├── team.lua              # AI teams
│   │   └── waypoints.lua         # Named locations
│   │
│   ├── ui/
│   │   ├── init.lua
│   │   ├── sidebar.lua           # Build sidebar
│   │   ├── radar.lua             # Minimap
│   │   ├── selection_box.lua     # Drag selection
│   │   ├── cursor.lua            # Mouse cursors
│   │   ├── messages.lua          # In-game messages
│   │   └── power_bar.lua         # Power indicator
│   │
│   ├── input/
│   │   ├── init.lua
│   │   ├── keyboard.lua
│   │   ├── mouse.lua
│   │   └── commands.lua          # Command pattern
│   │
│   ├── audio/
│   │   ├── init.lua
│   │   ├── music.lua
│   │   ├── sfx.lua
│   │   └── speech.lua            # EVA voice
│   │
│   ├── video/
│   │   └── cutscene.lua          # MP4 playback
│   │
│   ├── net/
│   │   ├── init.lua
│   │   ├── protocol.lua          # Message encoding
│   │   ├── lockstep.lua          # Deterministic sync
│   │   ├── lobby.lua             # Game lobby
│   │   └── replay.lua            # Replay system
│   │
│   └── util/
│       ├── vector.lua            # 2D vector math
│       ├── direction.lua         # 8/32 direction helpers
│       ├── crc.lua               # CRC32 for sync
│       ├── random.lua            # Deterministic RNG
│       └── serialize.lua         # Save/load
│
├── data/
│   ├── units/
│   │   ├── infantry.json
│   │   ├── vehicles.json
│   │   └── aircraft.json
│   │
│   ├── buildings/
│   │   ├── structures.json
│   │   └── walls.json
│   │
│   ├── weapons/
│   │   ├── weapons.json
│   │   ├── warheads.json
│   │   └── projectiles.json
│   │
│   ├── terrain/
│   │   ├── templates.json
│   │   └── overlays.json
│   │
│   ├── houses/
│   │   ├── factions.json
│   │   └── tech_trees.json
│   │
│   ├── scenarios/
│   │   ├── gdi/                  # 15 GDI missions
│   │   ├── nod/                  # 13 Nod missions
│   │   └── multiplayer/
│   │
│   └── audio/
│       ├── themes.json
│       └── sounds.json
│
├── assets/
│   ├── sprites/
│   │   ├── infantry/
│   │   ├── vehicles/
│   │   ├── aircraft/
│   │   ├── buildings/
│   │   ├── terrain/
│   │   ├── effects/
│   │   └── ui/
│   │
│   ├── audio/
│   │   ├── music/               # .ogg files
│   │   ├── sfx/                 # .ogg files
│   │   └── speech/              # .ogg files
│   │
│   └── video/
│       └── cutscenes/           # .mp4 files
│
└── tools/
    ├── mix_extractor/
    │   ├── main.lua
    │   ├── mix_format.lua
    │   └── crc_lookup.lua
    │
    ├── sprite_converter/
    │   ├── main.lua
    │   ├── shp_parser.lua
    │   ├── palette.lua
    │   └── spritesheet.lua
    │
    ├── audio_converter/
    │   └── main.lua
    │
    └── scenario_converter/
        ├── main.lua
        └── ini_parser.lua
```

---

## Implementation Phases

### Phase 1: Foundation
**Goal**: Render map, place units, move them around

1. **ECS Framework** - `src/ecs/`
   - Entity, Component, System, World classes
   - Query system for component combinations

2. **Map System** - `src/map/`
   - 64x64 cell grid (from CELL.H)
   - Cell data: terrain, occupancy, overlay
   - Basic terrain rendering

3. **Core Components** - `src/components/`
   - Transform, Renderable, Selectable, Mobile

4. **Basic Systems** - `src/systems/`
   - RenderSystem, SelectionSystem, MovementSystem

5. **Asset Pipeline** - `tools/`
   - MIX extractor (from MIXFILE.H format)
   - SHP to PNG converter with palette support
   - Initial JSON data files for units/buildings

**Key Source Reference**:
- [CELL.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/CELL.H)
- [DEFINES.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H)

---

### Phase 2: Combat & AI
**Goal**: Units fight, respond to threats

1. **Weapons System** - `src/systems/combat_system.lua`
   - Projectile spawning and travel
   - Damage calculation with armor modifiers
   - Warhead effects (from WARHEAD.H)

2. **Mission System** - `src/systems/ai_system.lua`
   - MissionType enum: Guard, Attack, Move, Hunt, etc.
   - Target acquisition and threat evaluation

3. **Pathfinding** - `src/map/pathfinding.lua`
   - A* for cell-based movement
   - Occupancy checking
   - Multi-cell building avoidance

4. **Combat Components** - `src/components/`
   - Combat, Mission, Health with armor types

**Key Source Reference**:
- [MISSION.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/MISSION.H)
- [TECHNO.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TECHNO.H)
- [BULLET.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.H)

---

### Phase 3: Economy & Production
**Goal**: Build bases, harvest Tiberium, train units

1. **Tiberium System**
   - Tiberium overlay spawning and growth
   - Harvester collection logic
   - Refinery processing

2. **Production System** - `src/systems/production_system.lua`
   - Building placement with prerequisites
   - Unit training queues
   - Factory assignment (primary)

3. **Power System** - `src/systems/power_system.lua`
   - Power production/consumption tracking
   - Low power penalties

4. **Sidebar UI** - `src/ui/sidebar.lua`
   - Build icons with progress
   - Production queue display
   - Credits counter

**Key Source Reference**:
- [FACTORY.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/FACTORY.H)
- [HOUSE.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/HOUSE.H)

---

### Phase 4: Multiplayer
**Goal**: Stable 2+ player online matches

1. **Deterministic Lockstep** - `src/net/lockstep.lua`
   - Frame-synchronized command execution
   - Input delay for network latency

2. **Deterministic RNG** - `src/util/random.lua`
   - Seeded LCG matching original algorithm
   - No floats in gameplay calculations

3. **Network Protocol** - `src/net/protocol.lua`
   - Event encoding (from EVENT.H)
   - CRC sync checks per frame

4. **Desync Detection**
   - State CRC comparison
   - Resync recovery

5. **Lobby System** - `src/net/lobby.lua`
   - Host/join games
   - Player slots and factions

**Key Source Reference**:
- [EVENT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/EVENT.H)

---

### Phase 5: Campaign & Scenarios
**Goal**: Full GDI + Nod campaigns

1. **Trigger System** - `src/scenario/trigger.lua`
   - Event conditions (unit destroyed, time elapsed, etc.)
   - Actions (reinforcements, messages, win/lose)

2. **Team System** - `src/scenario/team.lua`
   - AI team coordination
   - Formation movement

3. **Scenario Loader** - `src/scenario/loader.lua`
   - Parse JSON scenario files
   - Place initial units/buildings
   - Set up triggers

4. **Mission Briefings**
   - Text display
   - Map reveal animations

5. **All Missions**
   - 15 GDI missions
   - 13 Nod missions
   - Branching paths

**Key Source Reference**:
- [TRIGGER.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TRIGGER.H)
- [TEAM.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TEAM.H)
- [SCENARIO.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/SCENARIO.H)

---

### Phase 6: Polish
**Goal**: Feature complete, release quality

1. **Fog of War** - `src/systems/fog_system.lua`
   - Shroud (never seen) vs fog (previously seen)
   - Unit sight ranges

2. **Special Weapons**
   - Ion Cannon, Nuclear Strike, Airstrike
   - Targeting UI

3. **Audio System** - `src/audio/`
   - Background music
   - Unit responses
   - EVA announcements

4. **Cutscenes** - `src/video/cutscene.lua`
   - MP4 playback for briefings

5. **Cloaking** - `src/systems/cloak_system.lua`
   - Stealth tank mechanics

---

## Critical Source Files

Reference these during implementation:

| File | Purpose |
|------|---------|
| `DEFINES.H` | All enums (units, buildings, weapons, missions) |
| `TECHNO.H` | Core combat entity functionality |
| `CELL.H` | Map cell structure |
| `EVENT.H` | Network event types for multiplayer |
| `TRIGGER.H` | Campaign trigger/scripting system |
| `MISSION.H` | AI mission types |
| `HOUSE.H` | Faction and economy |
| `MIXFILE.H` | Asset archive format |

---

## Verification Plan

### During Development
- Run with `love .` from project root
- Use Love2D console for debugging (`io.write`, `print`)

### Per-Phase Testing
1. **Phase 1**: Render map, click to select units, right-click to move
2. **Phase 2**: Units attack enemies, die, explode
3. **Phase 3**: Build from MCV, harvest, produce units
4. **Phase 4**: Host game, join from second client, play synchronized
5. **Phase 5**: Load GDI mission 1, complete objectives, win
6. **Phase 6**: Full playthrough of both campaigns

### Multiplayer Sync Testing
- Record replays and verify identical final state CRC
- Run same inputs on two clients, compare frame-by-frame

### Performance Targets
- 60 FPS at 1080p
- 500+ entities without slowdown
- No GC stutters during gameplay
