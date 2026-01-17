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

5. **Files still referencing deleted ECS**:
   - `src/core/game.lua` - requires major refactor (next priority)

### Next Steps (per PROGRESS.md)
1. ~~Delete `src/systems/` directory entirely~~ DONE
2. Update `main.lua` to remove ECS requires (check if needed)
3. Update `src/core/game.lua` to remove ECS dependencies (major task)
