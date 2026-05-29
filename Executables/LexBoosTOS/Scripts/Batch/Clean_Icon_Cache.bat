@echo off
echo ========================================
echo  COMPLETE WINDOWS ICON CACHE CLEANING
echo ========================================
echo.

echo [1/4] Temporarily stopping Explorer...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
echo.
echo.
echo [2/4] Deleting main icon cache...
if exist "%localappdata%\IconCache.db" (
    del /f /q "%localappdata%\IconCache.db" 2>nul
    echo   - IconCache.db deleted
) else (
    echo   - IconCache.db not found
)
echo.
echo.
echo [3/4] Deleting iconcache files...
for /f "tokens=*" %%i in ('dir /b "%localappdata%\Microsoft\Windows\Explorer\iconcache*" 2^>nul') do (
    del /f /q "%localappdata%\Microsoft\Windows\Explorer\%%i" 2>nul
    echo   - %%i deleted
)
echo.
echo.
echo [4/4] Cleaning thumbnail cache...
if exist "%localappdata%\Microsoft\Windows\Explorer\thumbcache_*.db" (
    del /f /q "%localappdata%\Microsoft\Windows\Explorer\thumbcache_*.db" 2>nul
    echo   - Thumbcache files deleted
)
echo.
echo.
echo   - Restarting Explorer...
start explorer.exe
timeout /t 5 /nobreak >nul
echo.
echo.
echo ========================================
echo  CLEANING COMPLETED SUCCESSFULLY!
echo ========================================
echo.
echo Windows icon cache has been completely cleaned.
echo.
echo Auto-closing in 3 seconds...
timeout /t 3 /nobreak >nul
exit /b 0