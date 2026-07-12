#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host "=== Active Setup Stubs Cleanup ==="

$activeSetupPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components'
)

$vendorPatterns = @(
    'Brave', 'MicrosoftEdge', 'Microsoft Edge', 'Edge Update',
    'OneDrive', 'GoogleChrome', 'Google Chrome', 'Chrome Update',
    'Mozilla', 'Firefox', 'Opera', 'Vivaldi', 'Zen Browser'
)

$stubPatterns = @(
    'Brave', 'MicrosoftEdge', 'msedge', 'OneDrive', 'GoogleChrome',
    'chrome\.exe', 'firefox', 'Mozilla', 'Opera', 'vivaldi', 'zen'
)

$cleaned = 0

# 1. Clear Active Setup StubPath for browser/OneDrive entries
foreach ($root in $activeSetupPaths) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $name = (Get-ItemProperty -Path $_.PSPath -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
            $stub = (Get-ItemProperty -Path $_.PSPath -Name 'StubPath' -ErrorAction SilentlyContinue).StubPath
            $isVendor = $false

            foreach ($pat in $vendorPatterns) {
                if ($name -and $name -match $pat) { $isVendor = $true; break }
            }
            if (-not $isVendor) {
                foreach ($pat in $stubPatterns) {
                    if ($stub -and $stub -match $pat) { $isVendor = $true; break }
                }
            }

            if ($isVendor) {
                if ($stub -and $stub.Length -gt 0) {
                    Set-ItemProperty -Path $_.PSPath -Name 'StubPath' -Value '' -Type ExpandString -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $_.PSPath -Name 'StubPath' -Force -ErrorAction SilentlyContinue
                }
                $cleaned++
                Write-Log '+' "  Cleaned: $($name -replace '\s+', ' ') (StubPath cleared)"
            }
        } catch { }
    }
}

# 2. Remove Run keys for browser/OneDrive auto-launch
$runKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Run'
)

$runValueNames = @(
    'OneDriveSetup', 'OneDrive', 'BraveUpdate', 'BraveUpdateOnDemand',
    'MicrosoftEdgeAutoLaunch', 'EdgeAutoLaunch', 'ChromeAutoLaunch',
    'OperaBrowserAutoLaunch', 'VivaldiAutoLaunch'
)

foreach ($runKey in $runKeys) {
    if (-not (Test-Path $runKey)) { continue }
    foreach ($valName in $runValueNames) {
        try {
            $existing = Get-ItemProperty -Path $runKey -Name $valName -ErrorAction SilentlyContinue
            if ($existing.$valName) {
                Remove-ItemProperty -Path $runKey -Name $valName -Force -ErrorAction SilentlyContinue
                Write-Log '-' "  Removed Run key: $valName from $runKey"
            }
        } catch { }
    }
    # Also match wildcard patterns
    try {
        $props = Get-Item -Path $runKey -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($vn in $props.GetValueNames()) {
                if ($vn -like '*EdgeAutoLaunch*' -or $vn -like '*BrowserAuto*' -or
                    $vn -like '*OneDrive*' -or $vn -like '*Brave*') {
                    Remove-ItemProperty -Path $runKey -Name $vn -Force -ErrorAction SilentlyContinue
                    Write-Log '-' "  Removed Run key (wildcard): $vn from $runKey"
                }
            }
        }
    } catch { }
}

Write-Log '+' "Active Setup cleanup complete. $cleaned stubs cleaned."
exit 0
