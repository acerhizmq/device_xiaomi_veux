#!/usr/bin/env bash
# ==============================================================================
# Veux/Peux Camera Fix Fast Packager (WhatsApp + Leica Camera)
# Builds libcameraservice, cameraserver, libgui_camera_shim and creates a
# Magisk / KernelSU / Recovery compatible flashable zip in ~1-2 minutes.
# ==============================================================================
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
cd "$ROOT"

export LC_ALL=C
export LANG=C
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR="/home/acer/.ccache"

source build/envsetup.sh
lunch rising_veux-bp4a-userdebug

echo ">> [1/3] Building camera modules (libcameraservice, cameraserver, libgui_camera_shim)..."
m libcameraservice cameraserver libgui_camera_shim -j$(nproc)

echo ">> [2/3] Preparing Magisk/KernelSU module structure..."
TMP_DIR=$(mktemp -d)
MOD_DIR="$TMP_DIR/veux-camera-fix"
mkdir -p "$MOD_DIR/system/lib64" \
         "$MOD_DIR/system/bin" \
         "$MOD_DIR/system/priv-app/MiuiCamera/lib/arm64" \
         "$MOD_DIR/META-INF/com/google/android"

# module.prop
cat << 'EOF' > "$MOD_DIR/module.prop"
id=veux-camera-fix
name=Redmi Note 11 Pro 5G / Poco X4 Pro 5G Camera Fix
version=v2.0-WhatsApp-Leica
versionCode=20260825
author=acerhizm
description=Fixes WhatsApp rear camera crash (IMAGE_SIZE_VIOLATION) and Leica Camera UnsatisfiedLinkError on RisingOS (veux/peux).
EOF

# service.sh
cat << 'EOF' > "$MOD_DIR/service.sh"
#!/system/bin/sh
# Restart cameraserver once system boots
sleep 5
pkill -f cameraserver
EOF
chmod 755 "$MOD_DIR/service.sh"

# update-binary for TWRP / Recovery compatibility
cat << 'EOF' > "$MOD_DIR/META-INF/com/google/android/update-binary"
#!/sbin/sh
OUTFD=$2
ui_print() { echo -e "ui_print $1\nui_print" > /proc/self/fd/$OUTFD; }
ui_print "***********************************************"
ui_print " Veux Camera Fix (WhatsApp + Leica Camera)"
ui_print "***********************************************"
exit 0
EOF
chmod 755 "$MOD_DIR/META-INF/com/google/android/update-binary"
touch "$MOD_DIR/META-INF/com/google/android/updater-script"

# Copy compiled binaries & libraries
OUT_SYS="$ROOT/out/target/product/veux/system"
VENDOR_SYS="$ROOT/vendor/xiaomi/camera/proprietary/system"

cp "$OUT_SYS/lib64/libcameraservice.so" "$MOD_DIR/system/lib64/"
cp "$OUT_SYS/bin/cameraserver" "$MOD_DIR/system/bin/"
cp "$OUT_SYS/lib64/libgui_camera_shim.so" "$MOD_DIR/system/lib64/"
cp "$OUT_SYS/lib64/libgui_camera_shim.so" "$MOD_DIR/system/priv-app/MiuiCamera/lib/arm64/"

# Copy patched camera vendor libraries
cp "$VENDOR_SYS/lib64/libcamera_algoup_jni.xiaomi.so" "$MOD_DIR/system/lib64/"
cp "$VENDOR_SYS/lib64/libcamera_mianode_jni.xiaomi.so" "$MOD_DIR/system/lib64/"
cp "$VENDOR_SYS/lib64/libmisys_jni.xiaomi.so" "$MOD_DIR/system/lib64/"

echo ">> [3/3] Packaging Flashable Zip..."
ZIP_NAME="$ROOT/Veux-Camera-Fix-$(date +%Y%m%d_%H%M%S).zip"
cd "$MOD_DIR"
zip -r9 "$ZIP_NAME" . >/dev/null
rm -rf "$TMP_DIR"

echo "================================================================="
echo " SUCCESS! Flashable Zip created at:"
echo " $ZIP_NAME"
echo " You can flash this in KernelSU / Magisk / Recovery without building the full ROM."
echo "================================================================="
