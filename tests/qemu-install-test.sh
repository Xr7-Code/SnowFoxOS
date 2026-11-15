#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — QEMU install test
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Usage:
#    sudo bash tests/qemu-install-test.sh --offline
#    sudo bash tests/qemu-install-test.sh --online
#
#  Requires: qemu-system-x86_64, qemu-utils, curl, xorriso
#  The script downloads a Debian 12 netinst ISO, creates a QEMU
#  disk, boots the installer, and (in --online mode) allows the
#  install to complete with network access.
#
#  It is *not* fully automated — expect to interact with the
#  Debian installer. The expect script (tests/expect-install.exp)
#  can drive the interactive installer once it is running.
# ============================================================

set -euo pipefail

MODE=""
case "${1:-}" in
    --offline|--online) MODE="${1#--}" ;;
    *) echo "usage: $0 --offline|--online" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/tests/.qemu}"
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_FILE="$WORK_DIR/debian-12-netinst.iso"
DISK_FILE="$WORK_DIR/snowfox-test.qcow2"
DISK_SIZE="20G"
RAM="4096"
CPUS="2"

mkdir -p "$WORK_DIR"

echo "=== SnowFoxOS v4 — QEMU install test ($MODE) ==="

# 1. ISO herunterladen (falls nicht vorhanden)
if [[ ! -f "$ISO_FILE" ]]; then
    echo "→ downloading Debian 12 netinst ISO (~630 MB)…"
    curl -fL --progress-bar "$ISO_URL" -o "$ISO_FILE"
else
    echo "→ ISO cached: $ISO_FILE"
fi

# 2. Disk anlegen (falls nicht vorhanden)
if [[ ! -f "$DISK_FILE" ]]; then
    echo "→ creating $DISK_SIZE qcow2 disk…"
    qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
else
    echo "→ disk cached: $DISK_FILE"
fi

# 3. Netzwerk-Modus
if [[ "$MODE" == "offline" ]]; then
    NET_ARGS=(-nic none)
    echo "→ OFFLINE mode: no network in guest"
else
    NET_ARGS=(-nic user,model=virtio-net-pci)
    echo "→ ONLINE mode: user-mode network in guest"
fi

# 4. QEMU starten
echo "→ starting QEMU (Ctrl+A X to quit)…"
echo "  boot the installer, set up a minimal Debian 12,"
echo "  then clone the SnowFoxOS repo and run install.sh"
echo ""

exec qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CPUS" \
    -m "$RAM" \
    -drive file="$DISK_FILE",format=qcow2,if=virtio \
    -cdrom "$ISO_FILE" \
    -boot d \
    "${NET_ARGS[@]}" \
    -vga qxl \
    -display gtk