#Requires -Version 5.1

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ok = 0; $script:skip = 0; $script:fail = 0

function Banner { param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor DarkCyan
    Write-Host ('   ' + $Title) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor DarkCyan
}
function Step  { param([string]$T) Write-Host ('   -> ' + $T) -ForegroundColor Yellow }
function Ok    { param([string]$T) Write-Host ('   [OK ] ' + $T) -ForegroundColor Green;  $script:ok++ }
function Skip  { param([string]$T) Write-Host ('   [-- ] ' + $T) -ForegroundColor DarkGray; $script:skip++ }
function Fail  { param([string]$T) Write-Host ('   [!! ] ' + $T) -ForegroundColor Red;     $script:fail++ }

Banner 'LexBoosT - Ultimate Disk Cleanup'
$beforeFree = [math]::Round((Get-PSDrive C).Free / 1MB)

function Clear-Folder([string]$Path) {
    $exp = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not (Test-Path -LiteralPath $exp)) { Skip ('absent : ' + $Path); return }
    $n = 0
    Get-ChildItem -LiteralPath $exp -Force -EA SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -Recurse -EA SilentlyContinue
        $n++
    }
    if ($n -gt 0) { Ok ('cleared ' + $n + ' item(s) : ' + $exp) } else { Skip ('empty  : ' + $exp) }
}
function Clear-File([string]$Path) {
    $exp = [Environment]::ExpandEnvironmentVariables($Path)
    if (Test-Path -LiteralPath $exp) {
        Remove-Item -LiteralPath $exp -Force -EA SilentlyContinue
        if (Test-Path -LiteralPath $exp) { Fail ('locked : ' + $exp) } else { Ok ('deleted : ' + $exp) }
    } else { Skip ('absent : ' + $Path) }
}

# ---------- 1) Temporary / system folders ----------
Banner '1. Temporary / system folders'
@(
  '%WINDIR%\Temp',
  '%TEMP%',
  '%WINDIR%\Prefetch',
  '%SystemDrive%\$GetCurrent',
  '%SystemDrive%\$SysReset',
  '%SystemDrive%\$Windows.~BT',
  '%SystemDrive%\$Windows.~WS',
  '%SystemDrive%\$WinREAgent',
  '%SystemDrive%\OneDriveTemp',
  '%WINDIR%\Logs',
  '%WINDIR%\Installer\$PatchCache$',
  '%SYSTEMROOT%\Temp\CBS',
  '%SYSTEMROOT%\Logs\waasmedic',
  '%SYSTEMROOT%\Logs\SIH',
  '%SYSTEMROOT%\Traces\WindowsUpdate',
  '%SYSTEMROOT%\Panther',
  '%SYSTEMROOT%\ServiceProfiles\LocalService\AppData\Local\Temp',
  '%LOCALAPPDATA%\Microsoft\CLR_v4.0\UsageTraces',
  '%LOCALAPPDATA%\Microsoft\CLR_v4.0_32\UsageTraces',
  '%SYSTEMROOT%\Logs\NetSetup',
  '%SYSTEMROOT%\System32\LogFiles\setupcln'
) | ForEach-Object { Clear-Folder $_ }

# ---------- 2) Standalone log files ----------
Banner '2. Standalone log files'
@(
  '%SYSTEMROOT%\System32\catroot2\dberr.txt',
  '%SYSTEMROOT%\System32\catroot2.log',
  '%SYSTEMROOT%\System32\catroot2.jrs',
  '%SYSTEMROOT%\System32\catroot2.edb',
  '%SYSTEMROOT%\System32\catroot2.chk',
  '%SYSTEMROOT%\comsetup.log',
  '%SYSTEMROOT%\DtcInstall.log',
  '%SYSTEMROOT%\PFRO.log',
  '%SYSTEMROOT%\setupact.log',
  '%SYSTEMROOT%\setuperr.log',
  '%SYSTEMROOT%\setupapi.log',
  '%SYSTEMROOT%\inf\setupapi.app.log',
  '%SYSTEMROOT%\inf\setupapi.dev.log',
  '%SYSTEMROOT%\inf\setupapi.offline.log',
  '%SYSTEMROOT%\Performance\WinSAT\winsat.log',
  '%SYSTEMROOT%\debug\PASSWD.LOG',
  '%SYSTEMROOT%\Logs\CBS\CBS.log',
  '%SYSTEMROOT%\Logs\DISM\DISM.log'
) | ForEach-Object { Clear-File $_ }

# ---------- 3) Windows Update + Diagnostics (stop / clear / start) ----------
Banner '3. Windows Update + Diagnostics (stop / clear / start)'
if (Get-Service -Name wuauserv -EA SilentlyContinue) {
    Stop-Service -Name wuauserv -Force -EA SilentlyContinue
    Start-Sleep -Milliseconds 800
    Clear-Folder '%SYSTEMROOT%\SoftwareDistribution'
    Start-Service -Name wuauserv -EA SilentlyContinue
} else { Skip 'wuauserv not present' }

if (Get-Service -Name DiagTrack -EA SilentlyContinue) {
    Stop-Service -Name DiagTrack -Force -EA SilentlyContinue
    Start-Sleep -Milliseconds 800
    Clear-File '%PROGRAMDATA%\Microsoft\Diagnosis\ETLLogs\AutoLogger\AutoLogger-Diagtrack-Listener.etl'
    Clear-File '%PROGRAMDATA%\Microsoft\Diagnosis\ETLLogs\ShutdownLogger\AutoLogger-Diagtrack-Listener.etl'
    Start-Service -Name DiagTrack -EA SilentlyContinue
} else { Skip 'DiagTrack not present' }

# ---------- 4) Defender scan history (with permissions) ----------
Banner '4. Windows Defender scan history'
$dhist = [Environment]::ExpandEnvironmentVariables('%ProgramData%\Microsoft\Windows Defender\Scans\History')
if (Test-Path -LiteralPath $dhist) {
    takeown /f "$dhist" /A *> $null
    Clear-Folder '%ProgramData%\Microsoft\Windows Defender\Scans\History'
} else { Skip 'Defender history not present' }

# ---------- 5) App caches / traces ----------
Banner '5. App caches / traces'
@(
  '%PROGRAMFILES(X86)%\Steam\Dumps',
  '%PROGRAMFILES(X86)%\Steam\Traces',
  '%APPDATA%\Listary\UserData',
  '%APPDATA%\Sun\Java\Deployment\cache',
  '%APPDATA%\Macromedia\Flash Player',
  '%USERPROFILE%\.dotnet\TelemetryStorageService',
  '%APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations'
) | ForEach-Object { Clear-Folder $_ }

# ---------- 6) Event logs (Event Viewer) ----------
Banner '6. Event logs (Event Viewer)'
wevtutil sl Microsoft-Windows-LiveId/Operational "/ca:O:BAG:SYD:(A;;0x1;;;SY)(A;;0x5;;;BA)(A;;0x1;;;LA)" *> $null
$evt = wevtutil el
if ($evt) {
    foreach ($l in $evt) { wevtutil cl "$l" *> $null }
    Ok 'Event logs cleared'
} else { Skip 'No event logs to clear' }

# ---------- 7) Recent / MRU (registry history) ----------
Banner '7. Recent / MRU (registry history)'
$mru = @(
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRULegacy',
 'HKCU:\Software\Adobe\MediaBrowser\MRU',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Paint\Recent File List',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Paint\Recent File List',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Wordpad\Recent File List',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Map Network Drive MRU',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Map Network Drive MRU',
 'HKCU:\Software\Microsoft\Search Assistant\ACMru',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSaveMRU',
 'HKCU:\Software\Microsoft\MediaPlayer\Player\RecentFileList',
 'HKCU:\Software\Microsoft\MediaPlayer\Player\RecentURLList',
 'HKLM:\SOFTWARE\Microsoft\MediaPlayer\Player\RecentFileList',
 'HKLM:\SOFTWARE\Microsoft\MediaPlayer\Player\RecentURLList',
 'HKCU:\Software\Microsoft\Direct3D\MostRecentApplication',
 'HKLM:\SOFTWARE\Microsoft\Direct3D\MostRecentApplication'
)
foreach ($k in $mru) { Remove-Item -Path $k -Recurse -Force -EA SilentlyContinue }
Ok ('MRU registry history cleared (' + $mru.Count + ' keys)')

# ---------- 8) Recycle Bin ----------
Banner '8. Recycle Bin'
try {
    $bin = (New-Object -ComObject Shell.Application).NameSpace(10)
    $bin.Items() | ForEach-Object { Remove-Item -LiteralPath $_.Path -Force -Recurse -EA SilentlyContinue }
    Ok 'Recycle Bin emptied'
} catch { Fail ('Recycle Bin : ' + $_.Exception.Message) }

# ---------- 9) Disk Cleanup (cleanmgr volume cache) ----------
Banner '9. Disk Cleanup (cleanmgr)'
$vcBase = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$cats = @('Active Setup Temp Folders','BranchCache','Delivery Optimization Files','Device Driver Packages','Downloaded Program Files','Internet Cache Files','Language Pack','Offline Pages Files','Old ChkDsk Files','Setup Log Files','System error memory dump files','System error minidump files','Temporary Setup Files','Temporary Sync Files','Update Cleanup','Upgrade Discarded Files','User file versions','Windows Defender','Windows Error Reporting Files','Windows Reset Log Files','Windows Upgrade Log Files')
foreach ($c in $cats) {
    $kp = Join-Path $vcBase $c
    if (Test-Path $kp) { New-ItemProperty -Path $kp -Name 'StateFlags1337' -Value 2 -PropertyType DWord -Force -EA SilentlyContinue | Out-Null }
}
try { Start-Process -FilePath cleanmgr.exe -ArgumentList '/sagerun:1337' -WindowStyle Hidden | Out-Null; Ok 'Disk Cleanup launched in background (cleanmgr /sagerun:1337)' } catch { Fail ('cleanmgr : ' + $_.Exception.Message) }

# ---------- 10) Leftovers (Windows subfolders) ----------
Banner '10. Leftovers (Windows subfolders)'
@('CbsTemp','Logs','SoftwareDistribution','System32\LogFiles','System32\LogFiles\WMI','System32\SleepStudy','System32\sru','System32\WDI\LogFiles','System32\winevt\Logs','SystemTemp','Temp') | ForEach-Object {
    Clear-Folder ('%WINDIR%\' + $_)
}
# ---------- 11) Bonus: Windows.old + thumbnail/icon cache ----------
Banner '11. Bonus (Windows.old + thumbnail/icon cache)'
$oldPath = 'C:\Windows.old'
if (Test-Path -LiteralPath $oldPath) {
    Step 'Removing Windows.old (previous Windows installation)...'
    takeown /f "$oldPath" /A *> $null
    Remove-Item -LiteralPath $oldPath -Force -Recurse -EA SilentlyContinue
    if (Test-Path -LiteralPath $oldPath) { Fail 'Windows.old locked - remove it via Disk Cleanup > Previous Windows installation(s)' } else { Ok 'Windows.old removed' }
} else { Skip 'Windows.old not present' }

$explorerCache = [Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Microsoft\Windows\Explorer')
if (Test-Path -LiteralPath $explorerCache) {
    $thumbs = Get-ChildItem -LiteralPath $explorerCache -Filter 'thumbcache_*.db' -File -EA SilentlyContinue
    $icons  = Get-ChildItem -LiteralPath $explorerCache -Filter 'iconcache_*.db' -File -EA SilentlyContinue
    $n = 0
    @($thumbs) + @($icons) | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue
        if (Test-Path -LiteralPath $_.FullName) { Fail ('locked (Explorer open) : ' + $_.Name) } else { $n++ }
    }
    if ($n -gt 0) { Ok ('thumbnail/icon cache cleared (' + $n + ' file(s), rebuilt automatically)') } else { Skip 'thumbnail cache: nothing removed (Explorer locks them while open)' }
} else { Skip 'thumbnail cache folder absent' }

# ---------- 12) DNS cache flush ----------
Banner '12. DNS cache (flush)'
try {
    ipconfig /flushdns | Out-Null
    Ok 'DNS resolver cache flushed (ipconfig /flushdns)'
} catch { Fail ('DNS flush : ' + $_.Exception.Message) }

# ---------- Summary ----------
$afterFree = [math]::Round((Get-PSDrive C).Free / 1MB)
$freed = [math]::Max(0, $afterFree - $beforeFree)
Banner 'Summary'
Ok   ('targets OK        : ' + $script:ok)
Skip ('absent / empty    : ' + $script:skip)
if ($script:fail -gt 0) { Fail ('failed / locked    : ' + $script:fail) } else { Ok ('failed / locked    : 0') }
Write-Host ('   Free space reclaimed on C: ~ ' + $freed + ' MB') -ForegroundColor Magenta
Write-Host ''
Write-Host '   Done! A restart is not required, but rebooting frees space taken by locked files.' -ForegroundColor Cyan
exit 0
