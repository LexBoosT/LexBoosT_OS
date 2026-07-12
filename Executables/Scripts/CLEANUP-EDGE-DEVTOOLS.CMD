@echo off
"%windir%\LexBoosTOS\Utilities\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged cmd /c "takeown /f \"%windir%\SystemApps\Microsoft.MicrosoftEdgeDevToolsClient_8wekyb3d8bbwe\" /r /d y >nul 2>&1 & icacls \"%windir%\SystemApps\Microsoft.MicrosoftEdgeDevToolsClient_8wekyb3d8bbwe\" /grant administrators:F /t /c >nul 2>&1 & rmdir /s /q \"%windir%\SystemApps\Microsoft.MicrosoftEdgeDevToolsClient_8wekyb3d8bbwe\" >nul 2>&1" >nul 2>&1
exit /b 0
