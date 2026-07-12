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
    Select-Object -Property $OriginalFileName, Driver, ClassDescription, ProviderName, $DriverDate, Version

Write-Verbose -Message "All installed third-party drivers" -Verbose
($AllDrivers | Sort-Object -Property ClassDescription | Format-Table -AutoSize -Wrap | Out-String).Trim()

$DriverGroups = $AllDrivers | Group-Object -Property OriginalFileName | Where-Object { $_.Count -gt 1 }

Write-Verbose -Message "Duplicate drivers" -Verbose
($DriverGroups | ForEach-Object {
    $_.Group | Sort-Object -Property DriverDate -Descending | Select-Object -Skip 1 |
        Select-Object OriginalFileName, Driver, ClassDescription, ProviderName,
                      @{N='Date';E={$_.DriverDate.ToString('dd/MM/yyyy')}}, Version
} | Format-Table | Out-String).Trim()

# Remove older duplicates — sort by actual DateTime, keep newest, remove older ones
$DriversToRemove = $DriverGroups | ForEach-Object {
    $_.Group | Sort-Object -Property DriverDate -Descending | Select-Object -Skip 1
}

Write-Verbose -Message "Drivers to remove" -Verbose
($DriversToRemove |
    Select-Object OriginalFileName, Driver, ClassDescription, ProviderName,
                  @{N='Date';E={$_.DriverDate.ToString('dd/MM/yyyy')}}, Version |
    Sort-Object -Property ClassDescription | Format-Table | Out-String).Trim()

foreach ($item in $DriversToRemove) {
    $Name = $($item.Driver).Trim()
    Write-Host "Removing driver: $Name"
    $result = & pnputil.exe /delete-driver "$Name" /force 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Skipped (in use or protected): $($result -join ' ')"
    } else {
        Write-Host "  Removed successfully."
    }
}
