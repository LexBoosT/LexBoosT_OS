@echo off
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0disable-device-power-saving.ps1" >nul 2>&1
exit /b %errorlevel%
