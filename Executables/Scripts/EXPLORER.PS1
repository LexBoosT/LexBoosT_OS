#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Restarting as Administrator...'
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log { param([string]$Status, [string]$Message); Write-Host "[$Status] $Message" }

Write-Host '============================================'
Write-Host '       EXPLORER Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager'; Name = 'EnthusiastMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'ActiveWndTrkTimeout'; Value = '10'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'ActiveWndTrkTimeout'; Value = '10'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'AutoEndTasks'; Value = '1'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'AutoEndTasks'; Value = '1'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'HungAppTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'HungAppTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'WaitToKillAppTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'WaitToKillAppTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'LowLevelHooksTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'LowLevelHooksTimeout'; Value = '1000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'SmoothScroll'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'AutoColorization'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'SmoothScroll'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'ForegroundLockTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'ForegroundLockTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableXamlStartMenu'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SYSTEM\Control Panel\Desktop'; Name = 'WaitToKillServiceTimeout'; Value = '2000'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowInfoTip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowInfoTip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ExtendedUIHoverTime'; Value = '32'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ThumbnailLivePreviewHoverTime'; Value = '250'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowClockInNotificationCenter'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_Layout'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSecondsInSystemClock'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShouldPrelaunchFileExplorer'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SeparateProcess'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'DragFullWindows'; Value = '1'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'IconsOnly'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewAlphaSelect'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'FontSmoothing'; Value = '2'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'UseCompactMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTypeOverlay'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideMergeConflicts'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSuperHidden'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'PersistBrowsers'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowEncryptCompressedColor'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowStatusBar'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'AutoCheckSelect'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SharingWizardOn'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TypeAhead'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneShowAllCloudStates'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneExpandToCurrentFolder'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneShowAllFolders'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DesktopLivePreviewHoverTime'; Value = '250'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DesktopLivePreviewHoverTime'; Value = '250'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_NotifyNewApps'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackCachedFileUpdaterContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackConnectedSearchHistory'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackOpenPickerContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackSavePickerContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackSearchContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackShareContractMFU'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackCachedFileUpdaterContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackConnectedSearchHistory'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackOpenPickerContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackSavePickerContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackSearchContract'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackShareContractMFU'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DisablePreviewDesktop'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DisablePreviewWindow'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NoNetCrawling'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarFlashOverrideBreatheCount'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCortanaButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'CursorBlinkRate'; Value = '200'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowNotificationIcon'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'DstNotification'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackDocs'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LastActiveClick'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LastActiveClick'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarBadges'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarFlashing'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarSn'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarSd'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarGlomLevel'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarGlomLevel'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarCompanion'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'CopilotPWAPin'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'RecallPin'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'MenuShowDelay'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Desktop'; Name = 'MenuShowDelay'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'WaitForIdleState'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'; Name = 'FullPath'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'; Name = 'FullPath'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'SignInMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'TabletMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'ConvertibleSlateModePromptPreference'; Value = '2'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'SignInMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'TabletMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell'; Name = 'ConvertibleSlateModePromptPreference'; Value = '2'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAppsVisibleInTabletMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAppsVisibleInTabletMode'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAutoHideInTabletMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAutoHideInTabletMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'; Name = 'DisableAutoplay'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'; Name = 'DisableAutoplay'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotNudges'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Search\Preferences'; Name = 'WholeFileSystem'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'JPEGImportQuality'; Value = '100'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MultiTaskingAltTabFilter'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata'; Name = 'PreventDeviceMetadataFromNetwork'; Value = '1'; Type = 'REG_DWORD' }
)

$set = 0
foreach ($entry in $regValues) {
    try {
        if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
        $propType = switch ($entry.Type) { 'REG_SZ' { 'String' } 'REG_EXPAND_SZ' { 'ExpandString' } 'REG_DWORD' { 'DWord' } 'REG_BINARY' { 'Binary' } 'REG_NONE' { 'None' } default { 'String' } }
        New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $propType -Force -ErrorAction Stop | Out-Null
        $set++
    } catch { Write-Log '-' "Failed: $_" }
}

Write-Log '+' "$set registry values set"

exit 0