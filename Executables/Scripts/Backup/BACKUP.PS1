param (
    [string]$BackupDir = "$env:ProgramData\LexBoosTOS\Backup"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -BackupDir `"$BackupDir`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BackupDir = Join-Path $BackupDir $timestamp

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

Write-Host "=== LexBoosT OS Backup ==="
Write-Host "Backup directory: $BackupDir"
Write-Host ""

if (-not ('Priv' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Priv {
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr h, uint a, out IntPtr t);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string s, string n, out long l);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr t, bool d, ref TOKEN_PRIVILEGES p, uint b, IntPtr prev, IntPtr rl);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [StructLayout(LayoutKind.Sequential)]
    private struct LUID_AND_ATTRIBUTES { public long Luid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }
    private const uint TOKEN_QUERY = 0x0008;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint SE_PRIVILEGE_ENABLED = 0x0002;

    public static bool Enable(string name) {
        IntPtr tokenHandle;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES, out tokenHandle))
            return false;
        try {
            long luid;
            if (!LookupPrivilegeValue(null, name, out luid))
                return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Privileges.Luid = luid;
            tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;
            return AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        } finally { }
    }
}
"@
}

try {
    # 1. System Restore Point
    Write-Log '+' "[1/7] Creating system restore point..."
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "LexBoosT OS Pre-Installation Backup - $timestamp" -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue
        Write-Log '+' "System restore point created."
    }
    catch {
        Write-Log '-' "Failed to create restore point: $_"
    }

    # 2. Export targeted registry keys (from YAML config)
    Write-Log '+' "[2/7] Exporting registry keys targeted by the playbook..."
    $regBackupDir = Join-Path $BackupDir "Registry"
    New-Item -ItemType Directory -Path $regBackupDir -Force | Out-Null
    Write-Log '+' "Enabling SeBackupPrivilege..."
    [Priv]::Enable("SeBackupPrivilege") | Out-Null

    $regLogFile = Join-Path $BackupDir "backup-registry.log"
    $logHeader = @"
============================================================
LexBoosT OS - Registry Backup Log
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================================

"@
    $logHeader | Out-File -FilePath $regLogFile -Encoding UTF8

    # Parse YAML configs to find all registry paths that will be modified
    $configFolder = Join-Path $PSScriptRoot "..\..\..\Configuration\Tasks"
    if (-not (Test-Path $configFolder)) {
        $configFolder = "$env:ProgramData\LexBoosTOS\Config\Tasks"
    }
    Write-Log '+' "Scanning YAML configs in: $configFolder"

    $yamlFiles = Get-ChildItem -Path $configFolder -Filter *.yml -Recurse -ErrorAction SilentlyContinue
    $regPaths = [System.Collections.Generic.HashSet[string]]::new()
    $regTargetValues = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new()

    foreach ($yamlFile in $yamlFiles) {
        $content = Get-Content $yamlFile.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        $blocks = [regex]::Matches($content, '- !registryValue:.*?(?=\r?\n\r?\n|\r?\n  - |\Z)', 'Singleline')
        foreach ($block in $blocks) {
            $b = $block.Value
            if ($b -match "path:\s*'([^']+)'") {
                $p = $matches[1]
                if ($p -match '^HK(LM|CU|CR|U|CC)\\') {
                    [void]$regPaths.Add($p)
                    if ($b -match "value:\s*['`"]([^'`"]+)['`"]") {
                        $v = $matches[1]
                        if (-not $regTargetValues.ContainsKey($p)) {
                            $regTargetValues[$p] = [System.Collections.Generic.HashSet[string]]::new()
                        }
                        [void]$regTargetValues[$p].Add($v)
                    }
                }
            }
        }
    }

    Write-Log '+' "Found $($regPaths.Count) unique registry key paths in YAML."

    # Export each key individually via PowerShell (handles REG_BINARY/REG_NONE correctly)
    $exportedCount = 0
    $skippedCount = 0
    $createdPaths = @()
    $combinedReg = Join-Path $regBackupDir "registry-backup.reg"
    $combinedRegWriter = [System.IO.StreamWriter]::new($combinedReg, $false, [System.Text.Encoding]::Unicode)
    $combinedRegWriter.WriteLine("Windows Registry Editor Version 5.00")
    $combinedRegWriter.WriteLine("")

    function Export-RegistryKey {
        param([string]$RegPath, [System.IO.StreamWriter]$Writer, [System.Collections.Generic.HashSet[string]]$ValueNames)
        $psPath = $RegPath -replace '^(HKLM|HKCU|HKCR|HKU|HKCC)\\(.+)', '$1:\$2'
        if (-not (Test-Path $psPath)) { return }
        $key = Get-Item -Path $psPath -ErrorAction Stop
        $Writer.WriteLine("[$RegPath]")
        $filterNames = ($ValueNames -and $ValueNames.Count -gt 0)
        foreach ($valName in $key.GetValueNames()) {
            if ($filterNames -and -not $ValueNames.Contains($valName)) { continue }
            $val = $key.GetValue($valName)
            $kind = $key.GetValueKind($valName)
            $displayName = if ($valName -eq '') { '@' } else { "`"$valName`"" }
            switch ($kind) {
                'DWord' {
                    $Writer.WriteLine("$displayName=dword:$('{0:x8}' -f $val)")
                }
                'QWord' {
                    $bytes = [BitConverter]::GetBytes([int64]$val)
                    $hexStr = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                    $Writer.WriteLine("$displayName=hex(b):$hexStr")
                }
                'Binary' {
                    $hexStr = ([byte[]]$val | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                    $Writer.WriteLine("$displayName=hex:$hexStr")
                }
                'MultiString' {
                    $strData = ($val -join "`0") + "`0`0"
                    $bytes = [System.Text.Encoding]::Unicode.GetBytes($strData)
                    $hexStr = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                    $Writer.WriteLine("$displayName=hex(7):$hexStr")
                }
                'ExpandString' {
                    $bytes = [System.Text.Encoding]::Unicode.GetBytes($val + "`0")
                    $hexStr = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                    $Writer.WriteLine("$displayName=hex(2):$hexStr")
                }
                'String' {
                    if ($val -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
                        $bytes = [System.Text.Encoding]::Unicode.GetBytes($val)
                        $hexStr = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                        $Writer.WriteLine("$displayName=hex(1):$hexStr")
                    } else {
                        $escaped = $val -replace '\\', '\\' -replace '"', '\"'
                        $Writer.WriteLine("$displayName=`"$escaped`"")
                    }
                }
                'None' {
                    if ($val -is [byte[]] -and $val.Length -gt 0) {
                        $hexStr = ($val | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                        $Writer.WriteLine("$displayName=hex(0):$hexStr")
                    } else {
                        $Writer.WriteLine("$displayName=hex(0):")
                    }
                }
                default {
                    if ($val -is [byte[]]) {
                        $hexStr = ($val | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                        $Writer.WriteLine("$displayName=hex:$hexStr")
                    } elseif ("$val" -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
                        $bytes = [System.Text.Encoding]::Unicode.GetBytes("$val")
                        $hexStr = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','
                        $Writer.WriteLine("$displayName=hex(1):$hexStr")
                    } else {
                        $escaped = "$val" -replace '\\', '\\' -replace '"', '\"'
                        $Writer.WriteLine("$displayName=`"$escaped`"")
                    }
                }
            }
        }
    }

    foreach ($path in $regPaths) {
        $psPath = $path -replace '^(HKLM|HKCU|HKCR|HKU|HKCC)\\(.+)', '$1:\$2'
        $keyExists = Test-Path $psPath -ErrorAction SilentlyContinue
        if (-not $keyExists) {
            $createdPaths += $path
            $skippedCount++
            Write-Log '+' "$path (will be created by playbook)"
            continue
        }

        try {
            $targetVals = if ($regTargetValues.ContainsKey($path)) { $regTargetValues[$path] } else { $null }
            Export-RegistryKey -RegPath $path -Writer $combinedRegWriter -ValueNames $targetVals
            $exportedCount++
            Write-Log '+' "$path"
        }
        catch {
            $skippedCount++
            Write-Log '-' "$path - $_"
            "  [SKIPPED] $path - $_" | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
        }
    }
    $combinedRegWriter.Close()

    # Save list of paths that will be newly created (rollback must delete them)
    $createdPaths | ConvertTo-Json | Out-File -FilePath (Join-Path $regBackupDir "registry-created.json") -Encoding UTF8

    $backupSize = if (Test-Path $combinedReg) { '{0:N0}' -f (Get-Item $combinedReg).Length } else { "0" }

    $logSummary = @"

Exported : $exportedCount keys
Skipped  : $skippedCount keys (will be created by playbook)
Total    : $($regPaths.Count) paths found
Backup   : registry-backup.reg ($backupSize bytes)
Created  : registry-created.json

============================================================
Backup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================================
"@
    $logSummary | Out-File -FilePath $regLogFile -Encoding UTF8 -Append

    Write-Log '+' "$exportedCount keys exported to registry-backup.reg ($backupSize bytes)"
    Write-Log '+' "$skippedCount paths marked as new (will be cleaned up on rollback)"

    # 3. Save service state
    Write-Log '+' "[3/7] Saving service state..."
    try {
        $servicesFile = Join-Path $BackupDir "services.xml"
        Get-Service | Select-Object Name, DisplayName, Status, StartType | Export-CliXml -Path $servicesFile -Force
        Write-Log '+' "Service state saved."
    }
    catch {
        Write-Log '-' "Failed to save service state: $_"
    }

    # 4. Snapshot AppX packages
    Write-Log '+' "[4/7] Snapshotting AppX packages..."
    try {
        $appxFile = Join-Path $BackupDir "appx-packages.txt"
        Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, Status, InstallLocation |
            Sort-Object Name | Out-File -FilePath $appxFile -Encoding UTF8
        Write-Log '+' "AppX package list saved ($('{0:N0}' -f (Get-Item $appxFile).Length) bytes)"

        $appxProvisionedFile = Join-Path $BackupDir "appx-provisioned.txt"
        Get-AppxProvisionedPackage -Online |
            Select-Object DisplayName, PackageName | Sort-Object DisplayName |
            Out-File -FilePath $appxProvisionedFile -Encoding UTF8
        Write-Log '+' "Provisioned AppX list saved."
    }
    catch {
        Write-Log '-' "Failed to snapshot AppX packages: $_"
    }

    # 5. Export BCD configuration
    Write-Log '+' "[5/7] Exporting BCD configuration..."
    try {
        $bcdFile = Join-Path $BackupDir "bcd-backup"
        bcdedit /export $bcdFile 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log '+' "BCD exported."
        }
        else {
            Write-Log '-' "Failed to export BCD."
        }
    }
    catch {
        Write-Log '-' "Failed to export BCD: $_"
    }

    # 6. Save installed programs list
    Write-Log '+' "[6/7] Saving installed programs list..."
    try {
        $programsFile = Join-Path $BackupDir "installed-programs.txt"
        $uninstallPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($path in $uninstallPaths) {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher |
                Sort-Object DisplayName |
                Out-File -FilePath $programsFile -Encoding UTF8 -Append
        }
        Write-Log '+' "Installed programs list saved."
    }
    catch {
        Write-Log '-' "Failed to save programs list: $_"
    }

    # 7. Backup confirmation
    Write-Log '+' "[7/7] Writing backup manifest..."
    $manifest = @"
LexBoosT OS Backup Manifest
===========================
Timestamp: $timestamp
Backup Directory: $BackupDir

Contents:
  Registry\registry-backup.reg  - Original values of all keys targeted by playbook
  Registry\registry-created.json - Paths that will be created (deleted on rollback)
  services.xml                  - Service state (Import-CliXml)
  appx-packages.txt           - AppX package snapshot
  appx-provisioned.txt        - Provisioned AppX snapshot
  bcd-backup                  - BCD configuration (bcdedit /import)
  installed-programs.txt      - Installed programs list

To rollback: Run ROLLBACK.ps1 -BackupDir "$BackupDir"
"@
    $manifest | Out-File -FilePath (Join-Path $BackupDir "backup-manifest.txt") -Encoding UTF8

    Write-Host ""
    Write-Host "=== Backup Complete ==="
    Write-Log '+' "Backup saved to: $BackupDir"
    Write-Log '+' "To rollback later: ROLLBACK.ps1 -BackupDir \`"$BackupDir\`""
}
catch {
    Write-Log '-' "Fatal error during backup: $_"
    exit 1
}
