@echo off
setlocal
cd /d "%~dp0.."
where godot >nul 2>&1
if errorlevel 1 (
 echo [ERROR] Godot.exe not found in PATH. Open project.godot in Godot Editor and press F5.
 pause
 exit /b 1
)
godot --path . --editor --import --quit
if errorlevel 1 goto fail
godot --path .
exit /b %ERRORLEVEL%
:fail
echo Godot failed to import project.
pause
exit /b 1
