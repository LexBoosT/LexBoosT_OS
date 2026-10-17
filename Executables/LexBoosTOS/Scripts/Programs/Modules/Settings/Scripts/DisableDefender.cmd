@echo off
rem =====================================================================
rem DisableDefender.cmd - disable Windows Defender real-time protection
rem Ported/adapted from AtmosphereOS playbook (windows defender.yml):
rem service stops + DisableAntiSpyware policy (no file deletion - reversible)
rem Usage: DisableDefender.cmd [/silent]
rem =====================================================================
setlocal

rem Already elevated (RunElevated from the app) - but self-elevate if double-clicked
fltmc > nul 2>&1 || (
    set "___args="%~f0 %*"
    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c ' + $env:___args" 2> nul
    if "%~1" neq "/silent" pause
    exit /b
)

rem --- Policies: disable Defender + SmartScreen (110 = disabled, no UAC prompt)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d 110 /f > nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /t REG_DWORD /d 1 /f > nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableOnAccessProtection" /t REG_DWORD /d 1 /f > nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableIOAVProtection" /t REG_DWORD /d 1 /f > nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableScanningRemovableMedia" /t REG_DWORD /d 1 /f > nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableEnhancedBehaviorMonitoring" /t REG_DWORD /d 1 /f > nul 2>&1

rem --- Services: stop and prevent auto-start
sc config WinDefend start= disabled > nul 2>&1
sc stop WinDefend > nul 2>&1
sc config SecurityHealthService start= disabled > nul 2>&1
sc stop SecurityHealthService > nul 2>&1

rem --- Kill Defender processes
taskkill /f /im MsMpEng.exe > nul 2>&1
taskkill /f /im SecurityHealthSystray.exe > nul 2>&1
taskkill /f /im SecurityHealthService.exe > nul 2>&1
taskkill /f /im SecurityHealthHost.exe > nul 2>&1

rem --- Disable scheduled maintenance tasks
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance" /disable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Cleanup" /disable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan" /disable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Verification" /disable > nul 2>&1

if "%~1" neq "/silent" (
    echo Defender disabled. Reboot to fully complete.
    pause
)
exit /b 0
