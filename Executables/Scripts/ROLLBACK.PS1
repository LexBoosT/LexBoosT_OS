param (
    [Parameter(Mandatory = $false)]
    [string]$BackupDir = ""
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if (-not $scriptPath) {
        Write-Log '-' "Cannot determine script path for auto-elevation."
        Read-Host "Press Enter to exit"
        exit 1
    }
    $argList = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$scriptPath`""
    if ($BackupDir) { $argList += " -BackupDir `"$BackupDir`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit 0
}

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
    Write-Host "=== LexBoosT OS Rollback ==="

    if (-not $BackupDir) {
        $baseDir = "$env:ProgramData\LexBoosTOS\Backup"
        if (-not (Test-Path $baseDir)) {
            Write-Log '-' "ERROR: No backups found at $baseDir"
            Write-Log '-' "Specify a backup directory with: ROLLBACK.ps1 -BackupDir <path>"
            throw "No backups found"
        }
        $script:backupsList = @(Get-ChildItem -Path $baseDir -Directory | Sort-Object Name -Descending)
        if ($script:backupsList.Count -eq 0) {
            Write-Log '-' "ERROR: No backups found at $baseDir"
            throw "No backups found"
        }

        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "LexBoosT Restore Backup"
        $form.Size = New-Object System.Drawing.Size(720, 620)
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "Sizable"
        $form.MaximizeBox = $true
        $form.MinimizeBox = $false
        $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $form.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = "Select a backup to restore:"
        $lblTitle.AutoSize = $true
        $lblTitle.Location = New-Object System.Drawing.Point(16, 16)
        $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
        $form.Controls.Add($lblTitle)

        $listBox = New-Object System.Windows.Forms.ListBox
        $listBox.Location = New-Object System.Drawing.Point(16, 48)
        $listBox.Size = New-Object System.Drawing.Size(672, 260)
        $listBox.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $listBox.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
        $listBox.BorderStyle = "FixedSingle"
        $listBox.Font = New-Object System.Drawing.Font("Consolas", 9)
        $listBox.Anchor = "Top, Left, Right"
        $form.Controls.Add($listBox)

        $txtInfo = New-Object System.Windows.Forms.TextBox
        $txtInfo.Location = New-Object System.Drawing.Point(16, 318)
        $txtInfo.Size = New-Object System.Drawing.Size(672, 180)
        $txtInfo.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $txtInfo.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
        $txtInfo.BorderStyle = "FixedSingle"
        $txtInfo.Font = New-Object System.Drawing.Font("Consolas", 8)
        $txtInfo.Multiline = $true
        $txtInfo.ReadOnly = $true
        $txtInfo.ScrollBars = "Both"
        $txtInfo.WordWrap = $false
        $txtInfo.Anchor = "Top, Bottom, Left, Right"
        $form.Controls.Add($txtInfo)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "Restore"
        $btnOK.Location = New-Object System.Drawing.Point(508, 508)
        $btnOK.Size = New-Object System.Drawing.Size(85, 30)
        $btnOK.FlatStyle = "Flat"
        $btnOK.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
        $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.FlatAppearance.BorderSize = 0
        $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btnOK.Anchor = "Bottom, Right"
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.Add($btnOK)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(603, 508)
        $btnCancel.Size = New-Object System.Drawing.Size(85, 30)
        $btnCancel.FlatStyle = "Flat"
        $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $btnCancel.ForeColor = [System.Drawing.Color]::White
        $btnCancel.FlatAppearance.BorderSize = 0
        $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $btnCancel.Anchor = "Bottom, Right"
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($btnCancel)

        foreach ($b in $script:backupsList) {
            [void]$listBox.Items.Add($b.Name)
        }

        $listBox.Add_SelectedIndexChanged({
            $idx = $this.SelectedIndex
            if ($idx -ge 0 -and $idx -lt $script:backupsList.Count) {
                $selectedPath = $script:backupsList[$idx].FullName
                $manifestFile = Join-Path $selectedPath "backup-manifest.txt"
                if (Test-Path $manifestFile) {
                    $txtInfo.Text = Get-Content $manifestFile -Raw
                } else {
                    $items = Get-ChildItem -Path $selectedPath -Recurse -ErrorAction SilentlyContinue | Measure-Object
                    $txtInfo.Text = "Path: $selectedPath`r`nFiles: $($items.Count)  |  No manifest found."
                }
            }
        })

        if ($listBox.Items.Count -gt 0) {
            $listBox.SelectedIndex = 0
        }

        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Log '-' "Rollback cancelled."
            $form.Dispose()
            exit 0
        }

        $BackupDir = $script:backupsList[$listBox.SelectedIndex].FullName
        $form.Dispose()
        Write-Log '+' "Using backup: $BackupDir"
    }
    else {
        Write-Log '+' "Using backup: $BackupDir"
    }

    if (-not (Test-Path $BackupDir)) {
        Write-Log '-' "ERROR: Backup directory not found: $BackupDir"
        throw "Backup directory not found"
    }

    Write-Log '-' "WARNING: This will restore your system to the state before LexBoosT OS was applied."
    Write-Log '-' "Some changes may not be fully reversible without a Windows in-place upgrade."
    Write-Host ""

    # 1. Restore BCD
    Write-Log '+' "[1/5] Restoring BCD configuration..."
    $bcdFile = Join-Path $BackupDir "bcd-backup"
    if (Test-Path $bcdFile) {
        try {
            bcdedit /import $bcdFile /clean 2>$null
            Write-Log '+' "BCD restored."
        }
        catch {
            Write-Log '-' "Failed to restore BCD: $_"
        }
    }
    else {
        Write-Log '-' "No BCD backup found."
    }

    # 2. Restore registry keys
    Write-Log '+' "[2/5] Restoring registry keys..."
    $regBackupDir = Join-Path $BackupDir "Registry"
    $regLogFile = Join-Path $BackupDir "rollback-registry.log"
    $logHeader = @"
============================================================
LexBoosT OS - Registry Rollback Log
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Backup Dir: $BackupDir
============================================================

"@
    $logHeader | Out-File -FilePath $regLogFile -Encoding UTF8

    # Enable required privileges
    Write-Log '+' "Enabling SeRestorePrivilege..."
    $restorePriv = [Priv]::Enable("SeRestorePrivilege")
    Write-Log '+' "Enabling SeBackupPrivilege..."
    $backupPriv = [Priv]::Enable("SeBackupPrivilege")
    Write-Log '+' "Enabling SeTakeOwnershipPrivilege..."
    $takeOwnPriv = [Priv]::Enable("SeTakeOwnershipPrivilege")

    $privLine = "SeRestorePrivilege=$restorePriv SeBackupPrivilege=$backupPriv SeTakeOwnershipPrivilege=$takeOwnPriv"
    Write-Log '+' "Privileges: $privLine"
    $privLine | Out-File -FilePath $regLogFile -Encoding UTF8 -Append

    if (-not (Test-Path $regBackupDir)) {
        Write-Log '-' "No registry backups found."
        "============================================================`r`nNo registry backups found in: $regBackupDir`r`n============================================================`r`n" |
            Out-File -FilePath $regLogFile -Encoding UTF8
    }
    else {
        $targetedReg = Join-Path $regBackupDir "registry-backup.reg"

        if (-not (Test-Path $targetedReg)) {
            Write-Log '-' "registry-backup.reg not found in $regBackupDir."
            Write-Log '-' "No targeted registry backup to restore."
            "============================================================`r`nERROR: registry-backup.reg not found in: $regBackupDir`r`n============================================================`r`n" |
                Out-File -FilePath $regLogFile -Encoding UTF8
        }
        else {
            $fileSize = '{0:N0}' -f (Get-Item $targetedReg).Length
            Write-Log '+' "Importing: registry-backup.reg ($fileSize bytes)"
            $imported = $false
            $errorOutput = ""

            try {
                $result = & reg.exe import "$targetedReg" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $imported = $true
                }
                else {
                    $errorOutput = ($result | Out-String).Trim()
                }
            }
            catch {
                $errorOutput = $_.Exception.Message
            }

            if (-not $imported) {
                try {
                    & regedit.exe /s "$targetedReg" 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $imported = $true
                    }
                }
                catch {
                    if (-not $errorOutput) { $errorOutput = $_.Exception.Message }
                }
            }

            $logEntry = @"
--- registry-backup.reg ---
File Path: $targetedReg
File Size: $fileSize bytes
Imported : $imported
$(if ($imported) { "Status   : SUCCESS" } else { "Status   : FAILED" })
$(if ($errorOutput) { "Errors   : $errorOutput" } else { "" })

"@
            $logEntry | Out-File -FilePath $regLogFile -Encoding UTF8 -Append

            if ($imported) {
                Write-Log '+' "registry-backup.reg imported."
            }
            else {
                Write-Log '-' "Failed to import registry-backup.reg - see rollback-registry.log."
            }

            # Delete keys that were created by the playbook (didn't exist before)
            $createdFile = Join-Path $regBackupDir "registry-created.json"
            if (Test-Path $createdFile) {
                Write-Log '+' "Cleaning up keys created by the playbook..."
                try {
                    $createdPaths = Get-Content $createdFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    $deletedCount = 0
                    $deleteErrors = 0
                    foreach ($path in $createdPaths) {
                        try {
                            $result = & reg.exe delete "$path" /f 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                $deletedCount++
                                Write-Log '-' "Deleted: $path"
                            }
                            else {
                                $deleteErrors++
                                Write-Log '-' "Could not delete: $path"
                                "  [DELETE FAILED] $path - $($result | Out-String)" | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
                            }
                        }
                        catch {
                            $deleteErrors++
                            Write-Log '-' "Could not delete: $path"
                            "  [DELETE FAILED] $path - $_" | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
                        }
                    }
                    Write-Log '+' "$deletedCount keys deleted, $deleteErrors failed."
                    "Deleted created keys: $deletedCount success, $deleteErrors failed" | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
                }
                catch {
                    Write-Log '-' "Failed to parse registry-created.json: $_"
                    "Failed to clean up created keys: $_" | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
                }
            }
            else {
                Write-Log '-' "No registry-created.json found."
            }
        }

        # Log summary
        $summary = @"

============================================================
Rollback completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================================
"@
        $summary | Out-File -FilePath $regLogFile -Encoding UTF8 -Append
        Write-Log '+' "Registry log saved to: $regLogFile"
    }

    # 3. Restore services
    Write-Log '+' "[3/5] Restoring service state..."
    $servicesFile = Join-Path $BackupDir "services.xml"
    if (Test-Path $servicesFile) {
        try {
            $savedServices = Import-CliXml -Path $servicesFile
            $restoredCount = 0
            $skippedCount = 0
            foreach ($svc in $savedServices) {
                try {
                    $current = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                    if ($current) {
                        $currentType = $current.StartType.ToString()
                        $savedType = $svc.StartType.ToString()
                        if ($currentType -ne $savedType) {
                            Set-Service -Name $svc.Name -StartupType $svc.StartType -ErrorAction SilentlyContinue
                            Write-Log '+' "$($svc.Name): $currentType -> $savedType"
                            $restoredCount++
                        }
                    }
                    else {
                        $skippedCount++
                    }
                }
                catch {
                    $skippedCount++
                    continue
                }
            }
            Write-Log '+' "$restoredCount services restored, $skippedCount skipped (not found)."
        }
        catch {
            Write-Log '-' "Failed to restore services: $_"
        }
    }
    else {
        Write-Log '-' "No service state backup found."
    }

    # 4. Restore from System Restore Point (if available)
    Write-Log '+' "[4/5] Checking for system restore point..."
    try {
        $restorePoints = Get-ComputerRestorePoint | Where-Object { $_.Description -like "*LexBoosT OS*" } | Sort-Object CreationTime -Descending
        if ($restorePoints) {
            Write-Log '+' "Found restore point: $($restorePoints[0].Description) ($($restorePoints[0].CreationTime))"
            Write-Log '+' "To use this restore point, run: rstrui.exe"
            Write-Log '+' "(System Restore must be run interactively due to Windows restrictions)"
        }
        else {
            Write-Log '-' "No LexBoosT OS restore point found."
        }
    }
    catch {
        Write-Log '-' "Could not check restore points: $_"
    }

    # 5. Final cleanup and reboot prompt
    Write-Log '+' "[5/5] Rollback summary:"
    Write-Log '+' "Backup used: $BackupDir"
    Write-Host ""
    Write-Host "=== Rollback Complete ==="
    Write-Host ""
    Write-Log '+' "NOTE: A reboot is recommended to apply all changes."
    Write-Log '+' "Some changes may require an in-place Windows upgrade to fully revert."
    Write-Log '+' "Original packages snapshot saved to: $(Join-Path $BackupDir 'appx-packages.txt')"
    Write-Log '+' "Original programs list saved to: $(Join-Path $BackupDir 'installed-programs.txt')"
    Write-Host ""

    Write-Host "Press [R] to restart now, or any other key to exit..."
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'R') {
        Write-Log '+' "Rebooting..."
        shutdown /r /t 5 /c "LexBoosT OS rollback -- system will restart in 5 seconds."
        Write-Log '+' "System will restart in 5 seconds."
    }
    else {
        Write-Log '+' "Exiting..."
    }
    exit 0
}
catch {
    Write-Host ""
    Write-Host "=== FATAL ERROR ===" -ForegroundColor Red
    Write-Log '-' $_.Exception.Message
    Write-Log '-' $_.ScriptStackTrace
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
