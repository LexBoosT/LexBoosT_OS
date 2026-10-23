#Requires -RunAsAdministrator

# Disable Windows telemetry scheduled tasks
$tasks = @(
    "Microsoft\Windows\Application Experience\Compatibility Appraiser",
    "Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "Microsoft\Windows\Autochk\Proxy",
    "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "Microsoft\Windows\Feedback\Siuf\DmClient",
    "Microsoft\Windows\Maps\MapsUpdateTask",
    "Microsoft\Windows\Maps\MapsToastTask"
)

foreach ($task in $tasks) {
    try {
        Disable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
        Write-Host "Disabled: $task"
    }
    catch {
        Write-Host "Failed to disable: $task"
    }
}
