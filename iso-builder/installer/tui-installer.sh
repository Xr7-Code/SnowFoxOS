#!/bin/bash
# ============================================================
#  SnowFoxOS — TUI Installer
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

set -e

PURPLE='\033[0;35m'
LPURPLE='\033[1;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "Installer must be run as root."
    exit 1
fi

# Ensure dialog is available
if ! command -v dialog >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq dialog
fi

# Ensure other dependencies are available
NEED=()
for pkg in parted dosfstools e2fsprogs squashfs-tools util-linux debootstrap; do
    dpkg -s "$pkg" >/dev/null 2>&1 || NEED+=("$pkg")
done
if (( ${#NEED[@]} > 0 )); then
    clear
    echo -e "${CYAN}${BOLD}Installing missing packages: ${NEED[*]}${RESET}"
    apt-get update -qq && apt-get install -y -qq "${NEED[@]}"
fi

clear


# ============================================================
#  1. Questionnaire (Wizard with Back navigation)
# ============================================================
SYS_LANG="en_US.UTF-8"
KEYMAP="us"
TIMEZONE="UTC"
HOSTNAME="snowfox"
TARGET_USER="snowfox"
TARGET_PASS=""
ROOT_PASS=""
TARGET_DISK=""
PART_CHOICE="1"

step=1
while (( step >= 1 && step <= 10 )); do
    case $step in
        1)
            SYS_LANG=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — System Language (Step 1/10)" \
                --menu "Select System Language:" 12 55 4 \
                "en_US.UTF-8" "English (US) — Default" \
                "de_DE.UTF-8" "German / Deutsch" \
                "fr_FR.UTF-8" "French / Français" \
                "es_ES.UTF-8" "Spanish / Español")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                if dialog --stdout --yesno "Exit installer?" 6 40; then
                    clear; exit 0
                fi
                continue
            fi
            SYS_LANG="${SYS_LANG:-en_US.UTF-8}"
            step=2
            ;;
        2)
            KEYMAP=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Keyboard Layout (Step 2/10)" \
                --menu "Select Keyboard Layout:" 12 55 5 \
                "us" "US English — Default" \
                "de" "German / DE" \
                "fr" "French / FR" \
                "es" "Spanish / ES" \
                "gb" "UK English / GB")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=1
                continue
            fi
            KEYMAP="${KEYMAP:-us}"
            step=3
            ;;
        3)
            TIMEZONE=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Timezone (Step 3/10)" \
                --menu "Select Timezone:" 14 55 6 \
                "UTC"                 "UTC — Default" \
                "Europe/Berlin"       "Berlin / CET" \
                "Europe/London"       "London / GMT" \
                "America/New_York"    "New York / EST" \
                "America/Los_Angeles" "Los Angeles / PST" \
                "Asia/Tokyo"          "Tokyo / JST")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=2
                continue
            fi
            TIMEZONE="${TIMEZONE:-UTC}"
            step=4
            ;;
        4)
            HOSTNAME=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Hostname (Step 4/10)" \
                --inputbox "Enter System Hostname:" 8 55 "$HOSTNAME")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=3
                continue
            fi
            HOSTNAME="${HOSTNAME:-snowfox}"
            step=5
            ;;
        5)
            TARGET_USER=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — User Account (Step 5/10)" \
                --inputbox "Enter Username:" 8 55 "$TARGET_USER")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=4
                continue
            fi
            while [[ -z "$TARGET_USER" ]]; do
                TARGET_USER=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — User Account (Step 5/10)" \
                    --inputbox "Username cannot be empty. Enter Username:" 8 55 "snowfox")
                ret=$?
                if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                    step=4
                    break
                fi
            done
            [[ $ret -eq 3 || $ret -eq 1 ]] && continue
            step=6
            ;;
        6)
            # User password — dialog --insecure --passwordbox shows '*' per char
            # Use  || ret=$?  so set -e doesn't exit when Cancel (ret=1) is pressed
            while true; do
                ret=0
                TARGET_PASS=$(dialog --stdout --insecure \
                    --title "SnowFoxOS Installer — User Password (Step 6/10)" \
                    --passwordbox "Password for user '$TARGET_USER':\n\n[ Cancel = Back ]" 10 60) || ret=$?
                if [[ $ret -ne 0 ]]; then
                    step=5
                    break
                fi
                if [[ -z "$TARGET_PASS" ]]; then
                    dialog --stdout --msgbox "Password cannot be empty. Please try again." 6 50 || true
                    continue
                fi
                ret=0
                TARGET_PASS_CONF=$(dialog --stdout --insecure \
                    --title "SnowFoxOS Installer — User Password (Step 6/10)" \
                    --passwordbox "Confirm password for '$TARGET_USER':\n\n[ Cancel = Re-enter password ]" 10 60) || ret=$?
                if [[ $ret -ne 0 ]]; then
                    continue
                fi
                if [[ "$TARGET_PASS" == "$TARGET_PASS_CONF" ]]; then
                    step=7
                    break
                fi
                dialog --stdout --msgbox "Passwords do not match. Please try again." 6 50 || true
            done
            ;;
        7)
            ret=0
            dialog --extra-button --extra-label "Back" \
                --title "SnowFoxOS Installer — Root Password (Step 7/10)" \
                --yesno "Use the same password for root as well?" 7 60 || ret=$?
            if [[ $ret -eq 3 ]]; then
                # Back button → return to step 6
                step=6
                continue
            elif [[ $ret -eq 0 ]]; then
                # Yes → reuse user password
                ROOT_PASS="$TARGET_PASS"
                step=8
            else
                # No (ret=1) → enter a separate root password via TUI
                while true; do
                    ret=0
                    ROOT_PASS=$(dialog --stdout --insecure \
                        --title "SnowFoxOS Installer — Root Password (Step 7/10)" \
                        --passwordbox "Password for root:\n\n[ Cancel = Back ]" 10 60) || ret=$?
                    if [[ $ret -ne 0 ]]; then
                        step=6
                        break
                    fi
                    if [[ -z "$ROOT_PASS" ]]; then
                        dialog --stdout --msgbox "Password cannot be empty. Please try again." 6 50 || true
                        continue
                    fi
                    ret=0
                    ROOT_PASS_CONF=$(dialog --stdout --insecure \
                        --title "SnowFoxOS Installer — Root Password (Step 7/10)" \
                        --passwordbox "Confirm password for root:\n\n[ Cancel = Re-enter password ]" 10 60) || ret=$?
                    if [[ $ret -ne 0 ]]; then
                        continue
                    fi
                    if [[ "$ROOT_PASS" == "$ROOT_PASS_CONF" ]]; then
                        step=8
                        break
                    fi
                    dialog --stdout --msgbox "Passwords do not match. Please try again." 6 50 || true
                done
            fi
            ;;
        8)
            DISK_MENU_ARGS=()
            while read -r name size model; do
                [[ -n "$name" ]] && DISK_MENU_ARGS+=("$name" "$size  ${model:-Unknown}")
            done < <(lsblk -dno NAME,SIZE,MODEL | grep -v "^loop")

            TARGET_DISK=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Target Disk (Step 8/10)" \
                --menu "Select target disk (WARNING: all data will be erased):" 15 65 8 \
                "${DISK_MENU_ARGS[@]}")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=7
                continue
            fi
            if [[ -z "$TARGET_DISK" ]]; then
                continue
            fi
            TARGET_DEV="/dev/$TARGET_DISK"
            step=9
            ;;
        9)
            dialog --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Confirm (Step 9/10)" \
                --yesno "Really erase ALL data on:\n\n    $TARGET_DEV\n\n?" 10 55
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=8
                continue
            fi
            step=10
            ;;
        10)
            PART_CHOICE=$(dialog --stdout --extra-button --extra-label "Back" --title "SnowFoxOS Installer — Partitioning (Step 10/10)" \
                --menu "Select Partitioning Method:" 12 65 2 \
                "1" "Automatic — GPT + EFI, full disk" \
                "2" "Manual — interactive partition manager")
            ret=$?
            if [[ $ret -eq 3 || $ret -eq 1 ]]; then
                step=9
                continue
            fi
            PART_CHOICE="${PART_CHOICE:-1}"
            break
            ;;
    esac
done

TARGET_ROOT=""
TARGET_BOOT=""

# Suffix helper: nvme/mmcblk need 'p' before partition number
part_suffix() { [[ "$1" =~ (nvme|mmcblk|loop) ]] && echo "p" || echo ""; }

if [[ "$PART_CHOICE" == "2" ]]; then
    clear
    echo -e "${PURPLE}=== Manual Partition Manager ($TARGET_DEV) ===${RESET}"
    lsblk "$TARGET_DEV"
    echo ""
    while true; do
        echo "Actions: [s]hrink  [e]nlarge  [d]elete  [c]reate  [f]inish"
        read -rp "Choose action [s/e/d/c/f]: " part_act
        case "$part_act" in
            s)
                read -rp "Partition number to shrink (e.g. 2): " pnum
                read -rp "New filesystem size (e.g. 30G): " fsize
                read -rp "New partition end (e.g. 35GB): " psize
                PART="${TARGET_DEV}$(part_suffix "$TARGET_DEV")${pnum}"
                e2fsck -f -y "$PART" || true
                resize2fs "$PART" "$fsize" || true
                parted -s "$TARGET_DEV" resizepart "$pnum" "$psize" || echo "Resize failed"
                ;;
            e)
                read -rp "Partition number to enlarge (e.g. 2): " pnum
                read -rp "New partition end (e.g. 80GB or 100%): " psize
                PART="${TARGET_DEV}$(part_suffix "$TARGET_DEV")${pnum}"
                parted -s "$TARGET_DEV" resizepart "$pnum" "$psize" || echo "Enlarge failed"
                resize2fs "$PART" || true
                ;;
            d)
                read -rp "Partition number to delete: " pnum
                parted -s "$TARGET_DEV" rm "$pnum" || echo "Delete failed"
                ;;
            c)
                read -rp "parted arguments (e.g. mkpart primary ext4 512MiB 100%): " cargs
                # shellcheck disable=SC2086
                parted -s "$TARGET_DEV" $cargs || echo "Create failed"
                ;;
            f) break ;;
        esac
        lsblk "$TARGET_DEV"
    done

    read -rp "Root partition device (e.g. /dev/sda2): " TARGET_ROOT
    read -rp "EFI/Boot partition device (e.g. /dev/sda1): " TARGET_BOOT

else
    dialog --stdout --infobox "Wiping $TARGET_DEV and creating GPT + EFI layout..." 5 65
    wipefs -a "$TARGET_DEV"
    parted -s "$TARGET_DEV" mklabel gpt
    parted -s "$TARGET_DEV" mkpart ESP fat32 1MiB 512MiB
    parted -s "$TARGET_DEV" set 1 esp on
    parted -s "$TARGET_DEV" mkpart primary ext4 512MiB 100%

    SUF=$(part_suffix "$TARGET_DEV")
    TARGET_BOOT="${TARGET_DEV}${SUF}1"
    TARGET_ROOT="${TARGET_DEV}${SUF}2"

    mkfs.fat -F32 "$TARGET_BOOT"
    mkfs.ext4 -F  "$TARGET_ROOT"
fi

# ============================================================
#  5. Installation
# ============================================================
dialog --stdout --infobox "Installing SnowFoxOS to $TARGET_ROOT..." 5 65

MOUNT_DIR="/mnt/snowfox-install"
mkdir -p "$MOUNT_DIR"
mount "$TARGET_ROOT" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR/boot/efi"
mount "$TARGET_BOOT" "$MOUNT_DIR/boot/efi"

# Find squashfs image
SQUASHFS=""
for path in \
    /run/live/medium/live/filesystem.squashfs \
    /run/live/rootfs/filesystem.squashfs \
    /lib/live/mount/medium/live/filesystem.squashfs \
    /live/medium/live/filesystem.squashfs \
    /live/filesystem.squashfs \
    /cdrom/live/filesystem.squashfs; do
    if [[ -f "$path" ]]; then
        SQUASHFS="$path"
        break
    fi
done

if [[ -n "$SQUASHFS" ]]; then
    unsquashfs -f -d "$MOUNT_DIR" "$SQUASHFS"
else
    debootstrap --arch=amd64 bookworm "$MOUNT_DIR" http://deb.debian.org/debian
fi

# Generate fstab
ROOT_UUID=$(blkid -s UUID -o value "$TARGET_ROOT")
BOOT_UUID=$(blkid -s UUID -o value "$TARGET_BOOT")
mkdir -p "$MOUNT_DIR/etc"
echo "UUID=$ROOT_UUID  /          ext4  errors=remount-ro  0 1" >  "$MOUNT_DIR/etc/fstab"
echo "UUID=$BOOT_UUID  /boot/efi  vfat  umask=0077         0 1" >> "$MOUNT_DIR/etc/fstab"

# Bind virtual filesystems
for d in dev proc sys run; do
    mount --bind "/$d" "$MOUNT_DIR/$d" 2>/dev/null || true
done
[[ -f /etc/resolv.conf ]] && cp -L /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf" 2>/dev/null || true

# ============================================================
#  6. chroot configuration (variables expand directly into heredoc)
# ============================================================
cat > "$MOUNT_DIR/tmp/configure-system.sh" << EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1   localhost"                           > /etc/hosts
echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME"    >> /etc/hosts
echo "::1         localhost ip6-localhost ip6-loopback" >> /etc/hosts

apt-get update -qq
apt-get install -y -qq locales keyboard-configuration sudo systemd

echo "$SYS_LANG UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG="$SYS_LANG"

echo 'XKBLAYOUT="$KEYMAP"' > /etc/default/keyboard
setupcon --force 2>/dev/null || true

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

useradd -m -s /bin/bash -G sudo,audio,video,netdev "$TARGET_USER" 2>/dev/null || true
echo "$TARGET_USER:$TARGET_PASS" | chpasswd
echo "root:$ROOT_PASS" | chpasswd

sed -i 's/^# *%sudo/%sudo/' /etc/sudoers 2>/dev/null || true

grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=SnowFoxOS --recheck 2>/dev/null \
    || grub-install "$TARGET_DEV"
update-grub

if [[ -x /usr/local/bin/snowfox-auto-install ]]; then
    systemctl enable snowfox-firstboot.service || true
fi
EOF

chmod +x "$MOUNT_DIR/tmp/configure-system.sh"

# Firstboot service
mkdir -p "$MOUNT_DIR/etc/systemd/system"
cat > "$MOUNT_DIR/etc/systemd/system/snowfox-firstboot.service" << 'EOF'
[Unit]
Description=SnowFoxOS First Boot Setup (Hardware Drivers & Finalisation)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/usr/local/bin/snowfox-auto-install

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/snowfox-auto-install
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Copy auto-install script
if [[ -x /usr/local/bin/snowfox-auto-install ]]; then
    install -m 0755 /usr/local/bin/snowfox-auto-install \
        "$MOUNT_DIR/usr/local/bin/snowfox-auto-install"
fi

# Copy SnowFoxOS repo
if [[ -d /opt/SnowFoxOS ]]; then
    mkdir -p "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS"
    cp -a /opt/SnowFoxOS/. "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS/"
    chown -R 1000:1000 "$MOUNT_DIR/home/$TARGET_USER/SnowFoxOS"
fi

chroot "$MOUNT_DIR" /tmp/configure-system.sh
rm -f "$MOUNT_DIR/tmp/configure-system.sh"

# ============================================================
#  7. Cleanup & Reboot
# ============================================================
for m in run sys proc dev; do
    umount -lf "$MOUNT_DIR/$m" 2>/dev/null || true
done
umount -lf "$MOUNT_DIR/boot/efi" 2>/dev/null || true
umount -lf "$MOUNT_DIR"          2>/dev/null || true

# Disable live installer service
systemctl disable snowfox-live-installer.service 2>/dev/null || true
rm -f /etc/systemd/system/snowfox-live-installer.service

dialog --stdout --title "SnowFoxOS — Installation Complete" \
    --msgbox "SnowFoxOS was installed successfully!\n\nAfter reboot, hardware drivers, Zen Browser,\nFresh Editor and Console Launcher will be\nconfigured automatically.\n\nPress OK to reboot." \
    12 60

clear
echo -e "${GREEN}[OK] Installation finished. Rebooting...${RESET}"
reboot
