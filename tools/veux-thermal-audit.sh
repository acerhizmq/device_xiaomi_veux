#!/system/bin/sh
# Veux thermal stack audit — run on device (adb shell sh /path/veux-thermal-audit.sh)
# Collects sysfs, process, vendor config, and profile-switch readiness.

OUT="${1:-/sdcard/Download/veux_thermal_audit_$(date +%Y%m%d_%H%M%S).txt}"
exec >"$OUT" 2>&1

section() { echo ""; echo "========== $1 =========="; }

section "DEVICE"
getprop ro.product.device
getprop ro.product.model
getprop ro.build.display.id
uname -r

section "MI_THERMALD PROCESS"
ps -A 2>/dev/null | grep -i therm || ps | grep -i therm
ls -la /vendor/bin/mi_thermald /system/vendor/bin/mi_thermald 2>&1
getprop init.svc.mi_thermald 2>/dev/null

section "THERMAL_MESSAGE SYSFS (kernel bridge)"
TM="/sys/class/thermal/thermal_message"
if [ -d "$TM" ]; then
    ls -la "$TM"
    for f in "$TM"/*; do
        [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f" 2>&1
    done
else
    echo "MISSING: $TM (kernel mi_thermal_message driver not loaded)"
fi

section "THERMAL ZONES (sample)"
ls /sys/class/thermal/ 2>&1 | head -40
for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    type=$(cat "$z/type" 2>/dev/null)
    temp=$(cat "$z/temp" 2>/dev/null)
    echo "$type ($z): ${temp}mC"
done

section "VENDOR THERMAL CONFIG FILES"
for f in \
    /vendor/etc/thermal-map.conf \
    /vendor/etc/thermal-region-map.conf \
    /vendor/etc/thermal-decrypt \
    /vendor/etc/thermal-chg-only.conf \
    /vendor/etc/thermal-normal.conf \
    /vendor/etc/thermal-video.conf \
    /vendor/etc/thermal-youtube.conf \
    /vendor/etc/thermal-tgame.conf \
    /vendor/etc/thermald-devices.conf; do
    if [ -f "$f" ]; then
        echo "OK $(ls -la "$f")"
        file "$f" 2>/dev/null || true
        head -c 64 "$f" 2>/dev/null | od -A x -t x1z -v | head -2
    else
        echo "MISSING: $f"
    fi
done

section "DATA VENDOR THERMAL"
ls -laR /data/vendor/thermal 2>&1
[ -f /data/vendor/thermal/config/thermal-map.conf ] && head -20 /data/vendor/thermal/config/thermal-map.conf

section "SCONFIG WRITE TEST (requires root)"
if [ -w /sys/class/thermal/thermal_message/sconfig ] 2>/dev/null; then
    old=$(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null)
    echo "sconfig before: $old"
    echo 21 > /sys/class/thermal/thermal_message/sconfig 2>/dev/null && \
        echo "wrote 21 (video profile)" || echo "write 21 FAILED"
    echo "sconfig after: $(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null)"
    [ -n "$old" ] && echo "$old" > /sys/class/thermal/thermal_message/sconfig 2>/dev/null
else
    echo "sconfig not writable or missing"
fi

section "DMESG THERMAL (last 80 lines)"
dmesg 2>/dev/null | grep -iE 'thermal|mi_thermal|thermald' | tail -80

section "LOGCAT MI_THERMAL (last 50)"
logcat -d -t 50 2>/dev/null | grep -iE 'thermal|mi_thermal|sconfig|thermald' || true

echo ""
echo "Audit written to: $OUT"
echo "Pull: adb pull $OUT"
