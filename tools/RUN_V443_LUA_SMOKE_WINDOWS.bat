@echo off
setlocal
set "ROOT=%~dp0.."
if "%~1"=="" (
  echo Drag Godot_v4.6.1-stable_win64.exe onto this .bat
  pause
  exit /b 2
)
set "EXE=%~1"
"%EXE%" --headless --path "%ROOT%" --script res://tests/TestLuaChainV443.gd > "%ROOT%\V443_LUA_SMOKE.log" 2>&1
set "CODE=%errorlevel%"
echo Result exit code: %CODE%
echo Log: %ROOT%\V443_LUA_SMOKE.log
more "%ROOT%\V443_LUA_SMOKE.log"
pause
exit /b %CODE%
