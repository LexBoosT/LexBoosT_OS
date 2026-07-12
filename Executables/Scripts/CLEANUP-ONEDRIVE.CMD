@echo off
:: Kill all OneDrive-related processes (including new sync service and app)
taskkill /f /im OneDrive.exe >nul 2>&1
taskkill /f /im OneDrive.App.exe >nul 2>&1
taskkill /f /im OneDrive.Sync.Service.exe >nul 2>&1
taskkill /f /im FileCoAuth.exe >nul 2>&1
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul

:: Take ownership + delete only if the folder still exists
if exist "%LocalAppdata%\Microsoft\OneDrive\" (
    "%windir%\LexBoosTOS\Utilities\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged cmd /c "takeown /f \"%LocalAppdata%\Microsoft\OneDrive\" /r /d y >nul 2>&1 & icacls \"%LocalAppdata%\Microsoft\OneDrive\" /grant administrators:F /t /c /q >nul 2>&1 & rmdir /s /q \"%LocalAppdata%\Microsoft\OneDrive\" >nul 2>&1" >nul 2>&1
)

:: Explorer will restart automatically — no explicit start to avoid handle inheritance
exit /b 0
