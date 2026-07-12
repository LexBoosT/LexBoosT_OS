# Load DefaultUser hive and all offline NTUSER.DAT profiles
if (-not (Get-Module -ListAvailable -Name FXPSYaml)) {
    try {
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
        Install-Module -Name FXPSYaml -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    }
    finally {
        $ProgressPreference = $prevProgress
    }
}
Import-Module -Name FXPSYaml -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

function Get-UserProfilesOffline {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $usersDir = Join-Path $env:SYSTEMDRIVE 'Users'
    if (-not (Test-Path $usersDir)) { return @() }

    $profiles = @()
    $builtIn = @('Default', 'Public', 'All Users', 'Default User')
    $activeSIDs = @()

    try {
        $explorerProc = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
            Where-Object { $_.UserName } |
            Select-Object -ExpandProperty UserName -Unique
        foreach ($userName in $explorerProc) {
            try {
                $sid = (New-Object System.Security.Principal.NTAccount($userName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                if ($sid) { $activeSIDs += $sid }
            } catch { }
        }
    } catch { }

    Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $profileDir = $_.FullName
        $profileName = $_.Name

        if ($profileName -in $builtIn) { return }
        if ($profileName -like '*.*') { return }

        $ntuserPath = Join-Path $profileDir 'NTUSER.DAT'
        if (-not (Test-Path $ntuserPath)) { return }

        $profiles += @{ Name = $profileName; Path = $ntuserPath; Dir = $profileDir }
    }

    return $profiles
}

function Copy-HKCUSettingsToHive {
    param(
        [string]$HiveName,
        [string[]]$RegistryPaths
    )

    foreach ($path in $RegistryPaths) {
        $source = "Registry::HKCU\$path"
        $destination = "Registry::HKU\$HiveName\$path"
        $values = Get-ItemProperty -Path $source -ErrorAction SilentlyContinue
        if ($values) {
            foreach ($property in $values.PSObject.Properties) {
                if ($property.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                    if (-not (Test-Path $destination)) {
                        New-Item -Path $destination -Force | Out-Null
                    }
                    if (-not ((Get-ItemProperty $destination -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $property.Name)) {
                        New-ItemProperty -Path $destination -Name $property.Name -Value $property.Value | Out-Null
                    }
                    else {
                        Set-ItemProperty -Path $destination -Name $property.Name -Value $property.Value
                    }
                }
            }
        }
    }
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ===== COLLECT HKCU PATHS FROM ALL YAML CONFIGS =====
# AME extracts the playbook to %LocalAppData%\Temp\AME\Playbooks\<guid>\.
# From there: Executables\Scripts\<PSScriptRoot> -> ../../ is the playbook root.
$configurationFolder = Join-Path $PSScriptRoot "..\..\Configuration\Tasks"
if (-not (Test-Path $configurationFolder)) {
    Write-Log '-' "Configuration folder not found: $configurationFolder"
    $RegistryPaths = @()
} else {
    $yamlFiles = @(Get-ChildItem -Path $configurationFolder -Filter *.yml -Recurse -ErrorAction SilentlyContinue)
    $RegistryPaths = @()
    foreach ($yamlFile in $yamlFiles) {
        try {
            $yamlContent = Get-Content $yamlFile.FullName -Raw -ErrorAction Stop
            $parsedYaml = ConvertFrom-Yaml $yamlContent
            foreach ($entry in $parsedYaml) {
                if ($entry.actions.path) {
                    foreach ($value in $entry.actions.path) {
                        if ($value -like 'HKCU*') {
                            $subPath = $value.Substring(4)
                            if (!$RegistryPaths.Contains($subPath)) { $RegistryPaths += $subPath }
                        }
                    }
                }
            }
        } catch {
            Write-Log '-' "Failed to parse $($yamlFile.FullName): $_"
        }
    }
}

Write-Log '+' "Collected $($RegistryPaths.Count) HKCU registry paths to propagate."

# ===== PHASE 1: DEFAULT USER HIVE =====
Write-Host "=== Phase 1: Default User Hive ==="
$defaultHiveName = "AME_UserHive_Default"
$ntuserPaths = @(
    "C:\Users\Default\NTUSER.DAT",
    (Join-Path $env:SYSTEMDRIVE "Users\Default\NTUSER.DAT")
)

$defaultLoaded = $false
foreach ($ntuserPath in $ntuserPaths) {
    if (Test-Path $ntuserPath) {
        reg load "HKU\$defaultHiveName" $ntuserPath | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $defaultLoaded = $true
            Write-Log '+' "Loaded default user hive from: $ntuserPath"
            break
        }
    }
}

if ($defaultLoaded) {
    Copy-HKCUSettingsToHive -HiveName $defaultHiveName -RegistryPaths $RegistryPaths
    reg unload "HKU\$defaultHiveName" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log '+' "Successfully unloaded default user hive."
    } else {
        Write-Log '-' "Failed to unload default user hive. It may still be mounted."
    }
} else {
    Write-Log '-' "Could not find or load default user NTUSER.DAT."
}

# ===== PHASE 2: ALL OFFLINE USER PROFILES =====
Write-Host ""
Write-Host "=== Phase 2: Offline User Profiles ==="
$offlineProfiles = Get-UserProfilesOffline

if ($offlineProfiles.Count -eq 0) {
    Write-Log '+' "No offline user profiles found."
} else {
    $processed = 0
    foreach ($profile in $offlineProfiles) {
        $hiveName = "LexBoosT_Hive_$($profile.Name)"
        Write-Log '+' "Processing offline profile: $($profile.Name) ($($profile.Path))"

        $loadResult = reg load "HKU\$hiveName" $profile.Path 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log '-' "Could not load NTUSER.DAT (profile may be in use or corrupted)"
            continue
        }

        try {
            Copy-HKCUSettingsToHive -HiveName $hiveName -RegistryPaths $RegistryPaths
            $processed++
        }
        catch {
            Write-Log '-' "Failed to apply settings to $($profile.Name): $_"
        }
        finally {
            reg unload "HKU\$hiveName" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log '+' "Unloaded $($profile.Name) hive."
            } else {
                Write-Log '-' "Failed to unload $($profile.Name) hive. Use 'reg unload HKU\$hiveName' manually if needed."
            }
        }
    }
    Write-Log '+' "Applied HKCU settings to $processed offline profile(s)."
}

Write-Host ""
Write-Host "=== Done: HKCU settings propagated to Default + $processed offline profiles ==="
exit 0
