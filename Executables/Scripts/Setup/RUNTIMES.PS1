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
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        Write-Log '+' "Chocolatey installed successfully."
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

# .NET Desktop Runtime
Install-WingetPackageIfMissing -PackageId "Microsoft.DotNet.DesktopRuntime.7" -Test {
    Test-DotNetDesktopRuntime -MajorVersion 7
}
Install-WingetPackageIfMissing -PackageId "Microsoft.DotNet.DesktopRuntime.8" -Test {
    Test-DotNetDesktopRuntime -MajorVersion 8
}
Install-WingetPackageIfMissing -PackageId "Microsoft.DotNet.DesktopRuntime.9" -Test {
    Test-DotNetDesktopRuntime -MajorVersion 9
}

# VC++ Redistributables
function Test-VCRedistInstalled {
    param([string]$VersionKey)

    $patterns = @{
        '2005-x64'  = 'Microsoft Visual C\+\+ 2005.*Redistributable.*x64'
        '2005-x86'  = 'Microsoft Visual C\+\+ 2005.*Redistributable.*x86'
        '2008-x64'  = 'Microsoft Visual C\+\+ 2008.*Redistributable.*x64'
        '2008-x86'  = 'Microsoft Visual C\+\+ 2008.*Redistributable.*x86'
        '2010-x64'  = 'Microsoft Visual C\+\+ 2010.*x64.*Redistributable'
        '2010-x86'  = 'Microsoft Visual C\+\+ 2010.*x86.*Redistributable'
        '2012-x64'  = 'Microsoft Visual C\+\+ 2012.*Redistributable.*x64'
        '2012-x86'  = 'Microsoft Visual C\+\+ 2012.*Redistributable.*x86'
        '2013-x64'  = 'Microsoft Visual C\+\+ 2013.*Redistributable.*x64'
        '2013-x86'  = 'Microsoft Visual C\+\+ 2013.*Redistributable.*x86'
        '2015+-x64' = 'Microsoft Visual C\+\+ 2015.*Redistributable.*x64'
        '2015+-x86' = 'Microsoft Visual C\+\+ 2015.*Redistributable.*x86'
    }

    if (-not $patterns.ContainsKey($VersionKey)) { return $false }
    $pattern = $patterns[$VersionKey]

    $uninstallPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    if ([Environment]::Is64BitOperatingSystem) {
        $uninstallPaths += 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    }

    foreach ($uninstallPath in $uninstallPaths) {
        if (-not (Test-Path $uninstallPath)) { continue }
        $keys = Get-ChildItem -Path $uninstallPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            try {
                $displayName = (Get-ItemProperty -Path $key.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                if ($displayName -and $displayName -match $pattern) { return $true }
            }
            catch {}
        }
    }
    return $false
}

$vcTempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $vcTempDir -Force | Out-Null

try {
    function Invoke-VCRedistDownload {
        param(
            [Parameter(Mandatory = $true)][string]$Uri,
            [Parameter(Mandatory = $true)][string]$Destination,
            [Parameter(Mandatory = $true)][string]$Description
        )
        Write-Log '+' "Downloading $Description..."
        & curl.exe -LSs $Uri -o $Destination --connect-timeout 10 --retry 5 --retry-delay 0 --retry-all-errors
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            throw "Downloading $Description from '$Uri' failed with exit code $LASTEXITCODE."
        }
    }

    function Invoke-VCRedistInstaller {
        param(
            [Parameter(Mandatory = $true)][string]$FilePath,
            [Parameter(Mandatory = $true)][string]$ArgumentList,
            [Parameter(Mandatory = $true)][string]$Description,
            [int[]]$SuccessExitCode = @(0, 1638)
        )
        Write-Log '+' "Installing $Description..."
        $process = Start-Process -FilePath $FilePath -WindowStyle Hidden -ArgumentList $ArgumentList -Wait -PassThru
        if ($process.ExitCode -notin $SuccessExitCode) {
            Write-Log '-' "Warning: Installing $Description returned exit code $($process.ExitCode)."
        }
    }

    $legacyArgs = '/q /norestart'
    $modernArgs = '/install /quiet /norestart'
    $msiArgs = '/qn /quiet /norestart ALLUSERS=1 REBOOT=ReallySuppress'

    $vcredists = [ordered] @{
        'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.exe'                = @('2005-x64', '/c /q /t:')
        'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.exe'                = @('2005-x86', '/c /q /t:')
        'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe'                = @('2008-x64', $legacyArgs)
        'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe'                = @('2008-x86', $legacyArgs)
        'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe'                = @('2010-x64', $legacyArgs)
        'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'                = @('2010-x86', $legacyArgs)
        'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe'          = @('2012-x64', $modernArgs)
        'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe'          = @('2012-x86', $modernArgs)
        'https://download.visualstudio.microsoft.com/download/pr/10912041/cee5d6bca2ddbcd039da727bf4acb48a/vcredist_x64.exe' = @('2013-x64', $modernArgs)
        'https://download.visualstudio.microsoft.com/download/pr/10912113/5da66ddebb0ad32ebd4b922fd82e8e25/vcredist_x86.exe' = @('2013-x86', $modernArgs)
        'https://aka.ms/vs/17/release/vc_redist.x64.exe'                                                                     = @('2015+-x64', $modernArgs)
        'https://aka.ms/vs/17/release/vc_redist.x86.exe'                                                                     = @('2015+-x86', $modernArgs)
    }

    foreach ($entry in $vcredists.GetEnumerator()) {
        $vcName = $entry.Value[0]
        if (Test-VCRedistInstalled -VersionKey $vcName) {
            Write-Log '+' "Visual C++ Runtime $vcName is already installed. Skipping."
            continue
        }
        $vcArgs = $entry.Value[1]
        $vcExePath = Join-Path -Path $vcTempDir -ChildPath "vcredist-$vcName.exe"
        Invoke-VCRedistDownload -Uri $entry.Name -Destination $vcExePath -Description "Visual C++ Runtime $vcName"

        if ($vcArgs -match ':') {
            $msiDir = Join-Path -Path $vcTempDir -ChildPath "vcredist-$vcName"
            Invoke-VCRedistInstaller -FilePath $vcExePath -ArgumentList ($vcArgs + '"' + $msiDir + '"') -Description "Visual C++ Runtime $vcName extractor"
            $msiPaths = @(Get-ChildItem -LiteralPath $msiDir -Filter '*.msi' -ErrorAction SilentlyContinue)
            if (-not $msiPaths) {
                Write-Log '-' "Failed to extract MSI for $vcName, not installing."
                continue
            }
            foreach ($msi in $msiPaths) {
                $msiArguments = '/log "' + (Join-Path -Path $msiDir -ChildPath 'logfile.log') + '" /i "' + $msi.FullName + '" ' + $msiArgs
                Invoke-VCRedistInstaller -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Description "Visual C++ Runtime $vcName MSI"
            }
        }
        else {
            Invoke-VCRedistInstaller -FilePath $vcExePath -ArgumentList $vcArgs -Description "Visual C++ Runtime $vcName"
        }
    }
}
finally {
    if ($vcTempDir -and (Test-Path -LiteralPath $vcTempDir -PathType Container)) {
        Remove-Item -LiteralPath $vcTempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# DirectX legacy runtime
Install-DirectXLegacyIfMissing

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
