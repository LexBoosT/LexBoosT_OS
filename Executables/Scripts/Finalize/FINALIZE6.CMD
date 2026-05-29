@echo off
setlocal enabledelayedexpansion


:: ================================================
:: FINALIZE6.CMD - FINALIZATION & NETWORK CONFIGURATION
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. FINALIZATION
call :Finalization

:: 3. NETWORK CONFIGURATION
call :NetworkConfig

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

:Finalization
echo.
echo ================================================
echo FINALIZATION
echo ================================================

:: Disable service host splitting (reduces svchost.exe count by ~40-60)
echo [+] Disabling service host splitting...
powershell -Command "Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object { $_.PSChildName -notmatch 'Xbl|Xbox' } | ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name 'SvcHostSplitDisable' -Type DWORD -Value 1 -Force -EA 0 }" >nul 2>&1

:: SvcHost split threshold — filet de sécurité en complément de FINALIZE5.cmd (SvcHostSplitDisable)
:: 0x40000000 = 1 Go. Un service ne dépassera jamais ça, donc le split est effectivement impossible.
echo [+] Configuring SvcHost split threshold...
reg add "HKLM\SYSTEM\ControlSet001\Control" /v "SvcHostSplitThresholdInKB" /t REG_DWORD /d 0x40000000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v "SvcHostSplitThresholdInKB" /t REG_DWORD /d 0x40000000 /f >nul 2>&1


goto :eof

:NetworkConfig
echo.
echo ================================================
echo     OPTIMISATION RESEAU UDP EXTRAS + EEE
echo ================================================
echo.

:: ================================================
:: 1. Disabling Energy Efficient Ethernet (EEE) — fix per-adapter
:: ================================================
echo [+] Disabling Energy Efficient Ethernet (EEE) per adapter...
powershell -NoProfile -Command ^
  "$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'; " ^
  "Get-ChildItem $regBase -ErrorAction SilentlyContinue | " ^
  "Where-Object { $_.PSChildName -match '^\d{4}$' } | " ^
  "ForEach-Object { " ^
    "$p = $_.PSPath; " ^
    "Set-ItemProperty -Path $p -Name '*EEE'                  -Value '0' -Type String -Force -EA 0; " ^
    "Set-ItemProperty -Path $p -Name 'EnableGreenEthernet'   -Value '0' -Type String -Force -EA 0; " ^
    "Set-ItemProperty -Path $p -Name 'PowerSavingMode'       -Value '0' -Type String -Force -EA 0; " ^
    "Set-ItemProperty -Path $p -Name '*SpeedPowerManagement' -Value '0' -Type String -Force -EA 0; " ^
    "Set-ItemProperty -Path $p -Name '*FlowControl'          -Value '0' -Type String -Force -EA 0; " ^
    "Set-ItemProperty -Path $p -Name '*InterruptModeration'  -Value 'off' -Type String -Force -EA 0; " ^
    "Write-Host ('[OK] Adapter: ' + $_.PSChildName) " ^
  "}" >nul 2>&1
echo [OK] EEE disabled on all adapter entries

:: ================================================
:: 2. UDP extras (non présents dans network-stack.yml)
:: ================================================
echo [+] UDP extra optimizations (gaming latency)...

:: RSC sur UDP — empêche la fusion des paquets (CS2, Valorant, Quake-like)
netsh int udp set global rsc=disabled >nul 2>&1 && echo [+] UDP RSC disabled || echo [-] UDP RSC failed

:: Checksum offload UDP — stabilité drivers Realtek/Killer
netsh int udp set global checksumoffload=disabled >nul 2>&1 && echo [+] UDP checksum offload disabled || echo [-] failed

:: GRO — très efficace Intel i225/i226 et Killer (2-8ms gain)
netsh int udp set global gro=disabled >nul 2>&1 && echo [+] UDP GRO disabled || echo [-] UDP GRO failed

:: Low latency UDP — réduit le buffering interne depuis Win11 24H2 (1-4ms gain 240Hz+)
netsh int udp set global lowlatency=enabled >nul 2>&1 && echo [+] UDP low latency enabled || echo [-] failed

  :: Flow control UDP — évite les pauses inutiles
netsh int udp set global flowcontrol=disabled >nul 2>&1 && echo [+] UDP flow control disabled || echo [-] failed

  :: ================================================
:: 3. Redémarrage des adaptateurs physiques
:: ================================================
echo [+] Restarting physical network adapters...
powershell -NoProfile -Command ^
  "Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceType -eq 6 -and $_.Name -notmatch 'vEthernet|Virtual|VPN|TAP|Loopback|Warp|Bluetooth' } | " ^
  "ForEach-Object { Disable-NetAdapter -Name $_.Name -Confirm:$false -EA 0; Start-Sleep -Milliseconds 500; Enable-NetAdapter -Name $_.Name -Confirm:$false -EA 0 }" >nul 2>&1
echo [OK] Network adapters restarted

:: ================================================
:: Success message
:: ================================================
echo.
echo ================================================
echo OPERATIONS COMPLETED SUCCESSFULLY!
echo ================================================
echo.
echo LexBoosT OS script applied
echo All optimizations have been configured.
echo.
timeout /t 5 /nobreak >nul

goto :eof
