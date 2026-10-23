@echo off
rem =====================================================================
rem DisableMitigations.cmd - disable all Windows exploit mitigations
rem Ported 1:1 from AtmosphereOS playbook
rem (Executables\AtmosphereDesktop\7. Security\Mitigations\Disable All Mitigations.cmd)
rem Usage: DisableMitigations.cmd [/silent]
rem =====================================================================
setlocal EnableDelayedExpansion

if "%~1" == "/silent" goto main

fltmc > nul 2>&1 || (
	set "___args="%~f0" %*"
	powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c ' + $env:___args" 2> nul || (
		echo You must run this script as admin.
		pause
		exit /b 1
	)
	exit /b
)

:main
:: Disable Spectre and Meltdown
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverride" /t REG_DWORD /d "3" /f > nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverrideMask" /t REG_DWORD /d "3" /f > nul

:: Disable Control Flow Guard (CFG)
PowerShell -NoP -C "Set-ProcessMitigation -System -Disable CFG" > nul

:: Get current bit mask
for /f "tokens=3 skip=2" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "MitigationAuditOptions"') do (
    set "mitigation_mask=%%a"
)

:: Set all bits to 2 (Disable all process mitigations)
for /l %%a in (0,1,9) do (
    set "mitigation_mask=!mitigation_mask:%%a=2!"
)

:: Keep CFG for known games that break with it off
set "enableCFGApps=valorant valorant-win64-shipping vgtray vgc"
PowerShell -NoP -C "foreach ($a in $($env:enableCFGApps -split ' ')) {Set-ProcessMitigation -Name $a`.exe -Enable CFG}" > nul

:: DEP: OS components only (bcdedit)
bcdedit /set nx OptIn > nul

:: Apply mask to kernel
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "MitigationAuditOptions" /t REG_BINARY /d "%mitigation_mask%" /f > nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "MitigationOptions" /t REG_BINARY /d "%mitigation_mask%" /f > nul

:: Disable file system mitigations
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v "ProtectionMode" /t REG_DWORD /d "0" /f > nul

if "%~1" == "/silent" exit /b

echo Finished, please reboot your device for changes to apply.
pause
exit /b
