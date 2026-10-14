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
apt-get install -y -qq \
    debootstrap squashfs-tools xorriso \
    grub-pc-bin grub-efi-amd64-bin mtools \
    dosfstools wget curl git parted dialog whiptail

# 2. Prepare build dirs
rm -rf "$BUILD_DIR"
mkdir -p "$CHROOT_DIR" "$ISO_ROOT/boot/grub" "$ISO_ROOT/live" \
         "$BUILD_DIR/cache" "$CHROOT_DIR/opt/snowfox-packages"

# Download Fresh Editor on host to guarantee availability
echo -e "${PURPLE}[SnowFox] Downloading Fresh Editor package...${RESET}"
wget -q -O "$BUILD_DIR/cache/fresh-editor.deb" \
    https://github.com/sinelaw/fresh/releases/download/v0.5.2/fresh-editor_0.5.2-1_amd64.deb || true

# 3. Bootstrap Debian 12 (Bookworm) minimal system
echo -e "${PURPLE}[SnowFox] Bootstrapping Debian 12 minimal system (this may take a minute)...${RESET}"
debootstrap --arch=amd64 bookworm "$CHROOT_DIR" http://ftp.de.debian.org/debian

# 4. Configure chroot sources & mounts
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

cat << 'EOF' > "$CHROOT_DIR/etc/apt/sources.list"
deb http://ftp.de.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

mount --bind /dev  "$CHROOT_DIR/dev"
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /sys  "$CHROOT_DIR/sys"
mount --bind /run  "$CHROOT_DIR/run"

cleanup_mounts() {
    umount -lf "$CHROOT_DIR/run"  2>/dev/null || true
    umount -lf "$CHROOT_DIR/dev"  2>/dev/null || true
    umount -lf "$CHROOT_DIR/proc" 2>/dev/null || true
    umount -lf "$CHROOT_DIR/sys"  2>/dev/null || true
}
trap cleanup_mounts EXIT

# Copy cached deb into chroot
if [ -f "$BUILD_DIR/cache/fresh-editor.deb" ]; then
    cp "$BUILD_DIR/cache/fresh-editor.deb" "$CHROOT_DIR/opt/snowfox-packages/"
fi

# 5. Install packages inside chroot
echo -e "${PURPLE}[SnowFox] Installing packages and live-boot support...${RESET}"
cat << 'EOF' > "$CHROOT_DIR/tmp/chroot-setup.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export PATH="$PATH:/usr/sbin:/sbin:/usr/bin:/bin"
set -e

apt-get update -qq

# STEP 1: Install live-boot hooks and initramfs-tools FIRST — before the kernel.
# This is critical: when linux-image is installed its postinst runs update-initramfs.
# If live-boot-initramfs-tools is not yet present at that moment, /scripts/live will
# be missing from the initramfs → "/init: can't open /scripts/live" → kernel panic.
apt-get install -y -qq \
    initramfs-tools initramfs-tools-core \
    live-boot live-config live-boot-initramfs-tools \
    systemd-sysv locales console-setup keyboard-configuration

# STEP 2: Install the kernel — now live-boot hooks are already in place, so the
# initramfs built by linux-image's postinst will contain /scripts/live correctly.
apt-get install -y -qq linux-image-amd64

# Verify kernel is present
if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
    echo "ERROR: Kernel not found after installation!" >&2
    exit 1
fi

# STEP 3: Install remaining system & desktop packages
apt-get install -y -qq \
    dialog whiptail parted dosfstools ntfs-3g e2fsprogs \
    curl wget git \
    squashfs-tools debootstrap \
    network-manager \
    i3 polybar rofi dunst i3lock kitty \
    pipewire pipewire-audio wireplumber \
    pcmanfm mc file jq \
    xz-utils zip unzip python3

if [ -f /opt/snowfox-packages/fresh-editor.deb ]; then
    dpkg -i /opt/snowfox-packages/fresh-editor.deb || apt-get -fy install -qq
fi

# STEP 4: Rebuild initramfs as a final safety pass to ensure everything is baked in.
# This catches any edge case where hook ordering during apt may have been off.
for vmlinuz in /boot/vmlinuz-*; do
    [ -f "$vmlinuz" ] || continue
    kver=$(basename "$vmlinuz" | sed 's/vmlinuz-//')
    echo "[SnowFox] Rebuilding initramfs for kernel $kver..."
    update-initramfs -u -k "$kver" || update-initramfs -c -k "$kver"
done

# Verify /scripts/live is present in the initramfs.
# lsinitramfs (from initramfs-tools) correctly handles modern Debian initramfs
# files, which are concatenated (microcode prefix + compressed cpio) and cannot
# be reliably inspected with plain zcat | cpio -t.
INITRD=$(ls /boot/initrd.img-* 2>/dev/null | head -n 1)
if [ -n "$INITRD" ]; then
    if lsinitramfs "$INITRD" 2>/dev/null | grep -q "scripts/live"; then
        echo "[SnowFox] OK: /scripts/live confirmed in initramfs."
    else
        echo "ERROR: /scripts/live NOT found in initramfs — live-boot is broken!" >&2
        exit 1
    fi
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

chmod +x "$CHROOT_DIR/tmp/chroot-setup.sh"
chroot "$CHROOT_DIR" /tmp/chroot-setup.sh
rm -f "$CHROOT_DIR/tmp/chroot-setup.sh"

# 6. Copy SnowFoxOS project & installer scripts into chroot
echo -e "${PURPLE}[SnowFox] Copying SnowFoxOS project and installer scripts...${RESET}"
mkdir -p "$CHROOT_DIR/opt/SnowFoxOS"
cp -r "$PROJECT_ROOT"/* "$CHROOT_DIR/opt/SnowFoxOS/"

mkdir -p "$CHROOT_DIR/usr/local/bin"
cp "$SCRIPT_DIR/installer/tui-installer.sh"  "$CHROOT_DIR/usr/local/bin/snowfox-installer"
cp "$SCRIPT_DIR/installer/auto-install.sh"   "$CHROOT_DIR/usr/local/bin/snowfox-auto-install"
chmod +x "$CHROOT_DIR/usr/local/bin/snowfox-installer" \
         "$CHROOT_DIR/usr/local/bin/snowfox-auto-install"

# Configure passwordless sudo for live user 'user'
echo "user ALL=(ALL) NOPASSWD: ALL" > "$CHROOT_DIR/etc/sudoers.d/snowfox"
chmod 0440 "$CHROOT_DIR/etc/sudoers.d/snowfox"

# Auto-start installer in live user's profile via sudo.
# live-config creates default user 'user' and autologins on tty1.
# Writing to /etc/skel/.profile ensures user 'user' gets the auto-start script.
cat << 'EOF' > "$CHROOT_DIR/etc/skel/.profile"
# SnowFoxOS live installer — auto-start
if [ -t 0 ] && [ -x /usr/local/bin/snowfox-installer ]; then
    sudo /usr/local/bin/snowfox-installer
fi
EOF
cp "$CHROOT_DIR/etc/skel/.profile" "$CHROOT_DIR/etc/skel/.bash_profile"

# Also pre-create /home/user and set profile files directly
mkdir -p "$CHROOT_DIR/home/user"
cp "$CHROOT_DIR/etc/skel/.profile" "$CHROOT_DIR/home/user/.profile"
cp "$CHROOT_DIR/etc/skel/.bash_profile" "$CHROOT_DIR/home/user/.bash_profile"
chown -R 1000:1000 "$CHROOT_DIR/home/user"

# 7. Extract kernel & initrd before squashfs compression
VMLINUZ_SRC="$(ls -1 "$CHROOT_DIR"/boot/vmlinuz-* 2>/dev/null | head -n 1)"
INITRD_SRC="$(ls -1  "$CHROOT_DIR"/boot/initrd.img-* 2>/dev/null | head -n 1)"

if [[ -n "$VMLINUZ_SRC" && -n "$INITRD_SRC" ]]; then
    # Verify kernel and initrd versions match
    KVER_VMLINUZ=$(basename "$VMLINUZ_SRC" | sed 's/vmlinuz-//')
    KVER_INITRD=$(basename "$INITRD_SRC" | sed 's/initrd.img-//')
    if [[ "$KVER_VMLINUZ" != "$KVER_INITRD" ]]; then
        echo -e "${RED}ERROR: Kernel/initrd version mismatch: $KVER_VMLINUZ vs $KVER_INITRD${RESET}"
        exit 1
    fi
    echo -e "${PURPLE}[SnowFox] Kernel: $KVER_VMLINUZ${RESET}"
    cp "$VMLINUZ_SRC" "$ISO_ROOT/live/vmlinuz"
    cp "$INITRD_SRC"  "$ISO_ROOT/live/initrd.img"
else
    echo -e "${RED}ERROR: Kernel or initrd not found in chroot /boot!${RESET}"
    ls -la "$CHROOT_DIR/boot" || true
    exit 1
fi

# Unmount virtual filesystems before squashfs compression
umount -lf "$CHROOT_DIR/run"  2>/dev/null || true
umount -lf "$CHROOT_DIR/dev"  2>/dev/null || true
umount -lf "$CHROOT_DIR/proc" 2>/dev/null || true
umount -lf "$CHROOT_DIR/sys"  2>/dev/null || true

# 8. Compress chroot to squashfs
echo -e "${PURPLE}[SnowFox] Compressing filesystem to squashfs...${RESET}"
mksquashfs "$CHROOT_DIR" "$ISO_ROOT/live/filesystem.squashfs" \
    -comp gzip -processors "$(nproc)"

# 9. GRUB bootloader config
#    FIX: insmod all_video + set gfxmode=auto prevents the
#    "no suitable video mode found. Booting in blind mode" error.
#    The old terminal_input/terminal_output console lines triggered
#    gfxterm initialisation without any video drivers loaded.
mkdir -p "$ISO_ROOT/boot/grub"
cat << 'EOF' > "$ISO_ROOT/boot/grub/grub.cfg"
set timeout=5
set default=0

insmod all_video
set gfxmode=auto
set gfxpayload=keep

menuentry "SnowFoxOS v3 — Start Live Installer" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "SnowFoxOS v3 — Safe Graphics Mode" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}

menuentry "Boot Existing Operating System" {
    exit
}
EOF

# 10. Build bootable ISO
OUTPUT_ISO="$PROJECT_ROOT/SnowFoxOS-v3.iso"
echo -e "${PURPLE}[SnowFox] Generating bootable ISO: $OUTPUT_ISO...${RESET}"
grub-mkrescue -o "$OUTPUT_ISO" "$ISO_ROOT"

echo -e "${GREEN}[OK] SnowFoxOS ISO built successfully: $OUTPUT_ISO${RESET}"
