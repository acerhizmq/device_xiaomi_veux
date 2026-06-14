#!/usr/bin/env bash
# Video freeze logs — Termux only (root/Magisk su required). No PC.
#
# DO NOT run from Downloads/sdcard (noexec). Use:
#   cp LOG-CAPTURE-VIDEO-FREEZE-TERMUX.sh ~/
#   bash ~/LOG-CAPTURE-VIDEO-FREEZE-TERMUX.sh
#
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/lunaris-video-freeze-${STAMP}"
ZIP_DL="/sdcard/Download/lunaris-video-freeze-${STAMP}.zip"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v su >/dev/null 2>&1 || die "su not found (root/Magisk required)"
command -v bash >/dev/null 2>&1 || die "bash not found"

if ! pkg list-installed 2>/dev/null | grep -q android-tools; then
  pkg install -y android-tools zip
fi
command -v zip >/dev/null 2>&1 || pkg install -y zip

termux-setup-storage 2>/dev/null || true
mkdir -p "$OUT"/{kernel,logcat,sysfs}

echo "=== Video freeze capture (Termux) ==="
echo "1) Open Shorts / Reels / TikTok"
echo "2) Reproduce freeze (video stops, audio continues)"
echo "3) Keep scrolling 30s, then Ctrl+C"
echo "Output: $ZIP_DL"
echo ""

{
  echo "=== device ==="
  getprop ro.product.device
  getprop ro.build.fingerprint
  getprop ro.kernel.version
  echo ""
  echo "=== refresh ==="
  getprop vendor.display.enable_optimize_refresh
  settings get system peak_refresh_rate 2>/dev/null || true
  settings get system min_refresh_rate 2>/dev/null || true
  echo ""
  date
} >"$OUT/device_info.txt"

su -c dmesg >"$OUT/kernel/dmesg_before.txt" 2>/dev/null || true
su -c 'cat /sys/class/drm/sde-crtc-0/measured_fps 2>/dev/null; cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2>/dev/null' \
  >"$OUT/sysfs/display.txt" 2>/dev/null || true

su -c logcat -c
echo "Logging... reproduce freeze, then Ctrl+C"
su -c logcat -v threadtime 2>&1 | tee "$OUT/logcat/logcat_live.txt" || true

su -c dmesg >"$OUT/kernel/dmesg_after.txt" 2>/dev/null || true
grep -iE 'msm_vidc|iface_clk|vp9|h264|drm:dsi|refresh_rate|measured_fps|MediaCodec|Choreographer|fence|underrun|stall' \
  "$OUT/logcat/logcat_live.txt" >"$OUT/logcat/filtered.txt" 2>/dev/null || true
grep -iE 'msm_vidc|iface_clk|drm:dsi|refresh_rate|kgsl' \
  "$OUT/kernel/dmesg_after.txt" >"$OUT/kernel/filtered.txt" 2>/dev/null || true

ZIP_LOCAL="$HOME/lunaris-video-freeze-${STAMP}.zip"
rm -f "$ZIP_LOCAL"
(cd "$HOME" && zip -qr "$(basename "$ZIP_LOCAL")" "$(basename "$OUT")")
cp -f "$ZIP_LOCAL" "$ZIP_DL" 2>/dev/null || mv -f "$ZIP_LOCAL" "$ZIP_DL"
rm -rf "$OUT"
echo "OK: $ZIP_DL"
echo "Share from Downloads."
