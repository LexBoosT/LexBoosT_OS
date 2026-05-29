param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("EdgeBrowser", "EdgeUpdate")]
    [string]$Mode
)

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

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
    if (!(Test-Path -Path $registryPath)) {
        Write-Log '-' "Registry key not found: $registryPath"
        return
    }
    $uninstallCmdLine = (Get-ItemProperty -Path $registryPath).UninstallCmdLine

    if ([string]::IsNullOrEmpty($uninstallCmdLine)) {
        Write-Log '-' "Cannot find uninstall methods for $Mode"
        return
    }

    Write-Log '+' "Uninstalling: $uninstallCmdLine"
    Start-Process cmd.exe "/c $uninstallCmdLine" -WindowStyle Hidden -Wait
}

switch ($Mode) {
    "EdgeBrowser" { Uninstall-Edge }

    default { Write-Log '-' "Invalid mode: $Mode" }
}
# Exit cleanly
exit 0
