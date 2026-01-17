# Task Progress

This document tracks all implementation tasks for the Command & Conquer: Tiberian Dawn Love2D port.

**Legend:**
- `[ ]` Ready - Task not started
- `[~]` In Progress - Currently being worked on
- `[x]` Completed - Task finished
- `[!]` Blocked - Waiting on dependency

---

## Phase 0: Migration & Cleanup

### Legacy Code Removal
- [x] Delete `src/ecs/` directory entirely
- [x] Delete `src/components/` directory entirely (already removed)
- [x] Delete `src/systems/` directory entirely
- [ ] Audit remaining files against original C++ structure
- [ ] Remove any orphaned files not matching original structure
- [x] Update `main.lua` to remove ECS requires (already clean)
- [x] Update `src/core/game.lua` to remove ECS dependencies (compatibility shims created)

### File Structure Alignment
- [ ] Compare `src/` structure against `temp/TIBERIANDAWN/` structure
- [ ] Rename files to match C++ naming (lowercase)
- [ ] Move misplaced files to correct directories
- [ ] Create missing directories from PLAN.md structure
- [ ] Verify all type classes are in `src/objects/types/` (not `src/types/`)

---

## Phase 1: Base Classes & Infrastructure

### Class System Infrastructure
- [x] Verify `src/objects/class.lua` OOP system correctness (85 tests pass)
- [ ] Add strict type checking to class system
- [ ] Implement `Class.assert_type()` for type validation
- [ ] Add debug mode type checking toggle
- [x] Write unit tests for class inheritance (test_class_oop.lua)
- [x] Write unit tests for mixin composition (test_class_oop.lua)
- [x] Write unit tests for super() calls (test_class_oop.lua)

### HeapClass Object Pools (`src/heap/`) - COMPLETE
- [x] Implement `HeapClass` with fixed-size pools (heap.lua)
- [x] Implement pool allocation with hard error on exhaustion
- [x] Implement pool deallocation (return to pool)
- [x] Implement heap index tracking for objects
- [x] Implement `Active_Ptr()` - get object by heap index (Get())
- [x] Implement pool iteration (`For_Each()`) (Active_Objects())
- [x] Define pool limits for all object types (LIMITS table)
- [x] Implement `globals.lua` with global object arrays
- [x] Implement `Init_All_Heaps()` in globals.lua
- [x] Initialize heaps in Game:init()
- [x] Add RTTI to all game object classes (Infantry, Unit, Building, Aircraft, Bullet, Anim)
- [x] Write unit tests for HeapClass (test_class_hierarchy.lua, test_heaps.lua)

### COORDINATE System (`src/core/coord.lua`) - COMPLETE
- [x] Implement COORDINATE bit-packing (32-bit with cell + lepton)
- [x] Implement `Coord_Cell()` - extract cell from coordinate
- [x] Implement `Coord_XLepton()` / `Coord_YLepton()` - extract lepton offset
- [x] Implement `Coord_X()` / `Coord_Y()` - get full lepton position
- [x] Implement `XY_Coord()` - create from lepton X/Y
- [x] Implement `Cell_Coord()` - convert cell to coordinate (center)
- [x] Implement `Coord_Move()` / `Coord_Move_Dir()` / `Coord_Move_Toward()`
- [x] Implement `Distance()` - lepton distance (original C&C approximation)
- [x] Implement `Direction256()` / `Direction8()` - facing calculation
- [x] Implement pixel conversion utilities
- [x] Write unit tests (test_class_hierarchy.lua)

### CELL System (`src/core/coord.lua`) - COMPLETE
- [x] Implement CELL bit-packing (16-bit: y << 6 | x)
- [x] Implement `Cell_X()` / `Cell_Y()` - extract components
- [x] Implement `XY_Cell()` - create from X/Y
- [x] Implement `Adjacent_Cell()` - get neighbor cell by facing
- [x] Implement `Cell_Distance()` - Chebyshev distance
- [x] Implement `Cell_Is_Valid()` - bounds checking (0-63)
- [x] Write unit tests (test_class_hierarchy.lua)

### TARGET System (`src/core/target.lua`) - COMPLETE
- [x] Implement TARGET bit-packing (RTTI + ID + valid flag)
- [x] Implement `Build()` - create from RTTI + index
- [x] Implement `Get_RTTI()` - extract RTTI type
- [x] Implement `Get_ID()` - extract heap index
- [x] Implement `As_Target()` - convert object to TARGET
- [x] Implement `As_Cell()` / `As_Coord()` - cell/coord targets
- [x] Implement `As_Coordinate()` - convert TARGET to coordinate
- [x] Implement `Is_Valid()` - validate target
- [x] Implement `TARGET_NONE` constant
- [x] Implement RTTI enum (RTTI.INFANTRY, RTTI.UNIT, etc.)
- [x] Write unit tests (test_class_hierarchy.lua)

### Random Number Generator (`src/core/random.lua`) - COMPLETE
- [x] LCG implementation matches original
- [x] Implement `Random()` - get next random value
- [x] Implement `Random(min, max)` - bounded random
- [x] Implement seed getter/setter
- [x] Implement RNG state save/restore
Note: Validation tests against original sequences deferred

### Constants & Defines (`src/core/constants.lua`) - MOSTLY COMPLETE
- [x] Implement `MissionType` enum (MISSION.SLEEP, MISSION.ATTACK, etc.)
- [x] Implement `ActionType` enum (ACTION.MOVE, ACTION.ATTACK, etc.)
- [x] Implement `HousesType` enum (HOUSE.GOOD=GDI, HOUSE.BAD=NOD, etc.)
- [x] Implement `TheaterType` enum (THEATER.TEMPERATE, DESERT, WINTER)
- [x] Implement `LayerType` enum (LAYER.GROUND, AIR, TOP)
- [x] Implement `CloakType` enum (CLOAK.UNCLOAKED, CLOAKING, etc.)
- [x] Implement `FireType` enum (FIRE.OK, AMMO, RANGE, etc.)
- [x] Implement `MoveType` enum (MOVE.OK, CLOAK, NO, etc.)
- [x] Implement game constants (TICKS_PER_SECOND, LEPTON_PER_CELL, etc.)
- [x] Implement overlay/tiberium constants
- [ ] Implement `RadioMessageType` enum - needed for RadioClass
- [ ] Implement `SpeedType` enum (SPEED_FOOT, SPEED_TRACK, etc.)
- [ ] Implement `ArmorType` enum
- [ ] Implement `WarheadType` enum
- [ ] Implement `MarkType` enum (MARK_UP, MARK_DOWN, etc.)
- [ ] Implement `ThreatType` bitflags
Note: RTTIType is in target.lua as Target.RTTI. Most core enums are complete.

### AbstractClass (`src/objects/abstract.lua`) - COMPLETE
- [x] Implement all fields from ABSTRACT.H (Coord, IsActive, IsRecentlyCreated, _heap_index)
- [x] Implement `AI()` - per-tick logic (clears IsRecentlyCreated)
- [x] Implement `Center_Coord()` / `Target_Coord()` - coordinate queries
- [x] Implement `Distance_To_*()` - distance to target/coord/cell/object
- [x] Implement `Direction_To_*()` / `Facing_To_Object()` - direction calculations
- [x] Implement `As_Target()` - convert to TARGET
- [x] Implement `Owner()` - returns HOUSE_NONE (virtual)
- [x] Implement `Can_Enter_Cell()` - returns MOVE.OK (virtual)
- [x] Implement heap management (get/set_heap_index, get_rtti)
- [x] Implement `Debug_Dump()` - debug output
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` - serialization
Note: Entry_Coord/Exit_Coord/Sort_Y deferred to ObjectClass

### ObjectClass (`src/objects/object.lua`) - COMPLETE
- [x] Implement all fields from OBJECT.H (Next, Trigger, Strength, IsDown, IsToDamage, IsToDisplay, IsInLimbo, IsSelected, IsSelectedMask, IsAnimAttached)
- [x] Implement MARK and RESULT constants
- [x] Implement `Limbo()` / `Unlimbo()` - map presence control
- [x] Implement `Mark(mark_type)` - MARK.UP/DOWN/CHANGE handling
- [x] Implement `Render(forced)` - render control
- [x] Implement `Take_Damage()` - damage with warhead/armor support
- [x] Implement `Select()` / `Unselect()` / selection mask methods
- [x] Implement `What_Action_Object()` / `What_Action_Cell()` - action queries
- [x] Implement `Active_Click_With_Object()` / `Active_Click_With_Cell()` stubs
- [x] Implement `Clicked_As_Target()` stub
- [x] Implement `In_Which_Layer()` - returns LAYER.GROUND
- [x] Implement `Sort_Y()` / `Render_Coord()` / `Docking_Coord()` / `Fire_Coord()`
- [x] Implement `Health_Ratio()` - 0-256 fixed point
- [x] Implement `Detach()` / `Detach_All()` stubs
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` - serialization
- [x] Implement `Debug_Dump()`
Note: Per_Cell_Process, Look, Repair, Sell_Back are stubs to be filled in derived classes

### MissionClass (`src/objects/mission.lua`) - COMPLETE
- [x] Implement all fields (Mission, SuspendedMission, MissionQueue, Status, Timer)
- [x] Implement `AI()` - mission state machine with timer
- [x] Implement `Assign_Mission()` / `Set_Mission()` - mission assignment
- [x] Implement `Get_Mission()` / `Mission_Name()` - mission query
- [x] Implement `Commence()` / `Can_Commence_Mission()` - mission start
- [x] Implement `Override_Mission()` / `Restore_Mission()` - mission suspend/restore
- [x] Implement `Process_Mission()` - dispatch to Mission_X handlers
- [x] Implement all Mission_X() handlers as stubs
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` - serialization
- [x] Implement `Debug_Dump()`
Note: Mission_X handlers are base stubs - overridden in FootClass, TechnoClass, etc.

### RadioClass (`src/objects/radio.lua`) - COMPLETE
- [x] Implement all fields (Radio, LastMessage) + RADIO enum
- [x] Implement `Transmit_Message()` - send message with HELLO/OVER_OUT handling
- [x] Implement `Receive_Message()` - receive message with contact management
- [x] Implement `In_Radio_Contact()` / `Contact_With_Whom()` / `Radio_Off()`
- [x] Implement `Establish_Contact()` / `Break_Contact()` - helper functions
- [x] Implement `Limbo()` override - break contact before limbo
- [x] Implement RADIO enum with 22 message types
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` / `Resolve_Pointers()`
- [x] Implement `Debug_Dump()`
Note: Specific message handling (PICK_UP, ATTACH, etc.) done in derived TechnoClass

### CellClass (`src/map/cell.lua`) - MOSTLY COMPLETE
Audit reveals extensive implementation (669 lines):
- [x] Implement all fields from CELL.H
  - [x] `CellNumber` (CELL) via `get_cell_number()`, x/y fields
  - [x] `Overlay` (OverlayType) - overlay field
  - [x] `OverlayData` (tiberium stage, wall health) - overlay_data field
  - [x] `Smudge` (SmudgeType) - smudge field with SMUDGE constants
  - [x] `SmudgeData` (smudge variant) - smudge_data field
  - [ ] `Land` (LandType) - missing, terrain passability uses template_type
  - [x] `Owner` (HouseType) - owner field
  - [x] `OccupierPtr` (object linked list) - occupier field
  - [x] `OccupyList` via FLAG (CENTER/NW/NE/SW/SE/VEHICLE/MONOLITH/BUILDING/WALL)
  - [x] `InfType` - infantry_type field
  - [x] `Flag` (cell flags) - flags bitfield
  - [x] `Template` (TerrainType) - template_type field
  - [x] `Icon` (terrain icon index) - template_icon field
  - [x] `TriggerPtr` - trigger field
  - [x] `IsMapped`/`IsVisible` per-player via tables
  - [x] `IsWaypoint` - waypoint field
  - [x] `IsFlagged` (CTF) - has_flag/flag_owner fields
- [x] Implement `Cell_Coord()` - `to_leptons()` returns center coordinate
- [x] Implement `Cell_Occupier()` - resolves TARGET to object via Globals.Target_To_Object()
- [x] Implement `Is_Clear_To_Move()` - `is_passable(locomotor, terrain_type)`
- [x] Implement `Is_Clear_To_Build()` - in Grid.can_place_building()
- [x] Implement `Occupy_Down(obj)` / `Occupy_Up(obj)` - full implementation with type-specific handling
- [x] Implement `Overlap_Down(obj)` / `Overlap_Up(obj)` - render overlap management
- [x] Implement `Get_Template_Info()` - template_type/template_icon accessible
- [x] Implement `Spot_Index(coord)` - FLAG constants define positions
- [x] Implement `Closest_Free_Spot()` - `get_free_spot()` finds free infantry spot
- [x] Implement `Is_Bridge_Here()` - `has_bridge()` with OVERLAY_BRIDGE constants
- [x] Implement `Goodie_Check()` - no-op for TD (crates not in original)
- [x] Implement `Cell_Techno()` - resolves any RTTI (Building/Unit/Infantry/Aircraft)
- [x] Implement `Cell_Building()` - resolves to BuildingClass
- [x] Implement `Cell_Terrain()` - template_type provides terrain
- [x] Implement `Cell_Infantry(spot)` - resolves to InfantryClass with optional spot filter
- [x] Implement `Cell_Unit()` - resolves to UnitClass
- [x] Implement `Cell_Aircraft()` - resolves to AircraftClass
- [x] Implement `Cell_Find_Object(rtti)` - find any object type by RTTI
- [x] Implement `Iterate_Overlappers()` - iterator for all overlapping objects
- [x] Implement `Object_Count()` - count objects in cell
- [x] Implement `Adjacent_Cell(facing)` - in Grid.get_adjacent()
- [x] Implement `Concrete_Calc()` - wall_frame calculation exists
- [x] Implement `Wall_Update()` - Grid.update_wall_connections()
- [x] Implement `Tiberium_Adjust()` - `grow_tiberium()`, Grid.Logic()
- [x] Implement `Reduce_Tiberium()` - `harvest_tiberium(amount)`
- [x] Implement `Reduce_Wall()` - `damage_wall(damage)`
- [ ] Implement `Incoming()` - threat tracking missing
- [x] Implement `Redraw_Objects()` - handled by rendering system
- [x] Implement serialize/deserialize for save/load (includes TARGET-based occupier/overlappers)
- [x] Implement Debug_Dump() with flag names and TARGET resolution
- [ ] Write unit tests for CellClass
Note: Object retrieval now fully integrated with Globals heap via TARGET values

### MapClass (`src/map/grid.lua`) - MOSTLY COMPLETE
Note: Named `Grid` in implementation. Audit reveals extensive implementation (704 lines):
- [x] Implement 64x64 cell grid (configurable via Constants.MAP_CELL_W/H)
- [x] Implement `Cell_Ptr(cell)` - `get_cell(x,y)` and `get_cell_by_number()`
- [x] Implement `Coord_Cell(coord)` - `lepton_to_cell(lx, ly)`
- [x] Implement `Cell_Coord(cell)` - `cell_to_lepton(cx, cy)`
- [x] Implement `In_Radar(cell)` - `is_valid(x, y)` bounds check
- [ ] Implement `Close_Object(coord)` - find nearest object (needs heap)
- [ ] Implement `Nearby_Location(coord, speed)` - find passable cell
- [ ] Implement `Cell_Shadow(cell)` - calculate shroud (in shroud.lua)
- [x] Implement `Place_Down(cell, obj)` - `place_building()` for buildings
- [x] Implement `Pick_Up(cell, obj)` - `remove_building()` for buildings
- [x] Implement `Overlap_Down(cell, obj)` - Cell.add_overlapper()
- [x] Implement `Overlap_Up(cell, obj)` - Cell.remove_overlapper()
- [x] Implement map boundary handling - `is_valid()` bounds check
- [x] Implement map size/bounds storage - width/height fields
- [x] Implement `get_adjacent(x, y, direction)` - 8-directional neighbor
- [x] Implement `get_neighbors(x, y)` - all 8 adjacent cells
- [x] Implement `get_cells_in_rect()` - rectangular region
- [x] Implement `get_cells_in_radius()` - circular region
- [x] Implement `set_terrain()` / `set_overlay()` - cell modification
- [x] Implement `clear_visibility()` / `reveal_area()` - visibility control
- [x] Implement `can_place_building()` - full adjacency rules from original
- [x] Implement `can_place_building_type()` - building-specific rules
- [x] Implement wall system: `place_wall()`, `remove_wall()`, `update_wall_connections_area()`
- [x] Implement tiberium system via `Logic()`:
  - [x] Tiberium growth (stage increase)
  - [x] Tiberium spread (to adjacent cells)
  - [x] Blossom tree spawning (terrain_object.is_tiberium_spawn)
  - [x] Forward/backward scan alternation (match original)
  - [x] Growth/spread rate options (normal/fast)
- [x] Implement `iterate()` - cell iteration
- [x] Implement `serialize()` / `deserialize()` - save/load
- [ ] Write unit tests for MapClass/Grid
Note: Close_Object and Nearby_Location need heap integration for object queries

### LayerClass (`src/map/layer.lua`) - COMPLETE
Audit reveals extensive implementation (486 lines):
- [x] Implement LAYER_TYPE enum (NONE=-1, GROUND=0, AIR=1, TOP=2)
- [x] Implement `Submit(obj, sort)` - add object (optionally sorted)
- [x] Implement `Add(obj)` - add object unsorted
- [x] Implement `Sorted_Add(obj)` - add in Y-sorted position
- [x] Implement `Remove(obj)` - remove from layer
- [x] Implement `Sort()` - incremental bubble sort pass
- [x] Implement `Full_Sort()` - complete insertion sort
- [x] Implement `Compare(a, b)` - Y coordinate comparison
- [x] Implement `Get_Sort_Y(obj)` - extract sort key from Coord
- [x] Implement `Count()`, `Is_Empty()`, `Get(index)`, `Iterate()`, `Get_All()`
- [x] Implement static layer manager:
  - [x] `LayerClass.Layers[]` array (3 layers)
  - [x] `Init_All()` - initialize all layers
  - [x] `Get_Layer(type)` - get layer by type
  - [x] `Submit_To(obj, type, sort)` - submit to specific layer
  - [x] `Remove_From(obj, type)` - remove from specific layer
  - [x] `Sort_All()` - sort all layers
  - [x] `Clear_All()` - clear all layers
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` for save/load
- [x] Implement `Debug_Dump(layer_type)`
- [ ] Write unit tests for LayerClass

### Display Hierarchy (`src/display/`)
- [ ] Implement `GScreenClass` base
  - [ ] Screen dimensions
  - [ ] Input handling hooks
  - [ ] `One_Time()` initialization
  - [ ] `Init()` per-game init
- [ ] Implement `DisplayClass` tactical view
  - [ ] Viewport position
  - [ ] Cell-to-pixel conversion
  - [ ] Pixel-to-cell conversion
  - [ ] `Tactical_Cell()` - cell under cursor
  - [ ] `Tactical_Coord()` - coordinate under cursor
  - [ ] `Submit(cell)` - mark cell dirty
  - [ ] `Refresh_Cells(coord, list)` - refresh area
- [ ] Implement `RadarClass` minimap
  - [ ] Minimap rendering
  - [ ] Click-to-scroll
  - [ ] Object blips
- [ ] Implement `ScrollClass` scrolling
  - [ ] Edge scrolling
  - [ ] Keyboard scrolling
  - [ ] Scroll limits
- [ ] Implement `MouseClass` cursor
  - [ ] Cursor shape selection
  - [ ] Cursor animation
  - [ ] Cursor coordinate tracking
- [ ] Implement visual interpolation (15 FPS → 60 FPS)
- [ ] Write unit tests for display classes

### Game Loop Integration (`src/core/game.lua`)
- [ ] Remove ECS world reference (deferred - shims still needed for rendering)
- [x] Implement main game tick at 15 FPS (tick_accumulator exists)
- [x] Implement AI() calls for all active objects (Globals.Process_All_AI())
- [x] Implement object iteration order (match original) (Building→Infantry→Unit→Aircraft→Bullet→Anim)
- [x] Implement render loop at 60 FPS (Love2D default)
- [x] Implement delta time accumulator for fixed timestep (exists)
- [ ] Implement frame interpolation for smooth rendering
- [x] Implement game pause/resume (exists)
- [x] Implement game speed adjustment (game_speed multiplier exists)
- [ ] Write integration tests for game loop

### Save/Load System (`src/io/`)
- [ ] Implement `Code_Pointers()` for all classes
- [ ] Implement `Decode_Pointers()` for all classes
- [ ] Implement heap index serialization
- [ ] Implement TARGET serialization
- [ ] Implement COORDINATE serialization
- [ ] Implement CELL serialization
- [ ] Implement save file format
- [ ] Implement save file versioning
- [ ] Implement load validation
- [ ] Write save/load round-trip tests

### Debug Infrastructure (`src/debug/`)
- [ ] Implement `Debug_Dump()` for all classes
- [ ] Implement `MonoClass` equivalent logging
- [ ] Adapt IPC system for class hierarchy
- [ ] Implement debug overlay toggle
- [ ] Implement object inspection via IPC
- [ ] Implement heap status via IPC
- [ ] Write debug helper utilities

---

## Phase 2: TechnoClass & Game Objects

### Mixin Classes (`src/objects/mixins/`) - COMPLETE
- [x] Implement `FlasherClass` (flasher.lua)
  - [x] `FlashCount` field
  - [x] `Start_Flash()` / `Stop_Flash()` - trigger/stop flash
  - [x] `Process()` - decrement counter
  - [x] `Is_Flashing()` - check state
  - [x] Per-player flash support for multiplayer
  - [x] Save/load serialization
- [x] Implement `StageClass` (stage.lua)
  - [x] `Rate` field (animation speed)
  - [x] `Stage` field (current frame)
  - [x] `StageTimer` field
  - [x] `Set_Rate(rate)` - set animation speed
  - [x] `Set_Stage(stage)` - set frame
  - [x] `Graphic_Logic()` - advance animation
  - [x] Save/load serialization
- [x] Implement `CargoClass` (cargo.lua)
  - [x] `CargoHold` array (linked list)
  - [x] `CargoQuantity` field
  - [x] `Attach(obj)` - add cargo
  - [x] `Detach_Object()` - remove cargo
  - [x] `Attached_Object()` - get first cargo
  - [x] `How_Many()` - cargo count
  - [x] Save/load with TARGET resolution
- [x] Implement `DoorClass` (door.lua)
  - [x] `DoorState` field with STATE enum (CLOSED, OPENING, OPEN, CLOSING)
  - [x] `DoorTimer` field
  - [x] `Open_Door()` / `Close_Door()` with animation
  - [x] `AI_Door()` - door state machine
  - [x] `Is_Door_Open()` / `Is_Door_Closed()`
  - [x] Save/load serialization
- [x] Implement `CrewClass` (crew.lua)
  - [x] `Crew_Type()` - survivor infantry type
  - [x] `Made_A_Kill()` / `Get_Kills()` / `Set_Kills()`
  - [x] Rank system (ROOKIE, VETERAN, ELITE)
  - [x] `Should_Spawn_Crew()` - survivor generation logic
  - [x] Save/load serialization
- [x] All mixins integrated into TechnoClass via Class.include()
Note: Unit tests for mixins covered by test_class_oop.lua mixin composition tests

### TechnoClass (`src/objects/techno.lua`) - COMPLETE
- [x] Implement all fields from TECHNO.H (1462 lines)
  - [x] `House` (owning HouseClass)
  - [x] `TarCom` (TARGET - attack target)
  - [x] `PrimaryFacing` (facing)
  - [x] `Cloak` (cloak state) with CLOAK enum
  - [x] `CloakTimer` / `CloakStage` (animation)
  - [x] `Arm` (rearm countdown)
  - [x] `Ammo` (ammunition count)
  - [x] All flags: IsCloakable, IsLeader, IsALoaner, IsLocked, IsTethered, etc.
  - [x] `IsInRecoilState`, `IsTickedOff`, `IsOwnedByPlayer`
  - [x] `ArchiveTarget`, `SuspendedTarCom`
  - [x] `PurchasePrice`, `IsDiscoveredByPlayerMask`
  - [x] Constants: CLOAK enum, VISUAL enum, FIRE_ERROR enum, THREAT flags
- [x] Apply all mixins (Flasher, Stage, Cargo, Door, Crew) via Class.include()
- [x] Implement `AI()` - calls parent + mixins (Process, Graphic_Logic, AI_Door)
- [x] Implement `Fire_At(target, which)` - complete weapon firing with bullet spawn
- [x] Implement `Can_Fire(target, which)` - weapon readiness check
- [x] Implement `Fire_Coord(which)` - inherited from ObjectClass
- [x] Implement `Assign_Target(target)` - set TarCom
- [x] Implement `In_Range(target, which)` - range check with TARGET resolution
- [x] Implement `Take_Damage()` - calls parent + flash + tickedoff tracking
- [x] Implement `Captured(newowner)` - change ownership
- [x] Implement `Greatest_Threat(threat)` - full threat scanning with heap iteration
- [x] Implement `Evaluate_Object()` - threat evaluation helper
- [x] Implement `Is_Enemy()` - house-based enemy check
- [x] Implement `Do_Cloak()` / `Do_Uncloak()` - cloak control with state machine
- [x] Implement `Do_Shimmer()` - shimmer effect
- [x] Implement `Visual_Character()` - rendering state based on cloak
- [x] Implement `Revealed(house)` - reveal to house with bitmask
- [x] Implement `Is_Cloaked(house)` - cloaking visibility check
- [x] Implement `Player_Assign_Mission(order, target, destination)`
- [x] Implement `Response_Select/Move/Attack()` - voice stubs for derived classes
- [x] Implement `Weapon_Range(which)` - weapon range from type class
- [x] Implement `Rearm_Delay(second)` - rearm timing from type class
- [x] Implement `Base_Is_Attacked(source)` - base defense alert
- [x] Implement `Kill_Cargo(source)` - destroy cargo in transport
- [x] Implement `Record_The_Kill()` - kill tracking
- [x] Implement `Clicked_As_Target()` - target flash
- [x] Implement `Select()` override with voice response
- [x] Implement `Override_Mission()` / `Restore_Mission()` with TarCom handling
- [x] Implement `Unlimbo()` override with facing
- [x] Implement `Detach()` override for target cleanup
- [x] Implement helper queries: Techno_Type_Class, Get_Armor, Is_Weapon_Equipped, etc.
- [x] Implement Code_Pointers / Decode_Pointers for save/load
- [x] Implement Debug_Dump() with full state output
Note: Tiberium field is in UnitClass (harvesters); Electric/EMP not in original TD

### FootClass (`src/objects/foot.lua`) - COMPLETE
- [x] Implement all fields from FOOT.H (1127 lines)
  - [x] `NavCom` (TARGET - move target)
  - [x] `SuspendedNavCom` (saved nav target)
  - [x] `Path` array (24 entries max - CONQUER_PATH_MAX)
  - [x] `PathDelay` (pathfinding cooldown)
  - [x] `TryTryAgain` (retry counter)
  - [x] `Team` (TeamClass pointer)
  - [x] `Member` (next team member)
  - [x] `Group` (player group 0-9, GROUP_NONE=255)
  - [x] `Speed` (current movement speed 0-255)
  - [x] `HeadToCoord` (next waypoint coord)
  - [x] `IsInitiated` / `IsDriving` / `IsRotating` / `IsFiring`
  - [x] `IsUnloading` / `IsDeploying` / `IsNewNavCom` / `IsPlanningToLook`
  - [x] `BaseAttackTimer`
  - [x] Constants: CONQUER_PATH_MAX, PATH_DELAY, PATH_RETRY, FACING enum, MOVE enum
- [x] Implement `Assign_Destination(target)` - set NavCom with path clear
- [x] Implement `Start_Driver(coord)` - begin movement
- [x] Implement `Stop_Driver()` - halt movement
- [x] Implement `Offload_Tiberium_Bail()` - stub for UnitClass
- [x] Implement `Random_Animate()` - idle animation stub
- [x] Implement `Per_Cell_Process(center)` - cell transition handling
- [x] Implement `Can_Enter_Cell(cell, facing)` - movement check
- [x] Implement `Set_Speed(speed)` - speed control
- [x] Implement `Mission_Move()` - movement mission with idle transition
- [x] Implement `Mission_Attack()` - attack mission with Approach_Target
- [x] Implement `Mission_Guard()` - guard mission with threat scanning
- [x] Implement `Mission_Guard_Area()` - area guard with extended range
- [x] Implement `Mission_Hunt()` - hunt mission with engineer special case
- [x] Implement `Mission_Timed_Hunt()` - multiplayer AI timing
- [x] Implement `Mission_Enter()` - enter transport mission
- [x] Implement `Mission_Capture()` - capture mission for engineers
- [x] Implement `Approach_Target()` - full range calculation and positioning
- [x] Implement `Basic_Path()` - pathfinding integration with FindPath
- [x] Implement `Clear_Path()` / `Get_Next_Path_Facing()` - path management
- [x] Implement team support: Detach, Detach_All
- [x] Implement `Scatter(source, forced, nokidding)` - scatter from threats
- [x] Implement `Take_Damage()` override with scatter
- [x] Implement `Sell_Back(control)` - sell unit back
- [x] Implement `Limbo()` / `Unlimbo()` overrides with team handling
- [x] Implement `Override_Mission()` / `Restore_Mission()` with NavCom
- [x] Implement `Receive_Message()` override for HOLD_STILL/OVER_OUT
- [x] Implement query functions: Head_To_Coord, Sort_Y, Likely_Coord, Can_Demolish
- [x] Implement Code_Pointers / Decode_Pointers for save/load
- [x] Implement Debug_Dump() with path output
Note: Mission_Harvest, Mission_Sabotage, Mission_Retreat are in derived classes

### DriveClass (`src/objects/drive/drive.lua`)
- [ ] Implement ground vehicle movement physics
- [ ] Implement track/wheel/hover speed types
- [ ] Implement slope handling
- [ ] Implement water/cliff blocking
- [ ] Implement bridge crossing
- [ ] Implement crushing infantry
- [ ] Implement vehicle rotation animation
- [ ] Write unit tests for DriveClass

### FlyClass (`src/objects/drive/fly.lua`) - COMPLETE
- [x] Implement aircraft movement physics (433 lines)
  - [x] `SpeedAccum` / `SpeedAdd` - Bresenham-style speed accumulator
  - [x] `Physics()` - full flight physics with angle-based movement calculation
  - [x] `Fly_Speed()` / `Set_Max_Speed()` / `Stop_Flight()` - speed control
  - [x] `MPH` speed constants (IMMOBILE through BLAZING - 9 levels)
- [x] Implement flight altitude
  - [x] `Altitude` / `TargetAltitude` / `ClimbRate` fields
  - [x] `ALTITUDE` constants (GROUND/LOW/MEDIUM/HIGH)
  - [x] `Set_Altitude()` / `Get_Altitude()` - altitude control
  - [x] `Process_Altitude()` - smooth altitude interpolation
- [x] Implement takeoff/landing
  - [x] `FlightState` enum (GROUNDED/TAKING_OFF/FLYING/LANDING/HOVERING)
  - [x] `Take_Off()` / `Land()` - state transitions
  - [x] State machine in Process_Altitude()
- [x] Implement hovering (helicopters)
  - [x] `IsVTOL` flag
  - [x] `Hover()` - enter hover mode for VTOL aircraft
  - [x] `Is_Hovering()` query
- [x] Implement collision detection stub
  - [x] `Check_Collision()` - returns IMPACT enum
  - [x] `IMPACT` types (NONE/GROUND/WATER/BUILDING/UNIT)
- [x] Implement query functions: Is_Airborne, Is_Grounded, Is_Taking_Off, Is_Landing, Flight_Speed
- [x] Implement AI_Fly() for per-tick processing
- [x] Implement Code_Pointers_Fly / Decode_Pointers_Fly for save/load
- [x] Implement Debug_Dump_Fly with state names
Note: Landing pad docking handled in AircraftClass; high-speed flight via type MaxSpeed

### TarComClass (`src/objects/drive/tarcom.lua`)
- [ ] Implement turret tracking
- [ ] Implement turret rotation independent of body
- [ ] Implement secondary facing for turret
- [ ] Implement turret rotation speed
- [ ] Write unit tests for TarComClass

### InfantryClass (`src/objects/infantry.lua`) - COMPLETE
- [x] Implement all fields from INFANTRY.H (803 lines)
  - [x] `Fear` (fear value 0-255) with FEAR constants
  - [x] `Doing` (DoType - current action) with DO enum (22 states)
  - [x] `Stop` (StopType - stopped pose) with STOP enum
  - [x] `Comment` (comment timer)
  - [x] `IdleTimer` (idle animation timer)
  - [x] `IsProne` / `IsStoked` / `IsTechnician` / `IsBoxing`
  - [x] `Occupy` / `ToSubCell` - subcell position tracking
  - [x] Constants: FEAR levels, DO enum, STOP enum, SUBCELL enum
- [x] Implement 5-position cell occupation (SUBCELL enum with CENTER/NW/NE/SW/SE)
- [x] Implement `AI()` - infantry-specific logic with fear decay and panic
- [x] Implement `Do_Action(action, force)` - animation action with interrupt logic
- [x] Implement `Get_Action()` / `Clear_Action()` - action state management
- [x] Implement `Set_Occupy_Bit(cell)` / `Clear_Occupy_Bit(cell)` - occupy stubs
- [x] Implement `Find_Free_Subcell(cell)` - find free infantry spot
- [x] Implement `Start_Driver()` / `Stop_Driver()` overrides with animation
- [x] Implement fear system: Add_Fear, Reduce_Fear, Is_Panicking, Is_Scared, Response_Panic
- [x] Implement prone system: Go_Prone, Get_Up, Clear_Prone, Is_Prone
- [x] Implement `Get_Speed()` - movement speed with prone modifier
- [x] Implement `Fire_At()` override with prone animation selection
- [x] Implement `Take_Damage()` override with fear accumulation
- [x] Implement `Scatter()` override with fear and prone handling
- [x] Implement `Per_Cell_Process()` override with occupancy update
- [x] Implement `Select_Death_Animation(warhead)` - death animation selection
- [x] Implement `Kill(source, warhead)` - death handling
- [x] Implement mission overrides: Mission_Attack (engineer capture), Mission_Guard, Mission_Capture, Mission_Enter
- [x] Implement voice responses: Response_Select, Response_Move, Response_Attack
- [x] Implement `Center_Coord()` override (subcell positioning stub)
- [x] Implement `get_rtti()` / `What_Am_I()` - RTTI.INFANTRY
- [x] Implement `Techno_Type_Class()` / `Class_Of()` - type access
- [x] Implement Code_Pointers / Decode_Pointers for save/load
- [x] Implement Debug_Dump() with full state output
Note: C4/commando and enter building logic in mission handlers; Made_A_Kill inherited from CrewClass mixin

### UnitClass (`src/objects/unit.lua`) - COMPLETE
- [x] Implement all fields from UNIT.H (1000 lines)
  - [x] `Tiberium` (harvester cargo count)
  - [x] `HarvestTimer` / `UnloadTimer` (harvest/unload operation timing)
  - [x] `IsHarvesting` / `IsDeploying` / `IsRotating` flags
  - [x] `DeployTimer` / `AnimTimer` (deployment and animation timing)
  - [x] `Flagged` (CTF mode flag)
  - [x] `JitterCount` (stuck detection)
  - [x] `IsTurretEquipped` / `IsTransporter` (from type class)
  - [x] Constants: UNIT enum (16 unit types), TIBERIUM_CAPACITY, HARVEST_DELAY, UNLOAD_DELAY, DEPLOY_TIME
- [x] Implement `AI()` - vehicle-specific logic with timer decrements
- [x] Implement full harvester system:
  - [x] `Is_Harvester()` / `Tiberium_Load()` / `Is_Full()` / `Is_Empty()` - status queries
  - [x] `Harvest()` - basic harvest operation with timer
  - [x] `Harvesting()` - full harvest from cell with grid integration
  - [x] `On_Tiberium()` - check if on tiberium cell
  - [x] `Find_Tiberium()` - spiral search for nearest tiberium field
  - [x] `Find_Refinery()` - find nearest refinery with radio contact
  - [x] `Offload_Tiberium_Bail()` - unload at refinery
- [x] Implement `Mission_Harvest()` - full state machine (LOOKING/HARVESTING/FINDHOME/HEADINGHOME/GOINGTOIDLE)
- [x] Implement `Mission_Unload()` - refinery unloading with house credit
- [x] Implement `Mission_Move()` override with stuck detection
- [x] Implement `Mission_Guard()` override with auto-harvest for harvesters
- [x] Implement transport system: `Can_Transport()`, `Max_Passengers()`
- [x] Implement MCV deployment:
  - [x] `Can_Deploy()` - deployment check
  - [x] `Deploy()` - start deployment
  - [x] `Complete_Deploy()` - create Construction Yard and remove MCV
- [x] Implement `Death_Announcement(source)` - explosion/tiberium spill/cargo kill
- [x] Implement `Per_Cell_Process()` override with auto-harvest
- [x] Implement `Get_Speed_Factor()` - slower when carrying tiberium
- [x] Implement `Enter_Idle_Mode()` override for harvester auto-harvest
- [x] Implement voice responses: Response_Select, Response_Move, Response_Attack
- [x] Implement `get_rtti()` / `What_Am_I()` - RTTI.UNIT
- [x] Implement `Techno_Type_Class()` / `Class_Of()` - type access
- [x] Implement Code_Pointers / Decode_Pointers for save/load
- [x] Implement Debug_Dump() with full state output
Note: Turret rotation via TarComClass inheritance; crushing/amphibious from type flags; gap/berzerk not in TD

### AircraftClass (`src/objects/aircraft.lua`) - COMPLETE
- [x] Implement all fields from AIRCRAFT.H (721 lines + 433-line FlyClass mixin)
  - [x] `BodyFrame` (rotor/body animation frame)
  - [x] `Altitude` (via FlyClass mixin - current altitude in leptons)
  - [x] `TargetAltitude` / `ClimbRate` (altitude control)
  - [x] `IsLanding` / `IsTakingOff` / `LandState` (landing state machine)
  - [x] `LandingTarget` (helipad TARGET for landing)
  - [x] `Ammo` / `MaxAmmo` / `Fuel` (resource tracking)
  - [x] `AttackTimer` / `StrafeCount` (attack operation tracking)
  - [x] `IsVTOL` (VTOL capability flag from type)
  - [x] Constants: AIRCRAFT enum (4 types), LAND_STATE (5 states), AIRCRAFT_SPEED, FLIGHT_LEVEL
- [x] Implement FlyClass mixin (src/objects/drive/fly.lua - 433 lines):
  - [x] `SpeedAccum` / `SpeedAdd` - Bresenham-style speed accumulator
  - [x] `FlightState` enum (GROUNDED/TAKING_OFF/FLYING/LANDING/HOVERING)
  - [x] `ALTITUDE` constants (GROUND/LOW/MEDIUM/HIGH)
  - [x] `MPH` speed constants (IMMOBILE through BLAZING)
  - [x] `IMPACT` collision types
  - [x] `Fly_Speed()` / `Set_Max_Speed()` / `Stop_Flight()` - speed control
  - [x] `Set_Altitude()` / `Take_Off()` / `Land()` / `Hover()` - altitude control
  - [x] `Physics()` - full flight physics with angle-based movement
  - [x] `Process_Altitude()` - altitude interpolation toward target
  - [x] `Check_Collision()` - collision detection stub
  - [x] `AI_Fly()` - per-tick flight processing
  - [x] Query functions: Is_Airborne, Is_Grounded, Is_Taking_Off, Is_Landing, Is_Hovering
  - [x] Code_Pointers_Fly / Decode_Pointers_Fly for save/load
  - [x] Debug_Dump_Fly with state names
- [x] Implement `AI()` - flight physics + takeoff/landing completion + rotor animation
- [x] Implement `Start_Takeoff()` / `Start_Landing()` / `Complete_Landing()` - flight control
- [x] Implement `Reload_Ammo()` - ammunition reload at helipad
- [x] Implement `Should_Return_To_Base()` / `Return_To_Base()` - RTB logic
- [x] Implement `Start_Driver()` override - auto-takeoff before movement
- [x] Implement `Per_Cell_Process()` override - fuel consumption
- [x] Implement `Center_Coord()` / `Sort_Y()` overrides for altitude rendering
- [x] Implement `Can_Fire()` / `Fire_At()` overrides with ammo consumption
- [x] Implement `Take_Damage()` override with `Crash()` when destroyed airborne
- [x] Implement mission overrides: Mission_Move, Mission_Attack, Mission_Guard, Mission_Enter, Mission_Hunt
- [x] Implement `Enter_Idle_Mode()` override - RTB when idle and airborne
- [x] Implement voice responses: Response_Select, Response_Move, Response_Attack
- [x] Implement `get_rtti()` / `What_Am_I()` - RTTI.AIRCRAFT
- [x] Implement `Techno_Type_Class()` / `Class_Of()` - type access
- [x] Implement Code_Pointers / Decode_Pointers for save/load (includes Fly mixin data)
- [x] Implement Debug_Dump() with full state output (includes Debug_Dump_Fly)
Note: Specific unit behaviors (Orca/Apache/Chinook/A-10) determined by type class properties

### BuildingClass (`src/objects/building.lua`) - COMPLETE
- [x] Implement all fields from BUILDING.H (2340 lines)
  - [x] `Factory` (FactoryClass pointer)
  - [x] `BState` / `QueueBState` / `ScenarioInit` / `StateFrame` (state machine)
  - [x] `LastStrength` (for damage state tracking)
  - [x] `PowerOutput` / `PowerDrain` (power system)
  - [x] `IsRepairing` / `RepairTimer` (repair system)
  - [x] `IsPrimary` (primary factory for production)
  - [x] `IsSelling` / `SellTimer` (sell system)
  - [x] `IsCaptured` (captured by engineer)
  - [x] `TiberiumStored` / `TiberiumCapacity` (storage)
  - [x] `BuildProgress` (construction progress)
  - [x] `TurretFacing` / `FireTarget` (defense buildings)
  - [x] `AnimTimer` / `SabotageTimer` (timers)
  - [x] Constants: BSTATE enum (7 states), BUILDING enum (17 types), POWER constants
- [x] Implement `AI()` - repair processing, sell timer, sabotage, animation, factory
- [x] Implement `Grand_Opening(captured)` - full activation with power, storage, free unit spawning
  - [x] `Spawn_Free_Harvester()` - refinery free harvester
  - [x] `Spawn_Free_Aircraft()` - helipad free aircraft
- [x] Implement `Toggle_Primary()` - set primary factory with type-based factory management
- [x] Implement `Get_Factory_Type()` - returns "infantry"/"vehicle"/"aircraft"/"building"
- [x] Implement `Begin_Mode(bstate)` - state transition with animation control
- [x] Implement `Fetch_Anim_Control()` - animation data lookup by state
- [x] Implement power system:
  - [x] `Power_Output()` - with damage scaling
  - [x] `Power_Drain()` - operational check
  - [x] `Has_Power()` - power plant/drain check
  - [x] `Power_Efficiency()` - 0.0-1.0 multiplier based on house power ratio
  - [x] `Can_Operate()` - operational + power check
- [x] Implement Tiberium storage:
  - [x] `Tiberium_Stored()` / `Storage_Capacity()` / `Is_Storage_Full()`
  - [x] `Store_Tiberium()` / `Remove_Tiberium()` with state updates
- [x] Implement production:
  - [x] `Can_Produce()` / `Get_Factory()` / `Set_Factory()` / `Start_Production()`
- [x] Implement repair system:
  - [x] `Can_Repair()` / `Start_Repair()` / `Stop_Repair()` / `Process_Repair()`
- [x] Implement sell system:
  - [x] `Can_Sell()` / `Sell()` / `Sell_Back()` / `Complete_Sell()` / `Update_Sell()`
- [x] Implement capture system:
  - [x] `Can_Capture()` / `Capture(newowner)` with health reduction
- [x] Implement sabotage:
  - [x] `Plant_C4(timer)` / `Process_Sabotage()`
- [x] Implement `Take_Damage()` override with `Death_Announcement()`
- [x] Implement mission overrides:
  - [x] `Mission_Guard()` - defense threat scanning
  - [x] `Mission_Attack()` - turret rotation and firing
  - [x] `Mission_Construction()` - full construction state machine
  - [x] `Mission_Deconstruction()` - full sell/demolition state machine with survivor spawning
  - [x] `Mission_Harvest()` - refinery tiberium processing (5 states)
  - [x] `Mission_Repair()` - repair facility and helipad behavior
  - [x] `Mission_Missile()` - Temple of Nod nuke launch (5 states)
  - [x] `Mission_Unload()` - factory unit delivery
- [x] Implement `Spawn_Survivors()` - crew spawning on sell/destroy
- [x] Implement `Unlimbo()` / `Limbo()` overrides with house registration
- [x] Implement `Enter_Idle_Mode()` override
- [x] Implement placement validation:
  - [x] `Is_Adjacent_To_Building()` - adjacency check (static)
  - [x] `Can_Place_Building()` - full placement validation (static)
  - [x] `Get_Valid_Placement_Cells()` - find all valid placement cells (static)
- [x] Implement `Receive_Message()` override - refinery, repair facility, helipad docking
- [x] Implement `get_rtti()` / `What_Am_I()` - RTTI.BUILDING
- [x] Implement `Techno_Type_Class()` / `Class_Of()` - type access
- [x] Implement Code_Pointers / Decode_Pointers for save/load
- [x] Implement Debug_Dump() with full state output
Note: Gap generator jamming not in original TD; Update_Buildables is in HouseClass; Radar provided via type flags

### Type Classes (`src/objects/types/`) - COMPLETE
- [x] Complete `TechnoTypeClass` (470 lines)
  - [x] All fields from TECHNOTYPE.H (IsLeader, IsScanner, IsTurretEquipped, etc.)
  - [x] Weapon references (Primary, Secondary with WEAPON enum)
  - [x] Armor type field
  - [x] Speed type (MPH constants)
  - [x] Production: Cost, Level, Scenario, Prerequisites, Ownable bitfield
  - [x] Combat: SightRange, MaxSpeed, MaxAmmo, Risk, Reward
  - [x] Methods: Raw_Cost, Cost_Of, Time_To_Build, Can_Build, Repair_Cost/Step
  - [x] Cameo data support
  - [x] Debug_Dump
- [x] Complete `InfantryTypeClass` (433 lines)
  - [x] INFANTRY enum (20 types including civilians)
  - [x] DoControls (animation sequences) with DO enum (35 animation types)
  - [x] Set_Do_Control/Get_Do_Control, Get_Action_Frame/Count
  - [x] IsFemale, IsCrawling, IsCapture, IsFraidyCat, IsCivilian, IsAvoidingTiberium
  - [x] FireLaunch/ProneLaunch frames
  - [x] Factory method Create() with all infantry types (E1-E7, RAMBO, civilians)
  - [x] Query functions: Is_Civilian, Can_Capture, Is_Female, Is_Engineer, Is_Fraidy_Cat
  - [x] Debug_Dump
- [x] Complete `UnitTypeClass` (547 lines)
  - [x] UNIT enum (22 types including dinosaurs)
  - [x] SPEED enum (FOOT, TRACKED, WHEELED, WINGED, HOVER, FLOAT)
  - [x] SpeedType, IsCrusher, IsHarvester, IsRadar, IsRotatingTurret
  - [x] IsDeployable, DeployBuilding (for MCV)
  - [x] TurretOffset, TurretFrames, BodyFrames, AnimationRate
  - [x] IsNoFireWhileMoving, IsGigundo, IsAnimating, IsJammable
  - [x] Factory method Create() with all unit types (tanks, APC, harvester, MCV, etc.)
  - [x] Query functions: Is_Harvester, Can_Crush, Can_Deploy, Is_Wheeled/Tracked, Can_Hover
  - [x] Debug_Dump
- [x] Complete `AircraftTypeClass` (380 lines)
  - [x] AIRCRAFT enum (5 types: TRANSPORT, A10, HELICOPTER, CARGO, ORCA)
  - [x] LANDING enum (NONE, HELIPAD, RUNWAY, ANYWHERE)
  - [x] IsFixedWing, IsRotorEquipped, IsLandable, IsVTOL, IsTransportAircraft
  - [x] LandingType, FlightROT, CruiseAltitude, StrafeRuns
  - [x] BodyFrames, RotorFrames
  - [x] Factory method Create() with all aircraft types
  - [x] Query functions: Is_Fixed_Wing, Is_Rotor_Equipped, Can_Land, Is_VTOL, Can_Transport
  - [x] Debug_Dump
- [x] Complete `BuildingTypeClass` (746 lines)
  - [x] STRUCT enum (40+ types)
  - [x] SIZE table, FACTORY enum, BSTATE enum
  - [x] SizeWidth/Height, FoundationType, HasBib
  - [x] PowerOutput, PowerDrain
  - [x] TiberiumCapacity
  - [x] FactoryType, ToBuild list
  - [x] ExitCoord, RallyPoint
  - [x] IsCapturable, IsBaseDefense, IsSellable, RequiresPower, IsCivilian, IsStealthable, IsHelipad, IsRadar
  - [x] AnimControls for BState animations
  - [x] Factory method Create() with all building types (power, barracks, weapons factory, etc.)
  - [x] Size/Foundation, Power, Factory, Animation methods
  - [x] Debug_Dump
- [ ] Implement type data loading from JSON/data files (deferred - factory methods provide static data)
- [ ] Verify all type data matches original (deferred - awaiting gameplay testing)
- [ ] Write unit tests for type classes
Note: Factory Create() methods provide all unit/building data inline, matching original IDATA.CPP/UDATA.CPP/ADATA.CPP/BDATA.CPP

### Input Handling
- [ ] Implement left-click selection
- [ ] Implement right-click commands
- [ ] Implement box selection (drag)
- [ ] Implement double-click select same type
- [ ] Implement Ctrl+# group assignment
- [ ] Implement # group recall
- [ ] Implement Shift+# add to selection
- [ ] Implement scatter command (X key)
- [ ] Implement stop command (S key)
- [ ] Implement guard command (G key)
- [ ] Implement force attack (Ctrl+click)
- [ ] Implement force move (Alt+click)
- [ ] Implement original keybindings exactly
- [ ] Write input handling tests

### Selection System
- [ ] Implement multi-selection limit (matching original)
- [ ] Implement selection priority (buildings vs units)
- [ ] Implement selection box rendering
- [ ] Implement selection indicators on units
- [ ] Implement selected unit health bars
- [ ] Write selection tests

---

## Phase 3: Combat Systems - MOSTLY COMPLETE

### BulletClass (`src/objects/bullet.lua`) - COMPLETE
Audit reveals extensive implementation (620 lines):
- [x] Implement all fields from BULLET.H
  - [x] `Class` (BulletTypeClass)
  - [x] `Payback` (damage source for kill credit)
  - [x] `TarCom` (target object/coordinate)
  - [x] `PrimaryFacing` (travel direction 0-255)
  - [x] `IsInaccurate` / `IsToAnimate` / `IsLocked` flags
  - [x] `ArcAltitude` / `Riser` (arcing projectile physics)
  - [x] `FuseTimer` / `ArmingTimer` / `ProximityDistance` (fuse system)
- [x] Implement `AI()` - projectile movement with arcing/homing/fuse logic
- [x] Implement `Unlimbo(coord, facing, target)` - spawn projectile with range/arc setup
- [x] Implement straight-line ballistics via `Physics()` with speed accumulator
- [x] Implement arcing projectiles with gravity and Riser
- [x] Implement homing projectiles with ROT-based turn rate
- [x] Implement proximity detonation via `Fuse_Checkup()`
- [x] Implement impact detection via Physics() IMPACT return
- [x] Implement `Detonate()` with damage and explosion animation
- [x] Implement `Apply_Inaccuracy()` for scatter
- [x] Implement FlyClass mixin for flight physics
- [x] Implement RTTI, Debug_Dump, Draw_It stubs
- [ ] Write unit tests for BulletClass

### BulletTypeClass (`src/objects/types/bullettype.lua`) - COMPLETE
Audit reveals extensive implementation (506 lines):
- [x] Implement all 19 bullet types from original via factory:
  - SNIPER, BULLET, APDS, HE, SSM, SSM2, SAM, TOW, FLAME, CHEMSPRAY
  - NAPALM, GRENADE, LASER, NUKE_UP, NUKE_DOWN, HONEST_JOHN, SPREADFIRE
  - HEADBUTT, TREXBITE
- [x] Implement all flags: IsHigh, IsArcing, IsHoming, IsDropping, IsInvisible
  - IsProximityArmed, IsFlameEquipped, IsFueled, IsFaceless, IsInaccurate
  - IsTranslucent, IsAntiAircraft
- [x] Implement MaxSpeed, Warhead, Explosion, ROT, Arming, Range fields
- [x] Implement `Create(type)` factory method
- [x] Implement query functions: Is_Arcing, Is_Homing, Is_Invisible, etc.

### AnimClass (`src/objects/anim.lua`) - COMPLETE
Audit reveals extensive implementation (660 lines):
- [x] Implement all fields from ANIM.H
  - [x] `Class` (AnimTypeClass)
  - [x] `Object` (attached object for following)
  - [x] `AttachOffset` (offset from attached object)
  - [x] `State` (DELAY/PLAYING/LOOPING/FINISHED)
  - [x] `LoopsRemaining` (loop count)
  - [x] `DelayTimer` (initial delay)
  - [x] `DamageAccum` (accumulated damage for attached)
- [x] Implement `AI()` - full animation state machine
- [x] Implement animation attachment to objects
- [x] Implement `Complete_Animation()` - handles chaining and effects
- [x] Implement StageClass mixin for frame management
- [x] Implement `Attach_To(object)` / `Detach_From()`
- [x] Implement ground effects (scorch marks, craters)
- [x] Implement damage over time to attached objects
- [x] Implement animation chaining to next animation
- [x] Implement RTTI, Debug_Dump, Code_Pointers
- [ ] Write unit tests for AnimClass

### AnimTypeClass (`src/objects/types/animtype.lua`) - COMPLETE
Audit reveals extensive implementation (566 lines):
- [x] Implement all 75+ animation types from original via factory:
  - Explosions: FBALL1, GRENADE, FRAG1/2, VEH_HIT1/2/3, ART_EXP1, NAPALM1/2/3
  - Impacts: SMOKE_PUFF, PIFF, PIFFPIFF
  - Directional: FLAME_N-NW (8 dirs), CHEM_N-NW, SAM_N-NW, GUN_N-NW (8 dirs each)
  - Fires: FIRE_SMALL/MED/MED2/TINY, BURN_SMALL/MED/BIG, ON_FIRE_*
  - Infantry deaths, ION_CANNON, ATOM_BLAST, and more
- [x] Implement animation frame data (StartFrame, Stages, Loops)
- [x] Implement animation timing (Delay, Rate)
- [x] Implement ground effects (MakesScorchMark, MakesCrater)
- [x] Implement chaining (ChainTo)
- [x] Implement `Create(type)` factory method

### WeaponTypeClass (`src/combat/weapon.lua`) - COMPLETE
Audit reveals extensive implementation (498 lines):
- [x] Implement all weapon attributes: Attack, ROF, Range, Fires, Sound, Anim
- [x] Implement all 25 weapon types via factory:
  - RIFLE, CHAIN_GUN, PISTOL, M16, DRAGON, FLAMETHROWER, FLAME_TONGUE
  - CHEMSPRAY, GRENADE, 75MM/105MM/120MM, TURRET_GUN, MAMMOTH_TUSK
  - MLRS, 155MM, M60MG, TOMAHAWK, TOW_TWO, NAPALM, OBELISK_LASER
  - NIKE, HONEST_JOHN, STEG, TREX
- [x] Implement `Get(type)` lookup and `Create(type)` factory
- [x] Implement query functions: Range_In_Cells, Is_Anti_Aircraft

### WarheadTypeClass (`src/combat/warhead.lua`) - COMPLETE
Audit reveals extensive implementation (417 lines):
- [x] Implement all warhead attributes: SpreadFactor, wall/tiberium destruction flags
- [x] Implement Modifier array for armor damage multipliers
- [x] Implement ArmorType enum (NONE, WOOD, ALUMINUM, STEEL, CONCRETE)
- [x] Implement all 12 warhead types via factory:
  - SA, HE, AP, FIRE, LASER, PB, FIST, FOOT, HOLLOW_POINT, SPORE, HEADBUTT, FEEDME
- [x] Implement `Modify_Damage(base, armor)` - integer armor calculation
- [x] Implement `Distance_Damage(base, distance)` - falloff calculation
- [x] Implement `Get(type)` and `Create(type)` factory
Note: Armor enum is in WarheadTypeClass, not separate armor.lua file

### Combat Module (`src/combat/combat.lua`) - COMPLETE
Audit reveals implementation (260 lines):
- [x] Implement `Explosion_Damage(coord, strength, source, warhead)`
  - Scans 9-cell area for objects via Globals heap
  - Applies distance-based damage via Take_Damage
  - Handles wall/tiberium destruction effects (stubs)
- [x] Implement `Do_Explosion(coord, strength, source, warhead, anim)`
  - Spawns explosion animation
  - Calls Explosion_Damage
- [x] Implement `Distance_Modify(damage, distance, warhead)`
- [ ] Implement `Destroy_Tiberium()` cell integration (stub)
- [ ] Implement `Destroy_Wall()` cell integration (stub)

### Combat Integration (in TechnoClass) - COMPLETE
- [x] Implement `Fire_At()` spawning bullets (techno.lua:920-1050)
- [x] Implement rearm timing via `Arm` field and `Rearm_Delay()`
- [x] Implement weapon cycling (primary/secondary via `which` parameter)
- [x] Implement range checking via `In_Range()` and `Weapon_Range()`
- [x] Implement `Take_Damage()` with armor and warhead (object.lua)
- [x] Implement damage result states via Strength tracking
- [x] Implement `Record_The_Kill()` in TechnoClass
- [x] Implement kill credit via `Payback` pointer on bullets

### Pathfinding (`src/pathfinding/findpath.lua`) - COMPLETE
Audit reveals extensive implementation (793 lines):
- [x] Port FINDPATH.CPP algorithm exactly (LOS + edge following)
- [x] Implement `PathType` structure (Start, Cost, Length, Command, Overlap)
- [x] Implement `Find_Path()` main function with both directions
- [x] Implement `Follow_Edge()` edge-following (clockwise/counter-clockwise)
- [x] Implement `Register_Cell()` path recording with loop detection
- [x] Implement path management: `clear_all_overlap()`, path truncation
- [x] Implement movement cost calculation via `passable_cell()`
- [x] Implement passable_callback for custom passability
- [x] Implement path length limits (MAX_MLIST_SIZE=300, MAX_PATH_EDGE_FOLLOW=400)
- [x] Implement path failure handling (loop detection, max cells)
- [x] Implement coordinate-based interface: `find_path_coords()`
- [x] Implement `get_path_facings()` for FootClass (CONQUER_PATH_MAX=9)
- [x] Implement `optimize_path()` for path smoothing
- [x] Implement `Debug_Dump_Path()` for debugging
- [ ] Implement threat avoidance in pathfinding (deferred)
- [ ] Write pathfinding unit tests
- [ ] Write pathfinding integration tests

### Debug Overlays (Combat)
- [ ] Implement weapon range visualization
- [ ] Implement projectile trajectory visualization
- [ ] Implement damage number popups
- [ ] Implement threat map visualization
- [ ] Implement pathfinding visualization
Note: Combat system is functionally complete for gameplay. Debug overlays are deferred.

---

## Phase 4: Economy & Production - MOSTLY COMPLETE

### HouseClass (`src/house/house.lua`) - COMPLETE
Audit reveals extensive implementation (1243 lines):
- [x] Implement all fields from HOUSE.H
  - [x] `type` / `name` / `side` - house identity
  - [x] `allies` / `enemies` - diplomacy tables
  - [x] `credits` / `tiberium` / `credits_capacity` - economy
  - [x] `power_output` / `power_drain` / `has_power` - power system
  - [x] `Build_Unit` / `Build_Infantry` / `Build_Aircraft` / `Build_Structure` - production methods
  - [x] `units` / `buildings` / `aircraft` - entity tracking lists
  - [x] `owned_building_types` - prerequisite tracking
  - [x] `radar_active` - radar state
  - [x] `is_human` / `is_player` / `is_defeated` - state flags
  - [x] `stats` - statistics tracking (units_built, units_lost, etc.)
  - [x] `cost_bias` / `build_time_bias` - production modifiers
  - [x] `tech_level` - tech tree level
- [x] Implement `update()` - house per-tick logic (factories, special weapons, radar)
- [x] Implement `Spend_Money(amount)` - deduct from tiberium first, then credits
- [x] Implement `Refund_Money(amount)` - add credits back
- [x] Implement `Available_Money()` - credits + tiberium total
- [x] Implement `Harvested(amount)` - add tiberium with capacity cap
- [x] Implement `get_power_ratio()` / `is_low_power()` - power fraction
- [x] Implement `is_ally(house)` / `is_enemy(house)` - alliance check
- [x] Implement `set_ally(house)` / `set_enemy(house)` - diplomacy control
- [x] Implement `meets_prerequisites()` - tech tree check via owned_building_types
- [x] Implement special weapon system:
  - [x] ion_cannon, nuke, airstrike tracking
  - [x] `update_special_weapons(dt)` - charge accumulation
  - [x] `use_special_weapon(name)` - activate and reset charge
  - [x] `get_special_weapon_charge(name)` - percentage query
- [x] Implement `Adjust_Capacity(adjust, in_anger)` - silo management
- [x] Implement `Silo_Redraw_Check()` - visual update tracking
- [x] Implement entity management: add_unit, remove_unit, add_building, remove_building
- [x] Implement `check_special_buildings()` - radar, ion cannon, nuke, airstrike detection
- [x] Implement `update_primary_factories()` - auto-assign primary buildings
- [x] Implement `check_defeat()` - victory/defeat condition check
- [x] Implement serialize/deserialize for save/load
- [x] Implement `Debug_Dump()` with full state output
- [ ] Write unit tests for HouseClass
Note: House.TYPE enum provides all house types (GOOD/BAD/NEUTRAL/JP/MULTI1-6). House colors via COLORS enum.

### HouseTypeClass (`src/house/house_type.lua`)
- [x] House types defined in House.TYPE enum (10 types)
- [x] House colors in House.COLORS enum (6 colors)
- [x] Side affiliations in House.SIDE enum (GDI/NOD/NEUTRAL/SPECIAL)
- [x] `get_name_for_type()` - type to name lookup
- [x] `get_side_for_type()` - type to faction lookup
- [x] `get_default_color()` - type to color lookup
- [ ] Starting units/buildings (scenario-specific, handled by scenario loader)
- [ ] Load house data from data files (deferred - factory methods provide data)
Note: Type data is embedded in HouseClass rather than separate HouseTypeClass file

### FactoryClass (`src/production/factory.lua`) - COMPLETE
Audit reveals extensive implementation (605 lines):
- [x] Implement all fields from FACTORY.H
  - [x] `Object` (TechnoClass being built) / `ObjectType` (TechnoTypeClass)
  - [x] `House` (owning HouseClass)
  - [x] `SpecialItem` (SPECIAL enum: NONE/ION_CANNON/NUKE/AIR_STRIKE)
  - [x] `IsSuspended` / `IsDifferent` / `IsBlocked` - state flags
  - [x] `Balance` / `OriginalBalance` - cost tracking
  - [x] `Stage` / `StageTimer` / `Rate` - StageClass fields
- [x] Implement `AI()` - production tick with power-based slowdown and multi-factory acceleration
- [x] Implement `Set(type, house)` - start production with cost calculation
- [x] Implement `Set_Special(type, house)` - special weapon production
- [x] Implement `Set_Object(object)` - return completed object to factory
- [x] Implement `Start()` - resume production with affordability check
- [x] Implement `Suspend()` - pause production
- [x] Implement `Abandon()` - cancel with refund
- [x] Implement `Completed()` - clear factory after placement
- [x] Implement `Has_Completed()` - check if stage == STEP_COUNT (108)
- [x] Implement `Completion()` / `Completion_Percent()` - progress percentage
- [x] Implement `Cost_Per_Tick()` - installment cost calculation
- [x] Implement `Is_Building()` / `Is_Blocked()` - state queries
- [x] Implement StageClass methods: Fetch_Stage, Set_Stage, Fetch_Rate, Set_Rate, Graphic_Logic
- [x] Implement power-based production slowdown (power_ratio < 1.0 slows production)
- [x] Implement multi-factory acceleration (more factories = faster production)
- [x] Implement `Force_Complete()` - debug/testing instant completion
- [x] Implement `Code_Pointers()` / `Decode_Pointers()` - save/load
- [x] Implement `Debug_Dump()` with production state
- [ ] Write unit tests for FactoryClass
Note: STEP_COUNT=108 matches original C&C production stages

### Tiberium System - COMPLETE (across multiple files)
Implementation distributed across CellClass, Grid, UnitClass:
- [x] CellClass tiberium overlay - `overlay` field with OVERLAY constants
- [x] Tiberium value per cell - `overlay_data` field (0-11 stages)
- [x] `Cell:has_tiberium()` / `Cell:get_tiberium_value()` - queries
- [x] `Cell:grow_tiberium()` - increase stage
- [x] `Cell:harvest_tiberium(amount)` - reduce tiberium with value return
- [x] `Grid:Logic()` - tiberium growth/spread per tick:
  - [x] Forward/backward scan alternation (match original)
  - [x] Growth stage increase for existing tiberium
  - [x] Spread to adjacent cells from heavy tiberium (stage 7+)
  - [x] Blossom tree detection (terrain_object.is_tiberium_spawn)
  - [x] Fast mode for double growth rate
- [x] UnitClass harvester `Mission_Harvest()` - full 5-state machine:
  - [x] LOOKING - find tiberium via Find_Tiberium() spiral search
  - [x] HARVESTING - collect via Harvesting() with timer
  - [x] FINDHOME - find refinery via Find_Refinery() with radio contact
  - [x] HEADINGHOME - navigate to refinery
  - [x] GOINGTOIDLE - transition to idle after unload
- [x] UnitClass tiberium capacity - `Tiberium_Load()`, `Is_Full()`, `Is_Empty()`
- [x] UnitClass `On_Tiberium()` - cell query
- [x] UnitClass `Offload_Tiberium_Bail()` - unload at refinery
- [x] HouseClass `Harvested(amount)` - credits from tiberium with capacity cap
- [x] HouseClass `Adjust_Capacity()` - silo management
- [x] BuildingClass refinery docking via `Receive_Message()` RADIO protocol
- [x] BuildingClass Mission_Harvest - refinery processing (5 states)
- [ ] Write tiberium integration tests
Note: Tiberium stages 0-11 matching original; credits calculated from stage value

### Power System - COMPLETE (across HouseClass and BuildingClass)
- [x] BuildingTypeClass `PowerOutput` / `PowerDrain` - per building type
- [x] BuildingClass `Power_Output()` - with damage scaling
- [x] BuildingClass `Power_Drain()` - operational drain
- [x] BuildingClass `Has_Power()` / `Power_Efficiency()` - power queries
- [x] HouseClass `update_power()` - sum power from all buildings
- [x] HouseClass `get_power_ratio()` - output/drain ratio
- [x] HouseClass `is_low_power()` / `has_power` - status queries
- [x] Low power effects:
  - [x] FactoryClass AI() slows production based on power_ratio
  - [x] HouseClass `update_radar()` disables radar when low power
  - [x] BuildingClass `Can_Operate()` checks power status
- [ ] Implement power bar UI element (UI not yet implemented)
- [x] Power plant destruction effects - HouseClass update_power() recalculates
- [ ] Write power system tests
Note: Power ratio < 1.0 proportionally slows production; ratio <= 0 stops production

### Building Placement - MOSTLY COMPLETE (in BuildingClass and Grid)
- [ ] Implement building ghost/preview (UI layer)
- [x] `BuildingClass.Can_Place_Building(type, cell, house)` - full validation (static)
- [x] `BuildingClass.Is_Adjacent_To_Building(cell, house)` - adjacency check (static)
- [x] `BuildingClass.Get_Valid_Placement_Cells(type, house)` - find all valid cells (static)
- [x] `Grid:can_place_building(cx, cy, width, height)` - foundation fit checking
- [x] `Grid:can_place_building_type(building_type, cx, cy)` - building-specific rules
- [x] Terrain passability in Grid passability checks
- [x] BuildingClass `Mission_Construction()` - full construction state machine
- [x] BuildingClass `Grand_Opening()` - activation after construction
- [ ] Implement bib placement (visual layer)
- [ ] Write placement tests
Note: Core placement logic complete; UI preview/ghost is rendering layer concern

### Sell/Repair - COMPLETE (in BuildingClass)
- [ ] Implement sell cursor (UI layer)
- [ ] Implement sell confirmation (UI layer)
- [x] BuildingClass `Sell_Back()` - initiate sell with Mission_Deconstruction
- [x] BuildingClass `Complete_Sell()` - credit refund calculation
- [x] BuildingClass `Update_Sell()` - progress tracking
- [x] BuildingClass `Mission_Deconstruction()` - full sell state machine with survivor spawning
- [x] `Spawn_Survivors()` - unit evacuation on sell
- [ ] Implement repair cursor (UI layer)
- [x] BuildingClass `Can_Repair()` / `Start_Repair()` / `Stop_Repair()` / `Process_Repair()`
- [x] Repair cost calculation in BuildingTypeClass `Repair_Cost()` / `Repair_Step()`
- [x] BuildingClass `Mission_Repair()` - repair facility and helipad behavior
- [ ] Implement repair animation/wrench (visual layer)
- [ ] Write sell/repair tests
Note: Core sell/repair logic complete; cursors/animations are UI/visual layer

### MCV Deployment - COMPLETE (in UnitClass)
- [x] UnitClass `Can_Deploy()` - deployment validity check
- [x] UnitClass `Deploy()` - start deployment timer
- [x] UnitClass `Complete_Deploy()` - create Construction Yard building
- [x] UnitTypeClass `IsDeployable` / `DeployBuilding` - MCV type data
- [ ] Construction Yard undeploy (not in original TD)
- [ ] Write MCV tests
Note: MCV deployment fully functional; undeploy was Red Alert feature

### Sidebar UI (`src/ui/sidebar.lua`)
- [ ] Implement sidebar structure (classic 320x200)
- [ ] Implement HD-ready scalable version
- [ ] Implement structure build icons
- [ ] Implement unit build icons
- [ ] Implement production progress bars
- [ ] Implement production cancellation
- [ ] Implement icon click handling
- [ ] Implement icon tooltip/info
- [ ] Implement sell button
- [ ] Implement repair button
- [ ] Implement map button
- [ ] Write sidebar tests
Note: Sidebar UI not yet implemented - backend production system is complete

### EVA Voice System
- [ ] Implement EVA trigger system
- [ ] Implement "Construction complete"
- [ ] Implement "Building"
- [ ] Implement "Unit ready"
- [ ] Implement "Unit lost"
- [ ] Implement "Building lost"
- [ ] Implement "Our base is under attack"
- [ ] Implement "Ion cannon ready"
- [ ] Implement "Nuclear strike available"
- [ ] Implement "Insufficient funds"
- [ ] Implement "Cannot deploy here"
- [ ] Implement audio queue management
- [ ] Write EVA tests
Note: EVA voice system not yet implemented - Events system provides hooks

---

## Phase 5: AI, Triggers & Teams

### TriggerClass (`src/scenario/trigger.lua`)
- [ ] Implement all fields from TRIGGER.H
  - [ ] `Event` (TriggerEventType)
  - [ ] `Action` (TriggerActionType)
  - [ ] `House` (associated house)
  - [ ] `Data` (event-specific data)
  - [ ] `IsPersistent` (repeating trigger)
- [ ] Implement trigger attachment to objects
- [ ] Implement trigger attachment to cells
- [ ] Implement all event types:
  - [ ] Entered by
  - [ ] Spied by
  - [ ] Discovered by
  - [ ] Time elapsed
  - [ ] Credits below
  - [ ] Destroyed/Killed
  - [ ] Buildings destroyed
  - [ ] Units destroyed
  - [ ] All destroyed
  - [ ] No factories
  - [ ] Civilian evacuated
  - [ ] Build type
  - [ ] Build infantry
  - [ ] Build unit
  - [ ] Build aircraft
  - [ ] Leaves map
  - [ ] Entered zone
  - [ ] Crossed horizontal
  - [ ] Crossed vertical
  - [ ] Global set
  - [ ] Global clear
  - [ ] Low power
  - [ ] Bridge destroyed
  - [ ] Building exists
- [ ] Implement all action types:
  - [ ] Win
  - [ ] Lose
  - [ ] Begin production
  - [ ] Create team
  - [ ] Destroy team
  - [ ] All hunt
  - [ ] Reinforcement
  - [ ] Drop zone flare
  - [ ] Fire sale
  - [ ] Play movie
  - [ ] Text message
  - [ ] Destroy trigger
  - [ ] Autocreate
  - [ ] Destroy all
  - [ ] Allow win
  - [ ] Reveal all
  - [ ] Reveal zone
  - [ ] Play sound
  - [ ] Play music
  - [ ] Play speech
  - [ ] Force trigger
  - [ ] Timer start
  - [ ] Timer stop
  - [ ] Timer extend
  - [ ] Timer shorten
  - [ ] Timer set
  - [ ] Global set
  - [ ] Global clear
  - [ ] Set airstrike
  - [ ] Set nuke strike
  - [ ] Set ion cannon
- [ ] Write trigger unit tests
- [ ] Write trigger integration tests

### TeamClass (`src/scenario/team.lua`)
- [ ] Implement all fields from TEAM.H
  - [ ] `Class` (TeamTypeClass)
  - [ ] `House` (owning house)
  - [ ] `Members` (object list)
  - [ ] `Target` (team target)
  - [ ] `Center` (formation center)
  - [ ] `IsUnderStrength` / `IsFullStrength`
  - [ ] `IsAltered` / `IsMoving` / `IsReforming`
  - [ ] `Quantity` (member count)
  - [ ] `Risk` / `Zone`
- [ ] Implement `AI()` - team logic
- [ ] Implement team formation
- [ ] Implement team movement coordination
- [ ] Implement team attack coordination
- [ ] Implement team mission execution
- [ ] Implement team reinforcement (adding members)
- [ ] Implement team dissolution
- [ ] Write team tests

### TeamTypeClass (`src/scenario/team_type.lua`)
- [ ] Implement team composition lists
- [ ] Implement team mission queues
- [ ] Implement team priority
- [ ] Implement team waypoints
- [ ] Load team types from scenario files

### AI Controller
- [ ] Implement AI base building logic
- [ ] Implement AI unit production priorities
- [ ] Implement AI attack team creation
- [ ] Implement AI threat evaluation
- [ ] Implement AI target prioritization
- [ ] Implement AI resource management
- [ ] Implement AI defense placement
- [ ] Replicate original AI quirks exactly
- [ ] Write AI unit tests
- [ ] Write AI integration tests

### Scenario Loading (`src/scenario/scenario.lua`)
- [ ] Implement INI file parser
- [ ] Implement BIN file parser (map data)
- [ ] Parse [Basic] section
- [ ] Parse [Map] section
- [ ] Parse [Waypoints] section
- [ ] Parse [CellTriggers] section
- [ ] Parse [TeamTypes] section
- [ ] Parse [Triggers] section
- [ ] Parse [Infantry] section
- [ ] Parse [Units] section
- [ ] Parse [Aircraft] section
- [ ] Parse [Structures] section
- [ ] Parse [Reinforcements] section
- [ ] Parse [Base] section
- [ ] Implement map terrain loading
- [ ] Implement object placement
- [ ] Implement player starting position
- [ ] Write scenario loading tests

### Mission Briefing
- [ ] Implement briefing text display
- [ ] Implement briefing background
- [ ] Implement mission objectives
- [ ] Implement briefing audio

### Victory/Defeat Conditions
- [ ] Implement win condition checking
- [ ] Implement lose condition checking
- [ ] Implement score calculation
- [ ] Implement mission end sequence
- [ ] Implement campaign progression

---

## Phase 6: Network & Polish

### EventClass (`src/network/event.lua`)
- [ ] Implement all EventType variants from EVENT.H
- [ ] Implement event encoding to bytes
- [ ] Implement event decoding from bytes
- [ ] Implement event timestamp
- [ ] Implement event CRC
- [ ] Implement all event types:
  - [ ] MEGAMISSION
  - [ ] MEGAMISSION_F
  - [ ] IDLE
  - [ ] SCATTER
  - [ ] DESTRUCT
  - [ ] DEPLOY
  - [ ] PLACE
  - [ ] OPTIONS
  - [ ] GAMESPEED
  - [ ] PRODUCE
  - [ ] SUSPEND
  - [ ] ABANDON
  - [ ] PRIMARY
  - [ ] SPECIAL_PLACE
  - [ ] EXIT
  - [ ] ANIMATION
  - [ ] REPAIR
  - [ ] SELL
  - [ ] SELLCELL
  - [ ] SPECIAL
  - [ ] FRAMEINFO
  - [ ] TIMING
  - [ ] PROCESS_TIME
  - [ ] RESPONSE_TIME
  - [ ] FRAMESYNC
  - [ ] MESSAGE
  - [ ] SAVEGAME
  - [ ] ARCHIVE
  - [ ] ADDPLAYER
  - [ ] DELPLAYER

### Lockstep System (`src/network/lockstep.lua`)
- [ ] Implement frame synchronization
- [ ] Implement input collection per frame
- [ ] Implement input distribution
- [ ] Implement frame CRC calculation
- [ ] Implement desync detection
- [ ] Implement network latency handling
- [ ] Implement input delay buffer
- [ ] Implement catchup mechanism
- [ ] Write lockstep tests

### Session Management (`src/network/session.lua`)
- [ ] Implement SessionClass
- [ ] Implement player slot management
- [ ] Implement lobby state
- [ ] Implement ready checking
- [ ] Implement game start synchronization
- [ ] Implement player color assignment
- [ ] Implement disconnect handling

### Networking Transport
- [ ] Implement TCP connection (lobby)
- [ ] Implement UDP for game events
- [ ] Implement packet ordering
- [ ] Implement packet acknowledgment
- [ ] Implement reconnection handling

### Superweapons
- [ ] Implement Ion Cannon
  - [ ] Charge timer
  - [ ] Target selection cursor
  - [ ] Firing animation
  - [ ] Damage application
- [ ] Implement Nuclear Strike
  - [ ] Charge timer
  - [ ] Target selection
  - [ ] Missile flight
  - [ ] Explosion/damage
  - [ ] Radiation effect
- [ ] Implement Airstrike
  - [ ] Charge timer
  - [ ] Target selection
  - [ ] A-10 spawning
  - [ ] Strafing run
- [ ] Write superweapon tests

### Fog of War (`src/map/shroud.lua`)
- [ ] Implement shroud (never seen) state
- [ ] Implement fog (previously seen) state
- [ ] Implement sight range per unit type
- [ ] Implement sight update on unit move
- [ ] Implement shroud graphics
- [ ] Implement fog graphics
- [ ] Implement radar fog sync
- [ ] Implement building reveal on construction
- [ ] Write fog of war tests

### Cloaking System
- [ ] Implement cloak state machine
- [ ] Implement cloak charging timer
- [ ] Implement cloak shimmer effect
- [ ] Implement decloak on firing
- [ ] Implement decloak on damage
- [ ] Implement detection by adjacent units
- [ ] Implement stealth tank behavior
- [ ] Write cloaking tests

### Adapter: HD Graphics (`src/adapters/hd_graphics.lua`)
- [ ] Implement HD asset loading
- [ ] Implement sprite scale switching
- [ ] Implement UI scale switching
- [ ] Implement resolution-independent rendering
- [ ] Implement HD toggle at runtime

### Adapter: Controller (`src/adapters/controller.lua`)
- [ ] Implement controller detection
- [ ] Implement virtual cursor movement
- [ ] Implement radial menu for commands
- [ ] Implement controller button mapping
- [ ] Implement stick acceleration

### Adapter: Rebindable Hotkeys (`src/adapters/hotkeys.lua`)
- [ ] Implement keybind configuration
- [ ] Implement keybind persistence
- [ ] Implement keybind UI
- [ ] Implement default presets

### Adapter: Remastered Audio (`src/adapters/remastered_audio.lua`)
- [ ] Implement audio asset switching
- [ ] Implement audio format handling
- [ ] Implement audio toggle at runtime

### Replay System
- [ ] Implement input recording
- [ ] Implement input playback
- [ ] Implement replay file format
- [ ] Implement replay file saving
- [ ] Implement replay file loading
- [ ] Implement replay verification (CRC)
- [ ] Write replay tests

### Debug Support
- [ ] Complete `Debug_Dump()` for all classes
- [ ] Implement MonoClass logging output
- [ ] Implement cheat commands:
  - [ ] Reveal map
  - [ ] Instant build
  - [ ] Free units
  - [ ] God mode
  - [ ] Add credits
  - [ ] Win/Lose instant
- [ ] Implement debug menu toggle

---

## Testing Infrastructure

### Unit Tests
- [ ] Set up Lua testing framework (busted or similar)
- [ ] Write tests for all utility functions
- [ ] Write tests for all type classes
- [ ] Write tests for COORDINATE operations
- [ ] Write tests for CELL operations
- [ ] Write tests for TARGET operations
- [ ] Write tests for RNG sequences

### Integration Tests
- [ ] Write combat damage integration tests
- [ ] Write pathfinding integration tests
- [ ] Write production queue tests
- [ ] Write tiberium economy tests
- [ ] Write trigger/event tests
- [ ] Write AI behavior tests

### Replay Verification Tests
- [ ] Create determinism test suite
- [ ] Record reference replays
- [ ] Implement CRC comparison
- [ ] Implement divergence detection

### Performance Tests
- [ ] Implement frame time measurement
- [ ] Test with 500+ entities
- [ ] Test pathfinding performance
- [ ] Test rendering performance
- [ ] Profile memory usage

---

## Asset Pipeline

### MIX Extraction Tools (`tools/mix_extractor/`)
- [ ] Verify MIX extractor functionality
- [ ] Extract CONQUER.MIX (unit sprites)
- [ ] Extract TEMPERAT.MIX (terrain)
- [ ] Extract WINTER.MIX (terrain)
- [ ] Extract DESERT.MIX (terrain)
- [ ] Extract SOUNDS.MIX (SFX)
- [ ] Extract SPEECH.MIX (EVA)
- [ ] Extract SCORES.MIX (music)
- [ ] Document extraction process

### Sprite Conversion (`tools/sprite_converter/`)
- [ ] Convert SHP to PNG
- [ ] Handle palette application
- [ ] Generate sprite sheets
- [ ] Generate animation metadata

### Audio Conversion (`tools/audio_converter/`)
- [ ] Convert AUD to OGG/WAV
- [ ] Handle sample rate conversion
- [ ] Generate audio metadata

### Data File Population
- [ ] Populate `data/units/infantry.json`
- [ ] Populate `data/units/vehicles.json`
- [ ] Populate `data/units/aircraft.json`
- [ ] Populate `data/buildings/structures.json`
- [ ] Populate `data/buildings/walls.json`
- [ ] Populate `data/weapons/weapons.json`
- [ ] Populate `data/weapons/warheads.json`
- [ ] Populate `data/weapons/projectiles.json`
- [ ] Populate `data/houses/factions.json`
- [ ] Populate `data/houses/tech_trees.json`
- [ ] Populate `data/audio/themes.json`
- [ ] Populate `data/audio/sounds.json`

---

## Documentation

- [ ] Update PLAN.md as implementation progresses
- [ ] Maintain PROGRESS.md task tracking
- [ ] Document NOTES.md with learnings
- [ ] Document API for each class
- [ ] Document data file formats
- [ ] Document build/run instructions
- [ ] Document testing procedures
- [ ] Document asset extraction process
