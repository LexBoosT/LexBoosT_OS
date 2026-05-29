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

Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' } |
    ForEach-Object {
        $sid = $_.PSChildName
        foreach ($cap in $caps) {
            $base = 'Registry::HKEY_USERS\' + $sid + '\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $cap
            try { New-Item -Path $base -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
            try { Set-ItemProperty -Path $base -Name 'Value' -Value 'Deny' -Type String -Force -ErrorAction SilentlyContinue } catch {}
            $np = $base + '\NonPackaged'
            try { New-Item -Path $np -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
            try { Set-ItemProperty -Path $np -Name 'Value' -Value 'Deny' -Type String -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

$global:LASTEXITCODE = 0
Write-Log '+' "ConsentStore Deny applied to $($caps.Count) capabilities across all scopes."
exit 0
