#!/bin/bash
#
# SPDX-FileCopyrightText: acerhizm
# SPDX-License-Identifier: Apache-2.0
#
# Applies the framework patches this device tree depends on, skipping any the ROM
# already has:
#   frameworks/base  MIUI camera StreamConfigurationMap constructors (Leica camera)
#   frameworks/av    torch strength extension (CameraProviderExtension)
#   frameworks/av    client package name session tag + the veux fix (WhatsApp camera)
#
# Usage: device/xiaomi/veux/tools/apply-patches.sh [--check] [--quiet]
#   --check  only report what is present and what would be applied
#   --quiet  print only when something is applied or fails (used by vendorsetup.sh)

set -u

CHECK=0
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        --quiet) QUIET=1 ;;
        -h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

DT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOP="${ANDROID_BUILD_TOP:-$(cd "$DT/../../.." && pwd)}"
PATCHES="$DT/patches"
AV="$TOP/frameworks/av"
BASE="$TOP/frameworks/base"
LCS="$AV/services/camera/libcameraservice"
SCM="$BASE/core/java/android/hardware/camera2/params/StreamConfigurationMap.java"

LOG=""            # buffered output, flushed in --quiet mode only if something happened
EVENT=0           # set when a patch was applied or something failed
FAILED=0
SUMMARY=()

say() { LOG+="$*"$'\n'; }
note_event() { EVENT=1; }

if [ ! -f "$TOP/build/envsetup.sh" ] || [ ! -d "$AV" ] || [ ! -d "$BASE" ]; then
    echo "veux patches: no Android source tree at $TOP (set ANDROID_BUILD_TOP)" >&2
    exit 2
fi

# --- ROM and Android release, for the log only ---------------------------------------
roms=()
for d in rising axion evolution aospa infinity derp crdroid pixelos matrixx alpha \
         yaap voltage lunaris superior lineage; do
    [ -d "$TOP/vendor/$d" ] && roms+=("$d")
done
release="$(ls "$TOP/build/release/flag_values" 2>/dev/null | grep -E '^[a-z]{2}[0-9][a-z]$' | sort | tail -1)"
say "veux patches: ROM [${roms[*]:-unknown}] release [${release:-unknown}] at $TOP"

# --- Markers: does the tree already contain step N? -----------------------------------
has() { grep -qF -- "$2" "$1" 2>/dev/null; }

# Normalised constructor signatures, one per line, from Java source on stdin.
scm_sigs() {
    awk '/public StreamConfigurationMap\(/ { p = 1; s = "" }
         p { s = s " " $0 }
         p && /\)[[:space:]]*\{/ { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); print s; p = 0 }'
}

# The constructor a frameworks/base patch adds is already in StreamConfigurationMap.java.
has_ctor_of() {
    local want
    want="$(grep '^+' "$1" | sed 's/^+//' | scm_sigs)"
    [ -n "$want" ] && scm_sigs < "$SCM" | grep -qxF -- "$want"
}

av_has() {
    case "$1" in
        1) has "$LCS/CameraService.cpp" "getCurrPackageName" ;;
        2) has "$AV/camera/cameraserver/Android.bp" '-DCAMERA_PACKAGE_NAME=' ;;
        3) [ -f "$LCS/common/CameraProviderExtension.h" ] ;;
        4) has "$LCS/common/CameraProviderManager.cpp" "flashInfoStrengthDefaultLevelEntry.count == 0 || supportsTorchStrengthControlExt()" ;;
        5) has "$LCS/common/CameraProviderExtension.cpp" "__attribute__((weak))" ;;
        6) has "$LCS/common/CameraProviderManager.cpp" "defaultLevel = getTorchDefaultStrengthLevelExt()" ;;
        7) has "$LCS/common/CameraProviderExtension.h" "setTorchStrengthLevelExt(int32_t torchStrength, bool enabled)" ;;
        8) has "$LCS/device3/Camera3Device.h" "setClientPackageName" ;;
    esac
}

base_has() {
    has_ctor_of "$(ls "$PATCHES"/frameworks_base/000"$1"-*.patch)"
}

# --- Applying ---------------------------------------------------------------------------
# apply_repo <label> <repo dir> <patch dir> <marker fn>
apply_repo() {
    local label="$1" dir="$2" pdir="$3" marker="$4"
    local patches=() missing=() p n

    for p in "$pdir"/*.patch; do patches+=("$p"); done
    for p in "${patches[@]}"; do
        n="$(basename "$p" | sed 's/^0*\([0-9]*\)-.*/\1/')"
        "$marker" "$n" || missing+=("$p")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        say "  $label: all ${#patches[@]} patches present"
        SUMMARY+=("$label|present|-|OK")
        return 0
    fi

    say "  $label: missing ${#missing[@]} of ${#patches[@]}:"
    for p in "${missing[@]}"; do say "    - $(basename "$p")"; done

    if [ $CHECK -eq 1 ]; then
        SUMMARY+=("$label|${#missing[@]} missing|would apply|-")
        return 0
    fi
    note_event

    local is_git=0 start=""
    if [ "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$dir" && pwd -P)" ]; then
        is_git=1
    fi

    if [ $is_git -eq 1 ]; then
        local gitdir
        gitdir="$(git -C "$dir" rev-parse --git-dir)"
        case "$gitdir" in /*) ;; *) gitdir="$dir/$gitdir" ;; esac
        if [ -d "$gitdir/rebase-apply" ] || [ -d "$gitdir/rebase-merge" ]; then
            say "  $label: SKIPPED, a git am/rebase is already in progress in $dir"
            SUMMARY+=("$label|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
        fi
        if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
            say "  $label: SKIPPED, $dir has uncommitted changes; commit or stash them and rerun"
            SUMMARY+=("$label|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
        fi
        start="$(git -C "$dir" rev-parse HEAD)"
        local backup="veux-patches-backup-$(date +%Y%m%d-%H%M%S)-${start:0:7}"
        if ! git -C "$dir" branch "$backup" "$start" 2>/dev/null; then
            say "  $label: SKIPPED, could not create backup branch $backup"
            SUMMARY+=("$label|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
        fi
        say "  $label: backup branch $backup"

        # git am needs a committer; use a local one only if git has none configured.
        local env=()
        if [ -z "$(git -C "$dir" config user.email)" ]; then
            env=(GIT_COMMITTER_NAME=veux-patches GIT_COMMITTER_EMAIL=veux-patches@localhost)
        fi
        for p in "${missing[@]}"; do
            if ! env "${env[@]}" git -C "$dir" am -3 -q "$p" >/dev/null 2>&1; then
                say "  $label: FAILED on $(basename "$p"):"
                local f
                for f in $(git -C "$dir" diff --name-only --diff-filter=U); do say "      conflict: $f"; done
                git -C "$dir" am --abort >/dev/null 2>&1
                git -C "$dir" reset -q --hard "$start"
                say "  $label: $dir restored to $start, nothing applied"
                SUMMARY+=("$label|${#missing[@]} missing|conflict|FAIL"); FAILED=1; return 1
            fi
            say "    applied $(basename "$p")"
        done
    else
        # Not a git checkout: plain patching, dry run first, undone in reverse on failure.
        local done_list=() d
        for p in "${missing[@]}"; do
            if ! patch -d "$dir" -p1 -N -s --dry-run < "$p" >/dev/null 2>&1 ||
                    ! patch -d "$dir" -p1 -N -s < "$p" >/dev/null 2>&1; then
                say "  $label: FAILED on $(basename "$p") (not a git repo, no 3-way merge)"
                for ((d = ${#done_list[@]} - 1; d >= 0; d--)); do
                    patch -d "$dir" -p1 -R -s < "${done_list[d]}" >/dev/null 2>&1
                done
                say "  $label: earlier patches of this run undone"
                SUMMARY+=("$label|${#missing[@]} missing|conflict|FAIL"); FAILED=1; return 1
            fi
            done_list+=("$p")
            say "    applied $(basename "$p")"
        done
    fi

    for p in "${patches[@]}"; do
        n="$(basename "$p" | sed 's/^0*\([0-9]*\)-.*/\1/')"
        if ! "$marker" "$n"; then
            say "  $label: $(basename "$p") still not detected after applying"
            SUMMARY+=("$label|${#missing[@]} missing|applied|CHECK"); FAILED=1; return 1
        fi
    done
    SUMMARY+=("$label|${#missing[@]} missing|applied|OK")
}

# --- Run --------------------------------------------------------------------------------
if grep -rqF "XiaomiVendorTagOverlay" "$LCS" 2>/dev/null; then
    say "  frameworks/av: the old veux WhatsApp patch (XiaomiVendorTagOverlay) is applied."
    say "  Revert it first; it conflicts with the current fix. frameworks/av left untouched."
    SUMMARY+=("frameworks/av|old fix present|-|FAIL"); FAILED=1; note_event
else
    apply_repo "frameworks/av" "$AV" "$PATCHES/frameworks_av" av_has
fi
apply_repo "frameworks/base" "$BASE" "$PATCHES/frameworks_base" base_has

say ""
say "  component        before           action        result"
for row in "${SUMMARY[@]}"; do
    IFS='|' read -r c b a r <<< "$row"
    say "$(printf '  %-16s %-16s %-13s %s' "$c" "$b" "$a" "$r")"
done
[ $FAILED -eq 1 ] && note_event

if [ $QUIET -eq 0 ] || [ $EVENT -eq 1 ]; then
    printf '%s' "$LOG"
fi
exit $FAILED
