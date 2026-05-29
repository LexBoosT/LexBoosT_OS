#Requires -RunAsAdministrator

param (
    [Parameter(Mandatory = $false, HelpMessage = "Configuration options to apply")]
    [ValidateSet(
        "Configure-PowerScheme",
        "Configure-Adapters",
        "Configure-Drives",
        "Configure-PowerThrottling",
        "Configure-IRQAffinity",
        "Configure-NDISOptimizer",
        "Configure-DesktopPowerOptimizations",
        "Configure-TSX",
        "Configure-BcdOptimizations",
        "Configure-IntelHybridVisibility",
        "Update-Intel-Chipset",
        "Update-AMD-Chipset"
    )]
    [string[]]$Device
)

# =============================================================================
# CONSTANTS
# =============================================================================

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$LEXBOOST_SCHEME_GUID = "0DAE0BD4-1A77-4541-AB69-71EF304FF3E4"
$LEXBOOST_DEFAULT_PATH = "$env:windir\LexBoosTOS\Utilities\Powerplans\LexBoosT Powerplans\LexBoosT_Ultimate.pow"
$HIGH_PERFORMANCE_GUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# Cache system type detection (avoid multiple WMI calls)
$script:IsLaptop = $null
$script:IsVM = $null

function Get-CachedLaptopStatus {
    if ($null -eq $script:IsLaptop) {
        $script:IsLaptop = Test-Laptop
    }
    return $script:IsLaptop
}

function Get-CachedVMStatus {
    if ($null -eq $script:IsVM) {
        $script:IsVM = Test-VM
    }
    return $script:IsVM
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Test-IsIntelHybridCPU {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $name = $cpu.Name
        if ($name -notmatch "Intel") { return $false }
        return ($name -match "i[3579]-1[2-9]\d{3}") -or
               ($name -match "Core Ultra [2-9]") -or
               ($name -match "Core Ultra [1-9]\d{2}")
    }
    catch {
        Write-Log '-' "Failed to detect CPU type: $_"
        return $false
    }
}

function Test-IsIntelCPU {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        return $cpu.Name -match "Intel"
    }
    catch {
        Write-Log '-' "Failed to detect Intel CPU: $_"
        return $false
    }
}

function Test-IsIntelTSXVulnerable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Name -notmatch "Intel") { return $false }

        if ($cpu.Name -match "i[3579]-\d{1,2}4\d{2,3}") {
            Write-Log '+' "Intel Haswell (4th gen) detected - vulnerable to TSX Async Abort."
            return $true
        }
        if ($cpu.Name -match "i[3579]-\d{1,2}5\d{2,3}") {
            Write-Log '+' "Intel Broadwell (5th gen) detected - vulnerable to TSX Async Abort."
            return $true
        }
        if ($cpu.Name -match "i[3579]-\d{1,2}6\d{2,3}") {
            Write-Log '+' "Intel Skylake (6th gen) detected - potentially vulnerable to TSX Async Abort (CVE-2019-11135)."
            return $true
        }

        return $false
    }
    catch {
        Write-Log '-' "Failed to detect TSX vulnerability: $_"
        return $true
    }
}

function Test-IsAMD3DVCache {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        if ($cpu.Name -notmatch "AMD") { return $false }
        if ($cpu.Name -match "X3D") { return $true }
        $knownX3D = @(
            '5800X3D', '7800X3D', '7900X3D', '7950X3D',
            '9800X3D', '9900X3D', '9950X3D'
        )
        foreach ($model in $knownX3D) {
            if ($cpu.Name -match $model) { return $true }
        }
        return $false
    }
    catch {
        Write-Log '-' "Failed to detect AMD 3D V-Cache: $_"
        return $false
    }
}

function Test-VM {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        $vmIndicators = @(
            $bios.SerialNumber -match "VMware|VirtualBox|QEMU|Xen|KVM|Bochs",
            $computerSystem.Manufacturer -match "VMware|VirtualBox|QEMU|Xen|Microsoft|Parallels",
            $computerSystem.Model -match "Virtual Machine|VMware|VirtualBox|QEMU|Xen"
        )

        return $vmIndicators -contains $true
    }
    catch {
        Write-Log '-' "Failed to detect VM status: $_"
        return $false
    }
}

function Test-Laptop {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $isLaptop = $false
    $laptopChassisTypes = @(8, 9, 10, 11, 12, 13, 14, 18, 21, 30, 31, 32)

    try {
        $chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes
        if ($laptopChassisTypes | Where-Object { $chassisTypes -contains $_ }) {
            $isLaptop = $true
        }
    }
    catch {
        Write-Log '-' "Failed to detect laptop status: $_"
    }

    if (-not $isLaptop) {
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem.PCSystemType -eq 2 -or $computerSystem.PCSystemTypeEx -in @(2, 8)) {
                $isLaptop = $true
            }
        }
        catch {
            Write-Log '-' "Failed to detect PC system type: $_"
        }
    }

    if (-not $isLaptop) {
        try {
            if (Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop) {
                $isLaptop = $true
            }
        }
        catch {
            Write-Log '-' "Failed to detect battery status: $_"
        }
    }

    return $isLaptop
}

function Set-RegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("DWORD", "String", "QWORD", "MultiString", "ExpandString", "Binary")]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        $Value
    )

    try {
        if (!(Test-Path -Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created registry path: $Path"
        }

        $setParams = @{
            Path  = $Path
            Name  = $Name
            Value = $Value
        }

        switch ($Type) {
            "DWORD"       { Set-ItemProperty @setParams -Type DWORD }
            "String"      { Set-ItemProperty @setParams -Type String }
            "QWORD"       { Set-ItemProperty @setParams -Type QWORD }
            "MultiString" { Set-ItemProperty @setParams -Type MultiString -Value ([string[]]$Value) }
            "ExpandString"{ Set-ItemProperty @setParams -Type ExpandString }
            "Binary"      { Set-ItemProperty @setParams -Type Binary }
            default       { Set-ItemProperty @setParams -Type $Type }
        }

        Write-Verbose "Set registry value: $Path\$Name = $Value ($Type)"
    }
    catch {
        Write-Log '-' "Failed to set registry value '$Path\$Name': $_"
    }
}

function Set-RegistrySettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Paths,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [Parameter(Mandatory = $false)]
        [ValidateSet("DWORD", "String", "QWORD", "MultiString", "ExpandString", "Binary")]
        [string]$Type = "String"
    )

    foreach ($path in $Paths) {
        foreach ($setting in $Settings.GetEnumerator()) {
            Set-RegistryValue -Path $path -Name $setting.Key -Type $Type -Value $setting.Value
        }
    }
}

function Invoke-PowerCfg {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        [int]$TimeoutSeconds = 30
    )

    $ps = $null
    $outEvent = $null
    $errEvent = $null
    try {
        Write-Verbose "Executing: powercfg $Arguments"

        $ps = New-Object System.Diagnostics.Process
        $ps.StartInfo.FileName = "powercfg.exe"
        $ps.StartInfo.Arguments = $Arguments
        $ps.StartInfo.UseShellExecute = $false
        $ps.StartInfo.CreateNoWindow = $true
        $ps.StartInfo.RedirectStandardOutput = $true
        $ps.StartInfo.RedirectStandardError = $true

        $stdout = [System.Text.StringBuilder]::new()
        $stderr = [System.Text.StringBuilder]::new()
        $outEvent = Register-ObjectEvent -InputObject $ps -EventName 'OutputDataReceived' -Action {
            $eventSubscriber | Out-Null
            if ($EventArgs.Data) {
                [void]$Event.MessageData.AppendLine($EventArgs.Data)
            }
        } -MessageData $stdout
        $errEvent = Register-ObjectEvent -InputObject $ps -EventName 'ErrorDataReceived' -Action {
            $eventSubscriber | Out-Null
            if ($EventArgs.Data) {
                [void]$Event.MessageData.AppendLine($EventArgs.Data)
            }
        } -MessageData $stderr

        $ps.Start() | Out-Null
        $ps.BeginOutputReadLine()
        $ps.BeginErrorReadLine()

        if (-not $ps.WaitForExit($TimeoutSeconds * 1000)) {
            $ps.Kill()
            Write-Log '-' "powercfg timed out after ${TimeoutSeconds}s: $Arguments"
            return $false
        }

        if ($ps.ExitCode -ne 0) {
            $errText = $stderr.ToString().Trim()
            if (-not $errText) { $errText = $stdout.ToString().Trim() }
            Write-Log '-' "powercfg failed (exit $($ps.ExitCode)): $Arguments"
            if ($errText) { Write-Log '-' "Details: $errText" }
            return $false
        }

        Write-Verbose "powercfg completed successfully"
        return $true
    }
    catch {
        Write-Log '-' "Error executing powercfg: $Arguments`n$_"
        return $false
    }
    finally {
        if ($outEvent) { Unregister-Event -SourceIdentifier $outEvent.Name -Force -ErrorAction SilentlyContinue }
        if ($errEvent) { Unregister-Event -SourceIdentifier $errEvent.Name -Force -ErrorAction SilentlyContinue }
        if ($ps) { $ps.Dispose() }
    }
}

function Set-LexBoostPowerScheme {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [string]$PowerPlanPath = $LEXBOOST_DEFAULT_PATH
    )

    Write-Log '+' "Configuring LexBoosT Ultimate power scheme..."

    try {
        if (-not (Test-Path -Path $PowerPlanPath)) {
            throw "Power plan file not found: $PowerPlanPath"
        }

        Write-Log '+' "Using power plan file: $PowerPlanPath"

        $schemeGuid = $LEXBOOST_SCHEME_GUID
        if (Test-PowerSchemeExists -SchemeGuid $schemeGuid) {
            Write-Log '+' "Existing power scheme found. Preparing for reconfiguration..."
            Remove-ExistingPowerScheme -SchemeGuid $schemeGuid
        }

        Write-Log '+' "Importing LexBoosT power scheme..."
        if (-not (Invoke-PowerCfg "/import `"$PowerPlanPath`" $schemeGuid")) {
            throw "Failed to import power scheme from $PowerPlanPath"
        }

        Start-Sleep -Seconds 2

        Write-Log '+' "Applying optimized power settings..."
		if (!(Get-CachedLaptopStatus)) {
			Set-OptimizedPowerSettings -SchemeGuid $schemeGuid
		}

        # CPU settings: visible for all devices
        Write-Log '+' "  Making CPU power settings visible in Power Options..."
        $processorSettingsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"
        if (Test-Path $processorSettingsPath) {
            Get-ChildItem $processorSettingsPath | ForEach-Object {
                Set-RegistryValue -Path $_.PSPath -Name "Attributes" -Type DWORD -Value 2
            }
        }
        Write-Log '+' "  CPU power settings visibility done."

        # CPU detection for core parking logic
        Write-Log '+' "  Detecting CPU topology..."
        $skipCoreParking = $false
        try {
            $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
            $coreCount = [int]$cpuInfo.NumberOfCores
            Write-Log '+' "  CPU: $($cpuInfo.Name) ($coreCount cores)"
            $skipCoreParking = (Test-IsAMD3DVCache) -and ($coreCount -gt 8)
            if ($skipCoreParking) { Write-Log '+' "  AMD 3D V-Cache dual-CCD detected." }
        }
        catch {
            Write-Log '-' "Failed to detect CPU topology: $_"
        }
        Write-Log '+' "  CPU detection complete."

        Write-Log '+' "  Detecting system type (desktop/laptop)..."
        $isLaptop = Get-CachedLaptopStatus
        Write-Log '+' "  System type: $(if ($isLaptop) { 'Laptop' } else { 'Desktop' })"

        if ($isLaptop) {
            Write-Host "`nLaptop settings" -F Red
            if (-not $skipCoreParking) {
                Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR CPMINCORES 60"
                Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR CPMINCORES1 80"
            }
            else {
                Write-Log '-' "AMD 3D V-Cache dual-CCD detected: skipping CPMINCORES (core parking managed by Game Bar)."
            }
            # CPU Boost Mode: Enabled AC & DC (laptop only)
            Write-Log '+' "  Enabling CPU Boost Mode AC + DC..."
            Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR PERFBOOSTMODE 2"
            Invoke-PowerCfg "/setdcvalueindex $schemeGuid SUB_PROCESSOR PERFBOOSTMODE 2"
        }
        else {
            Write-Host "`nPC settings" -F Red
            if (-not $skipCoreParking) {
                Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR CPMINCORES 100"
                Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR CPMINCORES1 100"
            }
            else {
                Write-Log '-' "AMD 3D V-Cache dual-CCD detected: skipping CPMINCORES (core parking managed by Game Bar)."
            }
            Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PCIEXPRESS ASPM 0"
            Invoke-PowerCfg "/setdcvalueindex $schemeGuid SUB_PCIEXPRESS ASPM 0"
        }

        # C-States: enabled only on AMD dual-CCD X3D (required for core parking via Game Bar)
        if ($skipCoreParking) {
            Write-Log '+' "  Enabling C-States (AMD dual-CCD X3D: required for core parking)..."
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Processor" -Name "Cstates" -Type DWORD -Value 1

            Write-Log '+' "  Making deep C-States visible in Power Options..."
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\5d76a2ca-e8c0-402f-a133-2158492d58ad" -Name "Attributes" -Type DWORD -Value 0
        }
        else {
            Write-Log '+' "  Disabling C-States (eliminates latency from state transitions)..."
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Processor" -Name "Cstates" -Type DWORD -Value 0
        }

        if ($isLaptop) {
            Write-Log '+' "Laptop detected: setting PerfBoost on other schemes and activating Balanced..."
            $schemeList = powercfg /list 2>$null | Out-String
            $regex = [regex]'([0-9a-fA-F-]{36})'
            foreach ($match in $regex.Matches($schemeList)) {
                $guid = $match.Groups[1].Value
                if ($guid -ne $schemeGuid) {
                    Invoke-PowerCfg "/setacvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 1"
                    Invoke-PowerCfg "/setdcvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 1"
                }
            }
            $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
            if (-not (Invoke-PowerCfg "/setactive $balancedGuid")) {
                throw "Failed to activate Balanced power plan"
            }
            Write-Log '+' "Balanced power plan activated with PerfBoost Mode Enabled on other schemes."
            return $true
        }

        if ($skipCoreParking) {
            Write-Log '+' "AMD dual-CCD X3D detected: activating Balanced power plan (core parking preserved)..."
            $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
            if (-not (Invoke-PowerCfg "/setactive $balancedGuid")) {
                throw "Failed to activate Balanced power plan"
            }
            Write-Log '+' "Balanced plan activated. LexBoosT Ultimate available in Power Options for manual selection."
            return $true
        }

        Write-Log '+' "  Setting PerfBoost Mode to Aggressive..."
        Invoke-PowerCfg "/setacvalueindex $schemeGuid SUB_PROCESSOR PERFBOOSTMODE 2"
        Invoke-PowerCfg "/setdcvalueindex $schemeGuid SUB_PROCESSOR PERFBOOSTMODE 2"

        Write-Log '+' "Activating LexBoosT power scheme..."
        if (-not (Invoke-PowerCfg "/setactive $schemeGuid")) {
            throw "Failed to activate power scheme"
        }

        if (Test-PowerSchemeActive -SchemeGuid $schemeGuid) {
            Write-Log '+' "LexBoosT power scheme activated successfully!"
            return $true
        }
        else {
            Write-Log '-' "Power scheme activation could not be verified"
            return $false
        }
    }
    catch {
        Write-Log '-' "Failed to configure LexBoosT power scheme: $_"
        Write-Log '+' "Please ensure the LexBoosT_Ultimate.pow file is available at the specified path."
        return $false
    }
}

function Test-PowerSchemeExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid
    )

    try {
        $output = powercfg /l 2>$null
        return $output -match $SchemeGuid
    }
    catch {
        return $false
    }
}

function Remove-ExistingPowerScheme {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid
    )

    Write-Log '+' "Switching to High Performance plan temporarily..."
    Invoke-PowerCfg "/setactive $HIGH_PERFORMANCE_GUID" | Out-Null

    Start-Sleep -Seconds 2

    Write-Log '+' "Removing existing power scheme..."
    Invoke-PowerCfg "/delete $SchemeGuid" | Out-Null
}

function Set-OptimizedPowerSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid
    )

    $powerSettings = @(
        @{
            Guid        = "0012ee47-9041-4b5d-9b77-535fba8b1442"
            SubGuid     = "fc7372b6-ab2d-43ee-8797-15e9841f2cca"
            Value       = 1
            Description = "NVMe NOPPME"
        },
        @{
            Guid        = "2a737441-1930-4402-8d77-b2bebba308a3"
            SubGuid     = "0853a681-27c8-4100-a2fd-82013e970683"
            Value       = 1
            Description = "Hub Selective Suspend Timeout"
        },
        @{
            Guid        = "2a737441-1930-4402-8d77-b2bebba308a3"
            SubGuid     = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
            Value       = 0
            Description = "USB Selective Suspend Setting"
        }
    )

    foreach ($setting in $powerSettings) {
        Write-Log '+' "  Configuring $($setting.Description)..."
        $arguments = "/setacvalueindex $SchemeGuid $($setting.Guid) $($setting.SubGuid) $($setting.Value)"
        if (-not (Invoke-PowerCfg $arguments)) {
            Write-Log '-' "Failed to set power setting: $($setting.Description)"
        }
    }
}

function Test-PowerSchemeActive {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid
    )

    try {
        $activeScheme = powercfg /getactivescheme 2>$null
        return $activeScheme -match $SchemeGuid
    }
    catch {
        return $false
    }
}

function Set-NetConfig {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring network adapters..."

    $adapterKeys = Get-NetworkAdapterKeys
    $adapterVendors = Get-NetworkAdapterVendors
    $isLaptop = Get-CachedLaptopStatus

    if ($adapterVendors -contains 'Intel') {
        Write-Log '+' "Applying Intel network optimizations..."
        Set-IntelNetworkSettings -AdapterKeys $adapterKeys -IsLaptop $isLaptop
    }

    if ($adapterVendors -contains 'Realtek') {
        Write-Log '+' "Applying Realtek network optimizations..."
        Set-RealtekNetworkSettings -AdapterKeys $adapterKeys -IsLaptop $isLaptop
    }

    Write-Log '+' "Configuring global network offload settings..."
    Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction SilentlyContinue
    Set-NetOffloadGlobalSetting -PacketCoalescingFilter Disabled -ErrorAction SilentlyContinue

    Write-Log '+' "Network configuration completed successfully."
}

function Get-NetworkAdapterKeys {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $networkClassGuid = '{4D36E972-E325-11CE-BFC1-08002bE10318}'
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$networkClassGuid"

    Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue |
    Where-Object { $_.Property -like '*SpeedDuplex*' } |
    ForEach-Object { "$basePath\$($_.PSChildName)" }
}

function Get-NetworkAdapterVendors {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    try {
        Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
        Where-Object { $_.Manufacturer } |
        ForEach-Object {
            if ($_.Manufacturer -match 'Realtek') { 'Realtek' }
            elseif ($_.Manufacturer -match 'Intel') { 'Intel' }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
    }
    catch {
        Write-Log '-' "Failed to detect network adapter vendors: $_"
        @()
    }
}

function Get-CommonNetworkPerformanceSettings {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        "*EncapsulatedPacketTaskOffloadNvgre" = "1"
        "*EncapsulatedPacketTaskOffloadVxlan" = "1"
        "*EncapsulatedPacketTaskOffload"      = "1"
        "*IPChecksumOffloadIPv4"              = "3"
        "*LsoV1IPv4"                          = "0"
        "*LsoV2IPv4"                          = "0"
        "*LsoV2IPv6"                          = "0"
        "*TCPChecksumOffloadIPv4"             = "3"
        "*TCPChecksumOffloadIPv6"             = "3"
        "*UDPChecksumOffloadIPv4"             = "3"
        "*UDPChecksumOffloadIPv6"             = "3"
        "*IPsecOffloadV1IPv4"                 = "3"
        "*IPsecOffloadV2"                     = "3"
        "*IPsecOffloadV2IPv4"                 = "3"
        "*TCPConnectionOffloadIPv4"           = "1"
        "*TCPConnectionOffloadIPv6"           = "1"
        "*TCPUDPChecksumOffloadIPv4"          = "3"
        "*TCPUDPChecksumOffloadIPv6"          = "3"
        "*UsoIPv4"                            = "1"
        "*UsoIPv6"                            = "1"
        "*RscIPv4"                            = "0"
        "*RscIPv6"                            = "0"
        "*UdpRsc"                             = "0"
        "ForceRscEnabled"                     = "0"
        "*PMARPOffload"                       = "1"
        "*PMNSOffload"                        = "1"
        "*PMWiFiRekeyOffload"                 = "1"
        "*ReceiveBuffers"                     = "1024"
        "EnableAdaptiveQueuing"               = "0"
        "StoreBadPackets"                     = "0"
        "DynamicLTR"                          = "0"
        "*TransmitBuffers"                    = "1024"
        "DropHighlyFragmentedPacket"          = "1"
        "EnableCoalesce"                      = "0"
        "*PacketDirect"                       = "1"
        "AllowFlowControlFrames"              = "0"
        "EnableTss"                           = "1"
        "*PriorityVLANTag"                    = "0"
    }
}

function Set-NetworkAdapterSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AdapterKeys,

        [Parameter(Mandatory = $true)]
        [hashtable]$PerformanceSettings,

        [Parameter(Mandatory = $false)]
        [hashtable]$PowerSettings = @{},

        [Parameter(Mandatory = $true)]
        [bool]$IsLaptop
    )

    Write-Log '+' "  Applying performance settings..."
    Set-RegistrySettings -Paths $AdapterKeys -Settings $PerformanceSettings -Type String

    if (-not $IsLaptop -and $PowerSettings.Count -gt 0) {
        Write-Log '+' "  Applying power management settings..."
        Set-RegistrySettings -Paths $AdapterKeys -Settings $PowerSettings -Type String
    }
}

function Set-IntelNetworkSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AdapterKeys,

        [Parameter(Mandatory = $true)]
        [bool]$IsLaptop
    )

    $performanceSettings = Get-CommonNetworkPerformanceSettings

    # Intel-specific performance optimizations applied regardless of laptop/desktop
    $intelPerformanceSettings = @{
        # Interrupt & Latency
        "*InterruptModeration"         = "0"   # Disabled: lowest latency (standardized NDIS)
        "ITR"                          = "0"   # Interrupt Throttling Rate: adaptive/off

        # Receive Side Scaling
        "*RSS"                         = "1"   # Enabled: distribute processing across CPU cores (standardized)
        "*NumRssQueues"                = "4"   # 4 RSS queues

        # Flow Control & DMA
        "*FlowControl"                 = "0"   # Disabled: prevents pause-frame network flooding (standardized)
        "*DMACoalescing"               = "0"   # Disabled: lower latency

        # Packet Coalescing
        "*PacketCoalescing"            = "0"   # Disabled: prevents latency from packet batching (standardized)

        # Intel-specific IPv6 offload (some Intel adapters expose this)
        "*IPChecksumOffloadIPv6"       = "3"   # Rx & Tx Enabled

        # Logging
        "LogLinkStateEvent"            = "0"   # Disable link-state event logging
    }

    foreach ($key in $intelPerformanceSettings.Keys) {
        $performanceSettings[$key] = $intelPerformanceSettings[$key]
    }

    # Power management: Wake, EEE, and power-saving — disabled on desktop for maximum stability & performance
    $powerSettings = @{
        # Wake-on-LAN: all disabled
        "*ModernStandbyWoLMagicPacket" = "0"   # Standardized: S0ix WoL
        "*WakeOnMagicPacket"           = "0"   # Standardized
        "*WakeOnPattern"               = "0"   # Standardized
        "WakeOnMagicPacketFromS5"      = "0"   # Intel: S5 WoL
        "S5WakeOnLan"                  = "0"   # Intel: S5 WoL
        "WakeOnLink"                   = "0"   # Intel: wake on link change
        "EnablePME"                    = "0"   # PCI Power Management Event
        "WolShutdownLinkSpeed"         = "2"   # 100 Mbps (moot: WoL disabled above)

        # Energy Efficient Ethernet: disabled
        "*EEE"                         = "0"   # Standardized: 802.3az
        "AdvancedEEE"                  = "0"   # Intel
        "EEELinkAdvertisement"         = "0"   # Intel
        "EnableGreenEthernet"          = "0"   # Intel/Realtek
        "GigaLite"                     = "0"   # Intel/Realtek
        "PowerSavingMode"              = "0"   # Intel/Realtek
        "ReduceSpeedOnPowerDown"       = "0"   # Intel

        # Power saving features: disabled
        "*NicAutoPowerSaver"           = "0"   # Intel
        "AutoPowerSaveModeEnabled"     = "0"   # Intel
        "EnableSavePowerNow"           = "0"   # Intel
        "*SelectiveSuspend"            = "0"   # Standardized NDIS selective suspend
        "*DeviceSleepOnDisconnect"     = "0"   # Standardized: sleep on media disconnect
        "*EnableDynamicPowerGating"    = "0"   # Intel
        "EnableConnectedStandby"       = "0"   # Intel: connected standby / modern standby
        "OBFFEnabled"                  = "0"   # Intel: Optimized Buffer Flush/Fill

        # Protocol offloads during sleep: disabled (WoL is disabled, so no benefit)
        "*PMARPOffload"                = "0"   # Standardized: ARP offload during sleep
        "*PMNSOffload"                 = "0"   # Standardized: NS offload during sleep
    }

    Set-NetworkAdapterSettings -AdapterKeys $AdapterKeys -PerformanceSettings $performanceSettings -PowerSettings $powerSettings -IsLaptop $IsLaptop
}

function Set-RealtekNetworkSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AdapterKeys,

        [Parameter(Mandatory = $true)]
        [bool]$IsLaptop
    )

    $performanceSettings = Get-CommonNetworkPerformanceSettings

    # Realtek-specific performance optimizations applied regardless of laptop/desktop
    $realtekPerformanceSettings = @{
        # Idle restriction: only allow idle power-down when user isn't present (standardized NetAdapterCx)
        "*IdleRestriction"             = "1"

        # Interrupt & Latency
        "*InterruptModeration"         = "0"   # Disabled: lowest latency (standardized NDIS)
        "ITR"                          = "0"   # Interrupt Throttling Rate: adaptive/off

        # Receive Side Scaling
        "*RSS"                         = "1"   # Enabled: distribute interrupts across cores (standardized)
        "*NumRssQueues"                = "4"   # 4 RSS queues (Realtek typically supports 2-4)

        # Flow Control & DMA
        "*FlowControl"                 = "0"   # Disabled: prevents pause-frame network flooding (standardized)
        "*DMACoalescing"               = "0"   # Disabled: lower latency

        # Packet Coalescing
        "*PacketCoalescing"            = "0"   # Disabled: prevents latency from packet batching (standardized)
    }

    foreach ($key in $realtekPerformanceSettings.Keys) {
        $performanceSettings[$key] = $realtekPerformanceSettings[$key]
    }

    # Power management & PCIe link power saving — disabled on desktop for max stability & performance
    $powerSettings = @{
        # Wake-on-LAN: all disabled
        "*WakeOnMagicPacket"           = "0"   # Standardized
        "*WakeOnPattern"               = "0"   # Standardized
        "*ModernStandbyWoLMagicPacket" = "0"   # Standardized: S0ix WoL
        "EnableWakeOnSlot"             = "0"   # Realtek: wake on PCIe slot event
        "WakeOnSlot"                   = "0"   # Realtek: wake on PCIe slot
        "WolShutdownLinkSpeed"         = "2"   # 100 Mbps (moot: WoL disabled above)

        # Energy Efficient Ethernet: disabled
        "*EEE"                         = "0"   # Standardized: 802.3az
        "AdvancedEEE"                  = "0"   # Realtek
        "EEEPlus"                      = "0"   # Realtek enhanced EEE
        "EnableGreenEthernet"          = "0"   # Realtek/Intel

        # Selective Suspend: disabled
        "*SelectiveSuspend"            = "0"   # Standardized NDIS selective suspend
        "*DeviceSleepOnDisconnect"     = "0"   # Standardized: sleep on media disconnect

        # Power saving features: disabled
        "PowerSavingMode"              = "0"   # Realtek/Intel
        "AutoPowerSaveMode"            = "0"   # Realtek
        "EnableSavePower"              = "0"   # Realtek
        "EnablePowerManagement"        = "0"   # Realtek
        "GPPSW"                        = "0"   # Green Power PHY SW
        "EPSDRT"                       = "0"   # Energy saving for low traffic
        "GigaLite"                     = "0"   # Realtek/Intel: reduce speed to 100M
        "ULPMode"                      = "0"   # Ultra Low Power Mode
        "DeepSleep"                    = "0"   # Realtek deep sleep
        "ReduceSpeedOnPowerDown"       = "0"   # Reduce link speed on power down

        # PCIe link power management: disabled for lowest latency
        "ASPM"                         = "0"   # Active State Power Management
        "EnableAspm"                   = "0"   # Alternative ASPM toggle
        "CLKREQ"                       = "0"   # Clock request / clock gating
        "EnableL1"                     = "0"   # PCIe L1 sub-state
        "EnableL0s"                    = "0"   # PCIe L0s sub-state
        "PowerDownPll"                 = "0"   # PLL power down
        "LTROBF"                       = "0"   # LTR OBFF (affects latency)
    }

    Set-NetworkAdapterSettings -AdapterKeys $AdapterKeys -PerformanceSettings $performanceSettings -PowerSettings $powerSettings -IsLaptop $IsLaptop
}

function Set-DrivesConfiguration {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring drive settings..."

    $isLaptop = Get-CachedLaptopStatus
    $systemDriveLetter = $env:SystemDrive.Substring(0, 1)

    try {
        $isSSD = $false
        $diskDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='${systemDriveLetter}:'" -ErrorAction Stop |
            ForEach-Object { $_.GetRelated('Win32_DiskPartition') } |
            ForEach-Object { $_.GetRelated('Win32_DiskDrive') } |
            Select-Object -First 1

        if ($diskDrive) {
            $model = [string]$diskDrive.Model + ' ' + [string]$diskDrive.Caption
            $isSSD = $model -match 'SSD|NVMe|M\.2|Solid State|SATA SSD|PCIe SSD'
        }

        if ($isSSD) {
            Write-Log '+' "SSD detected. Applying SSD optimizations..."
            Set-HibernationSettings -IsLaptop $isLaptop

            Write-Log '+' "Enabling TRIM support..."
            fsutil behavior set disabledeletenotify 0 | Out-Null

            Write-Log '+' "Disabling HDD-specific scheduled tasks..."
            Disable-ScheduledTask -TaskPath "\Microsoft\Windows\Data Integrity Scan\" -TaskName "Data Integrity Scan" -ErrorAction SilentlyContinue | Out-Null

            Write-Log '+' "SSD configuration completed."
        }
        else {
            Write-Log '+' "HDD detected. Skipping SSD-specific optimizations."
        }

        Write-Log '+' "Optimizing system volume..."
        Optimize-Volume -DriveLetter $systemDriveLetter -ErrorAction SilentlyContinue

        Write-Log '+' "Drive configuration completed successfully."
    }
    catch {
        Write-Log '-' "Failed to configure drive settings: $_"
    }
}

function Set-HibernationSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsLaptop
    )

    if (-not $IsLaptop) {
        Write-Log '+' "Disabling hibernation for desktop system..."
        powercfg /h off | Out-Null

        $hibernationSettings = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings'; Name = 'ShowHibernateOption'; Value = 0 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'HibernateEnabled'; Value = 0 }
        )

        foreach ($setting in $hibernationSettings) {
            Set-RegistryValue -Path $setting.Path -Name $setting.Name -Type DWORD -Value $setting.Value
        }
    }
    else {
        Write-Log '+' "Reducing hibernation file size for laptop system..."
        powercfg /h /type reduced | Out-Null
        powercfg hibernate size 0 | Out-Null
    }
}

function Disable-PowerThrottling {
    [CmdletBinding()]
    param()

    if (Get-CachedLaptopStatus) {
        Write-Log '-' "Power Throttling optimization skipped: Detected laptop system"
        return
    }

    Write-Log '+' "Configuring Power Throttling..."

    $regEntries = @(
        @{
            Path  = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
            Name  = "PowerThrottlingOff"
            Value = 1
            Type  = "DWORD"
        }
    )

    foreach ($entry in $regEntries) {
        $path = $entry.Path
        $name = $entry.Name
        $value = $entry.Value
        $type = $entry.Type

        try {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
                Write-Verbose "Created registry path: $path"
            }

            Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force
            Write-Log '+' "[+] $path\$name = $value"
            Write-Verbose "Set: $path\$name = $value ($type)"
        }
        catch {
            Write-Log '-' "Failed to set $path\$name : $_"
        }
    }

    Write-Log '+' "Power Throttling configuration completed."
}

function Set-IRQAffinity {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring IRQ Affinity..."

    if (-not (Test-IsIntelHybridCPU)) {
        Write-Log '+' "Non-hybrid CPU detected. Skipping IRQ affinity pinning."
        return
    }

    $affinityBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\*\*\Device Parameters\Interrupt Management\Affinity Policy"

    try {
        Write-Log '+' "Pinning GPU interrupts to P-Core 1 (mask 0x02)..."
        $gpus = Get-ItemProperty -Path $affinityBase -ErrorAction SilentlyContinue |
            Where-Object { $_.PSPath -match "VEN_10DE|VEN_1002|VEN_8086" }

        if ($gpus) {
            foreach ($gpu in $gpus) {
                Set-RegistryValue -Path $gpu.PSPath -Name "AssignmentSetOverride" -Type Binary -Value ([byte[]](0x02, 0x00, 0x00, 0x00))
            }
            Write-Log '+' "GPU interrupts pinned to P-Core 1."
        }
        else {
            Write-Log '+' "No GPU found for IRQ pinning."
        }

        Write-Log '+' "Pinning NVMe interrupts to E-Cores (mask 0xF0)..."
        $nvmes = Get-ItemProperty -Path $affinityBase -ErrorAction SilentlyContinue |
            Where-Object { $_.PSPath -match "CC_0108" }

        if ($nvmes) {
            foreach ($nvme in $nvmes) {
                Set-RegistryValue -Path $nvme.PSPath -Name "AssignmentSetOverride" -Type Binary -Value ([byte[]](0xF0, 0x00, 0x00, 0x00))
            }
            Write-Log '+' "NVMe interrupts pinned to E-Cores."
        }

        Write-Log '+' "Pinning network adapter interrupts to E-Cores (mask 0xF0)..."
        $nets = Get-ItemProperty -Path $affinityBase -ErrorAction SilentlyContinue |
            Where-Object { $_.PSPath -match "CC_0200|CC_0280" }

        if ($nets) {
            foreach ($net in $nets) {
                Set-RegistryValue -Path $net.PSPath -Name "AssignmentSetOverride" -Type Binary -Value ([byte[]](0xF0, 0x00, 0x00, 0x00))
            }
            Write-Log '+' "Network adapter interrupts pinned to E-Cores."
        }

        Write-Log '+' "IRQ Affinity configuration completed successfully."
    }
    catch {
        Write-Log '-' "Failed to configure IRQ Affinity: $_"
    }
}

function Set-NDISOptimizer {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring NDIS RSS Optimizer..."

    if (-not (Test-IsIntelHybridCPU)) {
        Write-Log '+' "Non-hybrid CPU detected. Skipping RSS E-Core pinning."
        return
    }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $totalPhysical = [int]$cpu.NumberOfCores
        $totalLogical  = [int]$cpu.NumberOfLogicalProcessors

        $pCores       = $totalLogical - $totalPhysical
        $baseProcessor = $pCores * 2
        $eCores       = $totalLogical - $baseProcessor

        if ($baseProcessor -lt 0 -or $eCores -le 0) {
            Write-Log '-' "Invalid CPU topology (BaseProcessor=$baseProcessor, ECoreCount=$eCores). Skipping RSS E-Core pinning."
            return
        }

        Write-Log '+' "Detected $pCores P-Cores and $eCores E-Cores. Routing RSS from Core $baseProcessor..."

        Enable-NetAdapterRss -Name "*" -ErrorAction Stop
        Set-NetAdapterRss -Name "*" -BaseProcessorGroup 0 -BaseProcessorNumber $baseProcessor -MaxProcessors $eCores -ErrorAction Stop

        Write-Log '+' "NDIS RSS pinned to E-Cores (base=$baseProcessor, count=$eCores)."
        Write-Log '+' "NDIS RSS Optimizer configuration completed successfully."
    }
    catch {
        Write-Log '-' "Failed to configure NDIS RSS: $_"
    }
}

function Set-CoreParkingDisabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CpuType
    )

    Write-Log '+' "$CpuType CPU detected - unparking CPU cores..."
    $coreParkingBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
    $eCoresGuid = '0cc5b647-c1df-4637-891a-dec35c318583'
    $pCoresGuid = 'ea062031-0e34-4ff1-9b6d-eb1059334028'
    Set-RegistryValue -Path "$coreParkingBase\$eCoresGuid" -Name "Attributes" -Type DWORD -Value 0
    Set-RegistryValue -Path "$coreParkingBase\$pCoresGuid" -Name "Attributes" -Type DWORD -Value 0
    Set-RegistryValue -Path "$coreParkingBase\$eCoresGuid" -Name "ValueMax" -Type DWORD -Value 100
    Set-RegistryValue -Path "$coreParkingBase\$pCoresGuid" -Name "ValueMax" -Type DWORD -Value 100
}

function Set-DesktopPowerOptimizations {
    [CmdletBinding()]
    param()

    if (Get-CachedLaptopStatus) {
        Write-Log '-' "Desktop Power Optimizations skipped: Detected laptop system"
        return
    }

    Write-Log '+' "Applying desktop-only power optimizations..."

    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $coreCount = [int]$cpu.NumberOfCores

    if (Test-IsIntelCPU) {
        Set-CoreParkingDisabled -CpuType "Intel"
    }
    elseif (Test-IsAMD3DVCache) {
        if ($coreCount -gt 8) {
            Write-Log '-' "AMD 3D V-Cache dual-CCD detected ($coreCount cores): core parking preserved (required for 3D V-Cache scheduling via Game Bar)."
        }
        else {
            Set-CoreParkingDisabled -CpuType "AMD 3D V-Cache single-CCD"
        }
    }
    else {
        Set-CoreParkingDisabled -CpuType "AMD"
    }

    if (Test-IsIntelCPU) {
        Write-Log '+' "Intel CPU detected - disabling heterogeneous multi-class parking..."
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HeteroMultiClassParkingEnabled' -Type DWORD -Value 0
    }

    $isAMDDualCCDX3D = (Test-IsAMD3DVCache) -and ($coreCount -gt 8)
    if (-not $isAMDDualCCDX3D) {
        Write-Log '+' "Disabling per-CPU clock tick scheduling and forced parking..."
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'EnablePerCpuClockTickScheduling' -Type DWORD -Value 0
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'ForceParkingRequested' -Type DWORD -Value 0
    }
    else {
        Write-Log '-' "AMD 3D V-Cache dual-CCD detected: preserving per-CPU scheduling and parking request (required for proper CCD coordination)."
    }

    $desktopPowerSettings = @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf'; Name = 'WdfGlobalLogsDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf'; Name = 'WdfGlobalSleepStudyDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DeepIoCoalescingEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'StandbyConnectivityGracePeriod'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'SleepstudyAccountingEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'SkipHibernateMemoryMapValidation'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'MSDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'HibernateEnabledDefault'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'IdleProcessorsRequireQosManagement'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DisableInboxPepGeneratedConstraints'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'IgnoreCsComplianceCheck'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'EnergyEstimationEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'EventProcessorEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'FxAccountingTelemetryDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'ThermalTelemetryVerbosity'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'CoalescingFlushInterval'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PowerWatchdogRequestQueueTimeoutMsec'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PowerWatchdogPoCalloutTimeoutMsec'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PowerWatchdogPowerOnGdiTimeoutMsec'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PowerWatchdogDwmSyncFlushTimeoutMsec'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PowerWatchdogDrvSetMonitorTimeoutMsec'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'PowerSettingProfile'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'WatchdogResumeTimeout'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'WatchdogSleepTimeout'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'Win32CalloutWatchdogBugcheckEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'IdleScanInterval'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'SerializeTimerExpiration'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'PowerOffFrozenProcessors'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'IdlePowerMode'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'DisableDSTThrottle'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'ContiguousMemoryFromAnyNode'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'LogSize'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'DiagnosticFlags'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\usbflags'; Name = 'DisableHCS0Idle'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\usbflags'; Name = 'Allow64KLowOrFullSpeedControlTransfers'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'NoPauseOnSuspend'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'EnableNicAutoPowerSaverInSleepStudy'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'DisableNaps'; Value = 1 }
    )

    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -ge 26100) {
        $desktopPowerSettings += @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'EnforceAusterityMode'; Value = 0 }
        )
    }

    foreach ($setting in $desktopPowerSettings) {
        Set-RegistryValue -Path $setting.Path -Name $setting.Name -Type DWORD -Value $setting.Value
    }

    Write-Log '+' "Disabling USB LPM on all USB hubs..."
    try {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\usbflags' -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName.Length -eq 12 } |
            ForEach-Object { Set-ItemProperty $_.PSPath -Name 'DisableLPM' -Value 1 -Type DWord -Force }
        Write-Log '+' "[+] USB LPM disabled on all hubs"
    }
    catch {
        Write-Log '-' "Failed to disable USB LPM: $_"
    }

    Write-Log '+' "Disabling StorPort NVMe power management..."
    try {
        $storPortKeys = reg query "HKLM\SYSTEM\CurrentControlSet\Enum" /s /f "StorPort" 2>$null |
            Select-String "StorPort" |
            ForEach-Object { $_.Line.Trim() }
        foreach ($key in $storPortKeys) {
            reg add "$key" /v "EnableIdlePowerManagement" /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$key" /v "DisableD3Cold" /t REG_DWORD /d 1 /f 2>$null | Out-Null
        }
        Write-Log '+' "[+] StorPort NVMe power management disabled"
    }
    catch {
        Write-Log '-' "Failed to disable StorPort power management: $_"
    }

    Write-Log '+' "Disabling device-level power management on all Enum devices..."
    try {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum' -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                $p = $_.PSPath
                try {
                    $props = Get-ItemProperty $p -ErrorAction Stop
                    if ($props) {
                        $props.PSObject.Properties | ForEach-Object {
                            if ($_.Name -in 'EnhancedPowerManagementEnabled','AllowIdleIrpInD3','DeviceSelectiveSuspended','DeviceResetNotificationEnabled','EnableSelectiveSuspend','SelectiveSuspendEnabled','SelectiveSuspendOn','SelectiveSuspendTimeout','WaitWakeEnabled','WakeEnabled','D3ColdSupported','DisableD3Cold','WdfDirectedPowerTransitionEnable','EnableIdlePowerManagement','IdleInWorkingState','IdleTimeoutInMS','IdleTimeoutPeriodInMilliSec','MinimumIdleTimeoutInMS','EnableHIPM','EnableHDDParking','EnableDIPM','SuppressInputInCS','SystemInputSuppressionEnabled','WdfDefaultIdleInWorkingState','WdfDirectedPowerTransitionChildrenOptional','WdfUseWdfTimerForPofx','SleepstudyState') {
                                try { Set-ItemProperty $p $_.Name 0 -Type DWord -Force -ErrorAction Stop } catch {}
                            }
                            elseif ($_.Name -in 'DisableIdlePowerManagement','DisableRuntimePowerManagement','EnhancedPowerManagementUseMonitor') {
                                try { Set-ItemProperty $p $_.Name 1 -Type DWord -Force -ErrorAction Stop } catch {}
                            }
                        }
                    }
                }
                catch {}
            }
        Write-Log '+' "[+] Device-level power management disabled across all Enum devices"
    }
    catch {
        Write-Log '-' "Failed to disable device power management: $_"
    }

    Write-Log '+' "Desktop power optimizations completed."
}

function Set-TSX {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring Intel TSX (Transactional Synchronization Extensions)..."

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel'
    $valueName = 'DisableTsx'

    if (-not (Test-IsIntelCPU)) {
        Remove-ItemProperty -Path $regPath -Name $valueName -ErrorAction SilentlyContinue
        Write-Log '+' "Non-Intel CPU detected - TSX setting removed."
        return
    }

    if (Test-IsIntelTSXVulnerable) {
        Write-Log '+' "Intel CPU vulnerable to TSX Async Abort (CVE-2019-11135) - keeping TSX DISABLED (DisableTsx = 1)..."
        Set-RegistryValue -Path $regPath -Name $valueName -Type DWORD -Value 1
        Write-Log '+' "TSX disabled (secure)."
        return
    }

    Write-Log '+' "Intel CPU with fixed TSX - enabling TSX (DisableTsx = 0)..."
    Set-RegistryValue -Path $regPath -Name $valueName -Type DWORD -Value 0
    Write-Log '+' "TSX enabled (4-5x faster database transactions, ~40% faster in specific workloads)."
}

function Set-BcdOptimizations {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring BCD boot optimizations..."

    $skipOptimizations = $false
    try {
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $coreCount = [int]$cpuInfo.NumberOfCores
        $skipOptimizations = (Test-IsAMD3DVCache) -and ($coreCount -gt 8)
    }
    catch {
        Write-Log '-' "Failed to detect CPU topology: $_"
    }

    Write-Log '+' "Cleaning up stale/misconfigured BCD entries..."
    $cleanupKeys = @(
        'numproc', 'truncatememory', 'onecpu', 'removememory',
        'configaccesspolicy', 'maxgroup', 'groupsize',
        'xsavedisable', 'bootlog', 'sos'
    )
    foreach ($key in $cleanupKeys) {
        bcdedit /deletevalue $key 2>$null | Out-Null
    }

    Write-Log '+' "Disabling 5-level paging (consumer CPU)..."
    bcdedit /deletevalue linearaddress57 2>$null | Out-Null
    bcdedit /set linearaddress57 0 2>$null | Out-Null

    Write-Log '+' "Dedicating first MB of RAM to OS..."
    bcdedit /deletevalue firstmegabytepolicy 2>$null | Out-Null
    bcdedit /set firstmegabytepolicy UseAll 2>$null | Out-Null

    try {
        $cpuName = ((Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name)
        $isAMD = $cpuName -match "AMD"
    }
    catch {
        $isAMD = $false
    }

    if (-not $skipOptimizations) {
        Write-Log '+' "Disabling dynamic tick..."
        bcdedit /set disabledynamictick yes 2>$null | Out-Null

        Write-Log '+' "Enabling x2APIC for modern interrupt routing..."
        bcdedit /deletevalue x2apicpolicy 2>$null | Out-Null
        bcdedit /set x2apicpolicy enable 2>$null | Out-Null

        if (-not $isAMD) {
            Write-Log '+' "Disabling HPET (useplatformclock) for Intel CPU..."
            bcdedit /deletevalue useplatformclock 2>$null | Out-Null
            bcdedit /set useplatformclock no 2>$null | Out-Null
            bcdedit /deletevalue useplatformtick 2>$null | Out-Null
            bcdedit /set useplatformtick no 2>$null | Out-Null
        }
        else {
            Write-Log '+' "AMD CPU detected - enabling platform tick (TSC as tick source)..."
            bcdedit /deletevalue useplatformtick 2>$null | Out-Null
            bcdedit /set useplatformtick yes 2>$null | Out-Null
            Write-Log '+' "AMD CPU detected - keeping HPET enabled (required for TSC calibration)."
        }

        Write-Log '+' "Setting TSC sync policy to enhanced..."
        bcdedit /deletevalue tscsyncpolicy 2>$null | Out-Null
        bcdedit /set tscsyncpolicy enhanced 2>$null | Out-Null
    }
    else {
        Write-Log '-' "AMD 3D V-Cache dual-CCD detected: skipping BCD timer/memory optimizations (required for proper core scheduling)."
    }
}

function Set-IntelHybridVisibility {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring Intel hybrid CPU scheduling visibility..."

    if (-not (Test-IsIntelCPU)) {
        Write-Log '+' "Non-Intel CPU detected - skipping hybrid scheduling GUID visibility."
        return
    }

    $powerBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'

    Write-Log '+' "  Making heterogeneous policy visible..."
    Set-RegistryValue -Path "$powerBase\93b8b6dc-0698-4d1c-9ee4-0644e900c85d" -Name "Attributes" -Type DWORD -Value 2

    Write-Log '+' "  Making P-core parking visible (Class 1)..."
    Set-RegistryValue -Path "$powerBase\0cc5b647-c1df-4637-891a-dec35c318584" -Name "Attributes" -Type DWORD -Value 2

    Write-Log '+' "  Making E-core parking visible (Class 0)..."
    Set-RegistryValue -Path "$powerBase\0cc5b647-c1df-4637-891a-dec35c318583" -Name "Attributes" -Type DWORD -Value 2

    Write-Log '+' "Intel hybrid scheduling GUIDs now visible in Power Options."
}

function Invoke-Main {
    [CmdletBinding()]
    param()

    Write-Log '+' "=== Windows Device Optimization Script ==="
    Write-Log '+' "Starting system optimization process..."
    Write-Log '+' ""

    if (Get-CachedVMStatus) {
        Write-Log '+' "Virtual machine detected. Skipping optimizations."
        return
    }

    if (-not (Get-CachedLaptopStatus)) {
        Write-Log '+' "Disabling device power saving for desktop system..."
        try {
            Set-CimInstance -Namespace 'root\wmi' -Query 'SELECT * FROM MSPower_DeviceEnable' -Property @{Enable = $false } -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Log '-' "Failed to disable device power saving: $_"
        }
    }

    foreach ($option in $Device) {
        Write-Log '+' "Executing: $option"
        Write-Host ("-" * 50)

        switch ($option) {
            "Configure-PowerScheme" { Set-LexBoostPowerScheme }
            "Configure-Adapters" { Set-NetConfig }
            "Configure-Drives" { Set-DrivesConfiguration }
            "Configure-PowerThrottling" { Disable-PowerThrottling }
            "Configure-IRQAffinity" { Set-IRQAffinity }
            "Configure-NDISOptimizer" { Set-NDISOptimizer }
            "Configure-DesktopPowerOptimizations" { Set-DesktopPowerOptimizations }
            "Configure-TSX" { Set-TSX }
            "Configure-BcdOptimizations" { Set-BcdOptimizations }
            "Configure-IntelHybridVisibility" { Set-IntelHybridVisibility }
            "Update-Intel-Chipset" {
                if (Test-IsIntelCPU) {
                    & "$PSScriptRoot\INTEL-CHIPSET-UPDATE.ps1"
                }
                else {
                    Write-Log '+' "Non-Intel CPU detected - skipping Intel chipset update."
                }
            }
            "Update-AMD-Chipset" {
                if (-not (Test-IsIntelCPU)) {
                    & "$PSScriptRoot\AMD-CHIPSET-UPDATE.ps1"
                }
                else {
                    Write-Log '+' "Intel CPU detected - skipping AMD chipset update."
                }
            }
        }

        Write-Log '+' ""
    }

    Write-Log '+' "System optimization process completed."
    Write-Log '+' "A reboot may be required for all changes to take effect."
    exit 0
}

# Execute main function
Invoke-Main
