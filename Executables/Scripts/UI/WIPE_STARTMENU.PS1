#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host '============================================'
Write-Host '       Wipe StartMenu / Taskbar Pins'
Write-Host '============================================'

# ============================================================
# Helper
# ============================================================
function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ============================================================
# 1. Clean StartMenuLayout.xml
# ============================================================
$layoutXmlPath = "$env:SystemDrive\Windows\StartMenuLayout.xml"
if (Test-Path $layoutXmlPath) {
    Remove-Item $layoutXmlPath -Force
    Write-Log '-' "Removed $layoutXmlPath"
} else {
    Write-Log '+' "$layoutXmlPath not present"
}

# ============================================================
# 2. Copy layout files to Default profile
# ============================================================
$layoutFiles = @('LayoutModification.xml', 'LayoutModification.json', 'DefaultLayouts.xml', 'settings.json')
$shellDirDefault = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
$appInstallerDirDefault = "$env:SystemDrive\Users\Default\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"

New-Item -ItemType Directory -Force -Path $shellDirDefault -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Force -Path $appInstallerDirDefault -ErrorAction SilentlyContinue | Out-Null

foreach ($file in $layoutFiles[0..2]) {
    $src = Join-Path $scriptDir $file
    if (Test-Path $src) {
        Copy-Item $src $shellDirDefault -Force
        Write-Log '+' "Copied $file to Default profile"
    } else {
        Write-Log '-' "Skipped $file (not found)"
    }
}

$settingsSrc = Join-Path $scriptDir 'settings.json'
if (Test-Path $settingsSrc) {
    Copy-Item $settingsSrc $appInstallerDirDefault -Force
    Write-Log '+' "Copied settings.json to Default AppInstaller"
} else {
    Write-Log '-' "Skipped settings.json (not found)"
}

# ============================================================
# 3. Apply to all user hives
# ============================================================
$userHives = Get-ChildItem 'HKU:\' | Where-Object { $_.PSChildName -match '^S-\d+-\d+-\d+-[\d-]+$|^AME_UserHive_' }
$userCount = 0

foreach ($hive in $userHives) {
    $hivePath = $hive.Name
    $sid = $hive.PSChildName

    try {
        $volatile = Get-ItemProperty "$hivePath\Volatile Environment" -ErrorAction Stop
    } catch {
        $volatile = $null
    }
    $isAme = $hive.PSChildName -match '^AME_UserHive_'

    if ($volatile -or $isAme) {
        $userCount++
        Write-Host "  [$sid]"

        # --- Copy layout files to user ---
        try {
            $localAppData = Get-ItemProperty "$hivePath\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name 'Local AppData' -ErrorAction SilentlyContinue
            if ($localAppData -and $localAppData.'Local AppData') {
                $lad = $localAppData.'Local AppData'

                foreach ($file in $layoutFiles[0..2]) {
                    $src = Join-Path $scriptDir $file
                    $destShell = "$lad\Microsoft\Windows\Shell\$file"
                    if (Test-Path $src) {
                        New-Item -ItemType Directory -Force -Path (Split-Path $destShell) -ErrorAction SilentlyContinue | Out-Null
                        Copy-Item $src $destShell -Force
                        Write-Log '+' "  Copied $file"
                    }
                }

                # --- Delete start.bin cache ---
                $startMenuPkg = Get-ChildItem "$lad\Packages" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Microsoft.Windows.StartMenuExperienceHost*' }
                foreach ($pkg in $startMenuPkg) {
                    $binFiles = Get-ChildItem "$($pkg.FullName)\LocalState" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'start\.bin' }
                    foreach ($bf in $binFiles) {
                        Remove-Item $bf.FullName -Force
                        Write-Log '-' "  Removed $($bf.Name)"
                    }
                }

                # --- Copy settings.json ---
                $installerPkg = Get-ChildItem "$lad\Packages" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Microsoft.DesktopAppInstaller*' }
                foreach ($pkg in $installerPkg) {
                    $destSettings = "$($pkg.FullName)\LocalState\settings.json"
                    New-Item -ItemType Directory -Force -Path (Split-Path $destSettings) -ErrorAction SilentlyContinue | Out-Null
                    if (Test-Path $settingsSrc) {
                        Copy-Item $settingsSrc $destSettings -Force
                        Write-Log '+' "  Copied settings.json"
                    }
                }
            }
        } catch {
            Write-Log '-' "  Failed to process user hive"
        }

        # --- Clean CloudStore tilegrid ---
        $cloudStore = "$hivePath\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
        if (Test-Path $cloudStore) {
            $tileKeys = Get-ChildItem $cloudStore -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like '*start.tilegrid*' }
            foreach ($tk in $tileKeys) {
                Remove-Item $tk.PSPath -Force -Recurse
                Write-Log '-' "  Cleared tilegrid: $($tk.PSChildName)"
            }
        }

        # --- Remove Start Config ---
        $startKey = "$hivePath\Software\Microsoft\Windows\CurrentVersion\Start"
        if (Test-Path $startKey) {
            try {
                Remove-ItemProperty $startKey -Name 'Config' -Force -ErrorAction SilentlyContinue
                Write-Log '-' '  Removed Start\Config'
            } catch {}
        }
    }
}

Write-Log '+' "Processed $userCount user hive(s)"

# ============================================================
# 4. Unpin taskbar shortcuts
# ============================================================
Write-Host '--- Taskbar Pins ---'

$pinnedPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
if (Test-Path $pinnedPath) {
    $pins = Get-ChildItem $pinnedPath -Filter '*.lnk' -ErrorAction SilentlyContinue
    if ($pins) {
        foreach ($pin in $pins) {
            Remove-Item $pin.FullName -Force
            Write-Log '-' "Unpinned $($pin.Name)"
        }
        Write-Log '+' 'Taskbar shortcuts removed'
    } else {
        Write-Log '+' 'No taskbar shortcuts to remove'
    }
} else {
    Write-Log '+' 'Pinned path not found'
}

$taskbandPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
if (Test-Path $taskbandPath) {
    @('Favorites', 'FavoritesResolve', 'FavoritesChanges') | ForEach-Object {
        $prop = Get-ItemProperty $taskbandPath -Name $_ -ErrorAction SilentlyContinue
        if ($prop) {
            Remove-ItemProperty -Path $taskbandPath -Name $_ -Force -ErrorAction SilentlyContinue
            Write-Log '-' "Cleared Taskband\$_"
        }
    }
}

try {
    $shell = New-Object -ComObject Shell.Application
    $namespace = $shell.Namespace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
    if ($namespace) {
        for ($i = 0; $i -lt $namespace.Items().Count; $i++) {
            $item = $namespace.Items().Item($i)
            if ($item -and ($item.Name -match 'File Explorer|Microsoft Edge|Microsoft Store|Store')) {
                Write-Log '+' "  COM found: $($item.Name)"
            }
        }
    }
} catch {}

# ============================================================
# 5. Start Menu folders (VisiblePlaces)
# ============================================================
Write-Host '--- Start Menu Folders ---'

$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start'
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
    Write-Log '+' "Created $registryPath"
}

$binaryValue = [byte[]](
    0x86, 0x08, 0x73, 0x52, 0xaa, 0x51, 0x43, 0x42, 0x9f, 0x7b, 0x27, 0x76, 0x58, 0x46, 0x59, 0xd4,
    0xbc, 0x24, 0x8a, 0x14, 0x0c, 0xd6, 0x89, 0x42, 0xa0, 0x80, 0x6e, 0xd9, 0xbb, 0xa2, 0x48, 0x82,
    0xce, 0xd5, 0x34, 0x2d, 0x5a, 0xfa, 0x43, 0x45, 0x82, 0xf2, 0x22, 0xe6, 0xea, 0xf7, 0x77, 0x3c,
    0x2f, 0xb3, 0x67, 0xe3, 0xde, 0x89, 0x55, 0x43, 0xbf, 0xce, 0x61, 0xf3, 0x7b, 0x18, 0xa9, 0x37,
    0x20, 0x06, 0x0b, 0xb0, 0x51, 0x7f, 0x32, 0x4c, 0xaa, 0x1e, 0x34, 0xcc, 0x54, 0x7f, 0x73, 0x15,
    0xa0, 0x07, 0x3f, 0x38, 0x0a, 0xe8, 0x80, 0x4c, 0xb0, 0x5a, 0x86, 0xdb, 0x84, 0x5d, 0xbc, 0x4d,
    0xc5, 0xa5, 0xb3, 0x42, 0x86, 0x7d, 0xf4, 0x42, 0x80, 0xa4, 0x93, 0xfa, 0xca, 0x7a, 0x88, 0xb5,
    0x44, 0x81, 0x75, 0xfe, 0x0d, 0x08, 0xae, 0x42, 0x8b, 0xda, 0x34, 0xed, 0x97, 0xb6, 0x63, 0x94,
    0x4a, 0xb0, 0xbd, 0x74, 0x4a, 0xf9, 0x68, 0x4f, 0x8b, 0xd6, 0x43, 0x98, 0x07, 0x1d, 0xa8, 0xbc
)

Set-ItemProperty -Path $registryPath -Name 'VisiblePlaces' -Value $binaryValue -Type Binary -Force
Write-Log '+' 'VisiblePlaces set'

$shell = New-Object -ComObject Shell.Application
$shell.Windows() | ForEach-Object { $_.Refresh() }
Write-Log '+' 'Explorer refreshed'

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
