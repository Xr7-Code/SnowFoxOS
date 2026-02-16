#!/bin/bash

# SnowFoxOS Installer v1.2 (Fixed Path & Error Handling)
# Minimal. Fast. Beautiful.

# Exit on error
set -e

# Pfad zum Skript-Verzeichnis ermitteln (WICHTIG!)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "════════════════════════════════════════════════════"
echo "         🦊 SnowFoxOS Installation Script v1.2    "
echo "════════════════════════════════════════════════════"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Bitte als root ausführen: sudo bash install.sh${NC}"
    exit 1
fi

# Determine actual user and their home directory
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    echo -e "${RED}❌ Bitte mit sudo ausführen, nicht als root direkt!${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Installation für User: $REAL_USER"
echo -e "${GREEN}✓${NC} Home-Verzeichnis: $USER_HOME"

# 1. System Update
echo "📦 System wird aktualisiert..."
apt update -qq && apt upgrade -y -qq

# 2. Essential Packages
echo "📦 Installiere Core-Pakete..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq \
    sway waybar wofi kitty thunar firefox-esr neovim \
    network-manager grim slurp wl-clipboard swaylock \
    mako-notifier brightnessctl pulseaudio pavucontrol \
    git curl wget htop imagemagick swaybg fonts-noto \
    fonts-font-awesome libnotify-bin

# 3. Firmware & Drivers (Fehler hier ignorieren, falls Pakete fehlen)
echo "🔧 Installiere Treiber..."
apt install -y -qq firmware-linux-free firmware-linux-nonfree \
    firmware-misc-nonfree firmware-realtek firmware-iwlwifi \
    firmware-atheros intel-microcode amd64-microcode || echo -e "${YELLOW}⚠ Einige Treiber-Pakete nicht gefunden${NC}"

# 4. RTL8821CE WiFi Driver
if lspci | grep -qi "RTL8821CE"; then
    echo "📡 RTL8821CE gefunden, installiere Treiber..."
    apt install -y -qq dkms build-essential linux-headers-$(uname -r) git
    cd /tmp
    rm -rf rtl8821ce
    if git clone https://github.com/tomaspinho/rtl8821ce; then
        cd rtl8821ce
        ./install.sh || echo "Treiber-Install fehlgeschlagen"
    fi
    cd "$SCRIPT_DIR" # Zurück zum Installer-Pfad!
fi

# 5. NetworkManager & Configs
systemctl enable NetworkManager >/dev/null 2>&1 || true

# 6. Configs kopieren (Nutzt jetzt $SCRIPT_DIR)
echo "⚙️  Kopiere Konfigurationen..."
mkdir -p "$USER_HOME/.config/sway" "$USER_HOME/.config/waybar" \
         "$USER_HOME/.config/wofi" "$USER_HOME/.config/kitty" \
         "$USER_HOME/.config/swaylock" "$USER_HOME/.config/mako" \
         "$USER_HOME/bin" "$USER_HOME/Pictures/wallpapers"

# Funktion zum sicheren Kopieren
safe_copy() {
    if [ -f "$SCRIPT_DIR/$1" ]; then
        cp "$SCRIPT_DIR/$1" "$USER_HOME/$2"
        echo -e "${GREEN}✓${NC} $1 installiert"
    else
        echo -e "${YELLOW}⚠${NC} $1 fehlt im Repository"
    fi
}

safe_copy "configs/sway-config" ".config/sway/config"
safe_copy "configs/waybar-config" ".config/waybar/config"
safe_copy "configs/waybar-style.css" ".config/waybar/style.css"
safe_copy "configs/wofi-style.css" ".config/wofi/style.css"
safe_copy "configs/kitty.conf" ".config/kitty/kitty.conf"
safe_copy "configs/swaylock-config" ".config/swaylock/config"
safe_copy "configs/bash_profile" ".bash_profile"

# 7. Scripts & Wallpapers
if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp "$SCRIPT_DIR/scripts/"* "$USER_HOME/bin/" 2>/dev/null || true
    chmod +x "$USER_HOME/bin/"* 2>/dev/null || true
fi

if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    cp "$SCRIPT_DIR/wallpapers/"* "$USER_HOME/Pictures/wallpapers/" 2>/dev/null || true
fi

# 8. Ownership fix (Ganz wichtig für Root-Aktionen)
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config"
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/bin"
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/Pictures"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.bash_profile"

echo ""
echo -e "════════════════════════════════════════════════════"
echo -e "          ${GREEN}✅ Installation abgeschlossen!${NC}"
echo "════════════════════════════════════════════════════"
