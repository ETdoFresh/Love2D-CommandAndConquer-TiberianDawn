@echo off
REM Game CLI - Send commands to running Love2D game
REM Usage: game-cli <instance_id> <command> [args...]

if "%1"=="" (
    echo Usage: game-cli ^<instance_id^> ^<command^> [args...]
    echo.
    echo The instance_id is printed as IPC_ID=^<id^> when the game starts.
    echo.
    echo Commands:
    echo   ^<id^> input ^<key^>       - Simulate key press
    echo   ^<id^> gamepad ^<button^>  - Simulate gamepad button
    echo   ^<id^> screenshot [path] - Take screenshot
    echo   ^<id^> state             - Get game state
    echo   ^<id^> pause             - Pause game
    echo   ^<id^> resume            - Resume game
    echo   ^<id^> quit              - Quit game
    exit /b 1
)

REM Pass all arguments to Lua client
lua "%~dp0ipc_client.lua" %*
