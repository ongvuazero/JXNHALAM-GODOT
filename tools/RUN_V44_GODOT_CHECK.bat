@echo off
setlocal
set "ROOT=%~dp0.."
set "LOG=%ROOT%\JXNHALAM_V44_GODOT_CHECK.log"
if "%~1"=="" (
  echo Keo file Godot_v4.6.1-stable_win64.exe vao BAT nay de chay kiem tra.
  echo Hoac goi: RUN_V44_GODOT_CHECK.bat "C:\path\to\godot.exe"
  pause
  exit /b 1
)
if not exist "%~1" (
  echo Khong tim thay Godot: %~1
  pause
  exit /b 2
)
echo Running Godot headless on: %ROOT%
"%~1" --headless --path "%ROOT%" --editor --quit > "%LOG%" 2>&1
set "CODE=%ERRORLEVEL%"
echo Godot exit code: %CODE%
echo Log: %LOG%
findstr /i /c:"Parse Error" /c:"SCRIPT ERROR" /c:"Failed to load script" "%LOG%"
if errorlevel 1 echo Khong thay thong bao parse khi grep log. Van can xem toan bo log.
pause
exit /b %CODE%
