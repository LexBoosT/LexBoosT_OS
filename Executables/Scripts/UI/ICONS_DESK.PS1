#Requires -Version 5.0

[CmdletBinding()]
param()

# ============================================================================
# Constants and Configuration
# ============================================================================

# Registry Keys
$script:REG_HIDE_DESKTOP_ICONS_HKLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
$script:REG_HIDE_DESKTOP_ICONS_HKCU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
$script:REG_CONTENT_DELIVERY = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"

# CLSIDs for desktop icons
$script:CLSID_THIS_PC = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
$script:CLSID_USER_FOLDER = "{59031a47-3f72-44a7-89c5-5595fe6b30ee}"

# Paths
$script:LEXBOOST_ROOT = "$env:WINDIR\LexBoosTOS"
$script:LEXBOOST_OTHER = Join-Path $script:LEXBOOST_ROOT "Resources\Icons"
$script:DESKTOP_PATH = [Environment]::GetFolderPath("Desktop")

# URLs and external links
$script:SUPPORT_URL = "https://ko-fi.com/lexboostdev"

# ============================================================================
# Utility Functions
# ============================================================================

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $mark = switch ($Level) {
        "Warning" { "[-]" }
        "Error"   { "[-]" }
        default   { "[+]" }
    }

    Write-Host "$mark $Message"
}

function Set-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $false)]
        [ValidateSet("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString")]
        [string]$Type = "DWord"
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            Write-LogMessage "Created registry key: $Path" -Level Info
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        Write-LogMessage "Set registry value: $Path\$Name = $Value" -Level Success
    }
    catch {
        Write-LogMessage "Failed to set registry value $Path\$Name : $($_.Exception.Message)" -Level Error
        return $false
    }

    return $true
}

function New-DesktopShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutName,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = "",

        [Parameter(Mandatory = $false)]
        [string]$IconLocation = "",

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$Arguments = ""
    )

    $shortcutPath = Join-Path -Path $script:DESKTOP_PATH -ChildPath "$ShortcutName.lnk"
    $wshShell = $null
    $shortcut = $null

    try {
        # Validate target exists (unless it's a URL)
        if ($TargetPath -notmatch "^https?://" -and -not (Test-Path $TargetPath)) {
            throw "Target path does not exist: $TargetPath"
        }

        # Validate icon exists if specified
        if ($IconLocation) {
            # Extract the file path from IconLocation (remove icon index if present)
            $iconFilePath = $IconLocation -replace ',.*$', ''
            if (-not (Test-Path $iconFilePath)) {
                Write-LogMessage "Icon file not found: $iconFilePath" -Level Warning
                $IconLocation = "" # Clear icon location if file doesn't exist
            }
        }

        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)

        $shortcut.TargetPath = $TargetPath

        if ($WorkingDirectory) {
            $shortcut.WorkingDirectory = $WorkingDirectory
        }

        if ($IconLocation) {
            $shortcut.IconLocation = $IconLocation
        }

        if ($Description) {
            $shortcut.Description = $Description
        }

        if ($Arguments) {
            $shortcut.Arguments = $Arguments
        }

        $shortcut.Save()

        Write-LogMessage "Created shortcut: $ShortcutName -> $TargetPath" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Failed to create shortcut '$ShortcutName': $($_.Exception.Message)" -Level Error
        return $false
    }
    finally {
        # Clean up COM objects
        if ($shortcut) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shortcut) | Out-Null
        }
        if ($wshShell) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wshShell) | Out-Null
        }

        # Force garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

function Test-RequiredFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$FileChecks
    )

    $allValid = $true

    foreach ($check in $FileChecks.GetEnumerator()) {
        $filePath = $check.Value
        $description = $check.Key

        if (-not (Test-Path $filePath)) {
            Write-LogMessage "Missing required file: $description - $filePath" -Level Error
            $allValid = $false
        }
    }

    return $allValid
}

function Restart-Explorer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$WaitSeconds = 3
    )

    try {
        Write-LogMessage "Stopping Explorer process..." -Level Info
        taskkill /IM "explorer.exe" /F 2>$null

        Write-LogMessage "Waiting $WaitSeconds seconds..." -Level Info
        Start-Sleep -Seconds $WaitSeconds

        # Clear icon cache files
        Write-LogMessage "Clearing icon cache..." -Level Info
        $iconCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        Get-ChildItem "$iconCachePath\iconcache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem "$iconCachePath\thumbcache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        Write-LogMessage "Starting Explorer process..." -Level Info
        Start-Process "explorer.exe"

        Start-Sleep -Seconds $WaitSeconds

        Write-LogMessage "Refreshing desktop..." -Level Info
        (New-Object -ComObject Shell.Application).Namespace(0x0).Self.InvokeVerb("Refresh")
    }
    catch {
        Write-LogMessage "Error during Explorer restart: $($_.Exception.Message)" -Level Error
    }
}

# ============================================================================
# Main Functions
# ============================================================================

function Enable-ThisPCIcon {
    [CmdletBinding()]
    param()

    Write-LogMessage "Enabling 'This PC' icon on desktop..." -Level Info

    $success = Set-RegistryValue -Path $script:REG_HIDE_DESKTOP_ICONS_HKLM -Name $script:CLSID_THIS_PC -Value 0 -Type DWord

    if ($success) {
        Write-LogMessage "'This PC' icon enabled successfully" -Level Success
    }

    return $success
}

function Enable-UserFolderIcon {
    [CmdletBinding()]
    param()

    Write-LogMessage "Enabling 'User Folder' icon on desktop..." -Level Info

    $success = Set-RegistryValue -Path $script:REG_HIDE_DESKTOP_ICONS_HKCU -Name $script:CLSID_USER_FOLDER -Value 0 -Type DWord

    if ($success) {
        Write-LogMessage "'User Folder' icon enabled successfully" -Level Success
    }

    return $success
}

function New-SupportShortcut {
    [CmdletBinding()]
    param()

    Write-LogMessage "Creating support shortcut..." -Level Info

    $iconPath = Join-Path $script:LEXBOOST_OTHER "Donate.ico"

    # Check if icon exists
    if (-not (Test-Path $iconPath)) {
        Write-LogMessage "Support icon not found: $iconPath" -Level Warning
        $iconPath = "" # Clear icon path if not found
    }

    $success = New-DesktopShortcut -ShortcutName "Support Me" -TargetPath $script:SUPPORT_URL -IconLocation $iconPath -Description "Support LexBoosT Development"

    return $success
}

function Disable-SilentAppInstallations {
    [CmdletBinding()]
    param()

    Write-LogMessage "Disabling silent app installations..." -Level Info

    $success = Set-RegistryValue -Path $script:REG_CONTENT_DELIVERY -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord

    if ($success) {
        Write-LogMessage "Silent app installations disabled" -Level Success
    }

    return $success
}

function New-LexBoosTLauncherShortcut {
    [CmdletBinding()]
    param()

    Write-LogMessage "Creating LexBoosT Launcher shortcut..." -Level Info

    $launcherPath = Join-Path $script:LEXBOOST_ROOT "LexBoosT_Launcher\LexBoost_Launcher.exe"
    $iconPath = Join-Path $script:LEXBOOST_OTHER "icon.ico"

    # Validate required files
    $fileChecks = @{
        "LexBoosT_Launcher" = $launcherPath
    }

    if (-not (Test-RequiredFiles -FileChecks $fileChecks)) {
        Write-LogMessage "Cannot create LexBoosT Launcher shortcut due to missing executable" -Level Error
        return $false
    }

    # Check if icon exists
    if (-not (Test-Path $iconPath)) {
        Write-LogMessage "LexBoosT icon not found: $iconPath" -Level Warning
        $iconPath = "" # Clear icon path if not found
    }

    $success = New-DesktopShortcut -ShortcutName "LexBoosT™ Tools Launcher" -TargetPath $launcherPath -IconLocation $iconPath -Description "Launch LexBoosT OS Applications"

    return $success
}

# ============================================================================
# Main Execution
# ============================================================================

Write-LogMessage "=== LexBoosT OS Desktop Icons Configuration ===" -Level Info
Write-LogMessage "Starting desktop icons and shortcuts setup..." -Level Info

# Enable desktop icons
$iconSuccess = $true
$iconSuccess = $iconSuccess -and (Enable-ThisPCIcon)
$iconSuccess = $iconSuccess -and (Enable-UserFolderIcon)

if ($iconSuccess) {
    Write-LogMessage "Desktop icons configured successfully" -Level Success
}
else {
    Write-LogMessage "Some desktop icons may not have been configured properly" -Level Warning
}

# Create shortcuts
$shortcutSuccess = $true
$shortcutSuccess = $shortcutSuccess -and (New-SupportShortcut)
$shortcutSuccess = $shortcutSuccess -and (New-LexBoosTLauncherShortcut)

if ($shortcutSuccess) {
    Write-LogMessage "All shortcuts created successfully" -Level Success
}
else {
    Write-LogMessage "Some shortcuts may not have been created" -Level Warning
}

# Disable silent app installations
Disable-SilentAppInstallations

Write-LogMessage "=== Desktop configuration completed ===" -Level Success
Write-LogMessage "Please check your desktop for the new icons and shortcuts." -Level Info

# Exit cleanly
exit 0
