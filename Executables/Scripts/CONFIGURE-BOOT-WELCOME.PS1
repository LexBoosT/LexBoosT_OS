#Requires -RunAsAdministrator
#Requires -Version 5.1
# =============================================================================
# Configure Boot Welcome (LexBoosT OS)
#
# Installs the post-sign-in branded welcome panel. It:
#   1. Enables Windows' native VerboseStatus loading text on the secure
#      Welcome / "Please wait" screen.
#   2. Deploys SHOW-WELCOME-PANEL.PS1 + a hidden VBS launcher to
#      C:\ProgramData\LexBoosTOS\Welcome.
#   3. Registers an interactive LOGON scheduled task ("LexBoosT OS - Welcome")
#      so the panel is NOT listed under Task Manager > Startup apps.
#   4. Drops idempotency markers under HKLM:\SOFTWARE\LexBoosTOS.
#
# Safe to re-run. The panel itself is self-contained WPF (no project, no deps)
# and closes automatically after ~5 s, on Esc, or on click.
# =============================================================================

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Paths (LexBoosT OS layout)
# ------------------------------------------------------------------
$welcomeDir   = 'C:\ProgramData\LexBoosTOS\Welcome'
$logsDir      = 'C:\ProgramData\LexBoosTOS\Logs'
$logFile      = Join-Path $logsDir 'CONFIGURE-BOOT-WELCOME.log'
$panelSource  = Join-Path $PSScriptRoot 'SHOW-WELCOME-PANEL.PS1'
$panelDest    = Join-Path $welcomeDir 'SHOW-WELCOME-PANEL.PS1'
$launcherDest = Join-Path $welcomeDir 'LAUNCH-WELCOME-PANEL.VBS'

New-Item -Path $welcomeDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $logsDir    -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

function Write-Log {
    param([string]$Status, [string]$Message)
    $line = "[$Status] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# Admin guard
# ------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log '-' 'Administrator privileges are required.'
    exit 1
}

# ------------------------------------------------------------------
# PART 1 — Native VerboseStatus loading text (secure Welcome screen)
# ------------------------------------------------------------------
Write-Log '+' 'Enabling native status text for the secure Welcome/loading screen...'
$systemPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-Item -Path $systemPolicy -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $systemPolicy -Name 'VerboseStatus'           -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $systemPolicy -Name 'DisableStatusMessages'   -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $systemPolicy -Name 'EnableFirstLogonAnimation' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# ------------------------------------------------------------------
# PART 2 — Deploy the panel + hidden launcher
# ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $panelSource -PathType Leaf)) {
    Write-Log '-' ('Welcome panel source was not found: ' + $panelSource)
    exit 2
}
Copy-Item -LiteralPath $panelSource -Destination $panelDest -Force -ErrorAction Stop

# WScript runs PowerShell with window style 0, so after boot the panel is the
# only visible window; the script-host processes stay observable in Task Manager.
$escapedPanelPath = $panelDest.Replace('"', '""')
$launcher = @"
Option Explicit
Dim shell, command
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File ""$escapedPanelPath"""
shell.Run command, 0, False
"@
Set-Content -LiteralPath $launcherDest -Value $launcher -Encoding Unicode -Force
Write-Log '+' ('Deployed welcome panel to ' + $panelDest)

# ------------------------------------------------------------------
# PART 3 — Clear any legacy Run/Startup entries (task is the source of truth)
# ------------------------------------------------------------------
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$approvalKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
)
$legacyValueNames = @('LexBoosTWelcomePanel', 'LexBoosT OS - Welcome')
New-Item -Path $runKey -Force -ErrorAction SilentlyContinue | Out-Null
foreach ($valueName in $legacyValueNames) {
    Remove-ItemProperty -Path $runKey -Name $valueName -Force -ErrorAction SilentlyContinue
    foreach ($approvalKey in $approvalKeys) {
        Remove-ItemProperty -Path $approvalKey -Name $valueName -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# PART 4 — Register the interactive LOGON scheduled task
# ------------------------------------------------------------------
# Resolve the interactive user's SID (local / domain / Entra identities).
$accounts = @()
$computerUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if ($computerUser) { $accounts += $computerUser }
Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($owner.User) {
            if ($owner.Domain) { $accounts += ($owner.Domain + '\' + $owner.User) }
            else { $accounts += $owner.User }
        }
    } catch { }
}
$interactiveSid = $null
foreach ($account in ($accounts | Where-Object { $_ } | Select-Object -Unique)) {
    try {
        $sid = ([Security.Principal.NTAccount]$account).Translate([Security.Principal.SecurityIdentifier]).Value
        if ($sid -match '^S-1-(?:5-21|12-1)-') { $interactiveSid = $sid; break }
    } catch { }
}
if (-not $interactiveSid) {
    Write-Log '-' 'No interactive user SID was found for the Welcome task.'
    exit 5
}

$taskName = 'LexBoosT OS - Welcome'
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$xmlWscript  = [Security.SecurityElement]::Escape($wscriptPath)
$xmlLauncher = [Security.SecurityElement]::Escape($launcherDest)
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>LexBoosT OS post-sign-in Welcome panel</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>$interactiveSid</UserId><Delay>PT2S</Delay></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$interactiveSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>$xmlWscript</Command><Arguments>&quot;$xmlLauncher&quot;</Arguments></Exec></Actions>
</Task>
"@
try {
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Log '-' ('Could not register interactive Welcome task: ' + $_.Exception.Message)
    exit 6
}
Write-Log '+' ('Scheduled interactive Welcome panel: ' + $taskName + ' for ' + $interactiveSid)

# ------------------------------------------------------------------
# PART 5 — Idempotency markers
# ------------------------------------------------------------------
$marker = 'HKLM:\SOFTWARE\LexBoosTOS'
New-Item -Path $marker -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $marker -Name 'VerboseBootStatus'        -Value 1 -PropertyType DWord  -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $marker -Name 'PostBootWelcomePanel'     -Value 1 -PropertyType DWord  -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $marker -Name 'WelcomeTaskName'          -Value $taskName -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $marker -Name 'WelcomeTaskUserSid'       -Value $interactiveSid -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $marker -Name 'BootWelcomeInstalledDate' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

Write-Log '+' 'Boot welcome configuration complete.'
