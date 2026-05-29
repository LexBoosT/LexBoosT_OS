@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE4.CMD - SYSTEM CLEANUP
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. SYSTEM CLEANUP
call :SystemCleanup

goto :eof

:: ================================================
:: FUNCTIONS
:: ================================================

:CheckAdmin
echo.
echo ================================================
echo ADMINISTRATOR PRIVILEGES VERIFICATION
echo ================================================
echo [+] Checking administrator privileges...
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Administrator privileges required
    echo [+] Restarting with elevated privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
echo [OK] Administrator privileges confirmed
goto :eof

:SystemCleanup
echo.
echo ================================================
echo SYSTEM CLEANUP
echo ================================================

:: Remove update health tools
echo [+] Removing update health tools...
msiexec /X{43D501A5-E5E3-46EC-8F33-9E15D2A2CBD5} /qn /norestart >NUL 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\UpdateHealthTools" /f >NUL 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\rempl" /f >NUL 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\CloudManagedUpdate" /f >NUL 2>nul
rmdir /s /q "%ProgramW6432%\\Microsoft Update Health Tools" >NUL 2>nul

:: Remove PC health check
echo [+] Removing PC health check...
msiexec /X{804A0628-543B-4984-896C-F58BF6A54832} /qn /norestart >NUL 2>nul
rmdir /s /q "%ProgramW6432%\\PCHealthCheck" >NUL 2>nul

:: Remove Windows installation assistant
echo [+] Removing Windows installation assistant...
"%ProgramFiles(x86)%\WindowsInstallationAssistant\Windows10UpgraderApp.exe" /SunValley /ForceUninstall >NUL 2>nul
rmdir /s /q "%ProgramFiles(x86)%\WindowsInstallationAssistant" >NUL 2>nul

:: Remove default user accounts
echo [+] Removing default user accounts...
net user defaultuser0 /delete 2>nul
net user defaultuser1 /delete 2>nul
net user defaultuser100000 /delete 2>nul

:: NOTE: RAM compression is handled by gaming.yml (conditional 16GB+)
:: PageCombining is disabled here for systems that passed the RAM check
powershell -NoProfile -Command "Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue" >nul 2>&1


:: Valorant support mitigation
echo [+] Configuring Valorant mitigation...
powershell -NonInteractive -NoLogo -NoProfile Set-ProcessMitigation -Name vgc.exe -Enable CFG

:: Configure Shutdown Event Tracker
echo [+] Configuring Shutdown Event Tracker...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" /v "ShutdownReasonOn" /t REG_DWORD /d "0" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" /v "ShutdownReasonUI" /t REG_DWORD /d "0" /f >nul 2>&1

goto :eof
