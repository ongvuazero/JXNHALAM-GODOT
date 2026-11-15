@echo off
setlocal
set "PROJECT=%~dp0.."
where godot >nul 2>&1
if errorlevel 1 (
  echo Godot not in PATH. Open Godot Editor and use Tools -^^> Command Line or add Godot.exe to PATH.
  pause
  exit /b 1
)
echo Testing virtual file system and per-frame SPR...
godot --headless --path "%PROJECT%" --editor --import --quit
if errorlevel 1 goto fail
godot --headless --path "%PROJECT%" --script res://tests/TestVFS.gd
if errorlevel 1 goto fail
godot --headless --path "%PROJECT%" --script res://tests/TestVFSv6.gd
if errorlevel 1 goto fail
echo ALL TESTS PASSED
pause
exit /b 0
:fail
echo TEST FAILED: Please send the console output.
pause
exit /b 1
