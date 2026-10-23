@echo off
set "SCRIPT_DIR=%~dp0"
SETLOCAL ENABLEDELAYEDEXPANSION

:: Skip the start2.bin wipe if already done on a previous install
set "WIPE_DONE=0"
if exist "!SystemDrive!\ProgramData\LexBoosTOS\StartMenuWipe.done" set "WIPE_DONE=1"

if exist "!SystemDrive!\Windows\StartMenuLayout.xml" del /q /f "!SystemDrive!\Windows\StartMenuLayout.xml"

:: Kill StartMenuExperienceHost so it can't regenerate start2.bin from memory
taskkill /f /im StartMenuExperienceHost.exe >nul 2>&1

mkdir "%SYSTEMDRIVE%\Users\Default\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState" 2>nul
copy /y "%SCRIPT_DIR%settings.json" "%SYSTEMDRIVE%\Users\Default\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"

:: Start Menu shortcut "LexBoosT Tweaks & Tools" - Default profile (Roaming)
if not exist "%SYSTEMDRIVE%\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs" mkdir "%SYSTEMDRIVE%\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut('%SYSTEMDRIVE%\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\LexBoosT Tweaks & Tools.lnk'); $s.TargetPath='%SystemRoot%\LexBoosTOS\Scripts\Programs\INSTALLSOFTS.exe'; $s.IconLocation='%SystemRoot%\LexBoosTOS\Resources\Icons\soft.ico'; $s.Description='LexBoosT Tweaks & Tools'; $s.Save()"

for /f "usebackq tokens=2 delims=\" %%a in (`reg query "HKEY_USERS" ^| findstr /r /x /c:"HKEY_USERS\\S-.*" /c:"HKEY_USERS\\AME_UserHive_[^_]*"`) do (

	reg query "HKEY_USERS\%%a" | findstr /c:"Volatile Environment" /c:"AME_UserHive_" > nul 2>&1
	if not !errorlevel! == 1 (
		for /f "usebackq tokens=3* delims= " %%b in (`reg query "HKU\%%a\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v "Local AppData" 2^>nul ^| findstr /r /x /c:".*Local AppData[ ]*REG_SZ[ ].*"`) do (
			:: %%c = Local AppData; Start Menu lives in Roaming (sibling of Local)
			set "USER_ROAMING=%%c\..\Roaming"

			:: Deploy custom start2.bin (pre-configured pins) - skipped if already wiped
			if "!WIPE_DONE!"=="0" (
				for /f "usebackq delims=" %%d in (`dir /b "%%c\Packages" /a:d ^| findstr /c:"Microsoft.Windows.StartMenuExperienceHost"`) do (
					mkdir "%%c\Packages\%%d\LocalState" 2>nul
					copy /y "%SCRIPT_DIR%start2.bin" "%%c\Packages\%%d\LocalState\start2.bin"
				)
			)

			:: Start Menu shortcut "LexBoosT Tweaks & Tools" - per user (Roaming)
			if not exist "!USER_ROAMING!\Microsoft\Windows\Start Menu\Programs" mkdir "!USER_ROAMING!\Microsoft\Windows\Start Menu\Programs"
			powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut('!USER_ROAMING!\Microsoft\Windows\Start Menu\Programs\LexBoosT Tweaks & Tools.lnk'); $s.TargetPath='%%SystemRoot%%\LexBoosTOS\Scripts\Programs\INSTALLSOFTS.exe'; $s.IconLocation='%%SystemRoot%%\LexBoosTOS\Resources\Icons\soft.ico'; $s.Description='LexBoosT Tweaks & Tools'; $s.Save()"

			for /f "usebackq delims=" %%d in (`dir /b "%%c\Packages" /a:d ^| findstr /c:"Microsoft.DesktopAppInstaller"`) do (
				mkdir "%%c\Packages\%%d\LocalState" 2>nul
				echo copy /y "%SCRIPT_DIR%settings.json" "%%c\Packages\%%d\LocalState\settings.json"
				copy /y "%SCRIPT_DIR%settings.json" "%%c\Packages\%%d\LocalState\settings.json"
			)

		)
		for /f "usebackq delims=" %%c in (`reg query "HKU\%%a\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" ^| findstr /c:"start.tilegrid"`) do (
			reg delete "%%c" /f >nul 2>&1
		)

		reg delete "HKU\%%a\Software\Microsoft\Windows\CurrentVersion\Start" /v "Config" /f >nul 2>&1
	)
)
if "!WIPE_DONE!"=="0" (
	mkdir "!SystemDrive!\ProgramData\LexBoosTOS" 2>nul
	powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss' | Out-File -Encoding ascii '!SystemDrive!\ProgramData\LexBoosTOS\StartMenuWipe.done'"
)
endlocal
exit /b 0
