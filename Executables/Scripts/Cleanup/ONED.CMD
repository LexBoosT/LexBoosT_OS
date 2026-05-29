<# :
@echo off &pushd "%~dp0"
@set batch_args=%*
@powershell "iex (cat -Raw '%~f0')"
@exit /b %ERRORLEVEL%
: #>

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

# $sid = (([System.Security.Principal.WindowsIdentity]::GetCurrent()).User).Value

$uninstallRegPaths = New-Object System.Collections.ArrayList
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
$users = Get-ChildItem 'HKU:\'
foreach ($user in $users) {
    if (Test-Path "HKU:\$($user.PSChildName)\Volatile Environment") {
        $regPath = "HKU:\$($user.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
        $uninstallString = (Get-ItemProperty -Path $regPath -EA SilentlyContinue).UninstallString

        if (!([string]::IsNullOrEmpty($uninstallString))) {
            $uninstallFilePath = Get-UninstallExecutablePath -UninstallString $uninstallString
            if (!([string]::IsNullOrEmpty($uninstallFilePath))) {
                $uninstallRegPaths.Add($uninstallFilePath) | Out-Null
            }
        }

        Remove-ItemProperty -Path "HKU:\$($user.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -EA SilentlyContinue

        Remove-Item -Path "HKU:\$($user.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe" -Force -EA SilentlyContinue
        Remove-Item -Path "HKU:\$($user.PSChildName)\Software\Microsoft\OneDrive" -Recurse -Force -EA SilentlyContinue
        Remove-Item -Path "HKU:\$($user.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -EA SilentlyContinue
    }
}

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

if ($uninstallRegPaths.Count -ne 0) {
    $setupPaths = @($uninstallRegPaths) + $setupPaths
}

$setupPaths | ForEach-Object {
    if (![string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf)) {
        Write-Host "Uninstalling OneDrive from $_"
        Start-Process -FilePath $_ -ArgumentList $uninstallArguments -Verbose -Wait -NoNewWindow -PassThru
    }
}

Get-ChildItem -Path "$env:SystemDrive\Users" -Directory | ForEach-Object {
    $oneDrivePath = Join-Path $_.FullName "AppData\Local\Microsoft\OneDrive"
    if (Test-Path $oneDrivePath) {
        Remove-Item -Path $oneDrivePath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $oneDriveLinkPath = Join-Path $_.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
    if (Test-Path $oneDriveLinkPath) {
        Remove-Item -Path $oneDriveLinkPath -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $oneDriveUserFolder = Join-Path $_.FullName "OneDrive"
    if (Test-Path $oneDriveUserFolder) {
        Remove-Item -Path $oneDriveUserFolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# Remove OneDrive from the Explorer sidebar
[microsoft.win32.registry]::SetValue("HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "System.IsPinnedToNameSpaceTree", 0, [Microsoft.Win32.RegistryValueKind]::DWord)

# Remove OneDrive scheduled tasks (Startup Task, Standalone Update Task)
Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "OneDrive*" } | ForEach-Object {
    Write-Host "Removing scheduled task: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
