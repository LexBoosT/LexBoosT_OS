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
Write-Host '       DWM Registry Tweaks'
Write-Host '============================================'

# ============================================================
#  Valeurs DWM par defaut Windows / télémétrie désactivée.
#
#  NB: les anciennes valeurs "performance" (DisableAdvancedDirectFlip,
#  DisallowNonDrawListRendering, DisableDrawListCaching, EnableMegaRects,
#  EnableDesktopOverlays, HighColor, FrameLatency, etc.) ont ete RETIREES :
#  elles cassent la composition DWM -> rendu Chromium/CEF en software
#  (Steam invisible) et crashent les apps WPF (DwmExtendFrameIntoClientArea
#  0x80263001). La composition est laissee au comportement par defaut.
# ============================================================
$regValues = @(
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OneCoreNoDWMRawGameController'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'MPCInputRouterWaitForDebugger'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableRenderPathTestMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableHologramCompositor'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DebugFailFast'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DDisplayTestMode'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ForceDirectDrawSync'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'RenderThreadWatchdogTimeoutMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'MaxD3DFeatureLevel'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ResizeTimeoutModern'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ResizeTimeoutGdi'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'AnimationAttributionEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'IdleTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesSequenceMaximumPeriodMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesSequenceIdleIntervalMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesReportPeriodMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'RecurringWatchdogTelemetryTimeoutMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'InitialWatchdogTelemetryTimeoutMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM'; Name = 'DisableIndependentFlip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableIndependentFlip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\XAML'; Name = 'DisableGlobalAnimations'; Value = '1'; Type = 'REG_DWORD' }
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
