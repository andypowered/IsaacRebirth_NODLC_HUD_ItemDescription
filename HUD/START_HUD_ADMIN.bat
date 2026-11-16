@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path (Get-Location) 'MissingHUD2.exe'; Start-Process -FilePath $p -WorkingDirectory (Get-Location) -Verb RunAs"
