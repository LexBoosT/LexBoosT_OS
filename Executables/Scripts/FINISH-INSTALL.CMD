@echo off
setlocal EnableExtensions
title LexBoosT OS - Installation Finished
color 0A

echo.
echo  ============================================================================
echo    INSTALLATION COMPLETE - LexBoosT OS is ready
echo  ============================================================================
echo.
echo    All playbook steps have been applied successfully.
echo.
echo    A restart is required to finalize the installation.
echo    You may close this window and restart when ready.
echo.
echo  ============================================================================
echo.

if not exist "%TEMP%\LexBoosT_InstallFinished.marker" (
    > "%TEMP%\LexBoosT_InstallFinished.marker" echo %DATE% %TIME%
)

echo    Marker created : %TEMP%\LexBoosT_InstallFinished.marker
echo.
echo    This window will close automatically in a few seconds...
timeout /t 15 > nul
exit /b 0
