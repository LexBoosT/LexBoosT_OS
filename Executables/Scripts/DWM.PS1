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

$regValues = @(
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableAdvancedDirectFlip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisallowNonDrawListRendering'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\Dwm'; Name = 'DisallowNonDrawListRendering'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableDrawListCaching'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableEffectCaching'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableImageProcessing'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'UseHWDrawListEntriesOnWARP'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableDDisplayScanoutCaching'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DiscardSurfaceOnMinimize'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'FlattenVirtualSurfaceEffectInput'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'IdleTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesSequenceMaximumPeriodMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesSequenceIdleIntervalMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'TelemetryFramesReportPeriodMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'RecurringWatchdogTelemetryTimeoutMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'InitialWatchdogTelemetryTimeoutMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnablePrimitiveReordering'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ResampleModeOverride'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ResampleInLinearSpace'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'HighColor'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableDesktopOverlays'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableFrontBufferRenderChecks'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableCommonSuperSets'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OptimizeForDirtyExpressions'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableResizeOptimization'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayQualifyInterval'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayQualifyCount'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayDisqualifyInterval'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayDisqualifyCount'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm\ExtendedComposition'; Name = 'EnableColorSeparation'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm\ExtendedComposition'; Name = 'ForwardOnlyOnly'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm\ExtendedComposition'; Name = 'SydneyDownsampleFilterKernelSize'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\DWM\Schedule'; Name = 'FrameDisplayBaseNegOffsetNS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\DWM\Schedule'; Name = 'FrameDisplayResDivValue'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\DWM\Schedule'; Name = 'LingerInterval'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableIndependentFlip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM'; Name = 'DisableIndependentFlip'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM'; Name = 'MaxQueuedPresentBuffers'; Value = '3'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM\ExtendedComposition'; Name = 'ExclusiveModeFramerateAveragingPeriodMs'; Value = '1000'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm\ExtendedComposition'; Name = 'ExclusiveModeFramerateThresholdPercent'; Value = '45'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM\ExtendedComposition'; Name = 'ExclusiveModeFramerateThresholdPercent'; Value = '45'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Software\Microsoft\Windows\DWM'; Name = 'AlwaysHibernateThumbnails'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'AnimationsShiftKey'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ParallelModePolicy'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm\Scene'; Name = 'EnableBloom'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableCpuClipping'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'EnableMegaRects'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'ForceDesktopTreeFullDirty'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'GammaBlendPencil'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'GammaBlendWithFP16'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'MousewheelAnimationDurationMs'; Value = '100'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'DisableProjectedShadows'; Value = '1'; Type = 'REG_DWORD' }
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