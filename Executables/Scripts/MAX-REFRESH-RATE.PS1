function Test-Laptop {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $isLaptop = $false
    $laptopChassisTypes = @(8, 9, 10, 11, 12, 13, 14, 18, 21, 30, 31, 32)

    try {
        $chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes
        if ($laptopChassisTypes | Where-Object { $chassisTypes -contains $_ }) {
            $isLaptop = $true
        }
    }
    catch { }

    if (-not $isLaptop) {
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem.PCSystemType -eq 2 -or $computerSystem.PCSystemTypeEx -in @(2, 8)) {
                $isLaptop = $true
            }
        }
        catch { }
    }

    if (-not $isLaptop) {
        try {
            if (Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop) {
                $isLaptop = $true
            }
        }
        catch { }
    }

    return $isLaptop
}

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

$typesLoaded = $false
try { $null = [DisplayNative]; $null = [DEVMODE]; $typesLoaded = $true } catch {}

if (-not $typesLoaded) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DisplayNative
{
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwFlags, IntPtr lParam);

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DM_PELSWIDTH         = 0x00080000;
    public const int DM_PELSHEIGHT        = 0x00100000;
    public const int DM_BITSPERPEL        = 0x00040000;
    public const int DM_DISPLAYFREQUENCY  = 0x00400000;
    public const int CDS_UPDATEREGISTRY    = 0x00000001;
    public const int CDS_TEST              = 0x00000002;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
public struct DEVMODE
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string dmDeviceName;
    public short  dmSpecVersion;
    public short  dmDriverVersion;
    public short  dmSize;
    public short  dmDriverExtra;
    public int    dmFields;
    public int    dmPositionX;
    public int    dmPositionY;
    public int    dmDisplayOrientation;
    public int    dmDisplayFixedOutput;
    public short  dmColor;
    public short  dmDuplex;
    public short  dmYResolution;
    public short  dmTTOption;
    public short  dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string dmFormName;
    public short  dmLogPixels;
    public int    dmBitsPerPel;
    public int    dmPelsWidth;
    public int    dmPelsHeight;
    public int    dmDisplayFlags;
    public int    dmDisplayFrequency;
    public int    dmICMMethod;
    public int    dmICMIntent;
    public int    dmMediaType;
    public int    dmDitherType;
    public int    dmReserved1;
    public int    dmReserved2;
    public int    dmPanningWidth;
    public int    dmPanningHeight;
}
"@ -ErrorAction Stop
    }
    catch {
        Write-Log '-' "Failed to compile native types: $($_.Exception.Message)"
        exit 1
    }
}

# Skip on laptops: forcing max refresh via CDS_UPDATEREGISTRY can hide the
# refresh-rate dropdown in Settings on hybrid-GPU / panel-edid laptop setups.
if (Test-Laptop) {
    Write-Log '!' "Laptop detected: skipping max refresh-rate enforcement."
    Write-Log '!' "Set your preferred refresh rate manually in Settings or GPU driver panel."
    exit 0
}

Write-Log '+' "Scanning all displays for maximum refresh rate..."

$DM_ALL = [DisplayNative]::DM_PELSWIDTH -bor [DisplayNative]::DM_PELSHEIGHT -bor [DisplayNative]::DM_BITSPERPEL -bor [DisplayNative]::DM_DISPLAYFREQUENCY

$totalChanged = 0
$activeCount = 0

for ($displayIdx = 1; $displayIdx -le 10; $displayIdx++) {
    $deviceName = "\\.\DISPLAY$displayIdx"

    # Check if this display exists by reading current settings
    $currentMode = New-Object DEVMODE
    $currentMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($currentMode)
    $result = [DisplayNative]::EnumDisplaySettings($deviceName, [DisplayNative]::ENUM_CURRENT_SETTINGS, [ref]$currentMode)
    if ($result -eq 0) { continue }

    $activeCount++
    $curW    = $currentMode.dmPelsWidth
    $curH    = $currentMode.dmPelsHeight
    $curBpp  = $currentMode.dmBitsPerPel
    $curFreq = $currentMode.dmDisplayFrequency
    Write-Log '+' "Display #${displayIdx}: ${curW}x${curH} @ ${curFreq}Hz (${curBpp}-bit)"

    # Enumerate all modes, find max refresh at current resolution
    $maxFreq = 0
    $bestMode = $null
    $j = 0
    while ($true) {
        $mode = New-Object DEVMODE
        $mode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mode)
        if ([DisplayNative]::EnumDisplaySettings($deviceName, $j, [ref]$mode) -eq 0) { break }
        if ($mode.dmPelsWidth -eq $curW -and $mode.dmPelsHeight -eq $curH) {
            if ($mode.dmDisplayFrequency -gt $maxFreq) {
                $maxFreq = $mode.dmDisplayFrequency
                $bestMode = $mode
            }
        }
        $j++
    }

    if ($null -eq $bestMode -or $maxFreq -le $curFreq) {
        Write-Log '+' "  => Already at maximum (${curFreq}Hz)."
        continue
    }

    Write-Log '+' "  => Max available: ${maxFreq}Hz (from $j modes)"

    # Build desired mode
    $bestMode.dmPelsWidth        = $curW
    $bestMode.dmPelsHeight       = $curH
    $bestMode.dmBitsPerPel       = $curBpp
    $bestMode.dmDisplayFrequency = $maxFreq
    $bestMode.dmFields = $DM_ALL

    # Test
    $testResult = [DisplayNative]::ChangeDisplaySettingsEx($deviceName, [ref]$bestMode, [IntPtr]::Zero, [DisplayNative]::CDS_TEST, [IntPtr]::Zero)
    if ($testResult -ne [DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        Write-Log '-' "  => Test failed (result: $testResult)."
        continue
    }

    # Apply
    $applyResult = [DisplayNative]::ChangeDisplaySettingsEx($deviceName, [ref]$bestMode, [IntPtr]::Zero, [DisplayNative]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)
    if ($applyResult -eq [DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        Write-Log '+' "  => SUCCESS: Set to ${maxFreq}Hz."
        $totalChanged++
    } else {
        Write-Log '-' "  => Apply failed (result: $applyResult)."
    }
}

if ($activeCount -eq 0) {
    Write-Log '-' "No active displays found."
    exit 1
}

Write-Log '+' "Done. $activeCount display(s) scanned, $totalChanged updated."
exit 0
