#!/usr/bin/env bash
# Static verification of MIUI Camera EIS/MCTF (black tiles) fix in source tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
VEUX="${ROOT}/device/xiaomi/veux"
VENDOR="${ROOT}/vendor/xiaomi/veux/proprietary"
FAIL=0

die() { echo "FAIL: $*"; FAIL=1; }
ok() { echo "OK: $*"; }

# 1) Gyro direct channel enabled
grep -q '^persist.vendor.sensors.support_direct_channel=true' \
    "${VEUX}/configs/properties/vendor.prop" || die "support_direct_channel not true"
grep -q 'persist.vendor.sensors.support_direct_channel true' \
    "${VEUX}/init/init.target.rc" || die "init.target.rc missing direct_channel setprop"

# 2) No API1 ZSL kill-switch
grep -qE '^camera\.disable_zsl_mode=true' "${VEUX}/configs/properties/vendor.prop" \
    && die "camera.disable_zsl_mode still set"

# 3) MCTF enabled in shipping camx config (Lunaris configs/camera overlay)
grep -q '^enableMCTF=TRUE' \
    "${VEUX}/configs/camera/camxoverridesettings.txt" || die "enableMCTF not TRUE in camxoverridesettings"
grep -q '^logInfoMask=0x0' \
    "${VEUX}/configs/camera/camxoverridesettings.txt" || die "logInfoMask not 0 in camxoverridesettings"
grep -q '^overrideLogLevels=0x0' \
    "${VEUX}/configs/camera/camxoverridesettings.txt" || die "overrideLogLevels not 0 in camxoverridesettings"

# 4) SSC first in hals.conf (direct channel owner)
first_line="$(grep -v '^#' "${VENDOR}/vendor/etc/sensors/hals.conf" | grep -v '^[[:space:]]*$' | head -1)"
[[ "${first_line}" == "sensors.ssc.so" ]] || die "hals.conf first line is '${first_line}', want sensors.ssc.so"

# 5) SEPolicy: camera HAL may call sensors HAL
grep -q 'hal_client_domain(hal_camera_default, hal_sensors)' \
    "${VEUX}/sepolicy/vendor/hal_camera_default.te" || die "missing hal_client_domain sensors"

# 6) sns_direct_channel latency
grep -q '"data": "1"' "${VENDOR}/vendor/etc/sensors/config/sns_direct_channel.json" \
    || die "sns_direct_channel latency_enable not 1"

# 7) device.mk installs stock blobs
grep -q 'vendor/etc/sensors/hals.conf:\$(TARGET_COPY_OUT_VENDOR)/etc/sensors/hals.conf' \
    "${VEUX}/device.mk" || die "device.mk missing hals.conf copy"
grep -q 'configs/camera/camxoverridesettings.txt:\$(TARGET_COPY_OUT_VENDOR)/etc/camera/camxoverridesettings.txt' \
    "${VEUX}/device.mk" || die "device.mk missing camx copy"

if [[ "${FAIL}" -eq 0 ]]; then
    ok "all MIUI Camera EIS/MCTF source checks passed"
    exit 0
fi
exit 1
