function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Function Set-UserFolderIcon {
    param(
        [string]$IconPath = "$env:WINDIR\LexBoosTOS\Resources\Icons\FolderUser.ico"
    )

    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{59031A47-3F72-44A7-89C5-5595FE6B30EE}\DefaultIcon"
    $iconValue = "$IconPath,0"

    try {
        Write-Log '+' "Attempting to customize user folder icon..."

        Set-ItemProperty -Path $regPath -Name "(Default)" -Value $iconValue -ErrorAction Stop

        Write-Log '+' "User folder icon successfully updated!"
        Write-Log '+' "New icon location: $IconPath"
        return $true
    }
    catch {
        Write-Log '+' "Registry key not found, creating it..."

        try {
            New-Item -Path $regPath -Force | Out-Null
            New-ItemProperty -Path $regPath -Name "(Default)" -Value $iconValue -PropertyType String | Out-Null

            Write-Log '+' "User folder icon successfully configured!"
            Write-Log '+' "New icon location: $IconPath"
            return $true
        }
        catch {
            Write-Log '-' "ERROR: Failed to create registry key"
            Write-Log '-' "Details: $_"
            return $false
        }
    }
}

Add-Type -AssemblyName System.Windows.Forms
Set-UserFolderIcon
Start-Sleep -Seconds 5
[System.Windows.Forms.SendKeys]::SendWait("{F5}")
Start-Sleep -Seconds 3
exit