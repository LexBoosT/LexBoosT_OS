$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    }
    exit
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Test-CommandAvailable {
    param ([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-Winget {
    if (Test-CommandAvailable -Name "winget") {
        Write-Log '+' "Winget is already installed."
        return
    }

    Write-Log '+' "Installing Winget..."
    try {
        $installer = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $installer
        Add-AppxPackage -Path $installer -ErrorAction Stop
        if (Test-CommandAvailable -Name "winget") {
            Write-Log '+' "Winget installed successfully."
        }
        else {
            Write-Log '-' "Winget installation completed but winget.exe is not available. A reboot may be required."
        }
    }
    catch {
        Write-Log '-' "Failed to install Winget: $($_.Exception.Message)"
    }
}

function Install-Chocolatey {
    if (Test-CommandAvailable -Name "choco") {
        Write-Log '+' "Chocolatey is already installed."
        return
    }

    Write-Log '+' "Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        $env:ChocolateyInstall = Convert-Path "$env:ProgramData\chocolatey"
        $env:Path = "$env:ChocolateyInstall\bin;$env:Path"
        [Environment]::SetEnvironmentVariable('ChocolateyInstall', $env:ChocolateyInstall, 'Machine')
        [Environment]::SetEnvironmentVariable('Path', "$env:ChocolateyInstall\bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine'), 'Machine')

        if (Test-CommandAvailable -Name "choco") {
            Write-Log '+' "Chocolatey installed successfully."
        } else {
            Write-Log '-' "Chocolatey installation completed but choco.exe is not available. A reboot may be required."
        }
    }
    catch {
        Write-Log '-' "Failed to install Chocolatey: $($_.Exception.Message)"
    }
}

# Run winget, capture stdout+stderr to a temp file, decode as UTF-8 and print
# it cleanly. Fixes garbled/mojibake output on non-English locales where the
# console OEM code page differs from winget's UTF-8 output.
function Invoke-Winget {
    param([string[]]$WingetArgs)

    $outFile  = Join-Path $env:TEMP ('winget-out-' + [guid]::NewGuid().ToString() + '.txt')
    $errFile  = $outFile + '.err'
    $exitCode = -1
    $text     = ''
    $errText  = ''
    try {
        $process = Start-Process -FilePath 'winget.exe' `
            -ArgumentList ($WingetArgs -join ' ') `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError  $errFile
        $exitCode = $process.ExitCode
        $text     = [System.IO.File]::ReadAllText($outFile, [System.Text.Encoding]::UTF8)
        $errText  = [System.IO.File]::ReadAllText($errFile, [System.Text.Encoding]::UTF8)
    }
    catch {
        $text = 'Failed to launch winget: ' + $_.Exception.Message
    }
    finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    foreach ($line in (($text + [Environment]::NewLine + $errText) -split "`r?`n")) {
        if ($line.Trim()) { Write-Host ('    winget> ' + $line) }
    }
    return @{ ExitCode = $exitCode; Output = $text }
}
function Install-WingetPackage {
    param (
        [string]$PackageId,
        [string]$Source = "winget",
        [string[]]$ExtraArgs = @()
    )

    if (-not (Test-CommandAvailable -Name "winget")) {
        Write-Log '-' "Cannot install $PackageId because Winget is not available."
        return
    }

    Write-Log '+' "Installing $PackageId..."
    try {
        $wingetArgs = @(
            "install",
            "--id", $PackageId,
            "--exact",
            "--source", $Source,
            "--accept-source-agreements",
            "--disable-interactivity",
            "--silent",
            "--accept-package-agreements"
        )
        if ($ExtraArgs) {
            $wingetArgs += $ExtraArgs
        }

        $result = Invoke-Winget -WingetArgs $wingetArgs
        if ($result.ExitCode -eq 0) {
            Write-Log '+' "$PackageId installed successfully."
        }
        else {
            # winget exit codes are HRESULTs (negative in .NET). 0x8A15002B means
            # "no available upgrade found" (package already installed and up to
            # date) - not a real failure, so don't log it as one.
            $hr = [int64]$result.ExitCode + 4294967296
            if ($hr -eq 0x8A15002B) {
                Write-Log '+' "$PackageId is already installed and up to date."
            }
            else {
                Write-Log '-' "Failed to install $PackageId (Exit code: $($result.ExitCode), 0x$('{0:X8}' -f $hr))."
            }
        }
    }
    catch {
        Write-Log '-' "Error installing $PackageId - $($_.Exception.Message)"
    }
}

function Test-WingetPackageInstalled {
    param ([string]$PackageId)

    if (-not (Test-CommandAvailable -Name "winget")) {
        return $false
    }

    $output = winget.exe list --id $PackageId --exact --source winget --accept-source-agreements 2>$null
    return [bool]($output | Where-Object { $_ -match [regex]::Escape($PackageId) })
}

function Install-WingetPackageIfMissing {
    param (
        [string]$PackageId,
        [scriptblock]$Test,
        [string[]]$ExtraArgs = @()
    )

    if (($Test -is [scriptblock]) -and (& $Test)) {
        Write-Log '+' "$PackageId is already installed. Skipping."
        return
    }

    Install-Winget
    Install-WingetPackage -PackageId $PackageId -ExtraArgs $ExtraArgs
}

function Test-DirectXLegacyRuntime {
    $systemRoots = @("$env:SystemRoot\System32")
    if ([Environment]::Is64BitOperatingSystem) {
        $systemRoots += "$env:SystemRoot\SysWOW64"
    }

    $requiredFiles = @(
        "d3dx9_24.dll", "d3dx9_43.dll",
        "d3dcompiler_43.dll", "d3dcompiler_47.dll",
        "xinput1_3.dll", "XAudio2_7.dll"
    )
    foreach ($root in $systemRoots) {
        $foundCount = 0
        foreach ($file in $requiredFiles) {
            if (Test-Path -LiteralPath (Join-Path $root $file)) {
                $foundCount++
            }
        }
        if ($foundCount -eq 0) { return $false }
    }

    return $true
}

function Install-DirectXLegacyIfMissing {
    if (Test-DirectXLegacyRuntime) {
        Write-Log '+' "DirectX legacy runtime is already installed. Skipping."
        return
    }

    Install-Chocolatey
    if (Test-CommandAvailable -Name "choco") {
        Write-Log '+' "Installing DirectX legacy runtime..."
        try {
            $process = Start-Process -FilePath "choco" -ArgumentList @("install", "-y", "directx", "--allow-empty-checksums") -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-Log '+' "DirectX legacy runtime installed successfully."
            } else {
                Write-Log '-' "DirectX installation returned exit code $($process.ExitCode). DirectX components may still be functional."
            }
        } catch {
            Write-Log '-' "Failed to install DirectX legacy runtime: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log '-' "Cannot install DirectX legacy runtime, Chocolatey is not available."
    }
}

function Test-DotNetRuntime {
    try {
        $installed = & dotnet --list-runtimes 2>$null
        if ($installed -match 'Microsoft\.NETCore\.App') { return $true }
    } catch {}
    return $false
}

function Install-DotNetRuntimeIfMissing {
    if (Test-DotNetRuntime) {
        Write-Log '+' ".NET runtime is already installed. Skipping."
        return
    }

    Install-Chocolatey
    if (Test-CommandAvailable -Name "choco") {
        Write-Log '+' "Installing .NET runtime..."
        try {
            $process = Start-Process -FilePath "choco" -ArgumentList @("install", "-y", "dotnet-runtime", "--no-progress") -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-Log '+' ".NET runtime installed successfully."
            } else {
                Write-Log '-' ".NET runtime installation returned exit code $($process.ExitCode)."
            }
        } catch {
            Write-Log '-' "Failed to install .NET runtime: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log '-' "Cannot install .NET runtime, Chocolatey is not available."
    }
}

# NanaZip
Install-WingetPackageIfMissing -PackageId "M2Team.NanaZip" -Test { Test-WingetPackageInstalled -PackageId "M2Team.NanaZip" }
# .NET 10 (via Chocolatey)
Install-DotNetRuntimeIfMissing

# VC++ Redistributables (AIO abbodi1406 - latest release)
$vcAioUrl = 'https://github.com/abbodi1406/vcredist/releases/latest/download/VisualCppRedist_AIO_x86_x64.exe'

$vcTempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $vcTempDir -Force | Out-Null

try {
    $vcAioExe = Join-Path -Path $vcTempDir -ChildPath 'VisualCppRedist_AIO_x86_x64.exe'

    Write-Log '+' "Downloading VisualCppRedist_AIO_x86_x64.exe (latest release)..."
    & curl.exe -LSsL $vcAioUrl -o $vcAioExe --connect-timeout 10 --retry 5 --retry-delay 0 --retry-all-errors
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $vcAioExe -PathType Leaf)) {
        throw "Downloading VisualCppRedist_AIO_x86_x64.exe from '$vcAioUrl' failed with exit code $LASTEXITCODE."
    }

    Write-Log '+' "Installing Visual C++ Redistributables (x86 + x64)..."
    $process = Start-Process -FilePath $vcAioExe -WindowStyle Hidden -ArgumentList '/ai /gm2' -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Log '-' "Warning: Visual C++ Redistributable installation returned exit code $($process.ExitCode)."
    }
}
finally {
    if ($vcTempDir -and (Test-Path -LiteralPath $vcTempDir -PathType Container)) {
        Remove-Item -LiteralPath $vcTempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# DirectX legacy runtime
Install-DirectXLegacyIfMissing

# OpenAL
function Test-OpenALInstalled {
    $paths = @("$env:SystemRoot\System32\OpenAL32.dll")
    if ([Environment]::Is64BitOperatingSystem) {
        $paths += "$env:SystemRoot\SysWOW64\OpenAL32.dll"
    }
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) { return $true }
    }
    return $false
}

function Install-OpenALIfMissing {
    if (Test-OpenALInstalled) {
        Write-Log '+' "OpenAL is already installed. Skipping."
        return
    }

    Install-Chocolatey
    if (Test-CommandAvailable -Name "choco") {
        Write-Log '+' "Installing OpenAL..."
        try {
            $process = Start-Process -FilePath "choco" -ArgumentList @("install", "-y", "openal") -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-Log '+' "OpenAL installed successfully."
            } else {
                Write-Log '-' "OpenAL installation returned exit code $($process.ExitCode)."
            }
        } catch {
            Write-Log '-' "Failed to install OpenAL: $($_.Exception.Message)"
        }
    } else {
        Write-Log '-' "Cannot install OpenAL, Chocolatey is not available."
    }
}

Install-OpenALIfMissing

# XNA Framework
Install-WingetPackageIfMissing -PackageId "Microsoft.XNARedist" -Test { [bool](Test-Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\XNA\Framework\v4.0') }

# Notepad++
Install-WingetPackageIfMissing -PackageId "Notepad++.Notepad++" -Test { Test-WingetPackageInstalled -PackageId "Notepad++.Notepad++" }

# PowerShell
Install-WingetPackageIfMissing -PackageId "Microsoft.PowerShell" -Test { Test-WingetPackageInstalled -PackageId "Microsoft.PowerShell" }

# Node.js LTS (includes npm)
Install-WingetPackageIfMissing -PackageId "OpenJS.NodeJS.LTS" -Test { Test-CommandAvailable -Name "npm" }

Write-Log '+' "Script completed."
# Exit cleanly
exit 0
