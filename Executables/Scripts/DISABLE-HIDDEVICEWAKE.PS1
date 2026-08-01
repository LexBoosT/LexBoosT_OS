#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

<<<<<<< HEAD
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
=======
powercfg -devicedisablewake "HID-complaint mouse" 2>$null
powercfg -devicedisablewake "HID Keyboard Device" 2>$null
Write-Log '+' "HID device wake disabled."
>>>>>>> 0251bba90259c7b88ee0ce71c429e5c6fb1b4434
exit 0
