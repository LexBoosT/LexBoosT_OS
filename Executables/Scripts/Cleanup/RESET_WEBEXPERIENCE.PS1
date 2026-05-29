$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Resetting WebExperience widget package...'
$null = Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -ErrorAction SilentlyContinue | Reset-AppxPackage -ErrorAction SilentlyContinue
Write-Log '+' 'WebExperience reset'
# Exit cleanly
exit 0
