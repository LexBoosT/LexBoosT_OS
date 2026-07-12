$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Checking RAM for Memory Compression...'

try {
    $ramBytes = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $ramGB = [math]::Round($ramBytes / 1GB)

    if ($ramBytes -ge 17179869184) {
        Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        Write-Log '+' "MemoryCompression disabled ({0} GB RAM)" -f $ramGB
    } else {
        Write-Log '-' "MemoryCompression kept (RAM = {0} GB < 16 GB)" -f $ramGB
    }
} catch {
    Write-Log '-' "MemoryCompression unchanged (not supported on this build)"
}
# Exit cleanly
exit 0
