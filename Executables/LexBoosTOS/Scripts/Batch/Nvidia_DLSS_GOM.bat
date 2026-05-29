@echo off
setlocal

:: Define variables
set "CONFIG_URL=https://raw.githubusercontent.com/LexBoosT/LexBoosT-s-Tweaks/refs/heads/master/NVDLLSGLOM.txt"
set "ZIP_FILE=nvidiaDlssGlom.zip"
set "EXTRACT_DIR=%ProgramData%\Nvidia_DLSS_GOM"
set "EXE_FILE=nvidiaDlssGlom.exe"
set "TEMP_FILE=temp_url.txt"

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

if "%CHOICE%"=="1" goto DOWNLOAD
if "%CHOICE%"=="2" goto EXIT
echo Invalid choice, please try again.
timeout /t 2 /nobreak >nul
goto MENU

:DOWNLOAD
echo.
echo Reading download URL from configuration file...
powershell -Command "Invoke-WebRequest -Uri '%CONFIG_URL%' -OutFile '%TEMP_FILE%'"

if not %errorlevel% == 0 (
    echo Error reading configuration file
    pause
    goto MENU
)

:: Read the URL from the text file
set /p DOWNLOAD_URL=<%TEMP_FILE%

:: Clean up temporary file
del "%TEMP_FILE%"

if "%DOWNLOAD_URL%"=="" (
    echo Error: No URL found in configuration file
    pause
    goto MENU
)

echo Download URL found... Downloading...

echo Downloading archive using BITS...
powershell -Command "Start-BitsTransfer -Source '%DOWNLOAD_URL%' -Destination '%CD%\%ZIP_FILE%' -DisplayName 'Downloading Nvidia DLSS GOM' -Description 'Downloading archive...' -Priority High"

if not %errorlevel% == 0 (
    echo BITS transfer failed, using fallback method...
    powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%'"

    if not %errorlevel% == 0 (
        echo Error during download
        pause
        goto MENU
    )
)

echo Download completed successfully!

echo Creating extraction directory...
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

echo Extracting archive...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force"

if not %errorlevel% == 0 (
    echo Error during extraction
    pause
    goto MENU
)

echo Extraction completed successfully!

echo Deleting archive...
del "%ZIP_FILE%"

if not %errorlevel% == 0 (
    echo Error deleting ZIP file
    pause
    goto MENU
)

echo Cleanup completed!
goto EXIT

:EXIT
exit /b 0
