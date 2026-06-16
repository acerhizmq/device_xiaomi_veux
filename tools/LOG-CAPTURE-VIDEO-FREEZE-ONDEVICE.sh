#!/system/bin/sh
# Video freeze — ON PHONE, root shell, NO bash, NO ./
# Usage:
#   sh /data/local/tmp/cap.sh
#
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="/data/local/tmp/vf-$STAMP"
OUTZIP="/sdcard/Download/lunaris-video-freeze-$STAMP.tar.gz"

mkdir -p "$OUT/kernel" "$OUT/logcat"
mkdir -p /sdcard/Download

echo "=== Video freeze capture ==="
echo "Shorts/Reels ac, donmayi tetikle, 30sn sonra Ctrl+C"
echo "Cikti: $OUTZIP"
echo ""

{
  echo device: $(getprop ro.product.device)
  echo build: $(getprop ro.build.fingerprint)
  echo kernel: $(getprop ro.kernel.version)
  echo optimize_refresh: $(getprop vendor.display.enable_optimize_refresh)
  echo peak_hz: $(settings get system peak_refresh_rate 2>/dev/null)
  echo min_hz: $(settings get system min_refresh_rate 2>/dev/null)
  echo measured_fps: $(cat /sys/class/drm/sde-crtc-0/measured_fps 2>/dev/null)
  echo dfps: $(cat /sys/class/graphics/fb0/msm_fb_dfps_mode 2>/dev/null)
  date
} > "$OUT/device_info.txt"

dmesg > "$OUT/kernel/dmesg_before.txt" 2>/dev/null
logcat -c 2>/dev/null
logcat -v threadtime > "$OUT/logcat/live.txt" 2>&1
dmesg > "$OUT/kernel/dmesg_after.txt" 2>/dev/null

grep -i msm_vidc "$OUT/logcat/live.txt" > "$OUT/logcat/f_vid.txt" 2>/dev/null
grep -i iface_clk "$OUT/logcat/live.txt" > "$OUT/logcat/f_clk.txt" 2>/dev/null
grep -i MediaCodec "$OUT/logcat/live.txt" > "$OUT/logcat/f_codec.txt" 2>/dev/null
grep -i dsi "$OUT/kernel/dmesg_after.txt" > "$OUT/kernel/f_dsi.txt" 2>/dev/null

cd /data/local/tmp
tar -czf "vf-$STAMP.tar.gz" "vf-$STAMP"
cp "vf-$STAMP.tar.gz" "$OUTZIP"
rm -rf "$OUT" "vf-$STAMP.tar.gz"
echo "OK: $OUTZIP"
