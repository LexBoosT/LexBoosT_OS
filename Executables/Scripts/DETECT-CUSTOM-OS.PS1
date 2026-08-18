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

$editionSubHaystack = ''
try {
    $nv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    foreach ($n in @('EditionSubstring','EditionSubVersion','EditionSubManufacturer','RegisteredOrganization','RegisteredOwner')) {
        $v = $nv.$n
        if ($v) { $editionSubHaystack += ' ' + ([string]$v) }
    }
} catch { }

$haystack = ($productName + ' ' + $editionId + $editionSubHaystack).ToLower()

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
    @{ Name = 'KernelOS';         Patterns = @('kernelos','kernel os');                  Paths = @('C:\KernelOS');         Keys = @('HKLM:\SOFTWARE\KernelOS','HKLM:\SOFTWARE\WOW6432Node\KernelOS') },
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
    @{ Name = 'xOS';              Patterns = @('xos','x os');                            Paths = @('C:\xOS');              Keys = @() },
    @{ Name = 'SOS';              Patterns = @('sos');                                    Paths = @('C:\SOS');              Keys = @() },
    @{ Name = 'WinterOS';         Patterns = @('winteros','winter os');                  Paths = @('C:\WinterOS');         Keys = @() },
    @{ Name = 'SynergyOS';        Patterns = @('synergyos','synergy os');                Paths = @('C:\SynergyOS');        Keys = @() },
    @{ Name = 'KirbyOS';          Patterns = @('kirbyos','kirby os');                    Paths = @('C:\KirbyOS');          Keys = @() },
    @{ Name = 'LuminOS';          Patterns = @('luminos','lumin os');                    Paths = @('C:\LuminOS');          Keys = @() },
    @{ Name = 'FSOS';             Patterns = @('fsos','fs os');                          Paths = @('C:\Windows\FSOS');     Keys = @() }
)

foreach ($os in $osList) {
    if ($detected) { break }
    foreach ($pat in $os.Patterns) {
        if ($haystack -match "\b$pat\b") { $detected = $os.Name; break }
    }
    if ($detected) { break }
    foreach ($pat in $os.Patterns) {
        if ($oemHaystack -match "\b$pat\b") { $detected = $os.Name; break }
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

    $script:proceed = $false
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.ClientSize = New-Object System.Drawing.Size(540, 190)
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "LexBoosT OS cannot be installed over $detected.`n`nA clean stock Windows installation is required.`n`nDownload: $url"
    $label.AutoSize = $true
    $label.MaximumSize = New-Object System.Drawing.Size(500, 0)
    $label.Location = New-Object System.Drawing.Point(20, 20)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'OK - Quit & terminate AME'
    $btn.Size = New-Object System.Drawing.Size(230, 38)
    $btn.Location = New-Object System.Drawing.Point(155, 135)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = [System.Drawing.Color]::FromArgb(200, 30, 30)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Add_Click({
        $script:proceed = $true
        $form.Close()
    })

    $form.Controls.Add($label)
    $form.Controls.Add($btn)
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()

    if ($script:proceed) {
        Stop-Process -Name 'AME Beta','AME Wizard Beta','AME','TrustedUninstaller.CLI' -Force -ErrorAction SilentlyContinue
    }
    Write-Log '-' "Aborting installation."
    exit 1
}

Write-Log '+' "No incompatible custom OS detected."

$osInfo = Get-CimInstance Win32_OperatingSystem
if ($osInfo) {
    Write-Log '+' "System: $($osInfo.Caption) (Build $($osInfo.BuildNumber))"
} else {
    Write-Log '+' "System: unable to retrieve"
}

exit 0
