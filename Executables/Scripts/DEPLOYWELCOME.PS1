#Requires -RunAsAdministrator
#Requires -Version 5.1
# =============================================================================
# DeployLexBoosTWelcome
#
# Ensures LexBoosTWelcome.exe is deployed to C:\ProgramData\LexBoosTOS\Welcome
# (moved from %windir%\LexBoosTOS\Scripts\Programs) and running in the
# background. Safe to re-run: if the executable is already deployed, the
# source copy is deleted (no duplicates) and the program is launched only
# if it is not already running.
# =============================================================================

$SourcePath = Join-Path (Join-Path $env:windir 'LexBoosTOS\Scripts\Programs') 'LexBoosTWelcome.exe'
$DestDir    = 'C:\ProgramData\LexBoosTOS\Welcome'
$DestPath   = Join-Path $DestDir 'LexBoosTWelcome.exe'

# Ensure the destination folder exists.
if (-not (Test-Path -LiteralPath $DestDir -PathType Container)) {
    New-Item -Path $DestDir -ItemType Directory -Force | Out-Null
}

# Deploy the executable.
$srcOk = Test-Path -LiteralPath $SourcePath -PathType Leaf
$dstOk = Test-Path -LiteralPath $DestPath -PathType Leaf

if ($srcOk -and $dstOk) {
    # Already deployed: remove the duplicate source copy.
    Remove-Item -LiteralPath $SourcePath -Force
}
elseif ($srcOk) {
    # Fresh deployment: move the executable (copy+delete as fallback).
    try {
        Move-Item -LiteralPath $SourcePath -Destination $DestPath -Force
    }
    catch {
        Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
        Remove-Item -LiteralPath $SourcePath -Force
    }
}

# Launch in the background if not already running.
$running = Get-Process -Name 'LexBoosTWelcome' -ErrorAction SilentlyContinue
if ($dstOk -and -not $running) {
    Start-Process -FilePath $DestPath -WorkingDirectory $DestDir -WindowStyle Hidden -PassThru |
        ForEach-Object { Write-Verbose "LexBoosTWelcome.exe started (PID $($_.Id))" }
}
