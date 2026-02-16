#!/bin/bash

# SnowFoxOS Installer v1.1
# Minimal. Fast. Beautiful.

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "════════════════════════════════════════════════════"
echo "         🦊 SnowFoxOS Installation Script v1.1    "
echo "════════════════════════════════════════════════════"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Bitte als root ausführen: sudo bash install.sh${NC}"
    exit 1
fi

# Determine actual user (not root)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    USER_HOME="/home/$SUDO_USER"
else
    echo -e "${RED}❌ Bitte mit sudo ausführen, nicht als root direkt!${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Installation für User: $REAL_USER"
echo -e "${GREEN}✓${NC} Home-Verzeichnis: $USER_HOME"
echo ""

# 1. System Update
echo "📦 System wird aktualisiert..."
apt update -qq && apt upgrade -y -qq

# 2. Essential Packages
echo "📦 Installiere Core-Pakete..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq \
    sway \
    waybar \
    wofi \
    kitty \
    thunar \
    firefox-esr \
    neovim \
    network-manager \
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
    fonts-font-awesome \
    libnotify-bin

echo -e "${GREEN}✓${NC} Core-Pakete installiert"

# 3. Firmware & Drivers
echo "🔧 Installiere Treiber..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq \
    firmware-linux-free \
    firmware-linux-nonfree \
    firmware-misc-nonfree \
    firmware-realtek \
    firmware-iwlwifi \
    firmware-atheros \
    intel-microcode \
    amd64-microcode

echo -e "${GREEN}✓${NC} Treiber installiert"

# 4. RTL8821CE WiFi Driver (optional)
echo "📡 Prüfe WiFi-Hardware..."
if lspci | grep -qi "RTL8821CE"; then
    echo "   RTL8821CE gefunden, installiere Treiber..."
    apt install -y -qq dkms build-essential linux-headers-$(uname -r) git
    cd /tmp
    if [ -d "rtl8821ce" ]; then
        rm -rf rtl8821ce
    fi
    git clone https://github.com/tomaspinho/rtl8821ce >/dev/null 2>&1 || true
    if [ -d "rtl8821ce" ]; then
        cd rtl8821ce
        ./install.sh >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} RTL8821CE Treiber installiert" || echo -e "${YELLOW}⚠${NC} Treiber-Installation fehlgeschlagen (optional)"
    fi
else
    echo -e "${GREEN}✓${NC} Standard WiFi-Treiber ausreichend"
fi

# 5. NetworkManager konfigurieren
echo "🌐 Konfiguriere NetworkManager..."

# Stop conflicting services
systemctl stop dhcpcd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl stop networking 2>/dev/null || true
systemctl disable networking 2>/dev/null || true

# Remove wlo1 from /etc/network/interfaces
if [ -f /etc/network/interfaces ]; then
    if grep -q "wlo1" /etc/network/interfaces 2>/dev/null; then
        cp /etc/network/interfaces /etc/network/interfaces.backup
        sed -i '/allow-hotplug wlo1/d' /etc/network/interfaces
        sed -i '/iface wlo1/d' /etc/network/interfaces
        sed -i '/wpa-ssid/d' /etc/network/interfaces
        sed -i '/wpa-psk/d' /etc/network/interfaces
    fi
fi

# Enable NetworkManager
systemctl enable NetworkManager >/dev/null 2>&1
systemctl start NetworkManager >/dev/null 2>&1

# WiFi Power-Save ausschalten
mkdir -p /etc/NetworkManager/conf.d/
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF

echo -e "${GREEN}✓${NC} NetworkManager konfiguriert"

# 6. Configs kopieren
echo "⚙️  Kopiere Konfigurationen..."

# Create directories
mkdir -p "$USER_HOME/.config/sway"
mkdir -p "$USER_HOME/.config/waybar"
mkdir -p "$USER_HOME/.config/wofi"
mkdir -p "$USER_HOME/.config/kitty"
mkdir -p "$USER_HOME/.config/swaylock"
mkdir -p "$USER_HOME/.config/mako"
mkdir -p "$USER_HOME/bin"
mkdir -p "$USER_HOME/Pictures/wallpapers"

# Copy configs with error checking
if [ -f "configs/sway-config" ]; then
    cp configs/sway-config "$USER_HOME/.config/sway/config"
    echo -e "${GREEN}✓${NC} Sway config"
else
    echo -e "${RED}✗${NC} configs/sway-config nicht gefunden!"
fi

if [ -f "configs/waybar-config" ]; then
    cp configs/waybar-config "$USER_HOME/.config/waybar/config"
    echo -e "${GREEN}✓${NC} Waybar config"
fi

if [ -f "configs/waybar-style.css" ]; then
    cp configs/waybar-style.css "$USER_HOME/.config/waybar/style.css"
    echo -e "${GREEN}✓${NC} Waybar CSS"
fi

if [ -f "configs/wofi-style.css" ]; then
    cp configs/wofi-style.css "$USER_HOME/.config/wofi/style.css"
    echo -e "${GREEN}✓${NC} Wofi CSS"
fi

if [ -f "configs/kitty.conf" ]; then
    cp configs/kitty.conf "$USER_HOME/.config/kitty/kitty.conf"
    echo -e "${GREEN}✓${NC} Kitty config"
fi

if [ -f "configs/swaylock-config" ]; then
    cp configs/swaylock-config "$USER_HOME/.config/swaylock/config"
    echo -e "${GREEN}✓${NC} Swaylock config"
fi

if [ -f "configs/bash_profile" ]; then
    cp configs/bash_profile "$USER_HOME/.bash_profile"
    echo -e "${GREEN}✓${NC} Bash profile"
fi

# Mako config
cat > "$USER_HOME/.config/mako/config" << 'EOF'
background-color=#0a0a0a
text-color=#ffffff
border-color=#9B59B6
border-size=2
border-radius=8
font=monospace 11
default-timeout=5000
EOF
echo -e "${GREEN}✓${NC} Mako config"

# 7. Scripts kopieren
echo "📝 Installiere Scripts..."
if [ -d "scripts" ]; then
    cp scripts/* "$USER_HOME/bin/" 2>/dev/null || true
    chmod +x "$USER_HOME/bin/"* 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Scripts installiert"
else
    echo -e "${YELLOW}⚠${NC} Scripts-Ordner nicht gefunden"
fi

# 8. Wallpapers
echo "🖼️  Installiere Wallpapers..."
WALLPAPER_INSTALLED=false

if [ -f "wallpapers/snowfox_dark.png" ]; then
    cp wallpapers/snowfox_dark.png "$USER_HOME/Pictures/wallpapers/"
    convert "$USER_HOME/Pictures/wallpapers/snowfox_dark.png" -blur 0x8 "$USER_HOME/Pictures/wallpapers/snowfox_dark_blur.png" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Dunkles Wallpaper installiert"
    WALLPAPER_INSTALLED=true
fi

if [ -f "wallpapers/snowfox_light.png" ]; then
    cp wallpapers/snowfox_light.png "$USER_HOME/Pictures/wallpapers/"
    convert "$USER_HOME/Pictures/wallpapers/snowfox_light.png" -blur 0x8 "$USER_HOME/Pictures/wallpapers/snowfox_light_blur.png" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Helles Wallpaper installiert"
    WALLPAPER_INSTALLED=true
fi

if [ "$WALLPAPER_INSTALLED" = false ]; then
    echo -e "${YELLOW}⚠${NC} Keine Wallpapers gefunden. Bitte manuell hinzufügen zu:"
    echo "   $USER_HOME/Pictures/wallpapers/snowfox_dark.png"
fi

# 9. Desktop file
mkdir -p "$USER_HOME/.local/share/applications"
cat > "$USER_HOME/.local/share/applications/snowfox-store.desktop" << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=SnowFox Store
Comment=App Store für SnowFoxOS
Exec=$USER_HOME/bin/snowfox-store
Icon=system-software-install
Terminal=false
Categories=System;Settings;
DESKTOPEOF

# 10. Ownership fix
chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config" 2>/dev/null || true
chown -R $REAL_USER:$REAL_USER "$USER_HOME/.local" 2>/dev/null || true
chown -R $REAL_USER:$REAL_USER "$USER_HOME/bin" 2>/dev/null || true
chown -R $REAL_USER:$REAL_USER "$USER_HOME/Pictures" 2>/dev/null || true
chown $REAL_USER:$REAL_USER "$USER_HOME/.bash_profile" 2>/dev/null || true

# 11. Cleanup
echo "🧹 Aufräumen..."
apt autoremove -y -qq
apt clean

echo ""
echo "════════════════════════════════════════════════════"
echo -e "         ${GREEN}✅ SnowFoxOS Installation Complete!${NC}       "
echo "════════════════════════════════════════════════════"
echo ""
echo "Nächste Schritte:"
echo "1. Abmelden: exit"
echo "2. Neu anmelden"
echo "3. Sway startet automatisch!"
echo ""
if [ "$WALLPAPER_INSTALLED" = false ]; then
    echo -e "${YELLOW}Hinweis:${NC} Wallpapers fehlen noch!"
    echo "Kopiere sie nach: $USER_HOME/Pictures/wallpapers/"
    echo ""
fi
echo "Shortcuts: Drücke Mod+H für Hilfe"
echo ""
