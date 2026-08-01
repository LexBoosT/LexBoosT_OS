@echo off
setlocal EnableExtensions DisableDelayedExpansion

:: ============================================
:: SET_LEVEL_TELEMETRY.CMD
:: Set Windows telemetry level to 0 (Security)
:: ============================================

set "REG=reg.exe"

echo [+] Setting telemetry level to 0 (Security)...

%REG% ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul 2>&1
%REG% ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul 2>&1

echo [+] Telemetry level set to 0 (Security)

endlocal
exit /b 0
