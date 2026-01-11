---
name: interact-ipc
description: Interact with and control the Love2D game via IPC. Use this skill when you need to see what's on screen, navigate menus, send input commands, take screenshots, or get game state. Start the game first, then use the IPC commands to control it.
---

# Love2D Game IPC Control

This skill allows you to interact with the running Love2D game through an IPC (Inter-Process Communication) system.

## Starting the Game

Start the game using the console version to capture the IPC instance ID:

```bash
cd "<project-root>" && "C:\Program Files\LOVE\lovec.exe" . 2>&1 &
```

Look for `IPC_ID=<timestamp>` in the output. This is the instance ID you'll use for all commands.

## IPC Directory Structure

Commands are sent via files in the temp directory:
- **Command file**: `$TEMP/love2d_ipc_<id>/command.txt`
- **Response file**: `$TEMP/love2d_ipc_<id>/response.json`

On Windows with Git Bash, use `/tmp/love2d_ipc_<id>/`.

## Sending Commands

To send a command:
```bash
echo "<command>" > /tmp/love2d_ipc_<id>/command.txt && sleep 0.5 && cat /tmp/love2d_ipc_<id>/response.json
```

## Available Commands

### Get Game State
```bash
echo "state" > /tmp/love2d_ipc_<id>/command.txt && sleep 0.5 && cat /tmp/love2d_ipc_<id>/response.json
```
Returns JSON with current game state including:
- `game.state` - Current state (menu, playing, paused, etc.)
- `game.menu_selection` - Currently selected menu item (1-indexed)
- `game.menu_items` - List of menu options
- `game.paused` - Whether game is paused
- `window.width/height` - Window dimensions

### Simulate Key Press
```bash
echo "input <key>" > /tmp/love2d_ipc_<id>/command.txt
```
Keys: `up`, `down`, `left`, `right`, `return`, `escape`, `space`, `w`, `a`, `s`, `d`, etc.

### Simulate Gamepad Button
```bash
echo "gamepad <button>" > /tmp/love2d_ipc_<id>/command.txt
```
Buttons: `a`, `b`, `x`, `y`, `start`, `back`, `dpup`, `dpdown`, `dpleft`, `dpright`

### Take Screenshot
```bash
echo "screenshot" > /tmp/love2d_ipc_<id>/command.txt && sleep 1 && cat /tmp/love2d_ipc_<id>/response.json
```
Returns path to saved screenshot. Use the Read tool to view the screenshot image.

### Pause/Resume
```bash
echo "pause" > /tmp/love2d_ipc_<id>/command.txt
echo "resume" > /tmp/love2d_ipc_<id>/command.txt
```

### Quit Game
```bash
echo "quit" > /tmp/love2d_ipc_<id>/command.txt
```

## Workflow Example

1. **Start the game** and capture IPC_ID from output
2. **Get state** to see current menu/screen
3. **Navigate** using `input up/down/return` commands
4. **Take screenshot** to see what's on screen
5. **Read screenshot** using the Read tool to view it

## Menu Navigation

The main menu has these items (1-indexed):
1. New Campaign
2. Skirmish
3. Multiplayer
4. Map Editor
5. Options
6. Exit

Use `input down` to move selection down, `input up` to move up, `input return` to select.

## Tips

- Always check `state` first to understand current game context
- Wait ~0.5s after sending commands before reading response
- Screenshots are saved to Love2D's save directory (shown in response)
- Use the Read tool to view screenshot PNG files
- If game crashes, check the background task output for error messages
