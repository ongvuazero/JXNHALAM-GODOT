@echo off
setlocal
cd /d "%~dp0.."
if "%~1"=="" (
  echo Drag Godot_v4.6.1-stable_win64.exe onto this BAT file.
  pause
  exit /b 2
)
set "GODOT_EXE=%~1"
if not exist "%GODOT_EXE%" (
  echo Godot executable does not exist: "%GODOT_EXE%"
  pause
  exit /b 3
)
"%GODOT_EXE%" --headless --path . --editor --quit > "V44_4_GODOT_PARSE_LOG.txt" 2>&1
set "EXITCODE=%ERRORLEVEL%"
echo Godot exit code: %EXITCODE%
echo Saved: V44_4_GODOT_PARSE_LOG.txt
findstr /i /c:"Parse Error" /c:"SCRIPT ERROR" /c:"hides a global" "V44_4_GODOT_PARSE_LOG.txt"
pause
exit /b %EXITCODE%
