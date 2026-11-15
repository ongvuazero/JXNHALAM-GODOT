@echo off
cd /d "%~dp0.."
where godot4 >nul 2>nul && (godot4 --headless --path . --script res://tests/TestVFXv64.gd & exit /b %errorlevel%)
where godot >nul 2>nul && (godot --headless --path . --script res://tests/TestVFXv64.gd & exit /b %errorlevel%)
echo Cần cài Godot 4.4+ và thêm vào PATH.
pause
