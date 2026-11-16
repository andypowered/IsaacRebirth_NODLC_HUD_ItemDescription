@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" -Pause %*
if errorlevel 1 (
  echo.
  echo Uninstall failed. Read the message above.
  pause
)
