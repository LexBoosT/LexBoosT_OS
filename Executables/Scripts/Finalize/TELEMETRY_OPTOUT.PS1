#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       Telemetry Opt-Out'
Write-Host '============================================'

$vars = @(
    @{ Name = 'DOTNET_CLI_TELEMETRY_OPTOUT'; Value = '1'; Scope = 'User' },
    @{ Name = 'POWERSHELL_TELEMETRY_OPTOUT'; Value = '1'; Scope = 'User' },
    @{ Name = 'POWERSHELL_UPDATECHECK';      Value = 'Off'; Scope = 'User' }
)

foreach ($var in $vars) {
    [Environment]::SetEnvironmentVariable($var.Name, $var.Value, $var.Scope)
    Write-Log '+' "$($var.Name) = $($var.Value)"
}

Write-Log '+' 'All telemetry variables set'
Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
