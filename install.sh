#!/bin/bash

# SnowFoxOS Installer v1.0
# Minimal. Fast. Beautiful.

set -e

echo "════════════════════════════════════════════════════"
echo "         🦊 SnowFoxOS Installation Script         "
echo "════════════════════════════════════════════════════"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Bitte als root ausführen: sudo ./install.sh"
    exit 1
fi

USER_HOME="/home/$SUDO_USER"

# 1. System Update
echo "📦 System wird aktualisiert..."
apt update && apt upgrade -y

# 2. Essential Packages
echo "📦 Installiere Core-Pakete..."
apt install -y \
    sway \
    waybar \
    wofi \
    kitty \
    thunar \
    firefox-esr \
    neovim \
    network-manager \
    network-manager-gnome \
    grim \
    slurp \
    wl-clipboard \
    swaylock \
    mako-notifier \
    brightnessctl \
    pulseaudio \
    pavucontrol \
    git \
    curl \
    wget \
    htop \
    imagemagick \
    swaybg \
    fonts-noto \
    fonts-font-awesome

# 3. Firmware & Drivers
echo "🔧 Installiere Treiber..."
apt install -y \
    firmware-linux-free \
    firmware-linux-nonfree \
    firmware-misc-nonfree \
    firmware-realtek \
    firmware-iwlwifi \
    firmware-atheros \
    intel-microcode \
    amd64-microcode

# 4. RTL8821CE WiFi Driver (if needed)
echo "📡 Installiere WiFi-Treiber..."
apt install -y dkms build-essential linux-headers-$(uname -r)

if lspci | grep -i "RTL8821CE" > /dev/null; then
    echo "RTL8821CE gefunden, installiere Treiber..."
    cd /tmp
    git clone https://github.com/tomaspinho/rtl8821ce || true
    cd rtl8821ce
    ./install.sh || echo "Treiber-Installation fehlgeschlagen (optional)"
fi

# 5. NetworkManager konfigurieren
echo "🌐 Konfiguriere NetworkManager..."
systemctl stop dhcpcd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl enable NetworkManager
systemctl start NetworkManager

# Remove wlo1 from /etc/network/interfaces
if grep -q "wlo1" /etc/network/interfaces; then
    cp /etc/network/interfaces /etc/network/interfaces.backup
    sed -i '/wlo1/d' /etc/network/interfaces
fi

# WiFi Power-Save ausschalten
mkdir -p /etc/NetworkManager/conf.d/
echo -e "[connection]\nwifi.powersave = 2" > /etc/NetworkManager/conf.d/wifi-powersave.conf

# 6. Configs kopieren
echo "⚙️  Kopiere Konfigurationen..."
mkdir -p "$USER_HOME/.config/sway"
mkdir -p "$USER_HOME/.config/waybar"
mkdir -p "$USER_HOME/.config/wofi"
mkdir -p "$USER_HOME/.config/kitty"
mkdir -p "$USER_HOME/.config/swaylock"
mkdir -p "$USER_HOME/bin"
mkdir -p "$USER_HOME/Pictures/wallpapers"

cp configs/sway-config "$USER_HOME/.config/sway/config"
cp configs/waybar-config "$USER_HOME/.config/waybar/config"
cp configs/waybar-style.css "$USER_HOME/.config/waybar/style.css"
cp configs/wofi-style.css "$USER_HOME/.config/wofi/style.css"
cp configs/kitty.conf "$USER_HOME/.config/kitty/kitty.conf"
cp configs/swaylock-config "$USER_HOME/.config/swaylock/config"
cp configs/bash_profile "$USER_HOME/.bash_profile"

# 7. Scripts kopieren
echo "📝 Installiere Scripts..."
cp scripts/* "$USER_HOME/bin/"
chmod +x "$USER_HOME/bin/"*

# 8. Wallpapers kopieren und blurren
echo "🖼️  Installiere Wallpapers..."
if [ -f "wallpapers/snowfox_dark.png" ]; then
    cp wallpapers/snowfox_dark.png "$USER_HOME/Pictures/wallpapers/"
    convert "$USER_HOME/Pictures/wallpapers/snowfox_dark.png" -blur 0x8 "$USER_HOME/Pictures/wallpapers/snowfox_dark_blur.png"
    echo "   ✅ Dunkles Wallpaper installiert"
fi

if [ -f "wallpapers/snowfox_light.png" ]; then
    cp wallpapers/snowfox_light.png "$USER_HOME/Pictures/wallpapers/"
    convert "$USER_HOME/Pictures/wallpapers/snowfox_light.png" -blur 0x8 "$USER_HOME/Pictures/wallpapers/snowfox_light_blur.png"
    echo "   ✅ Helles Wallpaper installiert"
fi

# 9. .desktop Files
mkdir -p "$USER_HOME/.local/share/applications"
cat > "$USER_HOME/.local/share/applications/snowfox-store.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Type=Application
Name=SnowFox Store
Comment=App Store für SnowFoxOS
Exec=/home/fox/bin/snowfox-store
Icon=system-software-install
Terminal=false
Categories=System;Settings;
DESKTOPEOF

# 10. Ownership fix
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.config"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.local"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/bin"
chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/Pictures"
chown $SUDO_USER:$SUDO_USER "$USER_HOME/.bash_profile"

# 11. Cleanup
echo "🧹 Aufräumen..."
apt autoremove -y
apt clean

echo ""
echo "════════════════════════════════════════════════════"
echo "         ✅ SnowFoxOS Installation Complete!       "
echo "════════════════════════════════════════════════════"
echo ""
echo "Nächste Schritte:"
echo "1. Wallpapers hinzufügen zu ~/Pictures/wallpapers/"
echo "2. Abmelden und neu anmelden"
echo "3. Sway startet automatisch!"
echo ""
echo "Shortcuts: Drücke Mod+H für Hilfe"
echo ""
