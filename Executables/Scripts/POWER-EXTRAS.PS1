#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Additional safe power optimizations for desktop low-latency systems.
.DESCRIPTION
    Disables hibernation and hybrid sleep on desktops, and forces
    sleep-after and disk-off timers to 0 on AC power.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Test-IsLaptop {
    $mobileChassisTypes = @(8, 9, 10, 11, 12, 13, 14, 18, 21, 30, 31, 32)
    try {
        $chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop
        if ($chassis.ChassisTypes | Where-Object { $_ -in $mobileChassisTypes }) { return $true }
    } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PCSystemType -eq 2 -or $cs.PCSystemTypeEx -in @(2, 8)) { return $true }
    } catch {}
    try {
        if (Get-CimInstance Win32_Battery -ErrorAction Stop) { return $true }
    } catch {}
    return $false
}

$isLaptop = Test-IsLaptop

# -----------------------------------------------------------------------------
# 1. Disable hibernation on desktops
# -----------------------------------------------------------------------------
if (-not $isLaptop) {
    Write-Log '+' 'Desktop detected: disabling hibernation...'
    try {
        powercfg /hibernate off | Out-Null
        Write-Log '+' 'Hibernation disabled'
    } catch {
        Write-Log '-' "Could not disable hibernation: $_"
    }
} else {
    Write-Log '+' 'Laptop detected: keeping hibernation enabled'
}

# -----------------------------------------------------------------------------
# 2. Disable hybrid sleep and set AC timers to never
# -----------------------------------------------------------------------------
Write-Log '+' 'Configuring AC power timers...'
try {
    $active = (powercfg /getactivescheme).Split(' ')[3]
    if ($active -and $active -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        powercfg /setacvalueindex $active SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
        powercfg /setacvalueindex $active SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
        powercfg /setacvalueindex $active SUB_SLEEP STANDBYIDLE 0 | Out-Null
        powercfg /setdcvalueindex $active SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
        powercfg /setacvalueindex $active SUB_DISK DISKIDLE 0 | Out-Null
        powercfg /setactive $active | Out-Null
        Write-Log '+' 'AC timers configured'
    } else {
        Write-Log '-' 'Could not determine active power scheme'
    }
} catch {
    Write-Log '-' "Could not configure power timers: $_"
}

Write-Log '+' 'Power extras applied.'
exit 0
