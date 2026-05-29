@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE1.CMD - ADMINISTRATOR VERIFICATION & SYSTEM OPTIMIZATIONS
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. SYSTEM OPTIMIZATIONS
call :SystemOptimizations

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

:SystemOptimizations
echo.
echo ================================================
echo SYSTEM OPTIMIZATIONS
echo ================================================

:: SSD optimization
echo [+] SSD optimization...
set "diskDrive="
for /f "delims=" %%a in ('PowerShell -NoP -C "try { $driveLetter = $env:SystemDrive.Substring(0,1); $disk = Get-Disk -Number (Get-Partition -DriveLetter $driveLetter).DiskNumber; $physicalDisk = Get-PhysicalDisk -SerialNumber $disk.SerialNumber.TrimStart(); $physicalDisk.MediaType } catch { 'HDD' }" 2^>nul') do (
    set "diskDrive=%%a"
)

if /i "!diskDrive!" == "SSD" (
    echo [+] SSD detected, applying optimizations...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1
) else (
    echo [+] HDD detected, ignored optimizations...
)

:: Boot configuration & branding
echo [+] Boot configuration...
bcdedit /set {current} bootmenupolicy legacy >nul 2>&1
bcdedit /set {current} description "LexBoosT OS 26.06" >nul 2>&1
label LexBoosT_OS >nul 2>&1

:: Optimize NTFS
echo [+] NTFS optimization...
fsutil behavior set disableLastAccess 1 >nul 2>&1
fsutil behavior set 8dot3name 1 >nul 2>&1
fsutil behavior set memoryusage 2 >nul 2>&1
fsutil behavior set mftzone 4 >nul 2>&1
fsutil behavior set encryptpagingfile 0 >nul 2>&1
fsutil behavior set disablecompression 1 >nul 2>&1
fsutil behavior set disableencryption 1 >nul 2>&1

:: Disable search indexing on non-system drives (reduces I/O micro-stutters during gaming)
echo [+] Disabling search indexing on game drives...
powershell -NoProfile -Command "$sysLetter = $env:SystemDrive.Substring(0,1); Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne $sysLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { $drive = \"$($_.DriveLetter):\"; try { $folder = Get-Item $drive -Force; $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed; Write-Host ('[OK] Indexing disabled on ' + $drive) } catch { Write-Warning ('Failed on ' + $drive + ': ' + $_.Exception.Message) } }; Write-Host '[INFO] System drive indexing preserved for Windows Search functionality'" >nul 2>&1

:: Configuring teredo
echo [+] Configuring Teredo...
netsh interface Teredo set state type=default >nul 2>&1
netsh interface Teredo set state servername=default >nul 2>&1

:: Configuring Windows settings
echo [+] Configuring Windows settings...
net accounts /maxpwage:unlimited >nul 2>&1

:: turn off smart card plug and play service
echo [+] Turn off smart card plug and play service
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\ScPnP" /v EnableScPnP /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\ScPnP" /v EnableScPnP /t REG_DWORD /d 0 /f >nul 2>&1

:: disable notifications network usage
echo [+] Disable notifications network usage
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" /v NoCloudApplicationNotification /t REG_DWORD /d 1 /f >nul 2>&1

echo [+] Notifications Settings
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\QuietHours" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.AutoPlay" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.LowDisk" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Print.Notification" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.WiFiNetworkManager" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1

:: Native NVMe driver optimization - STABLE MODE
echo [+] Native NVMe driver optimization (Stable Mode)
rem NativeNVMePerformance: 0 = Mode compatible (évite problèmes NVMe Gen4/Gen5)
rem 1 = Mode performance mais peut causer instabilité sur certains NVMe
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NativeNVMePerformance /t REG_DWORD /d 0 /f >nul 2>&1
rem FeatureManagement Overrides - désactivés pour stabilité
reg delete "HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /f >nul 2>&1


:: block enumeration policy for external dma protected devices
echo [+] Block enumeration policy for external dma protected devices
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection" /v DeviceEnumerationPolicy /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\Kernel DMA Protection" /v DeviceEnumerationPolicy /t REG_DWORD /d 0 /f >nul 2>&1

:: disable typing insights
echo [+] Disable typing insights
reg add "HKCU\SOFTWARE\Microsoft\input\Settings" /v InsightsEnabled /t REG_DWORD /d 0 /f >nul 2>&1

:: disable app-v
echo [+] Disable app-v
reg add "HKLM\SOFTWARE\Microsoft\AppV\Client" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\AppV\Client" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\AppV\Client" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1

:: disable superfetch's eventlog connection
echo [+] Disable superfetch's eventlog connection
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Superfetch/Main" /v Enable /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Superfetch/PfApLog" /v Enable /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Superfetch/StoreLog" /v Enable /t REG_DWORD /d 0 /f >nul 2>&1

:: disable device health attestation
echo [+] Disable device health attestation
reg add "HKLM\SOFTWARE\Policies\Microsoft\DeviceHealthAttestationService" /v EnableDeviceHealthAttestationService /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\DeviceHealthAttestationService" /v EnableDeviceHealthAttestationService /t REG_DWORD /d 0 /f >nul 2>&1

:: disable font providers
echo [+] Disable font providers
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableFontProviders /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\System" /v EnableFontProviders /t REG_DWORD /d 0 /f >nul 2>&1

:: disable wmp media sharing
echo [+] Disable wmp media sharing
reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" /v PreventLibrarySharing /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\WindowsMediaPlayer" /v PreventLibrarySharing /t REG_DWORD /d 1 /f >nul 2>&1

:: Enable high-resolution timer requests (0.5ms)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v GlobalTimerResolutionRequests /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable ESP padding (potentially reduces latency on some UEFI systems).
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Bfsvc" /v EspPaddingPercent /t REG_DWORD /d 0 /f >nul 2>&1

:: ================================================
:: PAGEFILE — INTELLIGENT SIZING
:: ================================================
echo [+] Configuring pagefile based on RAM...
powershell -NoProfile -Command ^
  "$ramGB = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB); " ^
  "$sysDrive = $env:SystemDrive; " ^
  "if ($ramGB -le 8) { " ^
    "$min = 1024; $max = 4096 " ^
  "} elseif ($ramGB -le 16) { " ^
    "$min = 1024; $max = 8192 " ^
  "} elseif ($ramGB -le 32) { " ^
    "$min = 2048; $max = 16384 " ^
  "} else { " ^
    "$min = 4096; $max = 32768 " ^
  "} " ^
  "$cs = Get-CimInstance Win32_ComputerSystem; " ^
  "$cs.AutomaticManagedPagefile = $false; " ^
  "Set-CimInstance -InputObject $cs; " ^
  "Set-CimInstance -Query 'SELECT * FROM Win32_PageFileSetting' -Property @{InitialSize=$min; MaximumSize=$max} -ErrorAction SilentlyContinue; " ^
  "Write-Host ('[OK] Pagefile: ' + $min + '-' + $max + ' MB (RAM: ' + $ramGB + ' GB)')" >nul 2>&1

goto :eof
