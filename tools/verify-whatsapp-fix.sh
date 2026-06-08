#!/usr/bin/env bash
# Post-flash checks for WhatsApp rear-camera / CHI third-party path (veux).
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
VENDOR="${ROOT}/vendor/xiaomi/veux/proprietary"
die() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

[[ -d "$VENDOR" ]] || die "vendor tree missing at $VENDOR"

grep -q 'ro.build.product=veux' "${ROOT}/device/xiaomi/veux/lineage_veux.mk" \
    || die "ro.build.product=veux missing (CHI Pure AOSP XML fallback)"
ok "ro.build.product=veux in lineage_veux.mk"

grep -q 'persist.vendor.camera.strip_thirdparty_jfif=true' \
    "${ROOT}/device/xiaomi/veux/configs/properties/vendor.prop" \
    || die "strip_thirdparty_jfif not enabled"
ok "strip_thirdparty_jfif in vendor.prop"

grep -q 'persist.vendor.camera.clientname' \
    "${ROOT}/device/xiaomi/veux/sepolicy/vendor/property_contexts" \
    || die "clientname property_contexts missing"
ok "clientname sepolicy property_contexts"

grep -q 'updateVendorCameraClientNameProperty' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/CameraService.cpp" \
    || die "cameraserver clientname hook missing"
ok "cameraserver sets persist.vendor.camera.clientname"

grep -q 'appendXiaomiVeuxWhatsAppVendorTags' \
    "${ROOT}/frameworks/av/services/camera/libcameraservice/common/XiaomiVendorTagOverlay.cpp" \
    || die "Xiaomi vendor tag overlay missing"
ok "Xiaomi vendor tag overlay present"

grep -q 'is3rdLightWeightSupported=TRUE' \
    "${VENDOR}/vendor/etc/camera/camxoverridesettings.txt" \
    || die "is3rdLightWeightSupported not TRUE in stock camxoverridesettings"
ok "is3rdLightWeightSupported in camxoverridesettings"

echo ""
echo "All local WhatsApp-fix checks passed."
echo "After flash, log must show:"
echo "  - remapping dataspace -> UNKNOWN"
echo "  - thirdPartyYUVSnapshot=1 OR no 'thirdPartyYUVSnapshot vendor tag missing'"
echo "  - NO 'Pure AOSP Version build, switching current xml'"
echo "  - NO ZSLPreviewRaw_LT1080p / provider has died (rear camera 60s+)"
