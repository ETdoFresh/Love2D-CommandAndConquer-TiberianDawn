# Command & Conquer: Tiberian Dawn - Love2D Port

## Project Purpose
Create a faithful and accurate port of the original Command & Conquer: Tiberian Dawn into a fully runnable Love2D game.

## Source Reference
The original game source code is located at: `temp/CnC_Remastered_Collection/TIBERIANDAWN/`
(Use `Paths.cnc_source("FILENAME.H")` in Lua code - see [Git Worktree Support](#git-worktree-support))

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

### Usage
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
