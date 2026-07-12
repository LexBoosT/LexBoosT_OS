<# :
@echo off &pushd "%~dp0"
@set batch_args=%*
@powershell "iex (cat -Raw '%~f0')"
@exit /b %ERRORLEVEL%
: #>

# 1. Kill OneDrive processes before anything else
@("OneDrive", "OneDrive.App") | ForEach-Object {
    $processes = Get-Process -Name $_ -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "Killing process: $_"
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# 2. Discover and run OneDrive uninstallers
$setupPaths = @(
    "$env:systemroot\System32\OneDriveSetup.exe",
    "$env:systemroot\SysWOW64\OneDriveSetup.exe"
)
$uninstallArguments = "/uninstall"

function Get-UninstallExecutablePath {
    param([string]$UninstallString)

    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        return $null
    }

    $value = $UninstallString.Trim()
    $match = [regex]::Match($value, '^\s*"([^"]+\.exe)"')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    $match = [regex]::Match($value, '^\s*([^\s]+\.exe)')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $null
}

$uninstallRegPaths = New-Object System.Collections.ArrayList
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
$users = Get-ChildItem 'HKU:\'

foreach ($user in $users) {
    $sid = $user.PSChildName
    if (-not (Test-Path "HKU:\$sid\Volatile Environment")) { continue }

    # Collect custom uninstall paths
    $regPath = "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
    $uninstallString = (Get-ItemProperty -Path $regPath -EA SilentlyContinue).UninstallString
    if (!([string]::IsNullOrEmpty($uninstallString))) {
        $uninstallFilePath = Get-UninstallExecutablePath -UninstallString $uninstallString
        if (!([string]::IsNullOrEmpty($uninstallFilePath))) {
            [void]$uninstallRegPaths.Add($uninstallFilePath)
        }
    }

    # --- Per-user registry cleanup ---
    Remove-ItemProperty -Path "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -EA SilentlyContinue
    Remove-ItemProperty -Path "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -EA SilentlyContinue
    Remove-ItemProperty -Path "HKU:\$sid\Environment" -Name "OneDrive" -EA SilentlyContinue

    Remove-Item -Path "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe" -Recurse -Force -EA SilentlyContinue
    Remove-Item -Path "HKU:\$sid\Software\Microsoft\OneDrive" -Recurse -Force -EA SilentlyContinue
    Remove-Item -Path "HKU:\$sid\Software\WOW6432Node\Microsoft\OneDrive" -Recurse -Force -EA SilentlyContinue
    Remove-Item -Path "HKU:\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -EA SilentlyContinue

    # Remove OneDrive from Explorer sidebar per-user CLSID
    [microsoft.win32.registry]::SetValue("HKEY_USERS\$sid\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "System.IsPinnedToNameSpaceTree", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
    [microsoft.win32.registry]::SetValue("HKEY_USERS\$sid\SOFTWARE\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "System.IsPinnedToNameSpaceTree", 0, [Microsoft.Win32.RegistryValueKind]::DWord)

    # Deep registry scan: BannerStore, AutoplayHandlers, App Paths
    $scanRoots = @(
        "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\BannerStore",
        "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers\Handlers",
        "HKU:\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
    )
    foreach ($root in $scanRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*OneDrive*" } | ForEach-Object {
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- System-wide registry cleanup ---
# SyncRootManager entries
$syncRootManagerPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager"
Get-ChildItem -Path $syncRootManagerPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*OneDrive*" } | ForEach-Object {
    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
}

# BannerStore (HKLM native + WOW6432Node)
$bannerStorePaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\BannerStore",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\BannerStore"
)
foreach ($bs in $bannerStorePaths) {
    if (Test-Path $bs) {
        Get-ChildItem -Path $bs -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# System-wide CLSID (HKCR)
[microsoft.win32.registry]::SetValue("HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "System.IsPinnedToNameSpaceTree", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
[microsoft.win32.registry]::SetValue("HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "System.IsPinnedToNameSpaceTree", 0, [Microsoft.Win32.RegistryValueKind]::DWord)

# 3. Group Policy to disable OneDrive (prevents reinstall)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# 4. Run uninstallers
if ($uninstallRegPaths.Count -ne 0) {
    $setupPaths = @($uninstallRegPaths) + $setupPaths
}

$setupPaths | ForEach-Object {
    if (![string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf)) {
        Write-Host "Uninstalling OneDrive from $_"
        Start-Process -FilePath $_ -ArgumentList $uninstallArguments -Wait -NoNewWindow
    }
}

# 5. Delete OneDrive folders and files
# System-wide folders
@(
    "$env:ProgramData\Microsoft OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
) | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "Removing folder: $_"
        Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# System-wide Start Menu shortcuts
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
}

# Per-user folders and shortcuts
Get-ChildItem -Path "$env:SystemDrive\Users" -Directory | ForEach-Object {
    # AppData OneDrive with shell extension unregistration
    $oneDrivePath = Join-Path $_.FullName "AppData\Local\Microsoft\OneDrive"
    if (Test-Path $oneDrivePath) {
        Get-ChildItem -LiteralPath $oneDrivePath -Recurse -Filter 'FileSyncShell*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "Unregistering shell extension: $($_.FullName)"
            regsvr32 /u /s "$($_.FullName)"
        }
        Remove-Item -Path $oneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Per-user OneDrive* shortcuts
    Get-ChildItem "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }

    # User OneDrive folder
    $oneDriveUserFolder = Join-Path $_.FullName "OneDrive"
    if (Test-Path $oneDriveUserFolder) {
        Remove-Item -Path $oneDriveUserFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 6. Remove OneDrive scheduled tasks
Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "OneDrive*" } | ForEach-Object {
    Write-Host "Removing scheduled task: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
