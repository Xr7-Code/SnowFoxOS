#!/bin/bash
# ============================================================
#  SnowFoxOS — QEMU ISO Tester
#  Boots the installer ISO in a UEFI VM for fast testing.
#  Usage: bash test-iso.sh [path/to/SnowFoxOS-v3.iso]
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

set -e

# ── Config ───────────────────────────────────────────────────
ISO="${1:-SnowFoxOS-v3.iso}"
DISK_IMG="$(dirname "$ISO")/test-disk.qcow2"
DISK_SIZE="20G"
RAM="2048"          # MB — increase to 4096 if you have it
CPUS="2"
LOG="$(dirname "$ISO")/qemu-serial.log"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; RESET='\033[0m'

# ── Sanity checks ─────────────────────────────────────────────
if [[ ! -f "$ISO" ]]; then
    echo -e "${RED}[!] ISO not found: $ISO${RESET}"
    echo "    Build it first:  sudo bash iso-builder/build-iso.sh"
    echo "    Or pass a path:  bash test-iso.sh /path/to/SnowFoxOS-v3.iso"
    exit 1
fi

for cmd in qemu-system-x86_64 qemu-img; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[!] Missing: $cmd${RESET}"
        echo "    Install with:  sudo apt-get install qemu-system-x86 qemu-utils"
        exit 1
    fi
done

# Find OVMF (EFI firmware) — location differs by distro
OVMF=""
for path in \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/qemu/OVMF.fd; do
    [[ -f "$path" ]] && { OVMF="$path"; break; }
done

if [[ -z "$OVMF" ]]; then
    echo -e "${RED}[!] OVMF EFI firmware not found.${RESET}"
    echo "    Install with:  sudo apt-get install ovmf"
    exit 1
fi

# ── Fresh disk image ──────────────────────────────────────────
echo -e "${PURPLE}[SnowFox] Creating fresh ${DISK_SIZE} test disk: $DISK_IMG${RESET}"
qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" -q

# ── Boot ──────────────────────────────────────────────────────
echo -e "${GREEN}[SnowFox] Booting ISO in QEMU...${RESET}"
echo -e "          ISO:   $ISO"
echo -e "          Disk:  $DISK_IMG"
echo -e "          RAM:   ${RAM}MB   CPUs: $CPUS"
echo -e "          Log:   $LOG  (serial console)"
echo ""
echo -e "  ${PURPLE}Tip:${RESET} Ctrl+Alt+G  releases mouse from VM window"
echo -e "  ${PURPLE}Tip:${RESET} Ctrl+Alt+2  → QEMU monitor  (type 'quit' to exit)"
echo -e "  ${PURPLE}Tip:${RESET} Serial log updates live:  tail -f $LOG"
echo ""

qemu-system-x86_64 \
    -name "SnowFoxOS Test" \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp "$CPUS" \
    -m "$RAM" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive file="$DISK_IMG",format=qcow2,if=virtio \
    -cdrom "$ISO" \
    -boot order=dc,menu=on \
    -vga virtio \
    -display gtk,zoom-to-fit=on \
    -serial file:"$LOG" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -enable-kvm \
    2>/dev/null

echo -e "${GREEN}[SnowFox] VM closed. Serial log: $LOG${RESET}"
