#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# Auto-elevate to admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Restarting as Administrator...'
    Start-Process -FilePath PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       File Associations & ShellNew'
Write-Host '============================================'

$regKeys = @(
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat\ShellNew' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd\ShellNew' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1\ShellNew' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg\ShellNew' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs\ShellNew' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\shell' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\shell\open' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\shell\open\command' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\DefaultIcon' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\ScriptEngine' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\ScriptHostEncode' }
)

$regValues = @(
    # .bat
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat';                        Name = '';         Value = 'batfile';                        Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat\ShellNew';               Name = 'ItemName'; Value = '%windir%\System32\acppage.dll,-6002'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat\ShellNew';               Name = 'NullFile'; Value = '';                                    Type = 'String'       },
    # .cmd
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd';                        Name = '';         Value = 'cmdfile';                        Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd\ShellNew';               Name = 'ItemName'; Value = '%windir%\System32\acppage.dll,-6002'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd\ShellNew';               Name = 'NullFile'; Value = '';                                    Type = 'String'       },
    # .ps1
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1';                        Name = '';                  Value = 'Microsoft.PowerShellScript.1'; Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1\ShellNew';               Name = 'NullFile';          Value = '';                            Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1'; Name = '';                  Value = 'Windows PowerShell Script';     Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1'; Name = 'FriendlyTypeName'; Value = 'Windows PowerShell Script';     Type = 'String' },
    # .reg
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg';                        Name = '';         Value = 'regfile';                        Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg\ShellNew';               Name = 'NullFile'; Value = '';                         Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg\ShellNew';               Name = 'ItemName'; Value = '%windir%\regedit.exe,-309'; Type = 'ExpandString' },
    # .vbs
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs';                        Name = '';                  Value = 'VBSFile';                     Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs\ShellNew';               Name = 'NullFile';          Value = '';                           Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs\ShellNew';               Name = 'ItemName';          Value = '%windir%\System32\wscript.exe,-4804'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile';                     Name = '';                  Value = 'VBScript File';               Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\shell\open\command';  Name = '';                  Value = '%SystemRoot%\System32\WScript.exe "%1" %*'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile';                     Name = 'FriendlyTypeName';  Value = 'VBScript File';               Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\DefaultIcon';         Name = '';                  Value = '%SystemRoot%\System32\WScript.exe,2'; Type = 'ExpandString' },
    # ScriptEngine: WSH reads THIS key to resolve the engine for .vbs (missing = "no script engine" error)
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\ScriptEngine';        Name = '';                  Value = 'VBScript';                        Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile\ScriptHostEncode';    Name = '';                  Value = '{85131630-480C-11D2-B1F9-00C04F86C324}'; Type = 'String' }
)

foreach ($key in $regKeys) {
    New-Item -Path $key.Path -Force -ErrorAction SilentlyContinue | Out-Null
}

$extensions = @('.bat', '.cmd', '.ps1', '.reg', '.vbs')
foreach ($ext in $extensions) {
    $path = "Registry::HKEY_CLASSES_ROOT\$ext"
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name 'PerceivedType' -Force -ErrorAction SilentlyContinue
    }
}

foreach ($entry in $regValues) {
    if ($entry.Name -eq '') {
        Set-ItemProperty -Path $entry.Path -Name '(default)' -Value $entry.Value -Force -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Log '+' "$($regKeys.Count) registry keys ensured"
Write-Log '+' "$($regValues.Count) registry values set"

# --- VBScript COM engine registration ---
# WScript.exe needs the VBScript engine CLSID in HKCR to run .vbs files.
# Debloat/strip steps may remove it. regsvr32 re-registers vbscript.dll.
$vbsEngineClsid = '{31E6BBDE-96B8-11D0-842E-00A0C90DC849}'
$vbsEngineKey = "Registry::HKEY_CLASSES_ROOT\CLSID\$vbsEngineClsid"
$vbsDll = "$env:SystemRoot\System32\vbscript.dll"

if (-not (Test-Path $vbsEngineKey)) {
    Write-Log 'i' 'VBScript engine CLSID missing, re-registering vbscript.dll ...'
    & regsvr32 /s $vbsDll
    if (Test-Path $vbsEngineKey) {
        Write-Log '+' 'VBScript engine CLSID registered'
    } else {
        Write-Log '-' 'regsvr32 done, CLSID still missing (non-fatal)'
    }
} else {
    Write-Log '+' 'VBScript engine CLSID already present'
}

# Functional test
$testVbs = Join-Path $env:TEMP 'lexboost-vbs-test.vbs'
Set-Content -Path $testVbs -Value 'WScript.Echo "OK"' -Encoding ASCII
$cscriptOut = & "$env:SystemRoot\System32\cscript.exe" //nologo $testVbs 2>&1
Remove-Item $testVbs -Force -ErrorAction SilentlyContinue
if ("$cscriptOut" -match 'OK') {
    Write-Log '+' 'VBScript engine functional test passed'
} else {
    Write-Log '-' "VBScript engine test: $cscriptOut"
}

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
