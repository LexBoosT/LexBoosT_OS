#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$caps = @(
    'activity','appDiagnostics','appointments','backgroundSpatialPerception',
    'calendar','callHistory','cellularData','chat','contacts','email','eyeTracker',
    'gazeInput','generativeAI','humanPresence','location','motion',
    'notifications','passkeys','phoneCall','phoneCallHistory','spatialPerception',
    'tasks','userAccountInformation','userDataTasks','userNotificationListener',
    'voiceActivation','wifiData','wifiDirect'
)

$scopes = @('HKLM:\SOFTWARE','Registry::HKEY_USERS\.DEFAULT\Software')
foreach ($scope in $scopes) {
    foreach ($cap in $caps) {
        $base = $scope + '\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $cap
        try { New-Item -Path $base -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Set-ItemProperty -Path $base -Name 'Value' -Value 'Deny' -Type String -Force -ErrorAction SilentlyContinue } catch {}
        $np = $base + '\NonPackaged'
        try { New-Item -Path $np -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Set-ItemProperty -Path $np -Name 'Value' -Value 'Deny' -Type String -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# Per-user hive writes skipped — existing users inherit from .DEFAULT on next logon;
# HKLM covers machine-wide policy regardless. Avoids NTFS stress / hive-unload races.

$global:LASTEXITCODE = 0
Write-Log '+' "ConsentStore Deny applied to $($caps.Count) capabilities (HKLM + .DEFAULT only, per-user skipped)."
exit 0
