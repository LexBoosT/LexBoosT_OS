@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%Apply-NetworkPresets.ps1"
set "TEMP_FILE=%TEMP%\nova_nic_paths_%RANDOM%.txt"

if exist "%TEMP_FILE%" del /f /q "%TEMP_FILE%" >nul 2>&1

:: Query all subkeys under the NIC class for those exposing *SpeedDuplex.
:: reg query outputs HKEY_LOCAL_MACHINE\... lines — we filter to key-path lines only.
for /f "tokens=*" %%n in (
    'Reg query "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}" /v "*SpeedDuplex" /s 2^>nul ^| findstr /i "HKEY_LOCAL_MACHINE"'
) do (
    echo %%n>> "%TEMP_FILE%"
)

if not exist "%TEMP_FILE%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" >nul 2>&1
    goto :end
)

set "PATH_COUNT=0"
for /f %%c in ('type "%TEMP_FILE%" ^| find /c /v ""') do set "PATH_COUNT=%%c"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -PathsFile "%TEMP_FILE%" >nul 2>&1

:: Clean up temp file
del /f /q "%TEMP_FILE%" >nul 2>&1

:end
endlocal
exit /b 0
