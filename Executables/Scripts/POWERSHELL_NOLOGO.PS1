$ErrorActionPreference = "Stop"

$settingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path -LiteralPath $settingsPath)) {
    exit 0
}

try {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.profiles -or -not $settings.profiles.list) {
        exit 0
    }

    foreach ($termProfile in $settings.profiles.list) {
        if (-not $termProfile.commandline) {
            continue
        }

        $commandLine = [string]$termProfile.commandline
        if ($commandLine -like "*WindowsPowerShell\v1.0\powershell.exe*" -and $commandLine -notmatch "(^|\s)-NoLogo(\s|$)") {
            $termProfile.commandline = [string]::Concat($commandLine, " -NoLogo")
        }
    }

    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}
catch {
    Write-Warning "Windows Terminal PowerShell -NoLogo configuration skipped: $_"
}

# Exit cleanly
exit 0
