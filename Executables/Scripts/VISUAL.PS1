$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Vérifier et créer la clé pour le mode "Custom" des effets visuels
$visualEffectsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $visualEffectsPath)) {
    New-Item -Path $visualEffectsPath -Force | Out-Null
}
Set-ItemProperty -Path $visualEffectsPath -Name "VisualFXSetting" -Value 3 -Type DWord

# Définir le masque binaire UserPreferencesMask pour activer les 6 options cochées (hors rectangle translucide)
# Masque calculé : 0x90,0x12,0x03,0x81 (inclut ListviewShadow, exclut SelectionTranslucent)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90, 0x12, 0x03, 0x81)) -Type Binary -Force

# Appliquer les paramètres spécifiques
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Value 0 -Type DWord

# Forcer l'activation du rectangle de sélection translucide (problème potentiel avec le masque)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SelectionTranslucent" -Value 1 -Type DWord -Force

# Désactiver le watermark de version
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "PaintDesktopVersion" -Value 0 -Type DWord

# Désactiver la transparence des fenêtres (acrylic, menus, barres de titre, UWP)
# 0 = transparence désactivée — gain de perf sur les GPU modestes + moins de bruit visuel
$transparencyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
if (-not (Test-Path $transparencyPath)) {
    New-Item -Path $transparencyPath -Force | Out-Null
}
Set-ItemProperty -Path $transparencyPath -Name "EnableTransparency" -Value 0 -Type DWord -Force
# Sentinel pour la build >= 22621 : ActiveTransparency désactive aussi l'effet de flou
Set-ItemProperty -Path $transparencyPath -Name "ActiveTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Log '+' "Window transparency disabled"

# Forcer l'application des paramètres système
RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters

# Vider le cache des paramètres visuels
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\Settings" -Force -ErrorAction SilentlyContinue
Write-Log '+' "LexBoosT Visual Performance Configuration Success"
# Exit cleanly
exit 0
