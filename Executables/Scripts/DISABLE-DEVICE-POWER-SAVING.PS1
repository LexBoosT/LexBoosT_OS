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

# --- 1. USB selective suspend OFF (plan actif) ---
$active = powercfg /getactivescheme 2>$null | Select-Object -First 1
if ($active -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
    $plan = $Matches[1]
    $usbSub   = '2a737441-1930-4402-8d77-b2bebba308a3'   # USB Settings
    $suspend  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'   # USB selective suspend
    $null = powercfg /setacvalueindex $plan $usbSub $suspend 0 2>$null
    if ($LASTEXITCODE -eq 0) {
        $null = powercfg /setactive $plan 2>$null
        Write-Host '[+] USB selective suspend disabled (AC).'
    } else {
        Write-Host '[-] USB selective suspend setting not present, skipped.'
    }
}

# --- 2. Economie USB par peripherique (UNIQUEMENT si la cle existe) ---
$usbRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'
if (Test-Path $usbRoot) {
    Get-ChildItem $usbRoot -Recurse -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.PSPath 'Device Parameters') -ErrorAction SilentlyContinue } |
        ForEach-Object {
            $dp = Join-Path $_.PSPath 'Device Parameters'
            foreach ($k in @('DeviceSelectiveSuspended','SelectiveSuspendEnabled','EnableSelectiveSuspend')) {
                if (Test-Path (Join-Path $dp $k)) { Set-ItemProperty $dp $k 0 -Type DWord -Force -ErrorAction SilentlyContinue }
            }
        }
    Write-Host '[+] USB per-device power saving disabled (targeted).'
}

# --- 3. Modern Standby / Connected Standby OFF (desktop; necessite firmware S3) ---
# Desactive l'AoAC/Modern Standby -> vrai S3, moins de reveils d'arriere-plan et de latence.
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'CsEnabled' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue
Write-Host '[+] Connected Standby disabled (CsEnabled=0) - utilise le S3 (si supporte par le firmware).'

Write-Host 'Done - USB/device energy saving disabled (desktop, targeted).'
exit 0
