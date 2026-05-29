$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Disabling Remote Assistance firewall rule...'
netsh advfirewall firewall set rule group='Remote Assistance' new enable=no *>$null
Write-Log '+' 'Remote Assistance firewall disabled'
# Exit cleanly
exit 0
