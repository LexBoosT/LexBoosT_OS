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
Write-Host '       MOUSE Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed'; Name = 'CursorSensitivity'; Value = '10000'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed'; Name = 'CursorUpdateInterval'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed'; Name = 'IRRemoteNavigationDelta'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'DelayBeforeAcceptance'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'BounceTime'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'Last BounceKey Setting'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'Last Valid Delay'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'Last Valid Repeat'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'Last Valid Wait'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'KeyboardDelay'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'AutoRepeatDelay'; Value = '180'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'AutoRepeatRate'; Value = '2'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\Keyboard Response'; Name = 'Flags'; Value = '122'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Value = '506'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Value = '506'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Accessibility\ToggleKeys'; Name = 'Flags'; Value = '58'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'; Name = 'MouseDataQueueSize'; Value = '22'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'; Name = 'KeyboardDataQueueSize'; Value = '22'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseSensitivity'; Value = '10'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseHoverTime'; Value = '200'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKU\.DEFAULT\Control Panel\Mouse'; Name = 'MouseHoverTime'; Value = '200'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseSpeed'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseTrails'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'DoubleClickSpeed'; Value = '350'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'SwapMouseButtons'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'RawInput'; Value = '1'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'SnapToDefaultButton'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'MouseDelay'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'ActiveWindowTracking'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'RawMouseThrottleEnabled'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'RawMouseThrottleForced'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'RawMouseThrottleDuration'; Value = '20'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Mouse'; Name = 'RawMouseThrottleLeeway'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'RITdemonTimerPowerSaveElapse'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'RITdemonTimerPowerSaveCoalescing'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKCU\Control Panel\Keyboard'; Name = 'KeyboardDelay'; Value = '0'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Keyboard'; Name = 'KeyboardSpeed'; Value = '31'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Keyboard'; Name = 'InitialKeyboardIndicators'; Value = '2'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'AttractionRectInsetInDIPS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'DistanceThresholdInDIPS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'MagnetismDelayInMilliseconds'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'MagnetismUpdateIntervalInMilliseconds'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'VelocityInDIPSPerSecond'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'; Name = 'KeyboardTransmitTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'; Name = 'LayeredLatency'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'; Name = 'KeyboardTransmitTimeout'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'; Name = 'LayeredLatency'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'ConnectMultiplePorts'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouclass\Parameters'; Name = 'ConnectMultiplePorts'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'KeyboardDeviceBaseName'; Value = 'KeyboardClass'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'MaximumPortsServiced'; Value = '3'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouclass\Parameters'; Name = 'MaximumPortsServiced'; Value = '3'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'SendOutputToAllPorts'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouclass\Parameters'; Name = 'SendOutputToAllPorts'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'WppRecorder_UseTimeStamp'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouclass\Parameters'; Name = 'WppRecorder_UseTimeStamp'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouhid\Parameters'; Name = 'WppRecorder_UseTimeStamp'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdhid\Parameters'; Name = 'WppRecorder_UseTimeStamp'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'ThreadPriority'; Value = '15'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\mouclass\Parameters'; Name = 'ThreadPriority'; Value = '15'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\services\kbdclass\Parameters'; Name = 'WppRecorder_TraceGuid'; Value = '{09281f1f-f66e-485a-99a2-91638f782c49}'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Keyboard'; Name = 'Flags'; Value = '27'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKCU\Control Panel\Desktop'; Name = 'CursorBlinkRate'; Value = '200'; Type = 'REG_SZ' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\mouhid\Parameters'; Name = 'TreatAbsolutePointerAsAbsolute'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SYSTEM\CurrentControlSet\Services\mouhid\Parameters'; Name = 'TreatAbsoluteAsRelative'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Input\DelayZonePalmRejection'; Name = 'RejectionEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Input\DelayZonePalmRejection'; Name = 'DisableTimeThreshold'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Input\DelayZonePalmRejection'; Name = 'DelayZonePalmRejectionExtensionSizeDips'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Input\DelayZonePalmRejection'; Name = 'DelayZonePalmRejectionThresholdMS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input'; Name = 'IsInputAppPreloadEnabled'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'BluebirdDTWMultiplier'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'DisableExpressiveInputShellHotkey'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'DisablePersonalizationGTKM'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'DynamicAutocorrectionAllowed'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'INLINEPREDICTIONMINPREDICTIONLENGTH'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings'; Name = 'INLINEPREDICTIONMINPREFIXLENGTH'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'ClosestInteractiveBoundsUpdateIntervalInMilliseconds'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'SearchHeightInDIPS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism'; Name = 'SearchWidthInDIPS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1'; Name = 'BluebirdDTWMultiplier'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1'; Name = 'DynamicAutocorrectionAllowed'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'AUTOCORRECTIONTRIGGERS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'AUTOCORRECTSUPPRESSPREVCHARS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'BluebirdDTWMultiplier'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'DisableExpressiveInputShellHotkey'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'DynamicAutocorrectionAllowed'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'PERIODSHORTCUTCHARS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'PERIODSHORTCUTDELAY'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409'; Name = 'PERIODSHORTCUTDELAYCANDSELECTION'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'AUTOCORRECTIONTRIGGERS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'AUTOCORRECTSUPPRESSPREVCHARS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'BluebirdDTWMultiplier'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'COMMONEMOJIPRETERMINATORS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'COMMONEMOJITERMINATORS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'DisableExpressiveInputShellHotkey'; Value = '1'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'DynamicAutocorrectionAllowed'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'PERIODSHORTCUTCHARS'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'PERIODSHORTCUTDELAY'; Value = '0'; Type = 'REG_DWORD' }
    @{ Path = 'Registry::HKLM\SOFTWARE\Microsoft\Input\Settings\proc_1\loc_0409\im_1'; Name = 'PERIODSHORTCUTDELAYCANDSELECTION'; Value = '0'; Type = 'REG_DWORD' }
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