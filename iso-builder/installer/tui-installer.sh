#!/bin/bash
# ============================================================
#  SnowFoxOS — TUI Installer
#  SnowFox Theming & Interactive Partitioning / Questionnaire
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

set -e

PURPLE='\033[0;35m'
LPURPLE='\033[1;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "Installer must be run as root."
    exit 1
fi

# Use dialog if available, else fallback to standard read/echo
USE_DIALOG=false
if command -v dialog >/dev/null 2>&1; then
    USE_DIALOG=true
fi

clear
echo -e "${PURPLE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║                  🦊  SnowFoxOS v3                    ║"
echo "  ║               Interactive TUI Installer              ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}\n"
sleep 1

# 1. Questionnaire (Language, Keyboard, Timezone, Hostname, Username, Password)
if $USE_DIALOG; then
    SYS_LANG=$(dialog --stdout --inputbox "System Language:" 8 50 "en_US.UTF-8") || exit 1
    KEYMAP=$(dialog --stdout --inputbox "Keyboard Layout:" 8 50 "us") || exit 1
    TIMEZONE=$(dialog --stdout --inputbox "Timezone:" 8 50 "Europe/Berlin") || exit 1
    HOSTNAME=$(dialog --stdout --inputbox "Hostname:" 8 50 "snowfox") || exit 1
    TARGET_USER=$(dialog --stdout --inputbox "Username:" 8 50 "snowfoxuser") || exit 1
    TARGET_PASS=$(dialog --stdout --passwordbox "Password for $TARGET_USER:" 8 50) || exit 1
    TARGET_PASS_CONF=$(dialog --stdout --passwordbox "Confirm Password:" 8 50) || exit 1

    while [[ "$TARGET_PASS" != "$TARGET_PASS_CONF" || -z "$TARGET_PASS" ]]; do
        dialog --msgbox "Passwords do not match or are empty. Try again." 6 40
        TARGET_PASS=$(dialog --stdout --passwordbox "Password for $TARGET_USER:" 8 50) || exit 1
        TARGET_PASS_CONF=$(dialog --stdout --passwordbox "Confirm Password:" 8 50) || exit 1
    done
else
    echo -e "${LPURPLE}${BOLD}── System Configuration ──────────────────────────────${RESET}\n"
    read -rp "System Language [default: en_US.UTF-8]: " SYS_LANG
    SYS_LANG="${SYS_LANG:-en_US.UTF-8}"

    read -rp "Keyboard Layout [default: us]: " KEYMAP
    KEYMAP="${KEYMAP:-us}"

    read -rp "Timezone [default: Europe/Berlin]: " TIMEZONE
    TIMEZONE="${TIMEZONE:-Europe/Berlin}"

    read -rp "Hostname [default: snowfox]: " HOSTNAME
    HOSTNAME="${HOSTNAME:-snowfox}"

    read -rp "Username [default: snowfox]: " TARGET_USER
    TARGET_USER="${TARGET_USER:-snowfox}"

    read -rsp "Password for $TARGET_USER: " TARGET_PASS
    echo ""
    read -rsp "Confirm password: " TARGET_PASS_CONF
    echo ""
    while [[ "$TARGET_PASS" != "$TARGET_PASS_CONF" || -z "$TARGET_PASS" ]]; do
        echo -e "${RED}Passwords do not match or are empty. Try again.${RESET}"
        read -rsp "Password for $TARGET_USER: " TARGET_PASS
        echo ""
        read -rsp "Confirm password: " TARGET_PASS_CONF
        echo ""
    done
fi

# 2. Disk Selection & Partitioning TUI
clear
echo -e "${LPURPLE}${BOLD}── Disk Selection & Partitioning ─────────────────────${RESET}\n"
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""

read -rp "Select target disk (e.g. sda, nvme0n1): " TARGET_DISK
TARGET_DEV="/dev/$TARGET_DISK"

if [[ ! -b "$TARGET_DEV" ]]; then
    echo -e "${RED}[FAILED] Invalid block device $TARGET_DEV${RESET}"
    exit 1
fi

echo ""
echo -e "${ORANGE}Partitioning Options:${RESET}"
echo "1) Automatic partitioning (Erases target disk & creates standard Debian GPT+EFI layout)"
echo "2) Custom TUI Partition Manager (Delete, Shrink, Enlarge partitions, standard Debian choices)"
read -rp "Select option [1-2, default: 1]: " PART_CHOICE
PART_CHOICE="${PART_CHOICE:-1}"

TARGET_ROOT=""
TARGET_BOOT=""

if [[ "$PART_CHOICE" == "2" ]]; then
    echo -e "${PURPLE}[SnowFox] Launching Custom TUI Partition Manager...${RESET}"
    while true; do
        clear
        echo -e "${PURPLE}=== Custom TUI Partition Manager ($TARGET_DEV) ===${RESET}"
        lsblk "$TARGET_DEV"
        echo ""
        echo "Actions:"
        echo "  [s] Shrink a partition (resize2fs + parted)"
        echo "  [e] Enlarge / Grow a partition (parted + resize2fs)"
        echo "  [d] Delete a partition"
        echo "  [c] Create new partition"
        echo "  [f] Finish partitioning and proceed"
        read -rp "Choose action [s/e/d/c/f]: " part_act
        case "$part_act" in
            s)
                read -rp "Partition number to shrink (e.g. 2): " pnum
                read -rp "Filesystem size (e.g. 30G): " fsize
                read -rp "New partition end size (e.g. 35GB): " psize
                e2fsck -f -y "${TARGET_DEV}${pnum}" || true
                resize2fs "${TARGET_DEV}${pnum}" "$fsize" || true
                parted -s "$TARGET_DEV" resizepart "$pnum" "$psize" || echo "Resize failed"
                ;;
            e)
                read -rp "Partition number to enlarge (e.g. 2): " pnum
                read -rp "New partition end size (e.g. 80GB or 100%): " psize
                parted -s "$TARGET_DEV" resizepart "$pnum" "$psize" || echo "Enlarge failed"
                resize2fs "${TARGET_DEV}${pnum}" || true
                ;;
            d)
                read -rp "Partition number to delete: " pnum
                parted -s "$TARGET_DEV" rm "$pnum" || echo "Delete failed"
                ;;
            c)
                read -rp "Partition type/size (e.g. mkpart primary ext4 512MiB 100%): " cargs
                parted -s "$TARGET_DEV" $cargs || echo "Create failed"
                ;;
            f)
                break
                ;;
        esac
    done
    read -rp "Enter your root partition device (e.g. /dev/sda2 or /dev/nvme0n1p2): " TARGET_ROOT
    read -rp "Enter your EFI/Boot partition device (e.g. /dev/sda1 or /dev/nvme0n1p1): " TARGET_BOOT
else
    echo -e "${PURPLE}[SnowFox] Wiping and creating standard Debian 12 GPT+EFI layout on $TARGET_DEV...${RESET}"
    wipefs -a "$TARGET_DEV"
    parted -s "$TARGET_DEV" mklabel gpt
    parted -s "$TARGET_DEV" mkpart ESP fat32 1MiB 512MiB
    parted -s "$TARGET_DEV" set 1 esp on
    parted -s "$TARGET_DEV" mkpart primary ext4 512MiB 100%

    if [[ "$TARGET_DISK" =~ ^nvme ]]; then
        TARGET_BOOT="${TARGET_DEV}p1"
        TARGET_ROOT="${TARGET_DEV}p2"
    else
        TARGET_BOOT="${TARGET_DEV}1"
        TARGET_ROOT="${TARGET_DEV}2"
    fi

    mkfs.fat -F32 "$TARGET_BOOT"
    mkfs.ext4 -F "$TARGET_ROOT"
fi

# 3. Fast Installation (< 1 minute via SquashFS extraction)
clear
echo -e "${PURPLE}[SnowFox] Installing SnowFoxOS to $TARGET_ROOT (lightning-fast squashfs deployment)...${RESET}"

MOUNT_DIR="/mnt/snowfox-install"
mkdir -p "$MOUNT_DIR"
mount "$TARGET_ROOT" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR/boot/efi"
mount "$TARGET_BOOT" "$MOUNT_DIR/boot/efi"

SQUASHFS=""
for path in \
    /live/filesystem.squashfs \
    /run/live/medium/live/filesystem.squashfs \
    /live/medium/live/filesystem.squashfs \
    /run/live/rootfs/filesystem.squashfs \
    /lib/live/mount/medium/live/filesystem.squashfs; do
    if [[ -f "$path" ]]; then
        SQUASHFS="$path"
        break
    fi
done

if [[ -n "$SQUASHFS" ]]; then
    echo "[SnowFox] Extracting compressed filesystem (~under 1 minute)..."
    unsquashfs -f -d "$MOUNT_DIR" "$SQUASHFS"
else
    echo "[WARN] filesystem.squashfs not found, debootstrapping base system..."
    debootstrap --arch=amd64 bookworm "$MOUNT_DIR" http://deb.debian.org/debian
fi

# Generate fstab
echo "UUID=$(blkid -s UUID -o value "$TARGET_ROOT") / ext4 errors=remount-ro 0 1" > "$MOUNT_DIR/etc/fstab"
echo "UUID=$(blkid -s UUID -o value "$TARGET_BOOT") /boot/efi vfat umask=0077 0 1" >> "$MOUNT_DIR/etc/fstab"

# Bind virtual filesystems
mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"

# Configure system in chroot
cat << EOF > "$MOUNT_DIR/tmp/configure-system.sh"
export DEBIAN_FRONTEND=noninteractive
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

apt-get update -qq
apt-get install -y -qq locales keyboard-configuration
echo "$SYS_LANG UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG="$SYS_LANG"

echo "XKBLAYOUT=\"$KEYMAP\"" > /etc/default/keyboard
setupcon --force 2>/dev/null || true

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

# Create user
useradd -m -s /bin/bash -G sudo,audio,video,netdev "$TARGET_USER" 2>/dev/null || true
echo "$TARGET_USER:$TARGET_PASS" | chpasswd
echo "root:root" | chpasswd

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=SnowFoxOS --recheck || grub-install "$TARGET_DISK"
update-grub

# Register firstboot auto-install service for hardware drivers & final configuration
systemctl enable snowfox-firstboot.service
EOF

chmod +x "$MOUNT_DIR/tmp/configure-system.sh"

# Create firstboot service in target
cat << 'EOF' > "$MOUNT_DIR/etc/systemd/system/snowfox-firstboot.service"
[Unit]
Description=SnowFoxOS First Boot Setup (Hardware Drivers & Finalization)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snowfox-auto-install
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Copy auto-install script to target
cp /usr/local/bin/snowfox-auto-install "$MOUNT_DIR/usr/local/bin/snowfox-auto-install"
chmod +x "$MOUNT_DIR/usr/local/bin/snowfox-auto-install"

# Ensure SnowFoxOS repo is at /home/$TARGET_USER/SnowFoxOS
if [[ -d /opt/SnowFoxOS ]]; then
    mkdir -p "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS"
    cp -r /opt/SnowFoxOS/* "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS/"
    chown -R 1000:1000 "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS"
fi

chroot "$MOUNT_DIR" /tmp/configure-system.sh
rm -f "$MOUNT_DIR/tmp/configure-system.sh"

# Cleanup mounts
umount -lf "$MOUNT_DIR/dev" 2>/dev/null || true
umount -lf "$MOUNT_DIR/proc" 2>/dev/null || true
umount -lf "$MOUNT_DIR/sys" 2>/dev/null || true
umount -lf "$MOUNT_DIR/boot/efi" 2>/dev/null || true
umount -lf "$MOUNT_DIR" 2>/dev/null || true

clear
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║       🦊 SnowFoxOS Installation Complete!            ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}\n"
echo -e "SnowFoxOS was successfully installed to your system."
echo -e "After rebooting, the system will automatically configure hardware"
echo -e "drivers (AMD, NVIDIA, Intel), Zen Browser, Fresh Editor, and Console Launcher."
echo ""
read -rp "Press Enter to reboot into your new SnowFoxOS system..."
reboot
