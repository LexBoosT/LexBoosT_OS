#Requires -RunAsAdministrator
# =============================================================================
# LexBoosT OS — Disable Device Power Saving (PnP devices)
# Iterates every PnP device that has DevicePowerManagement keys and forces
# power-saving off (SelectiveSuspend, DeviceIdleEnabled, etc.) for desktop.
# =============================================================================

$ErrorActionPreference = 'Continue'
$LogDir  = Join-Path $env:windir 'LexBoosTOS\Logs'
$LogFile = Join-Path $LogDir 'disable-device-power-saving.log'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log {
    param([string]$msg)
    try { Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" } catch {}
}

Log 'Starting device power saving disable'

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Area, [string]$Target, [bool]$Success, [string]$Message)
    $null = $results.Add([pscustomobject]@{
        Area    = $Area
        Target  = $Target
        Success = $Success
        Message = $Message
    })
    $status = if ($Success) { 'OK' } else { 'FAIL' }
    Log "$status [$Area] $Target - $Message"
}

# --- Win32_PnPEntity: build map of name by PnP instance id ---
$pnpNameMap = @{}
try {
    $entities = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)
    foreach ($e in $entities) {
        if ($e.PNPDeviceID -and -not $pnpNameMap.ContainsKey($e.PNPDeviceID)) {
            $name = if ([string]::IsNullOrWhiteSpace($e.Name)) { $e.PNPDeviceID } else { $e.Name }
            $pnpNameMap[$e.PNPDeviceID] = $name
        }
    }
} catch {
    Add-Result 'Environment' 'Win32_PnPEntity' $false $_.Exception.Message
}

function Resolve-DeviceLabel {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $Id }
    if ($pnpNameMap.ContainsKey($Id)) { return $pnpNameMap[$Id] }
    return $Id
}

# --- Registry: DevicePowerManagement keys (USB selective suspend) ---
$instancePathRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
$usbSuspendKeys = @(
    'DevicePowerManagement',
    'DeviceIdleEnabled',
    'DeviceSelectiveSuspendEnabled',
    'SelectiveSuspendEnabled',
    'SelectiveSuspendTimeout',
    'PowerSaveEnabled'
)

$enumDirs = @()
try {
    $enumDirs = @(Get-ChildItem -Path $instancePathRoot -Recurse -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^\d+$' } |
        Select-Object -ExpandProperty PSPath)
} catch {
    Add-Result 'Registry' $instancePathRoot $false "Cannot enumerate: $($_.Exception.Message)"
}

foreach ($p in $enumDirs) {
    foreach ($key in $usbSuspendKeys) {
        $regPath = Join-Path $p $key
        if (Test-Path $regPath) {
            $label = Resolve-DeviceLabel (Split-Path $p -Leaf)
            try {
                # Only force-disable power-saving bits; preserve user-set timeouts when possible
                if ($key -match 'Enabled$|Suspend$|Save') {
                    Set-ItemProperty -Path $regPath -Name 'DevicePowerManagement' -Value 0 -Type DWord -ErrorAction Stop -Force
                    Set-ItemProperty -Path $regPath -Name 'DeviceIdleEnabled' -Value 0 -Type DWord -ErrorAction Stop -Force
                }
                Add-Result 'DevicePowerManagement' $label $true "Disabled: $p"
            } catch {
                Add-Result 'DevicePowerManagement' $label $false "Skip: $($_.Exception.Message)"
            }
        }
    }
}

# --- Print results summary ---
$ok = ($results | Where-Object { $_.Success }).Count
$ko = ($results | Where-Object { -not $_.Success }).Count
Log "Summary: $ok OK, $ko FAIL"
Write-Host "[+] Device power saving disabled: $ok OK, $ko FAIL"
exit 0
