$ProtectedClasses = @(
    'HIDClass',
    'System',
    'Mouse',
    'Keyboard',
    'Display',
    'Sound, video and game controllers',
    'Batteries',
    'Firmware',
    'ACPI x64-based PC',
    'Security devices',
    'Biometric',
    'Smart card readers',
    'Printers',
    'IEEE 1284.4 compatible printer'
)

$ProtectedProviders = @(
    'Intel',
    'Intel Corporation',
    'Intel(R) Corporation',
    'Advanced Micro Devices',
    'AMD',
    'AMD Corporation',
    'Realtek',
    'Realtek Semiconductor Corp.',
    'Synaptics',
    'Synaptics Incorporated',
    'ELAN',
    'ELAN Microelectronics Corp.',
    'Dolby',
    'DTS',
    'NVIDIA',
    'NVIDIA Corporation',
    'Microsoft',
    'Microsoft Corporation',
    'Windows',
    'Microsoft Windows'
)

$OriginalFileName = @{
    Name        = "OriginalFileName"
    Expression  = { $_.OriginalFileName | Split-Path -Leaf }
}
# Use actual DateTime for correct chronological sorting
$DriverDate = @{
    Name        = "DriverDate"
    Expression  = { $_.Date }
}

$AllDrivers = Get-WindowsDriver -Online -All |
    Where-Object { $_.Driver -like 'oem*inf' } |
    Select-Object -Property $OriginalFileName, Driver, ClassDescription, ClassName, ProviderName, $DriverDate, Version

Write-Verbose -Message "All installed third-party drivers" -Verbose
($AllDrivers | Sort-Object -Property ClassDescription | Format-Table -AutoSize -Wrap | Out-String).Trim()

$DriverGroups = $AllDrivers | Group-Object -Property OriginalFileName | Where-Object { $_.Count -gt 1 }

Write-Verbose -Message "Duplicate drivers" -Verbose
($DriverGroups | ForEach-Object {
    $_.Group | Sort-Object -Property DriverDate -Descending | Select-Object -Skip 1 |
        Select-Object OriginalFileName, Driver, ClassDescription, ClassName, ProviderName,
                      @{N='Date';E={$_.DriverDate.ToString('dd/MM/yyyy')}}, Version
} | Format-Table | Out-String).Trim()

# Remove older duplicates — sort by actual DateTime, keep newest, remove older ones
$DriversToRemove = $DriverGroups | ForEach-Object {
    $_.Group | Sort-Object -Property DriverDate -Descending | Select-Object -Skip 1
}

# Filter out protected drivers by class or provider
$FilteredDrivers = $DriversToRemove | Where-Object {
    $protected = $false
    foreach ($cls in $ProtectedClasses) {
        if ($_.ClassDescription -eq $cls -or $_.ClassName -eq $cls) {
            Write-Verbose "  PROTECTED (class: $($_.ClassDescription)): $($_.OriginalFileName)" -Verbose
            $protected = $true
            break
        }
    }
    if (-not $protected) {
        foreach ($prov in $ProtectedProviders) {
            if ($_.ProviderName -like "*$prov*") {
                Write-Verbose "  PROTECTED (provider: $($_.ProviderName)): $($_.OriginalFileName)" -Verbose
                $protected = $true
                break
            }
        }
    }
    -not $protected
}

Write-Verbose -Message "Drivers to remove (after protection filter)" -Verbose
($FilteredDrivers |
    Select-Object OriginalFileName, Driver, ClassDescription, ProviderName,
                  @{N='Date';E={$_.DriverDate.ToString('dd/MM/yyyy')}}, Version |
    Sort-Object -Property ClassDescription | Format-Table | Out-String).Trim()

if ($FilteredDrivers.Count -eq 0) {
    Write-Host "No drivers to remove after applying protection filters."
    return
}

foreach ($item in $FilteredDrivers) {
    $Name = $($item.Driver).Trim()
    Write-Host "Removing driver: $Name"
    $result = & pnputil.exe /delete-driver "$Name" /force 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Skipped (in use or protected): $($result -join ' ')"
    } else {
        Write-Host "  Removed successfully."
    }
}
