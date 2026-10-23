#Requires -RunAsAdministrator

param (
    [Parameter(Mandatory = $false, HelpMessage = "Configuration options to apply")]
    [string[]]$Device
)

# Valid device actions (custom validation because AME passes array syntax literally in args)
$script:ValidDevices = @(
    "Configure-PowerScheme",
    "Configure-Adapters",
    "Configure-Drives",
    "Configure-PowerThrottling",
    "Configure-NDISOptimizer",
    "Configure-DesktopPowerOptimizations",
    "Configure-TSX",
    "Configure-BcdOptimizations",
    "Configure-IntelHybridVisibility",
    "Configure-RegistryPowerTweaks",
    "Configure-Ntfs",
    "Configure-MobileSync"
)

# Normalize Device input: AME passes array syntax as a literal string, so strip surrounding @( ... )
if ($Device -and ($Device.Count -eq 1) -and ($Device[0] -match '^@\((.+)\)$')) {
    $Device = $matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
}

foreach ($d in $Device) {
    if ($script:ValidDevices -notcontains $d) {
        throw "Invalid device action: '$d'. Valid actions: $($script:ValidDevices -join '; ')"
    }
}

# =============================================================================
# CONSTANTS
# =============================================================================

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

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

function Test-IsAMDCPU {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        return $cpu.Name -match "AMD"
    }
    catch {
        Write-Log '-' "Failed to detect AMD CPU: $_"
        return $false
    }
}

function Set-SleepSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid,
        [Parameter(Mandatory = $true)]
        [bool]$IsLaptop
    )

    if ($IsLaptop) {
        Write-Log '+' "  Applying laptop sleep settings (lid=sleep, idle=10min, button=sleep)..."
        Invoke-PowerCfg "/setacvalueindex $SchemeGuid SUB_BUTTONS LIDACTION 1" | Out-Null
        Invoke-PowerCfg "/setdcvalueindex $SchemeGuid SUB_BUTTONS LIDACTION 1" | Out-Null
        Invoke-PowerCfg "/setacvalueindex $SchemeGuid SUB_SLEEP STANDBYIDLE 600000" | Out-Null
        Invoke-PowerCfg "/setdcvalueindex $SchemeGuid SUB_SLEEP STANDBYIDLE 600000" | Out-Null
        Invoke-PowerCfg "/setacvalueindex $SchemeGuid SUB_BUTTONS SLEEPBUTTON 1" | Out-Null
        Invoke-PowerCfg "/setdcvalueindex $SchemeGuid SUB_BUTTONS SLEEPBUTTON 1" | Out-Null
    } else {
        Write-Log '+' "  Applying desktop sleep settings (idle=never)..."
        Invoke-PowerCfg "/setacvalueindex $SchemeGuid SUB_SLEEP STANDBYIDLE 0" | Out-Null
        Invoke-PowerCfg "/setdcvalueindex $SchemeGuid SUB_SLEEP STANDBYIDLE 0" | Out-Null
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

        # Flush async output events: after WaitForExit returns, the OutputDataReceived /
        # ErrorDataReceived events may still be queued. A second WaitForExit() (no timeout)
        # blocks until the handlers have drained, so $stdout / $stderr below are complete.
        # Without this, a fast-exiting powercfg can leave the buffers empty and the real
        # error message is lost in the log.
        $ps.WaitForExit() | Out-Null

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
    param()

    # Detect CPU and select the appropriate settings table
    $isAMD = Test-IsAMDCPU
    if ($isAMD) {
        Write-Log '+' "AMD CPU detected - applying AMD Hybrid FPS+Latency settings"
        $settings = @(
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="0b2d69d7-a2a1-449c-9680-f91c70521c60"; AC=0; DC=1 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="6738e2c4-e8a5-4a42-b16a-e040e769756e"; AC=0; DC=0 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="80e3c60e-bb94-4ad8-bbe0-0d3195efc663"; AC=0; DC=30 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="d3d55efd-c1ff-424e-9dc3-441be7833010"; AC=4000; DC=2000 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="d639518a-e56d-4345-8af2-b9f32fb26109"; AC=500; DC=2000 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="dab60367-53fe-4fbc-825e-521d069d2456"; AC=0; DC=0 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="dbc9e238-6de9-49e3-92cd-8c2b4946b472"; AC=1; DC=0 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="fc7372b6-ab2d-43ee-8797-15e9841f2cca"; AC=1; DC=$null },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="fc95af4d-40e7-4b6d-835a-56d131dbc80e"; AC=1; DC=0 },
                @{ Sub="0d7dbae2-4294-402a-ba8e-26777e8488cd"; Set="309dce9b-bef4-4119-9921-a851fb12f0f4"; AC=1; DC=1 },
                @{ Sub="19cbb8fa-5279-450e-9fac-8a3d5fedd0c1"; Set="12bbebe6-58d6-4636-95bb-3217ef867c1a"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="25dfa149-5dd1-4736-b5ab-e8a37b5b8187"; AC=1; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="29f6c1db-86da-48c5-9fdb-f2b67b1f44da"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="7bc4a2f9-d8fc-4469-b07b-33eb785aaca0"; AC=120; DC=$null },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="94ac6d29-73ce-41a6-809f-6363ba21b47e"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="9d7815a6-7ee4-497e-8888-515a05f02364"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="abfc2519-3608-4c2a-94ea-171b0ed546ab"; AC=1; DC=1 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="d4c1d4c8-d5cc-43d3-b83e-fc51215cb04d"; AC=0; DC=0 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="0853a681-27c8-4100-a2fd-82013e970683"; AC=50; DC=50 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; AC=0; DC=0 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="498c044a-201b-4631-a522-5c744ed4e678"; AC=1; DC=0 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="d4e98f31-5ffe-4ce1-be31-1b38b384c009"; AC=0; DC=2 },
                @{ Sub="2e601130-5351-4d9d-8e04-252966bad054"; Set="c36f0eb4-2988-4a70-8eee-0884fc2c2433"; AC=0; DC=0 },
                @{ Sub="2e601130-5351-4d9d-8e04-252966bad054"; Set="d502f7ee-1dc7-4efd-a55d-f04b6f5c0545"; AC=0; DC=0 },
                @{ Sub="48672f38-7a9a-4bb2-8bf8-3d85be19de4e"; Set="2bfc24f9-5ea2-4801-8213-3dbae01aa39d"; AC=6; DC=0 },
                @{ Sub="48672f38-7a9a-4bb2-8bf8-3d85be19de4e"; Set="73cde64d-d720-4bb2-a860-c755afe77ef2"; AC=1; DC=50 },
                @{ Sub="4f971e89-eebd-4455-a8de-9e59040e7347"; Set="7648efa3-dd9c-4e3e-b566-50f929386280"; AC=3; DC=3 },
                @{ Sub="4f971e89-eebd-4455-a8de-9e59040e7347"; Set="a7066653-8d6c-40a8-910e-a1f54b84c7e5"; AC=2; DC=$null },
                @{ Sub="501a4d13-42af-4429-9fd1-a8218c268e20"; Set="ee12f906-d277-404b-b6da-e5fa1a576df5"; AC=0; DC=2 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="06cadf0e-64ed-448a-8927-ce7bf90eb35d"; AC=30; DC=90 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="0cc5b647-c1df-4637-891a-dec35c318583"; AC=100; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="12a0ab44-fe28-4fa9-b3bd-4b64f44960a6"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="2ddd5a84-5a71-437e-912a-db0b8c788732"; AC=7; DC=3 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="36687f9e-e3a5-4dbf-b1dc-15eb381c6864"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="40fbefc7-2e9d-4d25-a185-0cfd8574bac6"; AC=1; DC=1 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="45bcc044-d885-43e2-8605-ee0ec6e96b59"; AC=100; DC=100 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="465e1f50-b610-473a-ab58-00d1077dc418"; AC=2; DC=2 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="4b92d758-5a24-4851-a470-815d78aee119"; AC=98; DC=100 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="4d2b0152-7d5c-498b-88e2-34345392a2c5"; AC=5000; DC=15 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="5d76a2ca-e8c0-402f-a133-2158492d58ad"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="619b7505-003b-4e82-b7a6-4dd29c300971"; AC=99; DC=99 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="6c2993b0-8f48-481f-bcc6-00dd2742aa06"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7b224883-b3cc-4d79-819f-8374152cbe7c"; AC=98; DC=100 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="893dee8e-2bef-41e0-89c6-b55d0929964c"; AC=100; DC=50 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="893dee8e-2bef-41e0-89c6-b55d0929964d"; AC=100; DC=5 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="8baa4a8a-14c6-4451-8e8b-14bdbd197537"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="93b8b6dc-0698-4d1c-9ee4-0644e900c85d"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="943c8cb6-6f93-4227-ad87-e9a3feec08d1"; AC=60; DC=60 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="94d3a615-a899-4ac5-ae2b-e4d8f634367f"; AC=1; DC=1 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="bae08b81-2d5e-4688-ad6a-13243356654b"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="bc5038f7-23e0-4960-96da-33abaf5935ec"; AC=100; DC=100 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="be337238-0d82-4146-a960-4f3749d470c7"; AC=5; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="c4581c31-89ab-4597-8e2b-9c9cab440e6b"; AC=20000; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="cfeda3d0-7697-4566-a922-a9086cd49dfa"; AC=20000; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="dfd10d17-d5eb-45dd-877a-9a34ddd15c82"; AC=20; DC=20 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="ea062031-0e34-4ff1-9b6d-eb1059334028"; AC=100; DC=100 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="17aaa29b-8b43-4b94-aafe-35f64daaf1ee"; AC=0; DC=0 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"; AC=0; DC=0 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="684c3e69-a4f7-4014-8754-d45179a56167"; AC=1; DC=1 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="8ec4b3a5-6868-48c2-be75-4f3044be88a7"; AC=0; DC=0 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="aded5e82-b909-4619-9949-f5d71dac0bcb"; AC=$null; DC=100 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="0a7d6ab6-ac83-4ad1-8282-eca5b58308f3"; AC=30; DC=30 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="49cb11a5-56e2-4afb-9d38-3df47872e21b"; AC=0; DC=0 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="5adbbfbc-074e-4da1-ba38-db8b36b2c8f3"; AC=240; DC=$null },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="60c07fe1-0556-45cf-9903-d56e32210242"; AC=0; DC=0 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="82011705-fb95-4d46-8d35-4042b1d20def"; AC=0; DC=1 },
                @{ Sub="9596fb26-9850-41fd-ac3e-f7c3c00afd4b"; Set="10778347-1370-4ee0-8bbd-33bdacaade49"; AC=1; DC=0 },
                @{ Sub="9596fb26-9850-41fd-ac3e-f7c3c00afd4b"; Set="34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4"; AC=0; DC=0 },
                @{ Sub="c763b4ec-0e50-4b6b-9bed-2b92a6ee884e"; Set="7ec1751b-60ed-4588-afb5-9819d3d77d90"; AC=3; DC=3 },
                @{ Sub="de830923-a562-41af-a086-e3a2c6bad2da"; Set="13d09884-f74e-474a-a852-b6bde8ad03a8"; AC=100; DC=50 },
                @{ Sub="de830923-a562-41af-a086-e3a2c6bad2da"; Set="5c5bb349-ad29-4ee2-9d0b-2b25270f7a81"; AC=0; DC=0 },
                @{ Sub="e276e160-7cb0-43c6-b20b-73f5dce39954"; Set="a1662ab2-9d34-4e53-ba8b-2639b9e20857"; AC=3; DC=3 },
                @{ Sub="e73a048d-bf27-4f12-9731-8b2076e8891f"; Set="637ea02f-bbcb-4015-8e2c-a1c7b9c0b546"; AC=0; DC=0 },
                @{ Sub="e73a048d-bf27-4f12-9731-8b2076e8891f"; Set="8183ba9a-e910-48da-8769-14ae6dc1170a"; AC=15; DC=$null },
                @{ Sub="e73a048d-bf27-4f12-9731-8b2076e8891f"; Set="f3c5027d-cd16-4930-aa6b-90db844a8f00"; AC=10; DC=$null },
                @{ Sub="f693fb01-e858-4f00-b20f-f30e12ac06d6"; Set="191f65b5-d45c-4a4f-8aae-1ab8bfd980e6"; AC=1; DC=0 }
        )
    } else {
        Write-Log '+' "Intel CPU detected - applying Intel Hybrid FPS+Latency settings"
        $settings = @(
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="0b2d69d7-a2a1-449c-9680-f91c70521c60"; AC=0; DC=1 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="6738e2c4-e8a5-4a42-b16a-e040e769756e"; AC=0; DC=600 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="80e3c60e-bb94-4ad8-bbe0-0d3195efc663"; AC=0; DC=30 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="d3d55efd-c1ff-424e-9dc3-441be7833010"; AC=4000; DC=1000 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="d639518a-e56d-4345-8af2-b9f32fb26109"; AC=500; DC=100 },
                @{ Sub="0012ee47-9041-4b5d-9b77-535fba8b1442"; Set="fc7372b6-ab2d-43ee-8797-15e9841f2cca"; AC=1; DC=0 },
                @{ Sub="0d7dbae2-4294-402a-ba8e-26777e8488cd"; Set="309dce9b-bef4-4119-9921-a851fb12f0f4"; AC=1; DC=1 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="25dfa149-5dd1-4736-b5ab-e8a37b5b8187"; AC=1; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="29f6c1db-86da-48c5-9fdb-f2b67b1f44da"; AC=0; DC=0 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="7bc4a2f9-d8fc-4469-b07b-33eb785aaca0"; AC=120; DC=120 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="94ac6d29-73ce-41a6-809f-6363ba21b47e"; AC=0; DC=$null },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="abfc2519-3608-4c2a-94ea-171b0ed546ab"; AC=1; DC=1 },
                @{ Sub="238c9fa8-0aad-41ed-83f4-97be242c8f20"; Set="bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d"; AC=1; DC=0 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="0853a681-27c8-4100-a2fd-82013e970683"; AC=0; DC=50 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; AC=0; DC=1 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="498c044a-201b-4631-a522-5c744ed4e678"; AC=1; DC=0 },
                @{ Sub="2a737441-1930-4402-8d77-b2bebba308a3"; Set="d4e98f31-5ffe-4ce1-be31-1b38b384c009"; AC=0; DC=2 },
                @{ Sub="2e601130-5351-4d9d-8e04-252966bad054"; Set="3166bc41-7e98-4e03-b34e-ec0f5f2b218e"; AC=0; DC=300 },
                @{ Sub="2e601130-5351-4d9d-8e04-252966bad054"; Set="d502f7ee-1dc7-4efd-a55d-f04b6f5c0545"; AC=0; DC=$null },
                @{ Sub="48672f38-7a9a-4bb2-8bf8-3d85be19de4e"; Set="2bfc24f9-5ea2-4801-8213-3dbae01aa39d"; AC=1; DC=0 },
                @{ Sub="48672f38-7a9a-4bb2-8bf8-3d85be19de4e"; Set="73cde64d-d720-4bb2-a860-c755afe77ef2"; AC=1; DC=50 },
                @{ Sub="48672f38-7a9a-4bb2-8bf8-3d85be19de4e"; Set="d6ba4903-386f-4c2c-8adb-5c21b3328d25"; AC=0; DC=$null },
                @{ Sub="4f971e89-eebd-4455-a8de-9e59040e7347"; Set="96996bc0-ad50-47ec-923b-6f41874dd9eb"; AC=0; DC=$null },
                @{ Sub="501a4d13-42af-4429-9fd1-a8218c268e20"; Set="ee12f906-d277-404b-b6da-e5fa1a576df5"; AC=0; DC=2 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="06cadf0e-64ed-448a-8927-ce7bf90eb35d"; AC=1; DC=90 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="06cadf0e-64ed-448a-8927-ce7bf90eb35e"; AC=1; DC=90 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="0cc5b647-c1df-4637-891a-dec35c318583"; AC=100; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="0cc5b647-c1df-4637-891a-dec35c318584"; AC=100; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="12a0ab44-fe28-4fa9-b3bd-4b64f44960a6"; AC=0; DC=30 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="12a0ab44-fe28-4fa9-b3bd-4b64f44960a7"; AC=0; DC=30 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="1facfc65-a930-4bc5-9f38-504ec097bbc0"; AC=100; DC=50 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="2430ab6f-a520-44a2-9601-f7f23b5134b1"; AC=100; DC=97 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="2ddd5a84-5a71-437e-912a-db0b8c788732"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="40fbefc7-2e9d-4d25-a185-0cfd8574bac6"; AC=2; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="40fbefc7-2e9d-4d25-a185-0cfd8574bac7"; AC=2; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="447235c7-6a8d-4cc0-8e24-9eaf70b96e2b"; AC=2; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="447235c7-6a8d-4cc0-8e24-9eaf70b96e2c"; AC=2; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="465e1f50-b610-473a-ab58-00d1077dc418"; AC=2; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="465e1f50-b610-473a-ab58-00d1077dc419"; AC=2; DC=3 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="4b92d758-5a24-4851-a470-815d78aee119"; AC=1; DC=20 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="4bdaf4e9-d103-46d7-a5f0-6280121616ef"; AC=0; DC=90 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="4d2b0152-7d5c-498b-88e2-34345392a2c5"; AC=5000; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="5d76a2ca-e8c0-402f-a133-2158492d58ad"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="60fbe21b-efd9-49f2-b066-8674d8e9f423"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="616cdaa5-695e-4545-97ad-97dc2d1bdd88"; AC=100; DC=50 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="616cdaa5-695e-4545-97ad-97dc2d1bdd89"; AC=100; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="619b7505-003b-4e82-b7a6-4dd29c300971"; AC=100; DC=99 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="619b7505-003b-4e82-b7a6-4dd29c300972"; AC=100; DC=50 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="6788488b-1b90-4d11-8fa7-973e470dff47"; AC=100; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="69439b22-221b-4830-bd34-f7bcece24583"; AC=100; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="71021b41-c749-4d21-be74-a00f335d582b"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7b224883-b3cc-4d79-819f-8374152cbe7c"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7d24baa7-0b84-480f-840c-1b0743c00f5f"; AC=1; DC=1 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7f2492b6-60b1-45e5-ae55-773f8cd5caec"; AC=1; DC=3 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="828423eb-8662-4344-90f7-52bf15870f5a"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="893dee8e-2bef-41e0-89c6-b55d0929964c"; AC=100; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="8baa4a8a-14c6-4451-8e8b-14bdbd197537"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="93b8b6dc-0698-4d1c-9ee4-0644e900c85d"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="943c8cb6-6f93-4227-ad87-e9a3feec08d1"; AC=5; DC=85 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="94d3a615-a899-4ac5-ae2b-e4d8f634367f"; AC=1; DC=1 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="b0deaf6b-59c0-4523-8a45-ca7f40244114"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="b669a5e9-7b1d-4132-baaa-49190abcfeb6"; AC=1; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="bae08b81-2d5e-4688-ad6a-13243356654b"; AC=0; DC=0 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="bc5038f7-23e0-4960-96da-33abaf5935ec"; AC=100; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="be337238-0d82-4146-a960-4f3749d470c7"; AC=2; DC=2 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="bf903d33-9d24-49d3-a468-e65e0325046a"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="c4581c31-89ab-4597-8e2b-9c9cab440e6b"; AC=200000; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="c7be0679-2817-4d69-9d02-519a537ed0c6"; AC=2; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="cfeda3d0-7697-4566-a922-a9086cd49dfa"; AC=0; DC=$null },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="d8edeb9b-95cf-4f95-a73c-b061973693c8"; AC=1; DC=1 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="d8edeb9b-95cf-4f95-a73c-b061973693c9"; AC=1; DC=2 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="dfd10d17-d5eb-45dd-877a-9a34ddd15c82"; AC=1; DC=20 },
                @{ Sub="54533251-82be-4824-96c1-47b60b740d00"; Set="f735a673-2066-4f80-a0c5-ddee0cf1bf5d"; AC=100; DC=20 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="17aaa29b-8b43-4b94-aafe-35f64daaf1ee"; AC=0; DC=$null },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"; AC=0; DC=600 },
                @{ Sub="7516b95f-f776-4464-8c53-06167f40cc99"; Set="8ec4b3a5-6868-48c2-be75-4f3044be88a7"; AC=0; DC=60 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="0a7d6ab6-ac83-4ad1-8282-eca5b58308f3"; AC=30; DC=30 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="5adbbfbc-074e-4da1-ba38-db8b36b2c8f3"; AC=240; DC=240 },
                @{ Sub="8619b916-e004-4dd8-9b66-dae86f806698"; Set="cf8c6097-12b8-4279-bbdd-44601ee5209d"; AC=0; DC=$null },
                @{ Sub="9596fb26-9850-41fd-ac3e-f7c3c00afd4b"; Set="10778347-1370-4ee0-8bbd-33bdacaade49"; AC=1; DC=0 }
        )
    }

    $schemeName = "LexBoosT Ultimate FPS+Latency"

    # Check if the LexBoosT plan already exists (by name in powercfg /list)
    $planList = powercfg /list 2>$null
    $existingLine = $planList | Where-Object { $_ -match [regex]::Escape($schemeName) }

    if ($existingLine) {
        $match = [regex]::Match($existingLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if ($match.Success) {
            $lexGuid = $match.Value
            Write-Log + "LexBoosT plan ($lexGuid) already exists - updating"
        } else {
            Write-Log - "Found plan by name but could not extract GUID"
            return $false
        }
    } else {
        # Duplicate the High Performance plan - powercfg returns the new GUID
        $dupOutput = powercfg /duplicatescheme $HIGH_PERFORMANCE_GUID 2>$null
        $match = [regex]::Match($dupOutput, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if ($match.Success) {
            $lexGuid = $match.Value
            Write-Log + "Created LexBoosT plan ($lexGuid) from High Performance template"
        } else {
            Write-Log - "Failed to create plan"
            return $false
        }
    }

    $schemeGuid = $lexGuid

    Write-Log '+' "Applying $($settings.Count) power settings to '$schemeName' ($schemeGuid)"

    $applied = 0
    $failed  = 0

    foreach ($s in $settings) {
        if ($null -ne $s.AC) {
            if (Invoke-PowerCfg "setacvalueindex $schemeGuid $($s.Sub) $($s.Set) $($s.AC)") { $applied++ } else { $failed++; Write-Log - ""AC failed: $($s.Sub)/$($s.Set)"" }

        }
        if ($null -ne $s.DC) {
            if (Invoke-PowerCfg "setdcvalueindex $schemeGuid $($s.Sub) $($s.Set) $($s.DC)") { $applied++ } else { $failed++; Write-Log - ""DC failed: $($s.Sub)/$($s.Set)"" }

        }
    }

    Write-Log '+' "Applied $applied settings, $failed failed"

    # Rename the plan using powercfg /changename (no registry access needed)
    if (Invoke-PowerCfg "changename $schemeGuid `"$schemeName`"") {
        Write-Log + "Renamed plan to '$schemeName'"
    } else {
        Write-Log - "Failed to rename plan"
    }

    # Set the plan description (User\PowerSchemes is ACL-locked for admin,
    # so we use a one-shot SYSTEM scheduled task - runs 3s then self-deletes
    $planDesc = "LexBoosT Ultimate FPS+Latency - Optimized for gaming: max FPS, min latency. CPU 100%, min C-States, PCIe ASPM off, HAGS on, SSD prefetch."
    $descTask = "LexBoosT_SetPlanDesc"
    try {
        $descCmd = "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$schemeGuid' -Name Description -Value '$planDesc' -Type ExpandString"
        $descAction    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$descCmd`""
        $descPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $descSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $descTask -Action $descAction -Principal $descPrincipal -Settings $descSettings -Force | Out-Null
        Start-ScheduledTask -TaskName $descTask
        Start-Sleep -Seconds 3
        $actualDesc = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$schemeGuid" -Name Description).Description
        if ($actualDesc -eq $planDesc) {
            Write-Log + "Plan description updated"
        } else {
            Write-Log - "Description not updated (ACL lock)"
        }
    } catch {
        Write-Log - "Failed to set plan description: $($_.Exception.Message)"
    } finally {
        Unregister-ScheduledTask -TaskName $descTask -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Activate the plan
    if (Invoke-PowerCfg "setactive $schemeGuid") {

        Write-Log '+' "Plan '$schemeName' activated"
        return $true
    } else {
        Write-Log '-' "Activation failed"
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
        }
        # POLICY 2026 (USB stock): USB power-plan settings (Hub Selective Suspend
        # Timeout + USB Selective Suspend Setting) removed - USB left at Windows defaults.
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

    Write-Log '+' "Applying per-adapter NIC presets (Intel/Realtek, Ethernet/WiFi)..."
    try {
        & "$PSScriptRoot\NIC-TWEAKS.PS1"
    }
    catch {
        Write-Log '-' "NIC-TWEAKS.PS1 failed: $_"
    }
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

        Write-Log '+' "Configuring NTFS..."
        try {
            # USN Journal — disable change journal to reduce disk writes
            fsutil usn deletejournal /d C: 2>$null | Out-Null
            fsutil usn deletejournal /n C: 2>$null | Out-Null
            Write-Log '+' "  USN Journal disabled on C:"
        }
        catch {
            Write-Log '-' "Failed to disable USN Journal: $_"
        }
        try {
            # Keep NTFS metadata in non-paged pool (faster access, uses slightly more RAM)
            fsutil behavior set enablenonpagedntfs 1 2>$null | Out-Null
            Write-Log '+' "  NTFS non-paged pool enabled"
        }
        catch {
            Write-Log '-' "Failed to set enablenonpagedntfs: $_"
        }
        try {
            # Disable disk quotas on C: (removes quota tracking overhead)
            fsutil quota disable C: 2>$null | Out-Null
            Write-Log '+' "  Disk quotas disabled on C:"
        }
        catch {
            Write-Log '-' "Failed to disable disk quotas: $_"
        }
        try {
            # Allow extended characters in 8.3 short names
            fsutil behavior set allowextchar 1 2>$null | Out-Null
            Write-Log '+' "  Extended characters in 8.3 names allowed"
        }
        catch {
            Write-Log '-' "Failed to set allowextchar: $_"
        }

        Write-Log '+' "Applying NTFS registry optimizations..."
        $ntfsSettings = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsMemoryUsage'; Value = 2 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'LongPathsEnabled'; Value = 1 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableCompression'; Value = 1 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableEncryption'; Value = 1 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsEncryptPagingFile'; Value = 0 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NTFSDisableLastAccessUpdate'; Value = 0x80000001 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisable8dot3NameCreation'; Value = 1 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsMftZoneReservation'; Value = 4 }
        )
        foreach ($setting in $ntfsSettings) {
            Set-RegistryValue -Path $setting.Path -Name $setting.Name -Type DWORD -Value $setting.Value
        }

        Write-Log '+' "Disabling boot defrag and auto layout..."
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction' -Name 'Enable' -Type String -Value 'N'
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout' -Name 'EnableAutoLayout' -Type DWORD -Value 0

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
        # Hibernation kept enabled — required by CUDA/TensorRT for large contiguous memory allocations.
        # Without hiberfil.sys as a memory reserve, OOM errors manifest as "invalid wheel" during pip install.
        Write-Log '+' "Hibernation kept enabled for desktop (required for CUDA/TensorRT memory reservations)."

        $hibernationSettings = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Value = 1 },
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings'; Name = 'ShowHibernateOption'; Value = 0 },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'HibernateEnabled'; Value = 1 }
        )

        foreach ($setting in $hibernationSettings) {
            Set-RegistryValue -Path $setting.Path -Name $setting.Name -Type DWORD -Value $setting.Value
        }
    }
    else {
        Write-Log '+' 'Reducing hibernation file size for laptop system...'
        try {
            powercfg /h /type reduced | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Log '-' ('powercfg /h /type reduced failed (exit ' + $LASTEXITCODE + '), falling back to reduced size...') }
            powercfg hibernate size 0 | Out-Null
        }
        catch {
            Write-Log '-' ('Reduced hibernation file size failed: ' + $_)
        }
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

function Get-EcoreLayout {
    # Hybrid topology split for Intel (Alder/Raptor/Meteor/Arrow Lake, Core Ultra).
    # Windows orders hybrid logical processors P-cores (with SMT siblings) first, then E-cores.
    # NOTE: assumes the common tail layout AND SMT-on-P; otherwise returns EBase=-1 so callers
    # skip rather than write an invalid affinity mask (which could freeze boot).
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $phys = [int]$cpu.NumberOfCores
        $log  = [int]$cpu.NumberOfLogicalProcessors
        $smt  = $log -gt $phys
        if (-not $smt) { return @{ ECores = 0; EBase = -1; Logical = $log } }
        $eCores = [Math]::Max(0, $phys * 2 - $log)   # E-cores have no SMT
        $pCount = $phys - $eCores
        $eBase  = $pCount * 2                        # first E-core logical id (tail)
        if ($eCores -le 0 -or $eBase -lt 0 -or $eBase -ge $log) { $eBase = -1 }
        return @{ ECores = $eCores; EBase = $eBase; Logical = $log }
    }
    catch {
        Write-Log '-' "Get-EcoreLayout failed: $_"
        return @{ ECores = 0; EBase = -1; Logical = 0 }
    }
}

function Set-NDISOptimizer {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring NDIS RSS Optimizer..."

    # WMI can hang under TrustedInstaller — query with timeout via job
    $wmiJob = Start-Job -ScriptBlock {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        return $cpu.Name
    }
    $cpuName = $null
    if (Wait-Job $wmiJob -Timeout 15) {
        $cpuName = Receive-Job $wmiJob
    } else {
        Stop-Job $wmiJob
        Write-Log '-' "WMI query timed out (TrustedInstaller context) — skipping NDIS RSS optimization."
        Remove-Job $wmiJob -Force
        return
    }
    Remove-Job $wmiJob -Force

    if ($cpuName -notmatch "Intel") {
        Write-Log '+' "Non-Intel CPU detected. Skipping RSS E-Core pinning."
        return
    }

    # Hybrid check: Intel 12th-gen+ (Core i-12xxx) or Core Ultra
    $isHybrid = ($cpuName -match "i[3579]-1[2-9]\d{3}") -or
                ($cpuName -match "Core Ultra [2-9]") -or
                ($cpuName -match "Core Ultra [1-9]\d{2}")

    if (-not $isHybrid) {
        Write-Log '+' "Non-hybrid CPU ($cpuName). Skipping RSS E-Core pinning."
        return
    }

    try {
        $topo = Get-EcoreLayout
        if ($topo.ECores -le 0 -or $topo.EBase -lt 0 -or $topo.EBase -ge $topo.Logical) {
            Write-Log '-' ("Invalid hybrid topology (ECores={0}, EBase={1}). Skipping RSS E-Core pinning." -f $topo.ECores, $topo.EBase)
            return
        }

        Write-Log '+' ("Detected {0} E-Cores (logical ids from {1}). Routing RSS to them..." -f $topo.ECores, $topo.EBase)

        Enable-NetAdapterRss -Name "*" -ErrorAction Stop
        Set-NetAdapterRss -Name "*" -BaseProcessorGroup 0 -BaseProcessorNumber $topo.EBase -MaxProcessors $topo.ECores -ErrorAction Stop

        Write-Log '+' ("NDIS RSS pinned to E-Cores (base={0}, count={1})." -f $topo.EBase, $topo.ECores)
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
        Write-Log '-' "AMD 3D V-Cache detected ($coreCount cores): core parking preserved (X3D stability — parking left to Windows/Game Bar)."
    }
    else {
        Set-CoreParkingDisabled -CpuType "AMD"
    }

    if (Test-IsIntelCPU) {
        Write-Log '+' "Intel CPU detected - disabling heterogeneous multi-class parking..."
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HeteroMultiClassParkingEnabled' -Type DWORD -Value 0
    }

    $isAMD3DVCache = Test-IsAMD3DVCache
    if (-not $isAMD3DVCache) {
        Write-Log '+' 'Disabling forced parking (per-CPU clock tick left at default)'
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'EnablePerCpuClockTickScheduling' -Type DWORD -Value 1
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'ForceParkingRequested' -Type DWORD -Value 0
    }
    else {
        Write-Log '-' "AMD 3D V-Cache detected: preserving per-CPU scheduling and parking request (X3D stability)."
    }

    $desktopPowerSettings = @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf'; Name = 'WdfGlobalLogsDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf'; Name = 'WdfGlobalSleepStudyDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DeepIoCoalescingEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'StandbyConnectivityGracePeriod'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'SleepstudyAccountingEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'SkipHibernateMemoryMapValidation'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'MSDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'HibernateEnabledDefault'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'AllowHibernate'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'HibernateChecksummingEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'IdleProcessorsRequireQosManagement'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DisableInboxPepGeneratedConstraints'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'IgnoreCsComplianceCheck'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'EnergyEstimationEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'EventProcessorEnabled'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'FxAccountingTelemetryDisabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'ThermalTelemetryVerbosity'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'CoalescingFlushInterval'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'PowerSettingProfile'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'Win32CalloutWatchdogBugcheckEnabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'PowerOffFrozenProcessors'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'IdlePowerMode'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'DisableDSTThrottle'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'ContiguousMemoryFromAnyNode'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'LogSize'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'; Name = 'DiagnosticFlags'; Value = 0 },
        # POLICY 2026 (USB stock): usbflags keys (DisableHCS0Idle / Allow64KLowOrFullSpeedControlTransfers) removed.
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'NoPauseOnSuspend'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'EnableNicAutoPowerSaverInSleepStudy'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'DisableNaps'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'AlwaysComputeQosHints'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'CoalescingTimerInterval'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'IpiLastClockOwnerDisable'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DisableVsyncLatencyUpdate'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PerfCalculateActualUtilization'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'AllowSystemRequiredPowerRequests'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'DisableDisplayBurstOnPowerSourceChange'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'PoFxSystemIrpWaitForReportDevicePowered'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'AllowAudioToEnableExecutionRequiredPowerRequests'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'TrackNblOwner'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'SriovSupportTestOverride'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'DebugLoggingMode'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'DisableNDISWatchDog'; Value = 1 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'; Name = 'DirectedMacForNapsEnabled'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System'; Name = 'IoAllowLoadCrashDumpDriver'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'IdleScanInterval'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'WatchdogSleepTimeout'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'WatchdogResumeTimeout'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'SleepStudyDeviceAccountingLevel'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'SelfHealingEnabled'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'VirtualizationEnabled'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'BugcheckRecoveryEnabled'; Value = 0 }
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

    # POLICY 2026 (USB stock): USB LPM / hub LPM disabling removed - USB left stock.

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

    Write-Log '+' "Blocking SleepStudy diagnostic writes..."
    try {
        $sleepStudyDir = "$env:SystemRoot\System32\SleepStudy"
        if (Test-Path $sleepStudyDir) {
            icacls $sleepStudyDir /remove:g SYSTEM 2>$null | Out-Null
            icacls $sleepStudyDir /remove:g Administrators 2>$null | Out-Null
            Write-Log '+' "[+] SleepStudy permissions blocked (desktop only)"
        }
    }
    catch {
        Write-Log '-' "Failed to block SleepStudy permissions: $_"
    }

    # AMD GUARD (2026-09-04): disabling DMA remapping (AMD-Vi/IOMMU) destabilizes AMD
    # DMA routing (NVMe/PCIe/GPU) and triggers DPC_WATCHDOG_VIOLATION (0x133) at boot
    # on AMD platforms (R5 5600 + RX 6600). Skipped on AMD.
    $isAMDForDma = $false
    try { $isAMDForDma = ((Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name) -match 'AMD' } catch { }
    if ($isAMDForDma) {
        Write-Log '-' "AMD CPU detected: skipping DMA remapping disable (AMD-Vi/IOMMU critical - 0x133 boot crash risk)."
    } else {
        Write-Log ''+'' "Disabling DMA remapping on all services..."
        try {
            $dmaKeys = reg query "HKLM\SYSTEM\CurrentControlSet\Services" /s /f "DmaRemappingCompatible" 2>$null |
                Select-String 'HKEY_.*\\Services\\' |
                ForEach-Object { $_.Line.Trim() }
            foreach ($key in $dmaKeys) {
                reg add "$key" /v "DmaRemappingCompatible" /t REG_DWORD /d 0 /f 2>$null | Out-Null
            }
            Write-Log ''+'' "[+] DMA remapping disabled (desktop only)"
        }
        catch {
            Write-Log '-' "Failed to disable DMA remapping: $_"
        }
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
    $skipOptimizations = Test-IsAMDCPU

    if (-not $skipOptimizations) {
        Write-Log '+' "Disabling dynamic tick for maximum timer precision..."
        bcdedit /deletevalue useplatformclock 2>$null | Out-Null
        bcdedit /deletevalue useplatformtick  2>$null | Out-Null
        bcdedit /set disabledynamictick yes 2>$null | Out-Null
        bcdedit /deletevalue tscsyncpolicy 2>$null | Out-Null
    }
    else {
        Write-Log '-' "AMD CPU detected: skipping disabledynamictick (boot-hang risk)."
    }

    # AMD GUARD (2026-09-04): isolatedcontext No / nx optin disable VBS isolation + DEP;
    # destabilizes AMD boot. Skipped on AMD.
    $isAMDForBcd = $false
    try { $isAMDForBcd = ((Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name) -match 'AMD' } catch { }
    if ($isAMDForBcd) {
        Write-Log '-' "AMD CPU: skipping isolatedcontext/nx/bootmenupolicy (boot-crash risk on AMD)."
    } else {
        Write-Log '+' "Setting isolated context to No..."
        bcdedit /set {current} isolatedcontext No 2>$null | Out-Null
        Write-Log '+' "Enabling NX (DEP) opt-in..."
        bcdedit /set {current} nx optin 2>$null | Out-Null
        Write-Log '+' "Setting legacy boot menu policy..."
        bcdedit /set bootmenupolicy Legacy 2>$null | Out-Null
    }
}
function Set-NtfsConfiguration {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring NTFS behavior and disk power settings..."

    # === NTFS behavior ===
    fsutil behavior set disable8dot3 1           | Out-Null
    fsutil behavior set disablecompression 1      | Out-Null
    fsutil behavior set disabledeletenotify 0     | Out-Null
    fsutil behavior set disableencryption 1       | Out-Null
    fsutil behavior set encryptpagingfile 0       | Out-Null
    fsutil behavior set memoryusage 2             | Out-Null
    fsutil behavior set mftzone 4                 | Out-Null
    fsutil behavior set disablelastaccess 1       | Out-Null
    fsutil behavior set quotanotify 86400         | Out-Null

    # === Disk power ===
    # Only apply power settings for GUIDs that exist in the current scheme
    $diskSubSettings = @(
        '0b2d69d7-a2a1-449c-9680-f91c70521c60',
        'dab60367-53fe-4f59-828b-ccb42464c0ad',
        'd639518a-e56d-4345-8af2-b9f32fb26109',
        'd3d55efd-c1bd-4242-8af08-3362b6389142',
        '25dfa149-5dd1-4736-b5ab-e8a37b5b8187'
    )
    foreach ($guid in $diskSubSettings) {
        $queryResult = powercfg -query SCHEME_CURRENT SUB_DISK $guid 2>&1 | Out-String
        if ($queryResult -match 'Power Setting GUID') {
            powercfg -setacvalueindex SCHEME_CURRENT SUB_DISK $guid 0 2>$null | Out-Null
        }
    }

    Write-Log '+' "NTFS and disk power configuration completed."
}

function Set-MobileSyncOptimizations {
    [CmdletBinding()]
    param()

    Write-Log '+' "Configuring mobile sync / disk HIPM-DIPM and write cache..."

    foreach ($prop in @('EnableHIPM', 'EnableDIPM', 'EnableHDDParking')) {
        $keys = reg query "HKLM\SYSTEM\CurrentControlSet\Services" /s /f "$prop" 2>$null |
            Select-String -Pattern '^HKEY'
        foreach ($key in $keys) {
            $keyPath = $key.Line.Trim()
            reg add "$keyPath" /v "$prop" /t REG_DWORD /d "0" /f | Out-Null
        }
    }

    taskkill /im mobsync.exe /f 2>$null | Out-Null
    Start-Sleep -Milliseconds 500

    try {
        $mobsync = "$env:SystemRoot\system32\mobsync.exe"
        $mobsyncOld = "$env:SystemRoot\system32\mobsync.old"
        if (Test-Path $mobsync) {
            # mobsync.exe is owned by TrustedInstaller — need MinSudo to rename.
            $minSudo = Join-Path $env:SystemRoot 'LexBoosTOS\Utilities\MinSudo.exe'
            if (Test-Path $minSudo) {
                # Use cmd `ren` under TrustedInstaller (handles both fresh rename and replace-existing).
                $renCmd = "if exist `"$mobsyncOld`" del /f /q `"$mobsyncOld`" & ren `"$mobsync`" mobsync.old"
                $proc = Start-Process -FilePath $minSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged cmd.exe /c `"$renCmd`"" -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0 -and (Test-Path $mobsyncOld)) {
                    Write-Log '+' "Renamed mobsync.exe to mobsync.old (via TrustedInstaller)"
                } else {
                    throw "MinSudo ren exit $($proc.ExitCode)"
                }
            } else {
                # Fallback: take ownership then rename
                $acl = Get-Acl $mobsync
                $adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
                $acl.SetOwner($adminSid)
                Set-Acl -Path $mobsync -AclObject $acl -ErrorAction Stop
                if (Test-Path $mobsyncOld) { Remove-Item -Path $mobsyncOld -Force -ErrorAction Stop }
                Rename-Item -Path $mobsync -NewName 'mobsync.old' -Force -ErrorAction Stop
                Write-Log '+' "Renamed mobsync.exe to mobsync.old (ownership takeover)"
            }
        }
    }
    catch {
        Write-Log '-' "Could not rename mobsync.exe: $_"
    }

    $enumKeys = reg query "hklm\SYSTEM\CurrentControlSet\Enum" /f "{4d36e967-e325-11ce-bfc1-08002be10318}" /d /s 2>$null |
        Select-String -Pattern '^HKEY'
    foreach ($enumKey in $enumKeys) {
        $diskPath = Join-Path $enumKey.Line.Trim() 'Device Parameters\Disk'
        reg add "$diskPath" /v UserWriteCacheSetting /t REG_DWORD /d 1 /f | Out-Null
        reg add "$diskPath" /v CacheIsPowerProtected /t REG_DWORD /d 1 /f | Out-Null
    }

    Write-Log '+' "Mobile sync configuration completed."
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

# =============================================================================
# POWER REGISTRY TWEAKS
# Source-of-truth: was registry/power.yml (migrated here to avoid duplication)
# =============================================================================

function Set-RegistryPowerTweaks {
    [CmdletBinding()]
    param()

    Write-Log '+' "Applying Power registry tweaks (from power.yml)..."

    $isDesktop = -not (Get-CachedLaptopStatus)
    $isVM = Get-CachedVMStatus
    if ($isVM) {
        Write-Log '+' "VM detected — skipping most power tweaks"
        return
    }

    # POLICY 2026 (USB stock): USB selective suspend / LPM registry block removed.

    # === HKLM\SYSTEM\CurrentControlSet\Control\Wdf ===
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf' -Name 'WdfGlobalLogsDisabled' -Type DWORD -Value 1
    if ($isDesktop) {
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Wdf' -Name 'WdfGlobalSleepStudyDisabled' -Type DWORD -Value 1
    }

    # === HKLM\SYSTEM\CurrentControlSet\Control\Power ===
    $powerBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    if ($isDesktop) {
        Set-RegistryValue -Path $powerBase -Name 'CoalescingTimerInterval' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'DeepIoCoalescingEnabled' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'EnergyEstimationEnabled' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'IgnoreCsComplianceCheck' -Type DWORD -Value 1
        Set-RegistryValue -Path $powerBase -Name 'MSDisabled' -Type DWORD -Value 1
        Set-RegistryValue -Path $powerBase -Name 'StandbyConnectivityGracePeriod' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'SleepstudyAccountingEnabled' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'PlatformAoAcOverride' -Type DWORD -Value 0
        Set-RegistryValue -Path $powerBase -Name 'PlatformRoleOverride' -Type DWORD -Value 0
    }
    Set-RegistryValue -Path $powerBase -Name 'DisableInboxPepGeneratedConstraints' -Type DWORD -Value 1
    Set-RegistryValue -Path $powerBase -Name 'EnforceAusterityMode' -Type DWORD -Value 0
    Set-RegistryValue -Path $powerBase -Name 'EventProcessorEnabled' -Type DWORD -Value 0
    Set-RegistryValue -Path $powerBase -Name 'FxAccountingTelemetryDisabled' -Type DWORD -Value 1
    Set-RegistryValue -Path $powerBase -Name 'HeteroMultiClassParkingEnabled' -Type DWORD -Value 0
    Set-RegistryValue -Path $powerBase -Name 'IdleProcessorsRequireQosManagement' -Type DWORD -Value 0
    Set-RegistryValue -Path $powerBase -Name 'ThermalTelemetryVerbosity' -Type DWORD -Value 0

    # === Power\EnergyEstimation\TaggedEnergy ===
    $taggedEnergy = "$powerBase\EnergyEstimation\TaggedEnergy"
    if (-not (Test-Path $taggedEnergy)) { New-Item -Path $taggedEnergy -Force | Out-Null }
    Set-RegistryValue -Path $taggedEnergy -Name 'DisableTaggedEnergyLogging' -Type DWORD -Value 1
    Set-RegistryValue -Path $taggedEnergy -Name 'TelemetryMaxApplication' -Type DWORD -Value 0
    Set-RegistryValue -Path $taggedEnergy -Name 'TelemetryMaxTagPerApplication' -Type DWORD -Value 0

    # === Session Manager\Throttle ===
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Throttle' -Name 'PerfEnablePackageIdle' -Type DWORD -Value 0

    # === Processor power management ===
    # REMOVED (audit): CPPCEnable=0 + AllowPepPerfStates=0 coupaient la gestion moderne
    # fréquence/voltage (CPPC/pEP). Contre-productif sur AMD Zen (perte de boost, stutter)
    # et interférait avec le scheduling prefer-core des X3D. Défaut Windows conservé.

    # === I/O System ===
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System' -Name 'CountOperations' -Type DWORD -Value 0

    # === fssProv (shadow copy encryption) ===
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\fssProv' -Name 'EncryptProtocol' -Type DWORD -Value 0

    # === PCIe ASPM ===
    # AMD GUARD (2026-09-04): ASPMOptOut=1 overrides kernel PCIe ASPM; destabilizes AMD boot. Skipped on AMD.
    if (-not ((Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name -match 'AMD')) {
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\pci\Parameters' -Name 'ASPMOptOut' -Type DWORD -Value 1
    }

    # === Schedule (RPC over scheduler) ===
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule' -Name 'DisableRpcOver' -Type DWORD -Value 1

    # === Misc policies ===
    Set-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Control Panel\International' -Name 'BlockCleanupOfUnusedPreinstalledLangPacks' -Type DWORD -Value 1

    # === CLSID (NetworkExplorer folder) ===
    # HKCR is a merge of HKCU\Software\Classes + HKLM\Software\Classes. The CLSID
    # key is owned by TrustedInstaller in HKLM\Software\Classes — Set-ItemProperty
    # fails with "Accès refusé" even elevated. Use MinSudo to apply.
    $clsidPath = 'HKLM\Software\Classes\CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}\ShellFolder'
    $clsidValue = 'Attributes'
    $clsidData = '2962489444'
    $minSudo = Join-Path $env:SystemRoot 'LexBoosTOS\Utilities\MinSudo.exe'
    if (Test-Path $minSudo) {
        $regCmd = "reg add `"$clsidPath`" /v `"$clsidValue`" /t REG_DWORD /d `"$clsidData`" /f"
        $proc = Start-Process -FilePath $minSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged cmd.exe /c `"$regCmd`"" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Write-Log '+' "CLSID Attributes set (via TrustedInstaller)"
        } else {
            # Fallback: take ownership and try via PowerShell
            try {
                $tiSetup = "takeown /F `"$clsidPath`" /r /d y >nul 2>&1 & icacls `"$clsidPath`" /grant *S-1-5-32-544:(F) /T /C >nul 2>&1"
                Start-Process -FilePath $minSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged cmd.exe /c `"$tiSetup`"" -Wait -WindowStyle Hidden | Out-Null
                Set-RegistryValue -Path $clsidPath -Name 'Attributes' -Type DWORD -Value $clsidData
                Write-Log '+' "CLSID Attributes set (via ownership takeover)"
            } catch {
                Write-Log '-' "Failed to set CLSID Attributes: $_"
            }
        }
    } else {
        # No MinSudo — try direct write
        Set-RegistryValue -Path $clsidPath -Name 'Attributes' -Type DWORD -Value $clsidData
    }

    # === Storage / NVMe ===
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Storage' -Name 'StorageD3InModernStandby' -Type DWORD -Value 0
    $stornvme = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'
    if (-not (Test-Path $stornvme)) { New-Item -Path $stornvme -Force | Out-Null }
    Set-RegistryValue -Path $stornvme -Name 'DisableDSTThrottle' -Type DWORD -Value 1
    if (-not $isDesktop) {
        # Laptop: keep NVMe idle power management (battery). Desktop: 0 (perf) set by Set-DesktopPowerOptimizations.
        Set-RegistryValue -Path $stornvme -Name 'IdlePowerMode' -Type DWORD -Value 1
    } else {
        Set-RegistryValue -Path $stornvme -Name 'IdlePowerMode' -Type DWORD -Value 0
    }
    # QueueDepth=254 and MSI=1 REMOVED: forcing these on stornvme is a known trigger of
    # INACCESSIBLE_BOOT_DEVICE (0x7B) on some NVMe controllers/drives at next boot.
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Classpnp' -Name 'NVMeDisablePerfThrottling' -Type DWORD -Value 1
    # NVMe interrupt coalescing: disable (0) for lowest latency.
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Classpnp' -Name 'InterruptCoalescingTime' -Type String -Value '* 0'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Classpnp' -Name 'InterruptCoalescingEntry' -Type String -Value '* 0'

    # === Session Manager\Executive ===
    $exec = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive'
    Set-RegistryValue -Path $exec -Name 'TickcountRolloverDelay' -Type DWORD -Value 0
}

# === Main entry point ===
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
            "Configure-NDISOptimizer" { Set-NDISOptimizer }
            "Configure-DesktopPowerOptimizations" { Set-DesktopPowerOptimizations }
            "Configure-TSX" { Set-TSX }
            "Configure-BcdOptimizations" { Set-BcdOptimizations }
            "Configure-IntelHybridVisibility" { Set-IntelHybridVisibility }
            "Configure-RegistryPowerTweaks" { Set-RegistryPowerTweaks }
            "Configure-Ntfs" { Set-NtfsConfiguration }
            "Configure-MobileSync" { Set-MobileSyncOptimizations }
        }

        Write-Log '+' ""
    }

    Write-Log '+' "System optimization process completed."
    Write-Log '+' "A reboot may be required for all changes to take effect."
    exit 0
}

# Execute main function
Invoke-Main

