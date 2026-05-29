#Requires -Version 5.1

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log '-' 'This script must be run as Administrator!'
    exit
}

$sourceFile = Join-Path $PSScriptRoot '..\..\winver.exe'
$targetPath = "$env:windir\System32\winver.exe"
$targetBak  = "$env:windir\System32\winver.exe.bak"

$sourceFile = Resolve-Path $sourceFile -ErrorAction SilentlyContinue
if (-not $sourceFile) {
    Write-Log '-' "winver.exe not found at: $sourceFile"
    exit
}

Write-Log '+' "Source file   : $sourceFile"
Write-Log '+' "Destination   : $targetPath"
Write-Host ''

if (Test-Path $targetPath) {
    Write-Log '+' "Creating backup -> $targetBak"
    Copy-Item -Path $targetPath -Destination $targetBak -Force
    Write-Log '+' 'Backup OK'
}

Write-Log '+' 'Replacing file...'

try {
    takeown /F $targetPath | Out-Null
    icacls $targetPath /grant '*S-1-5-32-544:(F)' /C | Out-Null

    Copy-Item -Path $sourceFile -Destination $targetPath -Force -ErrorAction Stop

    Write-Log '+' 'Replacement completed successfully!'

    $oldSize = if (Test-Path $targetBak) { (Get-Item $targetBak).Length } else { 'unknown' }
    $newSize = (Get-Item $targetPath).Length
    Write-Log '+' "Original size : $oldSize bytes"
    Write-Log '+' "New size      : $newSize bytes"
}
catch {
    Write-Log '-' 'Replacement FAILED!'
    Write-Log '-' "$($_.Exception.Message)"
}

exit 0
