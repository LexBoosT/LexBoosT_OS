@echo off
setlocal EnableExtensions
:: takeown-lang.bat - Language-aware takeown + icacls
:: Usage: takeown-lang.bat <path> <file|dir>
:: Detects system32 binary language and uses the correct /d letter.

set "TARGET=%~1"
set "MODE=%~2"

if "%TARGET%"=="" exit /b 1
if "%MODE%"=="" set "MODE=dir"

:: --- Detect system binary language (system32 locale, NOT display language) ---
set "SYS_LANG="
for /f "tokens=3 delims= " %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v Default 2^>nul') do set "SYS_LANG=%%a"

:: --- Map locale to takeown /d letter ---
:: Default: Y (English - also fallback for CJK/other locales
:: where system32 binaries are typically English)
set "D=Y"
if "%SYS_LANG%"=="040c" set "D=O"   :: French (Oui)
if "%SYS_LANG%"=="0407" set "D=J"   :: German (Ja)
if "%SYS_LANG%"=="040a" set "D=S"   :: Spanish (Si)
if "%SYS_LANG%"=="0410" set "D=S"   :: Italian (Si)
if "%SYS_LANG%"=="0816" set "D=S"   :: Portuguese BR (Sim)
if "%SYS_LANG%"=="0416" set "D=S"   :: Portuguese PT (Sim)
if "%SYS_LANG%"=="0413" set "D=J"   :: Dutch (Ja)
if "%SYS_LANG%"=="041D" set "D=J"   :: Swedish (Ja)
if "%SYS_LANG%"=="0414" set "D=J"   :: Norwegian (Ja)
if "%SYS_LANG%"=="0406" set "D=J"   :: Danish (Ja)
if "%SYS_LANG%"=="040B" set "D=K"   :: Finnish (Kylla)
if "%SYS_LANG%"=="0415" set "D=T"   :: Polish (Tak)
if "%SYS_LANG%"=="0419" set "D=E"   :: Turkish (Evet)
if "%SYS_LANG%"=="0422" set "D=I"   :: Hungarian (Igen)
if "%SYS_LANG%"=="0418" set "D=A"   :: Czech (Ano)
if "%SYS_LANG%"=="0402" set "D=Y"   :: Arabic (fallback - system32 often English)

:: --- Run takeown ---
if "%MODE%"=="dir" (
    takeown /f "%TARGET%" /r /d %D%
) else (
    takeown /f "%TARGET%"
)

:: --- Run icacls ---
if "%MODE%"=="dir" (
    icacls "%TARGET%" /grant *S-1-5-32-544:F /t /c /l /q
) else (
    icacls "%TARGET%" /grant *S-1-5-32-544:F /c /l
)

endlocal
