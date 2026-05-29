$DebugMode = $false

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" -Verb RunAs
    } catch { exit 1 }
    exit 0
}

$amdDriversPageUrl = "https://www.amd.com/en/support/download/drivers.html"
$tempDir = Join-Path $env:SystemRoot "Temp\AMDChipset"

$global:InstallationErrors = @()
$global:ScriptStartTime = Get-Date
$logFile = Join-Path $env:ProgramData "amd_chipset_update.log"
Set-Content -Path $logFile -Value "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] [INFO] Script started" -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message, [string]$Type = "INFO", [string]$Status)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    try {
        Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    if ($Status) {
        Write-Host "[$Status] $Message"
    } elseif ($Type -eq "ERROR") {
        Write-Host "[-] $Message"
    }
    if ($Type -eq "ERROR") {
        $global:InstallationErrors += $Message
    }
}

function Write-DebugMessage {
    param([string]$Message)
    Write-Log -Message $Message -Type "DEBUG"
    if ($DebugMode) { Write-Host " DEBUG: $Message" }
}

function Show-FinalSummary {
    $duration = (Get-Date) - $global:ScriptStartTime
    if ($global:InstallationErrors.Count -gt 0) {
        Write-Log '-' "Completed with $($global:InstallationErrors.Count) error(s). See $logFile for details."
    } else {
        Write-Log '+' "Operation completed successfully."
    }
    Write-Log "Script execution completed in $([math]::Round($duration.TotalMinutes, 2)) minutes with $($global:InstallationErrors.Count) errors"
}

function Get-AMDChipsetModel {
    $chipsetModel = $null
    $detectionMethod = $null

    # Method 1: BaseBoardProduct (desktop motherboards typically have chipset in name)
    try {
        $product = (Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "BaseBoardProduct" -ErrorAction SilentlyContinue).BaseBoardProduct
        if ($product) {
            $productUpper = $product.ToUpper()
            if ($productUpper -match "([ABX]\d{3}E?)") {
                $chipsetModel = $matches[1]
                $detectionMethod = "BaseBoardProduct"
                Write-DebugMessage "Detected AMD chipset via BaseBoardProduct: $chipsetModel"
            }
        }
    } catch {
        Write-DebugMessage "BaseBoardProduct detection failed: $($_.Exception.Message)"
    }

    # Method 2: Check CPU manufacturer via WMI (works on any AMD system)
    if (-not $chipsetModel) {
        try {
            $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cpu -and $cpu.Manufacturer -match "AMD|AuthenticAMD|Advanced Micro Devices") {
                $cpuName = $cpu.Name
                Write-DebugMessage "AMD CPU detected via WMI: $cpuName"
                if ($cpuName -match "Ryzen.*(\d)\s") {
                    $chipsetModel = "Detected"
                    $detectionMethod = "WMI-CPU"
                    Write-DebugMessage "AMD Ryzen CPU found."
                } elseif ($cpuName -match "AMD") {
                    $chipsetModel = "Detected"
                    $detectionMethod = "WMI-CPU"
                    Write-DebugMessage "AMD CPU found."
                }
            }
        } catch {
            Write-DebugMessage "WMI CPU detection failed: $($_.Exception.Message)"
        }
    }

    # Method 3: PCI Vendor ID VEN_1022 (AMD) - broad match, no description filter
    if (-not $chipsetModel) {
        try {
            $amdDevices = @()
            Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" } | ForEach-Object {
                $device = $_
                foreach ($hwid in $device.HardwareID) {
                    if ($hwid -match "PCI\\VEN_1022&DEV_([A-F0-9]{4})") {
                        $amdDevices += [PSCustomObject]@{
                            DeviceId    = $matches[1]
                            Description = $device.FriendlyName
                            InstanceId  = $device.InstanceId
                        }
                        break
                    }
                }
            }
            if ($amdDevices.Count -gt 0) {
                $chipsetModel = "Detected"
                $detectionMethod = "PCI-VEN_1022"
                Write-DebugMessage "Detected $($amdDevices.Count) AMD PCI device(s) via VEN_1022"
            }
        } catch {
            Write-DebugMessage "PCI detection failed: $($_.Exception.Message)"
        }
    }

    if ($chipsetModel) {
        return @{
            ChipsetModel    = $chipsetModel
            DetectionMethod = $detectionMethod
            Devices         = $amdDevices
        }
    }
    return $null
}

function Get-InstalledAMDChipsetVersion {
    try {
        $uninstallPaths = @(
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($path in $uninstallPaths) {
            $subkeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            if (-not $subkeys) { continue }
            foreach ($subkey in $subkeys) {
                $props = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
                $publisher = $props.Publisher
                $displayName = $props.DisplayName
                $displayVersion = $props.DisplayVersion
                if ($publisher -eq "Advanced Micro Devices, Inc." -and $displayName -like "*AMD Chipset*") {
                    Write-DebugMessage "Found installed AMD Chipset Software version: $displayVersion (from $displayName)"
                    return $displayVersion
                }
            }
        }
    } catch {
        Write-DebugMessage "Error reading installed version: $($_.Exception.Message)"
    }
    return $null
}

function Get-WebContent {
    param([string]$Url, [int]$TimeoutSec = 30)

    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }

    try {
        Write-DebugMessage "Fetching: $Url"
        $response = Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $response.Content
    } catch {
        Write-Log "Failed to fetch $Url : $($_.Exception.Message)" -Type "ERROR"
        return $null
    }
}

function Decode-HtmlEntities {
    param([string]$Text)
    $Text = $Text -replace "&#34;", '"'
    $Text = $Text -replace "&#39;", "'"
    $Text = $Text -replace "&quot;", '"'
    $Text = $Text -replace "&amp;", "&"
    $Text = $Text -replace "&#x2F;", "/"
    return $Text
}

function Extract-JsonUrls {
    param([string]$Content, [string]$FilterPattern = "chipset")

    $decoded = Decode-HtmlEntities -Text $Content
    $urlPattern = '"url"\s*:\s*"([^"]+' + [regex]::Escape($FilterPattern) + '[^"]*\.html)"'
    $matches = [regex]::Matches($decoded, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $urls = @()
    foreach ($m in $matches) {
        $url = $m.Groups[1].Value
        if ($url -notin $urls) {
            $urls += $url
        }
    }
    return $urls
}

function Extract-ExeUrl {
    param([string]$Content)

    $decoded = Decode-HtmlEntities -Text $Content

    # Priority 0: Try to extract __NEXT_DATA__ JSON (Next.js SSR)
    $nextDataMatch = [regex]::Match($decoded, '<script[^>]*id="__NEXT_DATA__"[^>]*type="application/json"[^>]*>\s*(\{.*?\})\s*</script>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $nextDataMatch.Success) {
        $nextDataMatch = [regex]::Match($decoded, '<script[^>]*id="__NEXT_DATA__"[^>]*>\s*(\{.*?\})\s*</script>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    if ($nextDataMatch.Success) {
        try {
            $nextJson = $nextDataMatch.Groups[1].Value | ConvertFrom-Json
            $jsonStr = $nextJson | ConvertTo-Json -Depth 20 -Compress
            $exeMatch = [regex]::Match($jsonStr, 'https?://[^"\\]+amd[^"\\]+chipset[^"\\]+\.exe', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($exeMatch.Success) {
                Write-DebugMessage "Found EXE via __NEXT_DATA__: $($exeMatch.Value)"
                return $exeMatch.Value
            }
            $exeMatch = [regex]::Match($jsonStr, 'https?://[^"\\]+drivers\.amd\.com[^"\\]+\.exe', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($exeMatch.Success -and $exeMatch.Value -match "chipset") {
                Write-DebugMessage "Found EXE via __NEXT_DATA__ (drivers): $($exeMatch.Value)"
                return $exeMatch.Value
            }
        } catch {
            Write-DebugMessage "__NEXT_DATA__ parsing failed: $($_.Exception.Message)"
        }
    }

    # Priority 1: "downloadUrl" or "DownloadUrl" JSON key
    foreach ($key in @("downloadUrl", "DownloadUrl", "downloadLink", "DownloadLink", "fileUrl", "FileUrl")) {
        $pattern = '"' + $key + '"\s*:\s*"([^"]+\.exe)"'
        $match = [regex]::Match($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            Write-DebugMessage "Found EXE via key '$key': $($match.Groups[1].Value)"
            return $match.Groups[1].Value
        }
    }

    # Priority 2: Any JSON "url" key with chipset .exe value
    $pattern = '"url"\s*:\s*"([^"]*chipset[^"]*\.exe)"'
    $match = [regex]::Match($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        Write-DebugMessage "Found EXE via url key: $($match.Groups[1].Value)"
        return $match.Groups[1].Value
    }

    # Priority 3: drivers.amd.com/chipset URL
    $pattern = '(https?://[^"''\s<>{}]+drivers\.amd\.com[^"''\s<>{}]+chipset[^"''\s<>{}]+\.exe)'
    $match = [regex]::Match($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        Write-DebugMessage "Found EXE via drivers.amd.com: $($match.Groups[1].Value)"
        return $match.Groups[1].Value
    }

    # Priority 4: Any amd.com .exe URL with "chipset" in path
    $pattern = '(https?://[^"''\s<>{}]+amd[^"''\s<>{}]+chipset[^"''\s<>{}]+\.exe)'
    $match = [regex]::Match($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        Write-DebugMessage "Found EXE via amd.com chipset: $($match.Groups[1].Value)"
        return $match.Groups[1].Value
    }

    # Priority 5: Any .exe URL from amd.com domain with "chipset" in path or filename
    $pattern = '(https?://[^"''\s<>{}]+amd\.[^"''\s<>{}]+\.exe)'
    $matches = [regex]::Matches($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $matches) {
        $url = $m.Groups[1].Value
        if ($url -match "amd_chipset_software" -or $url -match "/chipset") {
            Write-DebugMessage "Found EXE via chipset URL: $url"
            return $url
        }
    }

    # Priority 6: Any JSON string value that looks like an amd chipset driver .exe
    $pattern = '"(https?://[^"]*amd_chipset_software[^"]*\.exe)"'
    $match = [regex]::Match($decoded, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        Write-DebugMessage "Found EXE via amd_chipset_software pattern: $($match.Groups[1].Value)"
        return $match.Groups[1].Value
    }

    return $null
}

function Find-AMDChipsetDriver {
    param([string]$ChipsetModel)

    Write-Log '+' "Fetching AMD chipset driver information..."

    $driversPage = Get-WebContent -Url $amdDriversPageUrl
    if (-not $driversPage) {
        Write-Log "Failed to load AMD drivers page." -Type "ERROR" -Status '-'
        return $null
    }

    Write-DebugMessage "AMD drivers page loaded ($($driversPage.Length) bytes)"

    # Extract chipset URLs from JSON data
    $chipsetUrls = Extract-JsonUrls -Content $driversPage -FilterPattern "chipset"
    Write-DebugMessage "Found $($chipsetUrls.Count) chipset URLs in page data"

    if ($chipsetUrls.Count -eq 0) {
        Write-Log "Could not find any chipset page URLs." -Type "ERROR" -Status '-'
        return $null
    }

    # Also check if main drivers page contains a direct download URL
    $downloadUrl = Extract-ExeUrl -Content $driversPage

    # If not found, build a prioritized list of chipset pages to try
    if (-not $downloadUrl) {
        $pagePriority = [System.Collections.Generic.List[string]]::new()

        # 1st: laptop/mobile chipsets (for Ryzen mobile CPUs)
        foreach ($url in $chipsetUrls) {
            if ($url -match "laptop|mobile|notebook") {
                $pagePriority.Add($url)
            }
        }

        # 2nd: specific chipset model match
        if ($ChipsetModel -ne "Detected") {
            foreach ($url in $chipsetUrls) {
                if ($url -match [regex]::Escape($ChipsetModel) -and $url -notin $pagePriority) {
                    $pagePriority.Add($url)
                }
            }
        }

        # 3rd: AM5 (newest platform)
        foreach ($url in $chipsetUrls) {
            if ($url -match "/am5/" -and $url -notin $pagePriority) {
                $pagePriority.Add($url)
            }
        }

        # 4th: AM4
        foreach ($url in $chipsetUrls) {
            if ($url -match "/am4/" -and $url -notin $pagePriority) {
                $pagePriority.Add($url)
            }
        }

        # 5th: rest
        foreach ($url in $chipsetUrls) {
            if ($url -notin $pagePriority) {
                $pagePriority.Add($url)
            }
        }

        # Try each page until we find a download URL
        $maxPages = [Math]::Min(5, $pagePriority.Count)
        for ($i = 0; $i -lt $maxPages; $i++) {
            $url = $pagePriority[$i]
            Write-Log "Trying chipset page $($i+1)/$maxPages ..." -Type "INFO" -Status '+'
            Write-DebugMessage "Loading chipset page: $url"

            $chipsetPage = Get-WebContent -Url $url
            if (-not $chipsetPage) {
                Write-DebugMessage "Failed to load, skipping."
                continue
            }

            $chipsetPageUrl = $url
            $downloadUrl = Extract-ExeUrl -Content $chipsetPage
            if ($downloadUrl) {
                Write-DebugMessage "Successfully found download URL on page: $url"
                break
            }
            Write-DebugMessage "No download URL found on this page, trying next..."
        }
    } else {
        $chipsetPageUrl = $amdDriversPageUrl
    }

    if (-not $downloadUrl) {
        Write-Log "Could not find AMD chipset driver download URL." -Type "ERROR" -Status '-'
        return $null
    }

    Write-Log "Found download URL." -Type "INFO" -Status '+'

    $versionString = "Unknown"
    if ($downloadUrl -match "_(\d+[\d.]*)\.exe$") {
        $versionString = $matches[1]
    } elseif ($downloadUrl -match "/([^/]+)\.exe$") {
        $filename = $matches[1]
        $versionString = $filename -replace ".*_", ""
    }

    Write-Log "Latest version detected: $versionString" -Type "INFO" -Status '+'

    $decodedPage = Decode-HtmlEntities -Text $driversPage
    $releaseNotesMatch = [regex]::Match($decodedPage, '"([^"]*release-notes[^"]*chipset[^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    return @{
        DownloadUrl     = $downloadUrl
        Version         = $versionString
        ReleaseNotesUrl = if ($releaseNotesMatch.Success) { $releaseNotesMatch.Value -replace '"', '' } else { $null }
        ChipsetPageUrl  = $chipsetPageUrl
    }
}

function Test-FileSignature {
    param([string]$FilePath)
    try {
        Write-DebugMessage "Verifying digital signature for: $FilePath"
        $signature = Get-AuthenticodeSignature -FilePath $FilePath
        if ($signature.Status -ne "Valid") {
            Write-Log "Digital signature is not valid. Status: $($signature.Status)" -Type "ERROR" -Status '-'
            return $false
        }
        if ($signature.SignerCertificate.Subject -notmatch "Advanced Micro Devices") {
            Write-Log "File not signed by AMD. Signer: $($signature.SignerCertificate.Subject)" -Type "ERROR" -Status '-'
            return $false
        }
        Write-Log "Digitally signed by Advanced Micro Devices, Inc." -Type "INFO" -Status '+'
        Write-DebugMessage "Digital signature verification passed for $FilePath"
        return $true
    } catch {
        Write-Log "Error verifying digital signature: $($_.Exception.Message)" -Type "ERROR" -Status '-'
        return $false
    }
}

function Clear-TempFolders {
    try {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-DebugMessage "Cleaned up temporary directory: $tempDir"
        }
    } catch {
        Write-DebugMessage "Error during cleanup: $_"
    }
}

function Install-AMDChipsetDriver {
    param([string]$InstallerPath)
    try {
        if (-not (Test-Path $InstallerPath)) {
            Write-Log "Installer not found at: $InstallerPath" -Type "ERROR" -Status '-'
            return $false
        }
        Write-Log "Verifying installer digital signature..." -Type "INFO" -Status '+'
        $null = Test-FileSignature -FilePath $InstallerPath

        Write-Host ""
        Write-Host "[!] IMPORTANT NOTICE:"
        Write-Host "[!] The AMD Chipset Driver installer is now running."
        Write-Host "[!] Please DO NOT close this window or interrupt the process."
        Write-Host "[!] The system may appear unresponsive during installation - this is normal."
        Write-Host ""

        Write-Log "Running installer: $(Split-Path $InstallerPath -Leaf)" -Type "INFO" -Status '+'

        $process = Start-Process -FilePath $InstallerPath -ArgumentList "-INSTALL" -Wait -PassThru

        Write-DebugMessage "Installer exit code: $($process.ExitCode)"

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "AMD Chipset drivers installed successfully." -Type "INFO" -Status '+'
            if ($process.ExitCode -eq 3010) {
                Write-Log "(Reboot required to complete installation)" -Type "INFO" -Status '+'
            }
            return $true
        } else {
            Write-Log "Installer failed with exit code: $($process.ExitCode)" -Type "ERROR" -Status '-'
            return $false
        }
    } catch {
        Write-Log "Error running installer: $_" -Type "ERROR" -Status '-'
        return $false
    }
}

function Cleanup {
    Write-Log "Cleaning up temporary files..." -Type "INFO" -Status '+'
    if (Test-Path $tempDir) {
        try {
            Get-ChildItem -Path $tempDir -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-Log "Temporary files cleaned successfully." -Type "INFO" -Status '+'
        } catch {
            Write-Log "Could not clean all temporary files." -Type "ERROR" -Status '-'
        }
    }
}

# =============================================
# MAIN SCRIPT EXECUTION
# =============================================

try {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  AMD CHIPSET DRIVER AUTOMATIC UPDATER"
    Write-Host "=============================================="
    Write-Host ""

    Clear-TempFolders
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Write-DebugMessage "Created temporary directory: $tempDir"

    Write-Log "Detecting AMD chipset..." -Type "INFO" -Status '+'
    $chipsetInfo = Get-AMDChipsetModel

    if (-not $chipsetInfo) {
        Write-Log "No AMD chipset detected on this system." -Type "ERROR" -Status '-'
        Write-Log "If you believe this is an error, please run with `$DebugMode = `$true" -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    Write-Log "AMD chipset detected: $($chipsetInfo.ChipsetModel)" -Type "INFO" -Status '+'
    Write-Log "Detection method: $($chipsetInfo.DetectionMethod)" -Type "INFO" -Status '+'

    Write-Log "Checking installed AMD chipset driver version..." -Type "INFO" -Status '+'
    $installedVersion = Get-InstalledAMDChipsetVersion

    if ($installedVersion) {
        Write-Log "Installed version: $installedVersion" -Type "INFO" -Status '+'
    } else {
        Write-Log "No installed AMD Chipset Software found." -Type "INFO" -Status '+'
    }

    Write-Log "Searching for latest AMD chipset driver..." -Type "INFO" -Status '+'
    $driverInfo = Find-AMDChipsetDriver -ChipsetModel $chipsetInfo.ChipsetModel

    if (-not $driverInfo) {
        Write-Log "Failed to find AMD chipset driver." -Type "ERROR" -Status '-'
        Write-Log "Could not locate the latest chipset driver on AMD website." -Type "ERROR" -Status '-'
        Write-Log "Please check your internet connection and try again." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    $needsUpdate = $true
    if ($installedVersion -and $driverInfo.Version -and $driverInfo.Version -ne "Unknown") {
        try {
            if ([version]$installedVersion -ge [version]$driverInfo.Version) {
                $needsUpdate = $false
                Write-Log "Your AMD chipset drivers are already up to date." -Type "INFO" -Status '+'
                Write-Log "Installed: $installedVersion | Latest: $($driverInfo.Version)" -Type "INFO" -Status '+'
            }
        } catch {
            Write-DebugMessage "Version comparison failed, proceeding with update."
        }
    }

    if (-not $needsUpdate) {
        Write-Log "Forcing reinstall anyway..." -Type "INFO" -Status '+'
    }

    if ($driverInfo.ReleaseNotesUrl) {
        Write-Log "Release notes: $($driverInfo.ReleaseNotesUrl)" -Type "INFO" -Status '+'
    }

    $restorePointDescription = "Before AMD Chipset Driver Update - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")"
    try {
        $null = Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    } catch {
        Write-DebugMessage "System restore might already be enabled."
    }

    try {
        $warningMessages = @()
        Checkpoint-Computer -Description $restorePointDescription -RestorePointType "MODIFY_SETTINGS" -WarningVariable warningMessages -WarningAction SilentlyContinue -ErrorAction Stop
        if ($warningMessages.Count -gt 0) {
            $warningText = $warningMessages -join " "
            if ($warningText -match "1440 minutes" -or $warningText -match "past.*minutes") {
                throw "RestorePointFrequencyLimit"
            }
        }
        Write-Log "System restore point created." -Type "INFO" -Status '+'
        Write-DebugMessage "Restore point: $restorePointDescription"
    } catch {
        Write-DebugMessage "Restore point creation skipped: $($_.Exception.Message)"
    }

    Write-Log "Downloading AMD chipset driver..." -Type "INFO" -Status '+'
    Write-Log "URL: $($driverInfo.DownloadUrl)" -Type "INFO" -Status '+'

    $installerPath = Join-Path $tempDir "amd_chipset_software.exe"

    try {
        $dlHeaders = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            "Referer"    = "https://www.amd.com/"
        }
        Invoke-WebRequest -Uri $driverInfo.DownloadUrl -Headers $dlHeaders -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        Write-Log "Download completed: $installerPath" -Type "INFO" -Status '+'

        $fileSize = (Get-Item -LiteralPath $installerPath).Length
        Write-Log "File size: $([math]::Round($fileSize/1MB, 2)) MB" -Type "INFO" -Status '+'
        if ($fileSize -lt 1MB) {
            Write-Log "Downloaded file is too small ($fileSize bytes). Likely not a valid installer." -Type "ERROR" -Status '-'
            Cleanup
            exit 1
        }
    } catch {
        Write-Log "Download failed: $($_.Exception.Message)" -Type "ERROR" -Status '-'
        Write-Log "Failed to download the driver installer." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    $installSuccess = Install-AMDChipsetDriver -InstallerPath $installerPath

    Cleanup

    if ($installSuccess) {
        Write-Log "AMD Chipset driver installation completed successfully." -Type "INFO" -Status '+'
        Write-Host ""
        Write-Host "[+] ============================================="
        Write-Host "[+] AMD Chipset Driver Update Completed!"
        Write-Host "[+] A system reboot is recommended."
        Write-Host "[+] ============================================="
    } else {
        Write-Log "AMD Chipset driver installation failed." -Type "ERROR" -Status '-'
    }

    Show-FinalSummary
    exit 0
} catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Type "ERROR" -Status '-'
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Type "ERROR" -Status '-'
    Cleanup
    exit 1
}
