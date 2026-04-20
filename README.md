<h1 align="center">Discontinued</h1>

<p align="center">Active Project: SnowFoxOS-v2-i3</p>

# 🦊 SnowFoxOS

> **Minimal. Fast. Beautiful.**

Ein ultra-leichtgewichtiges Linux-Betriebssystem basierend auf Debian 13 mit Sway Wayland Compositor.
Perfekt für Entwickler, die einen cleanen, ablenkungsfreien Workspace wollen.

![SnowFoxOS]()

## ✨ Features

- 🪶 **Ultra-leicht** - Unter 1GB Installation
- ⚡ **Blitzschnell** - Sway Wayland Compositor
- 🎨 **Schönes Design** - Custom Lila/Orange Theme
- ⌨️ **Tastatur-fokussiert** - Vim-Style Navigation
- 🛠️ **Developer-friendly** - Alle Tools die du brauchst, nichts was du nicht brauchst
- 🔋 **Energieeffizient** - Optimiert für Laptops
- 🌐 **WiFi Ready** - Automatische Treiber-Installation

## 📸 Screenshots

*Screenshots folgen nach dem ersten Release*

## 🚀 Quick Install

**Voraussetzungen:** Frische Debian 13 (Trixie) Minimal-Installation

```bash
# Repository klonen
git clone https://github.com/Xr7-Code/SnowFoxOS.git
cd SnowFoxOS

# Installer ausführen
chmod +x install.sh
sudo ./install.sh
```

**Das war's!** Nach dem Abmelden startet Sway automatisch.

## 📋 System-Anforderungen

- **RAM:** 2GB (minimal 1GB)
- **Festplatte:** 10GB
- **CPU:** x86_64 (Intel/AMD)
- **Netzwerk:** WiFi oder Ethernet

## 🎯 Was ist enthalten?

### Core System
- **Sway** - Wayland Window Manager
- **Waybar** - Minimalistische Status-Bar
- **Wofi** - App-Launcher

### Essential Apps
- **Firefox ESR** - Web Browser
- **Kitty** - Terminal
- **Thunar** - File Manager
- **Neovim** - Text Editor

### Tools
- **SnowFox Store** - App Installation/Deinstallation
- **Smart Launcher** - Suche Apps & Files (Ctrl+Space)
- **WiFi Manager** - Einfaches WiFi-Management
- **Power Menu** - System-Kontrolle
- **Screenshots** - grim + slurp

## ⌨️ Keyboard Shortcuts

| Shortcut | Aktion |
|----------|--------|
| `Mod+Return` | Terminal öffnen |
| `Mod+B` | Firefox starten |
| `Mod+E` | Dateimanager |
| `Mod+R` | App-Menü |
| `Ctrl+Space` | Smart Launcher (Apps + Files) |
| `Mod+N` | WiFi Manager |
| `Mod+X` | Bildschirm sperren |
| `Mod+,` | Settings |
| `Mod+H` | Shortcuts-Hilfe |
| `Mod+1-5` | Workspace wechseln |
| `Mod+Tab` | Nächster Workspace |
| `Alt+Tab` | Nächstes Fenster |
| `Print` | Screenshot |

**Vollständige Liste:** Siehe [SHORTCUTS.md](SHORTCUTS.md)

## 📚 Dokumentation

- [Installation Guide](INSTALL.md)
- [Keyboard Shortcuts](SHORTCUTS.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)

## 🎨 Design-System

SnowFoxOS nutzt ein konsistentes Design-System:

- **Primärfarbe:** `#9B59B6` (Lila)
- **Akzentfarbe:** `#E67E22` (Orange)
- **Hintergrund:** `#0a0a0a` (Schwarz)
- **Text:** `#ffffff` (Weiß)

## 🛠️ Anpassung

Alle Configs findest du in `~/.config/`:
- Sway: `~/.config/sway/config`
- Waybar: `~/.config/waybar/`
- Wofi: `~/.config/wofi/`
- Kitty: `~/.config/kitty/kitty.conf`

## 🤝 Lizenz

Siehe [LICENSE](LICENSE) für Details.

**Kurz:** Privat nutzen ✅ | Lernen ✅ | Veröffentlichen ❌

## 💬 Support & Community

- **Issues:** [GitHub Issues](https://github.com/Xr7-Code/SnowFoxOS/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Xr7-Code/SnowFoxOS/discussions)

## 🙏 Credits

Erstellt mit ❤️ und ☕

Basierend auf:
- Debian 13 (Trixie)
- Sway
- Waybar
- Und vielen anderen Open-Source-Projekten
