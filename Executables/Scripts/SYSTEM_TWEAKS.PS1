$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Applying YML system registry tweaks...'

# ================================================
# KERNEL / SESSION MANAGER
# ================================================

# Timer kernel tweaks
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'TimerCheckFlags' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'SerializeTimerExpiration' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'EnablePerCpuClockTickScheduling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
# GlobalTimerResolutionRequests laissé à son défaut (non modifié) — requis par TimerControl

# Memory Management
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'DisablePageCombining' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettings' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverride' /t REG_DWORD /d 3 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverrideMask' /t REG_DWORD /d 3 /f 2>&1 | Out-Null

# Power desktop-only
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v 'WatchdogResumeTimeout' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v 'WatchdogSleepTimeout' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v 'Win32CalloutWatchdogBugcheckEnabled' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v 'IdleScanInterval' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# DisableDiagnosticTracing
reg add 'HKLM\SYSTEM\CurrentControlSet001\Control\Diagnostics\Performance' /v 'DisableDiagnosticTracing' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# WINDOWS / RIT / DESKTOP HEAP
# ================================================

reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'RITdemonTimerPowerSaveElapse' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'RITdemonTimerPowerSaveCoalescing' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'ProcessDCEsInUseThreshold' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'DesktopHeapLogging' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# MULTIMEDIA / SYSTEM PROFILE (YML values)
# ================================================

# Priority Control
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' /v 'Win32PrioritySeparation' /t REG_DWORD /d 24 /f 2>&1 | Out-Null

# ================================================
# DIRECTX
# ================================================

reg add 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' /v 'DirectXUserGlobalSettings' /t REG_SZ /d 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;' /f 2>&1 | Out-Null

# DisableBandwidthThrottling — from misc.yml
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' /v 'DisableBandwidthThrottling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# Kernel DMA Protection DeviceEnumerationPolicy — from misc.yml
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection' /v 'DeviceEnumerationPolicy' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# EXPLORER DESKTOP TWEAKS
# NOTE: AutoEndTasks, HungAppTimeout, WaitToKillTimeout, WaitToKillServiceTimeout,
# InfoWindow, transparency, taskbar — kept in explorer.yml / themes.yml (YML only)
# WaitToKillServiceTimeout — from explorer.yml (no script existed)
# ================================================

# WaitToKillServiceTimeout — from explorer.yml
reg add 'HKLM\SYSTEM\CurrentControlSet\Control' /v 'WaitToKillServiceTimeout' /t REG_SZ /d 2000 /f 2>&1 | Out-Null

# InfoWindow color — from explorer.yml
reg add 'HKCU\Control Panel\Colors' /v 'InfoWindow' /t REG_SZ /d '246 253 255' /f 2>&1 | Out-Null

# Theme personalization — from explorer.yml (SystemUsesLightTheme, AppsUseLightTheme)
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v 'SystemUsesLightTheme' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v 'AppsUseLightTheme' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# Quick Access / Home removal — from explorer.yml
reg delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' /f 2>&1 | Out-Null
reg delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' /f 2>&1 | Out-Null

# Taskbar / LaunchTo — from explorer.yml
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v 'TaskbarBadges' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v 'TaskbarFlashing' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

Write-Log '+' 'System tweaks applied'
exit 0
