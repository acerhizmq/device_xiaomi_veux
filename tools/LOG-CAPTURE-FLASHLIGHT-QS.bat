@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Lunaris Flashlight QS Log Capture

:: USB debugging ON, phone connected.
:: 1) Run this .bat
:: 2) Follow on-screen steps (QS torch ON -> OFF -> stuck %% / crash)
:: 3) ZIP the output folder and send it
::
:: Output: lunaris-flashlight-logs-YYYYMMDD-HHMMSS\

set "ROOT=%~dp0"
set "STAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=%STAMP: =0%"
set "OUT_DIR=%ROOT%lunaris-flashlight-logs-%STAMP%"
set "LOGFILE=%OUT_DIR%\logcat_full.txt"
set "LOGFILTER=%OUT_DIR%\logcat_filtered.txt"

set "TORCH0=/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@0/torch_strength"
set "TORCH1=/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@1/torch_strength"
set "TORCH3=/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@3/torch_strength"
set "LED0=/sys/class/leds/led:torch_0/brightness"
set "LED1=/sys/class/leds/led:torch_1/brightness"

where adb >nul 2>&1
if errorlevel 1 if exist "%ROOT%platform-tools\adb.exe" set "PATH=%ROOT%platform-tools;%PATH%"

adb get-state >nul 2>&1
if errorlevel 1 (
    echo ERROR: No device. Enable USB debugging and connect the phone.
    pause
    exit /b 1
)

mkdir "%OUT_DIR%" 2>nul
mkdir "%OUT_DIR%\sysfs" 2>nul
mkdir "%OUT_DIR%\dumpsys" 2>nul
mkdir "%OUT_DIR%\crash" 2>nul

echo.
echo === Lunaris Flashlight QS Log Capture ===
echo Output: %OUT_DIR%
echo.

call :SaveDeviceInfo
call :SaveSysfsSnapshot "before_test" "%OUT_DIR%\sysfs\sysfs_before_test.txt"

echo [1/6] Clearing logcat buffer...
adb logcat -c >nul 2>&1

echo [2/6] Starting logcat recording on PC...
start "LunarisFlashLogcat" /min cmd /c "adb logcat -v threadtime > "%LOGFILE%" 2>&1"
timeout /t 2 /nobreak >nul

echo.
echo === REPRODUCE THE BUG ===
echo.
echo   Step A: Open Quick Settings, turn FLASHLIGHT ON.
echo          Wait until light is on and %% label appears.
echo          Press any key here...
pause >nul
call :SaveSysfsSnapshot "torch_on" "%OUT_DIR%\sysfs\sysfs_torch_on.txt"
call :SavePropsSnapshot "torch_on" "%OUT_DIR%\props_torch_on.txt"

echo.
echo   Step B: Turn FLASHLIGHT OFF in QS.
echo          Stop when: %% still visible OR phone thinks torch is on
echo          OR SystemUI freezes/crashes.
echo          Press any key here...
pause >nul
call :SaveSysfsSnapshot "torch_off_stuck" "%OUT_DIR%\sysfs\sysfs_torch_off_stuck.txt"
call :SavePropsSnapshot "torch_off_stuck" "%OUT_DIR%\props_torch_off_stuck.txt"

echo.
echo   Step C: Wait up to 15 seconds if SystemUI is restarting.
echo          Press any key to finish recording...
pause >nul
call :SaveSysfsSnapshot "after_wait" "%OUT_DIR%\sysfs\sysfs_after_wait.txt"
call :SavePropsSnapshot "after_wait" "%OUT_DIR%\props_after_wait.txt"

echo [3/6] Stopping logcat...
taskkill /FI "WINDOWTITLE eq LunarisFlashLogcat*" /T /F >nul 2>&1
timeout /t 1 /nobreak >nul

echo [4/6] Filtering logcat...
if exist "%LOGFILE%" (
    findstr /I /R "Flashlight FlashlightController FlashlightRepository FlashlightInteractor FlashlightTile CameraProviderExtension cameraserver CameraService CameraProviderManager torch MK9_BRIDGE AndroidRuntime FATAL EXCEPTION systemui SystemUI ANR watchdog" "%LOGFILE%" > "%LOGFILTER%" 2>nul
)

echo [5/6] Saving dumpsys and crash buffers...
adb shell dumpsys media.camera > "%OUT_DIR%\dumpsys\media_camera.txt" 2>nul
adb shell dumpsys activity service com.android.systemui > "%OUT_DIR%\dumpsys\systemui_full.txt" 2>nul
findstr /I "flashlight torch Flashlight" "%OUT_DIR%\dumpsys\systemui_full.txt" > "%OUT_DIR%\dumpsys\systemui_flashlight.txt" 2>nul

adb logcat -b crash -d -v threadtime > "%OUT_DIR%\crash\logcat_crash.txt" 2>nul
adb logcat -b events -d -v threadtime > "%OUT_DIR%\crash\logcat_events.txt" 2>nul
adb shell "ls -lt /data/tombstones 2>/dev/null | head -5" > "%OUT_DIR%\crash\tombstones_list.txt" 2>nul
adb shell "ls -lt /data/anr 2>/dev/null | head -5" > "%OUT_DIR%\crash\anr_list.txt" 2>nul
adb shell "t=$(ls -t /data/tombstones/tombstone_* 2>/dev/null | head -1); if [ -n \"$t\" ]; then cat \"$t\"; fi" > "%OUT_DIR%\crash\latest_tombstone.txt" 2>nul
adb shell "f=$(ls -t /data/anr/anr_* 2>/dev/null | head -1); if [ -n \"$f\" ]; then cat \"$f\"; fi" > "%OUT_DIR%\crash\latest_anr.txt" 2>nul

echo [6/6] Writing README...
call :WriteReadme

echo.
echo DONE.
echo.
echo Send this folder ^(ZIP it^):
echo   %OUT_DIR%
echo.
echo Key files:
echo   %LOGFILE%
echo   %LOGFILTER%
echo   %OUT_DIR%\sysfs\sysfs_torch_off_stuck.txt
echo   %OUT_DIR%\dumpsys\media_camera.txt
echo   %OUT_DIR%\README.txt
echo.
pause
exit /b 0

:SaveDeviceInfo
echo [0/6] Device info...
(
echo === device ===
adb shell getprop ro.product.device
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.display.id
adb shell getprop ro.lunaris.build.version
echo.
echo === flashlight props ===
adb shell getprop persist.flashlight.strength
adb shell settings get system flashlight_brightness
adb shell settings get secure flashlight_enabled
adb shell settings get secure flashlight_available
echo.
echo === capture started ===
echo %date% %time%
) > "%OUT_DIR%\device_info.txt"
exit /b 0

:SaveSysfsSnapshot
set "LABEL=%~1"
set "DEST=%~2"
(
echo === sysfs snapshot: %LABEL% ===
echo %date% %time%
echo.
echo --- persist.flashlight.strength ---
adb shell getprop persist.flashlight.strength
echo.
echo --- torch_strength @0 ---
adb shell "cat '%TORCH0%' 2>/dev/null || echo READ_FAIL"
echo.
echo --- torch_strength @1 ---
adb shell "cat '%TORCH1%' 2>/dev/null || echo READ_FAIL"
echo.
echo --- torch_strength @3 ---
adb shell "cat '%TORCH3%' 2>/dev/null || echo READ_FAIL"
echo.
echo --- led torch_0 brightness ---
adb shell "cat '%LED0%' 2>/dev/null || echo READ_FAIL"
echo.
echo --- led torch_1 brightness ---
adb shell "cat '%LED1%' 2>/dev/null || echo READ_FAIL"
) > "%DEST%"
exit /b 0

:SavePropsSnapshot
set "LABEL=%~1"
set "DEST=%~2"
(
echo === props snapshot: %LABEL% ===
echo %date% %time%
adb shell getprop persist.flashlight.strength
adb shell settings get system flashlight_brightness
adb shell settings get secure flashlight_enabled
adb shell settings get secure flashlight_available
) > "%DEST%"
(
echo === %LABEL% ===
type "%DEST%"
echo.
) >> "%OUT_DIR%\props_timeline.txt"
exit /b 0

:WriteReadme
(
echo Lunaris Flashlight QS log bundle
echo ================================
echo.
echo Reproduce steps recorded in this capture:
echo   A) QS flashlight ON
echo   B) QS flashlight OFF ^(stuck %% / SystemUI issue^)
echo   C) Wait for recovery/crash
echo.
echo Files:
echo   device_info.txt          - build + flashlight settings
echo   logcat_full.txt          - full logcat during test
echo   logcat_filtered.txt      - torch/SystemUI/camera filtered lines
echo   sysfs\sysfs_*.txt        - sysfs + prop at each step
echo   props_timeline.txt       - settings timeline
echo   dumpsys\media_camera.txt - camera HAL state
echo   dumpsys\systemui_*.txt   - SystemUI flashlight state
echo   crash\                   - crash buffer, tombstone/anr if pulled
echo.
echo Compare sysfs_torch_on vs sysfs_torch_off_stuck:
echo   If torch_strength or LED brightness ^> 0 while UI shows OFF, bridge/HAL desync.
echo.
echo Created: %date% %time%
) > "%OUT_DIR%\README.txt"
exit /b 0
