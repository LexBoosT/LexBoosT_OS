@echo off
setlocal enabledelayedexpansion

:: ================================================
:: FINALIZE5.CMD - TASK MANAGEMENT
:: ================================================

:: 1. ADMINISTRATOR VERIFICATION
call :CheckAdmin

:: 2. TASK MANAGEMENT
call :TaskManagement

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
    echo [ERROR] Administrator privileges required
    echo [+] Restarting with elevated privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
echo [OK] Administrator privileges confirmed
goto :eof

:TaskManagement
echo.
echo ================================================
echo TASK MANAGEMENT
echo ================================================

:: Event logs configuration
echo [+] Configuring event logs...
wevtutil sl Microsoft-Windows-SleepStudy/Diagnostic /q:false >NUL 2>nul
wevtutil sl Microsoft-Windows-Kernel-Processor-Power/Diagnostic /q:false >NUL 2>nul
wevtutil sl Microsoft-Windows-UserModePowerService/Diagnostic /q:false >NUL 2>nul

:: Disabling Windows tasks
echo [+] Disabling Windows tasks...

schtasks /Change /TN "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Application Experience\AitAgent" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScanAfterUpdate" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expedite Work" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan" /Disable >NUL 2>nul
schtasks /Change /TN "DUpdaterTask" /Disable >NUL 2>nul
schtasks /Change /TN "ModifyLinkUpdate" /Disable >NUL 2>nul
schtasks /Change /TN "StartAUEP" /Disable >NUL 2>nul
schtasks /Change /TN "StartCN" /Disable >NUL 2>nul
schtasks /Change /TN "StartCNBM" /Disable >NUL 2>nul
schtasks /Change /TN "StartDVR" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Application Experience\PcaPatchDbTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Application Experience\SdbinstMergeDbTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Autochk\Proxy" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Defrag\ScheduledDefrag" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Device Information\Device" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Device Information\Device User" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Diagnosis\Scheduled" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\DiskCleanup\SilentCleanup" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\DiskFootprint\Diagnostics" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\DiskFootprint\StorageSense" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\DUSM\dusmtask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\EnterpriseMgmt\MDMMaintenenceTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\FileHistory\File History (maintenance mode)" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\License Manager\TempSignedLicenseExchange" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Management\Connectivity\ESIMPM" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Management\Provisioning\Cellular" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Management\Provisioning\Logon" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Maintenance\WinSAT" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\MUI\LPRemove" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\NlaSvc\WiFiTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\NetTrace\GatherNetworkInfo" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Network Connectivity Status Indicator\NcsiIdentifyUserProxies" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\NetworkExperimentation" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\PI\Sqm-Tasks" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Printing\EduPrintProv" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Printing\PrinterCleanupTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Printing\PrintJobCleanupTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\PushToInstall\Registration" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Ras\MobilityManager" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\RecoveryEnvironment\VerifyWinRE" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\RetailDemo\CleanupOfflineContent" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Servicing\StartComponentCleanup" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Setup\SetupCleanupTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Setup\SnapshotCleanupTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Shell\FamilySafetyMonitor" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Shell\FamilySafetyRefreshTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\SpacePort\SpaceAgentTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\SpacePort\SpaceManagerTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Speech\SpeechModelDownloadTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Storage Tiers Management\Storage Tiers Management Initialization" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Sustainability\PowerGridForecastTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Sustainability\SustainabilityTelemetry" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Task Manager\Interactive" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Time Synchronization\ForceSynchronizeTime" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Time Synchronization\SynchronizeTime" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Time Zone\SynchronizeTimeZone" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\TPM\Tpm-HASCertRetr" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\TPM\Tpm-Maintenance" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\UPnP\UPnPHostConfig" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\User Profile Service\HiveUploadTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WCM\WiFiTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WDI\ResolutionHost" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Windows Filtering Platform\BfeOnServiceStartTypeChange" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WindowsUpdate\Scheduled Start" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WlanSvc\CDSSync" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WlanSvc\MoProfileManagement" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WOF\WIM-Hash-Management" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WOF\WIM-Hash-Validation" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Work Folders\Work Folders Logon Synchronization" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Work Folders\Work Folders Maintenance Work" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\Workplace Join\Automatic-Device-Join" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WwanSvc\NotificationTask" /Disable >NUL 2>nul
schtasks /Change /TN "Microsoft\Windows\WwanSvc\OobeDiscovery" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Sysmain\ResPriStaticDbSync" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Sysmain\WsSwapAssessmentTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WaaSMedic\PerformRemediation" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Kernel\La57Cleanup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ReFsRedupSvc\Initialization" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\USB\Usb-Notifications" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Flighting\OneSettings\RefreshCache" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Containers\CmCleanup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ApplicationData\CleanupTemporaryState" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\LocalUserSyncDataAvailable" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Chkdsk\ProactiveScan" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\PerformanceTrace\RequestTrace" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Report Policies" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan_LicenseAccepted" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Active Directory Rights Management Services Client\AD RMS Rights Policy Template Management (Manual)" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Feedback\Siuf\DmClient" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\InputSettingsRestoreDataAvailable" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\BitLocker\BitLocker MDM policy Refresh" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\BitLocker\BitLocker Encrypt All Drives" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\CloudRestore\Restore" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\syncpensettings" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\TouchPadSyncDataAvailable" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\MouseSyncDataAvailable" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Input\PenSyncDataAvailable" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\EDP\StorageCardEncryption Task" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Shell\ThemesSyncedImageDownload" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Location\Notifications" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Maps\MapsToastTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan for Crash Recovery" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\AppListBackup\Backup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\CloudRestore\Backup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\AppListBackup\BackupNonMaintenance" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\InstallService\ScanForUpdates" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Registry\RegIdleBackup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\StateRepository\MaintenanceTasks" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ApplicationData\appuriverifierdaily" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Location\WindowsActionDialog" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ApplicationData\appuriverifierinstall" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\BrokerInfrastructure\BgTaskRegistrationMaintenanceTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Device Setup\Metadata Refresh" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\InstallService\SmartRetry" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\PushToInstall\LoginCheck" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\ApplicationData\DsSvcCleanup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Data Integrity Scan\Data Integrity Check And Scan" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\SettingSync\BackgroundUploadTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\SettingSync\NetworkStateChangeTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Shell\sSyncedImageDownload" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Wininet\CacheTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Refresh Group Policy Cache" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Application Experience\StartupAppTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Maps\MapsUpdateTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\RetailDemo\Cleanup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Sysmain\HybridDriveCachePrepopulate" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Sysmain\HybridDriveCacheRebalance" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\SystemRestore\SR" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Backup Scan" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Maintenance Install" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Policy Install" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Refresh Settings" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Resume On Boot" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WaaS\WaaSMedicAgent" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Automatic App Update" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sih" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sihboot" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTask" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTaskLogon" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\Application Experience\MareBackup" /Disable >NUL 2>nul
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker" /Disable >NUL 2>nul
schtasks /Change /TN "\MicrosoftEdgeUpdateTaskMachineCore" /Disable >NUL 2>nul
schtasks /Change /TN "\MicrosoftEdgeUpdateTaskMachineUA" /Disable >NUL 2>nul

powershell -Command "Get-ScheduledTask -TaskPath '\Microsoft\Windows\' -TaskName 'DeviceDirectoryClient' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:`$false -ErrorAction SilentlyContinue" >nul 2>&1
:: Creating persistent QoS task
echo [+] Creating persistent QoS task...
powershell -Command "try { $trigger = New-ScheduledTaskTrigger -AtStartup; $psCommand = 'Get-NetQosPolicy -PolicyStore ActiveStore | Remove-NetQosPolicy -Confirm:$false; New-NetQosPolicy -Name Bufferbloat_throttle -PolicyStore ActiveStore -NetworkProfile 2 -IPProtocol TCP -Precedence 254 -DSCPAction 24 -MinBandwidthWeightAction 2; New-NetQosPolicy -Name Bufferbloat_priority -PolicyStore ActiveStore -NetworkProfile 2 -Default -Precedence 252 -DSCPAction 40 -MinBandwidthWeightAction 98'; $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-ExecutionPolicy Bypass -Command ""' + $psCommand + '""'); Register-ScheduledTask -TaskName 'Bufferbloat' -Action $action -Trigger $trigger -User 'NT AUTHORITY\SYSTEM' -Force -ErrorAction SilentlyContinue } catch { Write-Warning 'Failed to create QoS task' }" >nul 2>&1

:: Disable unnecessary scheduled tasks
echo [+] Disabling unnecessary scheduled tasks...
powershell -Command "Get-ScheduledTask -TaskPath '\Microsoft\Windows\AppxDeploymentClient\' -TaskName 'UCPD velocity' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue" >nul 2>&1
powershell -Command "Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName 'ProgramDataUpdater' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue" >nul 2>&1

goto :eof
