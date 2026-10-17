@echo off
rem =====================================================================
rem EnableDefender.cmd - restore Windows Defender to Windows defaults
rem Reverses DisableDefender.cmd (policies removed, services back to
rem auto-start, scheduled tasks re-enabled, WinDefend restarted)
rem Usage: EnableDefender.cmd [/silent]
rem =====================================================================
setlocal

fltmc > nul 2>&1 || (
    set "___args="%~f0 %*"
    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c ' + $env:___args" 2> nul
    if "%~1" neq "/silent" pause
    exit /b
)

rem --- Remove disabling policies (back to Microsoft defaults)
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /f > nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableEnhancedBehaviorMonitoring" /f > nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /f > nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableOnAccessProtection" /f > nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableIOAVProtection" /f > nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableScanningRemovableMedia" /f > nul 2>&1

rem --- Services: auto-start + start now
sc config WinDefend start= auto > nul 2>&1
sc config SecurityHealthService start= auto > nul 2>&1
sc start WinDefend > nul 2>&1
sc start SecurityHealthService > nul 2>&1

rem --- Re-enable scheduled maintenance tasks
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance" /enable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Cleanup" /enable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan" /enable > nul 2>&1
schtasks /change /tn "Microsoft\Windows\Windows Defender\Windows Defender Verification" /enable > nul 2>&1

rem --- If it does not come up within 30 s (file locks), force-start MsMpEng
timeout /t 30 /nobreak > nul
sc query WinDefend | findstr /i "RUNNING" > nul 2>&1 || sc start WinDefend > nul 2>&1

if "%~1" neq "/silent" (
    echo Defender restored to defaults. A reboot is strongly advised to complete the re-arming.
    pause
)
exit /b 0
