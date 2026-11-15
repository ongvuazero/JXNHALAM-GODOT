@echo off
setlocal
cd /d "%~dp0.."
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "tools\audit_v444_vfx_source.py"
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo Python 3 is required for this read-only audit.
    pause
    exit /b 1
  )
  python "tools\audit_v444_vfx_source.py"
)
echo.
echo Report directory: reports\v44_4
pause
