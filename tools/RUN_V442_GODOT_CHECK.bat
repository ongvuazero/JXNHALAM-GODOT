@echo off
setlocal
cd /d "%~dp0.."
set "GODOT=%~1"
if "%GODOT%"=="" (
  echo Keo file Godot_v4.6.1-stable_win64_console.exe vao BAT nay.
  echo Hoac chay: RUN_V442_GODOT_CHECK.bat "C:\path\Godot_v4.6.1-stable_win64_console.exe"
  pause
  exit /b 1
)
if not exist "%GODOT%" (
  echo Godot EXE not found: %GODOT%
  pause
  exit /b 1
)
"%GODOT%" --headless --editor --path "%cd%" --quit > "V44_2_GODOT_PARSE_CHECK.log" 2>&1
set "ERR=%ERRORLEVEL%"
echo Exit: %ERR%
echo Log: %cd%\V44_2_GODOT_PARSE_CHECK.log
if not "%ERR%"=="0" (
  type "V44_2_GODOT_PARSE_CHECK.log"
)
pause
exit /b %ERR%
