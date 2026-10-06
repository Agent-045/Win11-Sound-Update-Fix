@echo off
setlocal

title USB Audio Driver Rollback Fix
color 0B

set "SRC_SYS=%~dp0USBAUDIO_10.0.26100.8972.sys"

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
echo   This tool restores a SIGNED pre-9457 USBAUDIO.sys
echo   (build 10.0.26100.8972) and reboots the PC when finished.
echo.

if not exist "%SRC_SYS%" (
    echo ERROR: File not found: %SRC_SYS%
    echo.
    echo Put this .bat file into the folder that contains
    echo USBAUDIO_10.0.26100.8972.sys and run it again.
    echo.
    pause
    exit /b 1
)

set "SIGSTATUS="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-AuthenticodeSignature -LiteralPath '%SRC_SYS%').Status"`) do set "SIGSTATUS=%%V"
if /I not "%SIGSTATUS%"=="Valid" (
    echo ERROR: Driver signature check failed: %SIGSTATUS%
    echo Refusing to install an unsigned driver.
    echo.
    pause
    exit /b 1
)

set "SRCVER="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Item '%SRC_SYS%').VersionInfo.FileVersion"`) do set "SRCVER=%%V"
set "SRCHASH="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%SRC_SYS%' -Algorithm SHA256).Hash"`) do set "SRCHASH=%%V"
echo   Source driver : %SRC_SYS%
echo   Driver build  : %SRCVER%
echo   SHA256        : %SRCHASH%
echo   Signature     : %SIGSTATUS%
echo.

set "STAGE=%TEMP%\usbaudio_rollback"
set "BACKUP=%SystemRoot%\Temp\usbaudio_rollback_backup"

if not exist "%STAGE%" mkdir "%STAGE%"
copy /y "%SRC_SYS%" "%STAGE%\usbaudio.sys" >nul
if not exist "%STAGE%\usbaudio.sys" (
    echo ERROR: Failed to prepare the driver file for copying.
    echo.
    pause
    exit /b 1
)

echo   [1/4] Backing up the current driver files...
if not exist "%BACKUP%" mkdir "%BACKUP%"
robocopy "%SystemRoot%\System32\drivers" "%BACKUP%\System32-drivers" usbaudio.sys /B /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
for /d %%D in (%SystemRoot%\System32\DriverStore\FileRepository\wdma_usb.inf_amd64_*) do (
    robocopy "%%D" "%BACKUP%\%%~nxD" USBAUDIO.sys /B /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
)
echo          Backup saved to: %BACKUP%
echo.

echo   [2/4] Replacing USBAUDIO.sys everywhere...
robocopy "%STAGE%" "%SystemRoot%\System32\drivers" usbaudio.sys /B /IS /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
for /d %%D in (%SystemRoot%\System32\DriverStore\FileRepository\wdma_usb.inf_amd64_*) do (
    robocopy "%STAGE%" "%%D" usbaudio.sys /B /IS /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
)
for /d %%D in (%SystemRoot%\WinSxS\amd64_dual_wdma_usb.inf_*) do (
    robocopy "%STAGE%" "%%D" usbaudio.sys /B /IS /R:0 /W:0 /NFL /NDL /NJH /NJS /NP >nul
)
echo          Done.
echo.

echo   [3/4] Verifying the installed driver binary...
set "DSTHASH="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%SystemRoot%\System32\drivers\usbaudio.sys' -Algorithm SHA256).Hash"`) do set "DSTHASH=%%V"
if /I not "%DSTHASH%"=="%SRCHASH%" (
    echo          ERROR: Hash mismatch after copy.
    echo          Got:      %DSTHASH%
    echo          Expected: %SRCHASH%
    echo.
    pause
    exit /b 1
)
set "DSTSIG="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-AuthenticodeSignature -LiteralPath '%SystemRoot%\System32\drivers\usbaudio.sys').Status"`) do set "DSTSIG=%%V"
if /I not "%DSTSIG%"=="Valid" (
    echo          ERROR: Installed driver signature is not valid: %DSTSIG%
    echo.
    pause
    exit /b 1
)
echo          OK: hash matches, signature is valid.
pnputil /scan-devices >nul 2>&1
echo.

echo   [4/4] Finish...
echo.
echo ==========================================================
echo   Signed USB audio driver restored:
echo     %SRCVER%
echo.
echo   Original driver files were kept at:
echo     %BACKUP%
echo.
echo   The PC will REBOOT in 10 seconds...
echo   To abort now, run in Command Prompt:  shutdown /a
echo ==========================================================
echo.

shutdown /r /t 10 /c "USB audio driver fix complete - rebooting in 10 seconds"

endlocal
