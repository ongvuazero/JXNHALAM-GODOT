@echo off
setlocal
set "ROOT=%~dp0.."
if "%~1"=="" (
  echo Drag Godot_v4.6.1-stable_win64.exe onto this .bat
  pause
  exit /b 2
)
set "EXE=%~1"
"%EXE%" --headless --path "%ROOT%" --script res://tests/RunLuaStageAuditV443.gd > "%ROOT%\V443_LUA_SPR_AUDIT.log" 2>&1
set "CODE=%errorlevel%"
echo Result exit code: %CODE%
echo Log: %ROOT%\V443_LUA_SPR_AUDIT.log
more "%ROOT%\V443_LUA_SPR_AUDIT.log"
pause
exit /b %CODE%
