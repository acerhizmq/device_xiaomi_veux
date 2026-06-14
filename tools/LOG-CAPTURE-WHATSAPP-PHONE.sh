#!/system/bin/sh
# WhatsApp rear-camera log bundle — ON PHONE, root shell, NO bash, NO ./
#
# Kurulum (bir kez):
#   adb root && adb push LOG-CAPTURE-WHATSAPP-PHONE.sh /data/local/tmp/wp-cap.sh
#   adb shell chmod 644 /data/local/tmp/wp-cap.sh
#
# Kullanim:
#   sh /data/local/tmp/wp-cap.sh          # testten HEMEN sonra (onerilen)
#   sh /data/local/tmp/wp-cap.sh watch    # once calistir, 3dk icinde test yap
#
# Cikti: /sdcard/Download/lunaris-whatsapp-logs-YYYYMMDD-HHMMSS/
# Tester sadece bu klasoru zipleyip gonderir.

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="/sdcard/Download/lunaris-whatsapp-logs-$STAMP"
MODE="${1:-dump}"
WATCH_SEC=180

STRINGS=/system/bin/strings
[ -x "$STRINGS" ] || STRINGS=strings

mkdir -p "$OUT/logcat" "$OUT/kernel" "$OUT/props" "$OUT/dumpsys" \
    "$OUT/vendor-check" "$OUT/tombstones" "$OUT/analysis"
mkdir -p /sdcard/Download

echo "=== Lunaris WhatsApp log capture ==="
echo "Mode: $MODE"
echo "Output: $OUT"
echo ""

# --- device + camera props ---
{
    echo "=== device ==="
    getprop ro.product.device
    getprop ro.build.fingerprint
    getprop ro.build.display.id
    getprop ro.build.product
    getprop ro.lunaris.build.version
    echo ""
    echo "=== camera props ==="
    getprop persist.vendor.camera.pkgname
    getprop persist.vendor.cam.strip3pjfif
    getprop persist.vendor.camera.privapp.list
    echo ""
    echo "=== capture ==="
    date
    echo "mode=$MODE"
} >"$OUT/device_info.txt"

getprop >"$OUT/props/all_getprop.txt" 2>/dev/null
getprop | grep -iE 'camera|vendor\.camera|persist\.vendor\.cam' \
    >"$OUT/props/camera_getprop.txt" 2>/dev/null

# --- kernel ---
dmesg >"$OUT/kernel/dmesg.txt" 2>/dev/null
dmesg | grep -iE 'camx|chi|camera|provider|SIGABRT|fault' \
    >"$OUT/kernel/dmesg_camera_filtered.txt" 2>/dev/null

# --- logcat ---
if [ "$MODE" = "watch" ]; then
    echo "logcat temizleniyor..."
    logcat -c 2>/dev/null
    echo ""
    echo ">>> SIMDI TEST YAP <<<"
    echo "WhatsApp goruntulu arama -> on kamera -> ARKA kamera"
    echo "Script ${WATCH_SEC} saniye log topluyor..."
    echo ""
    logcat -v threadtime >"$OUT/logcat/logcat_live.txt" 2>/dev/null &
    LPID=$!
    sleep "$WATCH_SEC"
    kill "$LPID" 2>/dev/null
    wait "$LPID" 2>/dev/null
    cp "$OUT/logcat/logcat_live.txt" "$OUT/logcat/logcat_full.txt" 2>/dev/null
else
    echo "Mevcut logcat buffer aliniyor (testten hemen sonra calistirdin mi?)"
    logcat -d -v threadtime >"$OUT/logcat/logcat_full.txt" 2>/dev/null
fi

logcat -d -v threadtime \
    CamX:V CHIUSECASE:V cameraserver:V CameraService:V \
    XiaomiVendorTagOverlay:V vendor.camera.provider@2.4:V \
    android.hardware.camera:V libc:V com.whatsapp:V '*:S' \
    >"$OUT/logcat/logcat_camera_whatsapp.txt" 2>/dev/null

grep -iE 'whatsapp|VoipActivity|camera|CamX|CHI|cameraserver|CameraService|provider@2.4|PLTV|IMAGE_SIZE|clientname|pkgname|thirdParty|SetPackageName|InitializeOverrideSession|can.t find tag|SIGABRT|provider.*died|remapping dataspace|sessionParams|configure_stream|Pure AOSP|ZSLPreview|HM2|QCFA|strip3pjfif' \
    "$OUT/logcat/logcat_full.txt" >"$OUT/logcat/logcat_filtered.txt" 2>/dev/null

# --- dumpsys ---
dumpsys media.camera >"$OUT/dumpsys/dumpsys_media_camera.txt" 2>/dev/null
dumpsys activity activities 2>/dev/null | head -200 \
    >"$OUT/dumpsys/activities_head.txt" 2>/dev/null

# --- vendor HAL on device ---
{
    echo "=== vendor HAL files ==="
    ls -la /vendor/lib64/hw/com.qti.chi.override.so \
        /vendor/lib64/hw/camera.qcom.so 2>&1
    echo ""
    echo "=== strings chi.override ==="
    "$STRINGS" /vendor/lib64/hw/com.qti.chi.override.so 2>/dev/null \
        | grep -iE 'pkgname|clientname|thirdParty|whatsapp' || true
    echo ""
    echo "=== strings camera.qcom ==="
    "$STRINGS" /vendor/lib64/hw/camera.qcom.so 2>/dev/null \
        | grep -iE 'pkgname|clientname|thirdParty' || true
    echo ""
    echo "=== camxoverridesettings (head) ==="
    head -25 /vendor/etc/camera/camxoverridesettings.txt 2>&1
} >"$OUT/vendor-check/hal_on_device.txt" 2>/dev/null

# --- tombstones (last 5) ---
ls -la /data/tombstones 2>/dev/null | tail -20 >"$OUT/tombstones/tombstones_list.txt"
for t in $(ls -t /data/tombstones/tombstone_* 2>/dev/null | head -5); do
    cp "$t" "$OUT/tombstones/" 2>/dev/null
done

# --- auto analysis ---
{
    echo "Lunaris WhatsApp rear-camera — otomatik analiz"
    echo "=============================================="
    echo ""
    echo "=== props ==="
    PKG=$(getprop persist.vendor.camera.pkgname)
    STRIP=$(getprop persist.vendor.cam.strip3pjfif)
    echo "persist.vendor.camera.pkgname = $PKG"
    echo "persist.vendor.cam.strip3pjfif = $STRIP"
    if [ -z "$PKG" ]; then
        echo "WARN: pkgname bos — cameraserver henuz set etmemis olabilir"
    fi
    if [ "$STRIP" != "true" ]; then
        echo "WARN: strip3pjfif true degil — cameraserver mitigation kapali olabilir"
    fi
    echo ""
    echo "=== basari isaretleri (logda aranan) ==="
    for m in \
        'remapping dataspace' \
        'thirdPartyYUVSnapshot=1' \
        'clientName=com.whatsapp' \
        'sessionParams clientName' \
        'ZSLPreviewRaw_LT1080p' ; do
        if grep -q "$m" "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
            echo "  [+] $m"
        else
            echo "  [-] $m"
        fi
    done
    echo ""
    echo "=== hata isaretleri ==="
    for m in \
        'IMAGE_SIZE_VIOLATION' \
        'SIGABRT' \
        'ZSLPreviewRaw_LT1080p_PLTV' \
        "can't find tag" \
        'Pure AOSP Version build' \
        'camera cannot be accessed' \
        'provider.*died' ; do
        if grep -qiE "$m" "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
            echo "  [!] $m — BULUNDU"
        else
            echo "  [ ] $m"
        fi
    done
    echo ""
    if grep -q 'ZSLPreviewRaw_LT1080p_PLTV' "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
        echo "SONUC: PLTV pipeline secilmis — fix CALISMIYOR olabilir"
    elif grep -q 'remapping dataspace' "$OUT/logcat/logcat_filtered.txt" 2>/dev/null \
        && grep -q 'thirdPartyYUVSnapshot=1' "$OUT/logcat/logcat_filtered.txt" 2>/dev/null; then
        echo "SONUC: Fix isaretleri gorunuyor — arka kamera testini logdan dogrula"
    else
        echo "SONUC: Belirsiz — arka kamera gecisi yapildi mi kontrol et"
    fi
} >"$OUT/analysis/summary.txt"

{
    echo "Lunaris WhatsApp rear-camera log bundle"
    echo "========================================"
    echo ""
    echo "Bu klasoru oldugu gibi ZIP yapip gelistiriciye gonder."
    echo ""
    echo "Test sirasi (yeni ROM):"
    echo "  1) WhatsApp goruntulu arama baslat"
    echo "  2) On kamera -> ARKA kameraya gec (10-60sn bekle)"
    echo "  3) Hemen: sh /data/local/tmp/wp-cap.sh"
    echo "     (veya once: sh /data/local/tmp/wp-cap.sh watch)"
    echo "  4) /sdcard/Download/ icindeki lunaris-whatsapp-logs-* klasorunu zip'le"
    echo ""
    echo "Dosyalar:"
    echo "  analysis/summary.txt     — otomatik basari/hata ozeti"
    echo "  logcat/logcat_filtered.txt — onemli satirlar"
    echo "  logcat/logcat_full.txt   — tam buffer"
    echo "  vendor-check/            — HAL blob kontrolu"
    echo "  tombstones/              — crash varsa"
    echo ""
    echo "Basari log isaretleri:"
    echo "  - remapping dataspace -> UNKNOWN"
    echo "  - sessionParams thirdPartyYUVSnapshot=1"
    echo "  - sessionParams clientName=com.whatsapp"
    echo "  - ZSLPreviewRaw_LT1080p (PLTV DEGIL)"
} >"$OUT/README.txt"

echo ""
echo "OK: $OUT"
echo ""
cat "$OUT/analysis/summary.txt"
echo ""
echo ">>> Bu klasoru ZIP yapip gonder <<<"
ls -la "$OUT" 2>/dev/null | head -20
