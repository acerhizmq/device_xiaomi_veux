#!/bin/bash
#
# SPDX-FileCopyrightText: acerhizm
# SPDX-License-Identifier: Apache-2.0
#
# Applies the framework patches this device tree depends on, skipping any the ROM
# already has. Components:
#   leica     frameworks/base  MIUI camera StreamConfigurationMap constructors
#   torch     frameworks/av    torch strength extension (CameraProviderExtension)
#   whatsapp  frameworks/av    client package name session tag + the veux fix
#
# Usage: device/xiaomi/veux/tools/apply-patches.sh [--check] [--quiet] [component...]
#   component  leica, torch, whatsapp or all (default: all, or $VEUX_PATCHES)
#   --check    only report what is present and what would be applied
#   --quiet    print only when something is applied, fails or needs attention

set -u

CHECK=0
QUIET=0
WANT=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        --quiet) QUIET=1 ;;
        leica|torch|whatsapp) WANT+=("$arg") ;;
        all) WANT+=(leica torch whatsapp) ;;
        -h|--help) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done
if [ ${#WANT[@]} -eq 0 ]; then
    for c in ${VEUX_PATCHES:-all}; do
        case "$c" in
            all) WANT+=(leica torch whatsapp) ;;
            leica|torch|whatsapp) WANT+=("$c") ;;
            *) echo "VEUX_PATCHES: unknown component $c" >&2; exit 2 ;;
        esac
    done
fi
wants() { [[ " ${WANT[*]} " == *" $1 "* ]]; }

DT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOP="${ANDROID_BUILD_TOP:-$(cd "$DT/../../.." && pwd)}"
PATCHES="$DT/patches"
AV="$TOP/frameworks/av"
BASE="$TOP/frameworks/base"
LCS="$AV/services/camera/libcameraservice"
SCM="$BASE/core/java/android/hardware/camera2/params/StreamConfigurationMap.java"

LOG=""     # buffered output; --quiet prints it only if EVENT is set
EVENT=0
FAILED=0
SUMMARY=()
BACKUP_DONE=" "

say() { LOG+="$*"$'\n'; }

if [ ! -f "$TOP/build/envsetup.sh" ] || [ ! -d "$AV" ] || [ ! -d "$BASE" ]; then
    echo "veux patches: no Android source tree at $TOP (set ANDROID_BUILD_TOP)" >&2
    exit 2
fi

# --- ROM and release, for the log only -------------------------------------------------
roms=()
for d in rising axion evolution aospa infinity derp crdroid pixelos matrixx alpha \
         yaap voltage lunaris superior lineage; do
    [ -d "$TOP/vendor/$d" ] && roms+=("$d")
done
release="$(ls "$TOP/build/release/flag_values" 2>/dev/null | grep -E '^[a-z]{2}[0-9][a-z]$' | sort | tail -1)"
say "veux patches: ROM [${roms[*]:-unknown}] release [${release:-unknown}] components [${WANT[*]}]"

# --- Markers: is patch N of a component already in the tree? ---------------------------
has() { grep -qF -- "$2" "$1" 2>/dev/null; }

# Normalised constructor signatures, one per line, from Java source on stdin.
scm_sigs() {
    awk '/public StreamConfigurationMap\(/ { p = 1; s = "" }
         p { s = s " " $0 }
         p && /\)[[:space:]]*\{/ { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); print s; p = 0 }'
}

leica_has() {
    local want
    want="$(grep '^+' "$(ls "$PATCHES"/leica/000"$1"-*.patch)" | sed 's/^+//' | scm_sigs)"
    [ -n "$want" ] && scm_sigs < "$SCM" | grep -qxF -- "$want"
}

whatsapp_has() {
    case "$1" in
        1) has "$LCS/CameraService.cpp" "getCurrPackageName" ;;
        2) has "$AV/camera/cameraserver/Android.bp" '-DCAMERA_PACKAGE_NAME=' ;;
        3) has "$LCS/device3/Camera3Device.h" "setClientPackageName" ;;
    esac
}

torch_has() {
    case "$1" in
        1) [ -f "$LCS/common/CameraProviderExtension.h" ] ;;
        2) has "$LCS/common/CameraProviderManager.cpp" "flashInfoStrengthDefaultLevelEntry.count == 0 || supportsTorchStrengthControlExt()" ;;
        3) has "$LCS/common/CameraProviderExtension.cpp" "__attribute__((weak))" ;;
        4) has "$LCS/common/CameraProviderManager.cpp" "torchStrength > getTorchMaxStrengthLevelExt()" ;;
        5) has "$LCS/common/CameraProviderManager.cpp" "deviceInfo->mTorchStrengthLevel = torchStrength;" ;;
        6) has "$LCS/common/CameraProviderManager.cpp" "defaultLevel = getTorchDefaultStrengthLevelExt()" ;;
        7) has "$LCS/common/CameraProviderExtension.h" "setTorchStrengthLevelExt(int32_t torchStrength, bool enabled)" ;;
    esac
}

patch_num() { basename "$1" | sed 's/^0*\([0-9]*\)-.*/\1/'; }

# --- Applying ---------------------------------------------------------------------------
is_git_top() { [ "$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$1" && pwd -P)" ]; }

# apply_component <name> <repo dir>
apply_component() {
    local name="$1" dir="$2" label="$1 (${2#"$TOP"/})"
    local patches=() missing=() p

    for p in "$PATCHES/$name"/*.patch; do patches+=("$p"); done
    for p in "${patches[@]}"; do
        "${name}_has" "$(patch_num "$p")" || missing+=("$p")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        say "  $label: all ${#patches[@]} patches present"
        SUMMARY+=("$name|present|-|OK")
        return 0
    fi
    say "  $label: missing ${#missing[@]} of ${#patches[@]}:"
    for p in "${missing[@]}"; do say "    - $(basename "$p")"; done
    if [ $CHECK -eq 1 ]; then
        SUMMARY+=("$name|${#missing[@]} missing|would apply|-")
        return 0
    fi
    EVENT=1

    if is_git_top "$dir"; then
        local gitdir start env=()
        gitdir="$(cd "$dir" && cd "$(git rev-parse --git-dir)" && pwd)"
        if [ -d "$gitdir/rebase-apply" ] || [ -d "$gitdir/rebase-merge" ]; then
            say "  $label: SKIPPED, a git am/rebase is already in progress in $dir"
            SUMMARY+=("$name|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
        fi
        if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
            say "  $label: SKIPPED, $dir has uncommitted changes; commit or stash them and rerun"
            SUMMARY+=("$name|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
        fi
        start="$(git -C "$dir" rev-parse HEAD)"
        if [[ "$BACKUP_DONE" != *" $dir "* ]]; then
            local backup="veux-patches-backup-$(date +%Y%m%d-%H%M%S)-${start:0:7}"
            if ! git -C "$dir" branch "$backup" "$start" 2>/dev/null; then
                say "  $label: SKIPPED, could not create backup branch $backup"
                SUMMARY+=("$name|${#missing[@]} missing|skipped|FAIL"); FAILED=1; return 1
            fi
            BACKUP_DONE+="$dir "
            say "  ${2#"$TOP"/}: backup branch $backup"
        fi
        # git am needs a committer; use a local one only if git has none configured.
        if [ -z "$(git -C "$dir" config user.email)" ]; then
            env=(GIT_COMMITTER_NAME=veux-patches GIT_COMMITTER_EMAIL=veux-patches@localhost)
        fi
        for p in "${missing[@]}"; do
            if ! env "${env[@]}" git -C "$dir" am -3 -q "$p" >/dev/null 2>&1; then
                local f
                say "  $label: FAILED on $(basename "$p")"
                for f in $(git -C "$dir" diff --name-only --diff-filter=U); do say "      conflict: $f"; done
                git -C "$dir" am --abort >/dev/null 2>&1
                git -C "$dir" reset -q --hard "$start"
                say "  $label: rolled back to ${start:0:12}, nothing of $name applied"
                SUMMARY+=("$name|${#missing[@]} missing|conflict|FAIL"); FAILED=1; return 1
            fi
            say "    applied $(basename "$p")"
        done
    else
        # Not a git checkout: dry run, apply, undo this component in reverse on failure.
        local done_list=() d
        for p in "${missing[@]}"; do
            if ! patch -d "$dir" -p1 -N -s --dry-run < "$p" >/dev/null 2>&1 ||
                    ! patch -d "$dir" -p1 -N -s < "$p" >/dev/null 2>&1; then
                say "  $label: FAILED on $(basename "$p") (not a git repo, no 3-way merge)"
                for ((d = ${#done_list[@]} - 1; d >= 0; d--)); do
                    patch -d "$dir" -p1 -R -s < "${done_list[d]}" >/dev/null 2>&1
                done
                say "  $label: rolled back, nothing of $name applied"
                SUMMARY+=("$name|${#missing[@]} missing|conflict|FAIL"); FAILED=1; return 1
            fi
            done_list+=("$p")
            say "    applied $(basename "$p")"
        done
    fi

    for p in "${patches[@]}"; do
        if ! "${name}_has" "$(patch_num "$p")"; then
            say "  $label: $(basename "$p") still not detected after applying"
            SUMMARY+=("$name|${#missing[@]} missing|applied|CHECK"); FAILED=1; return 1
        fi
    done
    SUMMARY+=("$name|${#missing[@]} missing|applied|OK")
}

# --- Run --------------------------------------------------------------------------------
OLD_AV_FIX=0
grep -rqF "XiaomiVendorTagOverlay" "$LCS" 2>/dev/null && OLD_AV_FIX=1

wants leica && apply_component leica "$BASE"
for c in whatsapp torch; do
    wants "$c" || continue
    if [ $OLD_AV_FIX -eq 1 ]; then
        say "  $c: the old veux WhatsApp patch (XiaomiVendorTagOverlay) is in frameworks/av."
        say "    Revert it first; it overlaps both av components. frameworks/av left untouched."
        SUMMARY+=("$c|old fix present|-|FAIL"); FAILED=1; EVENT=1
    else
        apply_component "$c" "$AV"
    fi
done

# --- What the device tree will do with the result ------------------------------------
# device.mk always sets camera.package_name and libcameraservice.ext_lib.
if [ $CHECK -eq 0 ] && [ $OLD_AV_FIX -eq 0 ] && whatsapp_has 1 && ! whatsapp_has 3; then
    say "  WARNING: frameworks/av has the stock client package name hook without the veux fix."
    say "    With this device tree the camera reconfigures endlessly. Apply: whatsapp"
    EVENT=1; FAILED=1
fi
if [ $CHECK -eq 0 ] && torch_has 1 && ! torch_has 7; then
    say "  WARNING: frameworks/av has an older torch extension without setTorchStrengthLevelExt(int32_t, bool)."
    say "    The device tree's extension will not link or not be used. Apply: torch"
    EVENT=1; FAILED=1
fi
if ! torch_has 1; then
    say "  note: no torch extension in frameworks/av, the torch strength setting will be missing."
fi
if ! whatsapp_has 1; then
    say "  note: no client package name hook in frameworks/av, third-party camera apps (WhatsApp) may stay black."
fi

say ""
say "  component  before           action        result"
for row in "${SUMMARY[@]}"; do
    IFS='|' read -r c b a r <<< "$row"
    say "$(printf '  %-10s %-16s %-13s %s' "$c" "$b" "$a" "$r")"
done
[ $FAILED -eq 1 ] && EVENT=1

if [ $QUIET -eq 0 ] || [ $EVENT -eq 1 ]; then
    printf '%s' "$LOG"
fi
exit $FAILED
