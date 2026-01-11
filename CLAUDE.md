# Command & Conquer: Tiberian Dawn - Love2D Port

## Project Purpose
Create a faithful and accurate port of the original Command & Conquer: Tiberian Dawn into a fully runnable Love2D game.

## Source Reference
The original game source code is located at: `./temp/CnC_Remastered_Collection/TIBERIANDAWN/`

Key reference files:
- `DEFINES.H` - All enums (units, buildings, weapons, missions), TICKS_PER_SECOND=15
- `TECHNO.H` - Core combat entity functionality
- `CELL.H` - Map cell structure, lepton system (256 leptons per cell)
- `EVENT.H` - Network event types for multiplayer
- `TRIGGER.H` - Campaign trigger/scripting system
- `MISSION.H` - AI mission types
- `HOUSE.H` - Faction and economy
- `FACTORY.H` - Production system
- `BULLET.H` - Projectile system

## Implementation Plan
See `PLAN.md` for the full 6-phase implementation plan.

## Development Workflow
1. Run the game: `love .` or `lovec .` (console version for stdout)
2. Use IPC system for testing - see `.claude/skills/interact-ipc/SKILL.md`
3. Reference original C++ source in `./temp/` for accurate behavior

## Key Technical Details
- **Tick Rate**: 15 FPS game logic (TICKS_PER_SECOND = 15)
- **Coordinate System**: Leptons (256 leptons per cell, 24 pixels per cell)
- **Target Resolution**: 320x200 (classic) / 1920x1080+ (HD mode)
- **ECS Architecture**: Entity-Component-System in `src/ecs/`

## Current Status
- Basic game loop and menu system working
- ECS framework implemented
- Map grid and cell system implemented
- Multiple systems scaffolded (combat, AI, production, harvest, power, fog, cloak)
- IPC debugging system for CLI control

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
