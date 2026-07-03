#!/usr/bin/env bash
# Extract Xiaomi thermal vendor blobs from OS1.0.13 EEA fastboot package.
# Requires: simg2img, lpunpack, debugfs (~12GB free for super unsparse)
set -eu

TGZ="${1:-/home/acer/romlar/veux_eea_global_images_OS1.0.13.0.TKCEUXM_20251227.0000.00_13.0_eea_e887aa14ef.tgz}"
OUT="${2:-/home/acer/romlar/stock-thermal-extract}"
VENDOR_PROP="${3:-/home/acer/romlar/lunaris/vendor/xiaomi/veux/proprietary/vendor/etc}"

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing command: $1"
        echo "  Arch: sudo pacman -S android-tools e2fsprogs ripgrep"
        exit 1
    fi
}

unsparse_if_needed() {
    local src="$1"
    local dst="$2"
    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        echo "  reuse $dst"
        return 0
    fi
    # Android sparse image magic: 0xED26FF3A
    if head -c 4 "$src" | od -An -tx1 | grep -q "3a ff 26 ed"; then
        echo "  simg2img $src -> $dst"
        simg2img "$src" "$dst"
    else
        echo "  copy raw $src -> $dst"
        cp -f "$src" "$dst"
    fi
}

if [ ! -f "$TGZ" ]; then
    echo "Missing: $TGZ"
    exit 1
fi

need_cmd simg2img
need_cmd lpunpack
need_cmd debugfs
need_cmd strings
need_cmd rg

mkdir -p "$OUT"
WORK="$OUT/work"
mkdir -p "$WORK"

SUPER_SPARSE="$WORK/veux_eea_global_images_OS1.0.13.0.TKCEUXM_13.0/images/super.img"
SUPER_RAW="$WORK/super.raw.img"

if [ ! -f "$SUPER_SPARSE" ]; then
    echo "[1/5] Extract super.img from tgz..."
    tar -xzf "$TGZ" -C "$WORK" \
        "veux_eea_global_images_OS1.0.13.0.TKCEUXM_13.0/images/super.img"
else
    echo "[1/5] Reuse existing super.img"
fi

echo "[2/5] Unsparse super.img..."
unsparse_if_needed "$SUPER_SPARSE" "$SUPER_RAW"

echo "[3/5] lpunpack super -> vendor_a..."
mkdir -p "$WORK/lpunpack"
lpunpack "$SUPER_RAW" "$WORK/lpunpack"

VIMG_SPARSE="$WORK/lpunpack/vendor_a.img"
VIMG_RAW="$WORK/lpunpack/vendor_a.raw.img"
if [ ! -f "$VIMG_SPARSE" ]; then
    echo "vendor_a.img not found under $WORK/lpunpack"
    ls -la "$WORK/lpunpack" 2>/dev/null || true
    exit 1
fi

echo "[4/5] Unsparse vendor_a if needed..."
unsparse_if_needed "$VIMG_SPARSE" "$VIMG_RAW"
VIMG="$VIMG_RAW"

echo "[5/5] Pull thermal etc from vendor..."
mkdir -p "$OUT/etc"
for f in \
    thermal-decrypt \
    thermal-region-map.conf \
    thermal-chg-only.conf \
    thermal-map.conf \
    thermal-normal.conf \
    thermal-video.conf \
    thermal-youtube.conf \
    thermald-devices.conf
do
    if debugfs -R "dump /etc/$f $OUT/etc/$f" "$VIMG" 2>/dev/null; then
        if [ -s "$OUT/etc/$f" ]; then
            echo "  OK $f ($(wc -c < "$OUT/etc/$f") bytes)"
        else
            echo "  EMPTY $f"
        fi
    else
        echo "  MISS $f"
    fi
done

echo ""
echo "Stock boot.img thermal driver strings..."
tar -xOzf "$TGZ" "veux_eea_global_images_OS1.0.13.0.TKCEUXM_13.0/images/boot.img" \
    | strings | rg -i "thermal.message|thermal_message|board.sensor|board-sensor" \
    | tee "$OUT/stock_boot_thermal_strings.txt"

echo ""
echo "Done. Review: $OUT/etc/"
echo "Install to vendor tree:"
echo "  cp -a $OUT/etc/thermal-* $VENDOR_PROP/"
echo "  cp -a $OUT/etc/thermal-decrypt $VENDOR_PROP/"
