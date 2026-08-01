$windir = [Environment]::GetFolderPath('Windows')

function Stop-ThemeProcesses {
    Get-Process 'SystemSettings', 'control' -EA 0 | Stop-Process -Force -EA 0
}

function Set-ThemeViaRegistry {
    param([string]$Path)

    # 1. Theme registry path
    $regThemes = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes"
    Set-ItemProperty -Path $regThemes -Name "CurrentTheme" -Value $Path -Type String -Force
    Set-ItemProperty -Path $regThemes -Name "ThemeMRU" -Value "$Path;$windir\Resources\Themes\dark.theme;" -Type String -Force

    # 2. Wallpaper
    $wallpaper = $null
    try {
        $themeContent = Get-Content $Path -Raw -Encoding UTF8
        if ($themeContent -match '(?m)^Wallpaper=(.+)$') {
            $wp = $Matches[1].Trim()
            if (Test-Path $wp) { $wallpaper = $wp }
        }
    } catch {}

    if ($wallpaper) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ThemeAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
        [ThemeAPI]::SystemParametersInfo(0x0014, 0, $wallpaper, 0x01 -bor 0x02) | Out-Null
    }

    # 3. Dark/Light mode
    try {
        if ($themeContent -match '(?m)^SystemMode=(.+)$') {
            $sysMode = $Matches[1].Trim()
            $appMode = if ($themeContent -match '(?m)^AppMode=(.+)$') { $Matches[1].Trim() } else { $sysMode }
            $regPers = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            if (-not (Test-Path $regPers)) { New-Item -Path $regPers -Force | Out-Null }
            Set-ItemProperty -Path $regPers -Name "SystemUsesLightTheme" -Value $(if ($sysMode -eq 'Light'){1}else{0}) -Type DWord -Force
            Set-ItemProperty -Path $regPers -Name "AppsUseLightTheme" -Value $(if ($appMode -eq 'Light'){1}else{0}) -Type DWord -Force
        }
    } catch {}

    # 4. Accent color
    try {
        if ($themeContent -match '(?m)^ColorizationColor=0x([0-9A-Fa-f]+)$') {
            $c = [Convert]::ToInt32($Matches[1], 16)
            $regDWM = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
            Set-ItemProperty -Path $regDWM -Name "ColorizationColor" -Value $c -Type DWord -Force
            Set-ItemProperty -Path $regDWM -Name "AccentColor" -Value $c -Type DWord -Force
            Set-ItemProperty -Path $regDWM -Name "ColorizationAutoColor" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $regDWM -Name "AccentColorInactive" -Value $c -Type DWord -Force
            Set-ItemProperty -Path $regDWM -Name "ColorPrevalence" -Value 1 -Type DWord -Force
        }
    } catch {}

    # 5. Lock screen wallpaper
    try {
        if ($themeContent -match '(?m)^\[LockScreen\][\s\S]*?Wallpaper=(.+)$') {
            $lockscreen = $Matches[1].Trim()
            if (Test-Path $lockscreen) {
                Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpaper" -Name "LockScreenImage" -Value $lockscreen -Type String -Force
                Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpaper" -Name "LockScreenImagePath" -Value $lockscreen -Type String -Force
            }
        }
    } catch {}

    # 6. Cursors
    try {
        $cursorKeys = @('AppStarting','Arrow','Crosshair','Hand','Help','IBeam','No','NWPen','SizeAll','SizeNESW','SizeNS','SizeNWSE','SizeWE','UpArrow','Wait')
        $regCursors = "HKCU:\Control Panel\Cursors"
        $changed = $false
        foreach ($k in $cursorKeys) {
            if ($themeContent -match "(?m)^$k=(.+)$") {
                $v = $Matches[1].Trim()
                if ($v) { Set-ItemProperty -Path $regCursors -Name $k -Value $v -Type String -Force; $changed = $true }
            }
        }
        if ($changed) { Set-ItemProperty -Path $regCursors -Name "Scheme Source" -Value 2 -Type DWord -Force }
    } catch {}
}

function Set-Theme {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (!((Get-Item $Path -EA 0).Extension -eq '.theme')) {
        throw "'$Path' is not a valid path to a theme file."
    }

    Write-Host "[+] Applying theme via registry..."
    Set-ThemeViaRegistry -Path $Path

    # Broadcast WM_SETTINGCHANGE
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class UISettings {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
'@
        $null = [UISettings]::SendMessageTimeout(0xFFFF, 0x001A, [IntPtr]::Zero, "Themes", 2, 5000, [IntPtr]::Zero)
    } catch {}

    # Also broadcast for desktop icons/wallpaper refresh
    try {
        $null = [UISettings]::SendMessageTimeout(0xFFFF, 0x001A, [IntPtr]::Zero, "WindowMetrics", 2, 5000, [IntPtr]::Zero)
        $null = [UISettings]::SendMessageTimeout(0xFFFF, 0x001A, [IntPtr]::Zero, "Desktop", 2, 5000, [IntPtr]::Zero)
    } catch {}

    # Force apply cursors via SystemParametersInfo
    try {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CurAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, IntPtr lpvParam, int fuWinIni);
}
'@
        [CurAPI]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 0x01 -bor 0x02) | Out-Null
    } catch {}

    # Stop Settings
    Stop-ThemeProcesses
    Start-Sleep 1

    # === Restart Explorer proprement pour appliquer le thème ===
    Write-Host "[+] Redémarrage de l'Explorateur Windows pour appliquer le thème..."
    
    try {
        # Utiliser SHGetKnownFolderPath + SHRestart API officielle
        # (plus propre que Kill() et Windows redémarre Explorer immédiatement)
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ShellRefresh {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
    
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    public static void RefreshDesktop() {
        // SHCNE_ASSOCCHANGED — force le rechargement complet
        SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
'@

        # 1. SHChangeNotify pour rafraîchir le bureau
        [ShellRefresh]::RefreshDesktop()
        Start-Sleep 1

        # 2. Redémarrer Explorer rapidement
        $explorer = Get-Process explorer -ErrorAction SilentlyContinue
        if ($explorer) {
            $explorer | Stop-Process -Force
            # Attendre le redémarrage automatique (Windows le relance en ~1-2s)
            $retries = 0
            while ($retries -lt 15) {
                if (Get-Process explorer -ErrorAction SilentlyContinue) {
                    Start-Sleep 1  # Laisser le temps d'initialiser
                    break
                }
                Start-Sleep 0.2
                $retries++
            }
        }
    } catch {
        Write-Warning "Shell refresh failed: $_"
    }

    # Vérification finale : lancer le fichier .theme pour que l'utilisateur voie
    try {
        Stop-ThemeProcesses
        Start-Process $Path
        Start-Sleep 2
    } catch {}

    Stop-ThemeProcesses
    Write-Host "[+] Theme applied successfully!"
}

function Set-ThemeMRU {
    if ([System.Environment]::OSVersion.Version.Build -ge 22000) {
        Stop-ThemeProcesses
        $themePath = "$windir\Resources\Themes\LexBoosT-v3.0-dark.theme"
        $mruValue = "$themePath;$windir\Resources\Themes\dark.theme;"
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" -Name "ThemeMRU" -Value $mruValue -Type String -Force
    }
}

# Credit: https://superuser.com/a/1343640
function Set-LockscreenImage {
    param (
        [ValidateNotNullOrEmpty()]
        [string]$Path = "$([Environment]::GetFolderPath('Windows'))\Web\Wallpaper\LexBoosTOS\v3\lockscreen.jpg"
    )

    if (!(Test-Path $Path)) {
        throw "Path ('$Path') for lockscreen not found."
    }
    $newImagePath = [System.IO.Path]::GetTempPath() + (New-Guid).Guid + [System.IO.Path]::GetExtension($Path)
    Copy-Item $Path $newImagePath

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null

    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? {
            $_.Name -eq 'AsTask' -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
    Function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }
    Function AwaitAction($WinRtAction) {
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and !$_.IsGenericMethod })[0]
        $netTask = $asTask.Invoke($null, @($WinRtAction))
        $netTask.Wait(-1) | Out-Null
    }

    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    $image = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($newImagePath)) ([Windows.Storage.StorageFile])

    AwaitAction ([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($image))

    Remove-Item $newImagePath
}

Export-ModuleMember -Function Set-Theme, Set-ThemeMRU, Set-LockscreenImage
