#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Per-adapter low-latency NIC presets (Intel Ethernet / Realtek Ethernet / Intel WiFi / Realtek WiFi).
.DESCRIPTION
    Detects ALL physical adapters (wired AND wireless), and applies to EACH one
    the preset matching its vendor (Intel / Realtek) and type (Ethernet / WiFi).
    Values are identical to the reference presets (Intel-Ethernet.ps1,
    Realtek-Ethernet.ps1, Intel-Wifi.ps1, Realtek-Wifi.ps1).
    Also applies: global NDIS offload settings, per-interface IP settings,
    PCIe ASPM powercfg values.
    NOTE: adapter restart intentionally skipped (preserves DNS/static config).
.NOTES
    Requires administrator privileges.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$adapterClassPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}'
$backupDir = Join-Path $env:ProgramData 'LexBoosTOS\Backups'

# -----------------------------------------------------------------------------
# Presets — values identical to the reference desktop scripts
# -----------------------------------------------------------------------------
$presetIntelEthernet = @{
    '*EnableDynamicPowerGating'      = 0
    '*EncapsulatedPacketTaskOffload' = 0
    '*EncapsulatedPacketTaskOffloadNvgre' = 0
    '*EncapsulatedPacketTaskOffloadVxlan' = 0
    '*IPChecksumOffloadIPv4'         = 0
    '*IPsecOffloadV1IPv4'            = 0
    '*IPsecOffloadV2'                = 0
    '*IPsecOffloadV2IPv4'            = 0
    '*InterruptModeration'           = 0
    '*InterruptModerationRate'       = 0
    '*LsoV1IPv4'                     = 0
    '*LsoV2IPv4'                     = 0
    '*LsoV2IPv6'                     = 0
    '*MaxRssProcessors'              = 4
    '*ModernStandbyWoLMagicPacket'   = 0
    '*NicAutoPowerSaver'             = 0
    '*NumRSSQueues'                  = 1
    '*PMARPOffload'                  = 0
    '*PMWiFiRekeyOffload'            = 0
    '*PacketDirect'                  = 1
    '*PriorityVLANTag'               = 0
    '*RSSBaseProcGroup'              = 0
    '*RssBaseProcNumber'             = 2
    '*RSSMaxProcGroup'               = 0
    '*RssMaxProcNumber'              = 7
    '*ReceiveBuffers'                = 2048
    '*RscIPv6'                       = 0
    '*SelectiveSuspend'              = 0
    '*SSIdleTimeout'                 = 0
    '*TCPChecksumOffloadIPv4'        = 0
    '*TCPChecksumOffloadIPv6'        = 0
    '*TCPUDPChecksumOffloadIPv4'     = 0
    '*TCPUDPChecksumOffloadIPv6'     = 0
    '*TransmitBuffers'               = 1024
    '*UDPChecksumOffloadIPv4'        = 0
    '*UDPChecksumOffloadIPv6'        = 0
    '*UsoIPv4'                       = 0
    '*WakeOnMagicPacket'             = 0
    '*WakeOnPattern'                 = 0
    '*DeviceSleepOnDisconnect'       = 0
    '*FlowControl'                   = 0
    '*JumboPacket'                   = 1514
    '*TxIntDelay'                    = 0
    '*InterruptCoalescing'           = 0
    '*RscIpV4'                       = 0
    '*UdpRsc'                        = 0
    '*ForceRscEnabled'               = 0
    # Non-prefixed variants (same values)
    'ReceiveBuffers'                 = 2048
    'TransmitBuffers'                = 1024
    'InterruptModeration'            = 0
    'InterruptModerationRate'        = 0
    'TxIntDelay'                     = 0
    'Coalesce'                       = 0
    'RscIpV4'                        = 0
    'RscIpV6'                        = 0
    'UdpRsc'                         = 0
    'ForceRscEnabled'                = 0
    'FlowControl'                    = 0
    'PriorityVLANTag'                = 0
    'JumboPacket'                    = 1514
    'PacketDirect'                   = 1
}

$presetRealtekEthernet = @{
    'IPChecksumOffloadIPv4'          = 0
    'TCPChecksumOffloadIPv4'         = 0
    'TCPChecksumOffloadIPv6'         = 0
    'UDPChecksumOffloadIPv4'         = 0
    'UDPChecksumOffloadIPv6'         = 0
    'LsoV1IPv4'                      = 0
    'LsoV2IPv4'                      = 0
    'LsoV2IPv6'                      = 0
    'IPSecOffloadV2'                 = 0
    'IPSecOffloadV2IPv4'             = 0
    'PMARPOffload'                   = 0
    'PMNSOffload'                    = 0
    'PMWiFiRekeyOffload'             = 0
    'ReceiveBuffers'                 = 1024
    'TransmitBuffers'                = 4096
    'InterruptModeration'            = 0
    'InterruptModerationRate'        = 0
    'TxIntDelay'                     = 0
    'Coalesce'                       = 0
    'RscIpV4'                        = 0
    'RscIpV6'                        = 0
    'UdpRsc'                         = 0
    'ForceRscEnabled'                = 0
    'FlowControl'                    = 0
    'PriorityVLANTag'                = 0
    'JumboPacket'                    = 1514
    'PacketDirect'                   = 1
    'WaitAutoNegComplete'            = 0
    'DeviceSleepOnDisconnect'        = 0
    'SelectiveSuspend'               = 0
    'SSIdleTimeout'                  = 0
    'DynamicPowerGating'             = 0
    'ConnectedPowerGating'           = 0
    'AutoPowerSaveMode'              = 0
    'NicAutoPowerSaver'              = 0
    'DelayedPowerUp'                 = 0
    'ReduceSpeedOnPowerDown'         = 0
    'WakeOnMagicPacket'              = 0
    'WakeOnPattern'                  = 0
    'WakeOnLink'                     = 0
    'ModernStandbyWoLMagicPacket'    = 0
    'EEE'                            = 0
}

$presetIntelWifi = @{
    '*PowerSaveMode'                 = 0
    '*MIMOPowerSave'                 = 0
    '*WiFiAdapterPowerSave'          = 0
    '*SelectiveSuspend'              = 0
    '*SSIdleTimeout'                 = 0
    '*DeviceSleepOnDisconnect'       = 0
    '*WakeOnWireless'                = 0
    '*ModernStandbyWoLMagicPacket'   = 0
    '*InterruptModeration'           = 0
    '*InterruptModerationRate'       = 0
    '*ReceiveBuffers'                = 2048
    '*TransmitBuffers'               = 1024
    '*PacketCoalescing'              = 0
    '*IPChecksumOffloadIPv4'         = 0
    '*TCPChecksumOffloadIPv4'        = 0
    '*UDPChecksumOffloadIPv4'        = 0
    '*LsoV1IPv4'                     = 0
    '*LsoV2IPv4'                     = 0
    '*RscIPv4'                       = 0
    '*RscIPv6'                       = 0
    '*RoamingAggressiveness'         = 1
    '*ThroughputBooster'             = 1
    '*U-APSD'                        = 0
    '*FatChannelIntolerant'          = 0
    '*WaitAutoNegComplete'           = 0
    # Non-prefixed variants (same values)
    'InterruptModeration'            = 0
    'InterruptModerationRate'        = 0
    'RoamingAggressiveness'          = 1
    'ThroughputBooster'              = 1
    'U-APSD'                         = 0
}

$presetRealtekWifi = @{
    '*PowerSaveMode'                 = 0
    '*WakeOnWLAN'                    = 0
    '*RoamingAggressiveness'         = 0
    '*U-APSD'                        = 0
    '*WMM'                           = 1
    '*MIMOPowerSave'                 = 0
    '*IPChecksumOffload'             = 0
    '*TCPChecksumOffload'            = 0
    '*UDPChecksumOffload'            = 0
    '*LsoV1IPv4'                     = 0
    '*LsoV2IPv4'                     = 0
    '*ReceiveBuffers'                = 1024
    '*TransmitBuffers'               = 4096
    '*InterruptModeration'           = 0
    '*InterruptModerationRate'       = 0
}

# RSS profile per vendor (same as reference scripts)
$rssIntel = @{ Profile = 'ClosestProcessorStatic'; Base = 2; Max = 7; Processors = 4; Queues = 1 }
$rssRealtek = @{ Profile = 'NUMAScaling'; Queues = 2 }

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Get-NicClassKey {
    param([string]$InterfaceGuid)
    foreach ($key in (Get-ChildItem $adapterClassPath | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
        $netCfgInstanceId = (Get-ItemProperty -Path $key.PSPath -Name 'NetCfgInstanceId' -ErrorAction SilentlyContinue).NetCfgInstanceId
        if ($netCfgInstanceId -eq $InterfaceGuid) { return $key.PSPath }
    }
    return $null
}

function Get-NicPreset {
    param($Adapter)
    $isWifi = ($Adapter.Name -match 'WiFi|Wireless|WLAN|802.11') -or ($Adapter.InterfaceDescription -match 'WiFi|Wireless|WLAN|802.11')
    # Manufacturer is often empty on Get-NetAdapter — fall back to the interface
    # description and the PCI vendor ID (Intel VEN_8086 / Realtek VEN_10EC).
    $isIntel = ($Adapter.Manufacturer -match 'Intel') -or ($Adapter.InterfaceDescription -match 'Intel') -or ($Adapter.PnpDeviceID -match 'VEN_8086')
    $isRealtek = ($Adapter.Manufacturer -match 'Realtek') -or ($Adapter.InterfaceDescription -match 'Realtek') -or ($Adapter.PnpDeviceID -match 'VEN_10EC')
    if ($isWifi) {
        if ($isIntel)  { return @{ Name = 'Intel WiFi';    Settings = $presetIntelWifi;    Rss = $rssIntel } }
        if ($isRealtek) { return @{ Name = 'Realtek WiFi';  Settings = $presetRealtekWifi;  Rss = $rssRealtek } }
    } else {
        if ($isIntel)  { return @{ Name = 'Intel Ethernet';    Settings = $presetIntelEthernet;    Rss = $rssIntel } }
        if ($isRealtek) { return @{ Name = 'Realtek Ethernet';  Settings = $presetRealtekEthernet;  Rss = $rssRealtek } }
    }
    return $null
}

# -----------------------------------------------------------------------------
# 1. Per-adapter advanced settings + RSS (ALL adapters, wired + wireless)
# -----------------------------------------------------------------------------
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
if (-not $adapters) {
    Write-Log '-' 'No active physical adapter found'
    exit 0
}

foreach ($adapter in $adapters) {
    $preset = Get-NicPreset -Adapter $adapter
    if (-not $preset) {
        Write-Log '-' "Adapter $($adapter.Name): vendor not Intel/Realtek, skipped ($($adapter.Manufacturer))"
        continue
    }
    Write-Log '+' "Adapter: $($adapter.Name) -> $($preset.Name)"

    $interfaceGuid = $adapter.InterfaceGuid
    $targetKey = Get-NicClassKey -InterfaceGuid $interfaceGuid
    if (-not $targetKey) {
        Write-Log '-' "  Registry key not found for $($adapter.Name), skipped"
        continue
    }

    # Backup of current advanced settings
    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
    # $targetKey is a provider-qualified PSPath (Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\...)
    # — strip the provider prefix so reg.exe gets a plain HKEY_LOCAL_MACHINE\... key name.
    $regPath = $targetKey -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $backupFile = Join-Path $backupDir "NIC_$($adapter.Name.Replace(' ','_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    reg.exe export $regPath $backupFile /y *>$null

    # Apply advanced parameters
    foreach ($param in $preset.Settings.Keys) {
        try {
            Set-ItemProperty -Path $targetKey -Name $param -Value $preset.Settings[$param] -Type DWord -ErrorAction Stop
            Write-Log '+' "  $param = $($preset.Settings[$param])"
        } catch {
            Write-Log '-' "  $param = $($preset.Settings[$param]) (not supported, ignored)"
        }
    }

    # RSS configuration
    try {
        $rssArgs = @{
            Name                  = $adapter.Name
            Enabled               = $true
            Profile               = $preset.Rss.Profile
            NumberOfReceiveQueues = $preset.Rss.Queues
            ErrorAction           = 'Stop'
        }
        if ($preset.Rss.ContainsKey('Base'))    { $rssArgs.BaseProcessorNumber    = $preset.Rss.Base }
        if ($preset.Rss.ContainsKey('Max'))     { $rssArgs.MaxProcessorNumber     = $preset.Rss.Max }
        if ($preset.Rss.ContainsKey('Processors')) { $rssArgs.MaxProcessors       = $preset.Rss.Processors }
        Set-NetAdapterRss @rssArgs
        Write-Log '+' "  RSS: $($preset.Rss.Profile), queues=$($preset.Rss.Queues)"
    } catch {
        Write-Log '-' '  RSS: not supported by this adapter (ignored)'
    }
}

# -----------------------------------------------------------------------------
# 2. Global NDIS / Offload settings
# -----------------------------------------------------------------------------
Write-Log '+' 'Applying global NDIS offload settings...'
Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -PacketCoalescingFilter Disabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -Chimney Disabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -TaskOffload Enabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -NetworkDirect Enabled -ErrorAction SilentlyContinue
Set-NetOffloadGlobalSetting -NetworkDirectAcrossIPSubnets Blocked -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# 3. Per-interface IP settings (all detected adapters)
# -----------------------------------------------------------------------------
Write-Log '+' 'Applying per-interface IP settings...'
foreach ($adapter in $adapters) {
    $idx = $adapter.InterfaceIndex
    Set-NetIPInterface -InterfaceIndex $idx -RouterDiscovery ControlledByDHCP -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -AutomaticMetric Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -ClampMss Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -EcnMarking Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -Forwarding Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -WeakHostReceive Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -WeakHostSend Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $idx -NlMtu 1500 -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------------
# 4. PCIe ASPM powercfg (AC + DC, current scheme)
# -----------------------------------------------------------------------------
Write-Log '+' 'Disabling PCIe ASPM power saving (AC+DC)...'
# Real subgroup: PCI Express = 501a4d13-42af-4429-9fd1-a8218c268e20 (alias
# SUB_PCIEXPRESS), ASPM setting = ee12f906-d277-404b-b6da-e5fa1a576df5 (alias
# ASPM). The GUIDs from the reference presets (4f971e89 / 5e06ab08 / 5c3a0811)
# do not exist on current builds — 4f971e89 is the power-buttons subgroup, the
# other two are unknown settings, so powercfg fails with "setting not found".
# Guard keeps the section working on any build (L0s/L1 only where exposed).
$pcieQuery = powercfg /query SCHEME_CURRENT SUB_PCIEXPRESS 2>$null | Out-String
if ($pcieQuery -match 'ee12f906-d277-404b-b6da-e5fa1a576df5') {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ee12f906-d277-404b-b6da-e5fa1a576df5 0
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ee12f906-d277-404b-b6da-e5fa1a576df5 0
    Write-Log '+' '  PCIe ASPM disabled (AC+DC)'
} else {
    Write-Log '-' '  PCIe ASPM setting not present in active scheme, skipped'
}
if ($pcieQuery -match '5c3a0811-1ece-4cf6-b131-a8ea20779e1a') {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS 5c3a0811-1ece-4cf6-b131-a8ea20779e1a 0
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS 5c3a0811-1ece-4cf6-b131-a8ea20779e1a 0
    Write-Log '+' '  PCIe L0s/L1 disabled (AC+DC)'
} else {
    Write-Log '-' '  PCIe L0s/L1 setting not present in active scheme, skipped'
}

Write-Log '+' 'NIC presets applied. A full reboot is recommended.'
exit 0
