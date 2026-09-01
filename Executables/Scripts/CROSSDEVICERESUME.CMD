@echo off

:: 1. Deploy the kill script + exe to the persistent LexBoosT location.
::    (elevation is inherited from the playbook's runas: currentUserElevated)
if not exist "C:\ProgramData\LexBoosTOS\Scripts" (
    mkdir "C:\ProgramData\LexBoosTOS\Scripts" >NUL 2>&1
)
copy /y "%~dp0CROSSDEVICERESUME-KILL.PS1" "C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.PS1" >NUL 2>&1
if exist "%~dp0CROSSDEVICERESUME-KILL.exe" (
    copy /y "%~dp0CROSSDEVICERESUME-KILL.exe" "C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.exe" >NUL 2>&1
)

:: 2. Run the deployed script (kill + self-register the logon task).
::    Fallback to the in-place copy if the deployment target is missing.
if exist "C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.PS1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\LexBoosTOS\Scripts\CROSSDEVICERESUME-KILL.PS1" >NUL 2>&1
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CROSSDEVICERESUME-KILL.PS1" >NUL 2>&1
)

exit /b 0
