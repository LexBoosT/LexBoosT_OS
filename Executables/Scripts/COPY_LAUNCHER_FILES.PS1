$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Copying Launcher files...'
# LexBoosTLauncher is a sibling of Scripts/, directly under Executables/.
# From PSScriptRoot (Executables/Scripts), go up ONE level to reach Executables.
$scriptDir = Split-Path -Parent $PSCommandPath
$execDir = Split-Path -Parent $scriptDir

$destPath = Join-Path -Path $env:WINDIR 'LexBoosTOS\LexBoosT_Launcher'
if (-not (Test-Path $destPath)) {
    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
}

$sourcePath = Join-Path -Path $execDir 'LexBoosTLauncher'
if (Test-Path $sourcePath) {
    Write-Log '+' "Source: $sourcePath"
    Write-Log '+' "Destination: $destPath"
    robocopy "$sourcePath" "$destPath" /E /PURGE /IS /IT /NP /NFL /NDL /R:3 /W:1
    if ($LASTEXITCODE -ge 8) {
        Write-Log '-' "robocopy exit code $LASTEXITCODE — falling back to Copy-Item..."
        try {
            Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log '-' "Copy-Item failed: $_"
        }
    }
    # Verify files are present
    $copied = @(Get-ChildItem -Path $destPath -File -ErrorAction SilentlyContinue).Count
    if ($copied -gt 0) {
        Write-Log '+' "Launcher files deployed ($copied file(s))"
    } else {
        Write-Log '-' "Destination $destPath is empty after copy"
    }
} else {
    Write-Log '-' "LexBoosTLauncher folder not found at: $sourcePath"
}
# Exit cleanly
exit 0
