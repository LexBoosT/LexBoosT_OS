@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE3.CMD - SECURITY & PRIVACY
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. SECURITY & PRIVACY
call :SecurityPrivacy

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

:SecurityPrivacy
echo.
echo ================================================
echo SECURITY - PRIVACY
echo ================================================


:: Block untrusted fonts
echo [+] Blocking untrusted fonts...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\MitigationOptions" /v MitigationOptions_FontBlocking /t REG_QWORD /d 1000000000000 /f >nul 2>&1

:: Prevent DLL hijacking
echo [+] Preventing DLL hijacking...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v CWDIllegalInDllSearch /t REG_DWORD /d 0x2 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v SafeDLLSearchMode /t REG_DWORD /d 1 /f >nul 2>&1

:: Block anonymous enumeration of SAM accounts
echo [+] Blocking anonymous SAM enumeration...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RestrictAnonymousSAM /t REG_DWORD /d 1 /f >nul 2>&1

:: Restrict anonymous enumeration of shares
echo [+] Restricting anonymous share enumeration...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RestrictAnonymous /t REG_DWORD /d 1 /f >nul 2>&1

:: Keep last user
echo [+] Configuring last user display...
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DontDisplayLastUserName /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable Shared Experiences
echo [+] Disabling shared experiences...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableMmx /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable auto-reboot after Windows updates
echo [+] Disabling auto-reboot...
reg add "HKLM\SOFTWARE\Microsoft\Windows\AU" /v NoAutorebootWithLoggedOnUser /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable Ink Workspace
echo [+] Disabling Ink Workspace...
reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" /v AllowWindowsInkWorkspace /t REG_DWORD /d 0 /f >nul 2>&1

:: Crash dump configuration (kernel memory dump — cohérent avec crash-control.yml)
:: Complete dump (1) nécessite pagefile >= RAM totale -> volmgr Event 49
:: Kernel dump (2) suffit pour le debug BSOD et ne requiert pas un pagefile oversized
echo [+] Configuring crash dump settings...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v DisplayParameters /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v LogEvent /t REG_DWORD /d 1 /f >nul 2>&1


:: Disable foreground lock
echo [+] Disabling foreground lock...
reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v ForegroundFlashCount /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v ForegroundLockTimeout /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable auto-runs
echo [+] Disabling auto-runs...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoAutorun /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\Main" /v Autorun /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoAutoplayfornonVolume /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v DontSetAutoplayCheckbox /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable remote shared folders
echo [+] Disabling remote shared folders...
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoRecentDocsNetHood /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable app launch tracking
echo [+] Disabling app launch tracking...
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_TrackProgs /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable Advertising
echo [+] Disabling advertising...
:: Deny access to account info
echo [+] Denying access to account info...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{C1D23ACC-752B-43E5-8448-8D0E519CD6D6}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Keep access to radios (Bluetooth/Wi-Fi toggle required by Settings)
echo [+] Preserving access to radios...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{A8804298-2D5F-42E3-9531-9C8C39EB29CE}" /v Value /t REG_SZ /d "Allow" /f >nul 2>&1

:: Deny access to diagnostics
echo [+] Denying access to diagnostics...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{2297E4E2-5DBE-466D-A12B-0F8286F0D9CA}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Deny access to contacts
echo [+] Denying access to contacts...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{7D7E8402-7C54-4821-A34E-AEEFD62DED93}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Deny access to calendar
echo [+] Denying access to calendar...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{D89823BA-7180-4B81-B50C-7E471E6121A3}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Deny access to call history
echo [+] Denying access to call history...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{8BC668CF-7728-45BD-93F8-CF2B3B41D7AB}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Deny access to email
echo [+] Denying access to email...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{9231CB4C-BF57-4AF3-8C55-FDA7BFCC04C5}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Deny access to tasks
echo [+] Denying access to tasks...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{E390DF20-07DF-446D-B962-F5C953072741}" /v Value /t REG_SZ /d "Deny" /f >nul 2>&1

:: Disable suggestions
echo [+] Disabling suggestions...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable delivery optimizations
echo [+] Disabling delivery optimizations (user-level)...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DownloadMode /t REG_DWORD /d 0 /f >nul 2>&1

:: Enable startup scripts async
echo [+] Enabling async startup scripts...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v RunStartupScriptSync /t REG_DWORD /d 0 /f >nul 2>&1

:: Fix disappearing cursor
echo [+] Fixing disappearing cursor...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableCursorSuppression /t REG_DWORD /d 0 /f >nul 2>&1

:: Stop license checking on every startup
:: NOTE: NoGenTicket=1 breaks Microsoft Account login chain — set to 0 instead (handled by privacy.yml)
echo [+] Stopping license checking...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform" /v NoGenTicket /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform" /v AllowWindowsEntitlementReactivation /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable blocking of downloaded files
echo [+] Disabling downloaded file blocking...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" /v SaveZoneInformation /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" /v SaveZoneInformation /t REG_DWORD /d 1 /f >nul 2>&1
:: Disable Bluetooth ads
echo [+] Disabling Bluetooth ads...
reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Bluetooth" /v AllowAdvertising /t REG_DWORD /d 0 /f >nul 2>&1

:: Hide most used apps in Start menu
echo [+] Hiding most used apps in Start menu...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoStartMenuMFUprogramsList /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable KB4524752 support notifications
echo [+] Disabling support notifications...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Gwx" /v DisableGwx /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable Microsoft Peer-to-Peer Networking Services
echo [+] Disabling P2P services...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Peernet" /v Disabled /t REG_DWORD /d 1 /f >nul 2>&1

:: Stop auto keyboard layout creation
echo [+] Stopping auto keyboard layout creation...
REG QUERY "HKEY_CURRENT_USER\.DEFAULT\Keyboard Layout\Preload" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    REG DELETE "HKEY_CURRENT_USER\.DEFAULT\Keyboard Layout\Preload" /f >nul 2>&1
)

:: Add new templates
echo [+] Adding new templates...
reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /v NullFile /t REG_SZ /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\.cmd\ShellNew" /v NullFile /t REG_SZ /f >nul 2>&1

:: Restrict Anonymous Access
echo [+] Restrict Anonymous Access
reg add "HKLM\SYSTEM\ControlSet001\Services\LanmanServer\Parameters" /v RestrictNullSessAccess /t REG_DWORD /d 1 /f >nul 2>&1

:: Restrict Anonymous Enumeration of Shares
echo [+] Restrict Anonymous Enumeration of Shares
reg add "HKLM\SYSTEM\ControlSet001\Control\Lsa" /v RestrictAnonymous /t REG_DWORD /d 1 /f >nul 2>&1

:: disable troubleshooting
echo [+] Disable troubleshooting
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnostics" /v EnableDiagnostics /t REG_DWORD /d 0 /f >nul 2>&1

:: disable online troubleshooting
echo [+] Disable online troubleshooting
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnosticsProvider\Policy" /v EnableQueryRemoteServer /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\ScriptedDiagnosticsProvider\Policy" /v EnableQueryRemoteServer /t REG_DWORD /d 0 /f >nul 2>&1

goto :eof
