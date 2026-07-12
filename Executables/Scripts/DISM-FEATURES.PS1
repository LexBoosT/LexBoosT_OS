function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Update-Feature {
    param(
        [string]$featureName,
        [bool]$bool
    )

    $dismCmd = if ($bool) { "Enable" } else { "Disable" }

    try {
        if ($bool) {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
            if ($feature.State -ne "Enabled") {
                Write-Log '+' "$dismCmd $featureName"
                Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -All -ErrorAction Stop
            }
        }
        else {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
            if ($feature.State -ne "Disabled") {
                Write-Log '-' "$dismCmd $featureName"
                Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop
            }
        }
    }
    catch {
        Write-Log '-' "Skipping $featureName (not available on this system)"
    }
}

function Remove-Capability {
    param([string]$capabilityName)

    try {
        $cap = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop
        if ($cap.State -eq "Installed") {
            Write-Log '-' "Remove-Capability $capabilityName"
            Remove-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop
        }
    }
    catch {
        Write-Log '-' "Skipping $capabilityName (not available on this system)"
    }
}


$features = @(
    # Enable (kept for compatibility)
    @{ Name = "DirectPlay"; Bool = $true },
    @{ Name = "LegacyComponents"; Bool = $true },
    # Disable (covers all from registry/features.yml)
    @{ Name = "Internet-Explorer-Optional-amd64"; Bool = $false },
    @{ Name = "Printing-Foundation-Features"; Bool = $false },
    @{ Name = "Printing-Foundation-InternetPrinting-Client"; Bool = $false },
    @{ Name = "WorkFolders-Client"; Bool = $false },
    # New from features.yml
    @{ Name = "WindowsMediaPlayer"; Bool = $false },
    @{ Name = "MediaPlayback"; Bool = $false },
    @{ Name = "WCF-Services45"; Bool = $false },
    @{ Name = "WCF-TCP-PortSharing45"; Bool = $false },
    @{ Name = "Printing-PrintToPDFServices-Features"; Bool = $false }
)
foreach ($feature in $features) {
    Update-Feature -featureName $feature.Name -bool $feature.Bool
}

# Remove capabilities (Steps Recorder, Windows Media Player legacy, etc.)
$capabilities = @(
    "App.StepsRecorder~~~~0.0.1.0",
    "Media.WindowsMediaPlayer~~~~0.0.12.0"
)
foreach ($cap in $capabilities) {
    Remove-Capability -capabilityName $cap
}

# Disable Reserved Storage (frees ~7 GB reserved for Windows Update)
Write-Log '-' "Disabling Reserved Storage"
try {
    Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop
    Write-Log '+' "Reserved Storage disabled"
}
catch {
    Write-Log '-' "Reserved Storage could not be disabled: $_"
}

# ReserveManager registry key (migrated from features.yml)
$reserveMgr = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager'
if (-not (Test-Path $reserveMgr)) { New-Item -Path $reserveMgr -Force | Out-Null }
Set-ItemProperty -Path $reserveMgr -Name '0' -Value 0 -Type DWord -Force

# Exit cleanly
exit 0
