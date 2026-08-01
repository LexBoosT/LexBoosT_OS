@echo off
setlocal

:: ============================================
:: Nvidia DLSS Global Override Mode — Installer
:: Usage:
::   Nvidia_DLSS_GOM.bat          → auto-download (silent, pour GPUTweaks)
::   Nvidia_DLSS_GOM.bat /MENU    → interactive menu (pour usage manuel)
::   Nvidia_DLSS_GOM.bat /SILENT  → auto-download (explicit)
:: ============================================

:: === Detect mode ===
set "AUTO_MODE=1"
set "SHOW_MENU=0"
if /i "%~1"=="/MENU"   set "AUTO_MODE=0" & set "SHOW_MENU=1"
if /i "%~1"=="/SILENT"  set "AUTO_MODE=1"
if /i "%~1"=="--auto"   set "AUTO_MODE=1"

:: === Persist mode flag across elevation via temp marker ===
if %AUTO_MODE% equ 1 (
    copy nul "%TEMP%\__dlss_auto.flag" >nul 2>&1
)

:: === Élévation si pas admin ===
:: Note: net session dépend du service Server (LanmanServer) qui peut être désactivé.
:: On utilise whoami /groups avec le SID d'intégrité admin (S-1-16-12288).
whoami /groups | find "S-1-16-12288" >nul 2>&1
if %errorLevel% neq 0 (
    :: Vérifier qu'on n'est pas déjà en train de s'être élevé (anti-boucle)
    if exist "%TEMP%\__dlss_elevating.flag" (
        echo [DLSS] ERROR: Elevation failed or UAC denied.
        echo [DLSS] Please run GPUTweaks as Administrator manually.
        pause
        exit /b 1
    )
    copy nul "%TEMP%\__dlss_elevating.flag" >nul 2>&1
    PowerShell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs -Wait"
    del "%TEMP%\__dlss_elevating.flag" 2>nul
    exit /b %errorLevel%
)

:: === Restore mode flag after elevation ===
if exist "%TEMP%\__dlss_auto.flag" (
    set "AUTO_MODE=1"
    set "SHOW_MENU=0"
    del "%TEMP%\__dlss_auto.flag" 2>nul
)

setlocal

:: === Define variables ===
set "CONFIG_URL=https://raw.githubusercontent.com/LexBoosT/LexBoosT-s-Tweaks/refs/heads/master/NVDLLSGLOM.txt"
set "ZIP_FILE=%TEMP%\nvidiaDlssGlom.zip"
set "EXTRACT_DIR=%ProgramData%\Nvidia_DLSS_GOM"
set "EXE_FILE=nvidiaDlssGlom.exe"
set "TEMP_FILE=%TEMP%\nvdlss_url.txt"

:: === Interactive menu (only with /MENU) ===
if %SHOW_MENU% equ 1 (
    :MENU
    cls
    echo ============================================
    echo    Nvidia DLSS Global Override Mode
    echo ============================================
    echo.
    echo 1. Download and install the pack
    echo 2. Exit
    echo.
    echo ============================================
    set /p CHOICE="Enter your choice (1-2): "

    if "%CHOICE%"=="1" goto DOWNLOAD_INTERACTIVE
    if "%CHOICE%"=="2" goto EXIT
    echo Invalid choice, please try again.
    timeout /t 2 /nobreak >nul
    goto MENU

    :DOWNLOAD_INTERACTIVE
    echo.
    call :DOWNLOAD_SILENT
    if %errorLevel% neq 0 (
        pause
        goto MENU
    )
    goto EXIT
)

:: === Auto / default mode: silent download ===
if %AUTO_MODE% equ 1 (
    call :DOWNLOAD_SILENT
    exit /b %errorLevel%
)

:: ============================================
:: Silent download routine
:: ============================================
:DOWNLOAD_SILENT
echo [DLSS] Reading download URL from GitHub...
powershell -Command "Invoke-WebRequest -Uri '%CONFIG_URL%' -OutFile '%TEMP_FILE%' -UseBasicParsing" 2>nul
if not %errorLevel% == 0 (
    echo [DLSS] ERROR: Cannot reach GitHub configuration file.
    echo [DLSS] Check your internet connection.
    exit /b 1
)

set /p DOWNLOAD_URL=<"%TEMP_FILE%"
del "%TEMP_FILE%" 2>nul

if "%DOWNLOAD_URL%"=="" (
    echo [DLSS] ERROR: Configuration file is empty or invalid.
    exit /b 1
)

echo [DLSS] Downloading nvidiaDlssGlom archive...

:: BITS transfer (preferred, shows progress in background)
powershell -Command "Start-BitsTransfer -Source '%DOWNLOAD_URL%' -Destination '%ZIP_FILE%' -Priority High" 2>nul
if not %errorLevel% == 0 (
    echo [DLSS] BITS unavailable, using Invoke-WebRequest...
    powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing" 2>nul
)
if not %errorLevel% == 0 (
    echo [DLSS] ERROR: Download failed.
    exit /b 1
)

echo [DLSS] Download completed!

if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

echo [DLSS] Extracting to %EXTRACT_DIR%...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force" 2>nul
if not %errorLevel% == 0 (
    echo [DLSS] ERROR: Extraction failed.
    del "%ZIP_FILE%" 2>nul
    exit /b 1
)

del "%ZIP_FILE%" 2>nul

:: Verify the exe exists
if exist "%EXTRACT_DIR%\%EXE_FILE%" (
    echo [DLSS] SUCCESS: %EXE_FILE% ready!
    echo [DLSS] Path: %EXTRACT_DIR%\%EXE_FILE%
    exit /b 0
) else (
    echo [DLSS] WARNING: %EXE_FILE% not found after extraction.
    echo [DLSS] The archive may have a different structure.
    exit /b 1
)

:EXIT
exit /b 0
