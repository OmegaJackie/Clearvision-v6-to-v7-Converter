@echo off
REM Launcher for Start Conversion.ps1
SETLOCAL
SET "SCRIPT=%~dp0Start Conversion.ps1"
IF NOT EXIST "%SCRIPT%" (
  echo Script not found: %SCRIPT%
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
ENDLOCAL
