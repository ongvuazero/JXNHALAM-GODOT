@echo off
setlocal
cd /d "%~dp0.."
where godot >nul 2>&1
if %errorlevel% neq 0 (
  echo Godot was not found in PATH. Run in the Godot Editor or add godot.exe to PATH.
  pause
  exit /b 1
)
godot --headless --path . --script res://tests/TestVFXv63.gd
pause
