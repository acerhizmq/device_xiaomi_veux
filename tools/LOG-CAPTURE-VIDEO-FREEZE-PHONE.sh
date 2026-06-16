#!/system/bin/sh
# Video donma/takilma — ON PHONE, root shell, NO bash, NO ./
#
# Kurulum:
#   bash LOG-CAPTURE-VIDEO-FREEZE-PUSH.sh   (PC'den)
#   veya script'i /data/local/tmp/vf-cap.sh olarak kopyala
#
# Kullanim:
#   sh /data/local/tmp/vf-cap.sh          # testten HEMEN sonra
#   sh /data/local/tmp/vf-cap.sh watch    # once baslat, 3dk icinde test yap
#
# Cikti: /sdcard/Download/lunaris-video-stutter-logs-YYYYMMDD-HHMMSS/

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="/sdcard/Download/lunaris-video-stutter-logs-$STAMP"
MODE="${1:-dump}"
WATCH_SEC=180

mkdir -p "$OUT/logcat" "$OUT/kernel" "$OUT/props" "$OUT/dumpsys" \
    "$OUT/sysfs" "$OUT/proc" "$OUT/analysis" "$OUT/tombstones"
mkdir -p /sdcard/Download

echo "=== Lunaris video donma/takilma log capture ==="
echo "Mode: $MODE"
echo "Output: $OUT"
echo ""

{
    echo "=== device ==="
    getprop ro.product.device
    getprop ro.build.fingerprint
    getprop ro.build.display.id
    getprop ro.lunaris.build.version
    getprop ro.kernel.version
    echo ""
    echo "=== display / refresh ==="
    getprop debug.sf.frame_rate_multiple_threshold
    getprop vendor.display.enable_optimize_refresh
    getprop vendor.display.enable_camera_smooth
    settings get system peak_refresh_rate 2>/dev/null
    settings get system min_refresh_rate 2>/dev/null
    echo ""
    echo "=== capture ==="
    date
    echo "mode=$MODE"
} >"$OUT/device_info.txt"

getprop >"$OUT/props/all_getprop.txt" 2>/dev/null
getprop | grep -iE 'kernel|display|sf\.|kgsl|vidc|video|drm|codec|thermal|media' \
    >"$OUT/props/filtered_getprop.txt" 2>/dev/null

{
    echo "=== measured_fps ==="
    cat /sys/class/drm/sde-crtc-0/measured_fps 2>&1
    echo "=== dfps_mode ==="
    cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2>&1
    echo "=== kgsl ==="
    cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>&1
    cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>&1
    echo "=== thermal sample ==="
    for f in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$f" ] && echo "$f: $(cat "$f" 2>/dev/null)"
    done | head -8
} >"$OUT/sysfs/display_gpu_thermal.txt" 2>/dev/null

cat /proc/meminfo >"$OUT/proc/meminfo.txt" 2>/dev/null
cat /proc/loadavg >"$OUT/proc/loadavg.txt" 2>/dev/null
top -n 1 -b 2>/dev/null | head -40 >"$OUT/proc/top_head.txt" 2>/dev/null

dmesg >"$OUT/kernel/dmesg_before.txt" 2>/dev/null
cat /proc/last_kmsg >"$OUT/kernel/last_kmsg.txt" 2>/dev/null

if [ "$MODE" = "watch" ]; then
    echo "logcat temizleniyor..."
    logcat -c 2>/dev/null
    echo ""
    echo ">>> SIMDI TEST YAP <<<"
    echo "Video izle, donma/takilmayi tetikle (${WATCH_SEC}sn kayit)"
    echo ""
    logcat -v threadtime -b all >"$OUT/logcat/logcat_live.txt" 2>/dev/null &
    LPID=$!
    sleep "$WATCH_SEC"
    kill "$LPID" 2>/dev/null
    wait "$LPID" 2>/dev/null
    cp "$OUT/logcat/logcat_live.txt" "$OUT/logcat/logcat_full.txt" 2>/dev/null
else
    echo "Mevcut logcat buffer aliniyor (testten hemen sonra calistirdin mi?)"
    logcat -d -v threadtime -b all >"$OUT/logcat/logcat_full.txt" 2>/dev/null
fi

logcat -d -v threadtime \
    MediaCodec:V OMX:V CCodec:V NuPlayer:V SurfaceFlinger:V Choreographer:V \
    msm_vidc:V kgsl:V '*:S' \
    >"$OUT/logcat/logcat_video_tags.txt" 2>/dev/null

grep -iE 'msm_vidc|iface_clk|data_addr|vp9|h264|hevc|avc|MediaCodec|CCodec|OMX|NuPlayer|ExoPlayer|Choreographer|jank|dropped|frame|SurfaceFlinger|kgsl|GPU|hang|fence|timeout|drm|dsi|refresh|dfps|measured_fps|underrun|stall|dequeue|thermal|throttl|audiotrack|lowmemory|trim|kill' \
    "$OUT/logcat/logcat_full.txt" >"$OUT/logcat/logcat_filtered.txt" 2>/dev/null

dmesg >"$OUT/kernel/dmesg_after.txt" 2>/dev/null
grep -iE 'msm_vidc|iface_clk|vp9|h264|kgsl|GPU|hang|drm|dsi|thermal|throttl|fence|vidc|bandwidth|OOM|kill' \
    "$OUT/kernel/dmesg_after.txt" >"$OUT/kernel/dmesg_filtered.txt" 2>/dev/null

dumpsys media.codec >"$OUT/dumpsys/media_codec.txt" 2>/dev/null
dumpsys media.extractor >"$OUT/dumpsys/media_extractor.txt" 2>/dev/null
dumpsys SurfaceFlinger >"$OUT/dumpsys/surfaceflinger.txt" 2>/dev/null
dumpsys gfxinfo >"$OUT/dumpsys/gfxinfo.txt" 2>/dev/null
dumpsys display >"$OUT/dumpsys/display.txt" 2>/dev/null
dumpsys power >"$OUT/dumpsys/power.txt" 2>/dev/null
dumpsys meminfo >"$OUT/dumpsys/meminfo.txt" 2>/dev/null
dumpsys activity top >"$OUT/dumpsys/activity_top.txt" 2>/dev/null

ls -la /data/tombstones 2>/dev/null | tail -20 >"$OUT/tombstones/tombstones_list.txt"
for t in $(ls -t /data/tombstones/tombstone_* 2>/dev/null | head -3); do
    cp "$t" "$OUT/tombstones/" 2>/dev/null
done

{
    echo "Lunaris video donma/takilma — otomatik analiz"
    echo "=============================================="
    echo ""
    echo "=== onemli isaretler (logcat) ==="
    for m in msm_vidc iface_clk MediaCodec dequeue underrun stall kgsl GPU hang jank Choreographer dropped SurfaceFlinger thermal throttl; do
        if grep -qi "$m" "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
            echo "  [+] $m"
        else
            echo "  [-] $m"
        fi
    done
    echo ""
    echo "=== onemli isaretler (kernel) ==="
    for m in msm_vidc kgsl hang thermal throttl drm dsi; do
        if grep -qi "$m" "$OUT/kernel/dmesg_filtered.txt" 2>/dev/null; then
            echo "  [+] $m"
        else
            echo "  [-] $m"
        fi
    done
    echo ""
    if grep -qiE 'kgsl.*hang|GPU.*hang' "$OUT/kernel/dmesg_filtered.txt" 2>/dev/null; then
        echo "SONUC: GPU hang isareti — kgsl loglarina bak"
    elif grep -qiE 'msm_vidc|iface_clk' "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
        echo "SONUC: Video codec (msm_vidc) aktivitesi var — decoder stall arastir"
    elif grep -qiE 'jank|Choreographer|dropped' "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
        echo "SONUC: UI jank / frame drop — SurfaceFlinger + refresh rate kontrol et"
    else
        echo "SONUC: Belirsiz — donma sirasinda test yapildi mi kontrol et"
    fi
} >"$OUT/analysis/summary.txt"

{
    echo "Lunaris video donma/takilma log bundle"
    echo "======================================"
    echo ""
    echo "Bu klasoru ZIP yapip gonder."
    echo ""
    echo "Dosyalar:"
    echo "  analysis/summary.txt"
    echo "  logcat/logcat_full.txt"
    echo "  logcat/logcat_filtered.txt"
    echo "  kernel/dmesg_before.txt + dmesg_after.txt"
    echo "  dumpsys/*"
} >"$OUT/README.txt"

echo ""
echo "OK: $OUT"
cat "$OUT/analysis/summary.txt"
echo ""
echo ">>> Bu klasoru ZIP yapip gonder <<<"
