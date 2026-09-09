$ErrorActionPreference = "Continue"

function Test-IsIntelCPU {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        return $cpu.Name -match "Intel"
    }
    catch {
        Write-Log '-' "Failed to detect Intel CPU: $_"
        return $false
    }
}

function Test-IsAMD3DVCache {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Name -notmatch "AMD") { return $false }
        if ($cpu.Name -match "X3D") { return $true }
        $knownX3D = @('5800X3D','7800X3D','7900X3D','7950X3D','9800X3D','9900X3D','9950X3D')
        foreach ($model in $knownX3D) { if ($cpu.Name -match $model) { return $true } }
        return $false
    }
    catch { return $false }
}

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Applying YML system registry tweaks...'

# ================================================
# DPC KERNEL TWEAKS
# ================================================

Write-Log '+' 'Applying DPC kernel tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'IdealDpcRate' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'DpcQueueDepth' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MinimumDpcRate' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# SPLIT LARGE CACHES
# ================================================

Write-Log '+' 'Enabling split large caches...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'SplitLargeCaches' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# THREAD DPC
# ================================================

Write-Log '+' 'Enabling Thread DPC (restored from v5.1)...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'ThreadDpcEnable' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# KERNEL QUEUE / SCHEDULING
# ================================================

Write-Log '+' 'Applying kernel scheduling tweaks...'
if (Test-IsIntelCPU) {
    reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MaxDynamicTickDuration' /t REG_DWORD /d 10 /f 2>&1 | Out-Null
}
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MaximumSharedReadyQueueSize' /t REG_DWORD /d 128 /f 2>&1 | Out-Null
# ================================================
# CLOCK TIMER SETTINGS (KERNEL) - Performance
# ================================================
Write-Log '+' 'Applying clock timer kernel tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'KiClockTimerPerCpu' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'ClockTimerPerCpu' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'KiClockTimerHighLatency' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'ClockTimerHighLatency' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'KiClockTimerAlwaysOnPresent' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' /v 'ClockTimerAlwaysOnPresent' /t REG_DWORD /d 1 /f 2>&1 | Out-Null


# ================================================
# D3D11-D3D12 DIRECTX TWEAKS
# ================================================

Write-Log '+' 'Applying DirectX D3D11/D3D12 tweaks...'
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_ENABLE_RUNTIME_DRIVER_OPTIMIZATIONS' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_RESOURCE_ALIGNMENT' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D11_MULTITHREADED' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_MULTITHREADED' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D11_DEFERRED_CONTEXTS' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_DEFERRED_CONTEXTS' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D11_ALLOW_TILING' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D11_ENABLE_DYNAMIC_CODEGEN' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_ALLOW_TILING' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_CPU_PAGE_TABLE_ENABLED' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_HEAP_SERIALIZATION_ENABLED' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_MAP_HEAP_ALLOCATIONS' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectX' /v 'D3D12_RESIDENCY_MANAGEMENT_ENABLED' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# DXGKrnl (DIRECTX GRAPHICS KERNEL)
# ================================================

Write-Log '+' 'Applying DirectX Graphics Kernel tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'CreateGdiPrimaryOnSlaveGPU' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DriverSupportsCddDwmInterop' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkCddSyncDxAccess' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkCddSyncGPUAccess' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkCddWaitForVerticalBlankEvent' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkCreateSwapChain' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkFreeGpuVirtualAddress' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkOpenSwapChain' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkShareSwapChainObject' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkWaitForVerticalBlankEvent' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'DxgkWaitForVerticalBlankEvent2' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'SwapChainBackBuffer' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\DXGKrnl' /v 'TdrResetFromTimeoutAsync' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# GRAPHICS DRIVERS (GPU SCHEDULING & POWER)
# ================================================
Write-Log '+' 'Applying Graphics Drivers tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'PowerSavingModeEnabled' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'PanelSelfRefresh' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ForceOffScreenTimeout' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'MaximumAdapterCount' /t REG_DWORD /d 4 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ForceDirectFlip' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ForceSecondaryFlipSupport' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'EnableWDDM23Synchronization' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'WDDM2LockManagement' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'DiagnosticsBufferExpansionTime' /t REG_DWORD /d 300 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ExternalDiagnosticsBufferSize' /t REG_DWORD /d 65536 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'DpiMapIommuContiguous' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'ModeListCaching' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'EnableVirtualRefreshRateOnExternalMonitor' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'ShortLinkTrainingTimeout' /t REG_DWORD /d 100 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'LongLinkTrainingTimeout' /t REG_DWORD /d 500 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Power' /v 'DisableDevicePowerRequired' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' /v 'EnableFrameBufferCompression' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# DIRECT3D / DIRECTDRAW
# ================================================

Write-Log '+' 'Applying Direct3D tweaks...'
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'UseNonLocalVidMem' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'FullDebug' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'DisableDM' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'EnableMultimonDebugging' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'LoadDebugRuntime' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'FewVertices' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'DisableMMX' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D' /v 'UseMMXForRGB' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Direct3D' /v 'DisableVidMemVBs' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Direct3D' /v 'FlipNoVsync' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
if (Test-IsIntelCPU) {
    reg add 'HKCU\SOFTWARE\Microsoft\Direct3D' /v 'MMX Fast Path' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Write-Log '+' 'Intel CPU detected - MMX Fast Path enabled'
} else {
    Write-Log '+' 'AMD CPU detected - skipping MMX Fast Path'
}
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'ForceRgbRasterizer' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'EnumReference' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'EnumSeparateMMX' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'EnumRamp' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'EnumNullDevice' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'UseMMXForRGB' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Direct3D\Drivers' /v 'SoftwareOnly' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'DisableAGPSupport' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'UseNonLocalVidMem' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'DisableDDSCAPSInDDSD' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'EmulatePointSprites' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'EmulateStateBlocks' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\DirectDraw' /v 'EmulationOnly' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'ForceRgbRasterizer' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'EnumReference' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'EnumSeparateMMX' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'EnumRamp' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'EnumNullDevice' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'UseMMXForRGB' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Direct3D\Drivers' /v 'SoftwareOnly' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'DisableAGPSupport' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'UseNonLocalVidMem' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'DisableDDSCAPSInDDSD' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'EmulatePointSprites' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'EmulateStateBlocks' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\WOW6432Node\Microsoft\DirectDraw' /v 'EmulationOnly' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# KERNEL / SESSION MANAGER (existing)
# ================================================

# Timer kernel tweaks
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'TimerCheckFlags' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'SerializeTimerExpiration' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
if (-not (Test-IsAMD3DVCache)) {
    reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'EnablePerCpuClockTickScheduling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}

# Memory Management
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'DisablePageCombining' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverride' /t REG_DWORD /d 3 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverrideMask' /t REG_DWORD /d 3 /f 2>&1 | Out-Null

reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'GlobalTimerResolutionRequests' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# DisableDiagnosticTracing
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Diagnostics\Performance' /v 'DisableDiagnosticTracing' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# WINDOWS / RIT / DESKTOP HEAP
# ================================================

reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'RITdemonTimerPowerSaveElapse' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'RITdemonTimerPowerSaveCoalescing' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' /v 'DesktopHeapLogging' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# MULTIMEDIA / SYSTEM PROFILE
# ================================================

reg add 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' /v 'Win32PrioritySeparation' /t REG_DWORD /d 38 /f 2>&1 | Out-Null

# ================================================
# DIRECTX (existing)
# ================================================

reg add 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' /v 'DirectXUserGlobalSettings' /t REG_SZ /d '0' /f 2>&1 | Out-Null

# ================================================
# NETWORK / DMA / MISCELLANEOUS (existing)
# ================================================

reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' /v 'DisableBandwidthThrottling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# ================================================
# EXPLORER DESKTOP TWEAKS (existing)
# ================================================

reg add 'HKLM\SYSTEM\CurrentControlSet\Control' /v 'WaitToKillServiceTimeout' /t REG_SZ /d 2000 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v 'SystemUsesLightTheme' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v 'AppsUseLightTheme' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v 'EnabledBlurBehind' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' /f 2>&1 | Out-Null
reg delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' /f 2>&1 | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v 'TaskbarBadges' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v 'TaskbarFlashing' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

Write-Log '+' 'System tweaks applied'
exit 0
