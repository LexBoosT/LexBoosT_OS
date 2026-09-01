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
    # Build exacte (avec révision UBR, ex. 26200.9267) lue depuis la base de registre
    $ubr = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction SilentlyContinue).UBR
    $exactBuild = if ($ubr) { "$build.$ubr" } else { [string]$build }
    $displayVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion).DisplayVersion
    Write-Info 'Windows Edition' "$caption"
    Write-Info 'Version' "$version (Display: $displayVersion)"
    Write-Info 'Build' "$exactBuild"
} catch {
    Write-Info 'Windows Version' "Unable to retrieve"
}

# --- CPU ---
try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $maker = $cpu.Manufacturer
    $model = $cpu.Name.Trim()
    $cores  = $cpu.NumberOfCores
    $threads = $cpu.NumberOfLogicalProcessors
    $maxMHz = $cpu.MaxClockSpeed
    # Frequence REELLE (turbo) = base x % of Maximum Frequency  (meme source que Task Manager)
    $curGHz = 'N/A'
    # Fréquence réel (turbo) = base x % (même source que Task Manager). Chaîne de repli
    # sur plusieurs chemins de compteur, puis valeur nominale en dernier recours.
    $counterPaths = @(
        '\Processor Information(_Total)\% of Maximum Frequency',
        '\Processor Information(\_Total)\% of Maximum Frequency',
        '\Processor(*)\% Processor Performance'
    )
    $perfPct = $null
    foreach ($cp in $counterPaths) {
        try {
            $sample = (Get-Counter $cp -ErrorAction Stop).CounterSamples | Select-Object -First 1
            if ($sample -and $sample.CookedValue -gt 0) { $perfPct = $sample.CookedValue; break }
        } catch { }
    }
    if ($perfPct) {
        $curMHz = [math]::Round($maxMHz * $perfPct / 100.0)
        $curGHz = "$([math]::Round($curMHz/1000,2)) GHz"
    } else {
        $nomMHz = $cpu.CurrentClockSpeed
        $curGHz = "$([math]::Round($nomMHz/1000,2)) GHz (nominal)"
    }
    $sock = if ($cpu.SocketDesignation -and $cpu.SocketDesignation -notin @('CPU 0','Socket 0','Unknown')) { $cpu.SocketDesignation } else { 'N/A' }
    $l2 = if ($cpu.L2CacheSize -gt 0) { [math]::Round($cpu.L2CacheSize/1024,1) } else { 0 }
    $l3 = if ($cpu.L3CacheSize -gt 0) { [math]::Round($cpu.L3CacheSize/1024,1) } else { 0 }

    # Plateforme : Intel / AMD / AMD 3D V-Cache
    $platform = 'Unknown'
    if ($maker -match 'Intel') { $platform = 'Intel' }
    elseif ($maker -match 'AMD') {
        if ($model -match 'X3D') { $platform = 'AMD (3D V-Cache)' } else { $platform = 'AMD' }
    }

    Write-Info 'CPU' "$model"
    Write-Info 'CPU manufacturer' "$maker  ($platform)"
    Write-Info 'CPU cores' "$cores physical / $threads logical"
    Write-Info 'CPU clock' "base $([math]::Round($maxMHz/1000,2)) GHz - current $curGHz"
    Write-Info 'CPU cache' "L2 $l2 MB / L3 $l3 MB"
    Write-Info 'CPU socket' "$sock"
} catch {
    Write-Info 'CPU' "Unable to retrieve"
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
