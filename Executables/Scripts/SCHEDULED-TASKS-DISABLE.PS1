#Requires -Version 5.1
# ================================================================
# SCHEDULED-TASKS-DISABLE.PS1
# Consolidated scheduled task disabler for LexBoosT OS
# Replaces: FINALIZE5.CMD (task section), NETWORK-EXTRAS.PS1
#           (TaskScheduler section), DISABLE_OFFICE_TASKS.PS1
# ================================================================

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# ----------------------------------------------------------------
# Master task list M-bM-^@M-^T all tasks to disable
# Query-before-disable: no errors logged for absent tasks
# ----------------------------------------------------------------
$tasksToDisable = @(
    # --- Application Experience & Telemetry ---
    '\Microsoft\Windows\Application Experience\AitAgent'
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp'
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask'
    '\Microsoft\Windows\Application Experience\StartupAppTask'
    '\Microsoft\Windows\Application Experience\MareBackup'
    '\Microsoft\Windows\PI\Sqm-Tasks'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'

    # --- Customer Experience Improvement Program (CEIP) ---
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\Customer Experience Improvement Program\Uploader'
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM'
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerCeipAssistant'
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleCollector'
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleUsageCollector'

    # --- Autochk & Chkdsk ---
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Chkdsk\ProactiveScan'

    # --- Diagnostics ---
    '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner'
    '\Microsoft\Windows\Diagnosis\Scheduled'
    '\Microsoft\Windows\Diagnosis\UnexpectedCodepath'
    '\Microsoft\Windows\Hotpatch\Monitoring'
    '\Microsoft\Windows\PerformanceTrace\RequestTrace'
    '\Microsoft\Windows\PerformanceTrace\WhesvcToast'

    # --- Disk & Storage ---
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\DiskCleanup\SilentCleanup'
    '\Microsoft\Windows\DiskFootprint\Diagnostics'
    '\Microsoft\Windows\DiskFootprint\StorageSense'
    '\Microsoft\Windows\Defrag\ScheduledDefrag'
    '\Microsoft\Windows\Storage Tiers Management\Storage Tiers Management Initialization'
    '\Microsoft\Windows\Sysmain\ResPriStaticDbSync'
    '\Microsoft\Windows\Sysmain\WsSwapAssessmentTask'
    '\Microsoft\Windows\Sysmain\HybridDriveCachePrepopulate'
    '\Microsoft\Windows\Sysmain\HybridDriveCacheRebalance'
    '\Microsoft\Windows\SpacePort\SpaceAgentTask'
    '\Microsoft\Windows\SpacePort\SpaceManagerTask'
    '\Microsoft\Windows\ReFsRedupSvc\Initialization'
    '\Microsoft\Windows\WOF\WIM-Hash-Management'
    '\Microsoft\Windows\WOF\WIM-Hash-Validation'

    # --- DUSM (Data Usage) ---
    '\Microsoft\Windows\DUSM\dusmtask'

    # --- File History & Backup ---
    '\Microsoft\Windows\FileHistory\File History (maintenance mode)'
    '\Microsoft\Windows\AppListBackup\Backup'
    '\Microsoft\Windows\AppListBackup\BackupNonMaintenance'
    '\Microsoft\Windows\CloudRestore\Restore'
    '\Microsoft\Windows\CloudRestore\Backup'
    '\Microsoft\Windows\SystemRestore\SR'

    # --- Flighting / OS Insider ---
    '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures'
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing'
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver'
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting'
    '\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting'
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache'

    # --- InstallService (Store/Update scan) ---
    '\Microsoft\Windows\InstallService\ScanForUpdates'
    '\Microsoft\Windows\InstallService\ScanForUpdatesAsUser'
    '\Microsoft\Windows\InstallService\SmartRetry'
    '\Microsoft\Windows\InstallService\RestoreDevice'
    '\Microsoft\Windows\InstallService\WakeUpAndContinueUpdates'
    '\Microsoft\Windows\InstallService\WakeUpAndScanForUpdates'

    # --- UpdateOrchestrator (USO) ---
    '\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expediate Work'
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan_LicenseAccepted'
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan_OobeAppReady'
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work'
    '\Microsoft\Windows\UpdateOrchestrator\Report Policies'
    '\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task'
    '\Microsoft\Windows\UpdateOrchestrator\Backup Scan'
    '\Microsoft\Windows\UpdateOrchestrator\Maintenance Install'
    '\Microsoft\Windows\UpdateOrchestrator\Policy Install'
    '\Microsoft\Windows\UpdateOrchestrator\Reboot_AC'
    '\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery'
    '\Microsoft\Windows\UpdateOrchestrator\Refresh Settings'
    '\Microsoft\Windows\UpdateOrchestrator\Resume On Boot'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Maintenance Work'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Work'
    '\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask'
    '\Microsoft\Windows\UpdateOrchestrator\AC Power Download'
    '\Microsoft\Windows\UpdateOrchestrator\AC Power Install'
    '\Microsoft\Windows\UpdateOrchestrator\Battery Saver Deferred Install'
    '\Microsoft\Windows\UpdateOrchestrator\MusUx_LogonUpdateResults'
    '\Microsoft\Windows\UpdateOrchestrator\MusUx_UpdateInterval'
    '\Microsoft\Windows\UpdateOrchestrator\Reboot'
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Retry Scan'
    '\Microsoft\Windows\UpdateOrchestrator\USO_Broker_Display'
    '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker_Display'
    '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker_ReadyToReboot'
    '\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Start'
    '\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Idle Start'
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistant'
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantAllUsersRun'
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantCalendarRun'
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantWakeupRun'

    # --- WindowsUpdate ---
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start'
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start With Network'
    '\Microsoft\Windows\WindowsUpdate\Automatic App Update'
    '\Microsoft\Windows\WindowsUpdate\sih'
    '\Microsoft\Windows\WindowsUpdate\sihboot'
    '\Microsoft\Windows\WindowsUpdate\sihpostreboot'
    '\Microsoft\Windows\WindowsUpdate\AUScheduledInstall'
    '\Microsoft\Windows\WindowsUpdate\AUSessionConnect'
    '\Microsoft\Windows\WindowsUpdate\RUXIM\PLUGScheduler'
    '\Microsoft\Windows\WaaS\WaaSMedicAgent'
    '\Microsoft\Windows\WaaSMedic\PerformRemediation'

    # --- Windows Error Reporting ---
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'

    # --- Edge / third-party updaters ---
    '\MicrosoftEdgeUpdateTaskMachineCore'
    '\MicrosoftEdgeUpdateTaskMachineUA'
    'DUpdaterTask'
    'ModifyLinkUpdate'
    'StartAUEP'
    'StartCN'
    'StartCNBM'
    'StartDVR'

    # --- Memory Diagnostic ---
    '\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents'
    '\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic'
    '\Microsoft\Windows\MemoryDiagnostic\AutomaticOfflineMemoryDiagnostic'

    # --- Device Information ---
    '\Microsoft\Windows\Device Information\Device'
    '\Microsoft\Windows\Device Information\Device User'
    '\Microsoft\Windows\Device Setup\Metadata Refresh'

    # --- Enterprise / MDM ---
    '\Microsoft\Windows\EnterpriseMgmt\MDMMaintenenceTask'
    '\Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh'
    '\Microsoft\Windows\BitLocker\BitLocker MDM policy Refresh'
    '\Microsoft\Windows\BitLocker\BitLocker Encrypt All Drives'

    # --- License Manager ---
    '\Microsoft\Windows\License Manager\TempSignedLicenseExchange'

    # --- Connectivity / Cellular / eSIM ---
    '\Microsoft\Windows\Management\Connectivity\ESIMPM'
    '\Microsoft\Windows\Management\Provisioning\Cellular'

    # --- Maintenance & WinSAT ---
    '\Microsoft\Windows\Maintenance\WinSAT'
    '\Microsoft\Windows\Servicing\StartComponentCleanup'
    '\Microsoft\Windows\Setup\SetupCleanupTask'
    '\Microsoft\Windows\Setup\SnapshotCleanupTask'
    '\Microsoft\Windows\Registry\RegIdleBackup'
    '\Microsoft\Windows\StateRepository\MaintenanceTasks'
    '\Microsoft\Windows\BrokerInfrastructure\BgTaskRegistrationMaintenanceTask'
    '\Microsoft\Windows\ApplicationData\CleanupTemporaryState'
    '\Microsoft\Windows\ApplicationData\appuriverifierdaily'
    '\Microsoft\Windows\ApplicationData\appuriverifierinstall'
    '\Microsoft\Windows\ApplicationData\DsSvcCleanup'

    # --- TaskScheduler maintenance (from NETWORK-EXTRAS) ---
    '\Microsoft\Windows\TaskScheduler\MaintenanceConfigurator'
    '\Microsoft\Windows\TaskScheduler\IdleMaintenance'
    '\Microsoft\Windows\TaskScheduler\RegularMaintenance'

    # --- MUI & Language ---
    '\Microsoft\Windows\MUI\LPRemove'

    # --- Network diagnostics ---
    '\Microsoft\Windows\Network Connectivity Status Indicator\NcsiIdentifyUserProxies'
    '\Microsoft\Windows\NetworkExperimentation'
    '\Microsoft\Windows\NlaSvc\WiFiTask'
    '\Microsoft\Windows\WCM\WiFiTask'
    '\Microsoft\Windows\WlanSvc\CDSSync'
    '\Microsoft\Windows\WlanSvc\MoProfileManagement'
    '\Microsoft\Windows\WwanSvc\NotificationTask'
    '\Microsoft\Windows\WwanSvc\OobeDiscovery'
    '\Microsoft\Windows\Ras\MobilityManager'

    # --- Printing ---
    '\Microsoft\Windows\Printing\EduPrintProv'
    '\Microsoft\Windows\Printing\PrinterCleanupTask'
    '\Microsoft\Windows\Printing\PrintJobCleanupTask'

    # --- PushToInstall ---
    '\Microsoft\Windows\PushToInstall\Registration'
    '\Microsoft\Windows\PushToInstall\LoginCheck'

    # --- Recovery & RemoteAssistance ---
    '\Microsoft\Windows\RecoveryEnvironment\VerifyWinRE'
    '\Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask'

    # --- Retail Demo ---
    '\Microsoft\Windows\RetailDemo\CleanupOfflineContent'
    '\Microsoft\Windows\RetailDemo\Cleanup'

    # --- Shell & Themes ---
    '\Microsoft\Windows\Shell\FamilySafetyMonitor'
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'
    '\Microsoft\Windows\Shell\ThemesSyncedImageDownload'
    '\Microsoft\Windows\Shell\sSyncedImageDownload'

    # --- Speech ---
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask'

    # --- Sustainability & Power ---
    '\Microsoft\Windows\Sustainability\PowerGridForecastTask'
    '\Microsoft\Windows\Sustainability\SustainabilityTelemetry'
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem'

    # --- Time Synchronization (NTP handled by TIME_NTP.PS1) ---
    '\Microsoft\Windows\Time Synchronization\ForceSynchronizeTime'
    '\Microsoft\Windows\Time Synchronization\SynchronizeTime'
    '\Microsoft\Windows\Time Zone\SynchronizeTimeZone'

    # --- TPM ---
    '\Microsoft\Windows\TPM\Tpm-HASCertRetr'
    '\Microsoft\Windows\TPM\Tpm-Maintenance'

    # --- UPnP ---
    '\Microsoft\Windows\UPnP\UPnPHostConfig'

    # --- User Profile ---
    '\Microsoft\Windows\User Profile Service\HiveUploadTask'

    # --- WDI ---
    '\Microsoft\Windows\WDI\ResolutionHost'

    # --- Windows Filtering Platform ---
    '\Microsoft\Windows\Windows Filtering Platform\BfeOnServiceStartTypeChange'

    # --- Work Folders ---
    '\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization'
    '\Microsoft\Windows\Work Folders\Work Folders Maintenance Work'

    # --- Workplace Join ---
    '\Microsoft\Windows\Workplace Join\Automatic-Device-Join'

    # --- Input sync (pen/touch/mouse) ---
    '\Microsoft\Windows\Input\LocalUserSyncDataAvailable'
    '\Microsoft\Windows\Input\InputSettingsRestoreDataAvailable'
    '\Microsoft\Windows\Input\syncpensettings'
    '\Microsoft\Windows\Input\TouchPadSyncDataAvailable'
    '\Microsoft\Windows\Input\MouseSyncDataAvailable'
    '\Microsoft\Windows\Input\PenSyncDataAvailable'

    # --- EDP ---
    '\Microsoft\Windows\EDP\StorageCardEncryption Task'

    # --- Location ---
    '\Microsoft\Windows\Location\Notifications'
    '\Microsoft\Windows\Location\WindowsActionDialog'

    # --- Maps ---
    '\Microsoft\Windows\Maps\MapsToastTask'
    '\Microsoft\Windows\Maps\MapsUpdateTask'

    # --- Data Integrity Scan ---
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan for Crash Recovery'
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan'
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Check And Scan'

    # --- Settings Sync ---
    '\Microsoft\Windows\SettingSync\BackgroundUploadTask'
    '\Microsoft\Windows\SettingSync\NetworkStateChangeTask'

    # --- Wininet cache ---
    '\Microsoft\Windows\Wininet\CacheTask'

    # --- AD RMS ---
    '\Microsoft\Windows\Active Directory Rights Management Services Client\AD RMS Rights Policy Template Management (Manual)'

    # --- Kernel ---
    '\Microsoft\Windows\Kernel\La57Cleanup'

    # --- USB ---
    '\Microsoft\Windows\USB\Usb-Notifications'

    # --- XblGameSave ---
    '\Microsoft\XblGameSave\XblGameSaveTask'
    '\Microsoft\XblGameSave\XblGameSaveTaskLogon'

    # --- Task Manager ---
    '\Microsoft\Windows\Task Manager\Interactive'

    # --- WindowsAI (Recall/Copilot) ---

    # ============================================================
    # NOTE: MSA login chain tasks are INTENTIONALLY KEPT ENABLED:
    #   \Microsoft\Windows\Management\Provisioning\Logon
    #   \Microsoft\Windows\CloudExperienceHost\CreateObjectTask
    #   \Microsoft\Windows\AccountHealth\RecoverabilityToastTask
    # Disabling them breaks MSA login for users without local password.
    # ============================================================

    # --- AppxDeploymentClient UCPD ---
    # (handled via Get-ScheduledTask below M-bM-^@M-^T has spaces in path)
)

# ----------------------------------------------------------------
# Disable named tasks (query-before-disable)
# ----------------------------------------------------------------
$disabled = 0
$notFound = 0
$alreadyDisabled = 0
$failed = 0

Write-Log '+' "Processing $($tasksToDisable.Count) scheduled tasks..."

foreach ($task in $tasksToDisable) {
    try {
        $null = (& schtasks /Query /TN "$task" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $notFound++
            continue
        }
        $null = (& schtasks /Change /TN "$task" /Disable 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $disabled++
        } else {
            # Check if already disabled
            $state = (& schtasks /Query /TN "$task" /FO LIST 2>$null | Select-String 'Status:\s*Disabled')
            if ($state) {
                $alreadyDisabled++
            } else {
                $failed++
                Write-Log '-' "Failed to disable: $task"
            }
        }
    } catch {
        $failed++
        Write-Log '-' "Exception processing: $task"
    }
}

# ----------------------------------------------------------------
# Special: tasks with spaces/special chars handled via PS cmdlet
# ----------------------------------------------------------------
$psCmdletTasks = @(
    @{Path = '\Microsoft\Windows\UpdateOrchestrator\';   Name = 'USO_UxBroker'}
    @{Path = '\Microsoft\Windows\AppxDeploymentClient\'; Name = 'UCPD velocity'}
)

foreach ($t in $psCmdletTasks) {
    try {
        $st = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($st) {
            $null = $st | Disable-ScheduledTask -ErrorAction SilentlyContinue
            if ($?) { $disabled++ } else { $failed++ }
        } else {
            $notFound++
        }
    } catch {
        $notFound++
    }
}

# ----------------------------------------------------------------
# Unregister DeviceDirectoryClient (not just disable, remove it)
# ----------------------------------------------------------------
try {
    $ddc = Get-ScheduledTask -TaskPath '\Microsoft\Windows\' -TaskName 'DeviceDirectoryClient' -ErrorAction SilentlyContinue
    if ($ddc) {
        $null = $ddc | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {}

# ----------------------------------------------------------------
# Wildcard: all Office tasks
# ----------------------------------------------------------------
Write-Log '+' 'Disabling Office scheduled tasks...'
try {
    $officeTasks = Get-ScheduledTask -TaskPath '\Microsoft\Office\*' -ErrorAction SilentlyContinue
    if ($officeTasks) {
        $officeCount = @($officeTasks).Count
        $officeTasks | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        Write-Log '+' "Office tasks disabled ($officeCount)"
    } else {
        Write-Log '-' 'No Office tasks found'
    }
} catch {
    Write-Log '-' "Could not disable Office tasks: $_"
}

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
Write-Host ''
Write-Log '+' 'Scheduled tasks processing complete:'
Write-Host "    Disabled:          $disabled"
Write-Host "    Already disabled:  $alreadyDisabled"
Write-Host "    Not found:         $notFound"
Write-Host "    Failed:            $failed"

exit 0
