#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

<<<<<<< HEAD
$src = Join-Path $PSScriptRoot 'ROLLBACK.PS1'
=======
$src = Join-Path (Split-Path (Get-Location)) 'Executables\Scripts\ROLLBACK.PS1'
>>>>>>> 0251bba90259c7b88ee0ce71c429e5c6fb1b4434
$dstDir = Join-Path $env:ProgramData 'LexBoosTOS\Scripts'
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
Copy-Item -Path $src -Destination $dstDir -Force
Write-Log '+' "Rollback script deployed to $dstDir"
