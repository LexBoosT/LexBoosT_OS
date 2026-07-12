@echo off
setlocal enabledelayedexpansion

schtasks /Change /Disable /TN "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures"
schtasks /create /sc OnLogon /delay 0000:03 /tn "\Microsoft\Windows\Shell\Kill CrossDeviceResume.exe" /tr "taskkill /im CrossDeviceResume.exe /f" /ru SYSTEM /f

endlocal
exit /b 0