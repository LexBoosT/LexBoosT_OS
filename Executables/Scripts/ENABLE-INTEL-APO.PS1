#Requires -RunAsAdministrator
# =============================================================================
# LexBoosT OS - Intel APO (Application Performance Optimization)
# Automatically installs the Intel Platform Performance Package (IPPP):
# 8 Intel components (DTT driver, IPF, APO software, UI, PPM, ESIF...)
# in silent mode (WiX Burn : /quiet /log).
#
# Clean no-op : AMD, Intel <12th gen, no network, invalid hash.
# Reboot required after installation (signaled to the playbook).
# =============================================================================
$ErrorActionPreference = 'Continue'

function Write-Lex { param([string]$m) Write-Host "[APO] $m" }

# ---------------------------------------------------------------------------
# 1) CPU detection: Intel 12th gen+ (Alder/Raptor Lake) or Core Ultra?
#    Relies on VendorIdentifier + name (robust, no native CPUID in PS).
# ---------------------------------------------------------------------------
function Test-ApoSupportedCpu {
    try {
        $cpu  = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $name = ($cpu.Name -as [string])
        $vend = ($cpu.VendorIdentifier -as [string])
        Write-Lex ("CPU: " + $name)
        # AMD / other: not supported by Intel APO
        if ($vend -ne 'GenuineIntel' -and ($name -notmatch 'Intel')) {
            Write-Lex 'Non-Intel CPU (AMD/other) - APO not applicable (no-op).'
            return $false
        }
        # Supported generations:
        #   - Core Ultra (Sapphire/Arrow/Panther Lake)
        #   - i3/i5/i7/i9 series 12xxx-14xxx (Alder Lake, Raptor Lake, Raptor Lake Refresh)
        $isCoreUltra = ($name -match 'Core Ultra')
        $is12to14    = ($name -match 'i[3579]-1[2-4]\d{3}')
        if ($isCoreUltra -or $is12to14) { return $true }
        Write-Lex 'Intel CPU not covered by APO (<12th gen) - no-op.'
        return $false
    } catch {
        Write-Lex ('CPU detection failed: ' + $_.Exception.Message)
        return $false
    }
}

if (-not (Test-ApoSupportedCpu)) { exit 0 }
Write-Lex 'Intel 12th gen+ / Core Ultra detected - auto-installing IPPP...'

# ---------------------------------------------------------------------------
# 2) Already installed? (DTT/IPF/APO service present or Intel folder exists)
# ---------------------------------------------------------------------------
function Get-IntelApoService {
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'esif|Dtt|Apo' -or
                       $_.DisplayName -match 'Application Performance|Dynamic Tuning|Innovation Platform|Intel Application' }
}
$existing = Get-IntelApoService
$installedDir = 'C:\Program Files\Intel\Platform Performance Package'
if ($existing -or (Test-Path $installedDir)) {
    Write-Lex 'IPPP already present - enabling services only.'
    foreach($s in $existing){
        try { Set-Service -Name $s.Name -StartupType Automatic -ErrorAction Stop } catch {}
        try { Start-Service -Name $s.Name -ErrorAction SilentlyContinue } catch {}
        Write-Lex ('Service ' + $s.Name + ' enabled/verified.')
    }
    exit 0
}

# ---------------------------------------------------------------------------
# 3) IPPP download (direct URL + official Intel SHA256 hash)
# ---------------------------------------------------------------------------
$Url = 'https://downloadmirror.intel.com/927220/PlatformPerformancePackageInstaller.exe'
$Sha = '33A77D76CDE1923E153098CBE56D85504741C5430EC6449AE7DBD41BE599B786'
$Dir = Join-Path $env:TEMP 'LexBoosT_APO'
New-Item -ItemType Directory -Path $Dir -ErrorAction SilentlyContinue | Out-Null
$Exe = Join-Path $Dir 'PlatformPerformancePackageInstaller.exe'
$Log = Join-Path $Dir 'ipp_silent.log'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$hdr = @{ 'User-Agent' = $ua; 'Referer' = 'https://www.intel.com/content/www/us/en/download/869519/intel-platform-performance-package.html' }

Write-Lex 'Downloading IPPP (103 MB)...'
$ok = $false
foreach($attempt in 1..3){
    try {
        if (Test-Path $Exe) { Remove-Item $Exe -Force -ErrorAction SilentlyContinue }
        Invoke-WebRequest -Uri $Url -Headers $hdr -OutFile $Exe -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        $h = (Get-FileHash $Exe -Algorithm SHA256).Hash
        if ($h -eq $Sha) { Write-Lex ('Hash verified (' + $h.Substring(0,8) + '...)'); $ok = $true; break }
        else { Write-Lex ('Hash mismatch (attempt ' + $attempt + ') : ' + $h) }
    } catch {
        Write-Lex ('Attempt ' + $attempt + ' : ' + $_.Exception.Message)
    }
}
if (-not $ok) { Write-Lex 'Download failed - aborting (no-op).'; exit 0 }

# ---------------------------------------------------------------------------
# 4) Silent install (WiX Burn)
# ---------------------------------------------------------------------------
Write-Lex 'Running silent install (quiet mode)...'
try {
    $proc = Start-Process -FilePath $Exe -ArgumentList ('/quiet /log "{0}"' -f $Log) -WorkingDirectory $Dir -Wait -PassThru
    $code = $proc.ExitCode
} catch {
    Write-Lex ('Installer launch error : ' + $_.Exception.Message)
    $code = -1
}
# 0 = ok, 3010 = ok + reboot required
if ($code -eq 0 -or $code -eq 3010) { Write-Lex ('Install finished (code ' + $code + ').') }
else { Write-Lex ('Install code ' + $code + ' - verifying services...') }

# ---------------------------------------------------------------------------
# 5) Enabling Intel services (DTT / IPF / APO)
# ---------------------------------------------------------------------------
$svc = Get-IntelApoService
if ($svc) {
    foreach($s in $svc){
        try { Set-Service -Name $s.Name -StartupType Automatic -ErrorAction Stop } catch {}
        try { Start-Service -Name $s.Name -ErrorAction Stop; Write-Lex ('Service ' + $s.Name + ' started.') } catch { Write-Lex ('Starting ' + $s.Name + ' : ' + $_.Exception.Message) }
    }
} else {
    # DTT/IPF may be disabled in BIOS by the OEM: the driver cannot install,
    # the bundle stays as-is. Nothing forced (clean no-op).
    Write-Lex 'No Intel APO/DTT service found after install (BIOS DTT/IPF may be disabled).'
}

# ---------------------------------------------------------------------------
# 6) Cleanup
# ---------------------------------------------------------------------------
try { Remove-Item $Exe -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item $Log -Force -ErrorAction SilentlyContinue } catch {}
Write-Lex 'Done.'
exit 0
