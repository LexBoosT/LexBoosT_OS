@echo off
:: ReconcileFeatures is also disabled in packages/tasks.yml (idempotent duplicate)
schtasks /Change /Disable /TN "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures" >NUL 2>&1
:: One-shot kill only — no permanent logon task (the CrossDeviceResume packages
:: themselves are removed by APPX-REMOVER, so a permanent kill task is invasive dead weight)
taskkill /im CrossDeviceResume.exe /f >NUL 2>&1
exit /b 0