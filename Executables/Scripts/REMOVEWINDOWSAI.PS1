#Requires -Version 5.1

$aiCommand = '& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/zoicware/RemoveWindowsAI/main/RemoveWindowsAi.ps1"))) -nonInteractive -Options DisableRegKeys,RemoveAppxPackages,PreventAIPackageReinstall,RemoveRecallFeature,RemoveCBSPackages,RemoveAIFiles,HideAIComponents,DisableRewrite,RemoveWindowsAITasks,UpdateCleanupCheck'

# --- Elevation / permission helpers -----------------------------------

function Test-IsElevated {
    $level = 0
    foreach ($line in (whoami /groups 2>$null)) {
        if ($line -match 'S-1-16-(\d+)') {
            $n = [int]$Matches[1]
            if ($n -gt $level) { $level = $n }
        }
    }
    return ($level -ge 16384)
}

function Test-HasAdminAccess {
    $probe = 'HKLM:\Software\AJLauncherProbe'
    try {
        $null = New-Item -Path $probe -ErrorAction Stop
        Remove-Item $probe -Force -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

$uacEnabled = $true
try {
    $val = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop).EnableLUA
    $uacEnabled = ($val -ne 0)
} catch { $uacEnabled = $true }

# --- Decide -----------------------------------------------------------

$elev   = Test-IsElevated
$access = Test-HasAdminAccess

if ($elev -or $access) {
    # We have admin access, run directly (no relaunch needed)
    Write-Host "OK: running with admin access (elevated=$elev, hkml-access=$access)"
} else {
    # No direct access, try UAC
    if ($uacEnabled -and $PSCommandPath) {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile',
                            '-ExecutionPolicy', 'Bypass',
                            '-WindowStyle', 'Hidden',
                            '-File', $PSCommandPath) `
            -Verb RunAs
        exit
    } else {
        Write-Error 'No admin access and UAC is disabled. Cannot continue.'
        exit 1
    }
}

# --- Execution --------------------------------------------------------

$logFile = Join-Path $env:TEMP 'RemoveWindowsAI.log'
$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

try {
    "=== START | $stamp ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
    & ([scriptblock]::Create($aiCommand)) *>&1 | Out-File -FilePath $logFile -Append -Encoding UTF8
    "=== END (OK) | " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
}
catch {
    "=== ERROR | $stamp ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Message : $($_.Exception.Message)" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Stack   : $($_.ScriptStackTrace)"  | Out-File -FilePath $logFile -Append -Encoding UTF8
    exit 1
}
