#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Restarting as Administrator...'
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log { param([string]$Status, [string]$Message); Write-Host "[$Status] $Message" }

Write-Host '============================================'
Write-Host '       BROKER Registry Tweaks'
Write-Host '============================================'

$protectedValues = @(
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\WinStore.Tasks.WindowsSearchTask'; Name = 'ActivationType'; Value = '4294967295'; Type = 'REG_DWORD' }
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\WinStore.Tasks.WindowsSearchTask'; Name = 'Server'; Value = ''; Type = 'REG_SZ' }
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\ValueBanner.IdealStateFeatureControlProvider'; Name = 'ActivationType'; Value = '4294967295'; Type = 'REG_DWORD' }
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\ValueBanner.IdealStateFeatureControlProvider'; Name = 'Server'; Value = ''; Type = 'REG_SZ' }
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.Xbox.GamingAI.Companion.Host.GamingCompanionHostOptions'; Name = 'ActivationType'; Value = '4294967295'; Type = 'REG_DWORD' }
    @{ Path = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.Xbox.GamingAI.Companion.Host.GamingCompanionHostOptions'; Name = 'Server'; Value = ''; Type = 'REG_SZ' }
)

$regValues = @(
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'DisableDynamicTick'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'DisableDynamicTickOnSpecificCores'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'DisableSleepIdle'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'EnableClockSteering'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'EnableHighResolutionTaskScheduling'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'EnableHighResolutionTimers'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'ForceClockSync'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\TimeBroker'; Name = 'ReduceIdleTime'; Value = '1'; Type = 'REG_DWORD' }
)

function Set-RegistryWithFallback {
    param([array]$Entries)
    $minSudo = Join-Path $env:windir 'LexBoosTOS\Utilities\MinSudo.exe'
    foreach ($entry in $Entries) {
        $key = $entry.Path -replace '^Registry::', ''
        $name = $entry.Name
        $val = $entry.Value
        $type = $entry.Type
        try {
            $regType = if ($type -eq 'REG_DWORD') { 'REG_DWORD' } else { 'REG_SZ' }
            $regCmd = if ($regType -eq 'REG_DWORD') {
                "reg add `"$key`" /v `"$name`" /t REG_DWORD /d $val /f"
            } else {
                "reg add `"$key`" /v `"$name`" /t REG_SZ /d `"$val`" /f"
            }
            $done = $false
            if (Test-Path $minSudo) {
                $proc = Start-Process -FilePath $minSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged cmd.exe /c `"$regCmd`"" -Wait -PassThru -WindowStyle Hidden
                $done = ($proc.ExitCode -eq 0)
            }
            if (-not $done) {
                Invoke-Expression $regCmd | Out-Null
                $done = ($LASTEXITCODE -eq 0)
            }
            if ($done) { $script:set++ } else { throw "reg exit code" }
        } catch {
            Write-Log '-' "Failed to set ${key}\${name}: $_"
        }
    }
}

$set = 0

# Protected broker keys (require TrustedInstaller)
Set-RegistryWithFallback -Entries $protectedValues

# Standard registry keys
foreach ($entry in $regValues) {
    try {
        if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
        $propType = switch ($entry.Type) { 'REG_SZ' { 'String' } 'REG_EXPAND_SZ' { 'ExpandString' } 'REG_DWORD' { 'DWord' } 'REG_BINARY' { 'Binary' } 'REG_NONE' { 'None' } default { 'String' } }
        New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $propType -Force -ErrorAction Stop | Out-Null
        $set++
    } catch { Write-Log '-' "Failed: $_" }
}

Write-Log '+' "$set registry values set"

exit 0
