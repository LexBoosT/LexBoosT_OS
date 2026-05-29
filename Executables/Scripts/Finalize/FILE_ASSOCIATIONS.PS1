#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       File Associations & ShellNew'
Write-Host '============================================'

$regValues = @(
    # .bat
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat\ShellNew';               Name = 'ItemName'; Value = '%windir%\System32\acppage.dll,-6002'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.bat\ShellNew';               Name = 'NullFile'; Value = '';                                    Type = 'String'       },
    # .cmd
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd\ShellNew';               Name = 'ItemName'; Value = '%windir%\System32\acppage.dll,-6002'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.cmd\ShellNew';               Name = 'NullFile'; Value = '';                                    Type = 'String'       },
    # .ps1
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1';                        Name = '(default)';         Value = 'Microsoft.PowerShellScript.1'; Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.ps1\ShellNew';               Name = 'NullFile';          Value = '';                            Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1'; Name = '(default)';         Value = 'Windows PowerShell Script';     Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1'; Name = 'FriendlyTypeName'; Value = 'Windows PowerShell Script';     Type = 'String' },
    # .reg
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg\ShellNew';               Name = 'NullFile'; Value = '';                         Type = 'String'       },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.reg\ShellNew';               Name = 'ItemName'; Value = '%windir%\regedit.exe,-309'; Type = 'ExpandString' },
    # .vbs
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs';                        Name = '(default)';         Value = 'VBSFile';                     Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs\ShellNew';               Name = 'NullFile';          Value = '';                           Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\.vbs\ShellNew';               Name = 'ItemName';          Value = '%windir%\System32\wscript.exe,-4804'; Type = 'ExpandString' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile';                     Name = '(default)';         Value = 'VBScript File';               Type = 'String' },
    @{ Path = 'Registry::HKEY_CLASSES_ROOT\VBSFile';                     Name = 'FriendlyTypeName';  Value = 'Fichier VBScript';             Type = 'String' }
)

foreach ($entry in $regValues) {
    New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction SilentlyContinue | Out-Null
}

Write-Log '+' "$($regValues.Count) registry values set"

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
