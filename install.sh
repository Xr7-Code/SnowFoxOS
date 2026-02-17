#!/bin/bash

# SnowFoxOS Installer v1.3
# Minimal. Fast. Beautiful.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "════════════════════════════════════════════════════"
echo "         🦊 SnowFoxOS Installation Script v1.3    "
echo "════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Bitte als root ausführen: sudo bash install.sh${NC}"
    exit 1
fi

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
    git curl wget htop imagemagick swaybg \
    fonts-noto fonts-font-awesome libnotify-bin \
    swayidle policykit-1 polkit

echo -e "${GREEN}✓${NC} Core-Pakete installiert"

# 3. Firmware & Drivers
echo "🔧 Installiere Treiber..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq \
    firmware-linux-free firmware-linux-nonfree \
    firmware-misc-nonfree firmware-realtek firmware-iwlwifi \
    firmware-atheros intel-microcode amd64-microcode \
    || echo -e "${YELLOW}⚠ Einige Treiber-Pakete nicht gefunden${NC}"

echo -e "${GREEN}✓${NC} Treiber installiert"

# 4. RTL8821CE WiFi Driver
if lspci | grep -qi "RTL8821CE"; then
    echo "📡 RTL8821CE gefunden, installiere Treiber..."
    apt install -y -qq dkms build-essential linux-headers-$(uname -r) git
    cd /tmp
    rm -rf rtl8821ce
    if git clone https://github.com/tomaspinho/rtl8821ce >/dev/null 2>&1; then
        cd rtl8821ce
        ./install.sh >/dev/null 2>&1 \
            && echo -e "${GREEN}✓${NC} RTL8821CE Treiber installiert" \
            || echo -e "${YELLOW}⚠${NC} Treiber-Install fehlgeschlagen (optional)"
    fi
    cd "$SCRIPT_DIR"
fi

# 5. NetworkManager konfigurieren (ALLES was WiFi stört entfernen)
echo "🌐 Konfiguriere NetworkManager..."

# Alle konkurrierenden Services stoppen
for svc in dhcpcd networking wpa_supplicant; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
    systemctl mask $svc 2>/dev/null || true
done

# wlo1 aus /etc/network/interfaces entfernen
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.backup
    cat > /etc/network/interfaces << 'EOF'
# SnowFoxOS - Managed by NetworkManager
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
fi

# NetworkManager Config
mkdir -p /etc/NetworkManager/conf.d/
cat > /etc/NetworkManager/conf.d/snowfox.conf << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[connection]
wifi.powersave=2

[device]
wifi.scan-rand-mac-address=no
EOF

# NetworkManager starten
systemctl unmask NetworkManager 2>/dev/null || true
systemctl enable NetworkManager
systemctl restart NetworkManager

echo -e "${GREEN}✓${NC} NetworkManager konfiguriert"

# 6. Polkit für systemctl (shutdown/reboot ohne sudo)
cat > /etc/polkit-1/rules.d/50-snowfox.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.systemd1.manage-units" ||
         action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.reboot") &&
         subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

echo -e "${GREEN}✓${NC} Polkit konfiguriert (Shutdown/Reboot ohne Passwort)"

# 7. Configs kopieren
echo "⚙️  Kopiere Konfigurationen..."
mkdir -p \
    "$USER_HOME/.config/sway" \
    "$USER_HOME/.config/waybar" \
    "$USER_HOME/.config/wofi" \
    "$USER_HOME/.config/kitty" \
    "$USER_HOME/.config/swaylock" \
    "$USER_HOME/.config/mako" \
    "$USER_HOME/bin" \
    "$USER_HOME/Pictures/wallpapers"

safe_copy() {
    if [ -f "$SCRIPT_DIR/$1" ]; then
        cp "$SCRIPT_DIR/$1" "$USER_HOME/$2"
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${YELLOW}⚠${NC} $1 fehlt"
    fi
}

safe_copy "configs/sway-config"      ".config/sway/config"
safe_copy "configs/waybar-config"    ".config/waybar/config"
safe_copy "configs/waybar-style.css" ".config/waybar/style.css"
safe_copy "configs/wofi-style.css"   ".config/wofi/style.css"
safe_copy "configs/kitty.conf"       ".config/kitty/kitty.conf"
safe_copy "configs/swaylock-config"  ".config/swaylock/config"
safe_copy "configs/mako-config"      ".config/mako/config"
safe_copy "configs/bash_profile"     ".bash_profile"

# 8. Scripts
echo "📝 Installiere Scripts..."
if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp "$SCRIPT_DIR/scripts/"* "$USER_HOME/bin/" 2>/dev/null || true
    chmod +x "$USER_HOME/bin/"* 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Scripts installiert"
fi

# 9. Wallpapers
echo "🖼️  Installiere Wallpapers..."
if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    for img in "$SCRIPT_DIR/wallpapers/"*.png; do
        [ -f "$img" ] || continue
        cp "$img" "$USER_HOME/Pictures/wallpapers/"
        basename=$(basename "$img")
        name="${basename%.png}"
        convert "$USER_HOME/Pictures/wallpapers/$basename" \
            -blur 0x8 \
            "$USER_HOME/Pictures/wallpapers/${name}_blur.png" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} $basename"
    done
fi

# 10. Desktop File für SnowFox Store
mkdir -p "$USER_HOME/.local/share/applications"
cat > "$USER_HOME/.local/share/applications/snowfox-store.desktop" << EOF
[Desktop Entry]
Type=Application
Name=SnowFox Store
Comment=App Store für SnowFoxOS
Exec=$USER_HOME/bin/snowfox-store
Icon=system-software-install
Terminal=false
Categories=System;
EOF

# 11. Ownership fix
chown -R "$REAL_USER:$REAL_USER" \
    "$USER_HOME/.config" \
    "$USER_HOME/.local" \
    "$USER_HOME/bin" \
    "$USER_HOME/Pictures" \
    "$USER_HOME/.bash_profile" \
    2>/dev/null || true

# 12. Cleanup
echo "🧹 Aufräumen..."
apt autoremove -y -qq 2>/dev/null || true
apt clean 2>/dev/null || true

echo ""
echo "════════════════════════════════════════════════════"
echo -e "         ${GREEN}✅ SnowFoxOS v1.0 installiert!${NC}"
echo "════════════════════════════════════════════════════"
echo ""
echo "1. Abmelden:    exit"
echo "2. Neu anmelden"
echo "3. Sway startet automatisch!"
echo ""
echo "Shortcuts:"
echo "  Mod+Return   Terminal"
echo "  Mod+R        App-Menü"
echo "  Mod+F1       Alle Shortcuts"
echo "  Power-Button Power-Menü"
echo ""
