#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO late_command orchestrator
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Runs inside the target chroot (in-target), after d-i has
#  finished. Called from the preseed late_command:
#    cp /cdrom/simple-cdd/snowfox-overlay.tar.gz /target/
#    ; in-target mkdir -p /snowfox-install
#    ; in-target tar -xzf /snowfox-overlay.tar.gz -C /snowfox-install
#    ; in-target bash /snowfox-install/late.sh
#
#  Order:
#    10-apt-policy.sh   — APT policy, sources, apt-get update
#    20-base.sh         — install.sh --phase iso-base
#    30-gpu.sh          — install.sh --phase iso-gpu (exit 75 tolerated)
#    40-firstboot.sh    — systemd unit + firstboot payload
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-install.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "=== SnowFoxOS late.sh $(date -Iseconds) ==="

# Detect the user created by debian-installer
TARGET_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
if [[ -z "$TARGET_USER" ]]; then
    echo "[late] FATAL: no UID 1000 user found" >&2
    exit 1
fi
export TARGET_USER

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
export TARGET_HOME
echo "[late] target user: $TARGET_USER ($TARGET_HOME)"

# Secure Boot warning (XanMod + NVIDIA DKMS are unsigned)
if [[ -d /sys/firmware/efi ]] \
   && [[ "$(od -An -t u1 -j 4 -N 1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tr -d ' ' || true)" == "1" ]]; then
    echo "[late] WARNING: Secure Boot is ENABLED."
    echo "[late]          XanMod and NVIDIA DKMS are unsigned; the"
    echo "[late]          installed system may not boot. Disable Secure"
    echo "[late]          Boot in the firmware before rebooting."
fi

# Locate overlay scripts — they sit next to this file
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Persist build metadata inside the installed system. firstboot and
# incident reports use /etc/snowfox-build to identify the ISO build.
if [[ -f "$HERE/build-stamp" ]]; then
    install -m 0644 "$HERE/build-stamp" /etc/snowfox-build
    echo "[late] build stamp installed: /etc/snowfox-build"
else
    echo "[late] WARNING: build-stamp missing from overlay" >&2
fi

run_step() {
    local script="$1"
    echo ""
    echo "[late] → $script"
    if bash "$HERE/$script"; then
        echo "[late] ✓ $script"
    else
        local rc=$?
        echo "[late] ✗ $script (exit $rc)"
        return $rc
    fi
}

run_step "10-apt-policy.sh" || { echo "[late] aborting"; exit 1; }
run_step "20-base.sh"       || { echo "[late] aborting"; exit 1; }

# 30-gpu.sh may exit 75 (no network). That is NOT fatal.
if run_step "30-gpu.sh"; then
    :
else
    rc=$?
    if (( rc == 75 )); then
        echo "[late] 30-gpu.sh: network unavailable (exit 75) — firstboot will retry"
    else
        echo "[late] 30-gpu.sh failed (exit $rc) — firstboot will retry"
    fi
fi

run_step "40-firstboot.sh" || { echo "[late] aborting"; exit 1; }

echo ""
echo "=== SnowFoxOS late.sh complete $(date -Iseconds) ==="