#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

Write-Host '============================================'
Write-Host '       Post-Install Finalization'
Write-Host '============================================'

# ============================================================
# Helper
# ============================================================
function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ============================================================
# 1. Group Policy Update
# ============================================================
Write-Log '+' 'Group Policy Update via gpupdate.exe...'
gpupdate.exe 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'gpupdate failed'
} else {
    Write-Log '+' 'gpupdate completed'
}

# ============================================================
# 2. Rebuild Performance Counters
# ============================================================
Write-Log '+' 'Rebuilding performance counters (lodctr /r)...'
lodctr /r 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'lodctr /r (pass 1) failed'
} else {
    Write-Log '+' 'lodctr /r (pass 1) OK'
}

lodctr /r 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'lodctr /r (pass 2) failed'
} else {
    Write-Log '+' 'lodctr /r (pass 2) OK'
}

# ============================================================
# 3. Resync WMI Performance
# ============================================================
Write-Log '+' 'Resyncing WMI performance counters (winmgmt /resyncperf)...'
winmgmt /resyncperf 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' 'winmgmt /resyncperf failed'
} else {
    Write-Log '+' 'winmgmt /resyncperf completed'
}

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
