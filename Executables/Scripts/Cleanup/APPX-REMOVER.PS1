param (
    [Parameter(Mandatory = $true)]
    [string[]]$Packages,

    [switch]$Force = $false,

    [switch]$AppxOnly = $false
)

begin {
    # Admin check with explicit UAC request
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Packages $($Packages -join ',') $(if($Force){'-Force'}) $(if($AppxOnly){'-AppxOnly'})" -Verb RunAs
        exit
    }

    $baseRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore"
    $baseRegistryPath32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore"
    $global:ErrorActionPreference = "Stop"

    function Write-Log {
        param([string]$Status, [string]$Message)
        Write-Host "[$Status] $Message"
    }

    # Enable SeTakeOwnershipPrivilege / SeRestorePrivilege / SeBackupPrivilege
    $tokenPrivilegesDef = @'
using System;
using System.Runtime.InteropServices;

public class TokenManipulator {
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID_AND_ATTRIBUTES {
        public long Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES {
        public uint PrivilegeCount;
        public LUID_AND_ATTRIBUTES Privilege;
    }

    private const uint TOKEN_QUERY = 0x0008;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint SE_PRIVILEGE_ENABLED = 0x00000002;

    public static bool EnablePrivilege(string privilegeName) {
        IntPtr tokenHandle;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES, out tokenHandle))
            return false;
        try {
            long luid;
            if (!LookupPrivilegeValue(null, privilegeName, out luid))
                return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1 };
            tp.Privilege = new LUID_AND_ATTRIBUTES { Luid = luid, Attributes = SE_PRIVILEGE_ENABLED };
            return AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
        finally {
            CloseHandle(tokenHandle);
        }
    }
}
'@
    Add-Type -TypeDefinition $tokenPrivilegesDef -ErrorAction SilentlyContinue | Out-Null
    [TokenManipulator]::EnablePrivilege("SeTakeOwnershipPrivilege") | Out-Null
    [TokenManipulator]::EnablePrivilege("SeRestorePrivilege") | Out-Null
    [TokenManipulator]::EnablePrivilege("SeBackupPrivilege") | Out-Null

    # Enhanced registry ownership takeover
    function TakeRegistryOwnership {
        param([string]$path)
        if (-not (Test-Path $path)) { return $true }
        try {
            $acl = Get-Acl $path
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                [System.Security.Principal.NTAccount]::new("BUILTIN\Administrators"),
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.SetOwner([System.Security.Principal.NTAccount]::new("BUILTIN\Administrators"))
            $acl.AddAccessRule($rule)
            Set-Acl -Path $path -AclObject $acl -ErrorAction Stop
            return $true
        }
        catch {
            Write-Log '-' "Failed to take ownership of $path : $_"
            return $false
        }
    }

    # Check if a package is a system component (non-removable)
    function Is-SystemPackage {
        param($pkg)
        if ($pkg.IsFramework) { return $true }
        if ($pkg.SignatureKind -eq 'System') { return $true }
        if ($pkg.InstallLocation) {
            if (Test-IsSystemAppPath -path $pkg.InstallLocation) { return $true }
        }
        if ($pkg.Name -like 'Microsoft.VCLibs*' -or $pkg.Name -like 'Microsoft.NET.Native.*' -or $pkg.Name -like 'Microsoft.UI.Xaml*') { return $true }
        return $false
    }

    function Test-IsSystemAppPath {
        param([string]$path)
        try {
            $item = Get-Item -Path $path -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                return $false
            }
            return $item.FullName.StartsWith("$env:SystemRoot\SystemApps", [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            return $path.StartsWith("$env:SystemRoot\SystemApps", [StringComparison]::OrdinalIgnoreCase)
        }
    }

    # Nuclear registry key removal
    # Dans la section de suppression des clés de registre (remplacer la méthode actuelle) :
    function Remove-RegistryKeyNuclear {
        param([string]$path)
        try {
            if (-not (Test-Path $path)) { return $true }

            # Prendre ownership AVANT suppression
            if (-not (TakeRegistryOwnership -path $path)) {
                throw "Failed to take ownership"
            }

            # Suppression récursive
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 200  # Pause pour éviter les verrous résiduels

            # Vérification finale
            if (Test-Path $path) {
                throw "Registry key still exists after removal"
            }
            return $true
        }
        catch {
            Write-Log '-' "Nuclear registry removal failed: $_"
            # Fallback avec reg.exe
            try {
                $null = reg.exe delete "$path" /f 2>&1
                return $true
            }
            catch {
                return $false
            }
        }
    }

    # Advanced file system removal
    function Remove-FileSystemItemNuclear {
        param([string]$path)
        try {
            if (-not (Test-Path $path)) { return $true }

            # Never attempt to delete system-protected directories
            if ($path -match [regex]::Escape($env:SystemRoot)) {
                Write-Log '-' "Skipping system path: $path"
                return $false
            }

            # Take ownership
            $takeown = Start-Process -FilePath "takeown.exe" -ArgumentList "/F `"$path`" /A /R /D Y" -Wait -PassThru -WindowStyle Hidden

            # Set full control
            $icacls = Start-Process -FilePath "icacls.exe" -ArgumentList "`"$path`" /grant `"Administrators:F`" /T /C /Q" -Wait -PassThru -WindowStyle Hidden

            # Remove with retry logic
            $maxRetries = 5
            for ($i = 0; $i -lt $maxRetries; $i++) {
                try {
                    if (-not (Test-Path $path)) { return $true }
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($_.Exception -is [System.Management.Automation.ItemNotFoundException]) {
                        return $true
                    }
                    if ($i -eq ($maxRetries - 1)) { throw }
                    Start-Sleep -Seconds 1
                    [GC]::Collect() # Force garbage collection
                }
            }
            return $true
        }
        catch {
            if ($_.Exception -is [System.Management.Automation.ItemNotFoundException]) {
                return $true
            }
            Write-Log '-' "Nuclear filesystem removal failed: $_"
            return $false
        }
    }
}

process {
    try {
        # Elevate to SYSTEM context temporarily
        $elevatedProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -Command `"whoami`"" -Verb RunAs -WindowStyle Hidden -PassThru
        $elevatedProcess.WaitForExit()

        Write-Log '+' "Removing AppX packages..."

        # === PRE-SNAPSHOT: save current AppX list ===
        $snapshotDir = "$env:ProgramData\LexBoosTOS\Logs"
        if (-not (Test-Path $snapshotDir)) { New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null }
        $snapshotFile = Join-Path $snapshotDir "appx-packages-before.txt"
        try {
            Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, Status |
                Sort-Object Name | Out-File -FilePath $snapshotFile -Encoding UTF8
            $beforePackages = Get-AppxPackage -AllUsers | Select-Object -ExpandProperty PackageFullName
            Write-Log '+' "Pre-snapshot saved: $($beforePackages.Count) packages"
        }
        catch {
            Write-Log '-' "Failed to take pre-snapshot: $_"
            $beforePackages = @()
        }

        $removedCount = 0

        # Get all packages excluding Store
        $allPackages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -notmatch 'Microsoft.WindowsStore' }

        foreach ($packagePattern in $Packages) {
            $filteredPackages = $allPackages | Where-Object {
                $_.PackageFullName -like "*$packagePattern*" -or
                $_.Name -like "*$packagePattern*"
            }

            if (-not $filteredPackages -and $Force) {
                $filteredPackages = $allPackages | Where-Object {
                    $_.PackageFullName -like "*$packagePattern*"
                }
            }

            foreach ($pkg in $filteredPackages) {
                $fullPackageName = $pkg.PackageFullName
                $packageFamilyName = $pkg.PackageFamilyName
                $installLocation = $pkg.InstallLocation
                $isSystem = Is-SystemPackage -pkg $pkg

                if (-not $AppxOnly -and -not $isSystem) {
                    # ===== 1. Registry Cleanup (First to break dependencies) =====
                    try {
                        # AppxAllUserStore entries (x64 + x86)
                        $registryPaths = @(
                            "$baseRegistryPath\Applications\$fullPackageName",
                            "$baseRegistryPath\Deprovisioned\$packageFamilyName",
                            "$baseRegistryPath\EndOfLife\*\$fullPackageName",
                            "$baseRegistryPath\InboxApplications\$fullPackageName",
                            "$baseRegistryPath\Staged\$packageFamilyName",
                            "$baseRegistryPath32\Applications\$fullPackageName",
                            "$baseRegistryPath32\Deprovisioned\$packageFamilyName",
                            "$baseRegistryPath32\EndOfLife\*\$fullPackageName",
                            "$baseRegistryPath32\InboxApplications\$fullPackageName",
                            "$baseRegistryPath32\Staged\$packageFamilyName"
                        )

                        foreach ($regPath in $registryPaths) {
                            Remove-RegistryKeyNuclear -path $regPath | Out-Null
                        }

                        # Additional known registry locations
                        $additionalRegPaths = @(
                            "HKLM:\SOFTWARE\Classes\Extensions\ContractId\Windows.App\$packageFamilyName",
                            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\$fullPackageName",
                            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\*\$fullPackageName",
                            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\*\$fullPackageName"
                        )

                        foreach ($regPath in $additionalRegPaths) {
                            Remove-RegistryKeyNuclear -path $regPath | Out-Null
                        }
                    }
                    catch {
                        Write-Log '-' "Registry cleanup error: $_"
                    }
                }

                # ===== 2. Package Removal =====
                try {
                    # Per-user removal
                    foreach ($userInfo in $pkg.PackageUserInformation) {
                        $userSid = $userInfo.UserSecurityID.SID
                        try {
                            Remove-AppxPackage -Package $fullPackageName -User $userSid -ErrorAction Stop *>$null
                        }
                        catch {
                            $msg = "$_"
                            if ($_.Exception.HResult -notin @(0x80073CFA, 0x80070032) -and $msg -notmatch '0x80073CFA|0x80070032') {
                                Write-Log '-' "Failed user removal ($userSid): $_"
                            }
                            if (-not $Force) { continue }
                        }
                    }

                    # All-users removal
                    Remove-AppxPackage -Package $fullPackageName -AllUsers -ErrorAction Stop *>$null
                    if ($?) { $removedCount++ }
                }
                catch {
                    $msg = "$_"
                    if ($_.Exception.HResult -notin @(0x80073CFA, 0x80070032) -and $msg -notmatch '0x80073CFA|0x80070032') {
                        Write-Log '-' "Package removal failed: $_"
                    }
                    if (-not $Force) { continue }
                }

                if (-not $AppxOnly -and -not $isSystem) {
                    # ===== 3. File System Cleanup =====
                    try {
                        # Standard package location
                        $packageRoot = [System.IO.Path]::Combine($env:ProgramFiles, "WindowsApps", $packageFamilyName)
                        if (Test-Path $packageRoot) {
                            Remove-FileSystemItemNuclear -path $packageRoot | Out-Null
                        }

                        # Install location cleanup
                        if ($installLocation -and (Test-Path $installLocation)) {
                            Remove-FileSystemItemNuclear -path $installLocation | Out-Null
                        }

                        # Cleanup potential leftover directories
                        if (-not [string]::IsNullOrEmpty($packageFamilyName)) {
                            $potentialPaths = @(
                                "${env:ProgramFiles}\WindowsApps\$packageFamilyName*",
                                "${env:ProgramData}\Packages\$packageFamilyName*",
                                "${env:LocalAppData}\Packages\$packageFamilyName*"
                            )

                            foreach ($pathPattern in $potentialPaths) {
                                Get-Item $pathPattern -ErrorAction SilentlyContinue | ForEach-Object {
                                    Remove-FileSystemItemNuclear -path $_.FullName | Out-Null
                                }
                            }
                        }
                    }
                    catch {
                        Write-Log '-' "Filesystem cleanup error: $_"
                    }
                }

                # ===== 4. Provisioned Package Removal =====
                try {
                    Get-AppxProvisionedPackage -Online 2>$null 3>$null |
                    Where-Object { $_.PackageName -like "*$packagePattern*" -or $_.PackageFamilyName -eq $packageFamilyName } |
                    ForEach-Object {
                        $_ | Remove-AppxProvisionedPackage -Online -ErrorAction Stop *>$null
                    }
                }
                catch {
                    $msg = "$_"
                    if ($_.Exception.HResult -notin @(0x80073CFA, 0x80070032) -and $msg -notmatch '0x80073CFA|0x80070032') {
                        Write-Log '-' "Provisioned package removal failed: $_"
                    }
                }
            }
        }
    }
    catch {
        Write-Log '-' "Fatal error: $_"
        exit 1
    }
}

end {
    Write-Log '+' "AppX packages removed: $removedCount"

    # === POST-SNAPSHOT: save remaining AppX list and generate diff ===
    try {
        $afterFile = Join-Path $snapshotDir "appx-packages-after.txt"
        Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, Status |
            Sort-Object Name | Out-File -FilePath $afterFile -Encoding UTF8
        $afterPackages = Get-AppxPackage -AllUsers | Select-Object -ExpandProperty PackageFullName

        if ($beforePackages) {
            $removedList = $beforePackages | Where-Object { $_ -notin $afterPackages }
            $removedFile = Join-Path $snapshotDir "appx-packages-removed.txt"
            if ($removedList) {
                "=== AppX Packages Removed by LexBoosT OS ===`n" | Out-File -FilePath $removedFile -Encoding UTF8
                $removedList | Sort-Object | Out-File -FilePath $removedFile -Encoding UTF8 -Append
                "`nTotal removed: $($removedList.Count)" | Out-File -FilePath $removedFile -Encoding UTF8 -Append
            } else {
                "No AppX packages were removed." | Out-File -FilePath $removedFile -Encoding UTF8
            }
            Write-Log '+' "Post-snapshot saved. Removed packages report: $removedFile"
        }
    }
    catch {
        Write-Log '-' "Failed to generate post-snapshot: $_"
    }
}
