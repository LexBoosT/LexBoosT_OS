#Requires -Version 5.1

[CmdletBinding()]
param()

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

begin {
    Write-Log '+' 'Starting to remove default pinned applications from taskbar'
}

process {
    try {
        # Method 1: Remove shortcuts from Quick Launch folder
        Write-Log '-' 'Method 1: Removing shortcuts from Quick Launch folder...'
        $pinnedPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

        if (Test-Path $pinnedPath) {
            # Remove all .lnk files in the pinned folder (aggressive cleanup)
            Get-ChildItem $pinnedPath -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Log '-' "Removed shortcut: $($_.Name)"
            }
        }

        # Method 2: Clean registry entries for pinned items
        Write-Log '-' 'Method 2: Cleaning registry entries...'
        $taskbandPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"

        if (Test-Path $taskbandPath) {
            # Remove Favorites and FavoritesResolve entries
            Remove-ItemProperty -Path $taskbandPath -Name "Favorites" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $taskbandPath -Name "FavoritesResolve" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $taskbandPath -Name "FavoritesChanges" -ErrorAction SilentlyContinue
            Write-Log '-' 'Cleaned taskband registry entries'
        }

        # Method 3: Use COM API to unpin applications (if available)
        Write-Log '-' 'Method 3: Using COM API to unpin applications...'
        try {
            $shell = New-Object -ComObject shell.application
            $namespace = $shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}") # Taskbar pinned items

            if ($namespace) {
                # Try to enumerate and remove items
                for ($i = 0; $i -lt $namespace.Items().Count; $i++) {
                    $item = $namespace.Items().Item($i)
                    if ($item -and ($item.Name -match "File Explorer|Microsoft Edge|Microsoft Store|Store")) {
                        # Note: COM API doesn't always allow direct removal, but this helps identify items
                        Write-Log '+' "Found pinned item: $($item.Name)"
                    }
                }
            }
        }
        catch {
            Write-Log '-' "COM API method not available or failed: $_"
        }

    }
    catch {
        Write-Log '-' "An error occurred while removing pinned applications: $_"
    }
}

end {
    Write-Log '+' 'Script execution completed'
}
