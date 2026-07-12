$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$foldersToDelete = @(
    "$env:SystemDrive\Windows.old",
    "$env:SystemDrive\inetpub",
    "$env:SystemDrive\PerfLogs"
)

function DeleteFolder {
    param (
        [string]$folderPath
    )

    if (Test-Path $folderPath) {
        Write-Log '+' "Processing folder: $folderPath"

        # 1. Kill processes using the folder (silently continue on errors)
        Write-Log '+' "Searching for locking processes..."
        try {
            $lockingProcesses = Get-Process | Where-Object { $_.Path -like "$folderPath*" } -ErrorAction SilentlyContinue

            if ($lockingProcesses) {
                Write-Log '+' "Stopping $($lockingProcesses.Count) locking processes..."
                $lockingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        catch {
            Write-Log '-' "Error while analyzing processes: $_"
        }

        # 2. Release handles using Handle.exe (if available)
        $handlePath = "$env:TEMP\handle.exe"
        if (-not (Test-Path $handlePath)) {
            try {
                Write-Log '+' "Downloading Handle.exe from Sysinternals..."
                Invoke-WebRequest -Uri "https://live.sysinternals.com/handle.exe" -OutFile $handlePath -ErrorAction Stop
            }
            catch {
                Write-Log '-' "Failed to download Handle.exe - continuing without it"
            }
        }

        if (Test-Path $handlePath) {
            try {
                Write-Log '+' "Searching for locked handles with Handle.exe..."
                $output = & $handlePath -accepteula -a -nobanner $folderPath 2>&1
                $handles = $output | Select-String -Pattern "pid:(\d+)\s+type:\w+\s+(\w+):\s+(.*)" | ForEach-Object {
                    [PSCustomObject]@{
                        PID        = $_.Matches.Groups[1].Value
                        HandleType = $_.Matches.Groups[2].Value
                        FilePath   = $_.Matches.Groups[3].Value
                    }
                }

                foreach ($handle in $handles) {
                    try {
                        Write-Log '+' "Closing handle PID $($handle.PID) ($($handle.HandleType))"
                        & $handlePath -accepteula -c $handle.HandleType -p $handle.PID > $null 2>&1
                    }
                    catch {
                        Write-Log '-' "Could not close handle PID $($handle.PID): $_"
                    }
                }
                Start-Sleep -Seconds 1
            }
            catch {
                Write-Log '-' "Handle.exe error: $_"
            }
        }

        # 3. Take ownership of the folder (fixed command)
        Write-Log '+' "Taking ownership of folder..."
        try {
            # Fixed takeown command without invalid /D Y parameter
            takeown /F $folderPath /R | Out-Null

            # Use SID for Administrators group to avoid localization issues
            $adminsSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
            $adminsName = $adminsSid.Translate([System.Security.Principal.NTAccount]).Value

            icacls $folderPath /grant "${adminsName}:F" /T /C /Q | Out-Null
            if ($env:USERDOMAIN -and $env:USERNAME -and $env:USERNAME -notlike '*$') {
                icacls $folderPath /grant "$($env:USERDOMAIN)\$($env:USERNAME):F" /T /C /Q | Out-Null
            }
        }
        catch {
            Write-Log '-' "Ownership change error: $_"
        }

        # 4. Force recursive deletion
        Write-Log '-' "Deleting folder..."
        try {
            # First try standard PowerShell method
            Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
            Write-Log '+' "Folder deleted successfully!"
            return $true
        }
        catch {
            Write-Log '-' "Standard deletion failed - trying alternative methods..."

            # Try robocopy empty folder method (works for locked folders)
            try {
                $emptyDir = "$env:TEMP\empty_$([System.Guid]::NewGuid().ToString())"
                New-Item -ItemType Directory -Path $emptyDir | Out-Null

                Write-Log '-' "Attempting Robocopy mirror deletion..."
                Start-Process -Wait -NoNewWindow -FilePath "robocopy" -ArgumentList "`"$emptyDir`" `"$folderPath`" /mir /njh /njs /ndl /nc /ns /np"
                Remove-Item -Path $emptyDir -Recurse -Force

                if (Test-Path $folderPath) {
                    throw "Robocopy method failed"
                }
                Write-Log '+' "Folder deleted using Robocopy mirror method!"
                return $true
            }
            catch {
                Write-Log '-' "Robocopy method failed: $_"

                # Final fallback to cmd rd
                try {
                    Write-Log '-' "Attempting final fallback with cmd..."
                    cmd /c "rd /s /q `"$folderPath`"" 2>&1 | Out-Null

                    if (Test-Path $folderPath) {
                        throw "Fallback method failed"
                    }
                    Write-Log '+' "Folder deleted using fallback method!"
                    return $true
                }
                catch {
                    Write-Log '-' "Critical deletion failure: $_"
                    return $false
                }
            }
        }
    }
    else {
        Write-Log '+' "Folder does not exist: $folderPath"
        return $true
    }
}

# Main execution
Clear-Host
Write-Host "=== System Folders Cleanup ==="
Write-Host "This script will delete Windows.old and inetpub"
Write-Host "Running as admin: $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

$results = @{}
foreach ($folder in $foldersToDelete) {
    $results[$folder] = DeleteFolder -folderPath $folder
    Write-Host "`n"
}

# Summary
Write-Host "=== Summary ==="
foreach ($result in $results.GetEnumerator()) {
    $status = if ($result.Value) { "SUCCESS" } else { "FAILED" }
    if ($result.Value) {
        Write-Log '+' "$($result.Key): $status"
    } else {
        Write-Log '-' "$($result.Key): $status"
    }
}

Write-Log '+' 'Operation complete. The script will now exit.'
# Exit cleanly
exit 0
