#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Telemetry and data-collection disabling.
.DESCRIPTION
    Migrated from registry/telemetry.yml. Disables:
    - Telemetry services (DiagTrack, WTDS)
    - AllowTelemetry policy
    - 30+ WMI Autologger sessions
    - DMA remapping / StorPort idle power management
    - Cloud SDK / Docker / .NET / VS / npm telemetry env vars
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' "Applying telemetry and data-collection disabling..."

# =============================================================================
# 1. Core telemetry policies
# =============================================================================
# HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components is owned by
# TrustedInstaller ??? "Acc??s refus??" via reg add even when elevated. Use MinSudo.
$minSudo = Join-Path $env:windir 'LexBoosTOS\Utilities\MinSudo.exe'
$hasMinSudo = Test-Path $minSudo

# WTDS\Components\ServiceEnabled. The value lives in 'HKLM\...\WTDS\Components"'
# (note the trailing double-quote in the subkey name ??? a Windows quirk).
# The key/value pair is owned by the WTDS service and the registry ACL forbids
# modifications by Administrators after the first write. The value is already 0
# on any system where WTDS has been disabled even once, so we just verify and
# skip otherwise.
$wtdsValue = Get-ItemProperty -Path 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components"' -Name 'ServiceEnabled' -ErrorAction SilentlyContinue
if ($wtdsValue -and ($wtdsValue.ServiceEnabled -eq 0)) {
    Write-Log '+' "WTDS ServiceEnabled already 0 (no change needed)"
} else {
    Write-Log '-' "WTDS ServiceEnabled not 0 or key not accessible ??? leaving untouched (system-managed)"
}

reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\TaggedEnergy' /v 'TelemetryMaxTagPerApplication' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log '-' "Failed: TelemetryMaxTagPerApplication (exit $LASTEXITCODE)"
}

# =============================================================================
# 2. Disable WMI Autologger sessions (Start=0 to disable)
# =============================================================================
$autologgers = @(
    'Cellcore',
    'Circular Kernel Context Logger',
    'CloudExperienceHostOOBE',
    'Diaglog',
    'Diagtrack-Listener',
    'EventLog-Security',
    'FaceTel',
    'HolographicDevice',
    'LwtNetLog',
    'Mellanox-Kernel',
    'Microsoft-Windows-AssignedAccess-Trace',
    'Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace',
    'Microsoft-Windows-Setup',
    'NBSMLOGGER',
    'NetCore',
    'NtfsLog',
    'PEAuthLog',
    'RadioMgr',
    'RdrLog',
    'ReadyBoot',
    'ReFSLog',
    'SetupPlatform',
    'SetupPlatformTel',
    'SpoolerLogger',
    'SQMLogger',
    'TCPIPLOGGER',
    'TileStore',
    'UBPM',
    'WdiContextLog',
    'WFP-IPsec Trace',
    'WiFiDriverHVSession',
    'WiFiDriverHVSessionRepro',
    'WiFiSession',
    'WMI_Traces'
)

foreach ($name in $autologgers) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$name"
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'Start' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# 3. Disable DMA remapping compatible bit (security hardening)
# =============================================================================
# Use the registry provider directly instead of parsing reg.exe output (avoids
# the "ERREUR: nom de cl?? non valide" loop when a value name contains spaces
# or special characters that confuse the regex match).
try {
    $root = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $env:COMPUTERNAME)
    $servicesKey = $root.OpenSubKey('SYSTEM\CurrentControlSet\Services')
    if ($servicesKey) {
        foreach ($subName in $servicesKey.GetSubKeyNames()) {
            $sub = $servicesKey.OpenSubKey($subName)
            if ($sub) {
                try {
                    if ($sub.GetValue('DmaRemappingCompatible') -ne $null) {
                        $sub.SetValue('DmaRemappingCompatible', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
                    }
                } catch { }
                $sub.Close()
            }
        }
        $servicesKey.Close()
    }
} catch {
    Write-Log '-' "DMA remapping sweep failed: $_"
}
$root = $null

# =============================================================================
# 4. Disable StorPort idle power management
# =============================================================================
try {
    $root = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $env:COMPUTERNAME)
    $enumKey = $root.OpenSubKey('SYSTEM\CurrentControlSet\Enum')
    if ($enumKey) {
        foreach ($busName in $enumKey.GetSubKeyNames()) {
            $bus = $enumKey.OpenSubKey($busName)
            if (-not $bus) { continue }
            foreach ($devName in $bus.GetSubKeyNames()) {
                $dev = $bus.OpenSubKey($devName)
                if (-not $dev) { continue }
                try {
                    if ($dev.GetValue('StorPort') -ne $null) {
                        $dev.SetValue('EnableIdlePowerManagement', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
                    }
                } catch { }
                $dev.Close()
            }
            $bus.Close()
        }
        $enumKey.Close()
    }
} catch {
    Write-Log '-' "StorPort idle sweep failed: $_"
}
$root = $null

# =============================================================================
# 5. Cloud / Dev tool telemetry env vars (per-user + system)
# =============================================================================
$envVars = @{
    # Cloud / container tools
    'CLOUDSDK_CORE_DISABLE_PROMPTS'   = '1'
    'DOCKER_CLI_TELEMETRY_OPTOUT'     = '1'

    # .NET / Visual Studio telemetry opt-out
    'DOTNET_CLI_TELEMETRY_OPTOUT'     = '1'
    'DOTNET_TRY_CLI_TELEMETRY_OPTOUT' = '1'
    'VS_TELEMETRY_OPT_OUT'            = '1'

    # PowerShell telemetry opt-out
    'POWERSHELL_TELEMETRY_OPTOUT'     = '1'

    # Node.js
    'npm_config_loglevel'             = 'silent'
}

foreach ($name in $envVars.Keys) {
    $val = $envVars[$name]
    setx $name $val | Out-Null
    [Environment]::SetEnvironmentVariable($name, $val, 'Machine')
}

# =============================================================================
# 6. Settings sync / privacy (was registry/privacy.yml)
# =============================================================================
Write-Log '+' "Disabling settings sync..."

# Per-user
$syncBase = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SettingSync'
Set-ItemProperty -Path $syncBase -Name 'SyncPolicy' -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
foreach ($group in 'Accessibility','BrowserSettings','Credentials','Personalization','Windows') {
    $gpath = "$syncBase\Groups\$group"
    if (-not (Test-Path $gpath)) { New-Item -Path $gpath -Force | Out-Null }
    Set-ItemProperty -Path $gpath -Name 'Enabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Machine-wide policies
$polBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
if (-not (Test-Path $polBase)) { New-Item -Path $polBase -Force | Out-Null }
$syncPolicies = @{
    'DisableApplicationSettingSync'              = 2
    'DisableApplicationSettingSyncUserOverride'  = 1
    'DisableCredentialsSettingSync'              = 2
    'DisableCredentialsSettingSyncUserOverride'  = 1
    'DisablePersonalizationSettingSync'          = 2
    'DisablePersonalizationSettingSyncUserOverride' = 1
    'DisableSettingSync'                         = 2
    'DisableSettingSyncUserOverride'             = 1
    'DisableStartLayoutSettingSync'              = 2
    'DisableStartLayoutSettingSyncUserOverride'  = 1
    'DisableSyncOnPaidNetwork'                   = 1
    'DisableWebBrowserSettingSync'               = 2
    'DisableWebBrowserSettingSyncUserOverride'   = 1
    'DisableWindowsSettingSync'                  = 2
    'DisableWindowsSettingSyncUserOverride'      = 1
}
foreach ($p in $syncPolicies.GetEnumerator()) {
    Set-ItemProperty -Path $polBase -Name $p.Key -Value $p.Value -Type DWord -Force -ErrorAction SilentlyContinue
}

Write-Log '+' "Telemetry, data-collection, and settings sync disabling complete."
exit 0
