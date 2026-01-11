# Command & Conquer Tiberian Dawn - Love2D Port

## Overview

A faithful port of Command & Conquer: Tiberian Dawn to Love2D, recreating the original gameplay experience with optional HD graphics support. This is a fan project requiring ownership of C&C Remastered Collection for assets.

**Target**: Playable fan remake for C&C enthusiasts
**Engine**: Love2D 11.5+ (LuaJIT)
**License**: Fan project - EA/Westwood trademark attribution required

### Core Features
- Full GDI and Nod campaigns (15 + 13 missions)
- Covert Operations expansion missions included
- Multiplayer support (6 players, deterministic lockstep)
- Full skirmish mode with AI opponents
- Scenario editor for custom maps
- Asset extraction pipeline from original MIX files

### Intentional Deviations from Original
| Feature | Original | This Port |
|---------|----------|-----------|
| Graphics | 320x200 fixed | Toggle: Pixel-perfect OR Remastered HD |
| Audio | Classic only | Toggle: Classic OR Remastered |
| Input | Keyboard/mouse | Full controller support (virtual cursor, radial menus) |
| Spectating | None | Full observer mode with perspective switching |
| Map Editor | Hidden, limited | Full in-game scenario editor |
| Hotkeys | Fixed bindings | Fully rebindable |
| Cutscenes | Low-res FMV | Remastered HD videos |

---

## Naming Conventions

- **Files/directories**: `snake_case` (e.g., `movement_system.lua`, `src/systems/`)
- **Class tables**: `PascalCase` (e.g., `local MovementSystem = {}`)
- **Functions/variables**: `snake_case` (e.g., `function Entity:get_component()`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `CELL_SIZE = 24`)

---

## Technical Specifications

### Engine & Runtime
- **Love2D Version**: 11.5 (latest stable)
- **Lua Version**: LuaJIT (Love2D default)
- **Target Resolution**: 320x200 (classic) / 1920x1080+ (HD mode)
- **Target FPS**: 60 FPS rendering

### Game Timing (Match Original)
- **Logic Tick Rate**: 15 FPS (`TICKS_PER_SECOND = 15`)
- **Coordinate System**: Leptons (256 leptons per cell)
- **Game Speed Levels**: Slowest / Slower / Normal / Faster / Fastest

### Networking
- **Transport**: LuaSocket (TCP/UDP)
- **Protocol**: Deterministic lockstep
- **Max Players**: 6 (original limit)
- **Disconnect Handling**: Game ends immediately

### Data Format
- **Configuration**: JSON data files
- **Validation**: Runtime only (error on invalid data)
- **Scenarios**: JSON (converted from original INI)

---

## Project Structure

```
Love2D-CommandAndConquer-TiberianDawn/
├── main.lua
├── conf.lua
│
├── src/
│   ├── core/
│   │   ├── init.lua
│   │   ├── game.lua              # Main game state machine
│   │   ├── constants.lua         # CELL_SIZE, TICK_RATE, LEPTON_PER_CELL
│   │   ├── events.lua            # Event bus
│   │   └── pool.lua              # Object pooling
│   │
│   ├── ecs/
│   │   ├── init.lua              # Custom lightweight ECS manager
│   │   ├── entity.lua            # Entity factory
│   │   ├── component.lua         # Component registry
│   │   ├── system.lua            # System base class
│   │   └── world.lua             # World container
│   │
│   ├── components/
│   │   ├── transform.lua         # x, y (leptons), cell, facing
│   │   ├── renderable.lua        # sprite, frame, animation
│   │   ├── health.lua            # hp, armor_type
│   │   ├── owner.lua             # house, discovered_by
│   │   ├── selectable.lua        # is_selected, group (1-9)
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
│   │   ├── movement_system.lua   # Original pathfinding behavior
│   │   ├── combat_system.lua
│   │   ├── ai_system.lua         # Original team-based AI
│   │   ├── production_system.lua # Single-item queue
│   │   ├── harvest_system.lua
│   │   ├── animation_system.lua
│   │   ├── selection_system.lua  # Configurable classic/modern
│   │   ├── trigger_system.lua
│   │   ├── power_system.lua
│   │   ├── fog_system.lua        # Shroud + fog
│   │   └── cloak_system.lua
│   │
│   ├── map/
│   │   ├── init.lua
│   │   ├── cell.lua              # Cell data (terrain, occupancy, overlay)
│   │   ├── grid.lua              # 64x64 cell grid
│   │   ├── terrain.lua           # Templates, overlays
│   │   ├── pathfinding.lua       # A* with original blocking behavior
│   │   ├── theater.lua           # Temperate/Winter/Desert
│   │   └── shroud.lua            # Fog of war
│   │
│   ├── house/
│   │   ├── init.lua
│   │   ├── house.lua             # Faction class (max 6 players)
│   │   ├── economy.lua           # Credits, capacity
│   │   ├── tech_tree.lua         # Prerequisites
│   │   └── ai_controller.lua     # Original scripted AI behavior
│   │
│   ├── scenario/
│   │   ├── init.lua
│   │   ├── loader.lua            # Scenario loader
│   │   ├── trigger.lua           # Campaign trigger system
│   │   ├── team.lua              # AI teams
│   │   └── waypoints.lua         # Named locations
│   │
│   ├── ui/
│   │   ├── init.lua
│   │   ├── sidebar.lua           # Build sidebar (single-item queue)
│   │   ├── radar.lua             # Minimap (requires power + Comm Center)
│   │   ├── selection_box.lua     # Drag selection
│   │   ├── cursor.lua            # Mouse cursors
│   │   ├── messages.lua          # In-game messages
│   │   ├── power_bar.lua         # Power indicator
│   │   └── menu/
│   │       ├── main_menu.lua     # Animated globe background
│   │       ├── campaign_map.lua  # World map mission selection
│   │       ├── options.lua       # Settings (match original layout)
│   │       └── multiplayer.lua   # Lobby UI
│   │
│   ├── input/
│   │   ├── init.lua
│   │   ├── keyboard.lua          # Fully rebindable hotkeys
│   │   ├── mouse.lua
│   │   ├── controller.lua        # Virtual cursor + radial menus
│   │   └── commands.lua          # Command pattern
│   │
│   ├── audio/
│   │   ├── init.lua
│   │   ├── music.lua             # Switchable classic/remastered
│   │   ├── sfx.lua               # Switchable classic/remastered
│   │   └── speech.lua            # EVA voice
│   │
│   ├── video/
│   │   └── cutscene.lua          # Remastered video playback
│   │
│   ├── net/
│   │   ├── init.lua
│   │   ├── protocol.lua          # Message encoding
│   │   ├── lockstep.lua          # Deterministic sync
│   │   ├── lobby.lua             # Game lobby (6 players max)
│   │   └── spectator.lua         # Observer mode
│   │
│   ├── editor/
│   │   ├── init.lua
│   │   ├── terrain_brush.lua
│   │   ├── unit_placer.lua
│   │   ├── trigger_editor.lua
│   │   └── export.lua            # Save to JSON scenario
│   │
│   └── util/
│       ├── vector.lua            # 2D vector math
│       ├── direction.lua         # 8/32 direction helpers
│       ├── crc.lua               # CRC32 for sync
│       ├── random.lua            # Deterministic RNG (match original LCG)
│       └── serialize.lua         # Full state save/load
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
│   │   ├── covert_ops/           # 15 expansion missions
│   │   ├── funpark/              # Dinosaur missions
│   │   └── multiplayer/          # Skirmish maps
│   │
│   └── audio/
│       ├── themes.json
│       └── sounds.json
│
├── assets/
│   ├── sprites/
│   │   ├── classic/              # Original 320x200 sprites
│   │   │   ├── infantry/
│   │   │   ├── vehicles/
│   │   │   ├── aircraft/
│   │   │   ├── buildings/
│   │   │   ├── terrain/
│   │   │   ├── effects/
│   │   │   └── ui/
│   │   └── hd/                   # Remastered HD sprites
│   │       └── (same structure)
│   │
│   ├── audio/
│   │   ├── classic/
│   │   │   ├── music/            # .ogg converted from AUD
│   │   │   ├── sfx/
│   │   │   └── speech/
│   │   └── remastered/
│   │       └── (same structure)
│   │
│   └── video/
│       └── cutscenes/            # Remastered .mp4 files
│
├── temp/
│   └── CnC_Remastered_Collection/
│       └── TIBERIANDAWN/
│           ├── *.CPP, *.H        # Source code reference
│           └── MIX/              # Original game assets
│               ├── CD1/
│               ├── CD2/
│               └── CD3/
│
└── tools/
    ├── mix_extractor/
    │   ├── main.lua              # Standalone Lua script
    │   ├── mix_format.lua
    │   └── crc_lookup.lua
    │
    ├── sprite_converter/
    │   ├── main.lua
    │   ├── shp_parser.lua        # Classic SHP format
    │   ├── hd_parser.lua         # Remastered format
    │   ├── palette.lua
    │   └── spritesheet.lua
    │
    ├── audio_converter/
    │   ├── main.lua
    │   ├── classic_converter.lua  # AUD/VOC to OGG
    │   └── hd_extractor.lua       # Remastered audio
    │
    └── scenario_converter/
        ├── main.lua
        └── ini_parser.lua
```

---

## Implementation Phases

### Phase 1: Foundation
**Goal**: Render map, place units, move them around with save/load

**Priority Order**:
1. Asset pipeline (MIX extraction first)
2. Game systems with real assets

**Deliverables**:

1. **Asset Pipeline** - `tools/`
   - MIX extractor (from MIXFILE.H format)
   - SHP to PNG converter with palette support
   - HD asset extractor from Remastered data
   - Audio converter (classic AUD + remastered)
   - Initial JSON data files for units/buildings

2. **ECS Framework** - `src/ecs/`
   - Custom lightweight Entity, Component, System, World
   - Query system for component combinations

3. **Map System** - `src/map/`
   - 64x64 cell grid (from CELL.H)
   - Cell data: terrain, occupancy, overlay
   - All three theaters (Temperate, Winter, Desert)
   - Basic terrain rendering (classic + HD toggle)

4. **Core Components** - `src/components/`
   - Transform (with lepton coordinates)
   - Renderable, Selectable, Mobile

5. **Basic Systems** - `src/systems/`
   - RenderSystem (with HD/classic toggle)
   - SelectionSystem (configurable classic/modern presets)
   - MovementSystem (original pathfinding behavior)

6. **Settings System** - `src/ui/menu/`
   - Options menu matching original layout
   - Resolution toggle (classic/HD)
   - Audio toggle (classic/remastered)
   - Hotkey rebinding

7. **Save/Load** - `src/util/serialize.lua`
   - Full state serialization

**Acceptance Criteria**:
- All unit types moving on map
- All three theaters rendering
- Save and load working
- Classic/HD graphics toggle functional

**Key Source Reference**:
- [CELL.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/CELL.H)
- [DEFINES.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H)
- [MIXFILE.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/MIXFILE.H)

---

### Phase 2: Combat & AI
**Goal**: Units fight and respond to threats

1. **Weapons System** - `src/systems/combat_system.lua`
   - Projectile spawning and travel
   - Damage calculation with armor modifiers
   - Warhead effects (from original data)

2. **Mission System** - `src/systems/ai_system.lua`
   - MissionType enum: Guard, Attack, Move, Hunt, etc.
   - Target acquisition and threat evaluation
   - Original team-based scripted AI

3. **Pathfinding** - `src/map/pathfinding.lua`
   - A* for cell-based movement
   - Original blocking behavior (units can get stuck)
   - Multi-cell building avoidance

4. **Combat Components** - `src/components/`
   - Combat, Mission, Health with armor types

**Acceptance Criteria**:
- Units attack enemies automatically
- Units die and explode with correct animations
- AI responds to threats appropriately

**Key Source Reference**:
- [MISSION.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/MISSION.H)
- [TECHNO.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TECHNO.H)
- [BULLET.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.H)

---

### Phase 3: Economy, Production & Editor
**Goal**: Build bases, harvest Tiberium, train units, create maps

1. **Tiberium System**
   - Tiberium overlay spawning and growth (original spreading)
   - Harvester collection logic
   - Refinery processing
   - Infantry damage from Tiberium

2. **Production System** - `src/systems/production_system.lua`
   - Building placement with strict adjacency
   - Single-item build queue (original behavior)
   - Factory assignment (primary)
   - Original unit limits

3. **Power System** - `src/systems/power_system.lua`
   - Power production/consumption tracking
   - Low power penalties
   - Radar requires power + Communications Center

4. **Sidebar UI** - `src/ui/sidebar.lua`
   - Build icons with progress
   - Single-item queue display
   - Credits counter

5. **Scenario Editor** - `src/editor/`
   - Terrain placement
   - Unit/building placement
   - Trigger creation
   - Export to JSON

6. **Skirmish Mode**
   - Random/custom map selection
   - AI opponent configuration
   - Victory conditions

**Acceptance Criteria**:
- Build from MCV to full base
- Harvest Tiberium and produce units
- Create and save custom scenarios
- Play skirmish against AI

**Key Source Reference**:
- [FACTORY.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/FACTORY.H)
- [HOUSE.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/HOUSE.H)

---

### Phase 4: Multiplayer
**Goal**: Stable 2-6 player online matches with spectating

1. **Deterministic Lockstep** - `src/net/lockstep.lua`
   - Frame-synchronized command execution
   - Input delay for network latency

2. **Deterministic RNG** - `src/util/random.lua`
   - Seeded LCG matching original algorithm
   - No floats in gameplay calculations

3. **Network Protocol** - `src/net/protocol.lua`
   - Event encoding (from EVENT.H)
   - CRC sync checks per frame
   - LuaSocket TCP/UDP implementation

4. **Desync Detection**
   - State CRC comparison
   - Game ends on disconnect (no recovery)

5. **Lobby System** - `src/net/lobby.lua`
   - Host/join games
   - 6 player slots
   - Faction selection

6. **Observer Mode** - `src/net/spectator.lua`
   - Full map vision
   - Switch between player perspectives
   - Toggle fog of war view

**Acceptance Criteria**:
- Host game, join from second client
- Play synchronized match
- Spectator can watch with perspective switching

**Key Source Reference**:
- [EVENT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/EVENT.H)
- [SESSION.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/SESSION.H)

---

### Phase 5: Campaign & Scenarios
**Goal**: Full GDI + Nod + Covert Ops campaigns

1. **Trigger System** - `src/scenario/trigger.lua`
   - Event conditions (unit destroyed, time elapsed, etc.)
   - Actions (reinforcements, messages, win/lose)

2. **Team System** - `src/scenario/team.lua`
   - AI team coordination
   - No formation movement (original behavior)

3. **Scenario Loader** - `src/scenario/loader.lua`
   - Parse JSON scenario files
   - Place initial units/buildings
   - Set up triggers

4. **Mission Briefings**
   - Text display
   - Map reveal animations
   - World map mission selection (original style)

5. **All Missions**
   - 15 GDI missions
   - 13 Nod missions
   - 15 Covert Operations missions
   - Funpark/Dinosaur missions
   - Branching paths

**Acceptance Criteria**:
- Complete any campaign mission
- All triggers function correctly
- Mission branching works on world map

**Key Source Reference**:
- [TRIGGER.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TRIGGER.H)
- [TEAM.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TEAM.H)
- [SCENARIO.CPP](temp/CnC_Remastered_Collection/TIBERIANDAWN/SCENARIO.CPP)

---

### Phase 6: Polish
**Goal**: Feature complete, release quality

1. **Fog of War** - `src/systems/fog_system.lua`
   - Shroud (never seen) vs fog (previously seen)
   - Unit sight ranges

2. **Special Weapons**
   - Ion Cannon, Nuclear Strike, Airstrike
   - Original targeting UI (click sidebar, click map)

3. **Audio System** - `src/audio/`
   - Background music (classic/remastered toggle)
   - Unit responses
   - EVA announcements

4. **Cutscenes** - `src/video/cutscene.lua`
   - Remastered video playback for briefings

5. **Cloaking** - `src/systems/cloak_system.lua`
   - Stealth tank mechanics

6. **Controller Support** - `src/input/controller.lua`
   - Virtual cursor
   - Radial menus for commands
   - Full gamepad playability

7. **Main Menu** - `src/ui/menu/main_menu.lua`
   - Animated globe/map background (original style)
   - Campaign / Skirmish / Multiplayer / Options / Exit

**Acceptance Criteria**:
- Full playthrough of both campaigns
- All audio working with toggle
- Controller fully playable

---

## Critical Source Files

Reference these during implementation:

| File | Purpose |
|------|---------|
| `DEFINES.H` | All enums (units, buildings, weapons, missions), TICKS_PER_SECOND=15 |
| `TECHNO.H` | Core combat entity functionality |
| `CELL.H` | Map cell structure, lepton system |
| `EVENT.H` | Network event types for multiplayer |
| `TRIGGER.H` | Campaign trigger/scripting system |
| `MISSION.H` | AI mission types |
| `HOUSE.H` | Faction and economy |
| `SESSION.H` | Multiplayer session, MAX_PLAYERS=6 |
| `MIXFILE.H` | Asset archive format |

---

## Verification Plan

### During Development
- Run with `love .` from project root
- Use Love2D console for debugging (`io.write`, `print`)

### Per-Phase Testing
1. **Phase 1**: Render all theaters, select units, move them, save/load, toggle HD
2. **Phase 2**: Units attack enemies, die, explode correctly
3. **Phase 3**: Build from MCV, harvest, produce units, create map in editor
4. **Phase 4**: Host game, join from second client, play synchronized, spectate
5. **Phase 5**: Load GDI mission 1, complete objectives, win
6. **Phase 6**: Full playthrough of both campaigns with controller

### Multiplayer Sync Testing
- Run same inputs on two clients, compare frame-by-frame CRC

### Performance Targets
- 60 FPS at 1080p
- 500+ entities without slowdown
- No GC stutters during gameplay

---

## Asset Extraction

### Source Locations
- **Classic Assets**: `temp/CnC_Remastered_Collection/TIBERIANDAWN/MIX/CD1/`
- **Remastered Assets**: Steam install `Data/` directories

### Key MIX Files
| File | Contents |
|------|----------|
| `CONQUER.MIX` | Unit/building sprites (SHP) |
| `TEMPERAT.MIX` | Temperate theater terrain |
| `WINTER.MIX` | Winter theater terrain |
| `DESERT.MIX` | Desert theater terrain |
| `SOUNDS.MIX` | Sound effects (AUD) |
| `SPEECH.MIX` | EVA voice (AUD) |
| `SCORES.MIX` | Music tracks |
| `MOVIES.MIX` | Cutscene videos |
| `SC-000.MIX`, `SC-001.MIX` | Scenario data |

### Output Structure
- Classic sprites: `assets/sprites/classic/`
- HD sprites: `assets/sprites/hd/`
- Classic audio: `assets/audio/classic/`
- Remastered audio: `assets/audio/remastered/`
