@echo off
rem =====================================================================
rem EnableMitigations.cmd - restore Windows default exploit mitigations
rem Ported from AtmosphereOS playbook
rem (Executables\AtmosphereDesktop\7. Security\Mitigations\Set Windows Default Mitigations.cmd)
rem Usage: EnableMitigations.cmd [/silent]
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
:: Restore Spectre/Meltdown defaults
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverride" /f > nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverrideMask" /f > nul 2>&1

:: Restore SEHOP default
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "DisableExceptionChainValidation" /f > nul 2>&1

:: Restore default mitigation masks (deleting the values = Windows defaults, incl. CFG)
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "MitigationAuditOptions" /f > nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "MitigationOptions" /f > nul 2>&1

:: DEP: OS components only (bcdedit default behaviour)
bcdedit /set nx OptIn > nul

:: Restore file system mitigations
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v "ProtectionMode" /t REG_DWORD /d "1" /f > nul

:: Restore Hyper-V CPU mitigations default
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" /v "MinVmVersionForCpuBasedMitigations" /f > nul 2>&1

if "%~1" == "/silent" exit /b

echo Finished, please reboot your device for changes to apply.
pause
exit /b
