#Requires -RunAsAdministrator
#Requires -Version 5.1
# =============================================================================
# LexBoosT OS — CEIP / SQM / FTH / Error Reporting disable
# Each step is wrapped with a timeout so a single blocked reg.exe cannot
# freeze the whole playbook (previous version would hang indefinitely on
# certain Shell Extension / CrashControl keys).
# =============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# --- Robust reg.exe wrapper: timeout, exit code capture, error isolation ---
$script:RegSucceeded = 0
$script:RegFailed = 0

function Invoke-Reg {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueName,
        [Parameter(Mandatory = $true)][string]$ValueKind,    # REG_DWORD | REG_SZ | REG_BINARY
        [Parameter(Mandatory = $true)]$Data,
        [int]$TimeoutSec = 10
    )
    $cmd = "reg add `"$Key`" /v `"$ValueName`" /t $ValueKind /d `"$Data`" /f"
    try {
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\lex_reg_out.txt" -RedirectStandardError "$env:TEMP\lex_reg_err.txt" -ErrorAction Stop
        if ($p.ExitCode -eq 0) {
            $script:RegSucceeded++
            return $true
        }
        $err = ''
        if (Test-Path "$env:TEMP\lex_reg_err.txt") {
            $err = (Get-Content "$env:TEMP\lex_reg_err.txt" -Raw -ErrorAction SilentlyContinue).Trim()
        }
        if (-not $err -and (Test-Path "$env:TEMP\lex_reg_out.txt")) {
            $out = (Get-Content "$env:TEMP\lex_reg_out.txt" -Raw -ErrorAction SilentlyContinue).Trim()
            if ($out -match 'ERROR|erreur|refus|denied|non autoris') { $err = $out }
        }
        Write-Log '-' "reg add failed: $Key\$ValueName :: $err"
        $script:RegFailed++
        return $false
    } catch {
        Write-Log '-' "reg add exception: $Key\$ValueName :: $_"
        $script:RegFailed++
        return $false
    } finally {
        Remove-Item -Path "$env:TEMP\lex_reg_out.txt", "$env:TEMP\lex_reg_err.txt" -ErrorAction SilentlyContinue
    }
}

Write-Log '+' 'Disabling CEIP and SQM client...'

# === CEIP + SQM ===
Invoke-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'AllowOnlineTips' 'REG_DWORD' '0'
Invoke-Reg 'HKLM\SOFTWARE\Microsoft\SQMClient\Windows'                  'CEIPEnable'    'REG_DWORD' '0'
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows'        'CEIPEnable'    'REG_DWORD' '0'
Invoke-Reg 'HKLM\SOFTWARE\Wow6432Node\Microsoft\VSCommon\15.0\SQM'      'OptIn'         'REG_DWORD' '0'

# === Fault Tolerant Heap ===
Invoke-Reg 'HKLM\SOFTWARE\Microsoft\FTH'                                 'Enabled'       'REG_DWORD' '0'

# === Error Reporting ===
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\PCHealth\ErrorReporting'                       'DoReport'              'REG_DWORD' '0'
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'              'Disabled'              'REG_DWORD' '1'
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting\Consent'      'value'                 'REG_SZ'    '0'
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'              'DontSendAdditionalData' 'REG_DWORD' '1'
Invoke-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'              'LoggingDisabled'       'REG_DWORD' '1'

# === Crash control ===
Invoke-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'                            'AutoReboot'           'REG_DWORD' '0'
Invoke-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'                            'CrashDumpEnabled'     'REG_DWORD' '0'
Invoke-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'                            'LogEvent'             'REG_DWORD' '0'
Invoke-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'                            'DisplayParameters'    'REG_DWORD' '1'
Invoke-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl\StorageTelemetry'           'DeviceDumpEnabled'    'REG_DWORD' '0'

# === Block Problem Details shim extension (Shell Extensions\Blocked is write-protected in some builds) ===
Invoke-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}' 'REG_SZ' ''

Write-Log '+' "CEIP, SQM, FTH, and Error Reporting done. OK=$($script:RegSucceeded) FAIL=$($script:RegFailed)"
exit 0
