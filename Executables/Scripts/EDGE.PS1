param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("EdgeBrowser", "EdgeUpdate", "Full")]
    [string]$Mode
)

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ============================================
# Core uninstall functions
# ============================================

function Uninstall-Process {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $originalNation = [microsoft.win32.registry]::GetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', [Microsoft.Win32.RegistryValueKind]::String)

    $baseKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    $registryPath = $baseKey + '\ClientState\' + $Key

    if (!(Test-Path -Path $registryPath)) {
        Write-Log '-' "[$Mode] Registry key not found: $registryPath"
        return
    }

    Remove-ItemProperty -Path $registryPath -Name "experiment_control_labels" -ErrorAction SilentlyContinue | Out-Null

    $folderPath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"

    if (!(Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }
    New-Item -ItemType File -Path $folderPath -Name "MicrosoftEdge.exe" -Force | Out-Null

    [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', 84, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null

    $env:windir = ""
    try {
        $uninstallString = (Get-ItemProperty -Path $registryPath).UninstallString
        $uninstallArguments = (Get-ItemProperty -Path $registryPath).UninstallArguments

        if ([string]::IsNullOrEmpty($uninstallString) -or [string]::IsNullOrEmpty($uninstallArguments)) {
            Write-Log '-' "[$Mode] Cannot find uninstall methods for $Mode"
            return
        }

        $uninstallArguments += " --force-uninstall --delete-profile"

        if (!(Test-Path -Path $uninstallString)) {
            Write-Log '-' "[$Mode] setup.exe not found at: $uninstallString"
            return
        }
        Start-Process -FilePath $uninstallString -ArgumentList $uninstallArguments -Wait -NoNewWindow

        if ((Get-ItemProperty -Path $baseKey).IsEdgeStableUninstalled -eq 1) {
            Write-Log '+' "[$Mode] Edge Stable has been successfully uninstalled"
        }
    }
    finally {
        [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $originalNation, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
        $env:windir = [System.Environment]::GetEnvironmentVariable("windir", "Machine")
    }
}

# ============================================
# Tasks / Processes / Services
# ============================================

function Stop-EdgeTasks {
    Write-Log '+' "Killing Edge processes and tasks"
    "MicrosoftEdgeUpdate","msedge","MicrosoftEdge*" | ForEach-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Setup that may be running the Edge installer
    Get-Process | Where-Object { $_.ProcessName -eq "setup" -and $_.MainWindowTitle -like "*Edge*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Remove-EdgeServices {
    Write-Log '+' "Removing Edge services"
    @("edgeupdate","edgeupdatem","MicrosoftEdgeElevationService") | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
            sc.exe delete $_ | Out-Null
        }
    }
}

# ============================================
# File / folder cleanup
# ============================================

function Remove-EdgeFiles {
    Write-Log '+' "Removing Edge files and folders"
    $paths = @(
        "$env:SystemDrive\Users\Public\Desktop\Microsoft Edge.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "$env:windir\system32\MicrosoftEdgeBCHost.exe",
        "$env:windir\system32\MicrosoftEdgeCP.exe",
        "$env:windir\system32\MicrosoftEdgeDevTools.exe",
        "$env:windir\system32\MicrosoftEdgeSH.exe",
        "$env:windir\system32\Tasks\MicrosoftEdge*",
        "$env:ProgramFiles(x86)\Internet Explorer",
        "$env:ProgramW6432\Internet Explorer",
        "$env:ProgramFiles(x86)\Microsoft\Edge",
        "$env:ProgramFiles(x86)\Microsoft\EdgeUpdate",
        "$env:ProgramFiles(x86)\Microsoft\EdgeCore"
    )
    $paths | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log '+' "Removed: $_"
        }
    }
}

# ============================================
# Registry cleanup
# ============================================

function Remove-EdgeScheduledTasks {
    Get-ScheduledTask | Where-Object { $_.TaskName -like '*MicrosoftEdgeUpdate*' } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log '+' "Removed scheduled task: $($_.TaskName)"
    }
}

function Remove-EdgeRegistry {
    Write-Log '+' "Removing Edge registry keys and values"

    # Delete values
    $valueDeletes = @(
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMigratedBrowserPin' },
        @{ Path = 'HKLM:\SOFTWARE\RegisteredApplications'; Name = 'Microsoft Edge' },
        @{ Path = 'HKCR\.htm\OpenWithProgIds'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.html\OpenWithProgIds'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.shtml\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.svg\OpenWithProgIds'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.xht\OpenWithProgIds'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.xhtml\OpenWithProgIds'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.webp\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCR\.xml\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'; Name = 'MSEdgeHTM_microsoft-edge' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main\EnterpriseMode'; Name = 'MSEdgePath' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'Microsoft Edge Update' },
        @{ Path = 'HKCU:\SOFTWARE\RegisteredApplications'; Name = 'Microsoft Edge' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.htm\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.html\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.shtml\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.svg\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.xht\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.xhtml\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Classes\.webp\OpenWithProgids'; Name = 'MSEdgeHTM' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'; Name = 'MSEdgeHTM_microsoft-edge' }
    )
    foreach ($v in $valueDeletes) {
        if (Test-Path $v.Path) {
            Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue
        }
    }

    # Delete keys (whole subtrees)
    $keyDeletes = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update',
        'Registry::HKEY_CLASSES_ROOT\CLSID\{1FCBE96C-1697-43AF-9140-2897C7C69767}',
        'Registry::HKEY_CLASSES_ROOT\AppID\{1FCBE96C-1697-43AF-9140-2897C7C69767}',
        'Registry::HKEY_CLASSES_ROOT\Interface\{C9C2B807-7731-4F34-81B7-44FF7779522B}',
        'Registry::HKEY_CLASSES_ROOT\TypeLib\{C9C2B807-7731-4F34-81B7-44FF7779522B}',
        'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}',
        'Registry::HKEY_CLASSES_ROOT\MSEdgeHTM',
        'Registry::HKEY_CLASSES_ROOT\MSEdgePDF',
        'Registry::HKEY_CLASSES_ROOT\MSEdgeMHT',
        'Registry::HKEY_CLASSES_ROOT\AppID\{628ACE20-B77A-456F-A88D-547DB6CEEDD5}',
        'HKLM:\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'Registry::HKEY_CLASSES_ROOT\AppID\ie_to_edge_bho.dll',
        'Registry::HKEY_CLASSES_ROOT\AppID\{31575964-95F7-414B-85E4-0E9A93699E13}',
        'Registry::HKEY_CLASSES_ROOT\CLSID\{1FD49718-1D00-4B19-AF5F-070AF6D5D54C}',
        'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{1FD49718-1D00-4B19-AF5F-070AF6D5D54C}',
        'Registry::HKEY_CLASSES_ROOT\ie_to_edge_bho.IEToEdgeBHO',
        'Registry::HKEY_CLASSES_ROOT\ie_to_edge_bho.IEToEdgeBHO.1',
        'HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}',
        'HKCU:\SOFTWARE\Microsoft\Edge'
    )
    foreach ($k in $keyDeletes) {
        if (Test-Path $k) {
            Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log '+' "Removed key: $k"
        }
    }
}

# ============================================
# EdgeUpdate policies (prevent reinstall)
# ============================================

function Set-EdgeUpdatePolicies {
    Write-Log '+' "Setting EdgeUpdate policies to prevent reinstall"
    $basePath = 'HKLM:\Software\Policies\Microsoft\EdgeUpdate'
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -Force | Out-Null }
    $policies = @{
        'Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' = 0
        'Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' = 0
        'Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' = 0
        'Update{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}' = 0
        'Update{65C35B14-6C1D-4122-AC46-7148CC9D6497}' = 0
        'Update{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}' = 0
        'Install{65C35B14-6C1D-4122-AC46-7148CC9D6497}' = 0
        'InstallDefault' = 0
        'CreateDesktopShortcutDefault' = 0
        'UpdateDefault' = 0
    }
    foreach ($p in $policies.GetEnumerator()) {
        Set-ItemProperty -Path $basePath -Name $p.Key -Value $p.Value -Type DWord -Force -ErrorAction SilentlyContinue
    }

    # Other Edge policies
    Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\EdgeUI' -Name 'DisableMFUTracking' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\MicrosoftEdge\Main' -Name 'AllowPrelaunch' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\Software\OEM\MicrosoftEdge' -Name 'AutoLaunchOnLogonBehavior' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Font Drivers' -Name 'Adobe Type Manager' -Value $null -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Font Drivers' -Name 'Adobe Type Manager' -ErrorAction SilentlyContinue
}

# ============================================
# AppX Edge cleanup
# ============================================

function Remove-EdgeAppX {
    Write-Log '+' "Removing Edge AppX packages"
    Get-AppxPackage -AllUsers 'Microsoft.MicrosoftEdge.Stable*' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers 'Microsoft.MicrosoftEdgeDevToolsClient*' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like 'Microsoft.MicrosoftEdge*' } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# ============================================
# Internet Explorer system package removal
# ============================================

function Remove-IEPackage {
    Write-Log '+' "Removing Internet Explorer system package"
    try {
        Remove-WindowsPackage -Online -PackageName 'Microsoft-Windows-Internet-Browser-Deployment-Package~31bf3856ad364e35~amd64~~10.0.22621.1' -ErrorAction SilentlyContinue
    } catch {}
}

# ============================================
# Mode dispatchers
# ============================================

function Uninstall-Edge {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    [microsoft.win32.registry]::SetValue("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev", "AllowUninstall", 1, [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null

    Uninstall-Process -Key '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'

    @( "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:PUBLIC\Desktop",
        "$env:USERPROFILE\Desktop" ) | ForEach-Object {
        $shortcutPath = Join-Path -Path $_ -ChildPath "Microsoft Edge.lnk"
        if (Test-Path -Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
        }
    }
}

function Uninstall-EdgeUpdate {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    if (Test-Path -Path $registryPath) {
        $uninstallCmdLine = (Get-ItemProperty -Path $registryPath).UninstallCmdLine
        if (-not [string]::IsNullOrEmpty($uninstallCmdLine)) {
            Write-Log '+' "Uninstalling: $uninstallCmdLine"
            Start-Process cmd.exe "/c $uninstallCmdLine" -WindowStyle Hidden -Wait
        } else {
            Write-Log '-' "Cannot find uninstall methods for EdgeUpdate"
        }
    } else {
        Write-Log '-' "Registry key not found: $registryPath"
    }

    Get-ChildItem -Path "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $edgeUpdatePath = Join-Path $_.FullName "AppData\Local\Microsoft\EdgeUpdate"
        if (Test-Path $edgeUpdatePath) {
            Write-Log '+' "Removing per-user EdgeUpdate: $edgeUpdatePath"
            Remove-Item -LiteralPath $edgeUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MicrosoftEdgeUpdate*" } | ForEach-Object {
        Write-Log '+' "Removing scheduled task: $($_.TaskName)"
        Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
    Get-ScheduledTask -TaskPath "\Microsoft\EdgeUpdate\" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log '+' "Removing scheduled task: $($_.TaskName)"
        Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath "\Microsoft\EdgeUpdate\" -Confirm:$false -ErrorAction SilentlyContinue
    }

    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
    Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | ForEach-Object {
        $runPath = "HKU:\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runPath) {
            Remove-ItemProperty -LiteralPath $runPath -Name "Microsoft Edge Update" -Force -ErrorAction SilentlyContinue
        }
    }
}

# Full = everything (mirrors the YML edge.yml)
function Uninstall-Full {
    Stop-EdgeTasks
    Remove-EdgeServices
    Uninstall-Edge
    Remove-EdgeScheduledTasks
    Remove-EdgeFiles
    Remove-EdgeRegistry
    Remove-EdgeAppX
    Remove-IEPackage
    Uninstall-EdgeUpdate
    Set-EdgeUpdatePolicies
}

switch ($Mode) {
    "EdgeBrowser" { Uninstall-Edge }
    "EdgeUpdate"  { Uninstall-EdgeUpdate }
    "Full"        { Uninstall-Full }
    default { Write-Log '-' "Invalid mode: $Mode" }
}
exit 0
