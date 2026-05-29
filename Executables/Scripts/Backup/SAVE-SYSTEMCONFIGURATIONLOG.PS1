#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$logDir = Join-Path $env:ProgramData 'LexBoosTOS\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'lexboost-system-config.txt'
$ver = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion')

'=== LexBoosT OS System Configuration Log ===' | Out-File $logFile -Encoding UTF8
"Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Encoding UTF8 -Append
'Playbook Version: 26.06' | Out-File $logFile -Encoding UTF8 -Append
"Windows: $($ver.ProductName) ($($ver.EditionID)) Build $($ver.CurrentBuild)" | Out-File $logFile -Encoding UTF8 -Append
"Architecture: $(if([Environment]::Is64BitOperatingSystem){'x64'}else{'x86'})" | Out-File $logFile -Encoding UTF8 -Append
try {
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    "CPU: $cpu" | Out-File $logFile -Encoding UTF8 -Append
} catch {}
try {
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    "RAM: ${ram}GB" | Out-File $logFile -Encoding UTF8 -Append
} catch {}
"User: $env:USERNAME" | Out-File $logFile -Encoding UTF8 -Append
Write-Log '+' "System configuration log saved to: $logFile"
