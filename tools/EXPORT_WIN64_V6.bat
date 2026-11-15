@echo off
setlocal
cd /d "%~dp0.."
where godot >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Godot.exe not found in PATH.
  echo Use Godot 4 Standard Editor, add its folder to PATH, then rerun.
  pause
  exit /b 1
)
if not exist Windows_Build mkdir Windows_Build
echo Importing assets...
godot --headless --path . --editor --import --quit
if errorlevel 1 goto fail
echo Exporting Godot Windows x64. Requires matching installed export templates.
godot --headless --path . --export-release "Windows Desktop" "Windows_Build/JXNHALAM_V6.exe"
if errorlevel 1 goto fail
if not exist Windows_Build\JXNHALAM_V6.exe goto fail
echo [OK] Windows_Build\JXNHALAM_V6.exe
pause
exit /b 0
:fail
echo [ERROR] Godot import or export failed. Check installed export templates and log above.
pause
exit /b 1
