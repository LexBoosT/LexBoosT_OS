param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("EdgeBrowser", "EdgeUpdate", "Full", "Install", "WebView2")]
    [string]$Mode
)

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ============================================
# SHARED UTILITIES
# ============================================

function Invoke-WithTimeout {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSec = 30,
        [string]$Description = ''
    )
    try {
        $job = Start-Job -ScriptBlock $ScriptBlock
        $completed = Wait-Job $job -Timeout $TimeoutSec
        if (-not $completed) {
            Stop-Job $job | Out-Null
            Write-Log '-' "  [TIMEOUT] $Description"
        } else {
            Receive-Job $job | Out-Null
        }
        Remove-Job $job -Force
    } catch {
        Write-Log '-' "  [ERROR] $Description : $_"
    }
}

function Kill-EdgeProcesses {
    Write-Log '+' 'Killing Edge processes and tasks...'
    'MicrosoftEdgeUpdate', 'msedge', 'MicrosoftEdge*' | ForEach-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Get-Process | Where-Object { $_.ProcessName -eq 'setup' -and $_.MainWindowTitle -like '*Edge*' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Get-MsiexecAppByName {
    param([string]$Name)
    $uninstallKeyPath = 'Microsoft\Windows\CurrentVersion\Uninstall'
    $uninstallKeys = (Get-ChildItem -Path @(
        "HKLM:\SOFTWARE\$uninstallKeyPath",
        "HKLM:\SOFTWARE\WOW6432Node\$uninstallKeyPath",
        "HKCU:\SOFTWARE\$uninstallKeyPath",
        "HKCU:\SOFTWARE\WOW6432Node\$uninstallKeyPath"
    ) -EA SilentlyContinue) -match '\{[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}\}'
    $results = @()
    foreach ($key in $uninstallKeys.PSPath) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($props.DisplayName -like "*$Name*" -and $props.UninstallString -like '*MsiExec.exe*') {
            $results += Split-Path -Path $key -Leaf
        }
    }
    return $results
}

function Edge-Installed {
    $msedgeExe = "$([Environment]::GetFolderPath('ProgramFilesx86'))\Microsoft\Edge\Application\msedge.exe"
    return Test-Path $msedgeExe
}

function Delete-IfExists {
    param([string]$Path)
    if (Test-Path $Path) { Remove-Item -Path $Path -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue }
}

# ============================================
# CORE UNINSTALL — Multi-method (merged from RemoveEdge.ps1)
# ============================================

function Uninstall-EdgeProcess {
    param([string]$Key)

    $originalNation = [Microsoft.Win32.Registry]::GetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', [Microsoft.Win32.RegistryValueKind]::String)

    $baseKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    $registryPath = "$baseKey\ClientState\$Key"
    if (!(Test-Path $registryPath)) {
        Write-Log '-' "Registry key not found: $registryPath"
        return
    }

    Remove-ItemProperty -Path $registryPath -Name 'experiment_control_labels' -ErrorAction SilentlyContinue | Out-Null

    $folderPath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
    if (!(Test-Path $folderPath)) { New-Item -ItemType Directory -Path $folderPath -Force | Out-Null }
    New-Item -ItemType File -Path $folderPath -Name 'MicrosoftEdge.exe' -Force | Out-Null

    [Microsoft.Win32.Registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', 84, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null

    $env:windir = ''
    try {
        $uninstallString = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).UninstallString
        $uninstallArguments = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).UninstallArguments
        if ([string]::IsNullOrEmpty($uninstallString) -or [string]::IsNullOrEmpty($uninstallArguments)) {
            Write-Log '-' "Cannot find uninstall methods for $Key"
            return
        }
        $uninstallArguments += ' --force-uninstall --delete-profile'
        if (!(Test-Path $uninstallString)) {
            Write-Log '-' "setup.exe not found at: $uninstallString"
            return
        }
        Start-Process -FilePath $uninstallString -ArgumentList $uninstallArguments -Wait -NoNewWindow
        if ((Get-ItemProperty -Path $baseKey -ErrorAction SilentlyContinue).IsEdgeStableUninstalled -eq 1) {
            Write-Log '+' 'Edge Stable has been successfully uninstalled'
        }
    } finally {
        [Microsoft.Win32.Registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $originalNation, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
        $env:windir = [System.Environment]::GetEnvironmentVariable('windir', 'Machine')
    }
}

function Remove-EdgeChromium {
    Write-Log '+' 'Trying to find Edge uninstallers...'

    # Quick pre-check: if Edge executable is already gone, skip straight to cleanup
    if (-not (Edge-Installed)) {
        Write-Log '+' 'Edge not installed — skipping uninstall, continuing with cleanup.'
        return
    }

    # Allow Edge uninstall
    $baseKey = "HKLM:\SOFTWARE" + $(if ([Environment]::Is64BitOperatingSystem) { "\WOW6432Node" }) + "\Microsoft"
    $devKeyPath = "$baseKey\EdgeUpdateDev"
    if (!(Test-Path $devKeyPath)) { New-Item -Path $devKeyPath -ItemType Key -Force | Out-Null }
    Set-ItemProperty -Path $devKeyPath -Name 'AllowUninstall' -Value '' -Type String -Force

    # Remove experiment_control_labels
    Remove-ItemProperty -Path "$baseKey\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Name 'experiment_control_labels' -Force -EA 0

    # Remove NoRemove flags
    $noremovePaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
    )
    foreach ($p in $noremovePaths) {
        Remove-ItemProperty -Path $p -Name 'NoRemove' -ErrorAction SilentlyContinue | Out-Null
    }

    Kill-EdgeProcesses

    # Find MSI uninstallers
    $msis = Get-MsiexecAppByName -Name 'Microsoft Edge'

    # Find setup.exe locations
    $edgeUninstallers = @()
    'LocalApplicationData', 'ProgramFilesX86', 'ProgramFiles' | ForEach-Object {
        $folder = [Environment]::GetFolderPath($_)
        $edgeUninstallers += Get-ChildItem "$folder\Microsoft\Edge*\setup.exe" -Recurse -EA 0 |
            Where-Object { ($_ -like '*Edge\Application*') -or ($_ -like '*SxS\Application*') }
    }

    # Get uninstall string from registry
    $uninstallKeyPath = "$baseKey\Windows\CurrentVersion\Uninstall\Microsoft Edge"
    $uninstallString = (Get-ItemProperty -Path $uninstallKeyPath -EA 0).UninstallString
    $uninstallPath = $null
    $uninstallArgs = $null

    if (-not [string]::IsNullOrEmpty($uninstallString)) {
        $parts = $uninstallString -split '"', 3 | Where-Object { $_ } | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_.Trim()) }
        if ($parts.Count -ge 1 -and [System.IO.Path]::IsPathRooted($parts[0]) -and (Test-Path $parts[0] -PathType Leaf)) {
            $uninstallPath = $parts[0]
            if ($parts.Count -ge 2) { $uninstallArgs = $parts[1] }
        }
    }

    if (($msis.Count -le 0) -and ($edgeUninstallers.Count -le 0) -and !$uninstallPath) {
        Write-Log '+' 'Edge uninstaller not found — may already be uninstalled, continuing with cleanup.'
        return
    }

    # Try each uninstall method
    $method = 1
    $fail = $true
    while ($fail) {
        switch ($method) {
            1 {
                Kill-EdgeProcesses
                # Create fake UWP Edge stub to trick installer
                $edgeUWP = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
                $created = $false
                if (!(Test-Path "$edgeUWP\MicrosoftEdge.exe")) {
                    if (!(Test-Path $edgeUWP)) { New-Item $edgeUWP -ItemType Directory -Force | Out-Null }
                    New-Item "$edgeUWP\MicrosoftEdge.exe" -Force | Out-Null
                    $created = $true
                }
                # Uninstall MSI packages first
                foreach ($msi in $msis) {
                    Start-Process -FilePath 'msiexec.exe' -ArgumentList "/qn /X$(Split-Path -Path $msi -Leaf) REBOOT=ReallySuppress /norestart" -Wait
                }
                # Uninstall standard Edge
                if ($uninstallPath) {
                    Start-Process -Wait -FilePath $uninstallPath -ArgumentList "$uninstallArgs --force-uninstall --delete-profile" -WindowStyle Hidden
                } else {
                    foreach ($setup in $edgeUninstallers) {
                        if (Test-Path $setup) {
                            $sulevel = ('--system-level', '--user-level')[$setup -like '*\AppData\Local\*']
                            Start-Process -Wait $setup -ArgumentList "--uninstall --msedge $sulevel --channel=stable --verbose-logging --force-uninstall --delete-profile"
                        }
                    }
                }
                if ($created) { Remove-Item "$edgeUWP\MicrosoftEdge.exe" -Force -EA 0 }
                $fail = Edge-Installed
            }
            2 {
                Kill-EdgeProcesses
                # Delete windir temporarily
                $envPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
                try {
                    Set-ItemProperty -Path $envPath -Name 'windir' -Value '' -Type ExpandString -Force -ErrorAction SilentlyContinue
                    $env:windir = ''
                    if ($uninstallPath) {
                        Start-Process -Wait -FilePath $uninstallPath -ArgumentList "$uninstallArgs --force-uninstall --delete-profile" -WindowStyle Hidden
                    } else {
                        foreach ($setup in $edgeUninstallers) {
                            if (Test-Path $setup) {
                                $sulevel = ('--system-level', '--user-level')[$setup -like '*\AppData\Local\*']
                                Start-Process -Wait $setup -ArgumentList "--uninstall --msedge $sulevel --channel=stable --verbose-logging --force-uninstall --delete-profile"
                            }
                        }
                    }
                } finally {
                    Set-ItemProperty -Path $envPath -Name 'windir' -Value '%SystemRoot%' -Type ExpandString -Force -ErrorAction SilentlyContinue
                }
                $fail = Edge-Installed
            }
            3 {
                Kill-EdgeProcesses
                # Toggle EEA region
                $geoKey = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International\Geo'
                try {
                    Rename-ItemProperty -Path $geoKey -Name 'Name' -NewName 'NameEdgeSaved' -Force -ErrorAction SilentlyContinue
                    Rename-ItemProperty -Path $geoKey -Name 'Nation' -NewName 'NationEdgeSaved' -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $geoKey -Name 'Name' -Value 'FR' -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $geoKey -Name 'Nation' -Value '84' -Force -ErrorAction SilentlyContinue

                    if ($uninstallPath) {
                        Start-Process -Wait -FilePath $uninstallPath -ArgumentList "$uninstallArgs --force-uninstall --delete-profile" -WindowStyle Hidden
                    } else {
                        foreach ($setup in $edgeUninstallers) {
                            if (Test-Path $setup) {
                                $sulevel = ('--system-level', '--user-level')[$setup -like '*\AppData\Local\*']
                                Start-Process -Wait $setup -ArgumentList "--uninstall --msedge $sulevel --channel=stable --verbose-logging --force-uninstall --delete-profile"
                            }
                        }
                    }
                } finally {
                    Remove-ItemProperty -Path $geoKey -Name 'Name' -Force -EA 0
                    Remove-ItemProperty -Path $geoKey -Name 'Nation' -Force -EA 0
                    Rename-ItemProperty -Path $geoKey -Name 'NameEdgeSaved' -NewName 'Name' -Force -EA 0
                    Rename-ItemProperty -Path $geoKey -Name 'NationEdgeSaved' -NewName 'Nation' -Force -EA 0
                }
                $fail = Edge-Installed
            }
            4 {
                Kill-EdgeProcesses
                # Modify IntegratedServicesRegionPolicySet
                $sys32 = [Environment]::GetFolderPath('System')
                $integratedServicesPath = "$sys32\IntegratedServicesRegionPolicySet.json"
                $cleanup = $false
                if (Test-Path $integratedServicesPath) {
                    try {
                        $acl = Get-Acl -Path $integratedServicesPath
                        $backup = [System.Security.AccessControl.FileSecurity]::new()
                        $backup.SetSecurityDescriptorSddlForm($acl.Sddl)
                        $admin = [System.Security.Principal.NTAccount]$(New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
                        $acl.SetOwner($admin)
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($admin, 'FullControl', 'Allow')
                        $acl.AddAccessRule($rule)
                        Set-Acl -Path $integratedServicesPath -AclObject $acl

                        $integratedServices = Get-Content $integratedServicesPath | ConvertFrom-Json
                        ($integratedServices.policies | Where-Object { ($_.'$comment' -like '*Edge*') -and ($_.'$comment' -like '*uninstall*') }).defaultState = 'enabled'
                        $modifiedJson = $integratedServices | ConvertTo-Json -Depth 100
                        $backupName = "IntegratedServicesRegionPolicySet.json.$([System.IO.Path]::GetRandomFileName())"
                        Rename-Item $integratedServicesPath -NewName $backupName -Force
                        Set-Content $integratedServicesPath -Value $modifiedJson -Force -Encoding UTF8
                        $cleanup = $true

                        if ($uninstallPath) {
                            Start-Process -Wait -FilePath $uninstallPath -ArgumentList "$uninstallArgs --force-uninstall --delete-profile" -WindowStyle Hidden
                        } else {
                            foreach ($setup in $edgeUninstallers) {
                                if (Test-Path $setup) {
                                    $sulevel = ('--system-level', '--user-level')[$setup -like '*\AppData\Local\*']
                                    Start-Process -Wait $setup -ArgumentList "--uninstall --msedge $sulevel --channel=stable --verbose-logging --force-uninstall --delete-profile"
                                }
                            }
                        }
                        if ($cleanup) {
                            Remove-Item $integratedServicesPath -Force -EA 0
                            Rename-Item "$sys32\$backupName" -NewName $integratedServicesPath -Force -EA 0
                            Set-Acl -Path $integratedServicesPath -AclObject $backup
                        }
                    } catch {
                        Write-Log '-' "Method 4 failed: $_"
                    }
                }
                $fail = Edge-Installed
            }
            default {
                Write-Log '-' 'All uninstall methods failed — Edge may be partially removed.'
                $fail = $false
            }
        }
        $method++
    }

    if (-not (Edge-Installed)) {
        Write-Log '+' 'Edge Chromium uninstalled successfully.'
    }
}

# ============================================
# CLEANUP — Files, Registry, Services, Tasks
# ============================================

function Remove-EdgeServices {
    Write-Log '+' 'Removing Edge services...'
    @('edgeupdate', 'edgeupdatem', 'MicrosoftEdgeElevationService') | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
            sc.exe delete $_ | Out-Null
            Write-Log '+' "Service removed: $_"
        }
    }
}

function Remove-EdgeFiles {
    Write-Log '+' 'Removing Edge files and folders...'
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
    $paths | ForEach-Object { Delete-IfExists $_ }

    # Per-user Edge data
    Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $userEdge = Join-Path $_.FullName 'AppData\Local\Microsoft\Edge'
        $userEdgeUpdate = Join-Path $_.FullName 'AppData\Local\Microsoft\EdgeUpdate'
        if (Test-Path $userEdge) { Delete-IfExists $userEdge; Write-Log '+' "Removed: $userEdge" }
        if (Test-Path $userEdgeUpdate) { Delete-IfExists $userEdgeUpdate; Write-Log '+' "Removed: $userEdgeUpdate" }
    }
}

function Remove-EdgeScheduledTasks {
    Write-Log '+' 'Removing Edge scheduled tasks...'
    Get-ScheduledTask | Where-Object { $_.TaskName -like '*MicrosoftEdgeUpdate*' } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log '+' "Removed scheduled task: $($_.TaskName)"
    }
    Get-ScheduledTask -TaskPath '\Microsoft\EdgeUpdate\' -ErrorAction SilentlyContinue | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath '\Microsoft\EdgeUpdate\' -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log '+' "Removed scheduled task: $($_.TaskName)"
    }
}

function Remove-EdgeRegistry {
    Write-Log '+' 'Removing Edge registry keys and values...'

    # Delete values
    $valueDeletes = @(
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMigratedBrowserPin' }
        @{ Path = 'HKLM:\SOFTWARE\RegisteredApplications'; Name = 'Microsoft Edge' }
        @{ Path = 'HKCR\.htm\OpenWithProgIds'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.html\OpenWithProgIds'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.shtml\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.svg\OpenWithProgIds'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.xht\OpenWithProgIds'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.xhtml\OpenWithProgIds'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.webp\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCR\.xml\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'; Name = 'MSEdgeHTM_microsoft-edge' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main\EnterpriseMode'; Name = 'MSEdgePath' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'Microsoft Edge Update' }
        @{ Path = 'HKCU:\SOFTWARE\RegisteredApplications'; Name = 'Microsoft Edge' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.htm\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.html\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.shtml\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.svg\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.xht\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.xhtml\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Classes\.webp\OpenWithProgids'; Name = 'MSEdgeHTM' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'; Name = 'MSEdgeHTM_microsoft-edge' }
    )
    foreach ($v in $valueDeletes) {
        if (Test-Path $v.Path) { Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue }
    }

    # Per-user Run registry cleanup
    $sidRegex = '^S-1-5-21-'
    Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $sidRegex } | ForEach-Object {
        $runPath = "HKU:\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runPath) {
            Remove-ItemProperty -LiteralPath $runPath -Name 'Microsoft Edge Update' -Force -ErrorAction SilentlyContinue
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
        if (Test-Path $k) { Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue; Write-Log '+' "Removed key: $k" }
    }
}

function Remove-EdgeAppX {
    Write-Log '+' 'Removing Edge AppX packages...'
    Get-AppxPackage -AllUsers 'Microsoft.MicrosoftEdge.Stable*' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers 'Microsoft.MicrosoftEdgeDevToolsClient*' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    try {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Microsoft.MicrosoftEdge*' } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    } catch {
        Write-Log '-' 'AppX provisioned package scan skipped (TrustedInstaller context)'
    }
}

function Remove-IEPackage {
    Write-Log '+' 'Removing Internet Explorer system package...'
    try {
        # Dynamic query — the hardcoded build (10.0.22621.1) silently no-ops on 24H2/25H2
        Get-WindowsPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like '*Microsoft-Windows-Internet-Browser*' } |
            Remove-WindowsPackage -Online -NoRestart -ErrorAction SilentlyContinue
    } catch {}
}

# ============================================
# EDGEUPDATE POLICIES (prevent reinstall)
# ============================================

function Set-EdgeUpdatePolicies {
    Write-Log '+' 'Setting EdgeUpdate policies to prevent reinstall...'
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

    # Other Edge-blocking policies
    Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\EdgeUI' -Name 'DisableMFUTracking' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\MicrosoftEdge\Main' -Name 'AllowPrelaunch' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\Software\OEM\MicrosoftEdge' -Name 'AutoLaunchOnLogonBehavior' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

function Uninstall-EdgeUpdate {
    Write-Log '+' 'Removing EdgeUpdate...'

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" -Name 'NoRemove' -ErrorAction SilentlyContinue | Out-Null

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    if (Test-Path $registryPath) {
        $uninstallCmdLine = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).UninstallCmdLine
        if (-not [string]::IsNullOrEmpty($uninstallCmdLine)) {
            Write-Log '+' "Uninstalling: $uninstallCmdLine"
            Start-Process cmd.exe "/c $uninstallCmdLine" -WindowStyle Hidden -Wait
        } else {
            Write-Log '-' 'Cannot find uninstall methods for EdgeUpdate'
        }
    }
}

# ============================================
# INSTALL — Edge and WebView2 (from RemoveEdge.ps1)
# ============================================

function Install-EdgeChromium {
    Write-Log '+' 'Installing Microsoft Edge Chromium...'

    # Internet check
    if (-not (Test-Connection 'microsoft.com' -Count 1 -EA 0)) {
        Write-Log '-' 'No internet connection — cannot install Edge'
        return
    }

    $temp = Join-Path $([System.IO.Path]::GetTempPath()) $(New-Guid)
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $msi = "$temp\edge.msi"
    $msiLog = "$temp\edgeMsi.log"

    $archString = if ([Environment]::Is64BitOperatingSystem) {
        $arm = ((Get-CimInstance -Class Win32_ComputerSystem).SystemType -match 'ARM64') -or ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
        ('x64', 'arm64')[$arm]
    } else { 'x86' }

    try {
        $edgeUpdateApi = (Invoke-WebRequest 'https://edgeupdates.microsoft.com/api/products' -UseBasicParsing).Content | ConvertFrom-Json
        $edgeItem = ($edgeUpdateApi | Where-Object { $_.Product -eq 'Stable' }).Releases |
            Where-Object { $_.Platform -eq 'Windows' -and $_.Architecture -eq $archString } |
            Where-Object { $_.Artifacts.Count -ne 0 } | Select-Object -First 1

        if ($null -eq $edgeItem) { Write-Log '-' 'No matching Edge artifacts found from API'; return }

        $link = $edgeItem.Artifacts.Location | Select-Object -First 1
        $version = $edgeItem.ProductVersion | Select-Object -First 1
        $sizeInMb = [math]::round(($edgeItem.Artifacts.SizeInBytes | Select-Object -First 1) / 1Mb)

        Write-Log '+' "Downloading Edge $version ($sizeInMb MB)..."
        if ($null -eq (Get-Command curl.exe -EA 0)) {
            Invoke-WebRequest -Uri $link -Output $msi -UseBasicParsing
        } else {
            curl.exe -#L "$link" -o "$msi"
        }

        Write-Log '+' 'Installing Edge (this may take a moment)...'
        Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msi`" /l `"$msiLog`" /quiet" -Wait

        if ((Get-Content $msiLog -EA 0) -match 'Product: Microsoft Edge -- .* completed successfully') {
            Write-Log '+' 'Microsoft Edge installed successfully.'
        } else {
            Write-Log '-' 'Edge install may have failed — check the log'
        }
    } catch {
        Write-Log '-' "Edge install failed: $_"
    } finally {
        if (Test-Path $temp) { Remove-Item $temp -Recurse -Force -EA 0 }
        if (Test-Path $msiLog) { Remove-Item $msiLog -Force -EA 0 }
    }
}

function Install-WebView2 {
    Write-Log '+' 'Installing Microsoft Edge WebView2...'

    if (-not (Test-Connection 'microsoft.com' -Count 1 -EA 0)) {
        Write-Log '-' 'No internet connection — cannot install WebView2'
        return
    }

    $dlPath = "$(Join-Path $([System.IO.Path]::GetTempPath()) $(New-Guid))-webview2.exe"
    $link = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'

    try {
        Write-Log '+' 'Downloading Edge WebView2...'
        if ($null -eq (Get-Command curl.exe -EA 0)) {
            Invoke-WebRequest -Uri $link -Output $dlPath -UseBasicParsing
        } else {
            curl.exe -Ls "$link" -o "$dlPath"
        }

        Write-Log '+' 'Installing Edge WebView2...'
        Start-Process -FilePath "$dlPath" -ArgumentList '/silent /install' -Wait
        Write-Log '+' 'Edge WebView2 installed successfully.'
    } catch {
        Write-Log '-' "WebView2 install failed: $_"
    } finally {
        if (Test-Path $dlPath) { Remove-Item $dlPath -Force -EA 0 }
    }
}

# ============================================
# MODE DISPATCHERS
# ============================================

function Invoke-EdgeBrowser {
    Remove-EdgeChromium
    Remove-EdgeFiles
    Remove-EdgeRegistry
    Remove-EdgeScheduledTasks
    Remove-EdgeAppX

    # Remove desktop/start menu shortcuts
    @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Edge.lnk"
    ) | ForEach-Object { Delete-IfExists $_ }
}

function Invoke-Full {
    Write-Log '+' '=== Edge Full Removal ==='
    Invoke-EdgeBrowser
    Remove-EdgeServices
    Uninstall-EdgeUpdate
    Set-EdgeUpdatePolicies
    Remove-IEPackage
    Write-Log '+' '=== Edge Full Removal Complete ==='
}

# ============================================
# MAIN DISPATCH
# ============================================

switch ($Mode) {
    'EdgeBrowser' { Invoke-EdgeBrowser }
    'EdgeUpdate'  { Uninstall-EdgeUpdate }
    'Full'        { Invoke-Full }
    'Install'     { Install-EdgeChromium }
    'WebView2'    { Install-WebView2 }
    default       { Write-Log '-' "Invalid mode: $Mode" }
}

exit 0
