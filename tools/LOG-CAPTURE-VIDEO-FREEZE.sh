#!/usr/bin/env bash
# Video donma/takilma — PC + adb (Linux/macOS/Windows Git Bash)
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${1:-$(dirname "$0")/lunaris-video-stutter-logs-${STAMP}}"
ZIP="${OUT_DIR}.zip"

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

command -v adb >/dev/null || die "adb not found"
adb get-state >/dev/null 2>&1 || die "Device not connected"

mkdir -p "$OUT_DIR"/{kernel,logcat,dumpsys,props,sysfs,proc,analysis,tombstones}

echo "=== Lunaris video donma/takilma log capture ==="
echo "1) Open YouTube Shorts / IG Reels / TikTok"
echo "2) Reproduce freeze or stutter"
echo "3) Keep playing 30s more, then Ctrl+C"
echo "Output: $ZIP"
echo ""

adb root >/dev/null 2>&1 || true
sleep 1

{
  echo "=== device ==="
  adb shell getprop ro.product.device
  adb shell getprop ro.build.fingerprint
  adb shell getprop ro.build.display.id
  adb shell getprop ro.lunaris.build.version
  adb shell getprop ro.kernel.version
  echo ""
  echo "=== refresh / display ==="
  adb shell getprop debug.sf.frame_rate_multiple_threshold
  adb shell getprop vendor.display.enable_optimize_refresh
  adb shell settings get system peak_refresh_rate 2>/dev/null || true
  adb shell settings get system min_refresh_rate 2>/dev/null || true
  echo ""
  date -Iseconds 2>/dev/null || date
} >"$OUT_DIR/device_info.txt"

adb shell getprop >"$OUT_DIR/props/all_getprop.txt" 2>/dev/null || true
adb shell "getprop | grep -iE 'kernel|ksu|display|sf\\.|kgsl|vidc|video|drm|codec|thermal|media'" \
    >"$OUT_DIR/props/filtered_getprop.txt" 2>/dev/null || true

adb shell "cat /sys/class/drm/sde-crtc-0/measured_fps 2>/dev/null; \
  cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2>/dev/null; \
  cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null; \
  cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null" \
    >"$OUT_DIR/sysfs/display_gpu_thermal.txt" 2>/dev/null || true

adb shell cat /proc/meminfo >"$OUT_DIR/proc/meminfo.txt" 2>/dev/null || true
adb shell cat /proc/loadavg >"$OUT_DIR/proc/loadavg.txt" 2>/dev/null || true

adb shell dmesg -T >"$OUT_DIR/kernel/dmesg_before.txt" 2>/dev/null || \
    adb shell dmesg >"$OUT_DIR/kernel/dmesg_before.txt" 2>/dev/null || true
adb shell cat /proc/last_kmsg >"$OUT_DIR/kernel/last_kmsg.txt" 2>/dev/null || true

adb logcat -c
echo "Logging... reproduce freeze/stutter now (Ctrl+C when done)."
adb logcat -v threadtime -b all 2>&1 | tee "$OUT_DIR/logcat/logcat_full.txt" || true

adb shell dmesg -T >"$OUT_DIR/kernel/dmesg_after.txt" 2>/dev/null || \
    adb shell dmesg >"$OUT_DIR/kernel/dmesg_after.txt" 2>/dev/null || true

adb shell dumpsys media.codec >"$OUT_DIR/dumpsys/media_codec.txt" 2>/dev/null || true
adb shell dumpsys media.extractor >"$OUT_DIR/dumpsys/media_extractor.txt" 2>/dev/null || true
adb shell dumpsys SurfaceFlinger >"$OUT_DIR/dumpsys/surfaceflinger.txt" 2>/dev/null || true
adb shell dumpsys gfxinfo >"$OUT_DIR/dumpsys/gfxinfo.txt" 2>/dev/null || true
adb shell dumpsys display >"$OUT_DIR/dumpsys/display.txt" 2>/dev/null || true
adb shell dumpsys power >"$OUT_DIR/dumpsys/power.txt" 2>/dev/null || true
adb shell dumpsys meminfo >"$OUT_DIR/dumpsys/meminfo.txt" 2>/dev/null || true

adb logcat -d -v threadtime MediaCodec:V OMX:V CCodec:V NuPlayer:V SurfaceFlinger:V Choreographer:V '*:S' \
    >"$OUT_DIR/logcat/logcat_video_tags.txt" 2>/dev/null || true

grep -iE 'msm_vidc|iface_clk|data_addr|vp9|h264|hevc|MediaCodec|CCodec|OMX|NuPlayer|Choreographer|jank|dropped|SurfaceFlinger|kgsl|GPU|hang|fence|drm|dsi|refresh|underrun|stall|dequeue|thermal|throttl|audiotrack|lowmemory' \
    "$OUT_DIR/logcat/logcat_full.txt" >"$OUT_DIR/logcat/logcat_filtered.txt" 2>/dev/null || true

grep -iE 'msm_vidc|iface_clk|vp9|h264|kgsl|GPU|hang|drm|dsi|thermal|throttl|fence|vidc|OOM' \
    "$OUT_DIR/kernel/dmesg_after.txt" >"$OUT_DIR/kernel/dmesg_filtered.txt" 2>/dev/null || true

( cd "$(dirname "$OUT_DIR")" && zip -qr "$(basename "$ZIP")" "$(basename "$OUT_DIR")" )
ok "Saved $ZIP"
