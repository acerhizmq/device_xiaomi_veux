@echo off
setlocal EnableExtensions
title Video freeze log capture

set "STAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=%STAMP: =0%"
set "OUT_DIR=%~dp0lunaris-video-freeze-logs-%STAMP%"

where adb >nul 2>&1
if errorlevel 1 (
    echo ERROR: adb not found
    pause
    exit /b 1
)

adb get-state >nul 2>&1
if errorlevel 1 (
    echo ERROR: Device not connected
    pause
    exit /b 1
)

mkdir "%OUT_DIR%\kernel" "%OUT_DIR%\logcat" "%OUT_DIR%\dumpsys" "%OUT_DIR%\props" 2>nul

echo === Video freeze log capture ===
echo 1^) Open YouTube Shorts / IG Reels / TikTok
echo 2^) Scroll until video freezes ^(audio continues^)
echo 3^) Keep 30s, then press Ctrl+C here
echo.

adb root >nul 2>&1
timeout /t 1 /nobreak >nul

adb shell getprop ro.product.device > "%OUT_DIR%\device_info.txt"
adb shell getprop ro.build.fingerprint >> "%OUT_DIR%\device_info.txt"
adb shell getprop ro.kernel.version >> "%OUT_DIR%\device_info.txt"
adb shell dmesg > "%OUT_DIR%\kernel\dmesg_before.txt" 2>nul

adb logcat -c
echo Logging... reproduce freeze now, then Ctrl+C.
adb logcat -v threadtime > "%OUT_DIR%\logcat\logcat_live.txt"

adb shell dmesg > "%OUT_DIR%\kernel\dmesg_after.txt" 2>nul
adb shell dumpsys media.codec > "%OUT_DIR%\dumpsys\media_codec.txt" 2>nul
adb shell dumpsys SurfaceFlinger > "%OUT_DIR%\dumpsys\surfaceflinger.txt" 2>nul

findstr /i "msm_vidc iface_clk vp9 h264 fence kgsl GPU hang drm dsi refresh jank Choreographer MediaCodec dequeue drop stall underrun" "%OUT_DIR%\logcat\logcat_live.txt" > "%OUT_DIR%\logcat\logcat_filtered.txt" 2>nul
findstr /i "msm_vidc iface_clk vp9 h264 kgsl GPU hang drm dsi thermal throttl" "%OUT_DIR%\kernel\dmesg_after.txt" > "%OUT_DIR%\kernel\dmesg_filtered.txt" 2>nul

powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%' -DestinationPath '%OUT_DIR%.zip' -Force"
echo OK: %OUT_DIR%.zip
pause
