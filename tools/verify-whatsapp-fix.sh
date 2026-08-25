#!/usr/bin/env bash
# Post-flash checks for WhatsApp rear-camera / CHI third-party path (veux).
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
VENDOR="${ROOT}/vendor/xiaomi/veux/proprietary"
die() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

[[ -d "$VENDOR" ]] || die "vendor tree missing at $VENDOR"

grep -q 'ro.build.product=veux' "${ROOT}/device/xiaomi/veux/"*.mk \
    || die "ro.build.product=veux missing (CHI Pure AOSP XML fallback)"
ok "ro.build.product=veux in lineage_veux.mk"

grep -q 'persist.vendor.cam.strip3pjfif=true' \
    "${ROOT}/device/xiaomi/veux/configs/properties/vendor.prop" \
    || die "strip3pjfif not enabled"
ok "persist.vendor.cam.strip3pjfif in vendor.prop"

grep -q 'persist.vendor.cam.strip3pjfif' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/utils/SessionConfigurationUtils.cpp" \
    || die "cameraserver strip3pjfif property name missing"
ok "cameraserver reads persist.vendor.cam.strip3pjfif (<=30 chars)"

grep -q 'persist.vendor.camera.pkgname' \
    "${ROOT}/device/xiaomi/veux/sepolicy/vendor/property_contexts" \
    || die "pkgname property_contexts missing"
ok "pkgname sepolicy property_contexts"

grep -q 'set_prop(hal_camera_default, vendor_persist_camera_prop)' \
    "${ROOT}/device/xiaomi/veux/sepolicy/vendor/hal_camera_default.te" \
    || die "hal_camera_default missing set_prop vendor_persist_camera_prop"
ok "hal_camera_default can set persist.vendor.camera.pkgname"

grep -q 'persist.vendor.cam.cname_tag=0x808d0000' \
    "${ROOT}/device/xiaomi/veux/configs/properties/vendor.prop" \
    || die "cname_tag hex missing in vendor.prop"
grep -q 'persist.vendor.cam.3pyuv_tag=0x808d0001' \
    "${ROOT}/device/xiaomi/veux/configs/properties/vendor.prop" \
    || die "3pyuv_tag hex missing in vendor.prop"
python3 - <<PY || die "tag-ID property names exceed PROP_NAME_MAX (31)"
props = [
    "persist.vendor.cam.cname_tag",
    "persist.vendor.cam.3pyuv_tag",
]
for p in props:
    assert len(p) <= 31, p
PY
for prop in persist.vendor.cam.cname_tag persist.vendor.cam.3pyuv_tag; do
    grep -q "$prop" "${ROOT}/device/xiaomi/veux/sepolicy/vendor/property_contexts" \
        || die "property_contexts missing $prop"
    grep -q "$prop" "${ROOT}/frameworks/av/services/camera/libcameraservice/common/XiaomiVendorTagOverlay.cpp" \
        || die "XiaomiVendorTagOverlay.cpp missing $prop"
done
ok "Xiaomi sessionParams vendor tag IDs in vendor.prop (0x808d0000/0x808d0001, <=30 chars, all layers match)"

grep -q 'persist.vendor.camera.pkgname' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/CameraService.cpp" \
    || die "cameraserver pkgname hook missing"
ok "cameraserver sets persist.vendor.camera.pkgname"

grep -q 'sessionParams clientName=' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/utils/SessionConfigurationUtils.cpp" \
    || die "sessionParams clientName injection missing"
ok "sessionParams clientName injection present"

grep -q 'appendXiaomiVeuxWhatsAppVendorTags' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/common/XiaomiVendorTagOverlay.cpp" \
    || die "Xiaomi vendor tag overlay missing"
ok "Xiaomi vendor tag overlay present"

grep -q 'is3rdLightWeightSupported=TRUE' \
    "${ROOT}/device/xiaomi/veux/configs/camera/camxoverridesettings.txt" \
    || die "is3rdLightWeightSupported not TRUE in camxoverridesettings"
grep -q 'logInfoMask=0x0' \
    "${ROOT}/device/xiaomi/veux/configs/camera/camxoverridesettings.txt" \
    || die "logInfoMask not 0 in camxoverridesettings"
grep -q 'overrideLogLevels=0x0' \
    "${ROOT}/device/xiaomi/veux/configs/camera/camxoverridesettings.txt" \
    || die "overrideLogLevels not 0 in camxoverridesettings"
ok "camxoverridesettings: is3rdLightWeight + log masks off"

CHI="${VENDOR}/vendor/lib64/hw/com.qti.chi.override.so"
CAM="${VENDOR}/vendor/lib64/hw/camera.qcom.so"
for blob in "$CHI" "$CAM"; do
    bname=$(basename "$blob")
    [[ -f "$blob" ]] || die "$bname missing"
    python3 - "$blob" <<'PY' || die "$bname missing persist.vendor.camera.pkgname string"
import sys
data = open(sys.argv[1], 'rb').read()
sys.exit(0 if b'persist.vendor.camera.pkgname' in data else 1)
PY
    python3 - "$blob" <<'PY' && die "$bname still contains vendor.camera.clientname (v1 broken hotfix)"
import sys
data = open(sys.argv[1], 'rb').read()
sys.exit(0 if b'vendor.camera.clientname' in data else 1)
PY
done
ok "CHI/CamX blobs use persist.vendor.camera.pkgname (29 chars)"

MIALGO="${VENDOR}/vendor/lib64/camera/components/com.qti.node.mialgocontrol.so"
[[ -f "$MIALGO" ]] || die "mialgocontrol.so missing"
readelf -d "$MIALGO" | grep -q 'libpiex_shim.so' \
    || die "mialgocontrol.so missing NEEDED libpiex_shim.so (run extract-files blob fixup)"
ok "mialgocontrol.so links libpiex_shim.so"

echo ""
echo "All local WhatsApp-fix checks passed."
echo "After flash, log must show:"
echo "  - remapping dataspace -> UNKNOWN"
echo "  - sessionParams clientName=com.whatsapp"
echo "  - getprop persist.vendor.cam.strip3pjfif = true"
echo "  - NO 'SetPackageName() can't find tag' / 'InitializeOverrideSession() can't find tag'"
echo "  - NO 'Pure AOSP Version build, switching current xml'"
echo "  - NO ZSLPreviewRaw_LT1080p_PLTV + provider SIGABRT on rear camera switch"
