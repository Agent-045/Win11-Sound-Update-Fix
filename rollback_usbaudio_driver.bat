@echo off
setlocal

title USB Audio Driver Rollback Fix
color 0B

set "SRC_SYS=%~dp0USBAUDIO_10.0.26100.8875.sys"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo ==========================================================
echo   USB Audio Driver Rollback Fix
echo ==========================================================
echo.
echo   This tool rolls USBAUDIO.sys back to build 10.0.26100.8875
echo   and reboots the PC when finished.
echo.

if not exist "%SRC_SYS%" (
    echo ERROR: File not found: %SRC_SYS%
    echo.
    echo Put this .bat file into the folder that contains
    echo USBAUDIO_10.0.26100.8875.sys and run it again.
    echo.
    pause
    exit /b 1
)

set "SRCVER="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Item '%SRC_SYS%').VersionInfo.FileVersion"`) do set "SRCVER=%%V"
echo   Source driver : %SRC_SYS%
echo   Target build  : %SRCVER%
echo.

set "STAGE=%TEMP%\\usbaudio_rollback"
set "BACKUP=%SystemRoot%\\Temp\\usbaudio_rollback_backup"

if not exist "%STAGE%" mkdir "%STAGE%"
copy /y "%SRC_SYS%" "%STAGE%\\usbaudio.sys" >nul
if not exist "%STAGE%\\usbaudio.sys" (
    echo ERROR: Failed to prepare the driver file for copying.
    echo.
    pause
    exit /b 1
)

echo   [1/4] Backing up the current driver files...
if not exist "%BACKUP%" mkdir "%BACKUP%"
robocopy "%SystemRoot%\\System32\\drivers" "%BACKUP%\\System32-drivers" usbaudio.sys /B /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
for /d %%D in (%SystemRoot%\\System32\\DriverStore\\FileRepository\\wdma_usb.inf_amd64_*) do (
    robocopy "%%D" "%BACKUP%\\%%~nxD" USBAUDIO.sys /B /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
)
echo          Backup saved to: %BACKUP%
echo.

echo   [2/4] Replacing USBAUDIO.sys everywhere with build %SRCVER%...
for /d %%D in (%SystemRoot%\\System32\\DriverStore\\FileRepository\\wdma_usb.inf_amd64_*) do (
    robocopy "%STAGE%" "%%D" usbaudio.sys /B /IS /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
)
robocopy "%STAGE%" "%SystemRoot%\\System32\\drivers" usbaudio.sys /B /IS /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
if %errorlevel% geq 8 (
    echo          ERROR: Could not replace System32\\drivers\\usbaudio.sys.
    echo          The rollback could not be completed.
    echo.
    pause
    exit /b 1
)
echo          Done.
echo.

echo   [3/4] Re-binding USB audio devices to the wdma_usb driver...
set "STORE_INF="
for /d %%D in (%SystemRoot%\\System32\\DriverStore\\FileRepository\\wdma_usb.inf_amd64_*) do (
    if not defined STORE_INF set "STORE_INF=%%D\\wdma_usb.inf"
)
if defined STORE_INF goto do_rebind
echo          Skipped (no wdma_usb package found in DriverStore).
goto after_rebind

:do_rebind
pnputil /add-driver "%STORE_INF%" /install >nul 2>&1
if errorlevel 1 goto rebind_warn
echo          Driver re-installed on matching devices.
goto after_rebind

:rebind_warn
echo          pnputil returned an error (not critical: the binary is already
echo          replaced, so the rollback takes effect after reboot).

:after_rebind
echo.

echo   [4/4] Finish...
echo.
echo ==========================================================
echo   USB audio driver has been rolled back to:
echo     %SRCVER%
echo.
echo   Original driver files were kept at:
echo     %BACKUP%
echo.
echo   The PC will REBOOT in 10 seconds...
echo   To abort now, run in Command Prompt:  shutdown /a
echo ==========================================================
echo.

shutdown /r /t 10 /c "USB audio driver rollback complete - rebooting in 10 seconds"

endlocal