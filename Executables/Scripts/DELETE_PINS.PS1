#Requires -Version 5.1

[CmdletBinding()]
param()

function Remove-UserTaskbarPins {
    param(
        [Parameter(Mandatory)]
        [string]$Hive,
        [Parameter(Mandatory)]
        [string]$UserName
    )

    try {
        # --- Resolve this profile's Local AppData / AppData from its hive ---
        $shellFolders = "HKU:\$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
        if (-not (Test-Path $shellFolders)) {
            Write-Verbose "[$UserName] No Shell Folders key, skipping."
            return
        }

        $localAppData = (Get-ItemProperty -Path $shellFolders -Name "Local AppData" -ErrorAction SilentlyContinue).("Local AppData")
        $appData      = (Get-ItemProperty -Path $shellFolders -Name "AppData"      -ErrorAction SilentlyContinue).AppData

        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            Write-Verbose "[$UserName] Could not resolve Local AppData, skipping."
            return
        }

        # --- WIN11: button@*.json in Local\Microsoft\Windows\Explorer ---
        $explorerDir = Join-Path $localAppData "Microsoft\Windows\Explorer"
        if (Test-Path $explorerDir) {
            $pins = Get-ChildItem -Path $explorerDir -Filter "button@*.json" -ErrorAction SilentlyContinue
            foreach ($p in $pins) {
                try {
                    Remove-Item $p.FullName -Force -ErrorAction Stop
                    Write-Verbose "[$UserName] Removed Win11 pin: $($p.Name)"
                }
                catch {
                    Write-Verbose "[$UserName] Failed to remove $($p.Name): $($_.Exception.Message)"
                }
            }
            if (-not $pins) {
                Write-Verbose "[$UserName] No Win11 button@*.json pins found."
            }
        }
        else {
            Write-Verbose "[$UserName] No Explorer dir at $explorerDir."
        }

        # --- WIN10 (legacy): Quick Launch\User Pinned\TaskBar shortcuts ---
        if (-not [string]::IsNullOrWhiteSpace($appData)) {
            $taskbarLnk = Join-Path $appData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
            if (Test-Path $taskbarLnk) {
                Get-ChildItem $taskbarLnk -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item $_.FullName -Force -ErrorAction Stop
                        Write-Verbose "[$UserName] Removed Win10 pin: $($_.Name)"
                    }
                    catch {
                        Write-Verbose "[$UserName] Failed to remove $($_.Name): $($_.Exception.Message)"
                    }
                }
            }
        }

        # --- Taskband registry leftovers (Win10 favs) ---
        $taskband = "HKU:\$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        if (Test-Path $taskband) {
            Remove-ItemProperty -Path $taskband -Name "Favorites"        -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $taskband -Name "FavoritesResolve" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $taskband -Name "FavoritesChanges" -ErrorAction SilentlyContinue
            Write-Verbose "[$UserName] Cleaned Taskband registry entries."
        }

        Write-Verbose "[$UserName] Taskbar pin cleanup complete."
    }
    catch {
        Write-Verbose "[$UserName] Error during cleanup: $($_.Exception.Message)"
    }
}

# --- Enumerate all user hives (S-1-... and AME_UserHive_*) ---
$script:removedHives = @()
$script:seen         = @{}

$hives = Get-ChildItem -Path "HKU:\" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^S-1-|^AME_UserHive_' }

foreach ($hive in $hives) {
    $name = $hive.PSChildName

    # Skip the transient Default / Default User hives (no real pins there)
    if ($name -match 'S-1-5-18' -or $name -eq 'S-1-5-21') { continue }

    # De-duplicate: a hive can appear for both a mounted and a logged-in session
    if ($script:seen.ContainsKey($name)) { continue }
    $script:seen[$name] = $true

    # Best-effort friendly name via ProfileList (canonical location)
    $friendly = $name
    try {
        $profileName = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$name" `
            -Name "ProfileName" -ErrorAction SilentlyContinue).ProfileName
        if ($profileName) { $friendly = "$profileName ($name)" }
    }
    catch { }

    Write-Verbose "Processing user hive: $friendly"
    Remove-UserTaskbarPins -Hive $name -UserName $friendly
    $script:removedHives += $friendly
}

Write-Host "Taskbar pins removed for $($script:removedHives.Count) profile(s)."
exit 0
