# Learnings & Observations

## 2026-01-16: Phase 0 ECS Removal

### Completed
- Deleted `src/ecs/` directory (5 files: entity.lua, component.lua, system.lua, world.lua, init.lua)
- Deleted `src/systems/` directory (17 files, ~333KB of legacy code):
  - ai_system.lua, aircraft_system.lua, animation_system.lua, audio_system.lua
  - cloak_system.lua, combat_system.lua, fog_system.lua, harvest_system.lua
  - movement_system.lua, power_system.lua, production_system.lua, render_system.lua
  - selection_system.lua, special_weapons.lua, turret_system.lua, init.lua
- Updated `src/init.lua` to remove ECS and Systems exports
- Confirmed `src/components/` was already removed previously
- Created ECS/Systems compatibility shims to allow game to load:
  - `src/ecs/init.lua` - Minimal World class with entity storage + system management
  - `src/systems/init.lua` - Stub implementations of all 14 systems game.lua expects
  - Game now loads successfully with stub implementations (verified)
  - This is a transitional solution - shims should be removed when Phase 1 migration to
    class hierarchy is complete

### Observations
1. **ECS was actively integrated**: The ECS system was heavily used in `src/core/game.lua` with 50+ references to `self.world` for entity management. Recent commits (AI integration, production, tiberium growth) were building on top of this.

2. **Two parallel architectures existed**: The codebase had both:
   - ECS-based game loop (`src/ecs/` + `src/systems/`)
   - C++ class hierarchy port (`src/objects/` with AbstractClass → ObjectClass → TechnoClass etc.)

3. **Migration impact**: Removing ECS will break the game until:
   - `src/systems/` is deleted (next task)
   - `src/core/game.lua` is refactored to use the class hierarchy
   - The class hierarchy's AI() methods are wired into the game loop

4. **Class hierarchy is ready**: The `src/objects/` directory contains ~12,000 lines of ported C++ classes that are complete and waiting to be used:
   - All base classes (AbstractClass, ObjectClass, MissionClass, RadioClass, TechnoClass)
   - All concrete classes (InfantryClass, UnitClass, BuildingClass, AircraftClass, etc.)
   - All type classes in `src/objects/types/`
   - HeapClass pools in `src/heap/`

5. **Compatibility shim approach chosen**: Rather than immediately refactoring game.lua
   (which has 50+ ECS world references across ~4300 lines), we created lightweight shims
   that implement the same interface. This allows:
   - Game to load and run without crashes
   - Incremental migration to class hierarchy in Phase 1
   - Clear TODO markers indicating what needs removal

### Next Steps (per PROGRESS.md)
1. ~~Delete `src/systems/` directory entirely~~ DONE
2. ~~Update `main.lua` to remove ECS requires~~ Already clean
3. ~~Update `src/core/game.lua` to remove ECS dependencies~~ Shims created
4. Audit remaining files against original C++ structure
5. Begin Phase 1: Integrate class hierarchy with game loop
