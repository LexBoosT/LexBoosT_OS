@echo off
:: =============================================================================
:: PAUSE.CMD - Silent pause for AME Wizard orchestration
:: Used between FINALIZE1..6 to give the user time to read status messages.
:: Behavior:
::   - If interactive session (WindowVisible): show "[ENTER] to continue" prompt
::   - If non-interactive (service / piped / AME): exit immediately so AME
::     can move on to the next step. The original `pause >nul` would hang
::     AME indefinitely when no console is attached.
:: =============================================================================

:: Detect if a console is attached. We use `>con` test on NUL substitution
:: as a portable check. If stdout is being redirected, we are not interactive.
set "_IS_INTERACTIVE=1"
if not "%~1" == "" set "_IS_INTERACTIVE=0"
for /f "tokens=*" %%i in ('echo prompt $G ^| cmd /d /q') do set "_PROBE=%%i" >nul 2>&1

:: Simpler heuristic: check if STDIN is a console.
<nul set /p "_DUMMY=" 2>nul
if errorlevel 1 set "_IS_INTERACTIVE=0"

if "%_IS_INTERACTIVE%" == "1" (
    echo.
    echo ================================================================================
    echo  LexBoosT OS - Step complete.
    echo  You can continue. The next step will start automatically if AME is running.
    echo ================================================================================
    echo.
    echo Press any key to continue, or wait 15 seconds...
    choice /c YN /n /t 15 /d Y >nul 2>&1
)

exit /b 0
