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
Write-Host '       GRAPHICS Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace'; Name = 'Start'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Value = '2'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers'; Name = 'DisableVersionMismatchCheck'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers\Scheduler'; Name = 'AdjustWorkerThreadPriority'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers\Scheduler'; Name = 'AudioDgAutoBoostPriority'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers\Scheduler'; Name = 'AutoSyncToCPUPriority'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers\Scheduler'; Name = 'ForegroundPriorityBoost'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\ControlSet001\Control\GraphicsDrivers\Scheduler'; Name = 'FrameServerAutoBoostPriority'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DirectStorage'; Name = 'EnableDirectStorage'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DirectStorage'; Name = 'EnableOptimizations'; Value = '1'; Type = 'REG_DWORD' }
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