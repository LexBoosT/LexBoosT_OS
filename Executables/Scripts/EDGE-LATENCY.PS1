#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Disables Microsoft Edge prelaunch, tab preloading and background mode.
.DESCRIPTION
    Reduces startup overhead and background activity that can add latency spikes.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Set-EdgePolicy {
    param([string]$Name, [object]$Value, [string]$Type = 'DWord')
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $Name -Value $Value -Type $Type -Force
    Write-Log '+' "Edge policy set: $Name = $Value"
}

function Set-EdgeUserPref {
    param([string]$Sid, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    $path = "Registry::$Sid\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $Name -Value $Value -Type $Type -Force
}

Write-Log '+' 'Disabling Edge prelaunch, tab preloading and background mode...'

# Machine policies
Set-EdgePolicy 'StartupBoostEnabled' 0
Set-EdgePolicy 'AllowPrelaunch' 0
Set-EdgePolicy 'AllowTabPreloading' 0
Set-EdgePolicy 'BackgroundModeEnabled' 0
Set-EdgePolicy 'EdgeShoppingAssistantEnabled' 0
Set-EdgePolicy 'HubsSidebarEnabled' 0
Set-EdgePolicy 'ShowRecommendationsEnabled' 0
Set-EdgePolicy 'ShowPromotedLinksEnabled' 0
Set-EdgePolicy 'BingAdsSuppression' 1
Set-EdgePolicy 'NewTabPageAllowedBackgroundTypes' 0
Set-EdgePolicy 'SpotlightExperiencesAndRecommendationsEnabled' 0

# Apply to existing user hives
$profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
    Where-Object { $_.PSChildName -match '^S-1-5-21-' }

foreach ($profile in $profiles) {
    $profilePath = $profile.ProfileImagePath
    $sid = $profile.PSChildName
    $ntuser = Join-Path $profilePath 'NTUSER.DAT'
    if (Test-Path $ntuser) {
        # Skip if hive is already loaded (current logged-on user, or default user)
        if (Test-Path "Registry::HKEY_USERS\$sid") {
            Write-Log '+' "Hive already loaded for $sid, applying directly..."
            Set-EdgeUserPref "HKEY_USERS\$sid" 'StartupBoostEnabled' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'AllowPrelaunch' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'AllowTabPreloading' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'BackgroundModeEnabled' 0
            continue
        }
        Write-Log '+' "Loading user hive for $sid..."
        $loadResult = reg load "HKU\$sid" "$ntuser" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log '-' "Could not load hive for $sid : $loadResult"
            continue
        }
        try {
            Set-EdgeUserPref "HKEY_USERS\$sid" 'StartupBoostEnabled' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'AllowPrelaunch' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'AllowTabPreloading' 0
            Set-EdgeUserPref "HKEY_USERS\$sid" 'BackgroundModeEnabled' 0
        } finally {
            [gc]::Collect()
            reg unload "HKU\$sid" | Out-Null
        }
    }
}

Write-Log '+' 'Edge latency tweaks applied.'
exit 0
