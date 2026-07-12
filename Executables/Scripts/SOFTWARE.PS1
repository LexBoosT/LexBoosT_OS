#Requires -RunAsAdministrator

param ([string[]]$Software)
if ($Host.Version.Major -eq 5) { $Script:ProgressPreference = "SilentlyContinue" }

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Test-InstalledApplication {
    param ([string[]]$DisplayNamePatterns)

    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($root in $uninstallRoots) {
        $apps = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            foreach ($pattern in $DisplayNamePatterns) {
                if ($app.DisplayName -like $pattern) {
                    return $true
                }
            }
        }
    }

    return $false
}

function Save-BrowserInstaller {
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int64]$MinimumBytes = 262144
    )

    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log '-' "Failed to download ${Name}: $($_.Exception.Message)"
        return $false
    }

    $installer = Get-Item -LiteralPath $OutFile -ErrorAction SilentlyContinue
    if (-not $installer -or $installer.Length -lt $MinimumBytes) {
        Write-Log '-' "Downloaded ${Name} installer is missing or incomplete."
        return $false
    }

    return $true
}

function Get-LatestVivaldiInstallerUrl {
    $downloadPage = "https://vivaldi.com/download/"

    try {
        $content = (Invoke-WebRequest -Uri $downloadPage -UseBasicParsing -ErrorAction Stop).Content
    }
    catch {
        Write-Log '-' "Failed to read Vivaldi download page: $($_.Exception.Message)"
        return $null
    }

    $match = [regex]::Match($content, 'https://downloads\.vivaldi\.com/stable/Vivaldi\.[^"'']+\.x64\.exe')
    if (-not $match.Success) {
        Write-Log '-' "Failed to find the Vivaldi x64 installer URL."
        return $null
    }

    return $match.Value
}

function Invoke-BrowserInstaller {
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$SuccessExitCodes = @(0, 3010)
    )

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -Wait -ErrorAction Stop
    }
    catch {
        Write-Log '-' "Failed to start ${Name} installer: $($_.Exception.Message)"
        return $false
    }

    $exitCode = if ($null -ne $process.ExitCode) { [int]$process.ExitCode } else { 0 }
    if ($exitCode -notin $SuccessExitCodes) {
        Write-Log '-' "${Name} installer returned exit code: $exitCode"
        return $false
    }

    return $true
}

function Stop-BrowserProcesses {
    param ([string[]]$Names)

    foreach ($name in $Names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Install-Browser {
    [CmdletBinding()]
    param (
        [switch]$Brave,
        [switch]$Vivaldi,
        [switch]$Firefox,
        [switch]$Chrome,
        [switch]$OperaGX,
        [switch]$Zen
    )

    $tempDir = $env:TEMP

    switch ($true) {
        # ===========================
        # Brave Browser
        # ===========================
        $Brave {
            Write-Host "--- Install Brave Browser ---" -F Green
            Write-Host "Silent installation of the latest Brave release`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Brave*")) {
                Write-Log '+' "Brave is already installed. Skipping."
                return
            }

            $exeName = "BraveBrowserStandaloneSilentSetup.exe"
            $fullExePath = Join-Path $tempDir $exeName

            # === Download ===
            Write-Log '+' "Downloading Brave..."
            $src = "https://github.com/brave/brave-browser/releases/latest/download/BraveBrowserStandaloneSilentSetup.exe"
            if (-not (Save-BrowserInstaller -Name "Brave" -Url $src -OutFile $fullExePath -MinimumBytes 1048576)) { return }

            # === Installation ===
            Write-Log '+' "Installing Brave..."
            if (-not (Invoke-BrowserInstaller -Name "Brave" -FilePath $fullExePath)) { return }
            Stop-BrowserProcesses -Names @("brave")
            Write-Log '+' "`nDone."
        }

        # ===========================
        # Vivaldi Browser
        # ===========================
        $Vivaldi {
            Write-Host "--- Install Vivaldi ---" -F Green
            Write-Host "Silent installation of the latest Vivaldi browser`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Vivaldi*")) {
                Write-Log '+' "Vivaldi is already installed. Skipping."
                return
            }

            $srcUrl = Get-LatestVivaldiInstallerUrl
            if (-not $srcUrl) { return }

            $exeName = Split-Path -Path $srcUrl -Leaf
            $fullExePath = Join-Path $tempDir $exeName

            # === Download ===
            Write-Log '+' "Downloading Vivaldi..."
            if (-not (Save-BrowserInstaller -Name "Vivaldi" -Url $srcUrl -OutFile $fullExePath -MinimumBytes 52428800)) { return }

            # === Installation ===
            Write-Log '+' "Installing Vivaldi..."
            $installArgs = @("--vivaldi-silent", "--do-not-launch-chrome", "--system-level")
            if (-not (Invoke-BrowserInstaller -Name "Vivaldi" -FilePath $fullExePath -ArgumentList $installArgs)) { return }
            Stop-BrowserProcesses -Names @("vivaldi")
            Write-Log '+' "`nDone."
        }

        # ===========================
        # Chrome Browser
        # ===========================
        $Chrome {
            Write-Host "--- Install Google Chrome ---" -F Green
            Write-Host "Silent installation of Google Chrome`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Google Chrome*")) {
                Write-Log '+' "Google Chrome is already installed. Skipping."
                return
            }

            $srcUrl = 'https://dl.google.com/chrome/install/latest/chrome_installer.exe'
            $exeName = "ChromeStandaloneSetup64.exe"
            $fullExePath = Join-Path $tempDir $exeName
            Write-Log '+' "Downloading Chrome..."
            if (-not (Save-BrowserInstaller -Name "Chrome" -Url $srcUrl -OutFile $fullExePath -MinimumBytes 262144)) { return }

            # === Installation ===
            Write-Log '+' "Installing Chrome..."
            $installArgs = @("/silent", "/install")
            if (-not (Invoke-BrowserInstaller -Name "Chrome" -FilePath $fullExePath -ArgumentList $installArgs)) { return }
            Stop-BrowserProcesses -Names @("chrome")
            Write-Log '+' "`nDone."
        }

        # ===========================
        # Firefox Browser
        # ===========================
        $Firefox {
            Write-Host "--- Install Mozilla Firefox ---" -F Green
            Write-Host "Silent installation of the latest stable Firefox`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Mozilla Firefox*")) {
                Write-Log '+' "Mozilla Firefox is already installed. Skipping."
                return
            }

            if ((Get-Culture).Name -eq "fr-FR") {
                $srcUrl = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=fr'
            }
            else {
                $srcUrl = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64'
            }
            $exeName = "FirefoxSetup.exe"
            $fullExePath = Join-Path $tempDir $exeName

            # === Download ===
            Write-Log '+' "Downloading Firefox..."
            if (-not (Save-BrowserInstaller -Name "Firefox" -Url $srcUrl -OutFile $fullExePath -MinimumBytes 1048576)) { return }

            # === Installation ===
            Write-Log '+' "Installing Firefox..."
            $installArgs = @("/S", "/MaintenanceService=false", "/PreventRebootRequired=true")
            if (-not (Invoke-BrowserInstaller -Name "Firefox" -FilePath $fullExePath -ArgumentList $installArgs)) { return }
            Write-Log '+' "`nDone."
        }

        # ===========================
        # Opera GX Browser
        # ===========================
        $OperaGX {
            Write-Host "--- Install Opera GX ---" -F Green
            Write-Host "Silent installation of the latest Opera GX`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Opera GX*", "Opera GX Stable*")) {
                Write-Log '+' "Opera GX is already installed. Skipping."
                return
            }

            $srcUrl = 'https://net.geo.opera.com/opera_gx/stable/windows'
            $exeName = "OperaGXSetup.exe"
            $fullExePath = Join-Path $tempDir $exeName

            # === Download ===
            Write-Log '+' "Downloading Opera GX..."
            if (-not (Save-BrowserInstaller -Name "Opera GX" -Url $srcUrl -OutFile $fullExePath -MinimumBytes 1048576)) { return }

            # === Installation ===
            Write-Log '+' "Installing Opera GX..."
            $installArgs = @("/silent", "/launchopera=0", "/setdefaultbrowser=0", "/allusers=1", "/personalized-content=0", "/personalized-ads=0", "/show-intro-overlay=0")
            if (-not (Invoke-BrowserInstaller -Name "Opera GX" -FilePath $fullExePath -ArgumentList $installArgs)) { return }
            Stop-BrowserProcesses -Names @("opera_gx", "opera")
            Write-Log '+' "`nDone."
        }

        # ===========================
        # Zen Browser
        # ===========================
        $Zen {
            Write-Host "--- Install Zen Browser ---" -F Green
            Write-Host "Silent installation of the latest Zen Browser`n"

            if (Test-InstalledApplication -DisplayNamePatterns @("Zen Browser*", "Zen*")) {
                Write-Log '+' "Zen Browser is already installed. Skipping."
                return
            }

            $srcUrl = 'https://github.com/zen-browser/desktop/releases/latest/download/zen.installer.exe'
            $exeName = "ZenBrowserSetup.exe"
            $fullExePath = Join-Path $tempDir $exeName

            # === Download ===
            Write-Log '+' "Downloading Zen Browser..."
            if (-not (Save-BrowserInstaller -Name "Zen Browser" -Url $srcUrl -OutFile $fullExePath -MinimumBytes 1048576)) { return }

            # === Installation ===
            Write-Log '+' "Installing Zen Browser..."
            $installArgs = @("/S")
            if (-not (Invoke-BrowserInstaller -Name "Zen Browser" -FilePath $fullExePath -ArgumentList $installArgs)) { return }
            Stop-BrowserProcesses -Names @("zen")
            Write-Log '+' "`nDone."
        }
    }
}

Get-ChildItem -Path $env:TEMP | Where-Object { $_.Name -ne 'AME' } | Remove-Item -Recurse -Force -EA 0

# ===========================
# Function call based on the argument
# ===========================
foreach ($arg in $Software) {
    switch ($arg) {

        # === Brave Browser ===
        "Install-Brave" { Install-Browser -Brave }

        # === Vivaldi Browser ===
        "Install-Vivaldi" { Install-Browser -Vivaldi }

        # === Firefox Browser ===
        "Install-Firefox" { Install-Browser -Firefox }

        # === Chrome Browser ===
        "Install-Chrome" { Install-Browser -Chrome }

        # === Opera GX Browser ===
        "Install-OperaGX" { Install-Browser -OperaGX }

        # === Zen Browser ===
        "Install-Zen" { Install-Browser -Zen }

        default {
            Write-Log '-' "Error: Invalid argument \`"$arg\`""
        }
    }
}
# Exit cleanly
exit 0
