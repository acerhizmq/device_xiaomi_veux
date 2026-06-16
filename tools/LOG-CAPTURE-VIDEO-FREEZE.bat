@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Lunaris Video Donma / Takilma Log Capture

:: USB debugging ON, phone connected via USB.
:: 1) Run this .bat on Windows PC
:: 2) Reproduce video freeze/stutter (YouTube Shorts, IG Reels, TikTok, etc.)
:: 3) Press any key when done
:: 4) Send the generated .zip

set "ROOT=%~dp0"
set "STAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=%STAMP: =0%"
set "OUT_DIR=%ROOT%lunaris-video-stutter-logs-%STAMP%"
set "LOGFILE=%OUT_DIR%\logcat\logcat_live.txt"
set "LOGFULL=%OUT_DIR%\logcat\logcat_full.txt"

where adb >nul 2>&1
if errorlevel 1 if exist "%ROOT%platform-tools\adb.exe" set "PATH=%ROOT%platform-tools;%PATH%"
where adb >nul 2>&1
if errorlevel 1 (
    echo ERROR: adb not found. Install platform-tools or put adb.exe next to this script.
    pause
    exit /b 1
)

adb get-state >nul 2>&1
if errorlevel 1 (
    echo ERROR: No device. Enable USB debugging and connect the phone.
    pause
    exit /b 1
)

mkdir "%OUT_DIR%\kernel" "%OUT_DIR%\logcat" "%OUT_DIR%\dumpsys" "%OUT_DIR%\props" "%OUT_DIR%\sysfs" "%OUT_DIR%\proc" "%OUT_DIR%\analysis" "%OUT_DIR%\tombstones" "%OUT_DIR%\tombstones_full" "%OUT_DIR%\anr" "%OUT_DIR%\dropbox" "%OUT_DIR%\bugreport" 2>nul

echo.
echo ============================================================
echo   Lunaris — Video izlerken DONMA / TAKILMA log yakalama
echo ============================================================
echo Output folder: %OUT_DIR%
echo.
echo ONCELIKLE testi yapacaksin, sonra burada bir tusa basacaksin.
echo.

echo [1/11] adb root + device info...
adb root >nul 2>&1
timeout /t 2 /nobreak >nul

(
echo === device ===
adb shell getprop ro.product.device
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.display.id
adb shell getprop ro.lunaris.build.version
adb shell getprop ro.kernel.version
echo.
echo === display / refresh ===
adb shell getprop debug.sf.frame_rate_multiple_threshold
adb shell getprop vendor.display.enable_optimize_refresh
adb shell getprop vendor.display.enable_camera_smooth
adb shell getprop ro.surface_flinger.enable_frame_rate_override
adb shell settings get system peak_refresh_rate
adb shell settings get system min_refresh_rate
echo.
echo === video / codec props ===
adb shell getprop | findstr /i "vidc video codec kgsl drm display sf."
echo.
echo === capture ===
echo %date% %time%
) > "%OUT_DIR%\device_info.txt"

echo [2/11] getprop snapshot...
adb shell getprop > "%OUT_DIR%\props\all_getprop.txt" 2>nul
adb shell "getprop | grep -iE 'kernel|ksu|display|sf\\.|kgsl|vidc|video|drm|codec|thermal|media'" > "%OUT_DIR%\props\filtered_getprop.txt" 2>nul

echo [3/11] sysfs — FPS / GPU / thermal / DRM...
adb shell ls -laR /sys/class/drm > "%OUT_DIR%\sysfs\drm_ls.txt" 2>nul
adb shell cat /sys/class/drm/sde-crtc-0/measured_fps > "%OUT_DIR%\sysfs\measured_fps.txt" 2>nul
(
echo === measured_fps ===
adb shell cat /sys/class/drm/sde-crtc-0/measured_fps 2^>^&1
echo === dfps_mode ===
adb shell cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2^>^&1
echo === kgsl freq ===
adb shell cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2^>^&1
adb shell cat /sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies 2^>^&1
adb shell cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2^>^&1
echo === thermal (head) ===
adb shell "ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -8 | while read f; do echo -n \"$f: \"; cat \"$f\" 2>/dev/null; done"
) > "%OUT_DIR%\sysfs\display_gpu_thermal.txt" 2>nul

echo [4/11] proc snapshot...
adb shell cat /proc/meminfo > "%OUT_DIR%\proc\meminfo.txt" 2>nul
adb shell cat /proc/loadavg > "%OUT_DIR%\proc\loadavg.txt" 2>nul
adb shell "top -n 1 -b 2>/dev/null | head -40" > "%OUT_DIR%\proc\top_head.txt" 2>nul

echo [5/11] kernel dmesg BEFORE test...
adb shell dmesg -T > "%OUT_DIR%\kernel\dmesg_before.txt" 2>nul
if not exist "%OUT_DIR%\kernel\dmesg_before.txt" adb shell dmesg > "%OUT_DIR%\kernel\dmesg_before.txt" 2>nul
adb shell cat /proc/last_kmsg > "%OUT_DIR%\kernel\last_kmsg.txt" 2>nul

echo [6/11] logcat temizleniyor...
adb logcat -c >nul 2>&1

echo.
echo ============================================================
echo   SIMDI TESTI YAP:
echo     - YouTube Shorts / IG Reels / TikTok / normal video
echo     - Kaydir, donma veya takilmayi tetikle
echo     - Goruntu donuyor ama ses devam ediyorsa 30sn daha bekle
echo.
echo   Bitince buraya don ve bir tusa bas.
echo ============================================================
echo.

start "LunarisVideoLogcat" /min cmd /c "adb logcat -v threadtime -b all > "%LOGFILE%" 2>&1"
timeout /t 2 /nobreak >nul

pause

taskkill /FI "WINDOWTITLE eq LunarisVideoLogcat*" /T /F >nul 2>&1
timeout /t 1 /nobreak >nul
copy /y "%LOGFILE%" "%LOGFULL%" >nul 2>&1

echo [7/11] kernel AFTER + targeted dumpsys...
adb shell dmesg -T > "%OUT_DIR%\kernel\dmesg_after.txt" 2>nul
if not exist "%OUT_DIR%\kernel\dmesg_after.txt" adb shell dmesg > "%OUT_DIR%\kernel\dmesg_after.txt" 2>nul

adb shell dumpsys media.codec > "%OUT_DIR%\dumpsys\media_codec.txt" 2>nul
adb shell dumpsys media.extractor > "%OUT_DIR%\dumpsys\media_extractor.txt" 2>nul
adb shell dumpsys media.player > "%OUT_DIR%\dumpsys\media_player.txt" 2>nul
adb shell dumpsys media.audio_flinger > "%OUT_DIR%\dumpsys\media_audio_flinger.txt" 2>nul
adb shell dumpsys media.audio_policy > "%OUT_DIR%\dumpsys\media_audio_policy.txt" 2>nul
adb shell dumpsys SurfaceFlinger > "%OUT_DIR%\dumpsys\surfaceflinger.txt" 2>nul
adb shell dumpsys gfxinfo > "%OUT_DIR%\dumpsys\gfxinfo.txt" 2>nul
adb shell dumpsys display > "%OUT_DIR%\dumpsys\display.txt" 2>nul
adb shell dumpsys power > "%OUT_DIR%\dumpsys\power.txt" 2>nul
adb shell dumpsys meminfo > "%OUT_DIR%\dumpsys\meminfo.txt" 2>nul
adb shell dumpsys activity top > "%OUT_DIR%\dumpsys\activity_top.txt" 2>nul
adb shell dumpsys cpuinfo > "%OUT_DIR%\dumpsys\cpuinfo.txt" 2>nul

echo [8/11] full dumpsys -a ^(buyuk dosya, biraz surebilir^)...
adb shell dumpsys -a > "%OUT_DIR%\dumpsys\dumpsys_all.txt" 2>nul

echo [9/11] pull anr / dropbox / tombstones...
adb pull /data/anr "%OUT_DIR%\anr" >nul 2>&1
adb pull /data/system/dropbox "%OUT_DIR%\dropbox" >nul 2>&1
adb pull /data/tombstones "%OUT_DIR%\tombstones_full" >nul 2>&1
adb shell "ls -la /data/tombstones 2>/dev/null | tail -20" > "%OUT_DIR%\tombstones\tombstones_list.txt" 2>nul
for /f "tokens=*" %%F in ('adb shell "ls -t /data/tombstones/tombstone_* 2>/dev/null | head -3" 2^>nul') do (
    set "TB=%%F"
    set "TB=!TB: =!"
    if not "!TB!"=="" adb pull "!TB!" "%OUT_DIR%\tombstones\" >nul 2>&1
)

echo [10/11] bugreport ^(5-15 dk surebilir, USB takili kalsin^)...
adb bugreport "%OUT_DIR%\bugreport\bugreport.zip"

echo [11/11] filtered logs + analysis...
findstr /i /r "msm_vidc iface_clk data_addr vp9 h264 hevc avc MediaCodec CCodec OMX NuPlayer ExoPlayer Choreographer jank dropped frame SurfaceFlinger kgsl GPU hang fence timeout drm dsi refresh dfps measured_fps underrun stall dequeue thermal throttl audiotrack AudioFlinger audio_flinger lowmemory trim kill binder Slow dispatch" "%LOGFULL%" > "%OUT_DIR%\logcat\logcat_filtered.txt" 2>nul

findstr /i /r "msm_vidc iface_clk vp9 h264 kgsl GPU hang drm dsi thermal throttl fence vidc bandwidth OOM kill" "%OUT_DIR%\kernel\dmesg_after.txt" > "%OUT_DIR%\kernel\dmesg_filtered.txt" 2>nul

:: Video-focused tagged logcat buffer dump (post-hoc)
adb logcat -d -v threadtime MediaCodec:V OMX:V CCodec:V NuPlayer:V SurfaceFlinger:V Choreographer:V msm_vidc:V kgsl:V "*:S" > "%OUT_DIR%\logcat\logcat_video_tags.txt" 2>nul

(
echo Lunaris video donma/takilma — otomatik analiz
echo ==============================================
echo.
echo Kontrol edilen isaretler:
echo   [logcat] msm_vidc, iface_clk, MediaCodec stall/dequeue
echo   [logcat] Choreographer jank, SurfaceFlinger drop
echo   [kernel] kgsl hang, drm/dsi, thermal throttle
echo.
echo === logcat_filtered satir sayisi ===
for %%A in ("%OUT_DIR%\logcat\logcat_filtered.txt") do echo %%~zA bytes
echo.
echo === kernel_filtered satir sayisi ===
for %%A in ("%OUT_DIR%\kernel\dmesg_filtered.txt") do echo %%~zA bytes
echo.
echo === onemli anahtar kelimeler ===
for %%K in (msm_vidc iface_clk MediaCodec dequeueInputBuffer dequeueOutputBuffer underrun kgsl GPU hang thermal throttl jank Choreographer dropped SurfaceFlinger fence timeout) do (
    findstr /i "%%K" "%OUT_DIR%\logcat\logcat_filtered.txt" >nul 2>&1 && echo   [+] logcat: %%K || echo   [-] logcat: %%K
)
for %%K in (msm_vidc kgsl hang thermal throttl drm dsi) do (
    findstr /i "%%K" "%OUT_DIR%\kernel\dmesg_filtered.txt" >nul 2>&1 && echo   [+] kernel: %%K || echo   [-] kernel: %%K
)
echo.
echo Tam log: logcat\logcat_full.txt
echo Kernel: kernel\dmesg_before.txt + dmesg_after.txt
) > "%OUT_DIR%\analysis\summary.txt"

(
echo Lunaris video donma/takilma log bundle
echo =======================================
echo.
echo Bu klasoru ZIP yapip gonder.
echo.
echo Test sirasi:
echo   1) Bu .bat'i calistir
echo   2) Telefonda video izle, donmayi/takilmayi tetikle
echo   3) PC'de bir tusa bas
echo   4) Olusan .zip dosyasini gonder
echo.
echo Dosyalar:
echo   logcat\logcat_full.txt      — tam adb logcat ^(-b all^)
echo   logcat\logcat_filtered.txt  — video/GPU/codec onemli satirlar
echo   logcat\logcat_video_tags.txt — MediaCodec/SF tagged dump
echo   kernel\dmesg_before.txt     — test oncesi kernel
echo   kernel\dmesg_after.txt      — test sonrasi kernel
echo   kernel\last_kmsg.txt        — onceki boot kernel ^(varsa^)
echo   dumpsys\*.txt               — codec, audio, SurfaceFlinger, display, mem
echo   dumpsys\dumpsys_all.txt     — tam dumpsys -a
echo   sysfs\display_gpu_thermal.txt
echo   sysfs\drm_ls.txt            — /sys/class/drm agaci
echo   sysfs\measured_fps.txt      — anlik olculen FPS
echo   anr\                        — ANR trace dosyalari
echo   dropbox\                    — sistem dropbox kayitlari
echo   tombstones_full\            — tum tombstone dosyalari
echo   bugreport\bugreport.zip     — tam Android bugreport
echo   analysis\summary.txt        — otomatik ozet
echo.
echo NOT: bugreport + dumpsys_all buyuk olabilir; ZIP birkaç dakika surebilir.
) > "%OUT_DIR%\README.txt"

set "ZIPFILE=%OUT_DIR%.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%' -DestinationPath '%ZIPFILE%' -Force" 2>nul

echo.
echo ============================================================
echo DONE.
echo   Folder: %OUT_DIR%
if exist "%ZIPFILE%" echo   ZIP:    %ZIPFILE%
echo   Read:   %OUT_DIR%\analysis\summary.txt
echo ============================================================
type "%OUT_DIR%\analysis\summary.txt"
echo.
pause
