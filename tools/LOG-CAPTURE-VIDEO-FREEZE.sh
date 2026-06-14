#!/usr/bin/env bash
# Video freeze (image stalls, audio continues) — log bundle for veux.
# Run on PC with adb while tester reproduces in Instagram/YouTube/TikTok etc.
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${1:-/tmp/lunaris-video-freeze-logs-${STAMP}}"
ZIP="${OUT_DIR}.zip"

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

command -v adb >/dev/null || die "adb not found"
adb get-state >/dev/null 2>&1 || die "Device not connected"

mkdir -p "$OUT_DIR"/{kernel,logcat,dumpsys,props,sysfs}

echo "=== Video freeze log capture ==="
echo "1) Tester opens YouTube Shorts / IG Reels / TikTok"
echo "2) Scroll until freeze happens (video stops, audio continues)"
echo "3) Keep playing 30s more, then Ctrl+C here"
echo "Output: $ZIP"
echo ""

adb root >/dev/null 2>&1 || true
sleep 1

{
  echo "=== device ==="
  adb shell getprop ro.product.device
  adb shell getprop ro.build.fingerprint
  adb shell getprop ro.kernel.version
  adb shell getprop ro.build.display.id
  uname -r 2>/dev/null || true
  echo ""
  echo "=== refresh / display ==="
  adb shell getprop debug.sf.frame_rate_multiple_threshold
  adb shell getprop vendor.display.enable_optimize_refresh
  adb shell settings get system peak_refresh_rate 2>/dev/null || true
  adb shell settings get system min_refresh_rate 2>/dev/null || true
  echo ""
  echo "=== capture time ==="
  date -Iseconds 2>/dev/null || date
} >"$OUT_DIR/device_info.txt"

adb shell getprop >"$OUT_DIR/props/all_getprop.txt" 2>/dev/null || true
adb shell "getprop | grep -iE 'kernel|ksu|display|sf\\.|kgsl|vidc|video|drm'" \
    >"$OUT_DIR/props/filtered_getprop.txt" 2>/dev/null || true

adb shell "cat /sys/class/drm/sde-crtc-0/measured_fps 2>/dev/null; \
  cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2>/dev/null; \
  cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null; \
  cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null" \
    >"$OUT_DIR/sysfs/display_gpu.txt" 2>/dev/null || true

adb shell dmesg -T >"$OUT_DIR/kernel/dmesg_before.txt" 2>/dev/null || \
    adb shell dmesg >"$OUT_DIR/kernel/dmesg_before.txt" 2>/dev/null || true

adb logcat -c
echo "Logging... reproduce freeze now (Ctrl+C when done)."
adb logcat -v threadtime -b all 2>&1 | tee "$OUT_DIR/logcat/logcat_live.txt" || true

adb shell dmesg -T >"$OUT_DIR/kernel/dmesg_after.txt" 2>/dev/null || \
    adb shell dmesg >"$OUT_DIR/kernel/dmesg_after.txt" 2>/dev/null || true

adb shell dumpsys media.codec >"$OUT_DIR/dumpsys/media_codec.txt" 2>/dev/null || true
adb shell dumpsys SurfaceFlinger >"$OUT_DIR/dumpsys/surfaceflinger.txt" 2>/dev/null || true
adb shell dumpsys gfxinfo >"$OUT_DIR/dumpsys/gfxinfo.txt" 2>/dev/null || true
adb shell dumpsys power >"$OUT_DIR/dumpsys/power.txt" 2>/dev/null || true

grep -iE 'msm_vidc|iface_clk|data_addr|vp9|h264|fence.*timeout|kgsl|GPU|hang|drm:dsi|refresh|jank|Choreographer|MediaCodec|dequeue|drop|stall|underrun' \
    "$OUT_DIR/logcat/logcat_live.txt" >"$OUT_DIR/logcat/logcat_filtered.txt" 2>/dev/null || true

grep -iE 'msm_vidc|iface_clk|data_addr|vp9|h264|kgsl|GPU|hang|drm:dsi|IMAGE_SIZE|thermal|throttl' \
    "$OUT_DIR/kernel/dmesg_after.txt" >"$OUT_DIR/kernel/dmesg_filtered.txt" 2>/dev/null || true

( cd "$(dirname "$OUT_DIR")" && zip -qr "$(basename "$ZIP")" "$(basename "$OUT_DIR")" )
ok "Saved $ZIP"
echo "Send this zip for analysis."
