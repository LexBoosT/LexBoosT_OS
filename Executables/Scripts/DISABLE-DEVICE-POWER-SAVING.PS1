#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

function Test-IsLaptop {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PCSystemType -eq 2 -or $cs.PCSystemTypeEx -in @(2, 8)) { return $true }
        try { if (Get-CimInstance Win32_Battery -ErrorAction Stop) { return $true } } catch {}
    } catch {}
    try {
        $ch = Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop
        if ($ch.ChassisTypes | Where-Object { $_ -in @(8,9,10,11,12,13,14,18,21,30,31,32) }) { return $true }
    } catch {}
    return $false
}

if (Test-IsLaptop) {
    Write-Host '[-] Laptop detected - device power saving left enabled (battery).'
    exit 0
}

# POLICY 2026 (USB stock): USB selective suspend (powercfg) and per-device USB
# power saving are no longer touched - USB devices are left at Windows defaults.

# --- 3. Modern Standby / Connected Standby OFF (desktop; necessite firmware S3) ---
# Desactive l'AoAC/Modern Standby -> vrai S3, moins de reveils d'arriere-plan et de latence.
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'CsEnabled' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue
Write-Host '[+] Connected Standby disabled (CsEnabled=0) - utilise le S3 (si supporte par le firmware).'

Write-Host 'Done - device energy saving disabled (desktop, targeted).'
exit 0
