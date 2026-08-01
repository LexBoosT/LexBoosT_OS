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

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' 'Applying YML system registry tweaks...'

# ================================================
# DPC KERNEL TWEAKS
# ================================================

Write-Log '+' 'Applying DPC kernel tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'DpcWatchdogProfileOffset' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'DPCTimeout' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'IdealDpcRate' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'DpcQueueDepth' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MinimumDpcRate' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'DpcWatchdogPeriod' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# INTERRUPT STEERING
# ================================================

Write-Log '+' 'Disabling interrupt steering...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'InterruptSteeringDisabled' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

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
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MaxDynamicTickDuration' /t REG_DWORD /d 10 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'MaximumSharedReadyQueueSize' /t REG_DWORD /d 128 /f 2>&1 | Out-Null

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
# DXGI (DIRECTX GRAPHICS INFRASTRUCTURE)
# ================================================
# REMOVED 26.08: the DXGI_* presentation-forcing keys (DXGI_MAX_FRAME_LATENCY,
# DXGI_FORCE_FULLSCREEN_FLIP_MODE, DXGI_FORCE_FLIP_SEQUENTIAL, DXGI_DISABLE_DWM_THROTTLING,
# DXGI_PREEMPTION_MODE, ...) are undocumented tweak-pack values that the system does not
# read (frame latency is a per-process API: IDXGIDevice1::SetMaximumFrameLatency).
# A/B tested on LEXBOOST_OS-PC (RTX 5070 Ti): forcing the 1-frame queue + independent flip
# produced dxgkrnl ISR spikes (582 us) and nvlddmkm DPC spikes (1890 us). Removing them cut
# ISR peaks to 205 us and eliminated all ISR > 500 us.

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
# TdrDelay (GPU TIMEOUT)
# ================================================
Write-Log '+' 'Setting GPU TdrDelay...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'TdrDelay' /t REG_DWORD /d 20 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'TdrLevel' /t REG_DWORD /d 3 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'TdrDdiDelay' /t REG_DWORD /d 10 /f 2>&1 | Out-Null

# ================================================
# GRAPHICS DRIVERS (GPU SCHEDULING & POWER)
# ================================================
Write-Log '+' 'Applying Graphics Drivers tweaks...'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'PowerSavingModeEnabled' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'PanelSelfRefresh' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ForceOffScreenTimeout' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
# HwSchMode / HwSchTreatExperimentalAsStable REMOVED 26.08: SYSTEM_TWEAKS was rewriting
# HwSchMode=2 (HAGS ON) on every install, contradicting the "HAGS managed by GPUTweaks"
# decision and spiking dxgkrnl ISR (582 us at HAGS ON vs 205 us OFF, A/B tested).
# HAGS state is owned exclusively by GPUTweaks (tri-state DEFAULT/ON/OFF).
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'MaximumAdapterCount' /t REG_DWORD /d 4 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'WDDM2LockManagement' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'DiagnosticsBufferExpansionTime' /t REG_DWORD /d 300 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'ExternalDiagnosticsBufferSize' /t REG_DWORD /d 65536 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' /v 'DpiMapIommuContiguous' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
# MaxFrameLatency REMOVED 26.08: forced a 1-frame present queue (same family as the DXGI_*
# flip stack removed above); A/B: ISR peaks 484->205 us once removed.
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'ModeListCaching' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'EnableVirtualRefreshRateOnExternalMonitor' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'ShortLinkTrainingTimeout' /t REG_DWORD /d 100 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DMM' /v 'LongLinkTrainingTimeout' /t REG_DWORD /d 500 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Power' /v 'DisableDevicePowerRequired' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
# QueuedPresentLimit / ForceIndependentFlip REMOVED 26.08: forced independent flip with a
# near-empty present queue; when a frame misses VSync, nvlddmkm waits inside the DPC
# (1890 us peaks measured). Let the driver/DWM manage the flip queue (default).
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
# RESOURCE MANAGEMENT (CPU / I/O / FLAGS)
# ================================================

Write-Log '+' 'Applying Resource Management tweaks...'
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\HardCap0' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\HardCap0' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\Paused' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\Paused' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapFull' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapFull' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapFullAboveNormal' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapFullAboveNormal' /v 'PriorityClass' /t REG_DWORD /d 0x20 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapFullAboveNormal' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapLow' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapLow' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapLowBackgroundBegin' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapLowBackgroundBegin' /v 'PriorityClass' /t REG_DWORD /d 0x20 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\SoftCapLowBackgroundBegin' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\UnmanagedAboveNormal' /v 'CapPercentage' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\UnmanagedAboveNormal' /v 'PriorityClass' /t REG_DWORD /d 0x20 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\CPU\UnmanagedAboveNormal' /v 'SchedulingType' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\IO\NoCap' /v 'IOBandwidth' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System' /v 'IoEnableSessionZeroAccessCheck' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\BackgroundDefault' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\Frozen' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\FrozenDNCS' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\FrozenDNK' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\FrozenPPLE' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\Paused' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\PausedDNK' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\Pausing' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\PrelaunchForeground' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\Policies\Flags\ThrottleGPUInterference' /v 'IsLowPriority' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

# ================================================
# RESOURCE POLICY SETS (Priority overrides)
# ================================================

Write-Log '+' 'Applying Resource PolicySets (system-wide priority boost)...'

# Helper function to create PolicySet entries
function Set-PolicySet {
    param([string]$Name)
    $base = "Registry::HKLM\SYSTEM\ResourcePolicyStore\ResourceSets\PolicySets\$Name"
    if (-not (Test-Path $base)) { New-Item -Path $base -Force -ErrorAction SilentlyContinue | Out-Null }
    @('CPU','ExternalResources','Flags','IO','Memory') | ForEach-Object {
        $v = switch ($_) {
            'CPU'    { 'UnmanagedAboveNormal' }
            'ExternalResources' { 'ResourceIntensive' }
            'Flags'  { 'Foreground' }
            'IO'     { 'NoCap' }
            'Memory' { 'NoCap' }
        }
        New-ItemProperty -Path $base -Name $_ -Value $v -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-ItemProperty -Path $base -Name 'Importance' -Value 'Critical' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

$policySets = @(
    'ApplicationService','ApplicationServiceElastic','ApplicationServiceHighPriElastic','ApplicationServiceHighPriority',
    'ApplicationServiceRemote','AppToAppTarget','BackgroundAudioPlayer','BackgroundCachedFileUpdater',
    'BackgroundTaskCompletion','BackgroundTaskDebug','BackgroundTransfer','BackgroundTransferNetworkState',
    'Balloon','CalendarProviderAsChild','CallingEvent','CallingEventHighPriority','ChatMessageNotification',
    'ComponentTarget','ContinuousBackgroundExecution','CortanaSpeechBackground','CreateProcess',
    'DefaultModernBackgroundTask','DefaultPPLE','DefaultPPLE2','EmCreateProcess','EmCreateProcessNormalPriority',
    'EmptyHost','EmptyHostHighPriority','EmptyHostPPLE','FileProviderTarget','ForegroundAgent',
    'ForegroundCachedFileUpdater','ForegroundTaskCompletion','Frozen','GenericExtendedExecution',
    'GeofenceTask','HighPriorityBackgroundAgent','HighPriorityBackgroundDemoted','HighPriorityBackgroundTransfer',
    'IoTStartupTask','JumboForegroundAgent','LmaBackgroundTaskCompletion','LmaDefaultModernBackgroundTask',
    'LmaPrelaunchForeground','LmaUiDebugModeForeground','LmaUiFrozen','LmaUiFrozenDNCS','LmaUiFrozenDNK',
    'LmaUiFrozenHighPriority','LmaUiModernForeground','LmaUiModernForegroundLarge','LmaUiPaused','LmaUiPausedDNK',
    'LmaUiPausedHighPriority','LmaUiPausing','LongRunningBluetooth','LongRunningControlChannel','LongRunningSensor',
    'MediaProcessing','OemBackgroundAgent','OemTask','PendingDefaultPPLE','PiP','PreinstallTask',
    'PrelaunchForeground','PushTriggerTask','ResourceIntensive','ShareDataPackageHost','ShortRunningBluetooth',
    'TaskCompletionHighPriority','UiComposer','UiDebugModeForeground','UiForegroundDNK','UiFrozen','UiFrozenDNCS',
    'UiFrozenDNK','UiFrozenHighPriority','UiLockScreen','UiModernForeground','UiModernForegroundExtended',
    'UiModernForegroundLarge','UiOverlay','UiPaused','UiPausedDNK','UiPausedHighPriority','UiPausing',
    'UiPausingLowPriority','UiShellCustom1','UiShellCustom2','UiShellCustom3','UiShellCustom4',
    'VideoTranscoding','VoipActiveCallBackground','VoipActiveCallBackgroundPriority','VoipActiveCallForeground',
    'VoipForegroundWorker','VoipSuspendedBackground','VoipWorker','Vpn','WebAuthSignIn'
)

foreach ($ps in $policySets) {
    Set-PolicySet -Name $ps
}

# ================================================
# KERNEL / SESSION MANAGER (existing)
# ================================================

# Timer kernel tweaks
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'TimerCheckFlags' /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'SerializeTimerExpiration' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'EnablePerCpuClockTickScheduling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

# Memory Management
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'DisablePageCombining' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverride' /t REG_DWORD /d 3 /f 2>&1 | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v 'FeatureSettingsOverrideMask' /t REG_DWORD /d 3 /f 2>&1 | Out-Null


reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' /v 'GlobalTimerResolutionRequests' /t REG_DWORD /d 1 /f 2>&1 | Out-Null

reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v 'Win32CalloutWatchdogBugcheckEnabled' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

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

reg add 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' /v 'DirectXUserGlobalSettings' /t REG_SZ /d 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;' /f 2>&1 | Out-Null

# ================================================
# NETWORK / DMA / MISCELLANEOUS (existing)
# ================================================

reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' /v 'DisableBandwidthThrottling' /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection' /v 'DeviceEnumerationPolicy' /t REG_DWORD /d 0 /f 2>&1 | Out-Null

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
