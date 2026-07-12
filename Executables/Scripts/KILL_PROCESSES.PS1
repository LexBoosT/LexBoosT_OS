#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       Kill Processes Pre-Setup'
Write-Host '============================================'

$phase1 = @(
    'TodoListManager',
    'SetTimerResolution',
    'LexBoosT_Ram_Cleaner',
    'LexBoost_Launcher',
    'HideIcons_Desktop',
    'Discord'
)

foreach ($proc in $phase1) {
    $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($p) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Write-Log '-' "Killed: $proc"
    } else {
        Write-Log '+' "Not running: $proc"
    }
}

$phase2 = @(
    'SearchApp',
    'SearchHost',
    'RuntimeBroker',
    'TextInputHost',
    'ShellExperienceHost',
    'backgroundTaskHost',
    'Widgets'
)

foreach ($proc in $phase2) {
    $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($p) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Write-Log '-' "Killed: $proc"
    } else {
        Write-Log '+' "Not running: $proc"
    }
}

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
