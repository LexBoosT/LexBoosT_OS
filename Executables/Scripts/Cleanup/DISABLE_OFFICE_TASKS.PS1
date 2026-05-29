$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Disabling Office scheduled tasks...'
Get-ScheduledTask -TaskPath '\Microsoft\Office\*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
Write-Log '+' 'Office tasks disabled'
# Exit cleanly
exit 0
