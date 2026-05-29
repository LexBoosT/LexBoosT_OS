$DebugMode = $false

# Auto-elevate if not admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -File `"$scriptPath`"" -Verb RunAs
    } catch { exit 1 }
    exit 0
}

# GitHub repository URLs
$githubBaseUrl = "https://raw.githubusercontent.com/FirstEverTech/Universal-Intel-Chipset-Updater/main/data/"
$githubArchiveUrl = "https://github.com/FirstEverTech/Universal-Intel-Chipset-Updater/releases/download/archive/"
$chipsetINFsUrl = $githubBaseUrl + "intel-chipset-infs-latest.md"
$downloadListUrl = $githubBaseUrl + "intel-chipset-infs-download.txt"
$tempDir = Join-Path $env:SystemRoot "Temp\IntelChipset"

# =============================================
# ENHANCED ERROR HANDLING
# =============================================

$global:InstallationErrors = @()
$global:ScriptStartTime = Get-Date
$logFile = Join-Path $env:ProgramData "chipset_update.log"
Set-Content -Path $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Script started" -Force -ErrorAction SilentlyContinue

# =============================================
# VERSION MANAGEMENT FUNCTIONS
# =============================================

function Get-VersionNumber {
    param([string]$Version)

    $oldVersionTable = @{
        "10.1-2025.11.0" = "2025.11.0001"
        "10.1-2025.11.5" = "2025.11.0002"
        "10.1-2025.11.6" = "2025.11.0003"
        "10.1-2025.11.7" = "2025.11.0004"
        "10.1-2025.11.8" = "2025.11.0005"
        "10.1-2026.02.1" = "2026.02.0006"
        "10.1-2026.02.2" = "2026.02.0007"
    }

    if ($oldVersionTable.ContainsKey($Version)) {
        $Version = $oldVersionTable[$Version]
    }

    if ($Version -match '^10\.1-(\d{4}\.\d{2}\.\d+)$') {
        $Version = $matches[1]
    }

    if ($Version -match '^(\d{4})\.(\d{2})\.(\d+)$') {
        return [int]$matches[3]
    }

    throw "Cannot parse version: $Version"
}

function Compare-Versions {
    param([string]$Version1, [string]$Version2)

    $ver1Num = Get-VersionNumber -Version $Version1
    $ver2Num = Get-VersionNumber -Version $Version2

    if ($ver1Num -eq $ver2Num) { return 0 }
    if ($ver1Num -lt $ver2Num) { return -1 }
    return 1
}

function Get-VersionForFileName {
    param([string]$Version)

    if ($Version -match '^10\.1-(\d{4}\.\d{2}\.\d+)$') {
        return $matches[1]
    }
    return $Version
}

# =============================================
# LOGGING FUNCTIONS
# =============================================

function Write-Log {
    param([string]$Message, [string]$Type = "INFO", [string]$Status)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    try {
        Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silent fallback
    }

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
    param([string]$Message, [string]$Color = "Gray")
    Write-Log -Message $Message -Type "DEBUG"
    if ($DebugMode) {
        Write-Host " DEBUG: $Message"
    }
}

function Show-FinalSummary {
    $duration = (Get-Date) - $global:ScriptStartTime
    if ($global:InstallationErrors.Count -gt 0) {
        Write-Log "Completed with $($global:InstallationErrors.Count) error(s). See $logFile for details." -Type "INFO" -Status '-'
    } else {
        Write-Log "Operation completed successfully." -Type "INFO" -Status '+'
    }
    Write-Log "Script execution completed in $([math]::Round($duration.TotalMinutes, 2)) minutes with $($global:InstallationErrors.Count) errors"
}

# =============================================
# FILE INTEGRITY VERIFICATION FUNCTIONS
# =============================================

function Test-FileHash {
    param(
        [string]$FilePath,
        [string]$ExpectedHash,
        [string]$HashType = "Primary",
        [string]$OriginalFileName = $null
    )

    if (-not $ExpectedHash) {
        Write-DebugMessage "No expected $HashType hash provided, skipping verification."
        return $true
    }

    $actualHash = $null
    try {
        if (-not (Test-Path $FilePath)) {
            Write-Log "File not found for hash calculation: $FilePath" -Type "ERROR"
            return $false
        }
        $hashResult = Get-FileHash -Path $FilePath -Algorithm SHA256
        $actualHash = $hashResult.Hash
        Write-DebugMessage "Calculated SHA256 for $FilePath : $actualHash"
    } catch {
        Write-Log "Error calculating hash for $FilePath : $($_.Exception.Message)" -Type "ERROR"
        return $false
    }

    if (-not $actualHash) {
        Write-Log "Failed to calculate hash for $FilePath" -Type "ERROR"
        return $false
    }

    if ($actualHash -eq $ExpectedHash) {
        Write-DebugMessage "$HashType hash verification passed for $FilePath"
        Write-Log "$HashType hash verification passed." -Type "INFO" -Status '+'
        return $true
    } else {
        $displayName = if ($OriginalFileName) { $OriginalFileName } else { Split-Path $FilePath -Leaf }

        $errorMessage = "$HashType hash verification failed for $displayName. Source: $ExpectedHash, Actual: $actualHash"

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [ERROR] $errorMessage"
        try {
            Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
        } catch {
            # Silent fallback
        }
        $global:InstallationErrors += $errorMessage

        Write-Log "$HashType hash verification failed: $displayName" -Type "ERROR" -Status '-'
        Write-Log "Expected: $ExpectedHash" -Type "ERROR" -Status '-'
        Write-Log "Actual: $actualHash" -Type "ERROR" -Status '-'
        return $false
    }
}

# =============================================
# DIGITAL SIGNATURE VERIFICATION FUNCTIONS
# =============================================

function Test-FileSignature {
    param([string]$FilePath)

    try {
        Write-DebugMessage "Verifying digital signature for: $FilePath"

        $signature = Get-AuthenticodeSignature -FilePath $FilePath
        Write-DebugMessage "Signature status: $($signature.Status)"
        Write-DebugMessage "Signer: $($signature.SignerCertificate.Subject)"
        Write-DebugMessage "Signature Algorithm: $($signature.SignerCertificate.SignatureAlgorithm.FriendlyName)"

        if ($signature.Status -ne 'Valid') {
            Write-Log "Digital signature is not valid. Status: $($signature.Status)" -Type "ERROR" -Status '-'
            return $false
        }

        if ($signature.SignerCertificate.Subject -notmatch 'CN=Intel Corporation') {
            Write-Log "File not signed by Intel Corporation. Signer: $($signature.SignerCertificate.Subject)" -Type "ERROR" -Status '-'
            return $false
        }

        if ($signature.SignerCertificate.SignatureAlgorithm.FriendlyName -notmatch 'sha256') {
            Write-Log "Signature not using SHA256 algorithm. Algorithm: $($signature.SignerCertificate.SignatureAlgorithm.FriendlyName)" -Type "ERROR" -Status '-'
            return $false
        }

        Write-Log "Digitally signed by Intel Corporation." -Type "INFO" -Status '+'
        Write-DebugMessage "Digital signature verification passed for $FilePath"
        return $true
    } catch {
        Write-Log "Error verifying digital signature: $($_.Exception.Message)" -Type "ERROR" -Status '-'
        return $false
    }
}

# =============================================
# UPDATED PARSER FOR EXTENDED FORMAT
# =============================================

function ConvertFrom-DownloadList {
    param([string]$DownloadListContent)

    Write-DebugMessage "Starting download list parsing."
    $downloadData = @{}

    try {
        $blocks = $DownloadListContent -split "`n`n" | Where-Object { $_.Trim() }

        Write-DebugMessage "Found $($blocks.Count) blocks in download list."

        foreach ($block in $blocks) {
            $name = $null
            $infVer = $null
            $link = $null
            $prefix = $null
            $variant = "Consumer"
            $sha256 = $null
            $backup = $null
            $sha256_b = $null
            $prefix_b = $null

            $lines = $block -split "`n" | ForEach-Object { $_.Trim() }
            foreach ($line in $lines) {
                if ($line -match '^Name\s*=\s*(.+)') {
                    $name = $matches[1]
                } elseif ($line -match '^INFVer\s*=\s*[^,]+,([0-9.]+)') {
                    $infVer = $matches[1]
                } elseif ($line -match '^Link\s*=\s*(.+)') {
                    $link = $matches[1]
                } elseif ($line -match '^Prefix\s*=\s*(.+)') {
                    $prefix = $matches[1]
                } elseif ($line -match '^Variant\s*=\s*(.+)') {
                    $variant = $matches[1]
                } elseif ($line -match '^SHA256\s*=\s*([A-F0-9]+)') {
                    $sha256 = $matches[1]
                } elseif ($line -match '^Backup\s*=\s*(.+)') {
                    $backup = $matches[1]
                } elseif ($line -match '^SHA256_B\s*=\s*([A-F0-9]+)') {
                    $sha256_b = $matches[1]
                } elseif ($line -match '^Prefix_B\s*=\s*(.+)') {
                    $prefix_b = $matches[1]
                }
            }

            if ($infVer -and $link) {
                $key = "$infVer-$variant"
                $downloadData[$key] = @{
                    Name      = $name
                    INFVer    = $infVer
                    Link      = $link
                    Prefix    = $prefix
                    Variant   = $variant
                    SHA256    = $sha256
                    Backup    = $backup
                    SHA256_B  = $sha256_b
                    Prefix_B  = $prefix_b
                }
                Write-DebugMessage "Added download entry: $key -> $name"
            } else {
                Write-DebugMessage "Skipping incomplete block - missing INFVer or Link."
            }
        }

        Write-DebugMessage "Download list parsing completed. Found $($downloadData.Count) entries."
        return $downloadData
    } catch {
        Write-Log "Download list parsing failed: $($_.Exception.Message)" -Type "ERROR"
        return @{}
    }
}

# =============================================
# ENHANCED DOWNLOAD FUNCTION
# =============================================

function Save-ChipsetFile {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Prefix,
        [string]$ExpectedHash,
        [string]$SourceName = "Primary"
    )

    try {
        $tempFile = "$tempDir\temp_$(Get-Random).$([System.IO.Path]::GetExtension($Url).TrimStart('.'))"

        Write-DebugMessage "Downloading from $SourceName source: $Url to $tempFile"
        Write-Log "Downloading from $SourceName source..." -Type "INFO" -Status '+'

        $downloadSuccess = $true
        $downloadError = $null

        try {
            Invoke-WebRequest -Uri $Url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
        } catch {
            $downloadSuccess = $false
            $downloadError = $_.Exception.Message
        }

        if (-not $downloadSuccess) {
            Write-Log "Download failed for $SourceName source $Url : $downloadError" -Type "ERROR"
            return @{ Success = $false; ErrorType = "DownloadFailed"; Message = "Download failed: $downloadError" }
        }

        if (-not (Test-Path $tempFile)) {
            return @{ Success = $false; ErrorType = "DownloadFailed"; Message = "File not found after download" }
        }

        if ($ExpectedHash) {
            Write-Log "Verifying $SourceName source file integrity..." -Type "INFO" -Status '+'
            $originalFileName = [System.IO.Path]::GetFileName($Url)
            if (-not (Test-FileHash -FilePath $tempFile -ExpectedHash $ExpectedHash -HashType $SourceName -OriginalFileName $originalFileName)) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                return @{ Success = $false; ErrorType = "HashMismatch"; Message = "Hash verification failed." }
            }
        }

        $fileExtension = [System.IO.Path]::GetExtension($Url).ToLower()

        if ($fileExtension -eq '.zip') {
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $OutputPath)
                Write-Log "ZIP file extracted successfully." -Type "INFO" -Status '+'
                Write-DebugMessage "ZIP extraction successful to: $OutputPath"
            } catch {
                try {
                    Write-Log "Using COM object for ZIP extraction..." -Type "INFO" -Status '+'
                    $shell = New-Object -ComObject Shell.Application
                    $zipFolder = $shell.NameSpace($tempFile)
                    $destFolder = $shell.NameSpace($OutputPath)
                    $destFolder.CopyHere($zipFolder.Items(), 0x14)
                    Write-Log "ZIP file extracted successfully using COM." -Type "INFO" -Status '+'
                } catch {
                    Write-Log "Error extracting ZIP file: $_" -Type "ERROR"
                    return @{ Success = $false; ErrorType = "ExtractionFailed"; Message = "ZIP extraction failed.: $_" }
                }
            }
        } elseif ($fileExtension -eq '.exe') {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

            if ($Prefix -and $Prefix -ne '\SetupChipset.exe') {
                $subDir = Split-Path $Prefix.TrimStart('\') -Parent
                if ($subDir) {
                    $fullOutputPath = Join-Path $OutputPath $subDir
                    New-Item -ItemType Directory -Path $fullOutputPath -Force | Out-Null
                    Write-DebugMessage "Created subdirectory: $fullOutputPath"
                }

                $outputFile = Join-Path $OutputPath ($Prefix.TrimStart('\'))
                Copy-Item $tempFile $outputFile -Force
                Write-Log "EXE file copied to: $outputFile" -Type "INFO" -Status '+'
            } else {
                Copy-Item $tempFile "$OutputPath\SetupChipset.exe" -Force
                Write-Log "EXE file copied to: $OutputPath\SetupChipset.exe" -Type "INFO" -Status '+'
            }
        } else {
            Write-Log "Unknown file type: $fileExtension" -Type "ERROR"
            return @{ Success = $false; ErrorType = "UnknownFileType"; Message = "Unknown file type: $fileExtension" }
        }

        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Write-DebugMessage "Removed temporary file: $tempFile"
        return @{ Success = $true; ErrorType = "None"; Message = "Success" }
    } catch {
        Write-Log "Error in Save-ChipsetFile: $_" -Type "ERROR"
        return @{ Success = $false; ErrorType = "UnknownError"; Message = "Unexpected error: $_" }
    }
}

# =============================================
# HARDWARE DETECTION FUNCTIONS
# =============================================

function Get-IntelChipsetHWIDs {
    $intelChipsets = @()
    $chipsetCount = 0
    $nonChipsetCount = 0

    try {
        $pciDevices = Get-PnpDevice -Class 'System' -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareID -like '*PCI\VEN_8086*' -and $_.Status -eq 'OK' }

        foreach ($device in $pciDevices) {
            foreach ($hwid in $device.HardwareID) {
                if ($hwid -match 'PCI\\VEN_8086&DEV_([A-F0-9]{4})') {
                    $deviceId = $matches[1]
                    $description = $device.FriendlyName

                    if ($description -match 'Chipset|LPC|PCI Express Root Port|PCI-to-PCI bridge|Motherboard Resources') {
                        $intelChipsets += [PSCustomObject]@{
                            HWID        = $deviceId
                            Description = $description
                            HardwareID  = $hwid
                            InstanceId  = $device.InstanceId
                            IsChipset   = $true
                        }
                        $chipsetCount++
                    } else {
                        $nonChipsetCount++
                    }
                }
            }
        }

        if ($intelChipsets.Count -eq 0) {
            foreach ($device in $pciDevices) {
                foreach ($hwid in $device.HardwareID) {
                    if ($hwid -match 'PCI\\VEN_8086&DEV_([A-F0-9]{4})') {
                        $deviceId = $matches[1]
                        $description = $device.FriendlyName

                        $intelChipsets += [PSCustomObject]@{
                            HWID        = $deviceId
                            Description = $description
                            HardwareID  = $hwid
                            InstanceId  = $device.InstanceId
                            IsChipset   = $false
                        }
                        $chipsetCount++

                        if ($intelChipsets.Count -ge 5) { break }
                    }
                }
                if ($intelChipsets.Count -ge 5) { break }
            }
        }

        Write-DebugMessage "Scanning completed: found $chipsetCount potential chipset devices and $nonChipsetCount non-chipset devices"
        return $intelChipsets | Sort-Object HWID -Unique
    } catch {
        Write-Log "Hardware detection failed: $($_.Exception.Message)" -Type "ERROR"
        return @{}
    }
}

function Get-CurrentINFVersion {
    param([string]$DeviceInstanceId)

    try {
        $device = Get-PnpDevice | Where-Object { $_.InstanceId -eq $DeviceInstanceId }
        if ($device) {
            $versionProperty = $device | Get-PnpDeviceProperty -KeyName "DEVPKEY_Device_DriverVersion" -ErrorAction SilentlyContinue
            if ($versionProperty -and $versionProperty.Data) {
                Write-DebugMessage "Got version from DEVPKEY_Device_DriverVersion: $($versionProperty.Data)"
                return $versionProperty.Data
            }

            $infVersionProperty = $device | Get-PnpDeviceProperty -KeyName "DEVPKEY_Device_INFVersion" -ErrorAction SilentlyContinue
            if ($infVersionProperty -and $infVersionProperty.Data) {
                Write-DebugMessage "Got version from DEVPKEY_Device_INFVersion: $($infVersionProperty.Data)"
                return $infVersionProperty.Data
            }
        }

        $driverInfo = Get-CimInstance -ClassName Win32_PnPSignedDriver | Where-Object {
            $_.DeviceID -eq $DeviceInstanceId -and $_.DriverVersion
        } | Select-Object -First 1

        if ($driverInfo) {
            Write-DebugMessage "Got version from WMI: $($driverInfo.DriverVersion)"
            return $driverInfo.DriverVersion
        }

        Write-DebugMessage "Could not determine version for device: $DeviceInstanceId"
        return $null
    } catch {
        Write-DebugMessage "Error getting INF version: $_"
        return $null
    }
}

# =============================================
# TEMP DIRECTORY CLEANUP FUNCTION
# =============================================

function Clear-TempINFFolders {
    try {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-DebugMessage "Cleaned up temporary directory: $tempDir"
        }
    } catch {
        Write-DebugMessage "Error during cleanup: $_"
    }
}

# =============================================
# DATA DOWNLOAD AND PARSING FUNCTIONS
# =============================================

function Get-LatestINFInfo {
    param([string]$Url)

    try {
        $cacheBuster = "t=" + (Get-Date -Format 'yyyyMMddHHmmss')
        if ($Url.Contains('?')) {
            $finalUrl = $Url + "&" + $cacheBuster
        } else {
            $finalUrl = $Url + "?" + $cacheBuster
        }

        Write-DebugMessage "Downloading from: $finalUrl (with cache-buster)"
        $content = Invoke-WebRequest -Uri $finalUrl -UseBasicParsing -ErrorAction Stop
        Write-DebugMessage "Successfully downloaded content from $finalUrl"
        return $content.Content
    } catch {
        Write-Log "Error downloading from GitHub: `n $($_.Exception.Message)" -Type "ERROR"
        return $null
    }
}

function ConvertFrom-ChipsetMarkdown {
    param([string]$MarkdownContent)

    Write-DebugMessage "Starting Markdown parsing."
    $chipsetData = @{}

    try {
        $lines = $MarkdownContent -split "`n"
        $currentPlatform = $null
        $currentGeneration = $null
        $inMainstreamSection = $false
        $inWorkstationSection = $false
        $inXeonSection = $false
        $inAtomSection = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()

            if ($line -match '^### Mainstream Desktop/Mobile') {
                $inMainstreamSection = $true
                $inWorkstationSection = $false
                $inXeonSection = $false
                $inAtomSection = $false
                Write-DebugMessage "Entered Mainstream Desktop/Mobile section."
                continue
            } elseif ($line -match '^### Workstation/Enthusiast') {
                $inMainstreamSection = $false
                $inWorkstationSection = $true
                $inXeonSection = $false
                $inAtomSection = $false
                Write-DebugMessage "Entered Workstation/Enthusiast section."
                continue
            } elseif ($line -match '^### Xeon/Server Platforms') {
                $inMainstreamSection = $false
                $inWorkstationSection = $false
                $inXeonSection = $true
                $inAtomSection = $false
                Write-DebugMessage "Entered Xeon/Server Platforms section."
                continue
            } elseif ($line -match '^### Atom/Low-Power Platforms') {
                $inMainstreamSection = $false
                $inWorkstationSection = $false
                $inXeonSection = $false
                $inAtomSection = $true
                Write-DebugMessage "Entered Atom/Low-Power Platforms section."
                continue
            }

            if ($line -match '^####\s+(.+)') {
                $currentPlatform = $matches[1]

                if ($inMainstreamSection) {
                    $sectionName = "Mainstream Desktop/Mobile"
                } elseif ($inWorkstationSection) {
                    $sectionName = "Workstation/Enthusiast"
                } elseif ($inXeonSection) {
                    $sectionName = "Xeon/Server Platforms"
                } elseif ($inAtomSection) {
                    $sectionName = "Atom/Low-Power Platforms"
                } else {
                    $sectionName = "Unknown"
                }

                Write-DebugMessage "Processing platform: $currentPlatform ($sectionName)"
                continue
            }

            if ($line -match '\*\*Generation:\*\*\s*(.+)') {
                $currentGeneration = $matches[1]
                Write-DebugMessage "Generation: $currentGeneration"
                continue
            }

            if ($line -match '^\|.*INF.*\|.*Package.*\|.*Version.*\|.*Date.*\|.*HWIDs.*\|$' -and $currentPlatform) {
                Write-DebugMessage "Found table for platform: $currentPlatform"
                $i++

                while ($i -lt $lines.Count -and $lines[$i].Trim() -match '^\|.*\|.*\|.*\|.*\|.*\|$') {
                    $dataLine = $lines[$i].Trim()
                    $i++

                    if ($dataLine -match '^\|\s*:---') { continue }

                    $columns = $dataLine.Split('|', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
                    if ($columns.Count -ge 5) {
                        $inf = $columns[0]
                        $package = $columns[1]
                        $version = $columns[2]
                        $date = $columns[3] -replace '\\', ''
                        $hwIds = $columns[4] -split ',' | ForEach-Object { $_.Trim() }

                        Write-DebugMessage "Parsed row: INF=$inf, Package=$package, Version=$version, HWIDs=$($hwIds -join ', ')"

                        foreach ($hwId in $hwIds) {
                            if ($hwId -match '^[A-F0-9]{4}$') {
                                $chipsetData[$hwId] = @{
                                    Platform          = $currentPlatform
                                    Section           = $sectionName
                                    Generation        = $currentGeneration
                                    INF               = $inf
                                    Package           = $package
                                    Version           = $version
                                    Date              = $date
                                    HasAsterisk       = $date -match '\*$'
                                    IsWindowsInbox    = ($package -eq "None")
                                }
                                Write-DebugMessage "Added HWID: $hwId for platform $currentPlatform (Package: $package, IsWindowsInbox: $($package -eq 'None'))"
                            } else {
                                Write-DebugMessage "Skipping invalid HWID: $hwId"
                            }
                        }
                    }
                }
            }
        }

        Write-DebugMessage "Markdown parsing completed. Found $($chipsetData.Count) HWID entries."
        return $chipsetData
    } catch {
        Write-Log "Markdown parsing failed: $($_.Exception.Message)" -Type "ERROR"
        return @{}
    }
}

# =============================================
# INSTALLATION FUNCTION
# =============================================

function Install-ChipsetINF {
    param([string]$INFPath, [string]$Prefix)

    try {
        if ($Prefix) {
            $setupPath = Join-Path $INFPath ($Prefix.TrimStart('\'))
        } else {
            $setupPath = Join-Path $INFPath "SetupChipset.exe"
        }

        Write-DebugMessage "Installing from path: $setupPath"

        if (Test-Path $setupPath) {
            $isMSI = $setupPath -match '\.msi$'

            if ($isMSI) {
                Write-Log "Verifying MSI installer integrity..." -Type "INFO" -Status '+'

                if ($INFPath -match '(\d+\.\d+\.\d+\.\d+)') {
                    $version = $matches[1]
                    Write-DebugMessage "Extracted version for MSI verification: $version"

                    try {
                        $hashUrl = $githubArchiveUrl + "intel_chipset_$version.msi.sha256"
                        Write-DebugMessage "Downloading MSI hash from: $hashUrl"

                        $hashResponse = Invoke-WebRequest -Uri $hashUrl -UseBasicParsing -ErrorAction Stop
                        $hashContent = $hashResponse.Content
                        if ($hashContent -is [byte[]]) {
                            $hashContent = [System.Text.Encoding]::UTF8.GetString($hashContent)
                        } else {
                            $hashContent = $hashContent.ToString()
                        }

                        $hashContent = $hashContent.Trim()
                        if ($hashContent.Length -gt 0 -and [int][char]$hashContent[0] -eq 0xFEFF) {
                            $hashContent = $hashContent.Substring(1).Trim()
                        }
                        $hashContent = $hashContent.TrimStart([char]0xEF, [char]0xBB, [char]0xBF).Trim()

                        Write-DebugMessage "Hash file content: $hashContent"

                        if ($hashContent -match '^([A-F0-9]{64})\s+') {
                            $expectedHash = $matches[1]
                            Write-DebugMessage "Expected MSI hash: $expectedHash"

                            $actualHash = (Get-FileHash -Path $setupPath -Algorithm SHA256).Hash
                            Write-DebugMessage "Actual MSI hash: $actualHash"

                            if ($actualHash -eq $expectedHash) {
                                Write-Log "MSI integrity verification: PASSED" -Type "INFO" -Status '+'
                                Write-DebugMessage "MSI hash verification successful"
                            } else {
                                Write-Log "MSI hash mismatch for $setupPath" -Type "ERROR" -Status '-'
                                Write-Log "MSI integrity verification failed. Hash mismatch." -Type "ERROR" -Status '-'
                                Write-Log "Expected: $expectedHash" -Type "INFO" -Status '-'
                                Write-Log "Actual:   $actualHash" -Type "INFO" -Status '-'
                                return $false
                            }
                        } else {
                            Write-Log "Invalid hash file format from $hashUrl" -Type "WARN" -Status '-'
                            Write-Log "Could not parse hash file. Proceeding with caution..." -Type "WARN" -Status '-'
                        }
                    } catch {
                        Write-DebugMessage "Could not verify MSI hash: $($_.Exception.Message)"
                        Write-Log "Could not verify MSI hash (file may not be available yet)." -Type "WARN" -Status '-'
                        Write-Log "ZIP archive was already verified. Proceeding with installation..." -Type "INFO" -Status '+'
                    }
                } else {
                    Write-Log "Could not extract version for MSI verification." -Type "ERROR" -Status '-'
                }
            } else {
                Write-Log "Verifying installer digital signature..." -Type "INFO" -Status '+'
                if (-not (Test-FileSignature -FilePath $setupPath)) {
                    Write-Log "Installer digital signature verification failed. Aborting installation." -Type "ERROR" -Status '-'
                    Write-Log "Installer digital signature verification failed. Installation aborted." -Type "ERROR" -Status '-'
                    return $false
                }
            }

            Write-Host ""
            Write-Host "[!] IMPORTANT NOTICE:"
            Write-Host "[!] The INF files updater is now running."
            Write-Host "[!] Please DO NOT close this window or interrupt the process."
            Write-Host "[!] The system may appear unresponsive during installation - this is normal."
            Write-Host ""

            if ($isMSI) {
                Write-Log "Running installer: SetupChipset.msi" -Type "INFO" -Status '+'
                Write-DebugMessage "Starting MSI installer with msiexec: /i /quiet /norestart"

                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$setupPath`" /quiet /norestart" -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    Write-Log "INF files installed successfully." -Type "INFO" -Status '+'
                    if ($process.ExitCode -eq 3010) {
                        Write-Log "(Reboot required to complete installation)" -Type "INFO" -Status '+'
                    }
                    Write-DebugMessage "MSI installer completed successfully with exit code: $($process.ExitCode)"
                    return $true
                } else {
                    Write-Log "MSI installer failed with exit code: $($process.ExitCode)" -Type "ERROR" -Status '-'
                    Write-Log "MSI installation failed with exit code: $($process.ExitCode)" -Type "ERROR" -Status '-'
                    return $false
                }
            } else {
                Write-Log "Running installer: SetupChipset.exe" -Type "INFO" -Status '+'
                Write-DebugMessage "Starting installer with arguments: -S -OVERALL -downgrade -norestart"

                $process = Start-Process -FilePath $setupPath -ArgumentList "-S -OVERALL -downgrade -norestart" -Wait -PassThru

                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    Write-Log "INF files installed successfully." -Type "INFO" -Status '+'
                    Write-DebugMessage "Installer completed successfully with exit code: $($process.ExitCode)"
                    return $true
                } else {
                    Write-Log "Installer failed with exit code: $($process.ExitCode)" -Type "ERROR" -Status '-'
                    return $false
                }
            }
        } else {
            Write-Log "Installer not found at: $setupPath" -Type "ERROR"

            $installers = Get-ChildItem -Path $INFPath -Filter "*.exe" -Recurse | Where-Object {
                $_.Name -like "*Setup*" -or $_.Name -like "*Install*"
            }

            if (-not $installers) {
                $installers = Get-ChildItem -Path $INFPath -Filter "*.msi" -Recurse | Where-Object {
                    $_.Name -like "*Setup*" -or $_.Name -like "*Install*"
                }
            }

            if ($installers) {
                Write-Log "Found alternative installer: $($installers[0].FullName)" -Type "INFO" -Status '+'

                $altIsMSI = $installers[0].Name -match '\.msi$'
                if (-not $altIsMSI) {
                    Write-Log "Verifying alternative installer digital signature..." -Type "INFO" -Status '+'
                    if (-not (Test-FileSignature -FilePath $installers[0].FullName)) {
                        Write-Log "Alternative installer digital signature verification failed." -Type "ERROR"
                        return $false
                    }
                }

                return Install-ChipsetINF -INFPath $INFPath -Prefix "\$($installers[0].Name)"
            }
            return $false
        }
    } catch {
        Write-Log "Error running installer: $_" -Type "ERROR"
        return $false
    }
}

# =============================================
# CLEANUP FUNCTION
# =============================================

function Cleanup {
    Write-Log "Cleaning up temporary files..." -Type "INFO" -Status '+'
    if (Test-Path $tempDir) {
        try {
            Get-ChildItem -Path $tempDir -Exclude "*.ps1" -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
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
    Clear-TempINFFolders
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Write-DebugMessage "Created temporary directory: $tempDir"

    $detectedIntelChipsets = Get-IntelChipsetHWIDs

    if ($detectedIntelChipsets.Count -eq 0) {
        Write-Log "No Intel chipset devices found." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    Write-DebugMessage "Found $($detectedIntelChipsets.Count) Intel chipset device(s)"

    $chipsetInfo = Get-LatestINFInfo -Url $chipsetINFsUrl
    $downloadListInfo = Get-LatestINFInfo -Url $downloadListUrl

    if (-not $chipsetInfo -or -not $downloadListInfo) {
        Write-Log "Failed to download INF information." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    $chipsetData = ConvertFrom-ChipsetMarkdown -MarkdownContent $chipsetInfo
    $downloadData = ConvertFrom-DownloadList -DownloadListContent $downloadListInfo

    if ($chipsetData.Count -eq 0 -or $downloadData.Count -eq 0) {
        Write-Log "Could not parse INF information." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    $matchingChipsets = @()
    $chipsetUpdateAvailable = $false
    $windowsInboxPlatformsFound = @()

    foreach ($device in $detectedIntelChipsets) {
        $hwId = $device.HWID
        if ($chipsetData.ContainsKey($hwId)) {
            $info = $chipsetData[$hwId]
            if ($info.IsWindowsInbox) {
                $windowsInboxPlatformsFound += @{
                    HWID        = $hwId
                    Platform    = $info.Platform
                    Generation  = $info.Generation
                    Version     = $info.Version
                }
                continue
            }
            $currentVersion = Get-CurrentINFVersion -DeviceInstanceId $device.InstanceId
            $matchingChipsets += @{
                Device         = $device
                ChipsetInfo    = $info
                CurrentVersion = $currentVersion
            }
        }
    }

    if ($matchingChipsets.Count -eq 0) {
        Write-Log "No compatible Intel chipset platforms found." -Type "ERROR" -Status '-'
        Cleanup
        exit 1
    }

    # Build unique platforms for analysis
    $uniquePlatforms = @{}
    foreach ($match in $matchingChipsets) {
        $platform = $match.ChipsetInfo.Platform
        if (-not $uniquePlatforms.ContainsKey($platform)) {
            $uniquePlatforms[$platform] = @{
                ChipsetInfo     = $match.ChipsetInfo
                Devices         = @($match.Device)
                CurrentVersions = @()
            }
        }
        if ($match.CurrentVersion) {
            $uniquePlatforms[$platform].CurrentVersions += $match.CurrentVersion
        }
    }

    $hasNewerWindowsInbox = $false

    foreach ($platformName in $uniquePlatforms.Keys) {
        $platformData = $uniquePlatforms[$platformName]
        $chipsetInfo = $platformData.ChipsetInfo
        $currentVersions = $platformData.CurrentVersions | Sort-Object -Unique

        $needsUpdate = $false
        $newerVersionDetected = $false

        if ($currentVersions.Count -gt 0) {
            foreach ($currentVersion in $currentVersions) {
                try {
                    $currentVer = [version]$currentVersion
                    $latestVer = [version]$chipsetInfo.Version
                    if ($currentVer -gt $latestVer) {
                        $newerVersionDetected = $true
                        break
                    } elseif ($currentVer -ne $latestVer) {
                        $needsUpdate = $true
                        break
                    }
                } catch {
                    if ($currentVersion -ne $chipsetInfo.Version) {
                        $needsUpdate = $true
                        break
                    }
                }
            }
        } else {
            $needsUpdate = $true
        }

        if ($newerVersionDetected) {
            $hasNewerWindowsInbox = $true
        } elseif ($needsUpdate) {
            $chipsetUpdateAvailable = $true
        }
    }

    if ($hasNewerWindowsInbox -and -not $chipsetUpdateAvailable) {
        Write-Log "Newer INF versions detected via Windows Update. Skipping installation." -Type "INFO"
        Cleanup
        exit 0
    }

    if (-not $chipsetUpdateAvailable) {
        Write-Log "All platforms are up to date. Forcing reinstall." -Type "INFO"
        $chipsetUpdateAvailable = $true
    }

    Write-DebugMessage "Starting INF files update process..."

    $restorePointDescription = "Before Intel Chipset INF Update - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    try {
        $null = Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    } catch {
        Write-DebugMessage "System restore might already be enabled: $($_.Exception.Message)"
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
        Write-DebugMessage "System restore point created: $restorePointDescription"
    } catch {
        Write-DebugMessage "Restore point creation skipped: $($_.Exception.Message)"
    }

    $packageGroups = @{}
    foreach ($platformName in $uniquePlatforms.Keys) {
        $platformData = $uniquePlatforms[$platformName]
        $packageVersion = $platformData.ChipsetInfo.Package
        if (-not $packageGroups.ContainsKey($packageVersion)) {
            $packageGroups[$packageVersion] = @()
        }
        $packageGroups[$packageVersion] += $platformName
    }

    $sortedPackages = $packageGroups.Keys | Sort-Object { [version]($_ -replace '\s*\(S\)\s*', '') } -Descending
    $successCount = 0

    foreach ($packageVersion in $sortedPackages) {
        $platforms = $packageGroups[$packageVersion]
        Write-DebugMessage "Processing package: $packageVersion for platforms: $($platforms -join ', ')"

        $variant = "Consumer"
        if ($packageVersion -match '\(S\)$') { $variant = "Server" }

        $cleanPackageVersion = $packageVersion -replace '\s*\(S\)\s*', ''
        $downloadKey = "$cleanPackageVersion-$variant"

        if ($downloadData.ContainsKey($downloadKey)) {
            $downloadInfo = $downloadData[$downloadKey]
            $driverPath = "$tempDir\$cleanPackageVersion-$variant"

            $downloadSuccess = $false

            $primaryResult = Save-ChipsetFile -Url $downloadInfo.Link -OutputPath $driverPath -Prefix $downloadInfo.Prefix -ExpectedHash $downloadInfo.SHA256 -SourceName "Primary"

            if ($primaryResult.Success) {
                $downloadSuccess = $true
            } elseif ($downloadInfo.Backup) {
                $backupResult = Save-ChipsetFile -Url $downloadInfo.Backup -OutputPath $driverPath -Prefix $downloadInfo.Prefix -ExpectedHash $downloadInfo.SHA256 -SourceName "Backup"
                if ($backupResult.Success) {
                    $downloadSuccess = $true
                }
            }

            if (-not $downloadSuccess) {
                Write-Log "Download failed for package $cleanPackageVersion" -Type "ERROR" -Status '-'
                continue
            }

            if (Install-ChipsetINF -INFPath $driverPath -Prefix $downloadInfo.Prefix) {
                $successCount++
                Write-DebugMessage "Installation successful for package: $cleanPackageVersion"
            } else {
                Write-Log "Installation failed for package: $cleanPackageVersion" -Type "ERROR" -Status '-'
            }
        } else {
            Write-Log "Download info not found for $downloadKey" -Type "ERROR" -Status '-'
        }
    }

    Cleanup

    if ($successCount -gt 0) {
        Write-Log "Successfully installed $successCount package(s). Reboot required." -Type "INFO"
    } else {
        Write-Log "No INF files were successfully installed." -Type "ERROR" -Status '-'
    }

    Show-FinalSummary
    exit 0
} catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Type "ERROR" -Status '-'
    Cleanup
    exit 1
}