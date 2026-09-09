#Requires -RunAsAdministrator
#Requires -Version 5.1

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Test-IsLaptop {
    $mobileChassisTypes = @(8, 9, 10, 11, 12, 13, 14, 18, 21, 30, 31, 32)
    try {
        $chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop
        if ($chassis.ChassisTypes | Where-Object { $_ -in $mobileChassisTypes }) { return $true }
    } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PCSystemType -eq 2 -or $cs.PCSystemTypeEx -in @(2, 8)) { return $true }
    } catch {}
    try {
        if (Get-CimInstance Win32_Battery -ErrorAction Stop) { return $true }
    } catch {}
    return $false
}

$isLaptop = Test-IsLaptop

# -----------------------------------------------------------------------------
# 1. Hibernation: respect DEVICES.PS1 decision (kept enabled on desktop for
#    CUDA/TensorRT memory reservations). Only disable if not explicitly kept.
# -----------------------------------------------------------------------------
$hibernateKept = $false
try {
    $hibernateEnabled = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction SilentlyContinue
    if ($hibernateEnabled -eq 1) { $hibernateKept = $true }
} catch { }

if (-not $isLaptop -and -not $hibernateKept) {
    Write-Log '+' 'Desktop detected: disabling hibernation...'
    try {
        powercfg /hibernate off | Out-Null
        Write-Log '+' 'Hibernation disabled'
    } catch {
        Write-Log '-' "Could not disable hibernation: $_"
    }
} else {
    Write-Log '+' 'Hibernation kept enabled (required by DEVICES.PS1 for CUDA/TensorRT memory reservations)'
}

# -----------------------------------------------------------------------------
# 2. Disable hybrid sleep and set AC timers to never
# -----------------------------------------------------------------------------
Write-Log '+' 'Configuring AC power timers...'
try {
    $activeLine = (powercfg /getactivescheme)
    $active = [regex]::Match($activeLine, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    if ($active) {
        powercfg /setacvalueindex $active SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
        powercfg /setacvalueindex $active SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
        powercfg /setacvalueindex $active SUB_SLEEP STANDBYIDLE 0 | Out-Null
        powercfg /setdcvalueindex $active SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
        powercfg /setacvalueindex $active SUB_DISK DISKIDLE 0 | Out-Null
        powercfg /setactive $active | Out-Null
        Write-Log '+' 'AC timers configured'
    } else {
        Write-Log '-' 'Could not determine active power scheme'
    }
} catch {
    Write-Log '-' "Could not configure power timers: $_"
}

# -----------------------------------------------------------------------------
# 3. Lid-close action (laptops): force Sleep when the lid is closed
# -----------------------------------------------------------------------------
# DEVICES.PS1 activates a power plan but never sets the lid-close action, so it
# stays at the stock default (Do Nothing on minimal installs) and closing the
# lid does nothing. LIDACTION = 5ca83367-6e45-459f-a27b-476b1d01c936 (0=Do
# Nothing, 1=Sleep, 2=Hibernate, 3=Shut Down). Applied to every scheme (AC + DC)
# so the lid keeps working even if the user later switches plans. Desktops have
# no lid, so this is a harmless no-op there.
if ($isLaptop) {
    Write-Log '+' 'Laptop detected: setting lid-close action to Sleep on all schemes...'
    try {
        $lidAction = 1 # Sleep
        $lidSetting = '5ca83367-6e45-459f-a27b-476b1d01c936'
        $schemeList = (powercfg /list 2>$null) -join "`n"
        foreach ($m in [regex]::Matches($schemeList, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')) {
            $g = $m.Value
            powercfg /setacvalueindex $g SUB_BUTTONS $lidSetting $lidAction | Out-Null
            powercfg /setdcvalueindex $g SUB_BUTTONS $lidSetting $lidAction | Out-Null
        }
        Write-Log '+' 'Lid-close action set to Sleep (AC + DC) on all schemes.'
    } catch {
        Write-Log '-' "Could not set lid-close action: $_"
    }
}
Write-Log '+' 'Power extras applied.'
exit 0
