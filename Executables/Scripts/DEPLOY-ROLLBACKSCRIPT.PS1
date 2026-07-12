#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$src = Join-Path (Split-Path (Get-Location)) 'Executables\Scripts\ROLLBACK.PS1'
$dstDir = Join-Path $env:ProgramData 'LexBoosTOS\Scripts'
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
Copy-Item -Path $src -Destination $dstDir -Force
Write-Log '+' "Rollback script deployed to $dstDir"
