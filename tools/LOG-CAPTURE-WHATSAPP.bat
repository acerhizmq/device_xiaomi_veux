@echo off
setlocal EnableExtensions
title Lunaris WhatsApp Log Capture

:: USB debugging ON, phone connected.
:: 1) Run this .bat
:: 2) Do the WhatsApp test while it records
:: 3) Press a key when done
:: 4) ZIP the output folder and send it

set "ROOT=%~dp0"
set "STAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=%STAMP: =0%"
set "OUT_DIR=%ROOT%lunaris-whatsapp-logs-%STAMP%"
set "LOGFILE=%OUT_DIR%\logcat_full.txt"

where adb >nul 2>&1
if errorlevel 1 if exist "%ROOT%platform-tools\adb.exe" set "PATH=%ROOT%platform-tools;%PATH%"

adb get-state >nul 2>&1
if errorlevel 1 (
    echo ERROR: No device. Enable USB debugging and connect the phone.
    pause
    exit /b 1
)

mkdir "%OUT_DIR%" 2>nul

echo.
echo === Lunaris WhatsApp Log Capture ===
echo Output: %OUT_DIR%
echo.

echo [1/4] Device info...
(
echo === device ===
adb shell getprop ro.product.device
adb shell getprop ro.build.fingerprint
adb shell getprop ro.lunaris.build.version
echo.
echo === camera props ===
adb shell getprop persist.vendor.camera.pkgname
adb shell getprop persist.vendor.cam.strip3pjfif
echo.
echo === capture ===
echo %date% %time%
) > "%OUT_DIR%\device_info.txt"

echo [2/4] Clearing old logcat...
adb logcat -c >nul 2>&1

echo [3/4] Recording logcat to PC ^(full, unfiltered^)...
echo.
echo   NOW do the test:
echo     - WhatsApp video call
echo     - Switch front -^> REAR camera
echo     - Wait at least 30 seconds on rear camera
echo.
echo   When finished, press any key here to stop recording.
echo.

start "LunarisLogcat" /min cmd /c "adb logcat -v threadtime > "%LOGFILE%" 2>&1"
timeout /t 2 /nobreak >nul

pause

taskkill /FI "WINDOWTITLE eq LunarisLogcat*" /T /F >nul 2>&1
timeout /t 1 /nobreak >nul

echo [4/4] Saving dumpsys...
adb shell dumpsys media.camera > "%OUT_DIR%\dumpsys_media_camera.txt" 2>nul

echo.
echo DONE.
echo   %LOGFILE%
echo   %OUT_DIR%\device_info.txt
echo   %OUT_DIR%\dumpsys_media_camera.txt
echo.
echo ZIP this folder and send it:
echo   %OUT_DIR%
echo.
pause
