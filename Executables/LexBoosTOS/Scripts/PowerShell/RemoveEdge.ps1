#Requires -Version 5.0

<#
.SYNOPSIS
    Thin wrapper — delegates to EDGE.PS1 (unified Edge management script).
    Kept for backward compatibility; all actual logic is now in Executables\Scripts\EDGE.PS1.
.DESCRIPTION
    Supported switches:
        -UninstallEdge   → EDGE.PS1 -Mode Full
        -InstallEdge     → EDGE.PS1 -Mode Install
        -InstallWebView  → EDGE.PS1 -Mode WebView2
        -NonInteractive  → silent mode (inferred)
#>

param(
    [switch]$UninstallEdge,
    [switch]$InstallEdge,
    [switch]$InstallWebView,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'SilentlyContinue'

# Resolve EDGE.PS1 path (same playbook layout)
$edgeScript = $null
$candidates = @(
    Join-Path $PSScriptRoot '..\..\..\..\Scripts\EDGE.PS1'           # from Executables\LexBoosTOS\Scripts\PowerShell\
    Join-Path $PSScriptRoot '..\..\..\Scripts\EDGE.PS1'              # alternative depth
    Join-Path $env:windir 'LexBoosTOS\Scripts\EDGE.PS1'              # deployed location
    Join-Path $env:ProgramData 'LexBoosTOS\Scripts\EDGE.PS1'         # deployed alt
)

foreach ($c in $candidates) {
    $resolved = if (Test-Path $c) { (Get-Item $c).FullName } else { $null }
    if ($resolved) { $edgeScript = $resolved; break }
}

if (-not $edgeScript) {
    Write-Host '[-] EDGE.PS1 not found — cannot delegate.'
    Write-Host '[-] Expected at: ..\Executables\Scripts\EDGE.PS1 relative to this script.'
    exit 1
}

# Map switches to modes
if ($UninstallEdge) {
    Write-Host '[+] Delegating to EDGE.PS1 -Mode Full'
    & $edgeScript -Mode Full
} elseif ($InstallEdge -and $InstallWebView) {
    Write-Host '[+] Delegating to EDGE.PS1 -Mode Install then -Mode WebView2'
    & $edgeScript -Mode Install
    & $edgeScript -Mode WebView2
} elseif ($InstallEdge) {
    Write-Host '[+] Delegating to EDGE.PS1 -Mode Install'
    & $edgeScript -Mode Install
} elseif ($InstallWebView) {
    Write-Host '[+] Delegating to EDGE.PS1 -Mode WebView2'
    & $edgeScript -Mode WebView2
} else {
    # Interactive mode not supported by wrapper; run Full as sensible default
    Write-Host '[+] No switch specified — running Full removal as default'
    & $edgeScript -Mode Full
}

exit $LASTEXITCODE
