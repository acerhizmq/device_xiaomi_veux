#!/usr/bin/env bash
# Push WhatsApp on-device logger to phone (run from PC, once per flash).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${ROOT}/LOG-CAPTURE-WHATSAPP-PHONE.sh"
DEST="/data/local/tmp/wp-cap.sh"

command -v adb >/dev/null || { echo "adb yok"; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "cihaz bagli degil"; exit 1; }

adb root >/dev/null 2>&1 || true
sleep 1
adb push "$SRC" "$DEST"
adb shell chmod 644 "$DEST"

echo "OK: $DEST"
echo ""
echo "Telefonda (root shell veya Termux adb shell su):"
echo "  sh /data/local/tmp/wp-cap.sh"
echo "  sh /data/local/tmp/wp-cap.sh watch"
