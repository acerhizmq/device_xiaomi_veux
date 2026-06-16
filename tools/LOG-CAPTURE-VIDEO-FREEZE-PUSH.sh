#!/usr/bin/env bash
# Push on-phone video stutter capture script to /data/local/tmp/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${ROOT}/LOG-CAPTURE-VIDEO-FREEZE-PHONE.sh"
REMOTE="/data/local/tmp/vf-cap.sh"

command -v adb >/dev/null || { echo "ERROR: adb not found"; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "ERROR: missing $SCRIPT"; exit 1; }

adb get-state >/dev/null 2>&1 || { echo "ERROR: device not connected"; exit 1; }

adb root >/dev/null 2>&1 || true
sleep 1
adb push "$SCRIPT" "$REMOTE"
adb shell chmod 644 "$REMOTE"
echo "OK: pushed to $REMOTE"
echo "On phone (root shell): sh $REMOTE"
echo "Or watch mode:         sh $REMOTE watch"
