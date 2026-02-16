# 🚀 SnowFoxOS Installation Guide

Dieser Guide führt dich Schritt für Schritt durch die Installation von SnowFoxOS.

## 📋 Voraussetzungen

- Debian 13 (Trixie) **Minimal-Installation**
- Mindestens 10GB Festplattenspeicher
- Internet-Verbindung

## 🔧 Schritt 1: Debian Minimal installieren

1. **Download:** [Debian 13 Netinstall](https://www.debian.org/distrib/netinst)
2. **USB-Stick erstellen:** Mit Rufus, Balena Etcher, oder `dd`
3. **Boot:** Vom USB-Stick booten

### Bei der Installation:

**Software Selection:**
- ❌ Debian Desktop Environment
- ❌ GNOME / KDE / Xfce / LXDE
- ✅ SSH Server (optional, für Remote-Setup)
- ✅ Standard System Utilities

**Wichtig:** Keine Desktop-Umgebung auswählen!

## 🦊 Schritt 2: SnowFoxOS installieren

Nach dem ersten Boot und Login:

### Als root oder mit sudo:

```bash
# 1. Repository klonen
git clone https://github.com/USERNAME/SnowFoxOS.git
cd SnowFoxOS

# 2. Installer ausführen
chmod +x install.sh
sudo ./install.sh
```

Der Installer:
- ✅ Installiert alle benötigten Pakete
- ✅ Konfiguriert das System
- ✅ Installiert WiFi-Treiber
- ✅ Richtet Sway ein
- ✅ Kopiert alle Configs

**Dauer:** Ca. 10-15 Minuten (abhängig von Internet-Geschwindigkeit)

## 🎨 Schritt 3: Wallpapers hinzufügen

```bash
# Wallpapers nach ~/Pictures/wallpapers/ kopieren
# Du benötigst:
# - snowfox_dark.png (Hauptwallpaper)
# - snowfox_light.png (Optional: Helles Theme)

# Geblurrte Versionen für Lockscreen erstellen:
cd ~/Pictures/wallpapers
convert snowfox_dark.png -blur 0x8 snowfox_dark_blur.png
convert snowfox_light.png -blur 0x8 snowfox_light_blur.png
```

## 🎯 Schritt 4: Fertig!

```bash
# Abmelden
exit

# Wieder anmelden
# Sway startet automatisch!
```

## ⌨️ Erste Schritte

Nach dem Login:

1. **WiFi verbinden:** `Mod+N`
2. **Apps öffnen:** `Mod+R`
3. **Hilfe anzeigen:** `Mod+H`

## 🔧 Troubleshooting

### WiFi funktioniert nicht

```bash
# NetworkManager Status prüfen
systemctl status NetworkManager

# Neu starten
sudo systemctl restart NetworkManager

# Manuell verbinden
nmcli device wifi connect "SSID" password "PASSWORD"
```

### Sway startet nicht automatisch

```bash
# .bash_profile prüfen
cat ~/.bash_profile

# Sollte enthalten:
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec sway
fi
```

### Waybar zeigt nicht

```bash
# Waybar manuell starten
pkill waybar
waybar &

# In Sway neu laden
Mod+Shift+C
```

## 📚 Weitere Hilfe

- [README.md](README.md) - Übersicht
- [SHORTCUTS.md](SHORTCUTS.md) - Alle Tastenkombinationen
- [GitHub Issues](https://github.com/USERNAME/SnowFoxOS/issues) - Probleme melden

## 🎉 Fertig!

Viel Spaß mit SnowFoxOS! 🦊
