#Requires -RunAsAdministrator

param(
    [switch]$DryRun,
    [switch]$SkipImod
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'DEVICE TWEAKER - Auto-Optimization'

# Keep window open on error or completion
try {

# ──────────────────────────────────────────────
# LOGGING
function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$Script:LogPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "DeviceTweakerAuto_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function _log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] $msg"
    Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Log '+' $line
}
function _info($msg)  { Write-Log '+' "$msg";     _log "[INFO]  $msg" }
function _warn($msg)  { Write-Log '-' "$msg";     _log "[WARN]  $msg" }
function _err($msg)   { Write-Log '-' "$msg";     _log "[ERROR] $msg" }
function _ok($msg)    { Write-Log '+' "$msg";     _log "[OK]    $msg" }

# ──────────────────────────────────────────────
# PHASE 1 ─ CPU TOPOLOGY
# ──────────────────────────────────────────────
_info "=== PHASE 1: CPU Topology Discovery ==="

$CpuInfo = [PSCustomObject]@{
    PrimaryP     = [System.Collections.Generic.List[int]]::new()
    PrimaryE     = [System.Collections.Generic.List[int]]::new()
    AllP         = [System.Collections.Generic.List[int]]::new()
    AllE         = [System.Collections.Generic.List[int]]::new()
    ByCore       = @{}
    CcdMap       = @{}
    Logical      = 0
    PhysCores    = 0
    SMT          = $false
    Vendor       = ''
    Name         = ''
    MultiCcd     = $false
    TargetCcd    = -1
    TargetCcdLps = [System.Collections.Generic.List[int]]::new()
}

try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $CpuInfo.Name   = $cpu.Name.Trim()
    $CpuInfo.Vendor = $cpu.Manufacturer.Trim()
    $CpuInfo.Logical   = [int]$cpu.NumberOfLogicalProcessors
    $CpuInfo.PhysCores = [int]$cpu.NumberOfCores
    _log "CPU: $($CpuInfo.Name) | Vendor=$($CpuInfo.Vendor) | Logical=$($CpuInfo.Logical) | PhysCores=$($CpuInfo.PhysCores)"
} catch {
    $CpuInfo.Logical = [Environment]::ProcessorCount
    $CpuInfo.PhysCores = $CpuInfo.Logical
    _warn "CPU detection fallback: Logical=$($CpuInfo.Logical)"
}

$totalLP = $CpuInfo.Logical; $totalCores = $CpuInfo.PhysCores
if ($totalLP -gt 64) { _warn "CPU has $totalLP logical processors; affinity mask limited to 64 bits (LPs >= 64 excluded)" }
$lpIdx = 0; $pCoreCount = 0; $eCoreCount = 0

if ($totalLP -gt $totalCores) {
    $CpuInfo.SMT = $true
    $eCoreCount = [Math]::Max(0, $totalCores * 2 - $totalLP)
    $pCoreCount = $totalCores - $eCoreCount
} else {
    $pCoreCount = $totalCores; $eCoreCount = 0
}

_log "CPU.HYBRID: P-cores=$pCoreCount E-cores=$eCoreCount SMT=$($CpuInfo.SMT)"

for ($c = 0; $c -lt $pCoreCount; $c++) {
    $lps = if ($CpuInfo.SMT) { @($lpIdx, $lpIdx + 1) } else { @($lpIdx) }
    $CpuInfo.ByCore["Core$c"] = $lps
    [void]$CpuInfo.PrimaryP.Add($lpIdx)
    foreach ($l in $lps) { [void]$CpuInfo.AllP.Add($l) }
    $lpIdx += $lps.Count
}
for ($c = 0; $c -lt $eCoreCount; $c++) {
    $lps = @($lpIdx)
    $CpuInfo.ByCore["Core$($pCoreCount + $c)"] = $lps
    [void]$CpuInfo.PrimaryE.Add($lpIdx)
    [void]$CpuInfo.AllE.Add($lpIdx)
    $lpIdx++
}

# Multi-CCD detection (AMD, via L3 cache)
if ($CpuInfo.Vendor -match 'AMD') {
    try {
        $l3 = @(Get-CimInstance Win32_CacheMemory -Filter "Level=3" -EA SilentlyContinue)
        # Single-CCD X3D CPUs (5700X3D/5800X3D/7800X3D/9800X3D) report the 3D
        # V-Cache as a second L3 cache instance in WMI - only treat as multi-CCD
        # when physically >8 cores (7900X3D/7950X3D/9900X3D/9950X3D are 12/16C).
        if ($l3.Count -ge 2 -and $CpuInfo.PhysCores -gt 8) {
            $CpuInfo.MultiCcd = $true
            $CpuInfo.TargetCcd = $l3.Count - 1
            $lpsPerCcd = [Math]::Floor($CpuInfo.Logical / $l3.Count)
            for ($i = 0; $i -lt $CpuInfo.Logical; $i++) {
                $cid = [Math]::Min([Math]::Floor($i / $lpsPerCcd), $l3.Count - 1)
                $CpuInfo.CcdMap[$i] = $cid
                if ($cid -eq $CpuInfo.TargetCcd) { [void]$CpuInfo.TargetCcdLps.Add($i) }
            }

            if ($CpuInfo.Name -notmatch 'X3D') {
                $fp = [System.Collections.Generic.List[int]]::new()
                $fe = [System.Collections.Generic.List[int]]::new()
                foreach ($l in $CpuInfo.PrimaryP) { if ($CpuInfo.TargetCcdLps -contains $l) { [void]$fp.Add($l) } }
                foreach ($l in $CpuInfo.PrimaryE) { if ($CpuInfo.TargetCcdLps -contains $l) { [void]$fe.Add($l) } }
                if ($fp.Count -gt 0 -or $fe.Count -gt 0) { $CpuInfo.PrimaryP = $fp; $CpuInfo.PrimaryE = $fe }
                else { $CpuInfo.PrimaryP = $CpuInfo.TargetCcdLps; $CpuInfo.PrimaryE.Clear() }
                _log "CPU.CCD: Multi-CCD count=$($l3.Count) target=$($CpuInfo.TargetCcd) LPs=[$($CpuInfo.TargetCcdLps -join ',')] (pinning)"
            } else {
                _log "CPU.CCD.X3D: manual CCD pinning DISABLED (AMD driver / Xbox Game Bar manage routing)."
            }
        }
    } catch { _log "CPU.CCD: detection error: $_" }
}
# Default single-CCD
if (-not $CpuInfo.MultiCcd) {
    for ($i = 0; $i -lt $CpuInfo.Logical; $i++) { $CpuInfo.CcdMap[$i] = 0 }
    $CpuInfo.TargetCcd = 0
    0..($CpuInfo.Logical - 1) | ForEach-Object { [void]$CpuInfo.TargetCcdLps.Add($_) }
}

# AMD 3D V-Cache detection (X3D stability mode: skip IRQ lock / aggressive tweaks)
$IsAmdX3D = $CpuInfo.Vendor -match 'AMD' -and $CpuInfo.Name -match 'X3D'
if ($IsAmdX3D) { _log "CPU.X3D: AMD 3D V-Cache detected (stability mode: IRQ lock skipped)" }

_log "CPU.PRIMARY.P: [$($CpuInfo.PrimaryP -join ',')]"
_log "CPU.PRIMARY.E: [$($CpuInfo.PrimaryE -join ',')]"
_log "CPU.TARGET.CCD: LPs=[$($CpuInfo.TargetCcdLps -join ',')]"

# ──────────────────────────────────────────────
# PHASE 2 ─ DEVICE SCAN
# ──────────────────────────────────────────────
_info "=== PHASE 2: Device Scan & Classification ==="

$skipPatterns = @(
    '^ACPI\\AMDI00(10|30)\\','^ACPI\\PNP0103','^ACPI\\PNP0501',
    '^PCI\\VEN_1022&DEV_14DB','^PCI\\VEN_1022&DEV_14DD','^ACPI\\INTC1055\\',
    '^PCI\\VEN_8086&DEV_51E8','^PCI\\VEN_8086&DEV_A73E'
)
$Devices = [System.Collections.Generic.List[PSCustomObject]]::new()
$WifiIdSet = @{}
$rawDevices = Get-CimInstance Win32_PnPEntity -EA SilentlyContinue | Where-Object { $_.Status -in @('OK','Unknown') }
if (-not $rawDevices) { $rawDevices = Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.Status -in @('OK','Unknown') } }
_log "SCAN: $($rawDevices.Count) present PnP devices"

$physicalDisks = Get-CimInstance Win32_DiskDrive -EA SilentlyContinue

# USB role detection REMOVED by policy (USB stock): USB controllers never reach
# classification, so their child roles (keyboard/mouse/HID) are no longer probed.

# Audio endpoint detection
function _audioEndpoints($deviceId, $name) {
    try {
        $audioDevs = Get-CimInstance Win32_SoundDevice -EA SilentlyContinue
        foreach ($ad in $audioDevs) {
            if ($ad.PNPDeviceID -eq $deviceId -or ($ad.Name -and $ad.Name -eq $name)) {
                return $ad.Name
            }
        }
    } catch {}
    return $name
}

foreach ($dev in $rawDevices) {
    $did = if ($dev.PNPDeviceID) { $dev.PNPDeviceID } else { $dev.DeviceID }; if (-not $did) { continue }
    $dname  = if ($dev.Name) { $dev.Name } else { $did }
    $dclass = if ($dev.PNPClass) { $dev.PNPClass } else { '' }
    $dstatus = if ($dev.Status) { $dev.Status } else { 'OK' }

    # Skip filters
    if ($dstatus -notin @('OK','Unknown')) { _log "SCAN.SKIP: $did status=$dstatus"; continue }
    if ($did -match 'ACPI\\PNP0100') { continue }
    $skip = $false
    foreach ($p in $skipPatterns) { if ($did -match $p) { _log "SCAN.SKIP.PAT: $did"; $skip = $true; break } }
    if ($skip) { continue }
    if ($dname -match '(?i)(virtual|loopback|hyper-v|vmware|wan miniport|tap|tun|isatap|teredo|npcap|vb-?audio|voicemeeter|virtual cable|virtual audio|broadcast|software device)') { _log "SCAN.SKIP.VIRT: $did"; continue }
    if ($dclass -eq 'Bluetooth' -or $dname -match '(?i)Bluetooth') { continue }
    if ($dclass -eq 'System' -and $dname -match '(?i)(PCI Express Root Port|PCI-to-PCI Bridge|PCI standard.*bridge|SMBus|LPC Controller|ISA Bridge|I2C|SPI|GPIO|PS/2)') { continue }
    if ($dclass -eq 'Ports' -or $dname -match '(?i)\b(COM\d+|Serial Port|Communications Port)') { continue }
    if ($dclass -eq 'System' -and $dname -match '(?i)ACPI') { continue }
    if ($dclass -eq 'Display' -and ($dname -match '(?i)VirtualBox' -or $did -match 'VEN_80EE')) { continue }
    if ($dclass -eq 'USB' -and $did -match '(?i)\\VEN_10DE\\') { _log "SCAN.SKIP.NVIDIA.USB: $did"; continue }
    if ($dclass -eq 'Net' -and $dname -match '(?i)(Wi-?Fi|Wireless|802\.11|WLAN)') { _log "SCAN.SKIP.WIFI: $did"; continue }
    # POLICY 2026 (USB stock): every USB controller/hub is left at Windows defaults:
    # no MSI forcing, no DevicePriority, no affinity, no IMOD - USB is untouched.
    if ($dclass -eq 'USB' -and -not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$did\Device Parameters\Interrupt Management")) { _log "SCAN.SKIP.USB.POLICY: $did (USB left 100% stock)"; continue }

    # Classification
    $kind = 'OTHER'; $isWifi = $false; $isXhci = $false; $isCx = $false
    # USB (xHCI/controllers/hubs) never reaches classification: excluded earlier
    # via SCAN.SKIP.USB.POLICY - USB is left 100% stock (no MSI/priority/affinity).
    if ($dclass -eq 'Display') { $kind = 'GPU' }
    elseif ($dclass -eq 'Net') {
        # Detect NetAdapterCx vs NDIS
        try {
            $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\$did"
            $svcName = (Get-ItemProperty $svcKey -Name Service -EA SilentlyContinue).Service
            if ($svcName) {
                $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
                $dpName = (Get-ItemProperty $svcReg -Name DisplayName -EA SilentlyContinue).DisplayName
                $imgPath = (Get-ItemProperty $svcReg -Name ImagePath -EA SilentlyContinue).ImagePath
                if (($dpName -match '(?i)netadapter') -or ($imgPath -match '(?i)netadaptercx|netadapter\.sys')) {
                    $isCx = $true
                }
            }
        } catch {}
        $kind = if ($isCx) { 'NET_CX' } else { 'NET_NDIS' }
    }
    elseif ($dclass -in @('SCSIAdapter','HDC','IDE','Storage')) { $kind = 'STOR' }
    elseif ($dclass -in @('MEDIA','AudioEndpoint') -or $dname -match '(?i)High Definition Audio|HD Audio|Audio Controller') { $kind = 'AUDIO' }
    elseif ($dclass -eq 'HID' -and $dname -match '(?i)mouse|USB Input Device') { $kind = 'MOUSE' }
    elseif ($dclass -eq 'USB') { $kind = 'XHCI' }  # IM key present (checked below) -> xHCI host controller

    if ($kind -eq 'OTHER') { _log "SCAN.SKIP.OTHER: $did class=$dclass"; continue }

    # Check Interrupt Management key
    $regBase = "SYSTEM\CurrentControlSet\Enum\$did"
    $imKey = "HKLM:\$regBase\Device Parameters\Interrupt Management"
    if (-not (Test-Path $imKey)) { _log "SCAN.SKIP.NOIM: $did"; continue }

    $usbRoles = ''; $audioEndpoints = ''; $isIntegratedGpu = $false; $diskTag = ''

    if ($kind -eq 'AUDIO') { $audioEndpoints = _audioEndpoints $did $dname }
    if ($kind -eq 'GPU') { $isIntegratedGpu = $dname -match '(?i)(Intel.*UHD|Intel.*HD Graphics|AMD Radeon.*Graphics\s*$|AMD Radeon\(TM\) Graphics)' }
    if ($kind -eq 'STOR') {
        if ($dname -match '(?i)NVM\s*Express|NVMe') { $diskTag = 'SSD' }
        elseif ($dname -match '(?i)\bSATA\b|AHCI|IDE') {
            $hasSsd = ($physicalDisks | Where-Object { $_.MediaType -in @(4,5) }).Count -gt 0
            $diskTag = if ($hasSsd) { 'SSD' } else { 'HDD' }
        }
    }

    [void]$Devices.Add([PSCustomObject]@{
        Name = $dname; InstanceId = $did; Class = $dclass; RegBase = $regBase
        Kind = $kind; UsbRoles = $usbRoles; AudioEndpoints = $audioEndpoints
        IsIntegratedGpu = $isIntegratedGpu; IsWifi = $isWifi; IsXhci = $isXhci
        IsNetCx = $isCx; DiskTag = $diskTag
    })
    _log "SCAN: $kind $did name=$dname usbRoles=$usbRoles audio=$audioEndpoints wifi=$isWifi iGPU=$isIntegratedGpu cx=$isCx"
}

$Devices = @($Devices | Sort-Object { @{MOUSE=1;XHCI=1;GPU=2;AUDIO=3;NET_NDIS=4;NET_CX=4;STOR=5}[$_.Kind] }, 'Name')
_info "Scanned $($Devices.Count) tunable devices | WiFi=$($WifiIdSet.Count)"

# ──────────────────────────────────────────────
# PHASE 3 ─ FILTERING
# ──────────────────────────────────────────────
_info "=== PHASE 4: Device Filtering ==="
$SkipAutoIds = @{}; $MsiOnlyGpuIds = @{}

# USB filtering block removed by policy (2026, USB stock): USB devices never
# enter $Devices, so no USB controller can reach MSI/priority/affinity paths.
foreach ($d in $Devices | Where-Object Kind -eq GPU) {
    if ($d.IsIntegratedGpu) { $MsiOnlyGpuIds[$d.InstanceId] = $true; _log "AUTO.MSIONLY.GPU: $($d.InstanceId)" }
}
foreach ($d in $Devices | Where-Object Kind -eq AUDIO) {
    $isSpdif = $d.AudioEndpoints -match '(?i)S/PDIF|SPDIF|Digital Output'
    $isDisplay = $d.Name -match '(?i)(NVIDIA.*High Definition Audio|AMD.*High Definition Audio|HDMI|Display Audio|DP\s*Audio)' -or
                 $d.AudioEndpoints -match '(?i)(HDMI|DisplayPort|DP\s*Audio)'
    if ($isSpdif -or $isDisplay) {
        $SkipAutoIds[$d.InstanceId] = $true
        _log "AUTO.SKIP.AUDIO: $($d.InstanceId) ($(if($isSpdif){'S/PDIF'}else{'Display/HDMI'}))"
    }
}

# ──────────────────────────────────────────────
# PHASE 4 ─ CPU ASSIGNMENT
# ──────────────────────────────────────────────
_info "=== PHASE 5: CPU Assignment ==="

$orderedDevices = $Devices |
    Where-Object { -not $WifiIdSet.ContainsKey($_.InstanceId) -and -not $SkipAutoIds.ContainsKey($_.InstanceId) -and -not $MsiOnlyGpuIds.ContainsKey($_.InstanceId) -and $_.Kind -ne 'STOR' -and $_.Kind -ne 'MOUSE' -and $_.Kind -ne 'GPU' -and $_.Kind -ne 'XHCI' }

$prioMap = @{ GPU = 2; NET_NDIS = 3; NET_CX = 3; STOR = 4; AUDIO = 5 }
$orderedDevices = @($orderedDevices | Sort-Object { $prioMap[$_.Kind] })

_log "AUTO.ORDER: $($orderedDevices.Count) devices for affinity assignment"

function Get-PhysicalCores {
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $CpuInfo.ByCore.Keys) {
        $lps = @($CpuInfo.ByCore[$key] | Where-Object { $_ -lt 64 })
        if ($lps.Count) {
            $isP = ($lps | Where-Object { $CpuInfo.PrimaryP -contains $_ }).Count -gt 0
            $groups.Add([pscustomobject]@{ P = $isP; LPS = $lps })
        }
    }
    return @($groups | Sort-Object -Property @{Expression='P';Descending=$true}, @{Expression='LPS';Ascending=$true})
}

$Results = [System.Collections.Generic.List[PSCustomObject]]::new()

function Test-AffinityMaskValid {
    param([UInt64]$Mask, [int]$LogicalCount)
    if ($Mask -eq 0) { return $false }
    if ($LogicalCount -le 0) { return $false }
    for ($i = 0; $i -lt 64; $i++) {
        if (($Mask -shr $i) -band 1) {
            if ($i -ge $LogicalCount) { return $false }
        }
    }
    return $true
}

# NIC vendor RSS confinement (vendor-agnostic): the PnP AssignmentSetOverride bounds the
# initial MSI-X vector affinity. The DPC RSS (real packet work) targets the processors in the
# vendor's RSS-enabled list, which by default is ALL cores. This finds that vendor knob (PnP or
# service Device Parameters) and, if it exists as a numeric mask, confines it to the NIC's pinned
# cores. Reports only otherwise (some drivers manage RSS in the UI only). Read-only in DryRun.
function _nicVendorRSS { param($d, $mask)
      $rb = "HKLM:\$($d.RegBase)"   # RegBase is relative; needs the HKLM:\ prefix
    $svc = $null
    try { $svc = (Get-ItemProperty -Path $rb -ErrorAction SilentlyContinue).Service } catch {}
    $svcDP = if ($svc) { "HKLM:\SYSTEM\CurrentControlSet\Services\$svc\Device Parameters" } else { $null }
    $bases = @("$rb\Device Parameters", $svcDP) | Where-Object { $_ -and (Test-Path $_) }
    $found = @(); $candidates = @()
    foreach ($base in $bases) {
        $keys = @($base) + @((Get-ChildItem $base -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.PSPath }))
        foreach ($k in $keys) {
            $vals = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            if (-not $vals) { continue }
            foreach ($m in ($vals | Get-Member -ErrorAction SilentlyContinue)) {
                if ($m.Name -match '^(PSChildName|PSDrive|PSScriptRoot|PSParent|PSPath)$') { continue }
                if ($m.Name -match 'RSS|Queue|Vendor|Moderation|IntMod|MessageNumber') { $found += ("{0}\{1}" -f (Split-Path $k -Leaf), $m.Name) }
                if ($m.Name -match 'RSS') {
                    $v = $vals | Select-Object -ExpandProperty $m.Name -ErrorAction SilentlyContinue
                    if ($null -ne $v -and ($v -is [int] -or $v -is [long] -or $v -is [uint32] -or $v -is [uint64])) {
                        $candidates += [ordered]@{ K = $k; N = $m.Name }
                    }
                }
            }
        }
    }
    if ($DryRun) {
        if ($candidates.Count) { $ct = ($candidates | ForEach-Object { "{0}\{1}" -f (Split-Path $_.K -Leaf), $_.N }) -join '; '; _log "DRYRUN NIC-RSS: $($d.InstanceId) -> would confine RSS mask 0x$($mask.ToString('X')) on: $ct" }
        elseif ($found.Count) { _log "DRYRUN NIC-RSS: $($d.InstanceId) svc=$svc -> vendor knobs present: $($found -join '; ')" }
        else { _warn "DRYRUN NIC-RSS: $($d.InstanceId) svc=$svc -> no RSS/queue knob in registry (driver-managed / UI-only). PnP 2-core pin is the registry-level confine." }
        return
    }
    if ($candidates.Count) {
        foreach ($c in $candidates) {
            Set-ItemProperty -Path $c.K -Name $c.N -Value ([UInt64]$mask) -Force -ErrorAction SilentlyContinue
            _log "NIC-RSS: $($d.InstanceId) -> confined {0}\{1} = 0x{2:X}" -f (Split-Path $c.K -Leaf), $c.N, ([UInt64]$mask)
        }
    }
    elseif ($found.Count) {
        _log "NIC-RSS: $($d.InstanceId) svc=$svc -> vendor knobs present (not a numeric RSS mask, left as-is): $($found -join '; ')"
    }
    else {
        _warn "NIC-RSS: $($d.InstanceId) svc=$svc -> no RSS/queue/moderation knob in registry (driver-managed / UI-only). PnP 2-core pin is the registry-level confine."
    }
}
$physCores = @(Get-PhysicalCores)
# Reserver le coeur contenant CPU 0 (systeme/timer) tant qu'il reste assez de coeurs.
$pool = @($physCores | Where-Object { $_.LPS -notcontains 0 })
if ($pool.Count -lt 2) { $pool = @($physCores) }

$lowThreadCpu = ($CpuInfo.Logical -le 8)
if ($lowThreadCpu) { _warn "AUTO.LOWTHREADS: $($CpuInfo.Logical) logical processors - interrupt AFFINITY pinning skipped (MSI + priority only)." }

$isLaptopChassis = $false
try {
    $chassis = Get-CimInstance Win32_SystemEnclosure -EA SilentlyContinue | Select-Object -ExpandProperty ChassisTypes
    $mobileTypes = @(8,9,10,11,12,14,18,21,30,31)
    if ($chassis -and ($chassis | Where-Object { $mobileTypes -contains $_ })) { $isLaptopChassis = $true }
} catch { $isLaptopChassis = $false }
if ($isLaptopChassis) { _warn "AUTO.LAPTOP: portable chassis - interrupt AFFINITY pinning skipped (MSI + priority only)." }
if ($IsAmdX3D) { _warn "AUTO.X3D: AMD 3D V-Cache - interrupt AFFINITY pinning skipped (MSI + priority only)." }
$skipAffinity = $lowThreadCpu -or $IsAmdX3D -or $isLaptopChassis

_log "AUTO.CPU: physical cores = [$($pool | ForEach-Object { $_.LPS -join '+' })], SMT=$($CpuInfo.SMT)"

# ---------------------------------------------------------------------------
# GPU (dedicated core): the graphics driver interrupt/DPC path is the biggest
# source of frametime jitter. Pin it to the BEST P-core (pool[0]) - the same
# heuristic AutoGpuAffinity benchmarks for (best single-core perf), without the
# 20-min PresentMon run. Core 0 is already excluded (system/timers). The GPU core
# is reserved: no NIC/storage/audio interrupt shares it. Mouse takes pool[1].
# ---------------------------------------------------------------------------
$gpuEntries = @($Devices | Where-Object { $_.Kind -eq 'GPU' -and -not $MsiOnlyGpuIds.ContainsKey($_.InstanceId) })
if ($gpuEntries.Count -and $pool.Count -ge 1) {
    $gpuCore = $pool[0]
    $gpuLps = @($gpuCore.LPS)
    $gpuMask = [UInt64]0
    foreach ($l in $gpuLps) { $gpuMask = $gpuMask -bor ([UInt64]1 -shl $l) }
    $gpuValid = (Test-AffinityMaskValid -Mask $gpuMask -LogicalCount $CpuInfo.Logical)
    foreach ($d in $gpuEntries) {
        [void]$Results.Add([PSCustomObject]@{ Device=$d; LPs=$gpuLps; Mask=$gpuMask; Policy='SpecCPU'; Prio='High'; AffinityValid=$gpuValid })
        _ok "AUTO.GPU: $($d.Name) -> Core=$($gpuLps -join '+') Mask=0x$($gpuMask.ToString('X')) valid=$gpuValid"
    }
    if ($pool.Count -ge 2) {
        $pool = @($pool | Where-Object { ($_.LPS -join '+') -ne ($gpuCore.LPS -join '+') })
        _log "AUTO.GPU.RESERVE: core [$($gpuCore.LPS -join '+')] reserved - GPU dedicated (best P-core)"
    } else {
        _log "AUTO.GPU.SHARE: single-core pool - GPU shares core (no reservation possible)"
    }
} elseif ($gpuEntries.Count) {
    _warn "AUTO.GPU: no core in pool - GPU MSI + priority only"
}
# ---------------------------------------------------------------------------
# INPUT (USB mouse / keyboard): the HID child device has no IM key; its
# interrupt is serviced by the xHCI host controller (the USB-class device WITH
# an IM key). Pin that controller's IRQ/DPC to a dedicated physical core (MSI +
# High priority + affinity). The GPU already owns the best P-core, so the input
# takes the next best (pool[0] now = 2nd best). That core is reserved: no
# NIC/storage/audio interrupt is assigned to it, so the input IRQ/DPC path is
# never preempted by a network burst or a GPU interrupt.
# ---------------------------------------------------------------------------
$inputEntries = @($Devices | Where-Object { $_.Kind -eq 'XHCI' })
if ($inputEntries.Count -and $pool.Count -ge 1) {
    $inputCore = $pool[0]
    $inputLps = @($inputCore.LPS)
    $inputMask = [UInt64]0
    foreach ($l in $inputLps) { $inputMask = $inputMask -bor ([UInt64]1 -shl $l) }
    $inputValid = (Test-AffinityMaskValid -Mask $inputMask -LogicalCount $CpuInfo.Logical)
    foreach ($d in $inputEntries) {
        [void]$Results.Add([PSCustomObject]@{ Device=$d; LPs=$inputLps; Mask=$inputMask; Policy='SpecCPU'; Prio='High'; AffinityValid=$inputValid })
        _ok "AUTO.INPUT: $($d.Name) -> Core=$($inputLps -join '+') Mask=0x$($inputMask.ToString('X')) valid=$inputValid"
    }
    if ($pool.Count -ge 2) {
        $pool = @($pool | Where-Object { ($_.LPS -join '+') -ne ($inputCore.LPS -join '+') })
        _log "AUTO.INPUT.RESERVE: core [$($inputCore.LPS -join '+')] reserved - USB input dedicated (2nd best P-core)"
    } else {
        _log "AUTO.INPUT.SHARE: single-core pool - USB input shares core (no reservation possible)"
    }
} elseif ($inputEntries.Count) {
    _warn "AUTO.INPUT: no core in pool - USB input MSI + priority only"
}

$pi = 0
foreach ($d in $orderedDevices) {
    $nicCount = if ($d.Kind -match 'NET') { [Math]::Min(2, $pool.Count) } else { 1 }
    $lps = @()
    foreach ($k in 0..($nicCount-1)) { $c = $pool[($pi + $k) % $pool.Count]; $lps += @($c.LPS) }
    $pi += $nicCount
    if (-not $lps.Count) { _warn "AUTO: $($d.Kind) $($d.InstanceId) -> no core available"; continue }

    $mask = [UInt64]0; foreach ($l in $lps) { $mask = $mask -bor ([UInt64]1 -shl $l) }

    $policy = 'SpecCPU'
    $affinityRestricted = $d.Kind -eq 'AUDIO'
    if ($affinityRestricted) { _log "AUTO.RESTRICT: $($d.Kind) $($d.InstanceId) -> MSI + priority only (affinity restricted in 26.09.1.1)" }
      # NIC overrides the LOWTHREADS guard: pinning the NIC to 2 cores on an 8-thread CPU is safe
      # (it is the whole point of RSS/DPC confinement). X3D + laptop guards still apply.
      $nicOverrideLowThreads = ($d.Kind -match 'NET') -and $lowThreadCpu -and (-not ($IsAmdX3D -or $isLaptopChassis))
      $skipAffEff = $skipAffinity -and -not $nicOverrideLowThreads
      $affinityValid = if ($skipAffEff -or $affinityRestricted) { $false } else { Test-AffinityMaskValid -Mask $mask -LogicalCount $CpuInfo.Logical }
    if (-not $affinityValid) {
        _warn "AUTO.TOPO.INVALID: $($d.Kind) $($d.InstanceId) Mask=0x$($mask.ToString('X')) invalid for Logical=$($CpuInfo.Logical) — falling back to MSI+priority only (no AssignmentSetOverride)"
    }

    [void]$Results.Add([PSCustomObject]@{ Device=$d; LPs=$lps; Mask=$mask; Policy=$policy; Prio='High'; AffinityValid=$affinityValid })
    if ($d.Kind -match 'NET') { _nicVendorRSS -d $d -mask $mask }
    _log "AUTO: $($d.Kind) $($d.InstanceId) -> Core=$($lps -join '+') Mask=0x$($mask.ToString('X')) valid=$affinityValid"
}

# ──────────────────────────────────────────────
# PHASE 5 ─ APPLY REGISTRY
# ──────────────────────────────────────────────
_info "=== PHASE 6: Apply Registry Settings ==="

function _applyDevice($r) {
    $d = $r.Device; $rb = $d.RegBase
    $imKey = "HKLM:\$rb\Device Parameters\Interrupt Management"
    if ($DryRun) { _log "DRYRUN: $($d.InstanceId) Kind=$($d.Kind) LP=[$($r.LPs -join ',')]"; return }

    try {
        $null = New-Item "$imKey" -Force -EA SilentlyContinue
        # MSI
        $msiP = "$imKey\MessageSignaledInterruptProperties"
        $null = New-Item $msiP -Force -EA SilentlyContinue
        Set-ItemProperty $msiP -Name MSISupported -Value 1 -Type DWord -Force
        if ($d.Kind -notmatch 'NET') { Set-ItemProperty $msiP -Name MessageNumberLimit -Value 0 -Type DWord -Force }
        # Priority
        $affP = "$imKey\Affinity Policy"
        $null = New-Item $affP -Force -EA SilentlyContinue
        $pv = @{Low=1;Normal=2;High=3}[$r.Prio]
        Set-ItemProperty $affP -Name DevicePriority -Value $pv -Type DWord -Force

        if ($r.AffinityValid) {
            $polV = @{MachineDefault=0;All=1;Single=2;AllClose=3;SpecCPU=4;SpreadMessages=5}[$r.Policy]
            Set-ItemProperty $affP -Name DevicePolicy -Value $polV -Type DWord -Force
            $bytes = if ([Environment]::Is64BitOperatingSystem) { [BitConverter]::GetBytes([UInt64]$r.Mask) } else { [BitConverter]::GetBytes([UInt32]$r.Mask) }
            Set-ItemProperty $affP -Name AssignmentSetOverride -Value $bytes -Type Binary -Force
            _ok "APPLY: $($d.Kind) $($d.InstanceId) LP=[$($r.LPs -join ',')]"
        } else {
            Set-ItemProperty $affP -Name DevicePolicy -Value 0 -Type DWord -Force
            Remove-ItemProperty $affP -Name AssignmentSetOverride -ErrorAction SilentlyContinue
            _ok "APPLY.TOPO.SAFE: $($d.Kind) $($d.InstanceId) MSI+priority only (affinity skipped)"
        }
    } catch { _err "APPLY.FAIL: $($d.InstanceId): $_" }
}

# Integrated GPUs: MSI only
foreach ($d in $Devices | Where-Object { $MsiOnlyGpuIds.ContainsKey($_.InstanceId) }) {
    if (-not $DryRun) {
        try {
            $msiP = "HKLM:\$($d.RegBase)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $null = New-Item $msiP -Force -EA SilentlyContinue
            Set-ItemProperty $msiP -Name MSISupported -Value 1 -Type DWord -Force
            Set-ItemProperty $msiP -Name MessageNumberLimit -Value 0 -Type DWord -Force
            _log "APPLY.MSIONLY.GPU: $($d.InstanceId)"
        } catch { _err "APPLY.MSIONLY.GPU.FAIL: $($d.InstanceId): $_" }
    }
}

foreach ($d in $Devices | Where-Object { $SkipAutoIds.ContainsKey($_.InstanceId) }) {
    if ($WifiIdSet.ContainsKey($d.InstanceId) -or $MsiOnlyGpuIds.ContainsKey($d.InstanceId)) { continue }
    if (-not $DryRun) {
        try {
            $msiP = "HKLM:\$($d.RegBase)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $affP = "HKLM:\$($d.RegBase)\Device Parameters\Interrupt Management\Affinity Policy"
            $null = New-Item $msiP -Force -EA SilentlyContinue
            $null = New-Item $affP -Force -EA SilentlyContinue
            Set-ItemProperty $msiP -Name MSISupported -Value 1 -Type DWord -Force
            Set-ItemProperty $msiP -Name MessageNumberLimit -Value 0 -Type DWord -Force
            Set-ItemProperty $affP -Name DevicePriority -Value 2 -Type DWord -Force
            if ($d.Kind -notmatch 'NET') {
                Set-ItemProperty $affP -Name DevicePolicy -Value 0 -Type DWord -Force
                Remove-ItemProperty $affP -Name AssignmentSetOverride -EA SilentlyContinue
            }
            _log "APPLY.SKIPAUTO: $($d.InstanceId)"
        } catch { _err "APPLY.SKIPAUTO.FAIL: $($d.InstanceId): $_" }
    }
}

# Main assignments
foreach ($r in $Results) { _applyDevice $r }

# ──────────────────────────────────────────────
# NVIDIA GPU: RmForceEnableMSI - prerequisite for SpecCPU affinity
# ──────────────────────────────────────────────
$nvidiaGpu = $Devices | Where-Object { $_.Kind -eq 'GPU' -and $_.InstanceId -match 'VEN_10DE' -and -not $_.IsIntegratedGpu } | Select-Object -First 1
if ($nvidiaGpu) {
    if ($DryRun) { _log "DRYRUN: RmForceEnableMSI -> HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" }
    else {
        try {
            $nvt = "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak"
            $null = New-Item $nvt -Force -EA SilentlyContinue
            Set-ItemProperty $nvt -Name RmForceEnableMSI -Value 1 -Type DWord -Force
            _ok "NVIDIA GPU $($nvidiaGpu.InstanceId): RmForceEnableMSI=1 (MSI active -> SpecCPU affinity effective)"
        } catch { _err "NVIDIA.RMFORCEMSI.FAIL: $_" }
    }
} else {
    _log "NVIDIA GPU not detected - RmForceEnableMSI skipped"
}

# (PHASE 7 — Lock Interrupt Routing — REMOVED: forcing Interrupt Steering
#  Mode = 4 destabilized boot on some Windows builds / NVMe controllers.
#  Interrupt routing is left at Windows defaults, no opt-in offered.)

# ──────────────────────────────────────────────
# PHASE 8 ─ SUMMARY
# ──────────────────────────────────────────────
_info "=== SUMMARY ==="
Write-Host ""
Write-Host "============================================" -F Green
Write-Host "  DEVICE TWEAKER Auto-Optimization Complete" -F Green
Write-Host "============================================" -F Green
Write-Host ""
Write-Host "CPU: $($CpuInfo.Name)" -F Cyan
Write-Host "  P-cores: $($CpuInfo.PrimaryP.Count) ($($CpuInfo.PrimaryP -join ', '))"
if ($CpuInfo.PrimaryE.Count) { Write-Host "  E-cores: $($CpuInfo.PrimaryE.Count) ($($CpuInfo.PrimaryE -join ', '))" }
if ($CpuInfo.MultiCcd) { Write-Host "  Multi-CCD: Yes (targeting CCD $($CpuInfo.TargetCcd))" -F Yellow }
Write-Host ""
Write-Host "Devices:" -F Cyan
Write-Host "  Scanned:         $($Devices.Count)"
Write-Host "  Affinity set:    $($Results.Count)" -F Green
Write-Host "  WiFi (MSI+Prio): $($WifiIdSet.Count)"
Write-Host "  iGPU (MSI only): $($MsiOnlyGpuIds.Count)"
Write-Host "  Skipped:         $($SkipAutoIds.Count)"
Write-Host ""
foreach ($r in $Results) {
    Write-Host "  $($r.Device.Kind.PadRight(8)) $($r.Device.Name.Substring(0,[Math]::Min(40,$r.Device.Name.Length))) -> CPU $($r.LPs -join ',')" -F White
}
Write-Host ""
Write-Host "Log: $Script:LogPath" -F DarkGray
Write-Host ""
if ($DryRun) { Write-Host "*** DRY RUN - No changes written ***" -F Magenta }
Write-Host ""
Write-Host "============================================" -F Green

} catch {
    Write-Host ""
    Write-Host "============================================" -F Red
    Write-Host "  ERROR: $($_.Exception.Message)" -F Red
    Write-Host "  Line:  $($_.InvocationInfo.ScriptLineNumber)" -F Red
    Write-Host "  File:  $($_.InvocationInfo.ScriptName)" -F Red
    Write-Host "============================================" -F Red
    Write-Host ""
    _err "FATAL: $($_.Exception.Message)"
    _err "Stack: $($_.ScriptStackTrace)"
} finally {}

exit 0
