@echo off
setlocal EnableExtensions
set "PROJECT=%~dp0.."
if "%~1"=="" (
 echo KEO Godot_v4.6.1-stable_win64.exe VAO FILE BAT NAY.
 echo Hoac goi RUN_V441_GODOT_CHECK.bat "C:\path\godot.exe"
 pause
 exit /b 2
)
if not exist "%~1" (
 echo Khong tim thay Godot: %~1
 pause
 exit /b 3
)
set "LOG=%PROJECT%\JXNHALAM_V441_GODOT_CHECK.log"
echo ===== GODOT PROJECT PARSE ===== > "%LOG%"
"%~1" --headless --path "%PROJECT%" --editor --quit >> "%LOG%" 2>&1
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" goto failed
echo. >> "%LOG%"
echo ===== V44.1 MISSILE MOTION UNIT TEST ===== >> "%LOG%"
"%~1" --headless --path "%PROJECT%" --script res://tests/TestJXMissileMotion.gd >> "%LOG%" 2>&1
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" goto failed
findstr /i /c:"Parse Error" /c:"SCRIPT ERROR" /c:"FAIL V44.1" "%LOG%" >nul
if not errorlevel 1 (
 set "CODE=4"
 goto failed
)
echo PASS: Godot editor parse + V44.1 motion tests
GOTO done
:failed
echo FAIL: Godot exit=%CODE%. Mo file log de lay LOI DAU TIEN.
:done
echo Log: %LOG%
pause
exit /b %CODE%
