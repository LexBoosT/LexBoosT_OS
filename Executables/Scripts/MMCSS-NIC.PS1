#Requires -RunAsAdministrator

$MP      = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$MMCSS   = 'HKLM:\SYSTEM\CurrentControlSet\Services\MMCSS'

function Set-Reg($Path, $Name, $Type, $Value) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force
}

function Get-DriverType($PnpDeviceId) {
    $driver = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\$PnpDeviceId" `
        -Name 'Driver' -EA SilentlyContinue).Driver
    if (-not $driver) { return $null }

    $svcName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driver\Ndi" `
        -Name 'Service' -EA SilentlyContinue).Service
    if (-not $svcName) { return $null }
    $svcName = $svcName.TrimEnd('.')

    $imgPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName" `
        -Name 'ImagePath' -EA SilentlyContinue).ImagePath
    if (-not $imgPath) { return $null }

    $resolved = $imgPath `
        -replace '^\\SystemRoot', $env:SystemRoot `
        -replace '^%SystemRoot%', $env:SystemRoot `
        -replace '^\\\?\?\\',    '' `
        -replace '^System32\\',  "$env:SystemRoot\System32\"

    if (-not (Test-Path $resolved)) { return $null }

    try {
        $bytes = [IO.File]::ReadAllBytes($resolved)
        $text  = [Text.Encoding]::ASCII.GetString($bytes)
        if   ($text -match 'NetAdapter') { return 'NetAdapterCx' }
        elseif ($text -match 'NDIS\.SYS') { return 'NDIS' }
        else { return 'Unknown' }
    } catch { return $null }
}

# ── Detect primary adapter (default route) ────────────────────────────────────
$primaryType = $null

$defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue |
    Sort-Object RouteMetric | Select-Object -First 1

if ($defaultRoute) {
    $iface = Get-NetAdapter -InterfaceIndex $defaultRoute.ifIndex -EA SilentlyContinue
    if ($iface) {
        $pnp = (Get-CimInstance Win32_NetworkAdapter |
            Where-Object { $_.InterfaceIndex -eq $iface.ifIndex }).PNPDeviceID
        if ($pnp) {
            $primaryType = Get-DriverType $pnp
        }
    }
}

# ── Fallback: scan all ────────────────────────────────────────────────────────
if (-not $primaryType) {
    Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PNPDeviceID -ne $null } | ForEach-Object {
        $type = Get-DriverType $_.PNPDeviceID
        if ($type -and $type -ne 'Unknown') {
            if (-not $primaryType) { $primaryType = $type }
        }
    }
}

if (-not $primaryType) {
    exit 1
}

# ── Apply ─────────────────────────────────────────────────────────────────────
if ($primaryType -eq 'NetAdapterCx') {
    Set-Reg $MMCSS 'Start' DWord 4
    Set-Reg $MP 'SystemResponsiveness' DWord 100
} else {
    # NDIS detected — applying custom MMCSS profile
    Set-Reg $MMCSS 'Start' DWord 2
    Set-Reg $MP 'SystemResponsiveness'      DWord 10
    Set-Reg $MP 'NoLazyMode'               DWord 0
    Set-Reg $MP 'NetworkThrottlingIndex'    DWord 10
    Set-Reg $MP 'LazyModeTimeout'          DWord 0xFFFFFFFF
    Set-Reg $MP 'SchedulerPeriod'          DWord 1000000
    Set-Reg $MP 'IdleDetectionCycles'      DWord 1
    Set-Reg $MP 'SchedulerTimerResolution' DWord 10000

    foreach ($task in 'Audio', 'Pro Audio', 'Playback') {
        Set-Reg "$MP\Tasks\$task" 'Priority'              DWord  1
        Set-Reg "$MP\Tasks\$task" 'Scheduling Category'  String 'Medium'
        Set-Reg "$MP\Tasks\$task" 'Priority When Yielded' DWord  16
    }
}
