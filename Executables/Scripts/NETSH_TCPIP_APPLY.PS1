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
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global ecncapability=disabled 2>$null } -TimeoutSec 3 -Description 'ecncapability=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global rss=enabled 2>$null } -TimeoutSec 3 -Description 'rss=enabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global rssbasecpu=0 2>$null } -TimeoutSec 3 -Description 'rssbasecpu=0'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global chimney=disabled 2>$null } -TimeoutSec 3 -Description 'chimney=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global netdma=disabled 2>$null } -TimeoutSec 3 -Description 'netdma=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global nonsackrttresiliency=disabled 2>$null } -TimeoutSec 3 -Description 'nonsackrttresiliency=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global autotuninglevel=normal 2>$null } -TimeoutSec 3 -Description 'autotuninglevel=normal'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global congestionprovider=ctcp 2>$null } -TimeoutSec 3 -Description 'congestionprovider=ctcp'
# initialRTO=2000 REMOVED (2026-10-03): the 2s first retransmit timer made
# RustDesk/AnyDesk session setup crawl on packet loss (relays, wake-from-sleep).
# Stock Windows initial RTO (~300ms) restores fast TCP handshakes with no
# gaming downside measurable at our MTU/RTO profile.
# Active reset: machines provisioned before the fix still carry 2000.
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global initialRTO=300 2>$null } -TimeoutSec 3 -Description 'initialRTO=300 (stock reset)'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global rsc=disabled 2>$null } -TimeoutSec 3 -Description 'rsc=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global timestamps=disabled 2>$null } -TimeoutSec 3 -Description 'timestamps=disabled'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global maxsynretransmissions=4 2>$null } -TimeoutSec 3 -Description 'maxsynretransmissions=4'
Invoke-WithTimeout -ScriptBlock { netsh int tcp set global prr=enabled 2>$null } -TimeoutSec 3 -Description 'prr=enabled'
Write-Log '+' 'TCP/IP global settings applied'

Write-Log '+' 'Applying UDP settings...'
Invoke-WithTimeout -ScriptBlock { netsh int udp set global uro=enabled 2>$null } -TimeoutSec 3 -Description 'uro=enabled'
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

Write-Log '+' 'Cleaning up VoIP QoS policies (DSCP/802.1p tagging removed — broke Discord/Vesktop)...'
Get-NetQosPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'VoIP' -or $_.Name -like 'VoIP_*' } | Remove-NetQosPolicy -Confirm:$false -ErrorAction SilentlyContinue
Write-Log '+' 'VoIP QoS policies cleaned'

Write-Log '+' 'Disabling Remote Assistance firewall rule...'
Invoke-WithTimeout -ScriptBlock { netsh advfirewall firewall set rule group='Remote Assistance' new enable=no *>$null } -TimeoutSec 3 -Description 'disable Remote Assistance'
Write-Log '+' 'Remote Assistance firewall disabled'

Write-Host '================================================'
Write-Host ' Network stack configured                        '
Write-Host '================================================'
# Exit cleanly
exit 0
