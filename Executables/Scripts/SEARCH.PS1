#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Restarting as Administrator...'
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       SEARCH Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarModeCache'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'HistoryViewEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'HasAboveLockTips'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'AllowSearchToUseLocation'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'SafeSearchMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LastActiveClick'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LastActiveClick'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Chat'; Name = 'ChatIcon'; Value = '3'; Type = 'REG_DWORD' }
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
    @{ Path = 'Registry::HKCU\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify'; Name = 'SystemTrayChevronVisibility'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\TabletTip\1.7'; Name = 'TipbandDesiredVisibility'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarCompanion'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'CopilotPWAPin'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'RecallPin'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowCommercialDataPipeline'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowDeviceNameInTelemetry'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableEnterpriseAuthProxy'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'MicrosoftEdgeDataOptIn'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableTelemetryOptInChangeNotification'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableTelemetryOptInSettingsUx'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitEnhancedDiagnosticDataWindowsAnalytics'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDumpCollection'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\System'; Name = 'AllowExperimentation'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Diagtrack-Listener'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SQMLogger'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SetupPlatformTel'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Circular Kernel Context Logger'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DiagLog'; Name = 'Start'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\LwtNetLog'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\NtfsLog'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\ReFSLog'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\UBPM'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiSession'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Cellcore'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\CimFSUnionFS-Filter'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\FaceTel'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\FilterMgr-Logger'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\HolographicDevice'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Mellanox-Kernel'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Microsoft-Windows-AssignedAccess-Trace'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Microsoft-Windows-Setup'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\NBSMLOGGER'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\PEAuthLog'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\RdrLog'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\ReadyBoot'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SetupPlatform'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SpoolerLogger'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\TCPIPLOGGER'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\TileStore'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Tpm'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WdiContextLog'; Name = 'Start'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WFP-IPsec Trace'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverHVSession'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverHVSessionRepro'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverIHVSession'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverIHVSessionRepro'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WMI_Traces'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PerfTrack'; Name = 'Disabled'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; Name = 'ShowedToastAtLevel'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CPSS\Store\ImproveInkingAndTyping'; Name = 'Value'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDeviceSearchHistoryEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsMSACloudSearchEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsAADCloudSearchEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Narrator\NoRoam'; Name = 'OnlineServicesEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Narrator\NoRoam'; Name = 'ScriptingEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization'; Name = 'Value'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowDesktopAnalyticsProcessing'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowWUfBCloudProcessing'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowUpdateComplianceProcessing'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'MaxTelemetryAllowed'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableFontProviders'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReporting'; Name = 'PreventHandwritingData'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\WcmSvc\wifiservice'; Name = 'WifiSense'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'; Name = 'DisablePassivePolling'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\Photos'; Name = 'DisableCameraUpload'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupProfile'; Name = 'EnableStartupTelemetry'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\WindowsStore'; Name = 'DisableStoreTelemetry'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\WinSAT'; Name = 'DisableWinSAT'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableSharedPCMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'; Name = 'RestrictDriverInstallationToAdministrators'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer\SQM'; Name = 'DisableCustomerExperienceImprovementProgram'; Value = '0'; Type = 'REG_DWORD' }
)

$set = 0
foreach ($entry in $regValues) {
    try {
        if (-not (Test-Path $entry.Path)) {
            New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null
        }
        $propType = switch ($entry.Type) {
            'REG_SZ'        { 'String' }
            'REG_EXPAND_SZ' { 'ExpandString' }
            'REG_DWORD'     { 'DWord' }
            'REG_BINARY'    { 'Binary' }
            'REG_NONE'      { 'None' }
            default         { 'String' }
        }
        New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $propType -Force -ErrorAction Stop | Out-Null
        $set++
    } catch {
        Write-Log '-' "Failed to set $($entry.Path)\$($entry.Name): $_"
    }
}

# --- Protected autologger keys: require TrustedInstaller ---
$protectedAutologgers = @(
    @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\NetCore'; Value = 0 }
    @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\RadioMgr'; Value = 0 }
)

$minSudo = Join-Path $env:windir 'LexBoosTOS\Utilities\MinSudo.exe'
foreach ($auto in $protectedAutologgers) {
    $key = $auto.Path
    $val = $auto.Value
    try {
        $regCmd = "reg add `"$key`" /v Start /t REG_DWORD /d $val /f"
        if (Test-Path $minSudo) {
            $proc = Start-Process -FilePath $minSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged cmd.exe /c `"$regCmd`"" -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -eq 0) { $set++; Write-Log '+' "Set protected key: $key"; continue }
        }
        # fallback: direct attempt
        Invoke-Expression $regCmd | Out-Null
        if ($LASTEXITCODE -eq 0) { $set++; Write-Log '+' "Set protected key: $key" } else { throw "reg exit $LASTEXITCODE" }
    } catch {
        Write-Log '-' "Failed to set protected key ${key}: $_"
    }
}

Write-Log '+' "$set registry values set"
Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0