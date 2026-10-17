#Requires -Version 5.1

# ============================================================
# SVC-SPLIT-DISABLE.PS1
#
# Single source of truth for the "service host splitting" logic
# (SvcHostSplitDisable). SELECTIVE logic with the protected
# service set (Xbox/NVIDIA/VM).
#
# Behavior:
#   1. REMOVES SvcHostSplitDisable on the full $RmvList
#      (60 services) -> undoes the old "group everything in svchost" tweak.
#   2. If total RAM is < $RamLimitGb (default 8 GB):
#      creates SvcHostSplitDisable = 1 (DWord) on the reduced
#      $ApplyList (36 services), skipping the protected services.
#      (machines with >= 8 GB don't need the regrouping)
#
# PROTECTED SERVICES ($Exclude): Xbox/GameBar, NVIDIA/GPU and
# VM/Hyper-V integration services NEVER receive SvcHostSplitDisable=1
# (do not merge these services into the main svchost,
# risk of breaking the GPU / the VM).
#
# Called by services.yml (Phase 3), elevated (runas: currentUserElevated).
# ============================================================

[CmdletBinding()]
param (
    [int]$RamLimitGb = 8
)

$ErrorActionPreference = 'Continue'

$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Services\'

# --- RmvList (60 services): SvcHostSplitDisable is ALWAYS removed here ---
$RmvList = @(
    'DisplayEnhancementService', 'PcaSvc', 'WdiSystemHost', 'WdiServiceHost',
    'AudioEndpointBuilder', 'DeviceAssociationService', 'NcbService', 'StorSvc',
    'SysMain', 'TextInputManagementService', 'TrkWks', 'hidserv', 'Appinfo',
    'BITS', 'LanmanServer', 'SENS', 'Schedule', 'ShellHWDetection', 'Themes',
    'TokenBroker', 'UserManager', 'ProfSvc', 'UsoSvc', 'WpnService', 'gpsvc',
    'iphlpsvc', 'wuauserv', 'WinHttpAutoProxySvc', 'EventLog', 'TimeBrokerSvc',
    'lmhosts', 'Dhcp', 'FontCache', 'nsi', 'netprofm', 'SstpSvc', 'DispBrokerDesktopSvc',
    'CDPSvc', 'EventSystem', 'LicenseManager', 'SystemEventsBroker', 'Power', 'AppXSvc',
    'ClipSVC', 'camsvc', 'StateRepository', 'FDResPub', 'SSDPSRV', 'Dnscache', 'NlaSvc',
    'LanmanWorkstation', 'CoreMessagingRegistrar', 'DPS', 'NcdAutoSetup', 'bthserv',
    'WbioSrvc', 'TabletInputService', 'WlanSvc', 'Wecsvc', 'wscsvc'
)

# --- ApplyList (36 services): =1 is created here only if RAM < limit ---
$ApplyList = @(
    'DisplayEnhancementService', 'PcaSvc', 'WdiSystemHost', 'WdiServiceHost',
    'DeviceAssociationService', 'NcbService', 'StorSvc', 'TrkWks', 'Appinfo',
    'Schedule', 'TokenBroker', 'UsoSvc', 'WpnService', 'iphlpsvc', 'nsi',
    'WinHttpAutoProxySvc', 'TimeBrokerSvc', 'lmhosts', 'FontCache', 'wscsvc',
    'netprofm', 'SstpSvc', 'DispBrokerDesktopSvc', 'CDPSvc', 'EventSystem',
    'LicenseManager', 'SystemEventsBroker', 'ClipSVC', 'camsvc', 'FDResPub',
    'SSDPSRV', 'CoreMessagingRegistrar', 'NcdAutoSetup', 'bthserv', 'WbioSrvc',
    'Wecsvc'
)

# --- PROTECTED SERVICES: never SvcHostSplitDisable=1 ---
# Xbox/GameBar, NVIDIA/GPU, VM/Hyper-V integration. Case-insensitive regex.
$Exclude = 'Xbl|Xbox|NV|NVIDIA|NvContainer|NvTelemetry|NVDisplay|vmic|vmms|vmcompute|HvHost|nvspwmi|vmwp'

Write-Host ('[1/2] Removing SvcHostSplitDisable from the full list ({0} services)...' -f $RmvList.Count)
$removed = 0
foreach ($svc in $RmvList) {
    $path = $regBase + $svc
    try {
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name 'SvcHostSplitDisable' -ErrorAction Stop
            $removed++
        }
    } catch { }
}
Write-Host ('      {0} values removed' -f $removed)

# Reading RAM
$memgb = 0
try {
    $memgb = [math]::Round( (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 2)
} catch {
    Write-Host ('      (unable to read RAM: ' + $_.Exception.Message + ')')
}

if ($memgb -lt $RamLimitGb) {
    Write-Host ('[2/2] RAM = {0} GB (< {1}): applying SvcHostSplitDisable=1 on the reduced list ({2} services)...' -f $memgb, $RamLimitGb, $ApplyList.Count)
    $applied = 0
    $skipped = 0
    foreach ($svc in $ApplyList) {
        if ($svc -match $Exclude) {
            $skipped++
            Write-Host ('      ! {0} excluded (Xbox/NVIDIA/VM protection)' -f $svc)
            continue
        }
        $path = $regBase + $svc
        try {
            if (Test-Path $path) {
                Set-ItemProperty -Path $path -Name 'SvcHostSplitDisable' -Value 1 -Type DWord
                $applied++
            }
        } catch { }
    }
    Write-Host ('      {0} applied, {1} excluded' -f $applied, $skipped)
}
else {
    Write-Host ('[2/2] RAM = {0} GB (>= {1}): no SvcHostSplitDisable to apply (regrouping unnecessary)' -f $memgb, $RamLimitGb)
}
