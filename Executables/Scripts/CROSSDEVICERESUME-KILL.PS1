#Requires -Version 5.1

$taskName       = 'LexBoosT_CDR_Kill'
$deployedScript = 'C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.PS1'
$deployedExe    = 'C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.exe'
$sourceExe      = Join-Path $PSScriptRoot 'CROSSDEVICERESUME-KILL.exe'

# ------------------------------------------------------------------
# PART 1 — Kill CrossDeviceResume now (via the GUI exe: no console)
# ------------------------------------------------------------------
# Run the exe (it has its own 15x2 s retry loop) and wait for it to finish.
# It is a GUI exe so launching it from here opens no visible window either.
if (Test-Path -LiteralPath $sourceExe) {
    $proc = Start-Process -FilePath $sourceExe -PassThru
    try { $proc | Wait-Process -Timeout 45 -ErrorAction Stop | Out-Null } catch {}
    # The exe writes a log line; surface it for install-time diagnostics.
    $log = 'C:\ProgramData\LexBoosTOS\Logs\CROSSDEVICERESUME-KILL.log'
    if (Test-Path -LiteralPath $log) {
        Write-Host ((Get-Content -LiteralPath $log | Select-Object -Last 1))
    }
} else {
    # Fallback if the exe is somehow missing (shouldn't happen): plain kill.
    Write-Warning "CROSSDEVICERESUME-KILL.exe not found - falling back to direct taskkill."
    for ($round = 0; $round -lt 10; $round++) {
        $p = Get-Process -Name 'CrossDeviceResume' -ErrorAction SilentlyContinue
        if (-not $p) { break }
        foreach ($x in $p) { try { $x | Stop-Process -Force -ErrorAction Stop } catch {} }
        Start-Sleep -Seconds 3
    }
}

# ------------------------------------------------------------------
# PART 2 — Deploy the exe to the persistent location
# ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Split-Path -Parent $deployedExe))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $deployedExe) -Force | Out-Null
}
if (Test-Path -LiteralPath $sourceExe) {
    Copy-Item -LiteralPath $sourceExe -Destination $deployedExe -Force -ErrorAction SilentlyContinue
}
# Also deploy the PS1 itself (idempotent re-registration entry point).
if (Test-Path -LiteralPath $PSCommandPath) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $deployedScript -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# PART 3 — (Re-)register the persistent per-user LOGON task via XML
# ------------------------------------------------------------------
# Canonical target: the persistent exe (survives Harness cleanup).
$taskTarget = if (Test-Path -LiteralPath $deployedExe) { $deployedExe } else { $sourceExe }

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Build the task XML. The action runs the GUI exe directly (no console).
$taskXml = @"
<?xml version='1.0' encoding='UTF-16'?>
<Task version='1.3' xmlns='http://schemas.microsoft.com/windows/2004/02/mit/task'>
  <RegistrationInfo><URI>\$taskName</URI></RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$currentUser</UserId>
      <Delay>PT30S</Delay>
    </LogonTrigger>
  </Triggers>
  <Actions>
    <Exec>
      <Command>$taskTarget</Command>
    </Exec>
  </Actions>
  <Principals>
    <Principal id="Author">
      <UserId>$currentUser</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <Hidden>true</Hidden>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
</Task>
"@

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
} catch {}

try {
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -ErrorAction Stop | Out-Null
    Write-Host "Logon task '$taskName' registered (action: $taskTarget) - no console (GUI exe)."
} catch {
    Write-Host "Logon task registration FAILED: $_"
}
