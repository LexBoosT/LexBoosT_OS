param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CopyWallpapers', 'CopyThemeFile', 'SetDefaultTile', 'InstallTheme')]
    [string]$Action
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $PSCommandPath
$execDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

switch ($Action) {

    'CopyWallpapers' {
        Write-Log '+' "Copying wallpapers..."
        $wallDest = Join-Path -Path $env:systemroot 'Web\Wallpaper\LexBoosTOS\v3'
        if (-not (Test-Path $wallDest)) {
            New-Item -ItemType Directory -Path $wallDest -Force | Out-Null
        }
        $wallSrc = Join-Path -Path $execDir 'Wallpapers'
        if (Test-Path $wallSrc) {
            robocopy $wallSrc $wallDest /E /PURGE /IM /IT /NP /NFL /NDL /R:3 /W:1
            Write-Log '+' "Wallpapers deployed"
        } else {
            Write-Log '-' "Wallpapers folder not found"
        }
    }

    'CopyThemeFile' {
        Write-Log '+' "Copying theme file..."
        $themeDir = Join-Path -Path $env:WINDIR 'Resources\Themes'
        if (-not (Test-Path $themeDir)) {
            New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
        }
        $themeSrc = Join-Path -Path $execDir 'Themes'
        if (Test-Path $themeSrc) {
            robocopy $themeSrc $themeDir 'LexBoosT-v3.0-dark.theme' /NJH /NJS /NDL /NC /NS /R:3 /W:1
            Write-Log '+' "Theme file deployed"
        } else {
            Write-Log '-' "Theme file not found"
        }
    }

    'SetDefaultTile' {
        Write-Log '+' "Setting default tile..."
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        $regName = 'UseDefaultTile'
        $regValue = 1
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type DWORD -Force
        Write-Log '+' "Default tile set"
    }

    'InstallTheme' {
        Write-Log '+' "Installing theme..."
        $installScript = Join-Path -Path $env:windir 'LexBoosTOS\Scripts\PowerShell\INSTALL-THEME.ps1'
        if (Test-Path $installScript) {
            & $installScript
            Write-Log '+' "Theme applied"
        } else {
            Write-Log '-' "Theme installer not found at: LexBoosTOS\Scripts\PowerShell\INSTALL-THEME.ps1"
        }
    }
}

# Exit cleanly
exit 0
