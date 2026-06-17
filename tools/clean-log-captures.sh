#!/usr/bin/env bash
# Removes LOG-CAPTURE-* script output only. Does NOT touch AOSP source or out/.
set -euo pipefail

TOOLS="$(cd "$(dirname "$0")" && pwd)"
LUNARIS="$(cd "$TOOLS/../../../../.." && pwd)"

removed=0

rm_dir() {
    echo "rm -rf $1"
    rm -rf "$1"
    removed=$((removed + 1))
}

for dir in "$TOOLS"/lunaris-*-logs-* "$LUNARIS"/lunaris-*-logs-*; do
    [[ -d "$dir" ]] || continue
    rm_dir "$dir"
done

# Shallow dump trees at lunaris root (LOG-CAPTURE-VIDEO-FREEZE.bat layout)
if [[ -d "$LUNARIS/logcat" && -d "$LUNARIS/dumpsys" ]]; then
    for name in analysis anr bugreport dropbox dumpsys logcat tombstones tombstones_full props sysfs proc kernel device_info.txt; do
        [[ -e "$LUNARIS/$name" ]] && rm -rf "$LUNARIS/$name"
    done
    echo "Removed shallow capture tree under $LUNARIS"
    removed=$((removed + 1))
fi

echo "Done. Removed $removed capture folder(s)."
