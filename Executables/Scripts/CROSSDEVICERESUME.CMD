@echo off
<<<<<<< HEAD
:: ReconcileFeatures is also disabled in packages/tasks.yml (idempotent duplicate)
schtasks /Change /Disable /TN "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures" >NUL 2>&1
:: One-shot kill only — no permanent logon task (the CrossDeviceResume packages
:: themselves are removed by APPX-REMOVER, so a permanent kill task is invasive dead weight)
taskkill /im CrossDeviceResume.exe /f >NUL 2>&1
=======
setlocal enabledelayedexpansion

schtasks /Change /Disable /TN "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures"
schtasks /create /sc OnLogon /delay 0000:03 /tn "\Microsoft\Windows\Shell\Kill CrossDeviceResume.exe" /tr "taskkill /im CrossDeviceResume.exe /f" /ru SYSTEM /f

endlocal
>>>>>>> 0251bba90259c7b88ee0ce71c429e5c6fb1b4434
exit /b 0