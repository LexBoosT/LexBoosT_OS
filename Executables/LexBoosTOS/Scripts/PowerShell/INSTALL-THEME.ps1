$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

try {
    # Configure module path
    $windir = [Environment]::GetFolderPath('Windows')
    $moduleDir = Join-Path -Path $windir -ChildPath "LexBoosTOS\Scripts\Modules"

    # Force import module from specific location
    $modulePath = Join-Path -Path $moduleDir -ChildPath "Themes\Themes.psm1"

    if (-not (Test-Path $modulePath)) {
        throw "Themes module not found at: $modulePath"
    }

    # Explicitly import module
    Import-Module $modulePath -ErrorAction Stop -Force

    # Set theme path
    $themePath = Join-Path -Path $windir -ChildPath "Resources\Themes\LexBoosT-v3.0-dark.theme"

    if (Test-Path $themePath) {
        Set-Theme -Path $themePath -ErrorAction Stop
        Set-ThemeMRU -ErrorAction Stop
        Write-Log '+' "Theme applied successfully"
        exit 0
    }
    else {
        throw "Theme file not found at: $themePath"
    }
}
catch {
    Write-Log '-' "$_"
    exit 1
}
Write-Log '+' "Theme Installed!"