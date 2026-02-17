#!/bin/bash

# SnowFoxOS Installer v1.5.3
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===================================================="
echo "          SnowFoxOS Installation Script"
echo "===================================================="

# 1. Check Root & User
if [ "$EUID" -ne 0 ]; then
    echo "Fehler: Bitte als root ausfuehren!"
    exit 1
fi

if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    echo "Fehler: Bitte mit sudo ausfuehren!"
    exit 1
fi

# 2. Update & Install
apt update -qq && apt upgrade -y -qq
echo "Installiere Pakete..."
apt install -y -qq elogind libpam-elogind libelogind0
apt install -y -qq --no-install-recommends sway waybar wofi kitty thunar firefox-esr neovim network-manager grim slurp wl-clipboard swaylock mako-notifier brightnessctl pulseaudio pavucontrol git curl wget htop imagemagick swaybg fonts-noto fonts-font-awesome libnotify-bin swayidle

# 3. Network
echo "Konfiguriere Netzwerk..."
systemctl stop dhcpcd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
mkdir -p /etc/NetworkManager/conf.d/
echo -e "[main]\nplugins=ifupdown,keyfile\n[ifupdown]\nmanaged=true" > /etc/NetworkManager/conf.d/snowfox.conf
systemctl enable NetworkManager && systemctl restart NetworkManager

# 4. Sudoers
echo "%sudo ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown" > /etc/sudoers.d/snowfox-power
chmod 440 /etc/sudoers.d/snowfox-power

# 5. Configs & Directories
echo "Kopiere Dateien..."
mkdir -p "$USER_HOME/.config/sway" "$USER_HOME/.config/waybar" "$USER_HOME/.config/wofi" "$USER_HOME/.config/kitty" "$USER_HOME/.config/swaylock" "$USER_HOME/.config/mako" "$USER_HOME/bin" "$USER_HOME/Pictures/wallpapers"

[ -f "$SCRIPT_DIR/configs/sway-config" ] && cp "$SCRIPT_DIR/configs/sway-config" "$USER_HOME/.config/sway/config"
[ -f "$SCRIPT_DIR/configs/waybar-config" ] && cp "$SCRIPT_DIR/configs/waybar-config" "$USER_HOME/.config/waybar/config"
[ -f "$SCRIPT_DIR/configs/waybar-style.css" ] && cp "$SCRIPT_DIR/configs/waybar-style.css" "$USER_HOME/.config/waybar/style.css"
[ -f "$SCRIPT_DIR/configs/wofi-style.css" ] && cp "$SCRIPT_DIR/configs/wofi-style.css" "$USER_HOME/.config/wofi/style.css"
[ -f "$SCRIPT_DIR/configs/kitty.conf" ] && cp "$SCRIPT_DIR/configs/kitty.conf" "$USER_HOME/.config/kitty/kitty.conf"
[ -f "$SCRIPT_DIR/configs/swaylock-config" ] && cp "$SCRIPT_DIR/configs/swaylock-config" "$USER_HOME/.config/swaylock/config"
[ -f "$SCRIPT_DIR/configs/bash_profile" ] && cp "$SCRIPT_DIR/configs/bash_profile" "$USER_HOME/.bash_profile"

if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp -r "$SCRIPT_DIR/scripts/"* "$USER_HOME/bin/" 2>/dev/null || true
    chmod +x "$USER_HOME/bin/"* 2>/dev/null || true
fi

if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    cp "$SCRIPT_DIR/wallpapers/"*.png "$USER_HOME/Pictures/wallpapers/" 2>/dev/null || true
fi

# 6. Rights
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/bin" "$USER_HOME/Pictures" "$USER_HOME/.bash_profile"

echo "FERTIG! Bitte mit 'exit' abmelden und neu einloggen."
