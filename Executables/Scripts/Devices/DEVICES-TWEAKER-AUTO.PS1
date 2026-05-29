#Requires -RunAsAdministrator

param(
    [switch]$DryRun,
    [string]$WinioPath = "C:\Windows\LexBoosTOS\Resources\winio.sys",
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
        if ($l3.Count -ge 2) {
            $CpuInfo.MultiCcd = $true
            $CpuInfo.TargetCcd = $l3.Count - 1
            $lpsPerCcd = [Math]::Floor($CpuInfo.Logical / $l3.Count)
            for ($i = 0; $i -lt $CpuInfo.Logical; $i++) {
                $cid = [Math]::Min([Math]::Floor($i / $lpsPerCcd), $l3.Count - 1)
                $CpuInfo.CcdMap[$i] = $cid
                if ($cid -eq $CpuInfo.TargetCcd) { [void]$CpuInfo.TargetCcdLps.Add($i) }
            }
            # Filter to target CCD
            $fp = [System.Collections.Generic.List[int]]::new()
            $fe = [System.Collections.Generic.List[int]]::new()
            foreach ($l in $CpuInfo.PrimaryP) { if ($CpuInfo.TargetCcdLps -contains $l) { [void]$fp.Add($l) } }
            foreach ($l in $CpuInfo.PrimaryE) { if ($CpuInfo.TargetCcdLps -contains $l) { [void]$fe.Add($l) } }
            if ($fp.Count -gt 0 -or $fe.Count -gt 0) { $CpuInfo.PrimaryP = $fp; $CpuInfo.PrimaryE = $fe }
            else { $CpuInfo.PrimaryP = $CpuInfo.TargetCcdLps; $CpuInfo.PrimaryE.Clear() }
            _log "CPU.CCD: Multi-CCD count=$($l3.Count) target=$($CpuInfo.TargetCcd) LPs=[$($CpuInfo.TargetCcdLps -join ',')]"
        }
    } catch { _log "CPU.CCD: detection error: $_" }
}
# Default single-CCD
if (-not $CpuInfo.MultiCcd) {
    for ($i = 0; $i -lt $CpuInfo.Logical; $i++) { $CpuInfo.CcdMap[$i] = 0 }
    $CpuInfo.TargetCcd = 0
    0..($CpuInfo.Logical - 1) | ForEach-Object { [void]$CpuInfo.TargetCcdLps.Add($_) }
}

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

# USB role detection: enumerate children of USB controllers
function _usbRoles($deviceId) {
    $roles = [System.Collections.Generic.List[string]]::new()
    $norm = $deviceId -replace '\\\\','\'
    foreach ($svc in @('kbdhid','kbdclass','mouhid','mouclass','hidusb')) {
        try {
            $found = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\$norm" -Recurse -Depth 2 -EA SilentlyContinue |
                Where-Object { (Get-ItemProperty $_.PSPath -Name Service -EA SilentlyContinue).Service -eq $svc } | Select-Object -First 1
            if ($found) {
                $role = if ($svc -in @('kbdhid','kbdclass')) { 'Keyboard' }
                        elseif ($svc -in @('mouhid','mouclass')) { 'Mouse' }
                        else { 'HID' }
                if ($role -notin $roles) { [void]$roles.Add($role) }
            }
        } catch {}
    }
    return $roles -join ', '
}

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

    # Classification
    $kind = 'OTHER'; $isWifi = $false; $isXhci = $false; $isCx = $false
    if ($dclass -eq 'USB' -or $dname -match '(?i)xHCI|Host Controller') { $kind = 'USB'; $isXhci = $dname -match '(?i)xHCI|Host Controller' }
    elseif ($dclass -eq 'Display') { $kind = 'GPU' }
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

    if ($kind -eq 'OTHER') { _log "SCAN.SKIP.OTHER: $did class=$dclass"; continue }

    # Check Interrupt Management key
    $regBase = "SYSTEM\CurrentControlSet\Enum\$did"
    $imKey = "HKLM:\$regBase\Device Parameters\Interrupt Management"
    if (-not (Test-Path $imKey)) { _log "SCAN.SKIP.NOIM: $did"; continue }

    $usbRoles = ''; $audioEndpoints = ''; $isIntegratedGpu = $false; $diskTag = ''

    if ($kind -eq 'USB') {
        $usbRoles = _usbRoles $did
        if (-not $usbRoles) { _log "SCAN.SKIP.USB.NOROLES: $did"; continue }
    }
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

$Devices = @($Devices | Sort-Object { @{USB=1;GPU=2;AUDIO=3;NET_NDIS=4;NET_CX=4;STOR=5}[$_.Kind] }, 'Name')
_info "Scanned $($Devices.Count) tunable devices | WiFi=$($WifiIdSet.Count)"

# ──────────────────────────────────────────────
# PHASE 3 ─ RESET ALL
# ──────────────────────────────────────────────
_info "=== PHASE 3: Reset Existing Settings ==="

function _resetReg {
    param($RegBase, $Kind, $InstanceId)
    $imKey  = "HKLM:\$RegBase\Device Parameters\Interrupt Management"
    try {
        # Clear Priority subkey
        Remove-Item "$imKey\Priority" -Recurse -Force -EA SilentlyContinue
    } catch {}
    try {
        # Clear Affinity Policy values (keep key)
        Remove-ItemProperty "$imKey\Affinity Policy" -Name DevicePriority -EA SilentlyContinue
        Remove-ItemProperty "$imKey\Affinity Policy" -Name DevicePolicy -EA SilentlyContinue
        Remove-ItemProperty "$imKey\Affinity Policy" -Name AssignmentSetOverride -EA SilentlyContinue
    } catch {}
    # RSS clear for NET (skip RSS for NET devices; can break WiFi/Ethernet connectivity)
    if ($Kind -match 'NET' -and $false) {
        try {
            $driver = (Get-ItemProperty "HKLM:\$RegBase" -Name Driver -EA SilentlyContinue).Driver
            if ($driver) {
                $cp = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driver"
                Remove-ItemProperty $cp -Name '*RssBaseProcNumber' -EA SilentlyContinue
                Remove-ItemProperty $cp -Name '*NumRssQueues' -EA SilentlyContinue
                _log "RESET.RSS: $InstanceId"
            }
        } catch {}
    }
    _log "RESET: $InstanceId Kind=$Kind"
}

# Clear ReservedCpuSets
try { Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel" -Name ReservedCpuSets -EA SilentlyContinue; _ok "Cleared ReservedCpuSets" } catch {}

if (-not $DryRun) {
    foreach ($d in $Devices) {
        if (-not $WifiIdSet.ContainsKey($d.InstanceId)) {
            _resetReg $d.RegBase $d.Kind $d.InstanceId
        } else {
            _log "RESET.SKIP.WIFI: $($d.InstanceId)"
        }
    }
}

# ──────────────────────────────────────────────
# PHASE 4 ─ FILTERING
# ──────────────────────────────────────────────
_info "=== PHASE 4: Device Filtering ==="
$SkipAutoIds = @{}; $MsiOnlyGpuIds = @{}

foreach ($d in $Devices | Where-Object Kind -eq USB) {
    if (-not $d.UsbRoles) { $SkipAutoIds[$d.InstanceId] = $true; _log "AUTO.SKIP.USB: $($d.InstanceId) (no HID)" }
}
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
# PHASE 5 ─ CPU ASSIGNMENT
# ──────────────────────────────────────────────
_info "=== PHASE 5: CPU Assignment ==="

$orderedDevices = $Devices |
    Where-Object { $_.Kind -ne 'STOR' -and -not $WifiIdSet.ContainsKey($_.InstanceId) -and -not $SkipAutoIds.ContainsKey($_.InstanceId) -and -not $MsiOnlyGpuIds.ContainsKey($_.InstanceId) }

$prioMap = @{ USB = 1; GPU = 2; NET_NDIS = 3; NET_CX = 3; AUDIO = 4 }
$orderedDevices = @($orderedDevices | Sort-Object { $prioMap[$_.Kind] })

_log "AUTO.ORDER: $($orderedDevices.Count) devices for affinity assignment"

$coreOrder = $(if ($CpuInfo.PrimaryP.Count) { $CpuInfo.PrimaryP } else { $CpuInfo.PrimaryE }) | Where-Object { $_ -lt 64 }
$zeroAvailable = $coreOrder -contains 0

# Audio E-core queue (exclude CPU 0, clamp to < 64)
$audioQueue = [System.Collections.Generic.Queue[int]]::new()
foreach ($lp in $CpuInfo.PrimaryE) { if ($lp -ne 0 -and $lp -lt 64) { $audioQueue.Enqueue($lp) } }
$useAudioE = $CpuInfo.PrimaryP.Count -gt 0 -and $audioQueue.Count -gt 0

# Available pool (avoid CPU 0 initially, clamp to < 64)
$avail = [System.Collections.Generic.List[int]]::new()
foreach ($lp in $coreOrder) { if ($lp -ne 0) { [void]$avail.Add($lp) } }

$audioCt = ($orderedDevices | Where-Object Kind -eq AUDIO).Count
$audioECt = if ($useAudioE) { [Math]::Min($audioCt, $audioQueue.Count) } else { 0 }
$totalNeeded = (($orderedDevices | ForEach-Object { if ($_.Kind -eq 'GPU') {2} else {1} } | Measure-Object -Sum).Sum) - $audioECt
if ($totalNeeded -lt 0) { $totalNeeded = 0 }
if ($avail.Count -lt $totalNeeded -and $zeroAvailable) { [void]$avail.Add(0) }
$extras = [Math]::Max(0, $avail.Count - $totalNeeded)
$ai = 0; $aeAssigned = 0

_log "AUTO.CPU: pool=[$($avail -join ',')] needed=$totalNeeded extras=$extras audioE=$audioECt"

function _take([int]$n) {
    $r = [System.Collections.Generic.List[int]]::new()
    while ($r.Count -lt $n -and $script:ai -lt $avail.Count) { [void]$r.Add($avail[$script:ai]); $script:ai++ }
    if ($r.Count -eq $n -and $script:extras -gt 0 -and $script:ai -lt $avail.Count) { $script:ai++; $script:extras-- }
    return $r
}

$Results = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($d in $orderedDevices) {
    $need = if ($d.Kind -eq 'GPU') { 2 } else { 1 }
    if ($useAudioE -and $d.Kind -eq 'AUDIO' -and $aeAssigned -lt $audioECt) {
        $lps = if ($audioQueue.Count) { @($audioQueue.Dequeue()) } else { @() }
        if ($lps.Count) { $aeAssigned++ }
    } else { $lps = _take $need }
    if (-not $lps.Count) { _warn "AUTO: $($d.Kind) $($d.InstanceId) -> no LP available"; continue }

    $mask = [UInt64]0; foreach ($l in $lps) { if ($l -ge 64) { _warn "AUTO: LP $l exceeds 64-bit mask, skipping"; continue }; $mask = $mask -bor ([UInt64]1 -shl $l) }
    $policy = if ($d.Kind -match 'NET') { $null } else { 'SpecCPU' }

    [void]$Results.Add([PSCustomObject]@{ Device=$d; LPs=$lps; Mask=$mask; Policy=$policy; Prio='High' })
    _log "AUTO: $($d.Kind) $($d.InstanceId) -> LP=[$($lps -join ',')] Mask=0x$($mask.ToString('X'))"
}

# ──────────────────────────────────────────────
# PHASE 6 ─ APPLY REGISTRY
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
        # Policy + Mask
        if ($d.Kind -notmatch 'NET') {
            $polV = @{MachineDefault=0;All=1;Single=2;AllClose=3;SpecCPU=4;SpreadMessages=5}[$r.Policy]
            Set-ItemProperty $affP -Name DevicePolicy -Value $polV -Type DWord -Force
            $bytes = if ([Environment]::Is64BitOperatingSystem) { [BitConverter]::GetBytes([UInt64]$r.Mask) } else { [BitConverter]::GetBytes([UInt32]$r.Mask) }
            Set-ItemProperty $affP -Name AssignmentSetOverride -Value $bytes -Type Binary -Force
        } else {
            Set-ItemProperty $affP -Name DevicePolicy -Value 0 -Type DWord -Force
        }
        _ok "APPLY: $($d.Kind) $($d.InstanceId) LP=[$($r.LPs -join ',')]"
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

# WiFi: skipped entirely (MSI forcing breaks many WiFi drivers)

# Skipped auto devices: MSI + Normal priority, no affinity
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
# PHASE 7 ─ IMOD (xHCI Interrupt Moderation)
# ──────────────────────────────────────────────
if (-not $SkipImod) {
    _info "=== PHASE 7: IMOD (xHCI Interrupt Moderation) ==="

    if ($DryRun) {
        _warn "DRYRUN: Skipping IMOD hardware writes"
    } else {
        $winioSys = $WinioPath
        if (-not (Test-Path $winioSys)) {
            _err "winio.sys not found: $winioSys"
            _err "Skipping IMOD phase. Use -WinioPath to specify correct path, or -SkipImod to skip."
        } else {
            # ── Embedded C# for winio/xHCI hardware access ──
            $csharpCode = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class DeviceTweakerWinIO
{
    private const uint CM_PROB_DISABLED = 0x00000016;
    private const uint DIGCF_PRESENT = 0x00000002;
    private const uint DIGCF_ALLCLASSES = 0x00000004;
    private const uint SPDRP_SERVICE = 0x00000004;
    private const uint SPDRP_HARDWAREID = 0x00000001;
    private const uint SPDRP_COMPATIBLEIDS = 0x00000002;
    private const uint SPDRP_FRIENDLYNAME = 0x0000000C;
    private const uint SPDRP_DEVICEDESC = 0x00000000;
    private const uint REG_SZ = 1;
    private const uint REG_MULTI_SZ = 7;
    private const uint ALLOC_LOG_CONF = 0x00000002;
    private const uint BOOT_LOG_CONF = 0x00000003;
    private const uint RES_TYPE_MEM = 0x00000001;
    private const uint RES_TYPE_MEM_LARGE = 0x00000007;
    private const int CR_SUCCESS = 0x00000000;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const int ERROR_NO_MORE_ITEMS = 259;
    private const int ERROR_SERVICE_DOES_NOT_EXIST = 1060;
    private const int ERROR_SERVICE_ALREADY_RUNNING = 1056;
    private const uint SC_MANAGER_ALL_ACCESS = 0x000F003F;
    private const uint SERVICE_ALL_ACCESS = 0x000F01FF;
    private const uint SERVICE_KERNEL_DRIVER = 0x00000001;
    private const uint SERVICE_DEMAND_START = 0x00000003;
    private const uint SERVICE_ERROR_NORMAL = 0x00000001;
    private const uint SERVICE_CONTROL_STOP = 0x00000001;
    private const uint SERVICE_RUNNING = 0x00000004;
    private const uint SERVICE_STOPPED = 0x00000001;
    private const int SC_STATUS_PROCESS_INFO = 0;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    private const uint FILE_DEVICE_WINIO = 0x00008010;
    private const uint WINIO_IOCTL_INDEX = 0x810;
    private const uint METHOD_BUFFERED = 0;
    private const uint FILE_ANY_ACCESS = 0;
    private const string WINIO_DEVICE_PATH = "\\\\.\\WINIO";
    private const string WINIO_SERVICE_NAME = "WINIO";
    private static readonly uint IOCTL_WINIO_MAPPHYSTOLIN = CTL_CODE(FILE_DEVICE_WINIO, WINIO_IOCTL_INDEX, METHOD_BUFFERED, FILE_ANY_ACCESS);
    private static readonly uint IOCTL_WINIO_UNMAPPHYSADDR = CTL_CODE(FILE_DEVICE_WINIO, WINIO_IOCTL_INDEX + 1, METHOD_BUFFERED, FILE_ANY_ACCESS);
    private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevsW(IntPtr classGuid, string enumerator, IntPtr hwndParent, uint flags);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInfo(IntPtr deviceInfoSet, uint memberIndex, ref SP_DEVINFO_DATA deviceInfoData);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceRegistryPropertyW(IntPtr deviceInfoSet, ref SP_DEVINFO_DATA deviceInfoData, uint property, out uint propertyRegDataType, byte[] propertyBuffer, uint propertyBufferSize, out uint requiredSize);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInstanceIdW(IntPtr deviceInfoSet, ref SP_DEVINFO_DATA deviceInfoData, StringBuilder deviceInstanceId, int deviceInstanceIdSize, out int requiredSize);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Get_DevNode_Status(out uint status, out uint problem, uint devInst, uint flags);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Get_First_Log_Conf(out IntPtr logConf, uint devInst, uint flags);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Get_Next_Res_Des(out IntPtr resDes, IntPtr logConfOrResDes, uint forResource, IntPtr resourceId, uint flags);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Get_Res_Des_Data_Size(out uint dataSize, IntPtr resDes, uint flags);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Get_Res_Des_Data(IntPtr resDes, byte[] buffer, uint bufferLen, uint flags);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Free_Res_Des_Handle(IntPtr resDes);
    [DllImport("cfgmgr32.dll", SetLastError = true)]
    private static extern int CM_Free_Log_Conf_Handle(IntPtr logConf);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr OpenSCManager(string machineName, string databaseName, uint desiredAccess);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr OpenService(IntPtr scm, string serviceName, uint desiredAccess);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateService(IntPtr scm, string serviceName, string displayName, uint desiredAccess, uint serviceType, uint startType, uint errorControl, string binaryPathName, string loadOrderGroup, IntPtr tagId, string dependencies, string serviceStartName, string password);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool StartService(IntPtr service, uint numServiceArgs, IntPtr serviceArgVectors);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool QueryServiceStatusEx(IntPtr service, int infoLevel, ref SERVICE_STATUS_PROCESS buffer, uint bufferSize, out uint bytesNeeded);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool ControlService(IntPtr service, uint control, ref SERVICE_STATUS serviceStatus);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool DeleteService(IntPtr service);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CloseServiceHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFile(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(IntPtr deviceHandle, uint ioControlCode, ref PHYS_STRUCT inBuffer, int inBufferSize, ref PHYS_STRUCT outBuffer, int outBufferSize, out int bytesReturned, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private static uint CTL_CODE(uint deviceType, uint function, uint method, uint access) { return (deviceType << 16) | (access << 14) | (function << 2) | method; }

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVINFO_DATA { public uint cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct PHYS_STRUCT { public ulong physMemSizeInBytes; public ulong physAddress; public ulong physicalMemoryHandle; public ulong physMemLin; public ulong physSection; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MEM_DES { public uint MD_Count; public uint MD_Type; public ulong MD_Alloc_Base; public ulong MD_Alloc_End; public uint MD_Flags; public uint MD_Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MEM_RANGE { public ulong MR_Align; public uint MR_nBytes; public ulong MR_Min; public ulong MR_Max; public uint MR_Flags; public uint MR_Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MEM_LARGE_DES { public uint MLD_Count; public uint MLD_Type; public ulong MLD_Alloc_Base; public ulong MLD_Alloc_End; public uint MLD_Flags; public uint MLD_Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MEM_LARGE_RANGE { public ulong MLR_Align; public ulong MLR_nBytes; public ulong MLR_Min; public ulong MLR_Max; public uint MLR_Flags; public uint MLR_Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    private struct SERVICE_STATUS_PROCESS { public uint dwServiceType; public uint dwCurrentState; public uint dwControlsAccepted; public uint dwWin32ExitCode; public uint dwServiceSpecificExitCode; public uint dwCheckPoint; public uint dwWaitHint; public uint dwProcessId; public uint dwServiceFlags; }
    [StructLayout(LayoutKind.Sequential)]
    private struct SERVICE_STATUS { public uint dwServiceType; public uint dwCurrentState; public uint dwControlsAccepted; public uint dwWin32ExitCode; public uint dwServiceSpecificExitCode; public uint dwCheckPoint; public uint dwWaitHint; }

    public class XhciControllerInfo {
        public string DeviceId; public uint ProblemCode; public ulong BaseAddress; public string BaseError;
    }

    public class ImodResult {
        public int ControllersFound;
        public int ControllersApplied;
        public int WriteFailures;
        public int SkippedDisabled;
        public int MissingBase;
        public int ReadFailures;
        public List<string> Log = new List<string>();
    }

    public static ImodResult ApplyImod(string winioSysPath, uint imodInterval, List<string> psLog) {
        var result = new ImodResult();
        Action<string> L = m => { result.Log.Add(m); psLog.Add(m); };

        L(string.Format("IMOD: Starting with winio.sys at {0}, interval=0x{1:X}", winioSysPath, imodInterval));

        // Enumerate xHCI controllers
        var controllers = new List<XhciControllerInfo>();
        IntPtr devInfoSet = SetupDiGetClassDevsW(IntPtr.Zero, "PCI", IntPtr.Zero, DIGCF_PRESENT | DIGCF_ALLCLASSES);
        if (devInfoSet == INVALID_HANDLE_VALUE) { L(string.Format("IMOD.ERR: SetupDiGetClassDevsW failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result; }
        try {
            uint index = 0;
            while (true) {
                var devInfo = new SP_DEVINFO_DATA { cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINFO_DATA)) };
                if (!SetupDiEnumDeviceInfo(devInfoSet, index, ref devInfo)) {
                    if (Marshal.GetLastWin32Error() == ERROR_NO_MORE_ITEMS) break;
                    index++; continue;
                }
                index++;

                // Check if xHCI
                bool isXhci = false;
                string svc;
                if (TryGetStringProp(devInfoSet, ref devInfo, SPDRP_SERVICE, out svc) && svc.Equals("USBXHCI", StringComparison.OrdinalIgnoreCase)) isXhci = true;
                else {
                    List<string> hwIds;
                    if (TryGetMultiSzProp(devInfoSet, ref devInfo, SPDRP_HARDWAREID, out hwIds)) { foreach (var id in hwIds) if (id.IndexOf("CC_0C0330", StringComparison.OrdinalIgnoreCase) >= 0 || id.IndexOf("CLASS_0C0330", StringComparison.OrdinalIgnoreCase) >= 0) { isXhci = true; break; } }
                    else {
                        List<string> cIds;
                        if (TryGetMultiSzProp(devInfoSet, ref devInfo, SPDRP_COMPATIBLEIDS, out cIds)) { foreach (var id in cIds) if (id.IndexOf("CC_0C0330", StringComparison.OrdinalIgnoreCase) >= 0 || id.IndexOf("CLASS_0C0330", StringComparison.OrdinalIgnoreCase) >= 0) { isXhci = true; break; } }
                    }
                }
                if (!isXhci) continue;

                string instanceId;
                if (!TryGetDeviceInstanceId(devInfoSet, ref devInfo, out instanceId)) continue;
                uint problemCode = 0; uint dummyStatus = 0; CM_Get_DevNode_Status(out dummyStatus, out problemCode, devInfo.DevInst, 0);

                ulong baseAddr = 0; string baseErr = "";
                bool hasBase = TryGetMemoryBase(devInfo.DevInst, out baseAddr, out baseErr);
                controllers.Add(new XhciControllerInfo { DeviceId = instanceId, ProblemCode = problemCode, BaseAddress = baseAddr, BaseError = (hasBase ? "" : baseErr) });
            }
        } finally { SetupDiDestroyDeviceInfoList(devInfoSet); }

        result.ControllersFound = controllers.Count;
        L(string.Format("IMOD: Found {0} xHCI controllers", controllers.Count));

        if (controllers.Count == 0) { L("IMOD: No xHCI controllers found, skipping"); return result; }

        // WinIO driver handling
        var winioServiceCreated = false;
        IntPtr scm = OpenSCManager(null, null, SC_MANAGER_ALL_ACCESS);
        if (scm == IntPtr.Zero) { L(string.Format("IMOD.ERR: OpenSCManager failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result; }
        try {
            IntPtr service = OpenService(scm, WINIO_SERVICE_NAME, SERVICE_ALL_ACCESS);
            if (service == IntPtr.Zero) {
                if (Marshal.GetLastWin32Error() != ERROR_SERVICE_DOES_NOT_EXIST) {
                    L(string.Format("IMOD.ERR: OpenService failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result;
                }
                service = CreateService(scm, WINIO_SERVICE_NAME, WINIO_SERVICE_NAME, SERVICE_ALL_ACCESS, SERVICE_KERNEL_DRIVER, SERVICE_DEMAND_START, SERVICE_ERROR_NORMAL, winioSysPath, null, IntPtr.Zero, null, null, null);
                if (service == IntPtr.Zero) { L(string.Format("IMOD.ERR: CreateService failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result; }
                winioServiceCreated = true; L("IMOD: Created WINIO service");
            }
            try {
                bool wasRunning = false;
                SERVICE_STATUS_PROCESS ss = new SERVICE_STATUS_PROCESS();
                uint bytesNeeded;
                if (QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, ref ss, (uint)Marshal.SizeOf(typeof(SERVICE_STATUS_PROCESS)), out bytesNeeded)) wasRunning = ss.dwCurrentState == SERVICE_RUNNING;
                if (!wasRunning) {
                    if (!StartService(service, 0, IntPtr.Zero) && Marshal.GetLastWin32Error() != ERROR_SERVICE_ALREADY_RUNNING) {
                        L(string.Format("IMOD.ERR: StartService failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result;
                    }
                    L("IMOD: Started WINIO service");
                } else { L("IMOD: WINIO service already running"); }

                // Open driver device
                IntPtr hDevice = CreateFile(WINIO_DEVICE_PATH, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
                if (hDevice == INVALID_HANDLE_VALUE) { L(string.Format("IMOD.ERR: CreateFile(WINIO) failed: {0}", new Win32Exception(Marshal.GetLastWin32Error()).Message)); return result; }
                try {
                    foreach (var ctrl in controllers) {
                        string ctrlId = ctrl.DeviceId;
                        uint problemCode = ctrl.ProblemCode;
                        ulong baseAddr = ctrl.BaseAddress;
                        string baseErr = ctrl.BaseError;
                        if (problemCode == CM_PROB_DISABLED) { result.SkippedDisabled++; L(string.Format("IMOD.SKIP: {0} (disabled)", ctrlId)); continue; }
                        if (baseAddr == 0) { result.MissingBase++; L(string.Format("IMOD.SKIP: {0} no base addr: {1}", ctrlId, baseErr)); continue; }

                        ulong capAddr = baseAddr;
                        // HCSPARAMS (offset 4)
                        uint hcsparams;
                        if (!ReadPhys32(hDevice, capAddr + 4, out hcsparams)) { result.ReadFailures++; L(string.Format("IMOD.ERR: {0} read HCSPARAMS failed", ctrlId)); continue; }
                        // RTSOFF (offset 0x18)
                        uint rtsoff;
                        if (!ReadPhys32(hDevice, capAddr + 0x18, out rtsoff)) { result.ReadFailures++; L(string.Format("IMOD.ERR: {0} read RTSOFF failed", ctrlId)); continue; }

                        uint maxIntrs = (hcsparams >> 8) & 0xFF;
                        ulong runtimeAddr = capAddr + rtsoff;
                        L(string.Format("IMOD: {0} base=0x{1:X} maxIntrs={2} runtime=0x{3:X}", ctrlId, baseAddr, maxIntrs, runtimeAddr));

                        uint failures = 0;
                        for (uint i = 0; i < maxIntrs; i++) {
                            ulong imodAddr = runtimeAddr + 0x24 + (0x20 * i);
                            if (!WritePhys32(hDevice, imodAddr, imodInterval)) { failures++; L(string.Format("IMOD.ERR: {0} write IMOD[{1}] @ 0x{2:X} failed", ctrlId, i, imodAddr)); }
                        }
                        result.ControllersApplied++;
                        result.WriteFailures += (int)failures;
                        if (failures == 0) L(string.Format("IMOD.OK: {0} wrote {1} interrupters", ctrlId, maxIntrs));
                    }
                } finally { CloseHandle(hDevice); }
            } finally {
                // Stop service
                SERVICE_STATUS stopSs = new SERVICE_STATUS();
                ControlService(service, SERVICE_CONTROL_STOP, ref stopSs);
                for (int i = 0; i < 25; i++) {
                    SERVICE_STATUS_PROCESS check = new SERVICE_STATUS_PROCESS();
                    uint bytesNeeded2;
                    if (!QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, ref check, (uint)Marshal.SizeOf(typeof(SERVICE_STATUS_PROCESS)), out bytesNeeded2) || check.dwCurrentState == SERVICE_STOPPED) break;
                    Thread.Sleep(200);
                }
                if (winioServiceCreated) DeleteService(service);
                CloseServiceHandle(service);
            }
        } finally { CloseServiceHandle(scm); }

        L(string.Format("IMOD.DONE: applied={0} failures={1} skipped={2} missing={3}", result.ControllersApplied, result.WriteFailures, result.SkippedDisabled, result.MissingBase));
        return result;
    }

    private static bool TryGetMemoryBase(uint devInst, out ulong baseAddress, out string error) {
        baseAddress = 0; error = null;
        IntPtr logConf;
        int cr = CM_Get_First_Log_Conf(out logConf, devInst, ALLOC_LOG_CONF);
        if (cr != CR_SUCCESS) cr = CM_Get_First_Log_Conf(out logConf, devInst, BOOT_LOG_CONF);
        if (cr != CR_SUCCESS) { error = string.Format("log conf failed (0x{0:X})", cr); return false; }
        try {
            ulong minBase = 0; bool found = false;
            foreach (uint resType in new[] { RES_TYPE_MEM, RES_TYPE_MEM_LARGE }) {
                IntPtr resDes;
                int rCr = CM_Get_Next_Res_Des(out resDes, logConf, resType, IntPtr.Zero, 0);
                while (rCr == CR_SUCCESS) {
                    uint dataSize;
                    if (CM_Get_Res_Des_Data_Size(out dataSize, resDes, 0) == CR_SUCCESS && dataSize > 0) {
                        byte[] buf = new byte[dataSize];
                        if (CM_Get_Res_Des_Data(resDes, buf, dataSize, 0) == CR_SUCCESS) {
                            ulong cand = 0;
                            GCHandle gch = GCHandle.Alloc(buf, GCHandleType.Pinned);
                            try {
                                IntPtr p = gch.AddrOfPinnedObject();
                                if (resType == RES_TYPE_MEM && buf.Length >= Marshal.SizeOf(typeof(MEM_DES))) {
                                    MEM_DES mem = (MEM_DES)Marshal.PtrToStructure(p, typeof(MEM_DES));
                                    cand = mem.MD_Alloc_Base;
                                    if (cand == 0 && mem.MD_Count > 0 && buf.Length >= Marshal.SizeOf(typeof(MEM_DES)) + Marshal.SizeOf(typeof(MEM_RANGE))) {
                                        MEM_RANGE range = (MEM_RANGE)Marshal.PtrToStructure(p + Marshal.SizeOf(typeof(MEM_DES)), typeof(MEM_RANGE));
                                        cand = range.MR_Min;
                                    }
                                } else if (resType == RES_TYPE_MEM_LARGE && buf.Length >= Marshal.SizeOf(typeof(MEM_LARGE_DES))) {
                                    MEM_LARGE_DES mem = (MEM_LARGE_DES)Marshal.PtrToStructure(p, typeof(MEM_LARGE_DES));
                                    cand = mem.MLD_Alloc_Base;
                                    if (cand == 0 && mem.MLD_Count > 0 && buf.Length >= Marshal.SizeOf(typeof(MEM_LARGE_DES)) + Marshal.SizeOf(typeof(MEM_LARGE_RANGE))) {
                                        MEM_LARGE_RANGE range = (MEM_LARGE_RANGE)Marshal.PtrToStructure(p + Marshal.SizeOf(typeof(MEM_LARGE_DES)), typeof(MEM_LARGE_RANGE));
                                        cand = range.MLR_Min;
                                    }
                                }
                            } finally { gch.Free(); }
                            if (cand != 0 && (!found || cand < minBase)) { minBase = cand; found = true; }
                        }
                    }
                    IntPtr nextDes;
                    int nextCr = CM_Get_Next_Res_Des(out nextDes, resDes, resType, IntPtr.Zero, 0);
                    CM_Free_Res_Des_Handle(resDes); resDes = nextDes; rCr = nextCr;
                }
            }
            if (!found) { error = "no memory resource"; return false; }
            baseAddress = minBase; return true;
        } finally { CM_Free_Log_Conf_Handle(logConf); }
    }

    private static bool ReadPhys32(IntPtr hDevice, ulong address, out uint value) {
        value = 0;
        var phys = new PHYS_STRUCT { physMemSizeInBytes = 4, physAddress = address };
        int bytesReturned;
        if (!DeviceIoControl(hDevice, IOCTL_WINIO_MAPPHYSTOLIN, ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), out bytesReturned, IntPtr.Zero) || phys.physMemLin == 0) return false;
        try { value = unchecked((uint)Marshal.ReadInt32(new IntPtr(unchecked((long)phys.physMemLin)))); return true; }
        finally { int bytesReturned2; DeviceIoControl(hDevice, IOCTL_WINIO_UNMAPPHYSADDR, ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), out bytesReturned2, IntPtr.Zero); }
    }

    private static bool WritePhys32(IntPtr hDevice, ulong address, uint value) {
        var phys = new PHYS_STRUCT { physMemSizeInBytes = 4, physAddress = address };
        int bytesReturned3;
        if (!DeviceIoControl(hDevice, IOCTL_WINIO_MAPPHYSTOLIN, ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), out bytesReturned3, IntPtr.Zero) || phys.physMemLin == 0) return false;
        try { Marshal.WriteInt32(new IntPtr(unchecked((long)phys.physMemLin)), unchecked((int)value)); return true; }
        finally { int bytesReturned4; DeviceIoControl(hDevice, IOCTL_WINIO_UNMAPPHYSADDR, ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), ref phys, Marshal.SizeOf(typeof(PHYS_STRUCT)), out bytesReturned4, IntPtr.Zero); }
    }

    private static bool TryGetStringProp(IntPtr di, ref SP_DEVINFO_DATA dd, uint prop, out string val) {
        val = ""; List<string> vals; if (!TryGetMultiSzProp(di, ref dd, prop, out vals) || vals.Count == 0) return false; val = vals[0]; return true;
    }

    private static bool TryGetMultiSzProp(IntPtr di, ref SP_DEVINFO_DATA dd, uint prop, out List<string> vals) {
        vals = new List<string>();
        uint req = 0; uint regType = 0;
        if (!SetupDiGetDeviceRegistryPropertyW(di, ref dd, prop, out regType, null, 0, out req) && Marshal.GetLastWin32Error() != ERROR_INSUFFICIENT_BUFFER) return false;
        if (req == 0) return false;
        byte[] data = new byte[req];
        uint requiredSize;
        if (!SetupDiGetDeviceRegistryPropertyW(di, ref dd, prop, out regType, data, req, out requiredSize)) return false;
        if (regType != REG_MULTI_SZ && regType != REG_SZ) return false;
        string text = Encoding.Unicode.GetString(data);
        foreach (string part in text.Split(new char[] { '\0' }, StringSplitOptions.RemoveEmptyEntries)) { string t = part.Trim(); if (t.Length > 0) vals.Add(t); }
        return vals.Count > 0;
    }

    private static bool TryGetDeviceInstanceId(IntPtr di, ref SP_DEVINFO_DATA dd, out string id) {
        id = ""; int req = 0;
        SetupDiGetDeviceInstanceIdW(di, ref dd, null, 0, out req);
        if (Marshal.GetLastWin32Error() != ERROR_INSUFFICIENT_BUFFER || req <= 0) return false;
        StringBuilder sb = new StringBuilder(req);
        int requiredSize2;
        if (!SetupDiGetDeviceInstanceIdW(di, ref dd, sb, sb.Capacity, out requiredSize2)) return false;
        id = sb.ToString(); return !string.IsNullOrWhiteSpace(id);
    }
}
'@
            # ── Compile C# ──
            try {
                Add-Type -TypeDefinition $csharpCode -ErrorAction Stop
                _ok "IMOD C# module compiled"
            } catch {
                _err "IMOD C# compilation failed: $_"
                _err "Skipping IMOD phase."
            }

            # ── Run IMOD ──
            if ('DeviceTweakerWinIO' -as [type]) {
                # IMOD intervals:
                # 0x0   = disabled (keyboard+mouse combos get this for lowest latency)
                # 0xC8  = 200 (default moderation for other HID devices)
                # We apply 0xC8 globally; keyboard+mouse controllers get 0x0

                $globalImodInterval = 0xC8  # 200 = default moderation
                $kbmImodInterval = 0x0       # disabled for KB+M combos

                # C# ApplyImod does its own xHCI detection via SetupDi independently
                # of PowerShell $Devices (which requires Interrupt Management key absent on USB)
                $imodLogList = [System.Collections.Generic.List[string]]::new()

                # First apply global IMOD (0xC8) to ALL xHCI controllers
                $globalResult = [DeviceTweakerWinIO]::ApplyImod($winioSys, [uint32]$globalImodInterval, $imodLogList)
                foreach ($line in $globalResult.Log) { _log "IMOD: $line" }

                # Then apply disabled IMOD (0x0) to keyboard+mouse combo controllers
                $usbControllers = $Devices | Where-Object Kind -eq USB | Where-Object IsXhci
                $kbmControllers = $usbControllers | Where-Object { $_.UsbRoles -match 'Keyboard' -and $_.UsbRoles -match 'Mouse' }
                if ($kbmControllers.Count -gt 0) {
                    _log "IMOD: Found $($kbmControllers.Count) KBM combo controller(s), applying IMOD=0x0"
                    $kbmResult = [DeviceTweakerWinIO]::ApplyImod($winioSys, [uint32]$kbmImodInterval, $imodLogList)
                    foreach ($line in $kbmResult.Log) { _log "IMOD: $line" }
                } else {
                    _log "IMOD: No KBM combo controllers, using global IMOD=0xC8"
                }
            }
        }
    }
} else {
    _info "=== PHASE 7: IMOD SKIPPED (-SkipImod) ==="
}

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
else { Write-Host "IMPORTANT: Reboot required for changes to take effect." -F Yellow }
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
