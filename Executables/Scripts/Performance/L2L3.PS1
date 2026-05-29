#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Host '============================================'
Write-Host '       L2/L3 CPU Cache Configuration'
Write-Host '============================================'

Write-Log '+' 'Checking administrative privileges... OK'

$Processor = Get-WmiObject -Class Win32_Processor

$L2Cache = ($Processor | Measure-Object -Property L2CacheSize -Maximum).Maximum
$L3Cache = ($Processor | Measure-Object -Property L3CacheSize -Maximum).Maximum

$MaxL2CacheKB = 131072
$MaxL3CacheKB = 524288

if ($L2Cache -lt 256 -or $L2Cache -gt $MaxL2CacheKB) {
    Write-Log '-' "Invalid L2 Cache Size: $L2Cache KB (must be between 256 KB and $MaxL2CacheKB KB)"
    exit 0
}
if ($L3Cache -lt 1024 -or $L3Cache -gt $MaxL3CacheKB) {
    Write-Log '-' "Invalid L3 Cache Size: $L3Cache KB (must be between 1024 KB and $MaxL3CacheKB KB)"
    exit 0
}

$Path = "HKLM:\System\CurrentControlSet\Control\Session Manager\Memory Management"

$SecondLevelCache = Get-ItemProperty -Path $Path -Name "SecondLevelDataCache" -ErrorAction SilentlyContinue
if ($SecondLevelCache -and $SecondLevelCache.SecondLevelDataCache -ne $L2Cache) {
    Remove-ItemProperty -Path $Path -Name "SecondLevelDataCache"
}
New-ItemProperty -Path $Path -Name "SecondLevelDataCache" -Value $L2Cache -PropertyType DWORD -Force | Out-Null
Write-Log '+' "L2 Cache: $L2Cache KB ($([math]::Round($L2Cache/1024, 2)) MB)"

$ThirdLevelCache = Get-ItemProperty -Path $Path -Name "ThirdLevelDataCache" -ErrorAction SilentlyContinue
if ($ThirdLevelCache -and $ThirdLevelCache.ThirdLevelDataCache -ne $L3Cache) {
    Remove-ItemProperty -Path $Path -Name "ThirdLevelDataCache"
}
New-ItemProperty -Path $Path -Name "ThirdLevelDataCache" -Value $L3Cache -PropertyType DWORD -Force | Out-Null
Write-Log '+' "L3 Cache: $L3Cache KB ($([math]::Round($L3Cache/1024, 2)) MB)"

Write-Log '+' 'L2 and L3 cache sizes updated successfully'

Write-Host '============================================'
Write-Host '       Done!'
Write-Host '============================================'

exit 0
