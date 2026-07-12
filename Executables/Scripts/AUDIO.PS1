#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Restarting as Administrator...'
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       AUDIO Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    @{ Path = 'Registry::HKCU\Software\Microsoft\Multimedia\Audio'; Name = 'UserDuckingPreference'; Value = '3'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Software\Microsoft\Multimedia\Audio'; Name = 'UserDuckingPreference'; Value = '3'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'; Name = 'Affinity'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'; Name = 'GPU Priority'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'; Name = 'SFIO Priority'; Value = 'Normal'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'; Name = 'DisableStartupSound'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides'; Name = 'UserSetting_DisableStartupSound'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SpeechOneCore\Settings'; Name = 'AgentActivationEnabled'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SpeechOneCore\Settings'; Name = 'AgentActivationLastUsed'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Narrator\NoRoam'; Name = 'DuckAudio'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility'; Name = 'Sound on Activation'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility'; Name = 'Warning Sounds'; Value = '1'; Type = 'REG_DWORD' }
)

$set = 0
foreach ($entry in $regValues) {
    try {
        if (-not (Test-Path $entry.Path)) {
            New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null
        }
        $propType = switch ($entry.Type) {
            'REG_SZ'        { 'String' }
            'REG_EXPAND_SZ' { 'ExpandString' }
            'REG_DWORD'     { 'DWord' }
            'REG_BINARY'    { 'Binary' }
            'REG_NONE'      { 'None' }
            default         { 'String' }
        }
        New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $propType -Force -ErrorAction Stop | Out-Null
        $set++
    } catch {
        Write-Log '-' "Failed to set $($entry.Path)\$($entry.Name): $_"
    }
}

Write-Log '+' "$set registry values set"
Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0