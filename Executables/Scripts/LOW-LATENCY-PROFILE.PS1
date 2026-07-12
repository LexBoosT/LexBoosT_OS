# Low Latency Profile — enables Windows hidden low-latency features via ViVeTool
# ViVeTool is bundled in the playbook under LexBoosTOS\Utilities\ViVeTool\

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

try {
    Write-Host "=== Enabling Low Latency Profiles ==="

    # --- 1. Locate bundled ViVeTool.exe ---
    # Try multiple candidate paths (playbook source + deployed location)
    $candidates = @(
        (Join-Path $env:windir 'LexBoosTOS\Utilities\ViVeTool\ViVeTool.exe'),
        (Join-Path $env:ProgramData 'LexBoosTOS\Utilities\ViVeTool\ViVeTool.exe'),
        (Join-Path $PSScriptRoot '..\LexBoosTOS\Utilities\ViVeTool\ViVeTool.exe')
    )

    $exePath = $null
    foreach ($p in $candidates) {
        $full = if (Test-Path $p) { (Get-Item $p).FullName } else { $null }
        if ($full) {
            $exePath = $full
            break
        }
    }

    if (-not $exePath) {
        Write-Log '-' "ViVeTool.exe not found in bundled locations."
        Write-Log '-' "Expected at: $env:windir\LexBoosTOS\Utilities\ViVeTool\ViVeTool.exe"
        Write-Log '-' "Skipping low-latency feature activation."
        exit 0
    }

    Write-Log '+' "Using bundled ViVeTool: $exePath"

    # --- 2. Enable features ---
    Write-Log '+' "Enabling low-latency features (IDs: 60716524, 61391826, 58989092, 36435115)..."
    $process = Start-Process -FilePath $exePath -ArgumentList '/enable /id:60716524,61391826,58989092' -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Log '+' "Low-latency features enabled successfully!"
        Write-Log '+' "A reboot is required for changes to take effect."
    } else {
        Write-Log '-' "ViVeTool returned error code: $($process.ExitCode)"
    }
}
catch {
    Write-Log '-' "ERROR: $_"
}
