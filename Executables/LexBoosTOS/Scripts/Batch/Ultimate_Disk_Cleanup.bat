@echo off
setlocal EnableExtensions
title LexBoosT - Ultimate Disk Cleanup
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)
cls
echo.
echo  ==================================================================
echo          LexBoosT OS  -  ULTIMATE DISK CLEANUP
echo  ==================================================================
echo.
echo   Cleaning temporary files, caches, logs, history and Windows Update...
echo   (the engine shows live progress)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Ultimate_Disk_Cleanup.ps1"
echo.
echo  ==================================================================
echo   Cleanup finished. This window closes automatically.
echo  ==================================================================
timeout /t 6 /nobreak >nul
endlocal
