#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'

function Write-Info {
    param([string]$Label, [string]$Value)
    Write-Host "[INFO] $Label : $Value"
}

# --- Windows version & build ---
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = $os.Caption
    $version = $os.Version
    $build = [System.Environment]::OSVersion.Version.Build
    $displayVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion).DisplayVersion
    Write-Info 'Windows Edition' "$caption"
    Write-Info 'Version' "$version (Display: $displayVersion)"
    Write-Info 'Build' "$build"
} catch {
    Write-Info 'Windows Version' "Unable to retrieve"
}

# --- RAM ---
try {
    $totalRamBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $totalRamGB = [math]::Round($totalRamBytes / 1GB, 2)
    Write-Info 'Total RAM' "$totalRamGB GB"

    $sticks = Get-CimInstance Win32_PhysicalMemory
    if ($sticks) {
        $ddrMap = @{ 20='DDR'; 21='DDR2'; 22='DDR2'; 24='DDR3'; 25='DDR3L'; 26='DDR4'; 27='DDR5'; 28='LPDDR'; 29='LPDDR2'; 30='LPDDR3'; 31='LPDDR4'; 34='LPDDR5' }
        $i = 1
        foreach ($stick in $sticks) {
            $capacityGB = [math]::Round($stick.Capacity / 1GB, 2)
            $speedMHz = $stick.Speed
            $manufacturer = if ([string]::IsNullOrWhiteSpace($stick.Manufacturer)) { 'N/A' } else { $stick.Manufacturer.Trim() }
            $ddrType = if ($ddrMap.ContainsKey([int]$stick.SMBIOSMemoryType)) { $ddrMap[[int]$stick.SMBIOSMemoryType] } else { 'Unknown' }
            Write-Host "         [STICK $i] $manufacturer | $capacityGB GB | $ddrType | $speedMHz MHz"
            $i++
        }
    } else {
        Write-Host "         [STICKS] No details available"
    }
} catch {
    Write-Info 'Total RAM' "Unable to retrieve"
}

# --- GPU(s) & driver ---
try {
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic Display Driver' }
    if ($gpus) {
        $gpuList = @($gpus | ForEach-Object {
            $driver = $_.DriverVersion
            $driverDate = if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { 'N/A' }
            if ($driver) { "$($_.Name) [driver $driver - $driverDate]" } else { $_.Name }
        }) -join ' | '
        Write-Info 'GPU(s)' "$gpuList"
    } else {
        Write-Info 'GPU(s)' "None detected"
    }
} catch {
    Write-Info 'GPU(s)' "Unable to retrieve"
}

# --- Network adapter(s) ---
try {
    $nics = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true -and $_.Name }
    if ($nics) {
        $nicList = @($nics | ForEach-Object {
            $speed = if ($_.Speed) { "$([math]::Round($_.Speed / 1e9, 1)) Gbps" } else { 'speed N/A' }
            "$($_.Name) [$speed - MAC $($_.MACAddress)]"
        }) -join ' | '
        Write-Info 'Network adapter(s)' "$nicList"
    } else {
        Write-Info 'Network adapter(s)' "None detected"
    }
} catch {
    Write-Info 'Network adapter(s)' "Unable to retrieve"
}

# --- LexBoosT version / Edition ---
try {
    $editionSubVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionSubVersion).EditionSubVersion
    if ($editionSubVersion) {
        if ($editionSubVersion -match 'LexBoosT') {
            Write-Info 'LexBoosT version' "$editionSubVersion"
        } else {
            Write-Info 'Edition' "$editionSubVersion"
        }
    } else {
        Write-Info 'Edition' "Stock Windows"
    }
} catch {
    Write-Info 'Edition' "Stock Windows"
}

# --- System install date (age in days) ---
try {
    $installDate = $os.InstallDate
    $now = Get-Date
    $daysInstalled = [math]::Floor(($now - $installDate).TotalDays)
    Write-Info 'Windows installed on' "$($installDate.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Info 'Days since install' "$daysInstalled days"
} catch {
    Write-Info 'Windows install date' "Unable to retrieve"
}

exit 0
