@echo off
"%windir%\LexBoosTOS\Utilities\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0privileged-registry-tweaks.ps1" >nul 2>&1
exit /b 0
