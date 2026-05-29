$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Copying Launcher files...'
$scriptDir = Split-Path -Parent $PSCommandPath
$execDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

$destPath = Join-Path -Path $env:WINDIR 'LexBoosTOS\LexBoosT_Launcher'
if (-not (Test-Path $destPath)) {
    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
}

$sourcePath = Join-Path -Path $execDir 'LexBoosTLauncher'
if (Test-Path $sourcePath) {
    robocopy $sourcePath $destPath /E /PURGE /IS /IT /NP /NFL /NDL /R:3 /W:1
    if ($LASTEXITCODE -ge 8) {
        Write-Log '-' "robocopy failed (exit code $LASTEXITCODE), trying Copy-Item..."
        Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force -ErrorAction Stop
    }
    Write-Log '+' 'Launcher files deployed'
} else {
    Write-Log '-' 'LexBoosTLauncher folder not found'
}
# Exit cleanly
exit 0
