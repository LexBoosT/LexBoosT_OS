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


$features = @(
    @{ Name = "DirectPlay"; Bool = $true },
    @{ Name = "LegacyComponents"; Bool = $true },
    @{ Name = "MSRDC-Infrastructure"; Bool = $false },
    @{ Name = "Printing-Foundation-Features"; Bool = $false },
    @{ Name = "Printing-Foundation-InternetPrinting-Client"; Bool = $false },
    @{ Name = "WorkFolders-Client"; Bool = $false },
    @{ Name = "NetFx3"; Bool = $true }
)
foreach ($feature in $features) {
    Update-Feature -featureName $feature.Name -bool $feature.Bool
}
# Exit cleanly
exit 0
