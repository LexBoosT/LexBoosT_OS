@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE2.CMD - GAMING OPTIMIZATIONS
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. GAMING PERFORMANCE
call :GamingOptimizations

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

:GamingOptimizations
echo.
echo ================================================
echo GAMING OPTIMIZATIONS
echo ================================================

:: Disable USB selective suspend — NOTE: Already handled by extreme-performance-optimization.yml
echo [+] USB selective suspend already disabled via registry

:: Disable network card power saving
echo [+] Disabling network card power saving...
PowerShell -WindowStyle Hidden -Command "try { Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {($_.NetEnabled -eq $true) -and ($_.Name -like '*Ethernet*' -or $_.Name -like '*Network*')} | ForEach-Object { $path='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\'+$_.GUID; if (Test-Path $path) { Set-ItemProperty $path PowerSavingMode 0 -Force -ErrorAction SilentlyContinue; Write-Output ('Disabled: '+$_.Name) } else { Write-Warning ('Skipped: '+$path) } } } catch { Write-Warning 'Failed to disable network card power saving' }" >nul 2>&1

:: Audio Tweaks
echo [+] Disabling Nagle's Algorithm...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" /v FastSendDatagramThreshold /t REG_DWORD /d 1500 /f >nul 2>&1

:: Audio Tweaks
echo [+] Audio optimizations...
:: NOTE: GPU Priority set to 8 (HIGH) instead of 31 (REALTIME) to avoid GPU driver conflicts
:: REALTIME priority can interfere with GPU scheduling and cause display/BSOD issues
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v Affinity /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v BackgroundPriority /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Background Only" /t REG_SZ /d True /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Clock Rate" /t REG_DWORD /d 10000 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v Priority /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Scheduling Category" /t REG_SZ /d High /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "SFIO Priority" /t REG_SZ /d High /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Latency Sensitive" /t REG_SZ /d True /f >nul 2>&1

reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v Affinity /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v BackgroundPriority /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "Background Only" /t REG_SZ /d True /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "Clock Rate" /t REG_DWORD /d 10000 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v Priority /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "Scheduling Category" /t REG_SZ /d High /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "SFIO Priority" /t REG_SZ /d High /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio" /v "Latency Sensitive" /t REG_SZ /d True /f >nul 2>&1

:: Pro Audio Format — 24bit/48kHz (studio standard for gaming)
echo [+] Configuring Pro Audio format (24bit/48kHz)...
powershell -NoProfile -Command ^
  "$devices = Get-CimInstance Win32_SoundDevice | Where-Object { $_.Status -eq 'OK' -and $_.PNPDeviceID -notmatch 'HDAUDIO\\FUNC_01&VEN_8086' }; " ^
  "foreach ($dev in $devices) { " ^
    "$path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'; " ^
    "$keys = Get-ChildItem $path -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PSPath -Name 'DeviceDesc' -EA 0).DeviceDesc -match $dev.Name.Substring(0,10) }; " ^
    "foreach ($k in $keys) { " ^
      "Set-ItemProperty -Path ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\' + $k.PSChildName + '\Properties') -Name '{e4870e26-3cc5-4cd2-ba46-ca0a9a70ed04},3' -Value 24 -Type DWord -Force -EA 0; " ^
      "Set-ItemProperty -Path ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\' + $k.PSChildName + '\Properties') -Name '{e4870e26-3cc5-4cd2-ba46-ca0a9a70ed04},4' -Value 48000 -Type DWord -Force -EA 0 " ^
    "} " ^
  "} " ^
  "Write-Host '[OK] Audio format set to 24bit/48kHz'" >nul 2>&1

:: Disable power saving on storage devices - STABLE
echo [+] Disabling storage power saving...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Storage" /v StorageD3InModernStandby /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable disk defrag
echo [+] Disabling disk defragmentation...
reg add "HKLM\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction" /v Enable /t REG_SZ /d N /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout" /v EnableAutoLayout /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable persistent timestamp refresh
echo [+] Disabling timestamp refresh...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability" /v TimeStampInterval /t REG_DWORD /d 0 /f >nul 2>&1

:: File system tweaks
echo [+] File system optimizations...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsMemoryUsage /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsAllowExtendedCharacter8dot3Rename /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsBugcheckOnCorrupt /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisableCompression /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisableEncryption /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsEncryptPagingFile /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v RefsDisableLastAccessUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v UdfsSoftwareDefectManagement /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v Win31FileSystem /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v FileNameCache /t REG_DWORD /d 1024 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v PathCache /t REG_DWORD /d 128 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v ContigFileAllocSize /t REG_DWORD /d 1536 /f >nul 2>&1
:: NOTE: DisableLastAccess and 8dot3NameCreation are handled by FINALIZE1.cmd (fsutil)

:: Disable FTH (Fault Tolerant Heap)
echo [+] Disabling FTH...
reg add "HKLM\Software\Microsoft\FTH" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
REG QUERY "HKLM\SOFTWARE\Microsoft\FTH\State" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    REG DELETE "HKLM\SOFTWARE\Microsoft\FTH\State" /f >nul 2>&1
)

:: Memory optimizations
echo [+] Memory optimizations...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v HeapDeCommitFreeBlockThreshold /t REG_DWORD /d 40000 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v CacheUnmapBehindLengthInMB /t REG_DWORD /d 100 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v ModifiedWriteMaximum /t REG_DWORD /d 20 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v NonPagedPoolSize /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v SimulateCommitSavings /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v TrackLockedPages /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v TrackPtes /t REG_DWORD /d 0 /f >nul 2>&1

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v AlpcWakePolicy /t REG_DWORD /d 1 /f >nul 2>&1

:: Thread priorities
echo [+] Configuring thread priorities...
:: NOTE: 0x0f (15 = HIGH) choisi au lieu de 0x1f (31 = REALTIME) pour la souris/clavier.
:: REALTIME (31) peut provoquer des DPC storms et des freezes système sous charge.
:: 15 donne une réactivité maximale sans risque de starvation des threads critiques.
reg add "HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" /v ThreadPriority /t REG_DWORD /d 0x0000000f /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters" /v ThreadPriority /t REG_DWORD /d 0x0000000f /f >nul 2>&1

:: Advanced gaming optimizations
echo [+] Advanced gaming optimizations...

:: NOTE: GPU optimizations are handled by GPUTweaks (AMD/NVIDIA driver tweaks, shader cache, ULPS)

:: Network Gaming Optimizations
echo [+] Network gaming optimizations...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\QoS" /v "GamingQoS" /t REG_SZ /d "1" /f >nul 2>&1

:: CPU Gaming Optimizations
echo [+] CPU gaming optimizations...

:: USB Gaming Optimizations
echo [+] USB gaming optimizations...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USBXHCI\Parameters\Wdf" /v "NoExtraBufferRoom" /t REG_DWORD /d "1" /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\usbflags" /v "GlobalDisableSerNumGen" /t REG_DWORD /d "1" /f >nul 2>&1

:: disable suggestions in the search box and in search home
echo [+] Disable suggestions in the search box and in search home
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsDynamicSearchBoxEnabled /t REG_DWORD /d 0 /f >nul 2>&1

:: disable system responsiveness diagnostics
echo [+] Disable system responsiveness diagnostics
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{a7a5847a-7511-4e4e-90b1-45ad2a002f51}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{a7a5847a-7511-4e4e-90b1-45ad2a002f51}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{a7a5847a-7511-4e4e-90b1-45ad2a002f51}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{a7a5847a-7511-4e4e-90b1-45ad2a002f51}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{186f47ef-626c-4670-800a-4a30756babad}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{186f47ef-626c-4670-800a-4a30756babad}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{ecfb03d1-58ee-4cc7-a1b5-9bc6febcb915}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{ecfb03d1-58ee-4cc7-a1b5-9bc6febcb915}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1

:: disable windows boot performance diagnostics
echo [+] Disable windows boot performance diagnostics
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{67144949-5132-4859-8036-a737b43825d8}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{67144949-5132-4859-8036-a737b43825d8}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{67144949-5132-4859-8036-a737b43825d8}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{67144949-5132-4859-8036-a737b43825d8}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{86432a0b-3c7d-4ddf-a89c-172faa90485d}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{86432a0b-3c7d-4ddf-a89c-172faa90485d}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1

:: disable memory leak diagnostics
echo [+] Disable memory leak diagnostics
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{eb73b633-3f4e-4ba0-8f60-8f3c6f53168f}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{eb73b633-3f4e-4ba0-8f60-8f3c6f53168f}" /v EnabledScenarioExecutionLevel /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{eb73b633-3f4e-4ba0-8f60-8f3c6f53168f}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{eb73b633-3f4e-4ba0-8f60-8f3c6f53168f}" /v EnabledScenarioExecutionLevel /t REG_DWORD /d 1 /f >nul 2>&1

:: disable shutdown performance diagnostics
echo [+] Disable shutdown performance diagnostics
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{2698178D-FDAD-40AE-9D3C-1371703ADC5B}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WDI\{2698178D-FDAD-40AE-9D3C-1371703ADC5B}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{2698178D-FDAD-40AE-9D3C-1371703ADC5B}" /v ScenarioExecutionEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\WDI\{2698178D-FDAD-40AE-9D3C-1371703ADC5B}" /v EnabledScenarioExecutionLevel /t REG_SZ /d "" /f >nul 2>&1

:: Disable Home etc in file explorer
echo [+] Disable Home, Quick Access, OneDrive etc in file explorer...
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}" /f >nul 2>&1
reg add "HKCU\SOFTWARE\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Classes\CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Classes\CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >nul 2>&1

echo [+] Disable TOUCH SCREEN Advanced Stuff (only if no touch device detected)
:: Vérifie si un périphérique tactile est présent avant de désactiver.
:: Sur un desktop sans écran tactile, toutes les entrées suivantes sont appliquées.
:: Sur un laptop avec touchpad/touchscreen, cette section est ignorée pour préserver la navigation.
powershell -NoP -Command "$hasTouchOrPen = (Get-PnpDevice -Class 'HIDClass','Pen' -Status OK -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Touch|Pen|Stylus|Digitizer|HID-compliant touch' }) -or (Get-CimInstance Win32_PointingDevice | Where-Object { $_.Name -match 'Touch|Touchpad|HID' }); exit ([int]($hasTouchOrPen -ne $null -and $hasTouchOrPen))" >nul 2>&1
if %errorlevel% equ 1 (
    echo [SKIP] Touch/Pen device detected - skipping touchscreen disable to preserve input
) else (
reg add "HKCU\Control Panel\Accessibility" /v "TouchFeedback" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "TouchGestureSetting" /t REG_DWORD /d 0 /f >nul 2>&1
:: Fucking Win+V clipboard history shortcut fixed by Alcopsy
reg delete "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v "DisableNewKeyboardExperience" /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableCompatibilityKeyboard" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableDesktopModeAutoInvoke" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v "KeyboardLayoutPreference" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v "UserKeyboardScalingFactor" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TouchMode" /v "ShowTouchModeButton" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PenWorkspace" /v "PenWorkspaceButtonDesiredVisibility" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Wisp\Pen\Flicks" /v "EnableFlicks" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Wisp\Pen\PenFeedback" /v "TurnOnPressAndHold" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Wisp\Touch" /v "TouchGate" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" /v "EnableVirtualTouchpad" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\TabletPC" /v "TurnOffTouchInput" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Synaptics\SynTPPlugins\SynTP" /v "3FingerTapAction" /t REG_DWORD /d 0x0000000 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Synaptics\SynTPPlugins\SynTP" /v "4FingerTapAction" /t REG_DWORD /d 0x0000000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TabletPC" /v "EnableTouch" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\PenService" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
)

goto :eof
