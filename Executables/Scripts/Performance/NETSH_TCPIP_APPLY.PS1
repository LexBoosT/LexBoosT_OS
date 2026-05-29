$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

function Invoke-WithTimeout {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSec = 15,
        [string]$Description = ''
    )
    try {
        $job = Start-Job -ScriptBlock $ScriptBlock
        $completed = Wait-Job $job -Timeout $TimeoutSec
        if (-not $completed) {
            Stop-Job $job | Out-Null
            Write-Log '-' "  [TIMEOUT] $Description"
        }
        Remove-Job $job -Force
    } catch {
        Write-Log '-' "  [ERROR] $Description : $_"
    }
}

Write-Host '================================================'
Write-Host ' LexBoosT OS - Network Stack Configuration       '
Write-Host '================================================'

Write-Log '+' 'Applying TCP/IP global settings...'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global rss=enabled 2>$null } -TimeoutSec 3 -Description 'rss=enabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global ecncapability=enabled 2>$null } -TimeoutSec 3 -Description 'ecncapability=enabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global initialRTO=2000 2>$null } -TimeoutSec 3 -Description 'initialRTO=2000'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global rsc=disabled 2>$null } -TimeoutSec 3 -Description 'rsc=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global timestamps=allowed 2>$null } -TimeoutSec 3 -Description 'timestamps=allowed'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global maxsynretransmissions=4 2>$null } -TimeoutSec 3 -Description 'maxsynretransmissions=4'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global fastopen=enabled 2>$null } -TimeoutSec 3 -Description 'fastopen=enabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global fastopenfallback=enabled 2>$null } -TimeoutSec 3 -Description 'fastopenfallback=enabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global prr=enabled 2>$null } -TimeoutSec 3 -Description 'prr=enabled'
Write-Log '+' 'TCP/IP global settings applied'

Write-Log '+' 'Applying TCP supplemental settings...'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set supplemental internet congestionprovider=cubic 2>$null } -TimeoutSec 3 -Description 'congestionprovider=cubic'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set supplemental internet enablecwndrestart=enabled 2>$null } -TimeoutSec 3 -Description 'enablecwndrestart=enabled'
Write-Log '+' 'TCP supplemental settings applied'

Write-Log '+' 'Applying UDP settings...'
Invoke-WithTimeout -ScriptBlock { netsh int udp set global uro=disabled 2>$null } -TimeoutSec 3 -Description 'uro=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int udp set global uso=enabled 2>$null } -TimeoutSec 3 -Description 'uso=enabled'
Write-Log '+' 'UDP settings applied'

Write-Log '+' 'Applying IP loopback settings...'
Invoke-WithTimeout -ScriptBlock { netsh int ip set global loopbacklargemtu=enable 2>$null } -TimeoutSec 3 -Description 'loopbacklargemtu'
Invoke-WithTimeout -ScriptBlock { netsh int ip set global loopbackworkercount=4 2>$null } -TimeoutSec 3 -Description 'loopbackworkercount'
Invoke-WithTimeout -ScriptBlock { netsh int ip set global loopbackexecutionmode=inline 2>$null } -TimeoutSec 3 -Description 'loopbackexecutionmode'
Write-Log '+' 'IP loopback settings applied'

Write-Log '+' 'Setting dynamic port range...'
Invoke-WithTimeout -ScriptBlock { netsh int ip set dynamicport tcp start=32769 num=32766 2>$null } -TimeoutSec 3 -Description 'dynamicport tcp'
Invoke-WithTimeout -ScriptBlock { netsh int ip set dynamicport udp start=32769 num=32766 2>$null } -TimeoutSec 3 -Description 'dynamicport udp'
Write-Log '+' 'Dynamic port range set'

Write-Log '+' 'Configuring VoIP QoS policies...'
if (Get-NetQosPolicy -Name 'VoIP' -ErrorAction SilentlyContinue) {
    Remove-NetQosPolicy -Name 'VoIP' -Confirm:$false -ErrorAction SilentlyContinue
}

$voipApps = @(
    'Discord.exe', 'DiscordPTB.exe', 'DiscordCanary.exe', 'DiscordDevelopment.exe',
    'TS3Client_win64.exe', 'TS3Client_win32.exe', 'TeamSpeak3.exe', 'ts3client.exe',
    'Mumble.exe', 'mumble.exe', 'Teams.exe', 'ms-teams.exe', 'Zoom.exe',
    'GoogleMeet.exe', 'meet.exe', 'GoogleMeetElectron.exe', 'Slack.exe',
    'Signal.exe', 'WhatsApp.exe', 'Telegram.exe', 'Vesktop.exe',
    'webexmta.exe', 'Jitsi Meet.exe', 'jitsi-meet.exe', 'Element.exe',
    'Riot.exe', 'Vencord.exe', 'BetterDiscord.exe', 'Equicord.exe'
)

foreach ($app in $voipApps) {
    $policyName = 'VoIP_' + $app.Replace('.exe', '')
    if (Get-NetQosPolicy -Name $policyName -ErrorAction SilentlyContinue) {
        Remove-NetQosPolicy -Name $policyName -Confirm:$false -ErrorAction SilentlyContinue
    }
    New-NetQosPolicy -Name $policyName -AppPathNameMatch $app -DSCPAction 46 -PriorityValue8021Action 7 -ErrorAction SilentlyContinue | Out-Null
}
Write-Log '+' 'VoIP QoS policies configured'

Write-Log '+' 'Restarting physical network adapters...'
$physicalAdapters = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and
    $_.InterfaceType -eq '6' -and
    $_.Name -notmatch 'vEthernet|Virtual|VPN|TAP-Windows|Loopback|Warp|Bluetooth'
}

if ($physicalAdapters) {
    foreach ($adapter in $physicalAdapters) {
        Write-Log '+' "Restarting: $($adapter.Name)"
        Invoke-WithTimeout -ScriptBlock {
            Disable-NetAdapter -Name $using:adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        } -TimeoutSec 3 -Description "Disable-NetAdapter $($adapter.Name)"
        Start-Sleep -Seconds 2
        Invoke-WithTimeout -ScriptBlock {
            Enable-NetAdapter -Name $using:adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        } -TimeoutSec 3 -Description "Enable-NetAdapter $($adapter.Name)"
    }
    Start-Sleep -Seconds 3
    Write-Log '+' 'Network adapters restarted'
} else {
    Write-Log '-' 'No physical adapters found'
}

Write-Log '+' 'Disabling Remote Assistance firewall rule...'
Invoke-WithTimeout -ScriptBlock { netsh advfirewall firewall set rule group='Remote Assistance' new enable=no *>$null } -TimeoutSec 3 -Description 'disable Remote Assistance'
Write-Log '+' 'Remote Assistance firewall disabled'

Write-Host '================================================'
Write-Host ' Network stack configured                        '
Write-Host '================================================'
# Exit cleanly
exit 0
