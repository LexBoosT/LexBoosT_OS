@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE5.CMD - EVENT LOGS, QoS, REGISTRY CLEANUP
:: Scheduled tasks moved to SCHEDULED-TASKS-DISABLE.PS1
:: ================================================

call :CheckAdmin
call :EventLogs
call :QoSConfig
call :RegistryCleanup
goto :eof

:: ================================================
:: FUNCTIONS
:: ================================================

:CheckAdmin
echo.
echo ================================================
echo ADMINISTRATOR PRIVILEGES VERIFICATION
echo ================================================
echo [+] Checking administrator privileges...
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] net session failed, but the script is already invoked elevated by AME.
    echo [!] Continuing without re-elevation to avoid infinite RunAs loop.
    goto :eof
)
echo [OK] Administrator privileges confirmed
goto :eof

:EventLogs
echo.
echo ================================================
echo EVENT LOGS CONFIGURATION
echo ================================================
echo [+] Configuring event logs...
wevtutil sl Microsoft-Windows-SleepStudy/Diagnostic /q:false >NUL 2>nul
wevtutil sl Microsoft-Windows-Kernel-Processor-Power/Diagnostic /q:false >NUL 2>nul
wevtutil sl Microsoft-Windows-UserModePowerService/Diagnostic /q:false >NUL 2>nul

:: Disable all WINEVT analytic/debug channels (reduces disk I/O and CPU from event logging)
echo [+] Disabling WINEVT channels...
powershell -NoProfile -Command ^
  "try { " ^
  "  $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels', $true); " ^
  "  if ($root) { " ^
  "    foreach ($name in $root.GetSubKeyNames()) { " ^
  "      $sub = $null; " ^
  "      try { " ^
  "        $sub = $root.OpenSubKey($name, $true); " ^
  "        if ($sub -and ($sub.GetValue('Enabled') -eq 1)) { $sub.SetValue('Enabled', 0, 'DWord') } " ^
  "      } catch {} finally { if ($sub) { $sub.Close() } } " ^
  "    } " ^
  "    $root.Close() " ^
  "  } " ^
  "} catch {}" >nul 2>&1
echo [OK] WINEVT channels disabled
goto :eof

:QoSConfig
echo.
echo ================================================
echo QoS CONFIGURATION
echo ================================================
echo [+] Creating persistent QoS task...
powershell -Command "try { $trigger = New-ScheduledTaskTrigger -AtStartup; $psCommand = 'Get-NetQosPolicy -PolicyStore ActiveStore | Remove-NetQosPolicy -Confirm:$false; New-NetQosPolicy -Name Bufferbloat_throttle -PolicyStore ActiveStore -NetworkProfile 2 -IPProtocol TCP -Precedence 254 -DSCPAction 24 -MinBandwidthWeightAction 2; New-NetQosPolicy -Name Bufferbloat_priority -PolicyStore ActiveStore -NetworkProfile 2 -Default -Precedence 252 -DSCPAction 40 -MinBandwidthWeightAction 98'; $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-ExecutionPolicy Bypass -Command \"\"' + $psCommand + '\"\"'); Register-ScheduledTask -TaskName 'Bufferbloat' -Action $action -Trigger $trigger -User 'NT AUTHORITY\SYSTEM' -Force -ErrorAction SilentlyContinue } catch { Write-Warning 'Failed to create QoS task' }" >nul 2>&1
echo [OK] QoS task configured
goto :eof

:RegistryCleanup
echo.
echo ================================================
echo REGISTRY CLEANUP
echo ================================================
:: Registry: Windows Update Orchestrator
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate" /f >NUL 2>nul
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate" /v "workCompleted" /t REG_DWORD /d "1" /f >NUL 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" /f >NUL 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate" /f >NUL 2>nul
:: Driver Install kept enabled — required for CUDA/TensorRT driver updates
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Driver Install" /Enable >NUL 2>nul
echo [OK] Registry cleanup complete
goto :eof
