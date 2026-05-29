$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' "Locating EFI partition..."

try {
    $efiPartition = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } | Select-Object -First 1

    if ($null -eq $efiPartition) {
        Write-Log '+' "No EFI partition found"
        exit 0
    }

    if ([string]::IsNullOrEmpty($efiPartition.DriveLetter) -or $efiPartition.DriveLetter -notmatch '^[A-Z]$') {
        Write-Log '+' "EFI partition has no valid drive letter"
        exit 0
    }

    Write-Log '+' "Removing drive letter '$($efiPartition.DriveLetter):' from EFI partition..."
    Remove-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber -PartitionNumber $efiPartition.PartitionNumber -AccessPath "$($efiPartition.DriveLetter):\"
    Write-Log '+' "EFI partition drive letter removed"
} catch {
    Write-Log '-' "Failed to remove EFI drive letter: $_"
}
# Exit cleanly
exit 0
