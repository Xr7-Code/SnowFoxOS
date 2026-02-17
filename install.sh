#!/bin/bash

# SnowFoxOS Installer v1.6
# Strategie: Elogind-First & No-Recommends

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben für die Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "===================================================="
echo -e "          ${GREEN}🦊 SnowFoxOS Installation Script v1.6${NC}"
echo "===================================================="

# 1. Root & User Check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Fehler: Bitte als root ausführen (sudo bash install.sh)${NC}"
    exit 1
fi

if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    echo -e "${RED}❌ Fehler: Bitte mit sudo ausführen!${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Installiere für: $REAL_USER in $USER_HOME"

# 2. System Vorbereitung
echo "📦 Aktualisiere Paketquellen..."
apt update -qq

# 3. Den Systemd-Konflikt aktiv lösen
echo "🛡️  Blockiere systemd-sysv und bereite Elogind vor..."
# Wir verhindern, dass systemd-sysv jemals angefasst wird
apt-mark hold systemd-sysv 2>/dev/null || true

# Spezielle Optionen für eine "saubere" Installation ohne systemd-Beifang
APT_OPTS="-y -qq -o APT::Install-Recommends=0 -o APT::Install-Suggests=0"

echo "📦 Installiere Core-System (Elogind & Sway)..."
# Zuerst Elogind fixieren
DEBIAN_FRONTEND=noninteractive apt install $APT_OPTS elogind libpam-elogind libelogind0

# Dann den Rest ohne Recommends installieren
DEBIAN_FRONTEND=noninteractive apt install $APT_OPTS \
    sway waybar wofi kitty thunar firefox-esr neovim \
    network-manager grim slurp wl-clipboard swaylock \
    mako-notifier brightnessctl pulseaudio pavucontrol \
    git curl wget htop imagemagick swaybg \
    fonts-noto fonts-font-awesome libnotify-bin swayidle

# 4. Treiber (Optional)
echo "🔧 Installiere Firmware-Pakete..."
DEBIAN_FRONTEND=noninteractive apt install $APT_OPTS \
    firmware-linux-free firmware-linux-nonfree \
    firmware-misc-nonfree firmware-realtek firmware-iwlwifi \
    intel-microcode amd64-microcode || echo -e "${YELLOW}⚠ Einige Treiber fehlen (nicht kritisch).${NC}"

# 5. Netzwerk-Konfiguration
echo "🌐 Konfiguriere NetworkManager..."
for svc in dhcpcd networking wpa_supplicant; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
done

mkdir -p /etc/NetworkManager/conf.d/
cat > /etc/NetworkManager/conf.d/snowfox.conf << 'EOF'
[main]
plugins=ifupdown,keyfile
[ifupdown]
managed=true
[connection]
wifi.powersave=2
EOF
systemctl enable NetworkManager && systemctl restart NetworkManager

# 6. Sudoers für Power-Management
echo "🔑 Erlaube Power-Management ohne Passwort..."
echo "%sudo ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown" > /etc/sudoers.d/snowfox-power
chmod 440 /etc/sudoers.d/snowfox-power

# 7. Verzeichnisse erstellen
echo "⚙️  Erstelle Ordnerstruktur..."
mkdir -p "$USER_HOME/.config/sway" "$USER_HOME/.config/waybar" \
         "$USER_HOME/.config/wofi" "$USER_HOME/.config/kitty" \
         "$USER_HOME/.config/swaylock" "$USER_HOME/.config/mako" \
         "$USER_HOME/bin" "$USER_HOME/Pictures/wallpapers"

# 8. Dateien kopieren
echo "⚙️  Kopiere Konfigurationen..."
cp_if_exists() {
    if [ -f "$SCRIPT_DIR/configs/$1" ]; then
        cp "$SCRIPT_DIR/configs/$1" "$USER_HOME/$2"
        echo -e "${GREEN}✓${NC} $1 installiert"
    else
        echo -e "${YELLOW}⚠${NC} $1 fehlt in /configs"
    fi
}

cp_if_exists "sway-config" ".config/sway/config"
cp_if_exists "waybar-config" ".config/waybar/config"
cp_if_exists "waybar-style.css" ".config/waybar/style.css"
cp_if_exists "wofi-style.css" ".config/wofi/style.css"
cp_if_exists "kitty.conf" ".config/kitty/kitty.conf"
cp_if_exists "swaylock-config" ".config/swaylock/config"
cp_if_exists "bash_profile" ".bash_profile"

# 9. Scripts & Wallpapers
if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp -r "$SCRIPT_DIR/scripts/"* "$USER_HOME/bin/" 2>/dev/null || true
    chmod +x "$USER_HOME/bin/"* 2>/dev/null || true
fi

if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    cp "$SCRIPT_DIR/wallpapers/"*.png "$USER_HOME/Pictures/wallpapers/" 2>/dev/null || true
fi

# 10. Finale Rechtevergabe
echo "🔐 Setze Dateirechte für $REAL_USER..."
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config"
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/bin"
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/Pictures"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.bash_profile"

echo -e "\n${GREEN}════════════════════════════════════════════════════"
echo -e "          ✅ SnowFoxOS erfolgreich installiert!"
echo -e "════════════════════════════════════════════════════${NC}"
echo "Tippe 'exit' und logge dich neu ein, um Sway zu starten."
