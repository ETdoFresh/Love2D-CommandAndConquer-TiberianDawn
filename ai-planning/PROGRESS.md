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

### HeapClass Object Pools (`src/heap/`)
- [x] Implement `HeapClass` with fixed-size pools (heap.lua)
- [x] Implement pool allocation with hard error on exhaustion
- [x] Implement pool deallocation (return to pool)
- [x] Implement heap index tracking for objects
- [x] Implement `Active_Ptr()` - get object by heap index (Get())
- [x] Implement pool iteration (`For_Each()`) (Active_Objects())
- [x] Define pool limits for all object types (LIMITS table)
- [x] Implement `globals.lua` with global object arrays
- [x] Write unit tests for HeapClass (test_class_hierarchy.lua)
Note: Individual heaps are created lazily via Globals.Register_Heap() when game initializes

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

### Constants & Defines (`src/core/`)
- [ ] Port all enums from DEFINES.H to `defines.lua`
- [ ] Implement `MissionType` enum (MISSION_SLEEP, MISSION_ATTACK, etc.)
- [ ] Implement `RadioMessageType` enum
- [ ] Implement `SpeedType` enum (SPEED_FOOT, SPEED_TRACK, etc.)
- [ ] Implement `ArmorType` enum
- [ ] Implement `WarheadType` enum
- [ ] Implement `RTTIType` enum
- [ ] Implement `ActionType` enum (for cursor/order)
- [ ] Implement `FacingType` enum (8 directions)
- [ ] Implement `DirType` enum (256 directions)
- [ ] Implement `MarkType` enum (MARK_UP, MARK_DOWN, etc.)
- [ ] Implement `ThreatType` bitflags
- [ ] Implement `HousesType` enum (GDI, NOD, etc.)
- [ ] Implement `TheaterType` enum
- [ ] Implement game constants (CELL_SIZE, TICKS_PER_SECOND, etc.)
- [ ] Write validation tests for enum values

### AbstractClass (`src/objects/abstract.lua`)
- [ ] Implement all fields from ABSTRACT.H
  - [ ] `Coord` (COORDINATE)
  - [ ] `IsActive` (bool)
  - [ ] `IsRecentlyCreated` (bool)
  - [ ] `HeapID` (int)
- [ ] Implement `AI()` - per-tick logic (virtual)
- [ ] Implement `Center_Coord()` - center coordinate
- [ ] Implement `Target_Coord()` - targeting coordinate
- [ ] Implement `Entry_Coord()` - entry point coordinate
- [ ] Implement `Exit_Coord()` - exit point coordinate
- [ ] Implement `Sort_Y()` - Y coordinate for rendering sort
- [ ] Implement `Distance(target)` - distance to target
- [ ] Implement `Direction(target)` - direction to target
- [ ] Implement `As_Target()` - convert to TARGET
- [ ] Implement `Owner()` - owning house (virtual)
- [ ] Implement `Debug_Dump()` - debug output
- [ ] Implement `Code_Pointers()` - serialization
- [ ] Implement `Decode_Pointers()` - deserialization
- [ ] Write unit tests for AbstractClass

### ObjectClass (`src/objects/object.lua`)
- [ ] Implement all fields from OBJECT.H
  - [ ] `Class` (pointer to type class)
  - [ ] `Next` (linked list pointer)
  - [ ] `Trigger` (attached trigger)
  - [ ] `Strength` (current health)
  - [ ] `IsDown` (on map flag)
  - [ ] `IsToDamage` (pending damage)
  - [ ] `IsToDisplay` (needs redraw)
  - [ ] `IsInLimbo` (in limbo state)
  - [ ] `IsSelected` (selected flag)
  - [ ] `IsAnimAttached` (has animation)
  - [ ] `IsFalling` (falling from transport)
  - [ ] `SelectedMask` (which players have selected)
- [ ] Implement `AI()` - call parent, object-specific logic
- [ ] Implement `Limbo()` - remove from map
- [ ] Implement `Unlimbo(coord, facing)` - place on map
- [ ] Implement `Mark(mark_type)` - mark cells for redraw
- [ ] Implement `Render(forced)` - draw object
- [ ] Implement `Take_Damage(damage, distance, warhead, source)` - receive damage
- [ ] Implement `Receive_Damage(damage, distance, warhead, source)` - after armor
- [ ] Implement `Select()` - select object
- [ ] Implement `Unselect()` - deselect object
- [ ] Implement `What_Action(object)` - cursor for target object
- [ ] Implement `What_Action(cell)` - cursor for target cell
- [ ] Implement `Active_Click_With(action, object)` - handle click on object
- [ ] Implement `Active_Click_With(action, cell)` - handle click on cell
- [ ] Implement `Per_Cell_Process(why)` - per-cell entry logic
- [ ] Implement `Clicked_As_Target(count)` - flash when targeted
- [ ] Implement `In_Which_Layer()` - render layer
- [ ] Implement `Record_The_Kill(source)` - track kills
- [ ] Implement `Look(incremental)` - reveal shroud
- [ ] Implement `Fire_Out()` - fire damage logic
- [ ] Implement `Repair(step)` - repair logic
- [ ] Implement `Sell_Back(percent)` - sell refund
- [ ] Write unit tests for ObjectClass

### MissionClass (`src/objects/mission.lua`)
- [ ] Implement all fields from MISSION.H
  - [ ] `Mission` (current MissionType)
  - [ ] `SuspendedMission` (saved mission)
  - [ ] `MissionQueue` (pending mission)
  - [ ] `Status` (mission substep)
  - [ ] `Timer` (mission timer)
- [ ] Implement `AI()` - mission state machine
- [ ] Implement `Assign_Mission(mission)` - set new mission
- [ ] Implement `Get_Mission()` - get current mission
- [ ] Implement `Commence()` - start mission execution
- [ ] Implement `Override_Mission(mission, tarcom, navcom)` - interrupt mission
- [ ] Implement `Restore_Mission()` - restore suspended mission
- [ ] Implement `Set_Mission(mission)` - internal mission set
- [ ] Implement all `Mission_X()` virtual methods:
  - [ ] `Mission_Sleep()`
  - [ ] `Mission_Attack()`
  - [ ] `Mission_Move()`
  - [ ] `Mission_Retreat()`
  - [ ] `Mission_Guard()`
  - [ ] `Mission_Sticky()`
  - [ ] `Mission_Enter()`
  - [ ] `Mission_Capture()`
  - [ ] `Mission_Harvest()`
  - [ ] `Mission_Guard_Area()`
  - [ ] `Mission_Return()`
  - [ ] `Mission_Stop()`
  - [ ] `Mission_Ambush()`
  - [ ] `Mission_Hunt()`
  - [ ] `Mission_Timed_Hunt()`
  - [ ] `Mission_Unload()`
  - [ ] `Mission_Sabotage()`
  - [ ] `Mission_Construction()`
  - [ ] `Mission_Selling()`
  - [ ] `Mission_Repair()`
  - [ ] `Mission_Missile()`
- [ ] Implement `What_Mission()` - get effective mission
- [ ] Implement `MissionControl` table lookup
- [ ] Write unit tests for MissionClass

### RadioClass (`src/objects/radio.lua`)
- [ ] Implement all fields from RADIO.H
  - [ ] `Radio` (contact object)
  - [ ] `LastMessage` (last received message)
  - [ ] `Archive` (previous contact)
- [ ] Implement `Transmit_Message(message, param, to)` - send message
- [ ] Implement `Receive_Message(from, message, param)` - receive message
- [ ] Implement `In_Radio_Contact()` - has active contact
- [ ] Implement `Contact_With_Whom()` - get contact object
- [ ] Implement `Limbo()` - break contact when going to limbo
- [ ] Implement all RadioMessageType handling:
  - [ ] `RADIO_STATIC` - no-op
  - [ ] `RADIO_ROGER` - acknowledge
  - [ ] `RADIO_HELLO` - request contact
  - [ ] `RADIO_OVER_OUT` - end contact
  - [ ] `RADIO_PICK_UP` - request pickup
  - [ ] `RADIO_ATTACH` - request docking
  - [ ] `RADIO_DELIVERY` - cargo delivered
  - [ ] `RADIO_HOLD_STILL` - stop moving
  - [ ] `RADIO_UNLOADED` - cargo unloaded
  - [ ] `RADIO_UNLOAD` - request unload
  - [ ] `RADIO_NEGATIVE` - refuse
  - [ ] `RADIO_BUILDING` - structure identity
  - [ ] `RADIO_NEED_TO_MOVE` - request reposition
  - [ ] `RADIO_ON_DEPOT` - on repair depot
  - [ ] `RADIO_REPAIR_ONE_STEP` - repair tick
  - [ ] `RADIO_PREPARED` - ready for action
  - [ ] `RADIO_BACKUP_NOW` - request backup
  - [ ] `RADIO_RUN_AWAY` - flee
  - [ ] `RADIO_TETHER` - establish tether
  - [ ] `RADIO_UNTETHER` - break tether
  - [ ] `RADIO_REPAIR_CANCELLED` - repair stopped
- [ ] Write unit tests for RadioClass

### CellClass (`src/map/cell.lua`)
- [ ] Implement all fields from CELL.H
  - [ ] `CellNumber` (CELL)
  - [ ] `Overlay` (OverlayType)
  - [ ] `OverlayData` (tiberium stage, wall health)
  - [ ] `Smudge` (SmudgeType)
  - [ ] `SmudgeData` (smudge variant)
  - [ ] `Land` (LandType)
  - [ ] `Owner` (HouseType)
  - [ ] `OccupierPtr` (object linked list)
  - [ ] `OccupyList` (16 infantry slots)
  - [ ] `InfType` (infantry occupation bitfield)
  - [ ] `Flag` (cell flags: Visible, Revealed, etc.)
  - [ ] `Template` (TerrainType)
  - [ ] `Icon` (terrain icon index)
  - [ ] `TriggerPtr` (attached trigger)
- [ ] Implement `Cell_Coord()` - center coordinate
- [ ] Implement `Cell_Occupier()` - get occupying object
- [ ] Implement `Is_Clear_To_Move(speed, check_units)` - pathfinding check
- [ ] Implement `Is_Clear_To_Build(bib_coord)` - building placement check
- [ ] Implement `Occupy_Unit(obj)` - add unit to cell
- [ ] Implement `Occupy_Down(obj)` - mark cell occupied
- [ ] Implement `Occupy_Up(obj)` - mark cell unoccupied
- [ ] Implement `Get_Template_Info(x, y)` - terrain data
- [ ] Implement `Spot_Index(coord)` - infantry position index
- [ ] Implement `Closest_Free_Spot(coord)` - find free infantry spot
- [ ] Implement `Is_Bridge_Here()` - bridge detection
- [ ] Implement `Goodie_Check(obj)` - crate collection (no-op for TD)
- [ ] Implement `Cell_Techno()` - get first techno in cell
- [ ] Implement `Cell_Building()` - get building in cell
- [ ] Implement `Cell_Terrain()` - get terrain in cell
- [ ] Implement `Cell_Infantry(spot)` - get infantry at spot
- [ ] Implement `Cell_Unit()` - get unit in cell
- [ ] Implement `Adjacent_Cell(facing)` - get neighbor
- [ ] Implement `Concrete_Calc()` - concrete coverage
- [ ] Implement `Wall_Update()` - wall graphics update
- [ ] Implement `Tiberium_Adjust()` - tiberium recalculation
- [ ] Implement `Reduce_Tiberium(amount)` - harvest tiberium
- [ ] Implement `Reduce_Wall(damage)` - damage wall
- [ ] Implement `Incoming()` - threat tracking
- [ ] Implement `Redraw_Objects()` - mark for redraw
- [ ] Write unit tests for CellClass

### MapClass (`src/map/map.lua`)
- [ ] Implement 64x64 cell grid
- [ ] Implement `Cell_Ptr(cell)` - get CellClass by CELL
- [ ] Implement `Coord_Cell(coord)` - coordinate to cell
- [ ] Implement `Cell_Coord(cell)` - cell to coordinate
- [ ] Implement `In_Radar(cell)` - cell in playable area
- [ ] Implement `Close_Object(coord)` - find nearest object
- [ ] Implement `Nearby_Location(coord, speed)` - find passable cell
- [ ] Implement `Cell_Shadow(cell)` - calculate shroud
- [ ] Implement `Place_Down(cell, obj)` - place object
- [ ] Implement `Pick_Up(cell, obj)` - remove object
- [ ] Implement `Overlap_Down(cell, obj)` - render overlap
- [ ] Implement `Overlap_Up(cell, obj)` - clear overlap
- [ ] Implement map boundary handling
- [ ] Implement map size/bounds storage
- [ ] Write unit tests for MapClass

### LayerClass (`src/map/layer.lua`)
- [ ] Implement `LAYER_GROUND` for ground objects
- [ ] Implement `LAYER_AIR` for aircraft
- [ ] Implement `LAYER_TOP` for effects
- [ ] Implement `Add(obj)` - add object to layer
- [ ] Implement `Remove(obj)` - remove from layer
- [ ] Implement `Sort()` - sort by Y coordinate
- [ ] Implement `Sort_Y(obj)` - get sort key
- [ ] Implement layer rendering order
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
- [ ] Remove ECS world reference
- [ ] Implement main game tick at 15 FPS
- [ ] Implement AI() calls for all active objects
- [ ] Implement object iteration order (match original)
- [ ] Implement render loop at 60 FPS
- [ ] Implement delta time accumulator for fixed timestep
- [ ] Implement frame interpolation for smooth rendering
- [ ] Implement game pause/resume
- [ ] Implement game speed adjustment
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

### Mixin Classes (`src/objects/mixins/`)
- [ ] Implement `FlasherClass`
  - [ ] `FlashCount` field
  - [ ] `Flash()` - trigger flash
  - [ ] `Process()` - decrement counter
  - [ ] `Is_Flashing()` - check state
- [ ] Implement `StageClass`
  - [ ] `Rate` field (animation speed)
  - [ ] `Stage` field (current frame)
  - [ ] `Timer` field
  - [ ] `Set_Rate(rate)` - set animation speed
  - [ ] `Set_Stage(stage)` - set frame
  - [ ] `Graphic_Logic()` - advance animation
- [ ] Implement `CargoClass`
  - [ ] `CargoHold` array
  - [ ] `Quantity` field
  - [ ] `Attach(obj)` - add cargo
  - [ ] `Detach()` - remove cargo
  - [ ] `First_Object()` - get first cargo
  - [ ] `How_Many()` - cargo count
- [ ] Implement `DoorClass`
  - [ ] `State` field (door state)
  - [ ] `Timer` field
  - [ ] `Open_Door()` / `Close_Door()`
  - [ ] `AI()` - door animation
  - [ ] `Is_Door_Open()` / `Is_Door_Closed()`
- [ ] Implement `CrewClass`
  - [ ] `Crew_Type()` - survivor infantry type
  - [ ] Survivor generation logic
- [ ] Write unit tests for all mixins

### TechnoClass (`src/objects/techno.lua`)
- [ ] Implement all fields from TECHNO.H
  - [ ] `House` (owning HouseClass)
  - [ ] `TarCom` (TARGET - attack target)
  - [ ] `PrimaryFacing` (facing)
  - [ ] `Cloak` (cloak state)
  - [ ] `CloakDelay` (timer)
  - [ ] `Arm` (rearm countdown)
  - [ ] `Ammo` (ammunition count)
  - [ ] `IsCloakable` / `IsCloak` / `IsSensing` / `IsUseless` / etc.
  - [ ] `IsLeader` / `IsALoaner` / `IsLocked` / `IsRecoiling` / etc.
  - [ ] `IsTethered` (tethered to another object)
  - [ ] `Tiberium` (carried tiberium for harvesters)
  - [ ] `Electric` (EMP state)
  - [ ] `Price` (cost override)
- [ ] Apply all mixins (Flasher, Stage, Cargo, Door, Crew)
- [ ] Implement `AI()` - combat entity logic
- [ ] Implement `Fire_At(target, which)` - fire weapon
- [ ] Implement `Can_Fire(target, which)` - weapon readiness check
- [ ] Implement `Fire_Coord(which)` - muzzle coordinate
- [ ] Implement `Assign_Target(target)` - set TarCom
- [ ] Implement `In_Range(target, which)` - range check
- [ ] Implement `Take_Damage(damage, distance, warhead, source)`
- [ ] Implement `Captured(newowner)` - change ownership
- [ ] Implement `Greatest_Threat(threat)` - find best target
- [ ] Implement `Evaluate_Cell(threat, cell, dist, is_zone)` - threat eval
- [ ] Implement `Do_Cloak()` / `Do_Uncloak()` - cloak control
- [ ] Implement `Do_Shimmer()` - shimmer effect
- [ ] Implement `Revealed(house)` - reveal to house
- [ ] Implement `Is_Owned_By_Player()` - ownership check
- [ ] Implement `Is_Discovered_By_Player()` - visibility check
- [ ] Implement `Player_Assign_Mission(order, target, destination)`
- [ ] Implement `Response_Select()` - selection voice
- [ ] Implement `Response_Move()` - move order voice
- [ ] Implement `Response_Attack()` - attack order voice
- [ ] Implement `Combat_Damage(which)` - weapon damage value
- [ ] Implement `Weapon_Range(which)` - weapon range
- [ ] Implement `Rearm_Delay(second)` - rearm timing
- [ ] Implement `Base_Is_Attacked(source)` - base defense alert
- [ ] Implement `Kill_Cargo(source)` - destroy cargo
- [ ] Write unit tests for TechnoClass

### FootClass (`src/objects/foot.lua`)
- [ ] Implement all fields from FOOT.H
  - [ ] `NavCom` (TARGET - move target)
  - [ ] `SuspendedNavCom` (saved nav target)
  - [ ] `Path` array (pathfinding result)
  - [ ] `PathLength` / `PathIndex`
  - [ ] `PathDelay` (pathfinding cooldown)
  - [ ] `Team` (TeamClass pointer)
  - [ ] `Member` (next team member)
  - [ ] `Group` (player group 0-9)
  - [ ] `Speed` (current movement speed)
  - [ ] `HeadTo` (next waypoint coord)
  - [ ] `IsInitiated` / `IsDriving` / `IsRotating`
  - [ ] `IsUnloading` / `IsFormationMove`
  - [ ] `IsNavQueueLoop`
- [ ] Implement `AI()` - mobile unit logic
- [ ] Implement `Assign_Destination(target)` - set NavCom
- [ ] Implement `Start_Driver(coord)` - begin movement
- [ ] Implement `Stop_Driver()` - halt movement
- [ ] Implement `Offload_Tiberium_Bail()` - unload one bail
- [ ] Implement `Random_Animate()` - idle animation
- [ ] Implement `Handle_Navigation_List()` - waypoint queue
- [ ] Implement `Per_Cell_Process(why)` - cell transition
- [ ] Implement movement physics (speed, acceleration)
- [ ] Implement rotation toward destination
- [ ] Implement `Mission_Move()` - movement mission
- [ ] Implement `Mission_Attack()` - attack mission
- [ ] Implement `Mission_Guard()` - guard mission
- [ ] Implement `Mission_Hunt()` - hunt mission
- [ ] Implement `Mission_Retreat()` - retreat mission
- [ ] Implement `Mission_Enter()` - enter transport
- [ ] Implement `Mission_Harvest()` - harvester mission
- [ ] Implement `Mission_Sabotage()` - commando mission
- [ ] Implement `Approach_Target()` - move toward target
- [ ] Implement `Basic_Path()` - request pathfinding
- [ ] Implement team membership logic
- [ ] Write unit tests for FootClass

### DriveClass (`src/objects/drive/drive.lua`)
- [ ] Implement ground vehicle movement physics
- [ ] Implement track/wheel/hover speed types
- [ ] Implement slope handling
- [ ] Implement water/cliff blocking
- [ ] Implement bridge crossing
- [ ] Implement crushing infantry
- [ ] Implement vehicle rotation animation
- [ ] Write unit tests for DriveClass

### FlyClass (`src/objects/drive/fly.lua`)
- [ ] Implement aircraft movement physics
- [ ] Implement flight altitude
- [ ] Implement takeoff/landing
- [ ] Implement landing pad docking
- [ ] Implement hovering (helicopters)
- [ ] Implement high-speed flight (planes)
- [ ] Write unit tests for FlyClass

### TarComClass (`src/objects/drive/tarcom.lua`)
- [ ] Implement turret tracking
- [ ] Implement turret rotation independent of body
- [ ] Implement secondary facing for turret
- [ ] Implement turret rotation speed
- [ ] Write unit tests for TarComClass

### InfantryClass (`src/objects/infantry.lua`)
- [ ] Implement all fields from INFANTRY.H
  - [ ] `Fear` (fear value 0-255)
  - [ ] `Doing` (DoType - current action)
  - [ ] `Comment` (comment timer)
  - [ ] `IsProne` / `IsStoked` / `IsTechnician`
  - [ ] `IsZoneCheat`
- [ ] Implement 5-position cell occupation
- [ ] Implement `AI()` - infantry-specific logic
- [ ] Implement `Do_Action(todo, force)` - animation action
- [ ] Implement `Set_Occupy_Bit(cell, spot)` - occupy position
- [ ] Implement `Clear_Occupy_Bit(cell, spot)` - vacate position
- [ ] Implement `Stop_Driver()` - stop at exact spot
- [ ] Implement fear accumulation from explosions
- [ ] Implement fear decay over time
- [ ] Implement prone (crawling) state
- [ ] Implement infantry death animations
- [ ] Implement `Made_A_Kill()` - kill tracking
- [ ] Implement `Fear_AI()` - fear behavior
- [ ] Implement `Scatter(coord)` - evade
- [ ] Implement enter building logic
- [ ] Implement C4 placement (commandos)
- [ ] Write unit tests for InfantryClass

### UnitClass (`src/objects/unit.lua`)
- [ ] Implement all fields from UNIT.H
  - [ ] `SecondaryFacing` (turret)
  - [ ] `IsDumping` / `IsHarvesting` / `IsReturning`
  - [ ] `GapGenCount` (gap generator)
  - [ ] `BerzerkCount` (berzerk timer)
  - [ ] `ReloadTimer` (reload countdown)
- [ ] Implement `AI()` - vehicle-specific logic
- [ ] Implement harvester tiberium collection
- [ ] Implement harvester return to refinery
- [ ] Implement APC door and unloading
- [ ] Implement turret rotation (TarComClass)
- [ ] Implement MCV deployment
- [ ] Implement unit death/explosion
- [ ] Implement crushing infantry
- [ ] Implement amphibious vehicles (APC, hovercraft)
- [ ] Write unit tests for UnitClass

### AircraftClass (`src/objects/aircraft.lua`)
- [ ] Implement all fields from AIRCRAFT.H
  - [ ] `BodyFacing` (body direction)
  - [ ] `Altitude` (flight height)
  - [ ] `Jitter` (sway amount)
  - [ ] `IsLanding` / `IsLanded` / `IsTakingOff`
- [ ] Implement `AI()` - aircraft-specific logic
- [ ] Implement helicopter hover
- [ ] Implement helicopter attack run
- [ ] Implement airplane strafing run
- [ ] Implement landing pad approach
- [ ] Implement ammo depletion and RTB
- [ ] Implement Orca/Apache behavior
- [ ] Implement Chinook transport
- [ ] Implement A-10 airstrike
- [ ] Write unit tests for AircraftClass

### BuildingClass (`src/objects/building.lua`)
- [ ] Implement all fields from BUILDING.H
  - [ ] `Factory` (FactoryClass pointer)
  - [ ] `BState` (building state)
  - [ ] `ActLike` (act like house)
  - [ ] `LastStrength` (for damage state)
  - [ ] `PlacementDelay` (placement timer)
  - [ ] `IsPrimaryFactory` / `IsRepairing` / `IsAllowedToSell`
  - [ ] `IsCharging` / `IsCharged` (superweapons)
  - [ ] `IsJamming` / `IsJammed` (gap generator)
- [ ] Implement `AI()` - building-specific logic
- [ ] Implement `Grand_Opening(captured)` - activation
- [ ] Implement `Update_Buildables()` - refresh build options
- [ ] Implement `Toggle_Primary()` - set primary factory
- [ ] Implement `Begin_Mode(bstate)` - state transition
- [ ] Implement building damage states
- [ ] Implement building animations (working, damaged)
- [ ] Implement building bibs (foundation graphics)
- [ ] Implement turret buildings (guard tower, SAM)
- [ ] Implement power production/consumption
- [ ] Implement radar providing (Com Center)
- [ ] Implement repair building functionality
- [ ] Implement refinery docking
- [ ] Write unit tests for BuildingClass

### Type Classes (`src/objects/types/`)
- [ ] Complete `TechnoTypeClass`
  - [ ] All fields from TECHNOTYPE.H
  - [ ] Weapon references
  - [ ] Armor type
  - [ ] Speed type
  - [ ] Sprite/animation data
- [ ] Complete `InfantryTypeClass`
  - [ ] DoControls (animation sequences)
  - [ ] Fear thresholds
  - [ ] Infantry-specific attributes
- [ ] Complete `UnitTypeClass`
  - [ ] Has turret flag
  - [ ] Is harvester flag
  - [ ] Can crush infantry
  - [ ] Amphibious flag
- [ ] Complete `AircraftTypeClass`
  - [ ] Is helicopter flag
  - [ ] Landing pad requirement
  - [ ] Flight ceiling
- [ ] Complete `BuildingTypeClass`
  - [ ] Power production/drain
  - [ ] Foundation size
  - [ ] Bib requirement
  - [ ] Adjacent requirement
  - [ ] Factory type (infantry, vehicle, aircraft)
- [ ] Implement type data loading from JSON/data files
- [ ] Verify all type data matches original
- [ ] Write unit tests for type classes

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

## Phase 3: Combat Systems

### BulletClass (`src/objects/bullet.lua`)
- [ ] Implement all fields from BULLET.H
  - [ ] `Class` (BulletTypeClass)
  - [ ] `Payback` (damage source)
  - [ ] `TarCom` (target)
  - [ ] `Strength` (damage amount)
  - [ ] `Warhead` (WarheadType)
- [ ] Implement `AI()` - projectile movement
- [ ] Implement `Unlimbo(coord, facing)` - spawn projectile
- [ ] Implement straight-line ballistics
- [ ] Implement arcing projectiles
- [ ] Implement homing projectiles
- [ ] Implement proximity detonation
- [ ] Implement impact detection
- [ ] Implement area damage on impact
- [ ] Write unit tests for BulletClass

### BulletTypeClass (`src/objects/types/bullettype.lua`)
- [ ] Implement all bullet types from original
- [ ] Implement projectile sprites
- [ ] Implement projectile speeds
- [ ] Implement arcing vs straight
- [ ] Implement homing behavior flags
- [ ] Load bullet data from data files

### AnimClass (`src/objects/anim.lua`)
- [ ] Implement all fields from ANIM.H
  - [ ] `Class` (AnimTypeClass)
  - [ ] `Owner` (owning object)
  - [ ] `Loops` (loop count)
  - [ ] `IsToDelete`
- [ ] Implement `AI()` - animation playback
- [ ] Implement animation attachment to objects
- [ ] Implement animation completion callback
- [ ] Implement explosion animations
- [ ] Implement muzzle flash animations
- [ ] Implement death/destruction animations
- [ ] Implement fire/burning animations
- [ ] Implement smoke animations
- [ ] Write unit tests for AnimClass

### AnimTypeClass (`src/objects/types/animtype.lua`)
- [ ] Implement all animation types from original
- [ ] Implement animation frame data
- [ ] Implement animation timing
- [ ] Implement animation sound triggers
- [ ] Load animation data from data files

### WeaponTypeClass (`src/combat/weapon.lua`)
- [ ] Implement all weapon attributes
  - [ ] Damage
  - [ ] ROF (rate of fire)
  - [ ] Range
  - [ ] Projectile type
  - [ ] Warhead type
  - [ ] Burst count
  - [ ] Muzzle flash
  - [ ] Sound effect
- [ ] Load weapon data from data files
- [ ] Verify all weapons match original

### WarheadTypeClass (`src/combat/warhead.lua`)
- [ ] Implement all warhead attributes
  - [ ] Armor modifiers (vs None, Wood, Light, Heavy, Concrete)
  - [ ] Spread (area damage)
  - [ ] Wall destruction
  - [ ] Ore destruction
  - [ ] Infantry death type
  - [ ] Explosion animation
- [ ] Implement exact integer armor calculation
- [ ] Load warhead data from data files
- [ ] Verify damage matches original

### Armor System (`src/combat/armor.lua`)
- [ ] Implement ArmorType enum
- [ ] Implement armor modifier lookup
- [ ] Implement exact damage formula from original

### Combat Integration
- [ ] Implement `Fire_At()` spawning bullets
- [ ] Implement rearm timing
- [ ] Implement weapon cycling (primary/secondary)
- [ ] Implement range checking with weapon range
- [ ] Implement `Take_Damage()` armor calculations
- [ ] Implement damage result states (undamaged, light, heavy, dead)
- [ ] Implement death processing
- [ ] Implement `Record_The_Kill()` scoring
- [ ] Implement kill credit to source

### Pathfinding (`src/pathfinding/findpath.lua`)
- [ ] Port FINDPATH.CPP algorithm exactly
- [ ] Implement `PathType` structure
- [ ] Implement `Find_Path()` main function
- [ ] Implement `Follow_Edge()` edge-following
- [ ] Implement `Register_Cell()` path recording
- [ ] Implement `Clear_Path()` path clearing
- [ ] Implement movement cost calculation per terrain
- [ ] Implement threat avoidance in pathfinding
- [ ] Implement path caching/reuse
- [ ] Implement path length limits
- [ ] Implement path failure handling
- [ ] Write pathfinding unit tests
- [ ] Write pathfinding integration tests

### Debug Overlays (Combat)
- [ ] Implement weapon range visualization
- [ ] Implement projectile trajectory visualization
- [ ] Implement damage number popups
- [ ] Implement threat map visualization
- [ ] Implement pathfinding visualization

---

## Phase 4: Economy & Production

### HouseClass (`src/house/house.lua`)
- [ ] Implement all fields from HOUSE.H
  - [ ] `Class` (HouseTypeClass)
  - [ ] `ActLike` (behavior template)
  - [ ] `Allies` (alliance bitfield)
  - [ ] `Credits` / `Tiberium` / `Capacity`
  - [ ] `Power` / `Drain`
  - [ ] `BuildStructure` / `BuildUnit` / `BuildInfantry` / `BuildAircraft`
  - [ ] `CurBuildings` / `CurUnits` / `CurInfantry` / `CurAircraft`
  - [ ] `BScan` / `UScan` / `IScan` / `AScan` (what types built)
  - [ ] `Radar` / `OldRadar` (radar state)
  - [ ] `IsActive` / `IsHuman` / `IsPlayerControl`
  - [ ] `IsDefeated` / `IsToWin` / `IsToLose`
  - [ ] `Alerts` (attack alerts)
  - [ ] `ScreenX` / `ScreenY` (tactical view position)
  - [ ] `InitialCredits`
- [ ] Implement `AI()` - house logic
- [ ] Implement `Spend_Money(amount)` - deduct credits
- [ ] Implement `Refund_Money(amount)` - add credits
- [ ] Implement `Available_Money()` - current balance
- [ ] Implement `Harvested(amount)` - add tiberium
- [ ] Implement `Power_Fraction()` - power ratio
- [ ] Implement `Is_Ally(house)` - alliance check
- [ ] Implement `Make_Ally(house)` / `Make_Enemy(house)`
- [ ] Implement `Can_Build(type, house)` - tech tree check
- [ ] Implement prerequisite checking
- [ ] Implement special weapon charging
- [ ] Write unit tests for HouseClass

### HouseTypeClass (`src/house/house_type.lua`)
- [ ] Implement all house types (GDI, NOD, Neutral, etc.)
- [ ] Implement house colors
- [ ] Implement starting units/buildings
- [ ] Load house data from data files

### FactoryClass (`src/production/factory.lua`)
- [ ] Implement all fields from FACTORY.H
  - [ ] `Object` (object being built)
  - [ ] `House` (owning house)
  - [ ] `SpecialItem` (special override)
  - [ ] `IsSuspended` / `IsDifferent`
  - [ ] `Balance` (credits remaining)
  - [ ] `OriginalBalance`
- [ ] Implement `AI()` - production tick
- [ ] Implement `Set(type, house)` - start production
- [ ] Implement `Start()` - resume production
- [ ] Implement `Suspend()` - pause production
- [ ] Implement `Abandon()` - cancel production
- [ ] Implement `Has_Completed()` - check completion
- [ ] Implement `Completion()` - completion percentage
- [ ] Implement cost deduction per tick
- [ ] Implement production speed based on power
- [ ] Write unit tests for FactoryClass

### Tiberium System
- [ ] Implement tiberium overlay in CellClass
- [ ] Implement tiberium value per cell
- [ ] Implement tiberium growth timer
- [ ] Implement tiberium spread to adjacent cells
- [ ] Implement blossom tree spawning tiberium
- [ ] Implement tiberium visual stages (1-12)
- [ ] Implement harvester `Mission_Harvest()`
- [ ] Implement harvester tiberium collection
- [ ] Implement harvester tiberium capacity
- [ ] Implement harvester return when full
- [ ] Implement refinery docking
- [ ] Implement refinery unloading animation
- [ ] Implement credits from tiberium
- [ ] Implement silos increasing capacity
- [ ] Implement tiberium loss when over capacity
- [ ] Write tiberium integration tests

### Power System
- [ ] Implement power production per building type
- [ ] Implement power drain per building type
- [ ] Implement power ratio calculation
- [ ] Implement low power effects:
  - [ ] Slower production
  - [ ] Radar disabled
  - [ ] Defense buildings slower
- [ ] Implement power bar UI element
- [ ] Implement power plant destruction effects
- [ ] Write power system tests

### Building Placement
- [ ] Implement building ghost/preview
- [ ] Implement placement validity checking
- [ ] Implement adjacency requirement
- [ ] Implement foundation fit checking
- [ ] Implement terrain passability for foundation
- [ ] Implement bib placement
- [ ] Implement building construction animation
- [ ] Implement instant placement after construction
- [ ] Write placement tests

### Sell/Repair
- [ ] Implement sell cursor
- [ ] Implement sell confirmation
- [ ] Implement sell refund calculation
- [ ] Implement sell animation
- [ ] Implement unit evacuation on sell
- [ ] Implement repair cursor
- [ ] Implement repair cost calculation
- [ ] Implement repair rate
- [ ] Implement repair animation (wrench)
- [ ] Write sell/repair tests

### MCV Deployment
- [ ] Implement MCV deploy command
- [ ] Implement deployment location check
- [ ] Implement deployment animation
- [ ] Implement Construction Yard creation
- [ ] Implement Construction Yard undeploy (if applicable)
- [ ] Write MCV tests

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
