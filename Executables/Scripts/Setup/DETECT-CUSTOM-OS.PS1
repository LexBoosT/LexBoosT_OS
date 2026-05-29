#Requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$title = 'LexBoosT OS — Incompatible System Detected'
$url = 'www.microsoft.com/software-download/windows11'

Write-Host "=== LexBoosT OS Pre-Installation Compatibility Check ==="

$productName = ''
try {
    $pn = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ProductName' -ErrorAction SilentlyContinue).ProductName
    if ($pn) { $productName = [string]$pn }
} catch { }

$editionId = ''
try {
    $ed = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction SilentlyContinue).EditionID
    if ($ed) { $editionId = [string]$ed }
} catch { }

$haystack = ($productName + ' ' + $editionId).ToLower()

$oemHaystack = ''
try {
    $oemInfo = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' -ErrorAction SilentlyContinue
    if ($oemInfo) {
        foreach ($n in @('Manufacturer','Model','SupportURL','SupportPhone','SupportHours','Logo','SupportProvider','SupportAppLink')) {
            $v = $oemInfo.$n
            if ($v) { $oemHaystack += ' ' + ([string]$v) }
        }
    }
} catch { }
$oemHaystack = $oemHaystack.ToLower()

$detected = $null

$osList = @(
    @{ Name = 'AtlasOS';          Patterns = @('atlasos','atlas os');                    Paths = @('C:\Atlas');            Keys = @('HKLM:\SOFTWARE\AtlasOS') },
    @{ Name = 'ReviOS';           Patterns = @('revios','revi os');                      Paths = @('C:\ReviOS');           Keys = @('HKLM:\SOFTWARE\Revision','HKLM:\SOFTWARE\ReviOS') },
    @{ Name = 'Tiny11';           Patterns = @('tiny11','tiny 11');                      Paths = @('C:\Tiny11');           Keys = @() },
    @{ Name = 'Ghost Spectre';    Patterns = @('ghost spectre','ghostspectre','spectre'); Paths = @('C:\Ghost Spectre');   Keys = @() },
    @{ Name = 'Windows X-Lite';   Patterns = @('x-lite','xlite','windows x lite');       Paths = @('C:\X-Lite');           Keys = @() },
    @{ Name = 'CactusOS';         Patterns = @('cactusos','cactus os');                  Paths = @('C:\CactusOS');         Keys = @() },
    @{ Name = 'KernelOS';         Patterns = @('kernelos','kernel os');                  Paths = @('C:\KernelOS');         Keys = @() },
    @{ Name = 'YukiOS';           Patterns = @('yukios','yuki os');                      Paths = @('C:\YukiOS');           Keys = @() },
    @{ Name = 'NovaOS';           Patterns = @('novaos','nova os');                      Paths = @('C:\NovaOS');           Keys = @() },
    @{ Name = 'FoxOS';            Patterns = @('foxos','fox os');                        Paths = @('C:\FoxOS');            Keys = @() },
    @{ Name = 'ggOS';             Patterns = @('ggos','gg os');                          Paths = @('C:\ggOS');             Keys = @() },
    @{ Name = 'SapphireOS';       Patterns = @('sapphireos','sapphire os');              Paths = @('C:\SapphireOS');       Keys = @() },
    @{ Name = 'VainOS';           Patterns = @('vainos','vain os');                      Paths = @('C:\VainOS');           Keys = @() },
    @{ Name = 'BlitzOS';          Patterns = @('blitzos','blitz os');                    Paths = @('C:\BlitzOS');          Keys = @() },
    @{ Name = 'AtomOS';           Patterns = @('atomos','atom os');                      Paths = @('C:\AtomOS');           Keys = @() },
    @{ Name = 'IrisOS';           Patterns = @('irisos','iris os');                      Paths = @('C:\IrisOS');           Keys = @() },
    @{ Name = 'PeakOS';           Patterns = @('peakos','peak os');                      Paths = @('C:\PeakOS');           Keys = @() },
    @{ Name = 'xOS';              Patterns = @(' xos ',' x os ');                        Paths = @('C:\xOS');              Keys = @() },
    @{ Name = 'SOS';              Patterns = @(' sos ');                                 Paths = @('C:\SOS');              Keys = @() },
    @{ Name = 'WinterOS';         Patterns = @('winteros','winter os');                  Paths = @('C:\WinterOS');         Keys = @() },
    @{ Name = 'SynergyOS';        Patterns = @('synergyos','synergy os');                Paths = @('C:\SynergyOS');        Keys = @() },
    @{ Name = 'KirbyOS';          Patterns = @('kirbyos','kirby os');                    Paths = @('C:\KirbyOS');          Keys = @() },
    @{ Name = 'LuminOS';          Patterns = @('luminos','lumin os');                    Paths = @('C:\LuminOS');          Keys = @() },
    @{ Name = 'FSOS';             Patterns = @('fsos','fs os');                          Paths = @('C:\Windows\FSOS');     Keys = @() }
)

foreach ($os in $osList) {
    if ($detected) { break }
    foreach ($pat in $os.Patterns) {
        if ($haystack.Contains($pat)) { $detected = $os.Name; break }
    }
    if ($detected) { break }
    foreach ($pat in $os.Patterns) {
        if ($oemHaystack -and $oemHaystack.Contains($pat)) { $detected = $os.Name; break }
    }
    if ($detected) { break }
    foreach ($pth in $os.Paths) {
        if (Test-Path -LiteralPath $pth) { $detected = $os.Name; break }
    }
    if ($detected) { break }
    foreach ($k in $os.Keys) {
        if (Test-Path -LiteralPath $k) { $detected = $os.Name; break }
    }
}

if ($detected) {
    Write-Log '-' "Detected custom OS: $detected"
    Write-Log '-' "LexBoosT OS requires a clean stock Windows installation."
    Write-Log '-' "Download the latest Windows ISO from: $url"
    $msg = "LexBoosT OS cannot be installed over $detected.`n`nA clean stock Windows installation is required.`n`nDownload: $url"
    [System.Windows.Forms.MessageBox]::Show($msg, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly) | Out-Null
    Stop-Process -Name 'AME Beta','AME Wizard Beta','AME','TrustedUninstaller.CLI' -Force -ErrorAction SilentlyContinue
    Write-Log '-' "Aborting installation."
    exit 1
}

Write-Log '+' "No incompatible custom OS detected."

$osInfo = Get-CimInstance Win32_OperatingSystem
Write-Log '+' "System: $($osInfo.Caption) (Build $($osInfo.BuildNumber))"

exit 0
