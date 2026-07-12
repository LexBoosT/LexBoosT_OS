#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Combined advanced network tuning for low latency.
.DESCRIPTION
    Merges NETSH-EXTRAS and NETWORK-EXTRAS2:
    - RSS affinity/queues and per-adapter low-latency NIC settings
    - NetBIOS/LMHOSTS disable
    - Gaming QoS policy
    - SMB 1.0 disable
    - LanmanServer optimization
    - Automatic Scheduled Maintenance disable
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# -----------------------------------------------------------------------------
# 0. netsh stack reset (migrated from network.yml)
# -----------------------------------------------------------------------------
Write-Log '+' 'Resetting TCP/IP stack (netsh)...'
netsh int ip reset          | Out-Null
netsh interface ipv4 reset  | Out-Null
netsh interface ipv6 reset  | Out-Null
netsh interface tcp reset   | Out-Null
netsh winsock reset         | Out-Null
netsh int tcp set security profiles=disabled | Out-Null
netsh int udp set global uro=enabled         | Out-Null
netsh int tcp set global timestamps=disabled| Out-Null

# -----------------------------------------------------------------------------
# 0b. Disable unused bindings + re-enumerate network devices
# -----------------------------------------------------------------------------
try {
    Disable-NetAdapterBinding -Name '*' -ComponentID 'vmware_bridge','ms_lldp','ms_lltdio','ms_implat','ms_rspndr','ms_server','ms_msclient' -ErrorAction SilentlyContinue
} catch {}
try {
    foreach ($dev in Get-PnpDevice -Class Net -Status 'OK') {
        pnputil /remove-device $dev.InstanceId 2>&1 | Out-Null
    }
    pnputil /scan-devices | Out-Null
} catch {}

# -----------------------------------------------------------------------------
# 0c. Disable NetBT/NetBIOS/LMHOSTS via reg.exe (migrated from network.yml)
# -----------------------------------------------------------------------------
Write-Log '+' 'Disabling NetBT / NetBIOS / LMHOSTS...'
$netbtPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT'
$netbtParams = "$netbtPath\Parameters"
foreach ($p in $netbtPath, $netbtParams) {
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
}
Set-ItemProperty -Path $netbtPath      -Name 'Start'         -Value 4 -Type DWord -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBIOS' -Name 'Start' -Value 4 -Type DWord -Force
Set-ItemProperty -Path $netbtParams    -Name 'EnableLMHOSTS' -Value 0 -Type DWord -Force
Get-ChildItem "$netbtParams\Interfaces" -ErrorAction SilentlyContinue | ForEach-Object {
    try { Set-ItemProperty -Path $_.PSPath -Name 'NetbiosOptions' -Value 2 -Type DWord -Force -ErrorAction Stop } catch {}
}

# -----------------------------------------------------------------------------
# 1. RSS global base processor
# -----------------------------------------------------------------------------
Write-Log '+' 'Configuring RSS base processor...'
try {
    $logicalCores = [Environment]::ProcessorCount
    $baseProc = [Math]::Min(2, $logicalCores - 1)
    if ($baseProc -lt 1) { $baseProc = 1 }
    netsh int tcp set global rssbaseproc=$baseProc | Out-Null
    Write-Log '+' "RSS base processor set to $baseProc"
} catch {
    Write-Log '-' "Failed to set RSS base processor: $_"
}

# -----------------------------------------------------------------------------
# 2. Per-adapter RSS + low-latency NIC settings
# -----------------------------------------------------------------------------
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|802\.11|Bluetooth|Virtual|Loopback|Hyper-V|VMware' }

foreach ($nic in $adapters) {
    $name = $nic.Name
    Write-Log '+' "Tuning adapter: $name"

    try {
        $rssInfo = Get-NetAdapterRss -Name $name -ErrorAction Stop
        if ($rssInfo.Enabled) {
            $logicalCores = [Environment]::ProcessorCount
            $base = [Math]::Min(2, $logicalCores - 1)
            $maxProc = [Math]::Min($base + 3, $logicalCores - 1)
            $queues = [Math]::Min(4, $logicalCores)

            Set-NetAdapterRss -Name $name `
                -BaseProcessorNumber $base `
                -MaxProcessorNumber $maxProc `
                -NumberOfReceiveQueues $queues `
                -Profile NUMAStatic `
                -ErrorAction Stop
            Write-Log '+' "  RSS -> base=$base max=$maxProc queues=$queues"
        } else {
            Write-Log '-' "  RSS not enabled on this adapter"
        }
    } catch {
        Write-Log '-' "  RSS config failed: $_"
    }

    $advancedProps = @(
        @{ Keyword='*InterruptModeration';     Value=0;    Name='Interrupt Moderation' },
        @{ Keyword='*FlowControl';             Value=0;    Name='Flow Control' },
        @{ Keyword='*EEE';                     Value=0;    Name='Energy-Efficient Ethernet' },
        @{ Keyword='EnableGreenEthernet';      Value=0;    Name='Green Ethernet' },
        @{ Keyword='PowerSavingMode';          Value=0;    Name='Power Saving Mode' },
        @{ Keyword='UseInterruptSteering';     Value=0;    Name='Interrupt Steering' },
        @{ Keyword='*JumboPacket';             Value=1514; Name='Jumbo Packet' }
    )

    foreach ($prop in $advancedProps) {
        try {
            $current = Get-NetAdapterAdvancedProperty -Name $name -RegistryKeyword $prop.Keyword -ErrorAction Stop
            if ($current) {
                Set-NetAdapterAdvancedProperty -Name $name -RegistryKeyword $prop.Keyword -RegistryValue $prop.Value -ErrorAction Stop
                Write-Log '+' "  $($prop.Name) set to $($prop.Value)"
            }
        } catch {
            # property not supported by adapter, ignore
        }
    }
}

# -----------------------------------------------------------------------------
# 3. Per-adapter NetBIOS and LMHOSTS disable
# -----------------------------------------------------------------------------
Write-Log '+' 'Disabling NetBIOS over TCP/IP and LMHOSTS lookup per adapter...'
$interfaces = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" -ErrorAction SilentlyContinue
foreach ($nic in $interfaces) {
    try {
        $nic.SetTcpipNetbios(2) | Out-Null
        $guid = $nic.SettingID
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$guid"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "NetbiosOptions" -Value 2 -Type DWord -Force
            Set-ItemProperty -Path $regPath -Name "EnableLMHosts" -Value 0 -Type DWord -Force
        }
    } catch {
        Write-Log '-' "Failed to disable NetBIOS/LMHOSTS on adapter: $_"
    }
}

# -----------------------------------------------------------------------------
# 4. Global NetBIOS / LMHOSTS fallback
# -----------------------------------------------------------------------------
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" -Name "EnableLMHosts" -Value 0 -Type DWord -Force
    Write-Log '+' 'Global LMHOSTS lookup disabled'
} catch {
    Write-Log '-' 'Failed to disable global LMHOSTS'
}

# -----------------------------------------------------------------------------
# 5. Network QoS: reserve bandwidth for gaming traffic if supported
# -----------------------------------------------------------------------------
try {
    if (-not (Get-NetQosPolicy -Name 'Gaming' -ErrorAction SilentlyContinue)) {
        New-NetQosPolicy -Name 'Gaming' -AppPathNameMatchCondition 'game*.exe' -IPProtocol UDP -ThrottleRateActionBitsPerSecond 0 -ErrorAction SilentlyContinue | Out-Null
        Write-Log '+' 'Gaming QoS policy created'
    }
} catch {
    Write-Log '-' 'QoS policy creation skipped'
}

# -----------------------------------------------------------------------------
# 6. Disable SMB 1.0 protocol
# -----------------------------------------------------------------------------
Write-Log '+' 'Disabling SMB 1.0 protocol...'
try {
    # Server-side disable (works immediately, no reboot)
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
    Write-Log '+' 'SMB 1.0 server disabled'
} catch {
    Write-Log '-' "Could not disable SMB 1.0 server: $_"
}

try {
    # Client-side disable via registry
    $smbClientPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    if (-not (Test-Path $smbClientPath)) { New-Item -Path $smbClientPath -Force | Out-Null }
    Set-ItemProperty -Path $smbClientPath -Name 'DisableSMB1_Protocol' -Value 1 -Type DWord -Force
    Write-Log '+' 'SMB 1.0 client disabled'
} catch {
    Write-Log '-' "Could not disable SMB 1.0 client: $_"
}

# -----------------------------------------------------------------------------
# 7. Optimize LanmanServer for low-latency file sharing
# -----------------------------------------------------------------------------
Write-Log '+' 'Optimizing LanmanServer parameters...'
try {
    $srvParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    if (-not (Test-Path $srvParams)) { New-Item -Path $srvParams -Force | Out-Null }

    # Size=3 optimizes server for file sharing throughput/latency
    Set-ItemProperty -Path $srvParams -Name 'Size' -Value 3 -Type DWord -Force

    # Disable strict name checking for faster name resolution
    Set-ItemProperty -Path $srvParams -Name 'DisableStrictNameChecking' -Value 1 -Type DWord -Force

    Write-Log '+' 'LanmanServer optimized'
} catch {
    Write-Log '-' "Could not optimize LanmanServer: $_"
}

# -----------------------------------------------------------------------------
# 8. Disable Automatic Scheduled Maintenance
# -----------------------------------------------------------------------------
Write-Log '+' 'Disabling Automatic Scheduled Maintenance...'
try {
    $maintPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance'
    if (-not (Test-Path $maintPath)) { New-Item -Path $maintPath -Force | Out-Null }
    Set-ItemProperty -Path $maintPath -Name 'MaintenanceDisabled' -Value 1 -Type DWord -Force
    Write-Log '+' 'Automatic Scheduled Maintenance disabled'
} catch {
    Write-Log '-' "Could not disable Scheduled Maintenance: $_"
}

Write-Log '+' 'Network extras applied.'
exit 0

