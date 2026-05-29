@echo off

set "psScriptPath=%windir%\LexBoosTOS\Scripts\PowerShell\FolderUser.ps1"

:: Vérifier si le script PowerShell existe
if not exist "%psScriptPath%" (
    echo Error: %psScriptPath% not found!
    exit /b 1
)

:: Lancer directement le script PowerShell
powershell.exe -ExecutionPolicy Bypass -File "%psScriptPath%"

if %errorlevel% neq 0 (
    echo Error: Execution of the PowerShell script has failed.
    exit /b 1
)

echo Success!