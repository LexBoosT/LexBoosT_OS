#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

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
Write-Host '       SOFTWARE-ASSOCIATIONS Registry Tweaks'
Write-Host '============================================'

$regValues = @(
    # === 7-Zip: FM Columns (file manager column layout) ===
    @{ Path = 'Registry::HKCU\Software\7-Zip\FM\Columns'; Name = 'RootFolder'; Value = '0100000000000000010000000400000001000000a0000000'; Type = 'REG_BINARY' },
    @{ Path = 'Registry::HKCU\Software\7-Zip\Options'; Name = 'ContextMenu'; Value = '4903'; Type = 'REG_DWORD' },
    @{ Path = 'Registry::HKCU\Software\7-Zip\Options'; Name = 'ElimDupExtract'; Value = '0'; Type = 'REG_DWORD' },

    # === 7-Zip: file associations (.7z, .zip, .rar, etc.) — minimal key set ===
    @{ Path = 'Registry::HKCU\Software\Classes\.7z'; Name = ''; Value = '7-Zip.7z'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.zip'; Name = ''; Value = '7-Zip.zip'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.rar'; Name = ''; Value = '7-Zip.rar'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.001'; Name = ''; Value = '7-Zip.001'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.cab'; Name = ''; Value = '7-Zip.cab'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.iso'; Name = ''; Value = '7-Zip.iso'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.xz'; Name = ''; Value = '7-Zip.xz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.txz'; Name = ''; Value = '7-Zip.txz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.lzma'; Name = ''; Value = '7-Zip.lzma'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.tar'; Name = ''; Value = '7-Zip.tar'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.cpio'; Name = ''; Value = '7-Zip.cpio'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.bz2'; Name = ''; Value = '7-Zip.bz2'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.bzip2'; Name = ''; Value = '7-Zip.bzip2'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.tbz2'; Name = ''; Value = '7-Zip.tbz2'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.tbz'; Name = ''; Value = '7-Zip.tbz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.gz'; Name = ''; Value = '7-Zip.gz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.gzip'; Name = ''; Value = '7-Zip.gzip'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.tgz'; Name = ''; Value = '7-Zip.tgz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.tpz'; Name = ''; Value = '7-Zip.tpz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.z'; Name = ''; Value = '7-Zip.z'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.taz'; Name = ''; Value = '7-Zip.taz'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.lzh'; Name = ''; Value = '7-Zip.lzh'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.lha'; Name = ''; Value = '7-Zip.lha'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.rpm'; Name = ''; Value = '7-Zip.rpm'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.deb'; Name = ''; Value = '7-Zip.deb'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.arj'; Name = ''; Value = '7-Zip.arj'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.vhd'; Name = ''; Value = '7-Zip.vhd'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.wim'; Name = ''; Value = '7-Zip.wim'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.swm'; Name = ''; Value = '7-Zip.swm'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.fat'; Name = ''; Value = '7-Zip.fat'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.ntfs'; Name = ''; Value = '7-Zip.ntfs'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.dmg'; Name = ''; Value = '7-Zip.dmg'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.hfs'; Name = ''; Value = '7-Zip.hfs'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.xar'; Name = ''; Value = '7-Zip.xar'; Type = 'REG_SZ' },
    @{ Path = 'Registry::HKCU\Software\Classes\.squashfs'; Name = ''; Value = '7-Zip.squashfs'; Type = 'REG_SZ' },

    # === Notepad settings ===
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Notepad'; Name = 'ShowStoreBanner'; Value = '0'; Type = 'REG_DWORD' },
    @{ Path = 'Registry::HKCU\SOFTWARE\Microsoft\Notepad'; Name = 'fWrapAround'; Value = '1'; Type = 'REG_DWORD' }
)

$set = 0
foreach ($entry in $regValues) {
    try {
        if (-not (Test-Path $entry.Path)) {
            New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null
        }
        $propType = switch ($entry.Type) {
            'REG_SZ'        { 'String' }
            'REG_EXPAND_SZ' { 'ExpandString' }
            'REG_DWORD'     { 'DWord' }
            'REG_BINARY'    { 'Binary' }
            'REG_NONE'      { 'None' }
            default         { 'String' }
        }
        if ($entry.Name -eq '') {
            Set-ItemProperty -Path $entry.Path -Name '(default)' -Value $entry.Value -Force -ErrorAction Stop
        } elseif ($entry.Type -eq 'REG_BINARY') {
            [byte[]]$bytes = for ($i = 0; $i -lt $entry.Value.Length; $i += 2) { [Convert]::ToByte($entry.Value.Substring($i, 2), 16) }
            Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $bytes -Type Binary -Force -ErrorAction Stop
        } else {
            New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $propType -Force -ErrorAction Stop | Out-Null
        }
        $set++
    } catch {
        Write-Log '-' "Failed to set $($entry.Path)\$($entry.Name): $_"
    }
}

Write-Log '+' "$set registry values set"
Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
