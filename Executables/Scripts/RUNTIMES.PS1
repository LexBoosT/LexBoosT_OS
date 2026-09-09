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

        $process = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log '+' "$PackageId installed successfully."
        }
        else {
            Write-Log '-' "Failed to install $PackageId (Exit code: $($process.ExitCode))."
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

    if (& $Test) {
        Write-Log '+' "$PackageId is already installed. Skipping."
        return
    }

    Install-Winget
    Install-WingetPackage -PackageId $PackageId -ExtraArgs $ExtraArgs
}

function Test-DotNetDesktopRuntime {
    param ([int]$MajorVersion)

    if (-not (Test-CommandAvailable -Name "dotnet")) {
        return $false
    }

    $runtimes = & dotnet --list-runtimes 2>$null
    return [bool]($runtimes | Where-Object { $_ -match "^Microsoft\.WindowsDesktop\.App\s+$MajorVersion\." })
}

function Test-DotNetSdk {
    param ([int]$MajorVersion)

    if (-not (Test-CommandAvailable -Name "dotnet")) {
        return $false
    }

    $sdks = & dotnet --list-sdks 2>$null
    return [bool]($sdks | Where-Object { $_ -match "^$MajorVersion\." })
}


function Test-DirectXLegacyRuntime {
    $systemRoots = @("$env:WINDIR\System32")
    if ([Environment]::Is64BitOperatingSystem) {
        $systemRoots += "$env:WINDIR\SysWOW64"
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

# NanaZip
Install-WingetPackageIfMissing -PackageId "M2Team.NanaZip" -Test {
    Test-WingetPackageInstalled -PackageId "M2Team.NanaZip"
}


# .NET 8
Install-WingetPackageIfMissing -PackageId "Microsoft.DotNet.SDK.8" -Test {
    Test-DotNetSdk -MajorVersion 8
}
Install-WingetPackageIfMissing -PackageId "Microsoft.DotNet.DesktopRuntime.8" -Test {
    Test-DotNetDesktopRuntime -MajorVersion 8
}

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
    $paths = @("$env:WINDIR\System32\OpenAL32.dll")
    if ([Environment]::Is64BitOperatingSystem) {
        $paths += "$env:WINDIR\SysWOW64\OpenAL32.dll"
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
Install-WingetPackageIfMissing -PackageId "Microsoft.Xna.Framework" -Test {
    $regPath = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\XNA\Framework\v4.0'
    return [bool](Test-Path $regPath)
}

# Notepad++
Install-WingetPackageIfMissing -PackageId "Notepad++.Notepad++" -Test {
    Test-WingetPackageInstalled -PackageId "Notepad++.Notepad++"
}

# PowerShell
Install-WingetPackageIfMissing -PackageId "Microsoft.PowerShell" -Test {
    Test-WingetPackageInstalled -PackageId "Microsoft.PowerShell"
}

Write-Log '+' "Script completed."
# Exit cleanly
exit 0
