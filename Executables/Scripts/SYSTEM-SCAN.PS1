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
} catch {
    Write-Info 'Total RAM' "Unable to retrieve"
}

# --- GPU(s) ---
try {
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic Display Driver' }
    if ($gpus) {
        $gpuList = @($gpus | ForEach-Object { $_.Name }) -join ' | '
        Write-Info 'GPU(s)' "$gpuList"
    } else {
        Write-Info 'GPU(s)' "None detected"
    }
} catch {
    Write-Info 'GPU(s)' "Unable to retrieve"
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
