$ErrorActionPreference = "Continue"

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FileOps {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, uint dwFlags);
    public const uint MOVEFILE_REPLACE_EXISTING = 0x1;
    public const uint MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;
}
'@

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Move-FileAtReboot {
    param([string]$Source, [string]$Dest)
    $flags = [FileOps]::MOVEFILE_REPLACE_EXISTING -bor [FileOps]::MOVEFILE_DELAY_UNTIL_REBOOT
    [FileOps]::MoveFileEx($Source, $Dest, $flags)
}

function Test-Laptop {
    $isLaptop = $false
    $mobileChassisTypes = @(8, 9, 10, 11, 12, 13, 14, 18, 21, 30, 31, 32)

    try {
        $chassis = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        if ($chassis.ChassisTypes | Where-Object { $_ -in $mobileChassisTypes }) {
            $isLaptop = $true
        }
    } catch {
        Write-Verbose "Unable to read chassis type: $($_.Exception.Message)"
    }

    if (-not $isLaptop) {
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem.PCSystemType -eq 2 -or $computerSystem.PCSystemTypeEx -in @(2, 8)) {
                $isLaptop = $true
            }
        } catch {
            Write-Verbose "Unable to read PC system type: $($_.Exception.Message)"
        }
    }

    if (-not $isLaptop) {
        try {
            if (Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop) {
                $isLaptop = $true
            }
        } catch {
            Write-Verbose "Unable to read battery presence: $($_.Exception.Message)"
        }
    }

    return $isLaptop
}

function Copy-GpuProfileVariant {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GpuToolsPath
    )

    if (-not (Test-Path -LiteralPath $GpuToolsPath)) {
        Write-Log '-' "GPU tools folder not found: $GpuToolsPath"
        return
    }

    $profileVariant = if (Test-Laptop) { "Laptop" } else { "Desktop" }
    Write-Log '+' "Using $profileVariant NVIDIA profile variant"

    $profilePairs = @(
        @{ Source = "Profiles\$profileVariant\Lex_Profile.nip"; Target = "Lex_Profile.nip" },
        @{ Source = "Profiles\$profileVariant\Lex_Profile_GSYNC.nip"; Target = "Lex_Profile_GSYNC.nip" }
    )

    foreach ($profilePair in $profilePairs) {
        $source = Join-Path -Path $GpuToolsPath -ChildPath $profilePair.Source
        $target = Join-Path -Path $GpuToolsPath -ChildPath $profilePair.Target

        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $target -Force
        } else {
            Write-Log '-' "$($profilePair.Target) variant not found for $profileVariant"
        }
    }
}

$scriptDir = Split-Path -Parent $PSCommandPath
$executablesDir = Split-Path -Parent $scriptDir
$sourcePath = Join-Path -Path $executablesDir -ChildPath "LexBoosTOS"
$destPath = Join-Path -Path $env:WINDIR -ChildPath "LexBoosTOS"

if (-not (Test-Path -LiteralPath $destPath)) {
    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
}

if (Test-Path -LiteralPath $sourcePath) {
    $blurMica = Join-Path $destPath "Utilities\SystemTools\ExplorerBlurMica.dll"
    $wasBlurMicaLocked = $false
    if (Test-Path $blurMica) {
        try {
            $fs = [System.IO.File]::Open($blurMica, 'Open', 'ReadWrite', 'None')
            $fs.Close()
        } catch {
            $wasBlurMicaLocked = $true
        }
    }

    $shellDll = Join-Path $destPath "Utilities\NilesoftShell\Lex_Nilesoft_Shell\shell.dll"
    $wasShellLocked = $false
    if (Test-Path $shellDll) {
        try {
            $fs = [System.IO.File]::Open($shellDll, 'Open', 'ReadWrite', 'None')
            $fs.Close()
        } catch {
            $wasShellLocked = $true
        }
    }

    if ($wasShellLocked) {
        Write-Log '+' 'Unregistering current shell extension...'
        regsvr32 /u /s "$shellDll"
        Start-Sleep -Seconds 1
    }

    if ($wasBlurMicaLocked) {
        Write-Log '+' 'Unregistering current BlurMica...'
        regsvr32 /u /s "$blurMica"
        Start-Sleep -Seconds 1
    }

    $shellSrc = Join-Path $sourcePath 'Utilities\NilesoftShell\Lex_Nilesoft_Shell\shell.dll'
    $shellDst = Join-Path $destPath 'Utilities\NilesoftShell\Lex_Nilesoft_Shell\shell.dll'
    $blurSrc = Join-Path $sourcePath 'Utilities\SystemTools\ExplorerBlurMica.dll'
    $blurDst = Join-Path $destPath 'Utilities\SystemTools\ExplorerBlurMica.dll'

    $timerXmlDst = Join-Path $destPath 'Utilities\TimerResolution\Force Timer Resolution.xml'
    $robocopyArgs = @($sourcePath, $destPath, '/E', '/PURGE', '/IM', '/IT', '/NP', '/NFL', '/NDL', '/R:3', '/W:2',
                      '/XF', 'shell.dll', 'ExplorerBlurMica.dll')
    if (Test-Path -LiteralPath $timerXmlDst) {
        $robocopyArgs += 'Force Timer Resolution.xml'
        Write-Log '+' 'Preserving existing Force Timer Resolution.xml'
    }
    $robocopyArgs += @('/XD', 'Logs', 'Backup')
    & robocopy @robocopyArgs

    foreach ($pair in @(@{S=$shellSrc; D=$shellDst}, @{S=$blurSrc; D=$blurDst})) {
        if (Test-Path $pair.S) {
            try {
                Copy-Item -LiteralPath $pair.S -Destination $pair.D -Force -ErrorAction Stop
                Write-Log '+' "Copied: $(Split-Path $pair.D -Leaf)"
            } catch {
                Write-Log '-' "Locked, scheduling replace at reboot: $(Split-Path $pair.D -Leaf)"
                $rebootName = "$($pair.D).LexBoosT_new"
                Copy-Item -LiteralPath $pair.S -Destination $rebootName -Force -ErrorAction SilentlyContinue
                Move-FileAtReboot -Source $rebootName -Dest $pair.D
            }
        }
    }

    Copy-GpuProfileVariant -GpuToolsPath (Join-Path -Path $destPath -ChildPath "Utilities\GPU_Tools")

    if ($wasBlurMicaLocked) {
        $blurDll = Join-Path $destPath 'Utilities\SystemTools\ExplorerBlurMica.dll'
        if (Test-Path $blurDll) { regsvr32 /s "$blurDll" }
    }

    if ($wasShellLocked) {
        $shellExe = Join-Path $destPath "Utilities\NilesoftShell\Lex_Nilesoft_Shell\shell.exe"
        if (Test-Path $shellExe) {
            Start-Process -FilePath $shellExe -ArgumentList "-register" -Wait -WindowStyle Hidden
        }
    }

    Write-Log '+' 'Done'
} else {
    Write-Log '-' "LexBoosTOS folder not found: $sourcePath"
}

# Exit cleanly
exit 0
