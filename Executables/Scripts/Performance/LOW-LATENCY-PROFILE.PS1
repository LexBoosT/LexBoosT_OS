# Requires administrator rights
# Requires -RunAsAdministrator

# Stop on error
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

try {
    Write-Host "=== Enabling Low Latency Profiles ==="

    # --- 1. Detect processor architecture ---
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') {
        $zipName = 'ViVeTool-v0.3.4-IntelAmd.zip'
        Write-Log '+' "Detected architecture: x64 (Intel/AMD)"
    } elseif ($arch -eq 'ARM64') {
        $zipName = 'ViVeTool-v0.3.4-SnapdragonArm64.zip'
        Write-Log '+' "Detected architecture: ARM64 (Snapdragon)"
    } else {
        Write-Log '-' "Unrecognized architecture: $arch. Downloading default (x64)."
        $zipName = 'ViVeTool-v0.3.4-IntelAmd.zip'
    }

    $downloadUrl = "https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/$zipName"

    # --- 2. Create temporary folder ---
    $tempDir = Join-Path $env:TEMP 'ViVeTool_Temp'
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Write-Log '+' "Temporary folder created: $tempDir"

    # --- 3. Download ViVeTool ---
    $zipPath = Join-Path $tempDir $zipName
    Write-Log '+' "Downloading ViVeTool...`n$downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    # --- 4. Extract archive ---
    Write-Log '+' "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    # --- 5. Locate ViVeTool.exe ---
    $exePath = Get-ChildItem -Path $tempDir -Filter 'ViVeTool.exe' -Recurse | Select-Object -First 1
    if (-not $exePath) {
        throw "Could not find ViVeTool.exe after extraction."
    }
    Write-Log '+' "ViVeTool.exe found at: $($exePath.FullName)"

    # --- 6. Enable features ---
    Write-Log '+' "Enabling feature..."
    $process = Start-Process -FilePath $exePath.FullName -ArgumentList '/enable /id:60716524,61391826,58989092' -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Log '+' "Command executed successfully!"
        Write-Log '+' "A reboot is required for changes to take effect."
    } else {
        Write-Log '-' "Command returned error code: $($process.ExitCode)"
    }
}
catch {
    Write-Log '-' "ERROR: $_"
    Write-Log '-' "Make sure you are running this script as Administrator."
}
finally {
    # --- 7. Cleanup ---
    if (Test-Path $tempDir) {
        Write-Log '-' "Deleting temporary folder $tempDir..."
        Remove-Item $tempDir -Recurse -Force
        Write-Log '+' "Cleanup finished."
    }
}

Write-Log '+' "Script completed."
