#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# Disable wake for HID input devices — language-independent: device names are taken
# from powercfg's own output (friendly names are localized; hardcoded names fail on FR systems)
$wakeDevices = @(powercfg -devicequery wake_armed)
$disabled = 0
foreach ($device in $wakeDevices) {
    $name = $device.Trim()
    if ($name -match 'HID|Keyboard|Mouse') {
        powercfg -devicedisablewake $name 2>$null
        if ($LASTEXITCODE -eq 0) { $disabled++; Write-Log '+' "Wake disabled: $name" }
    }
}
Write-Log '+' "HID device wake disabled ($disabled device(s))."
exit 0
