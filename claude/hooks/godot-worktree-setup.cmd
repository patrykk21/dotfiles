@echo off
REM Godot worktree setup hook — runs on CwdChanged
REM Checks if we're in a Godot project worktree that needs setup

REM Read the new cwd from stdin JSON
for /f "delims=" %%i in ('jq -r ".cwd" ^< CON') do set "NEW_CWD=%%i"

REM Check if this is a Godot project (has project.godot)
if not exist "%NEW_CWD%\project.godot" exit /b 0

REM Check if .godot cache exists (if yes, already set up)
if exist "%NEW_CWD%\.godot\imported" exit /b 0

REM This is an uncached Godot worktree — run import
echo [godot-worktree-setup] Running Godot import for %NEW_CWD%... >&2
"Y:\Programs\Godot_v4.6.2-stable_mono_win64_console.exe" --headless --import --path "%NEW_CWD%" >nul 2>&1

REM Create .claude/launch.json if missing
if not exist "%NEW_CWD%\.claude\launch.json" (
    mkdir "%NEW_CWD%\.claude" 2>nul
    echo {"version":"0.0.1","configurations":[{"name":"godot","runtimeExecutable":"Y:/Programs/Godot_v4.6.2-stable_mono_win64_console.exe","runtimeArgs":["--path","."],"port":6850}]} > "%NEW_CWD%\.claude\launch.json"
    echo [godot-worktree-setup] Created .claude/launch.json >&2
)

echo [godot-worktree-setup] Setup complete >&2
exit /b 0
