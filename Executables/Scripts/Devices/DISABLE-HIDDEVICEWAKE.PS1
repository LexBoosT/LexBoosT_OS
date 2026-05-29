#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

powercfg -devicedisablewake "HID-complaint mouse" 2>$null
powercfg -devicedisablewake "HID Keyboard Device" 2>$null
Write-Log '+' "HID device wake disabled."
exit 0
