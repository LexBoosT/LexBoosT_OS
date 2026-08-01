#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       Time & NTP Configuration'
Write-Host '============================================'

Write-Log '+' 'Starting w32time service...'
try {
    Start-Service -Name w32time -ErrorAction Stop
    Write-Log '+' 'w32time started'
} catch {
    Write-Log '-' "w32time start failed: $($_.Exception.Message)"
}

Write-Log '+' 'Configuring NTP peers...'
w32tm /config /syncfromflags:manual /manualpeerlist:"0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'w32tm /config failed'
} else {
    Write-Log '+' 'NTP peers configured'
}

Write-Log '+' 'Updating w32tm config...'
w32tm /config /update 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'w32tm /config /update failed'
} else {
    Write-Log '+' 'w32tm config updated'
}

Write-Log '+' 'Resyncing time...'
w32tm /resync 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'w32tm /resync failed (trying alternative)...'
    w32tm /resync /rediscover 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log '-' 'w32tm /resync /rediscover also failed'
    } else {
        Write-Log '+' 'w32tm resync completed (rediscover)'
    }
} else {
    Write-Log '+' 'Time synced successfully'
}

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
