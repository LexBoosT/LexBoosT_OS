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

    # --- 2. CPU / build guards ---
    # The Low Latency Profile (K2 CPU boost) forces frequency spikes on app
    # launches. On AMD 3D V-Cache (X3D) this causes intermittent WHEA/BSOD —
    # the feature IDs 58989092 / 60716524 / 61391826 / 62816659 are skipped
    # on X3D. They also only exist on 25H2 26200.8728+ — on older builds
    # (24H2 26100) activating unknown feature IDs can bugcheck at boot.
    $isX3D = $false
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $isX3D = ($cpu.Name -match 'AMD') -and ($cpu.Name -match 'X3D')
    } catch {
        Write-Log '-' "CPU detection failed: $_"
    }
    $build = 0
    try {
        $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild -ErrorAction Stop).CurrentBuild
    } catch {
        Write-Log '-' "Build detection failed: $_"
    }

    $llpIds = '58989092,60716524,61391826,62816659'
    $uiIds  = '59213768,61754985,61225604,61596616,61596617,61596618,61596619'

    $enable = @()
    if ($isX3D) {
        Write-Log '-' "AMD 3D V-Cache detected: Low Latency Profile (K2 CPU boost) skipped (X3D stability)."
    } elseif ($build -lt 26200) {
        Write-Log '-' "Build ${build}: Low Latency Profile not available (26200.8728+ required), skipped."
    } else {
        $enable += $llpIds
        Write-Log '+' "Low Latency Profile (K2 CPU boost) enabled."
    }

    # UI feature IDs (new Start Menu / Taskbar) also only exist on 26200+;
    # activating unknown IDs on 24H2 26100 can bugcheck at boot.
    if ($build -ge 26200) {
        $enable += $uiIds
    } else {
        Write-Log '-' "Build ${build}: UI feature IDs skipped (26200+ required)."
    }

    # --- 3. Enable features ---
    Write-Log '+' "Enabling UI features (new Start Menu / Taskbar)..."
    $process = Start-Process -FilePath $exePath -ArgumentList ("/enable /id:" + ($enable -join ',')) -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Log '+' "Features enabled successfully!"
        Write-Log '+' "A reboot is required for changes to take effect."
    } else {
        Write-Log '-' "ViVeTool returned error code: $($process.ExitCode)"
    }
}
catch {
    Write-Log '-' "ERROR: $_"
}
