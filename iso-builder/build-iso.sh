#!/bin/bash
# ============================================================
#  SnowFoxOS — ISO Builder
#  Builds bootable SnowFoxOS installer ISO using /var/tmp
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

set -e

if [[ $EUID -ne 0 ]]; then
    echo "[-] Please run with sudo: sudo bash iso-builder/build-iso.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/var/tmp/snowfox-iso-build"
CHROOT_DIR="$BUILD_DIR/chroot"
ISO_ROOT="$BUILD_DIR/iso"

PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${PURPLE}[SnowFox] Starting ISO build process in $BUILD_DIR...${RESET}"

# 1. Ensure dependencies on host
echo -e "${PURPLE}[SnowFox] Checking host build dependencies...${RESET}"
apt-get update -qq
apt-get install -y -qq debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools wget curl git parted dialog whiptail

# 2. Prepare build dirs
rm -rf "$BUILD_DIR"
mkdir -p "$CHROOT_DIR" "$ISO_ROOT/boot/grub" "$ISO_ROOT/live" "$BUILD_DIR/cache" "$CHROOT_DIR/opt/snowfox-packages"

# Download Fresh Editor on host to guarantee availability
echo -e "${PURPLE}[SnowFox] Downloading Fresh Editor package...${RESET}"
wget -q -O "$BUILD_DIR/cache/fresh-editor.deb" https://github.com/sinelaw/fresh/releases/download/v0.5.2/fresh-editor_0.5.2-1_amd64.deb || true

# 3. Bootstrap Debian 12 (Bookworm) minimal system
echo -e "${PURPLE}[SnowFox] Bootstrapping Debian 12 minimal system (this may take a minute)...${RESET}"
debootstrap --arch=amd64 bookworm "$CHROOT_DIR" http://ftp.de.debian.org/debian

# 4. Configure chroot sources & mounts
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

cat << 'EOF' > "$CHROOT_DIR/etc/apt/sources.list"
deb http://ftp.de.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /sys "$CHROOT_DIR/sys"
mount --bind /run "$CHROOT_DIR/run"

cleanup_mounts() {
    umount -lf "$CHROOT_DIR/run" 2>/dev/null || true
    umount -lf "$CHROOT_DIR/dev" 2>/dev/null || true
    umount -lf "$CHROOT_DIR/proc" 2>/dev/null || true
    umount -lf "$CHROOT_DIR/sys" 2>/dev/null || true
}
trap cleanup_mounts EXIT

# Copy cached deb into chroot
if [ -f "$BUILD_DIR/cache/fresh-editor.deb" ]; then
    cp "$BUILD_DIR/cache/fresh-editor.deb" "$CHROOT_DIR/opt/snowfox-packages/"
fi

# 5. Install live & base packages in chroot + cache apt packages for offline install
echo -e "${PURPLE}[SnowFox] Installing packages and live-boot support...${RESET}"
cat << 'EOF' > "$CHROOT_DIR/tmp/chroot-setup.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export PATH="$PATH:/usr/sbin:/sbin:/usr/bin:/bin"
apt-get update -qq

# 1. Install kernel, initramfs, live-boot & essential system tools first
apt-get install -y -qq \
    initramfs-tools initramfs-tools-core linux-image-amd64 linux-headers-amd64 \
    grub-pc grub-efi-amd64 systemd-sysv locales console-setup \
    keyboard-configuration dialog whiptail parted dosfstools \
    ntfs-3g e2fsprogs curl wget git \
    live-boot live-config live-boot-initramfs-tools squashfs-tools || apt-get install -y -f -qq

# Ensure kernel is present
if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
    apt-get install -y -qq linux-image-amd64
fi

# 2. Install desktop environment & applications
apt-get install -y -qq \
    network-manager i3 polybar rofi dunst i3lock kitty \
    pipewire pipewire-audio wireplumber pcmanfm mc file jq \
    xz-utils zip unzip python3 python3-pip || apt-get install -y -f -qq

if [ -f /opt/snowfox-packages/fresh-editor.deb ]; then
    dpkg -i /opt/snowfox-packages/fresh-editor.deb || apt-get -fy install -y -qq
fi

# 3. Crucial: Update initramfs AFTER live-boot is installed so /scripts/live is baked in!
for vmlinuz in /boot/vmlinuz-*; do
    if [ -f "$vmlinuz" ]; then
        kver=$(basename "$vmlinuz" | sed 's/vmlinuz-//')
        update-initramfs -u -k "$kver" || update-initramfs -c -k "$kver"
    fi
done
apt-get clean
EOF

chmod +x "$CHROOT_DIR/tmp/chroot-setup.sh"
chroot "$CHROOT_DIR" /tmp/chroot-setup.sh
rm -f "$CHROOT_DIR/tmp/chroot-setup.sh"

# 6. Copy SnowFoxOS project into chroot & setup live environment / TUI installer
echo -e "${PURPLE}[SnowFox] Copying SnowFoxOS project and installer scripts...${RESET}"
mkdir -p "$CHROOT_DIR/opt/SnowFoxOS"
cp -r "$PROJECT_ROOT"/* "$CHROOT_DIR/opt/SnowFoxOS/"

# Copy iso-builder installer scripts into chroot
mkdir -p "$CHROOT_DIR/usr/local/bin"
cp "$SCRIPT_DIR/installer/tui-installer.sh" "$CHROOT_DIR/usr/local/bin/snowfox-installer"
chmod +x "$CHROOT_DIR/usr/local/bin/snowfox-installer"

cp "$SCRIPT_DIR/installer/auto-install.sh" "$CHROOT_DIR/usr/local/bin/snowfox-auto-install"
chmod +x "$CHROOT_DIR/usr/local/bin/snowfox-auto-install"

# Create systemd service for live boot autostarting installer
cat << 'EOF' > "$CHROOT_DIR/etc/systemd/system/snowfox-live-installer.service"
[Unit]
Description=SnowFoxOS TUI Live Installer
After=network.target systemd-user-sessions.service

[Service]
Type=simple
ExecStart=/usr/local/bin/snowfox-installer
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

chroot "$CHROOT_DIR" systemctl enable snowfox-live-installer.service
chroot "$CHROOT_DIR" systemctl mask getty@tty1

# Extract kernel and initrd before unmounting
VMLINUZ_SRC="$(ls -1 "$CHROOT_DIR"/boot/vmlinuz-* 2>/dev/null | head -n 1)"
INITRD_SRC="$(ls -1 "$CHROOT_DIR"/boot/initrd.img-* 2>/dev/null | head -n 1)"

if [[ -n "$VMLINUZ_SRC" && -n "$INITRD_SRC" ]]; then
    cp "$VMLINUZ_SRC" "$ISO_ROOT/live/vmlinuz"
    cp "$INITRD_SRC" "$ISO_ROOT/live/initrd.img"
else
    echo "ERROR: Kernel vmlinuz or initrd not found in chroot boot!"
    ls -la "$CHROOT_DIR/boot" || true
    exit 1
fi

# Unmount virtual filesystems before squashfs compression
umount -lf "$CHROOT_DIR/run" 2>/dev/null || true
umount -lf "$CHROOT_DIR/dev" 2>/dev/null || true
umount -lf "$CHROOT_DIR/proc" 2>/dev/null || true
umount -lf "$CHROOT_DIR/sys" 2>/dev/null || true

# 7. Compress chroot to squashfs
echo -e "${PURPLE}[SnowFox] Compressing filesystem to squashfs...${RESET}"
mkdir -p "$ISO_ROOT/live"
mksquashfs "$CHROOT_DIR" "$ISO_ROOT/live/filesystem.squashfs" -comp gzip -processors $(nproc)

# 8. Setup robust GRUB bootloader for ISO (Standard text console output)
mkdir -p "$ISO_ROOT/boot/grub"

cat << 'EOF' > "$ISO_ROOT/boot/grub/grub.cfg"
set timeout=5
set default=0

# Force standard text console mode to prevent video mode probing warnings
terminal_input console
terminal_output console

menuentry "SnowFoxOS v3 — Start Live Installer" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "SnowFoxOS v3 — Safe Graphics Mode" {
    linux /live/vmlinuz boot=live components nomodeset quiet
    initrd /live/initrd.img
}

menuentry "Boot Existing Operating System" {
    exit
}
EOF

# 9. Build ISO image (default automatic module handling)
OUTPUT_ISO="$PROJECT_ROOT/SnowFoxOS-v3.iso"
echo -e "${PURPLE}[SnowFox] Generating bootable ISO: $OUTPUT_ISO...${RESET}"

grub-mkrescue -o "$OUTPUT_ISO" "$ISO_ROOT"

echo -e "${GREEN}[OK] SnowFoxOS ISO built successfully at: $OUTPUT_ISO${RESET}"
