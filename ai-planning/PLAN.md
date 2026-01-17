# Command & Conquer Tiberian Dawn - Love2D Port

## Overview

A faithful port of Command & Conquer: Tiberian Dawn to Love2D, recreating the original gameplay experience with optional HD graphics support. This port mirrors the original C++ class hierarchy to ensure behavioral accuracy and maintainability.

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

**Note**: All deviations are implemented in separate adapter modules, keeping the core game classes faithful to the original.

### Priority & Scope Decisions
| Feature | Priority | Notes |
|---------|----------|-------|
| HD Graphics | Separate pack | Optional download, classic-only works standalone |
| Controller Support | Nice-to-have | After core game functional |
| Spectator Mode | Deferred | Post-launch feature |
| Crates/Powerups | Skip | Not in original TD (Red Alert feature) |
| Veterancy | Skip | Not in original TD |

---

## Implementation Decisions

These decisions were made during spec review to ensure consistency across all phases.

### Architecture & Code Structure
| Decision | Choice | Rationale |
|----------|--------|-----------|
| OOP System | Custom metatables | No external dependencies, full control |
| Type Safety | Strict metatable enforcement | COORDINATE/CELL/TARGET types with validation |
| Pool Overflow | Hard errors | Match original behavior, fail fast |
| File Structure | Match original C++ | Files should mirror `temp/TIBERIANDAWN/` structure |
| Error Handling | Crash loudly | Assert on invalid state for easier debugging |

### Core Systems
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Combat Math | Exact integer port | Bit operations, no floats for damage |
| RNG | Verified LCG | Already validated against original |
| Multiplayer | Architect from day 1 | All systems designed for deterministic lockstep |
| Tick/Render | 15 FPS logic, 60 FPS display | Interpolation for smooth visuals |
| Radio Messages | Synchronous | Immediate call/response like original |

### Game Mechanics
| Decision | Choice | Rationale |
|----------|--------|-----------|
| AI Behavior | Exact replica | Include all quirks and exploits |
| Tiberium Growth | Full system (Phase 4) | Blossom trees, growth, spread |
| Building Placement | Full rules from start | Adjacency, foundation, terrain checks |
| Fog of War | Original TD style | Explored stays visible, units hidden |
| Fear System | Exact port | Infantry Fear value and panic behaviors |
| Building Damage | Original formula | Match C++ damage state thresholds |

### Unit Behaviors
| Decision | Choice | Rationale |
|----------|--------|-----------|
| MCV Deployment | Phase 2 | Core unit transformation mechanic |
| Aircraft RTB | Auto-return | Return to helipad when ammo depleted |
| Harvester AI | Match original | Exact replication of seek/return behavior |
| Sell/Repair | Phase 4 | Part of economy system |

### UI & Input
| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Design | Both classic + HD ready | Parallel development from start |
| Keyboard Bindings | Original exact | Match original keybindings as default |
| EVA Voice | With sidebar/HUD | Implement alongside UI development |

### Assets & Scenarios
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Asset State | Partial extraction | Tools exist, some assets ready |
| Scenario Format | Original INI/BIN | Parse original format directly |
| Superweapons | Phase 6 | Ion Cannon, Nuke, Airstrike |

### Testing & Debug
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Test Coverage | All levels | Unit, integration, replay verification |
| Debug Overlays | Build from start | Visualize pathfinding, threat, AI decisions |
| Phase 1 Goal | Map + selection + movement | Minimum viable demonstration |

---

## Architecture: C++ Class Hierarchy Port

This port replicates the original C++ class hierarchy using Lua metatables and mixins. The goal is behavioral and structural equivalence with the original source code.

### Game Object Inheritance Hierarchy

```
AbstractClass
    └── ObjectClass
            └── MissionClass
                    └── RadioClass
                            └── TechnoClass [+ Mixins: Flasher, Stage, Cargo, Door, Crew]
                                    ├── FootClass
                                    │       ├── InfantryClass
                                    │       ├── UnitClass (via TarComClass/DriveClass)
                                    │       └── AircraftClass (via FlyClass)
                                    └── BuildingClass
```

### Type Class Hierarchy (Static Data)

```
AbstractTypeClass
    └── ObjectTypeClass
            └── TechnoTypeClass
                    ├── InfantryTypeClass
                    ├── UnitTypeClass
                    ├── AircraftTypeClass
                    └── BuildingTypeClass
```

### Additional Object Hierarchies

```
ObjectClass
    ├── BulletClass
    ├── AnimClass
    ├── TerrainClass
    ├── OverlayClass
    └── SmudgeClass
```

### Display/View Hierarchy

```
GScreenClass
    └── MapClass
            └── DisplayClass
                    └── RadarClass
                            └── ScrollClass
                                    └── MouseClass
```

### Mixin Classes (Multiple Inheritance Emulation)

TechnoClass incorporates behavior from:
- **FlasherClass**: Damage flash visual effect
- **StageClass**: Animation frame staging
- **CargoClass**: Unit transport/passenger management
- **DoorClass**: Building door animation state
- **CrewClass**: Crew/survivor generation

---

## Naming Conventions

- **Files/directories**: Match C++ naming in lowercase (e.g., `techno.lua`, `infantry.lua`)
- **Class tables**: `PascalCase` matching C++ names (e.g., `TechnoClass`, `InfantryClass`)
- **Methods**: Exact C++ signatures (e.g., `AI()`, `Take_Damage()`, `Can_Fire()`)
- **Fields**: Match C++ names with boolean prefix for flags (e.g., `IsDown`, `IsTethered`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `CELL_SIZE`, `TICKS_PER_SECOND`)

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

### Data Encoding (Match Original)
- **COORDINATE**: 32-bit packed (cell + lepton offset)
- **CELL**: 16-bit packed (x << 8 | y for 64x64 map)
- **TARGET**: Packed type (RTTI) + heap index
- **Direction**: 0-255 (256 directions, 8 cardinal)

### Object Pools (Match Original Limits)
| Type | Pool Size |
|------|-----------|
| Infantry | 500 |
| Units | 500 |
| Buildings | 500 |
| Aircraft | 100 |
| Bullets | 50 |
| Anims | 100 |
| Teams | 50 |
| Triggers | 100 |

### Networking
- **Transport**: LuaSocket (TCP/UDP)
- **Protocol**: Deterministic lockstep
- **Max Players**: 6 (original limit)
- **Disconnect Handling**: Game ends immediately
- **Event System**: Port of EventClass with all EventType variants

### Random Number Generator
- **Algorithm**: Exact LCG port from original
- **Usage**: All gameplay randomness uses seeded deterministic RNG
- **Sync**: RNG state included in frame CRC for desync detection

### Save/Load System
- **Pattern**: Port Code_Pointers()/Decode_Pointers() system
- **Format**: Convert object references to heap indices for serialization
- **Compatibility**: Save format allows cross-platform loading

---

## Project Structure

```
Love2D-CommandAndConquer-TiberianDawn/
├── main.lua
├── conf.lua
│
├── src/
│   ├── objects/                    # Game object class hierarchy
│   │   ├── abstract.lua            # AbstractClass - base coordinate/active state
│   │   ├── object.lua              # ObjectClass - map presence, health, targeting
│   │   ├── mission.lua             # MissionClass - AI mission state machine
│   │   ├── radio.lua               # RadioClass - inter-object communication
│   │   ├── techno.lua              # TechnoClass - combat entities
│   │   ├── foot.lua                # FootClass - mobile units base
│   │   ├── infantry.lua            # InfantryClass - infantry units
│   │   ├── unit.lua                # UnitClass - vehicles
│   │   ├── aircraft.lua            # AircraftClass - air units
│   │   ├── building.lua            # BuildingClass - structures
│   │   ├── bullet.lua              # BulletClass - projectiles
│   │   ├── anim.lua                # AnimClass - visual effects
│   │   ├── terrain.lua             # TerrainClass - trees, rocks
│   │   ├── overlay.lua             # OverlayClass - tiberium, walls
│   │   ├── smudge.lua              # SmudgeClass - craters, scorch marks
│   │   │
│   │   ├── mixins/                 # Multiple inheritance components
│   │   │   ├── flasher.lua         # FlasherClass - damage flash
│   │   │   ├── stage.lua           # StageClass - animation staging
│   │   │   ├── cargo.lua           # CargoClass - transport cargo
│   │   │   ├── door.lua            # DoorClass - building doors
│   │   │   └── crew.lua            # CrewClass - survivor generation
│   │   │
│   │   └── drive/                  # Movement specializations
│   │       ├── drive.lua           # DriveClass - ground vehicle movement
│   │       ├── fly.lua             # FlyClass - aircraft movement
│   │       └── tarcom.lua          # TarComClass - turret targeting
│   │
│   ├── types/                      # Type classes (static data)
│   │   ├── abstract_type.lua       # AbstractTypeClass
│   │   ├── object_type.lua         # ObjectTypeClass
│   │   ├── techno_type.lua         # TechnoTypeClass
│   │   ├── infantry_type.lua       # InfantryTypeClass
│   │   ├── unit_type.lua           # UnitTypeClass
│   │   ├── aircraft_type.lua       # AircraftTypeClass
│   │   ├── building_type.lua       # BuildingTypeClass
│   │   ├── bullet_type.lua         # BulletTypeClass
│   │   ├── anim_type.lua           # AnimTypeClass
│   │   ├── terrain_type.lua        # TerrainTypeClass
│   │   └── overlay_type.lua        # OverlayTypeClass
│   │
│   ├── map/                        # Map and cell system
│   │   ├── cell.lua                # CellClass - individual map cells
│   │   ├── map.lua                 # MapClass - cell grid management
│   │   ├── layer.lua               # LayerClass - render layer sorting
│   │   └── theater.lua             # Theater terrain sets
│   │
│   ├── display/                    # Display hierarchy
│   │   ├── gscreen.lua             # GScreenClass - base screen
│   │   ├── display.lua             # DisplayClass - tactical view
│   │   ├── radar.lua               # RadarClass - minimap
│   │   ├── scroll.lua              # ScrollClass - map scrolling
│   │   └── mouse.lua               # MouseClass - cursor handling
│   │
│   ├── house/                      # Faction management
│   │   ├── house.lua               # HouseClass - full field set
│   │   └── house_type.lua          # HouseTypeClass
│   │
│   ├── production/                 # Production system
│   │   └── factory.lua             # FactoryClass - build queue management
│   │
│   ├── scenario/                   # Campaign/scenario system
│   │   ├── trigger.lua             # TriggerClass - event triggers
│   │   ├── team.lua                # TeamClass - AI team instances
│   │   ├── team_type.lua           # TeamTypeClass - team definitions
│   │   └── scenario.lua            # Scenario loading/management
│   │
│   ├── combat/                     # Combat calculations
│   │   ├── weapon.lua              # WeaponTypeClass
│   │   ├── warhead.lua             # WarheadTypeClass
│   │   └── armor.lua               # ArmorType handling
│   │
│   ├── pathfinding/                # Movement pathfinding
│   │   └── findpath.lua            # Port of FINDPATH.CPP algorithm
│   │
│   ├── network/                    # Multiplayer networking
│   │   ├── event.lua               # EventClass - network events
│   │   ├── queue.lua               # Command queue
│   │   ├── lockstep.lua            # Deterministic lockstep
│   │   └── session.lua             # SessionClass - game session
│   │
│   ├── heap/                       # Object pool management
│   │   ├── heap.lua                # HeapClass - object allocation
│   │   └── globals.lua             # Global object arrays
│   │
│   ├── core/                       # Core utilities
│   │   ├── init.lua
│   │   ├── game.lua                # Main game loop (per-object AI)
│   │   ├── constants.lua           # All game constants
│   │   ├── coord.lua               # COORDINATE/CELL macros
│   │   ├── target.lua              # TARGET encoding/decoding
│   │   ├── random.lua              # Exact LCG RNG port
│   │   └── defines.lua             # Enum definitions from DEFINES.H
│   │
│   ├── io/                         # Save/Load system
│   │   ├── save.lua                # Save game handling
│   │   ├── load.lua                # Load game handling
│   │   └── pointers.lua            # Code_Pointers/Decode_Pointers
│   │
│   ├── adapters/                   # Deviation adapters (separate from core)
│   │   ├── hd_graphics.lua         # HD sprite rendering adapter
│   │   ├── controller.lua          # Controller input adapter
│   │   ├── spectator.lua           # Observer mode adapter
│   │   ├── hotkeys.lua             # Rebindable hotkey adapter
│   │   └── remastered_audio.lua    # Remastered audio adapter
│   │
│   ├── ui/                         # User interface
│   │   ├── sidebar.lua             # Build sidebar
│   │   ├── power_bar.lua           # Power indicator
│   │   ├── messages.lua            # In-game messages
│   │   ├── cursor.lua              # Mouse cursors
│   │   └── menu/
│   │       ├── main_menu.lua
│   │       ├── campaign_map.lua
│   │       ├── options.lua
│   │       └── multiplayer.lua
│   │
│   ├── debug/                      # Debug support
│   │   ├── dump.lua                # Debug_Dump() implementations
│   │   ├── mono.lua                # MonoClass equivalent
│   │   └── ipc.lua                 # IPC debugging system
│   │
│   ├── video/
│   │   └── cutscene.lua
│   │
│   └── util/
│       ├── vector.lua
│       ├── direction.lua
│       ├── crc.lua
│       └── serialize.lua
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
│   │   ├── gdi/
│   │   ├── nod/
│   │   ├── covert_ops/
│   │   ├── funpark/
│   │   └── multiplayer/
│   │
│   └── audio/
│       ├── themes.json
│       └── sounds.json
│
├── assets/
│   ├── sprites/
│   │   ├── classic/
│   │   └── hd/
│   │
│   ├── audio/
│   │   ├── classic/
│   │   └── remastered/
│   │
│   └── video/
│       └── cutscenes/
│
├── temp/
│   └── CnC_Remastered_Collection/
│       └── TIBERIANDAWN/
│
└── tools/
    ├── mix_extractor/
    ├── sprite_converter/
    ├── audio_converter/
    └── scenario_converter/
```

---

## C++ to Lua Source File Mapping

| Original C++ File | Lua File | Description |
|-------------------|----------|-------------|
| ABSTRACT.H/CPP | src/objects/abstract.lua | Base class with Coord, IsActive |
| OBJECT.H/CPP | src/objects/object.lua | Map object with health, selection |
| MISSION.H/CPP | src/objects/mission.lua | Mission state machine |
| RADIO.H/CPP | src/objects/radio.lua | Inter-object communication |
| TECHNO.H/CPP | src/objects/techno.lua | Combat entity base |
| FOOT.H/CPP | src/objects/foot.lua | Mobile unit base |
| INFANTRY.H/CPP | src/objects/infantry.lua | Infantry units |
| UNIT.H/CPP | src/objects/unit.lua | Vehicle units |
| AIRCRAFT.H/CPP | src/objects/aircraft.lua | Air units |
| BUILDING.H/CPP | src/objects/building.lua | Structures |
| BULLET.H/CPP | src/objects/bullet.lua | Projectiles |
| ANIM.H/CPP | src/objects/anim.lua | Animations |
| TERRAIN.H/CPP | src/objects/terrain.lua | Terrain objects |
| OVERLAY.H/CPP | src/objects/overlay.lua | Overlays (tiberium, walls) |
| SMUDGE.H/CPP | src/objects/smudge.lua | Smudges (craters) |
| FLASHER.H/CPP | src/objects/mixins/flasher.lua | Damage flash mixin |
| STAGE.H/CPP | src/objects/mixins/stage.lua | Animation stage mixin |
| CARGO.H/CPP | src/objects/mixins/cargo.lua | Cargo management mixin |
| DOOR.H/CPP | src/objects/mixins/door.lua | Door animation mixin |
| CREW.H/CPP | src/objects/mixins/crew.lua | Crew generation mixin |
| DRIVE.H/CPP | src/objects/drive/drive.lua | Ground movement |
| FLY.H/CPP | src/objects/drive/fly.lua | Air movement |
| TARCOM.H/CPP | src/objects/drive/tarcom.lua | Turret targeting |
| CELL.H/CPP | src/map/cell.lua | Map cell |
| MAP.H/CPP | src/map/map.lua | Map grid |
| LAYER.H/CPP | src/map/layer.lua | Render layers |
| GSCREEN.H/CPP | src/display/gscreen.lua | Base screen |
| DISPLAY.H/CPP | src/display/display.lua | Tactical display |
| RADAR.H/CPP | src/display/radar.lua | Minimap |
| SCROLL.H/CPP | src/display/scroll.lua | Map scrolling |
| MOUSE.H/CPP | src/display/mouse.lua | Cursor handling |
| HOUSE.H/CPP | src/house/house.lua | Faction management |
| FACTORY.H/CPP | src/production/factory.lua | Production queue |
| TRIGGER.H/CPP | src/scenario/trigger.lua | Event triggers |
| TEAM.H/CPP | src/scenario/team.lua | AI teams |
| EVENT.H/CPP | src/network/event.lua | Network events |
| FINDPATH.CPP | src/pathfinding/findpath.lua | Pathfinding algorithm |
| HEAP.H/CPP | src/heap/heap.lua | Object pools |
| DEFINES.H | src/core/defines.lua | Enums and constants |
| COORD.CPP | src/core/coord.lua | Coordinate functions |
| TARGET.H | src/core/target.lua | Target encoding |

---

## Implementation Phases

### Phase 1: Base Classes & Infrastructure
**Goal**: Establish class hierarchy foundation and map system

**Deliverables**:

1. **Class System Infrastructure**
   - Lua OOP base with metatables
   - Mixin composition system
   - HeapClass object pool implementation

2. **Base Class Chain** - `src/objects/`
   - `AbstractClass` with Coord, IsActive, IsRecentlyCreated
   - `ObjectClass` with IsDown, IsInLimbo, IsSelected, Strength, Next, Trigger
   - `MissionClass` with Mission, SuspendedMission, MissionQueue, Timer
   - `RadioClass` with Radio contact, LastMessage, Transmit_Message(), Receive_Message()

3. **Core Utilities** - `src/core/`
   - COORDINATE/CELL bit-packing (coord.lua)
   - TARGET encoding/decoding (target.lua)
   - Exact LCG random number generator (random.lua)
   - All enums from DEFINES.H (defines.lua)

4. **Map System** - `src/map/`
   - CellClass with terrain, occupancy, overlay, objects list
   - MapClass with 64x64 grid, cell access
   - LayerClass with GROUND, AIR, TOP layers and Sort_Y() ordering
   - Theater support (Temperate, Winter, Desert)

5. **Display Hierarchy** - `src/display/`
   - GScreenClass base
   - MapClass tactical view
   - DisplayClass rendering
   - Basic scrolling

**Key Methods to Implement**:
```lua
-- AbstractClass
AbstractClass:AI()
AbstractClass:Center_Coord()
AbstractClass:Target_Coord()
AbstractClass:Distance(target)
AbstractClass:Direction(target)

-- ObjectClass
ObjectClass:Limbo()
ObjectClass:Unlimbo(coord, facing)
ObjectClass:Mark(mark_type)
ObjectClass:Render(forced)
ObjectClass:Take_Damage(damage, distance, warhead, source)
ObjectClass:Select()
ObjectClass:What_Action(object)
ObjectClass:What_Action(cell)

-- MissionClass
MissionClass:Assign_Mission(mission)
MissionClass:Get_Mission()
MissionClass:Commence()
MissionClass:Override_Mission(mission, tarcom, navcom)
MissionClass:Restore_Mission()
MissionClass:Mission_Sleep()
MissionClass:Mission_Guard()
MissionClass:Mission_Attack()
-- ... all Mission_X() functions

-- RadioClass
RadioClass:Transmit_Message(message, param, to)
RadioClass:Receive_Message(from, message, param)
RadioClass:In_Radio_Contact()
RadioClass:Contact_With_Whom()
```

**Acceptance Criteria**:
- Class inheritance chain working with metatables
- HeapClass pools allocating/deallocating objects
- Map renders with cells and layers
- Basic object placement on map
- Save/load with Code_Pointers/Decode_Pointers

**Source Reference**:
- [ABSTRACT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/ABSTRACT.H)
- [OBJECT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/OBJECT.H)
- [MISSION.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/MISSION.H)
- [RADIO.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/RADIO.H)
- [CELL.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/CELL.H)

---

### Phase 2: TechnoClass & Game Objects
**Goal**: Implement combat-capable game objects

**Deliverables**:

1. **Mixin Classes** - `src/objects/mixins/`
   - FlasherClass (damage flash timing)
   - StageClass (animation frame management)
   - CargoClass (passenger/cargo list)
   - DoorClass (door open/close state)
   - CrewClass (survivor type generation)

2. **TechnoClass** - Combat entity base
   - All flags: IsCloakable, IsLeader, IsALoaner, IsTethered, etc.
   - House ownership
   - Cloak state management
   - TarCom (target computer)
   - PrimaryFacing
   - Arm (rearm countdown)
   - Ammo tracking
   - Mixin composition

3. **FootClass** - Mobile units
   - NavCom (navigation target)
   - Path[] array for pathfinding
   - PathDelay timer
   - Team membership
   - Group assignment (1-9)
   - Movement flags: IsInitiated, IsDriving, IsRotating

4. **Movement Specializations** - `src/objects/drive/`
   - DriveClass for ground vehicles
   - FlyClass for aircraft
   - TarComClass for turret-equipped units

5. **Concrete Classes**
   - InfantryClass with Fear, Doing (DoType), prone state
   - UnitClass with harvester support, door animations
   - AircraftClass with flight altitude, landing
   - BuildingClass with Factory pointer, power, production

6. **Type Classes** - `src/types/`
   - TechnoTypeClass with all static data
   - InfantryTypeClass, UnitTypeClass, AircraftTypeClass, BuildingTypeClass
   - Load data from JSON files

**Key Methods to Implement**:
```lua
-- TechnoClass
TechnoClass:AI()
TechnoClass:Fire_At(target, which)
TechnoClass:Can_Fire(target, which)
TechnoClass:Assign_Target(target)
TechnoClass:In_Range(target, which)
TechnoClass:Take_Damage(damage, distance, warhead, source)
TechnoClass:Captured(newowner)
TechnoClass:Greatest_Threat(threat)
TechnoClass:Do_Cloak()
TechnoClass:Do_Uncloak()
TechnoClass:Revealed(house)
TechnoClass:Player_Assign_Mission(order, target, destination)

-- FootClass
FootClass:Assign_Destination(target)
FootClass:Start_Driver(coord)
FootClass:Stop_Driver()
FootClass:Mission_Move()
FootClass:Mission_Attack()
FootClass:Mission_Guard()
FootClass:Mission_Hunt()

-- InfantryClass
InfantryClass:Do_Action(todo, force)
InfantryClass:Set_Occupy_Bit(cell, spot)
InfantryClass:Clear_Occupy_Bit(cell, spot)
InfantryClass:Made_A_Kill()

-- BuildingClass
BuildingClass:Grand_Opening(captured)
BuildingClass:Update_Buildables()
BuildingClass:Toggle_Primary()
BuildingClass:Begin_Mode(bstate)
```

**Acceptance Criteria**:
- Infantry, Units, Buildings placeable on map
- Basic movement working
- Selection and group assignment
- Unit facing and animation
- Building production icons visible

**Source Reference**:
- [TECHNO.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TECHNO.H)
- [FOOT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/FOOT.H)
- [INFANTRY.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/INFANTRY.H)
- [UNIT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/UNIT.H)
- [BUILDING.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/BUILDING.H)

---

### Phase 3: Combat Systems
**Goal**: Implement weapons, damage, and projectiles

**Deliverables**:

1. **BulletClass** - `src/objects/bullet.lua`
   - Projectile movement and tracking
   - Warhead effects on impact
   - Fuse timing

2. **AnimClass** - `src/objects/anim.lua`
   - Explosion animations
   - Muzzle flash
   - Death animations

3. **Weapon System** - `src/combat/`
   - WeaponTypeClass with range, damage, ROF
   - WarheadTypeClass with armor modifiers, spread
   - Armor type handling

4. **Combat Integration**
   - Fire_At() projectile spawning
   - Take_Damage() with armor calculations
   - Death handling and debris
   - Record_The_Kill() for scoring

5. **Pathfinding** - `src/pathfinding/findpath.lua`
   - Port of FINDPATH.CPP algorithm
   - PathType struct equivalent
   - Follow_Edge() edge-following
   - Register_Cell() path recording
   - Threat evaluation

**Key Methods**:
```lua
-- BulletClass
BulletClass:AI()
BulletClass:Unlimbo(coord, facing)

-- Combat
TechnoClass:Rearm_Delay(second)
TechnoClass:Weapon_Range(which)
FootClass:Approach_Target()
```

**Acceptance Criteria**:
- Units fire at enemies
- Projectiles travel and impact
- Damage calculations match original
- Death animations play
- Pathfinding navigates around obstacles

**Source Reference**:
- [BULLET.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/BULLET.H)
- [ANIM.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/ANIM.H)
- [COMBAT.CPP](temp/CnC_Remastered_Collection/TIBERIANDAWN/COMBAT.CPP)
- [FINDPATH.CPP](temp/CnC_Remastered_Collection/TIBERIANDAWN/FINDPATH.CPP)

---

### Phase 4: Economy & Production
**Goal**: Build bases, harvest Tiberium, produce units

**Deliverables**:

1. **HouseClass** - `src/house/house.lua`
   - All fields: ActLike, Allies, Power, Drain, Credits, Capacity
   - Tiberium tracking
   - BuildStructure/BuildUnit/BuildInfantry/BuildAircraft
   - Tech tree prerequisites

2. **FactoryClass** - `src/production/factory.lua`
   - Build queue management
   - Set(), Start(), Suspend(), Abandon()
   - Completed() callback
   - Progress tracking

3. **Tiberium System**
   - OverlayClass for tiberium fields
   - Harvester collection logic (Mission_Harvest)
   - Refinery processing
   - Tiberium growth/spread

4. **Power System**
   - Power production/consumption per building
   - Low power penalties
   - Power bar UI

5. **Construction**
   - Building placement with adjacency
   - MCV deployment
   - Factory assignment (primary)

**Acceptance Criteria**:
- MCV deploys to Construction Yard
- Buildings produce when placed
- Harvesters collect and return tiberium
- Credits increase from harvesting
- Power affects building function

**Source Reference**:
- [HOUSE.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/HOUSE.H)
- [FACTORY.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/FACTORY.H)

---

### Phase 5: AI, Triggers & Teams
**Goal**: Campaign AI and scripting

**Deliverables**:

1. **TriggerClass** - `src/scenario/trigger.lua`
   - Event types (destroyed, time, discovered, etc.)
   - Action types (reinforcement, win, lose, etc.)
   - Persistence flags
   - House association

2. **TeamClass** - `src/scenario/team.lua`
   - Team member management
   - Formation (none - original behavior)
   - Team missions
   - Waypoint following

3. **TeamTypeClass** - `src/scenario/team_type.lua`
   - Team composition definitions
   - Mission queue

4. **AI Controller**
   - Base building AI
   - Attack coordination
   - Threat evaluation

5. **Scenario System**
   - Scenario loading
   - Mission briefings
   - Victory/defeat conditions

**Acceptance Criteria**:
- Campaign missions load with triggers
- AI builds bases and attacks
- Triggers fire correctly
- Teams coordinate movement

**Source Reference**:
- [TRIGGER.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TRIGGER.H)
- [TEAM.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/TEAM.H)

---

### Phase 6: Network & Polish
**Goal**: Multiplayer and feature completion

**Deliverables**:

1. **EventClass** - `src/network/event.lua`
   - All EventType variants from original
   - Event encoding/decoding
   - Timestamp handling

2. **Lockstep System** - `src/network/lockstep.lua`
   - Frame-synchronized execution
   - Input delay
   - CRC sync checking

3. **Session Management**
   - Lobby system
   - Player slots
   - Game start synchronization

4. **Special Weapons**
   - Ion Cannon
   - Nuclear Strike
   - Airstrike

5. **Fog of War**
   - Shroud (never seen)
   - Fog (previously seen)
   - Sight range per unit type

6. **Cloaking**
   - Stealth tank mechanics
   - Detection logic

7. **Adapter Modules** - `src/adapters/`
   - HD graphics rendering
   - Controller support
   - Spectator mode
   - Rebindable hotkeys
   - Remastered audio

8. **Debug Support**
   - Debug_Dump() for all classes
   - MonoClass equivalent logging
   - Cheat commands

**Acceptance Criteria**:
- Two clients play synchronized match
- Replay files produce identical results
- All special weapons functional
- Controller fully playable

**Source Reference**:
- [EVENT.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/EVENT.H)
- [SESSION.H](temp/CnC_Remastered_Collection/TIBERIANDAWN/SESSION.H)

---

## Verification Plan

### Replay Compatibility Testing
The primary acceptance criterion is **replay compatibility**: given identical inputs and initial random seed, the game should produce identical game states frame-by-frame.

**Testing Method**:
1. Record input sequences with timestamps
2. Run replay on both implementations
3. Compare frame CRCs at each game tick
4. Any CRC mismatch indicates behavioral divergence

### Debug Functions
All classes implement `Debug_Dump()` for state inspection:
```lua
function TechnoClass:Debug_Dump()
    print(string.format("TechnoClass: House=%s TarCom=%s Mission=%s",
        self.House and self.House:Get_Name() or "none",
        Target_As_String(self.TarCom),
        Mission_Name(self.Mission)))
    -- Call parent
    RadioClass.Debug_Dump(self)
end
```

### Per-Phase Testing

| Phase | Test |
|-------|------|
| 1 | Object creation, map rendering, save/load cycle |
| 2 | Unit placement, selection, basic movement |
| 3 | Combat engagement, damage values match original |
| 4 | Full base build, harvest cycle, unit production |
| 5 | Campaign mission 1 completable, triggers fire |
| 6 | 2-player sync match, replay verification |

### Performance Targets
- 60 FPS at 1080p
- 500+ entities without slowdown
- No GC stutters during gameplay (use object pools)

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

---

## Migration Notes

### Removing Legacy ECS Implementation
The legacy ECS implementation must be **deleted immediately** (not deprecated). Remove these directories entirely:

**Directories to Delete:**
- `src/ecs/` - Entire directory (entity.lua, component.lua, system.lua, world.lua, init.lua)
- `src/components/` - Entire directory (all ECS component definitions)
- `src/systems/` - Entire directory (all ECS system implementations)

**Criterion for Removal:**
Any file that does not match the original C++ source structure in `temp/TIBERIANDAWN/` should be evaluated for removal or refactoring.

### Preserved Functionality
These modules are architecture-agnostic and should be preserved:
- `src/debug/ipc.lua` - IPC debugging system (adapt for class hierarchy if needed)
- `src/util/` - Utility modules (paths, vector, direction, crc, serialize)
- `src/graphics/sprite_loader.lua` - Asset loading infrastructure
- `src/map/theater.lua` - Theater terrain sets (adapt for CellClass)

---

## Critical Source Files Reference

The original game source code is located at: `temp/CnC_Remastered_Collection/TIBERIANDAWN/`
(Use `Paths.cnc_source("FILENAME.H")` in Lua code - see [Git Worktree Support](#git-worktree-support))

| File | Purpose |
|------|---------|
| `DEFINES.H` | All enums (units, buildings, weapons, missions), TICKS_PER_SECOND=15 |
| `TECHNO.H` | Core combat entity functionality |
| `CELL.H` | Map cell structure, lepton system (256 leptons per cell) |
| `EVENT.H` | Network event types for multiplayer |
| `TRIGGER.H` | Campaign trigger/scripting system |
| `MISSION.H` | AI mission types |
| `HOUSE.H` | Faction and economy |
| `FACTORY.H` | Production system |
| `BULLET.H` | Projectile system |
| `SESSION.H` | Multiplayer session, MAX_PLAYERS=6 |
| `MIXFILE.H` | Asset archive format |
| `FINDPATH.CPP` | Pathfinding algorithm |
| `COMBAT.CPP` | Damage calculations |

---

## Development Workflow

1. Run the game: `love .` or `lovec .` (console version for stdout)
2. Use IPC system for testing - see `.claude/skills/interact-ipc/SKILL.md`
3. Reference original C++ source in `./temp/` for accurate behavior

---

## Current Status

### Implemented
- Class hierarchy foundation (AbstractClass → ObjectClass → MissionClass → RadioClass → TechnoClass)
- All game object classes scaffolded (Infantry, Unit, Aircraft, Building, Bullet, Anim, Terrain, Overlay, Smudge)
- Mixin system for multiple inheritance (Flasher, Stage, Cargo, Door, Crew)
- Movement specializations (Drive, Fly, TarCom, Turret)
- All type classes defined (InfantryTypeClass, UnitTypeClass, etc.)
- Map grid and cell system
- Core utilities (coord, target, random, constants)
- IPC debugging system for CLI control
- Custom metatable OOP system (`src/objects/class.lua`)

### Needs Migration/Removal
- Legacy ECS framework (`src/ecs/`, `src/components/`, `src/systems/`) - DELETE
- Game loop currently ECS-based - REFACTOR to class hierarchy
- Any files not matching original C++ structure - EVALUATE

### Needs Implementation
- Game loop integration with class AI() methods
- HeapClass object pool management
- Full method implementations in class stubs
- Radio message protocol between objects
- Save/load with Code_Pointers/Decode_Pointers

---

## Testing with IPC

The game has an IPC system for automated testing:
```bash
# Start game (use lovec for console output)
lovec .

# Look for IPC_ID=<timestamp> in output
# Send commands via files:
echo "state" > /tmp/love2d_ipc_<id>/command.txt
cat /tmp/love2d_ipc_<id>/response.json

# Commands: state, input <key>, screenshot, pause, resume, quit
```

---

## Git Worktree Support

The codebase supports running from git worktrees (`.worktrees/{branch}/`). Large directories are stored in the main repository and shared across all worktrees.

### Shared Directories (not duplicated in worktrees)
- `assets/` - Game assets (sprites, audio, video)
- `temp/` - Original C++ source reference (CnC_Remastered_Collection)

### How It Works
- **Main repo**: Shared dirs at `./assets/` and `./temp/`
- **Worktrees**: Shared dirs at `../../assets/` and `../../temp/` (relative to worktree root)

The `src/util/paths.lua` module handles this automatically:
- Detects if running from a worktree by checking `love.filesystem.getSource()`
- Mounts the parent repo's `assets/` and `temp/` directories if in a worktree
- Provides helper functions for resolving paths

### Paths Module Usage
All asset and reference file loading should use the `Paths` module:
```lua
local Paths = require("src.util.paths")

-- Asset paths
Paths.asset("sprites/infantry/e1.png")  -- Full asset path
Paths.sprite("infantry/e1.png")         -- Sprite-specific
Paths.audio("sfx/gunfire.ogg")          -- Audio-specific
Paths.sound("explosion.wav")            -- Legacy sounds folder
Paths.music("act_on_instinct.ogg")      -- Music-specific
Paths.video("cutscenes/intro.ogv")      -- Video-specific

-- Reference source paths
Paths.temp("CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H")  -- Full temp path
Paths.cnc_source("DEFINES.H")           -- Shortcut to TIBERIANDAWN source

-- Debug info
Paths.is_worktree()        -- Returns true if in a worktree
Paths.get_main_repo_path() -- Returns main repo path (nil if not worktree)
Paths.get_info()           -- Returns diagnostic info table
```

### Files Using Paths Module
- `src/graphics/sprite_loader.lua` - Sprite sheet loading
- `src/systems/audio_system.lua` - Sound effects and music
- `src/video/cutscene.lua` - Video playback
- `src/map/theater.lua` - Theater-specific terrain assets
