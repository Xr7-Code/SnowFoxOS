# SnowFoxOS v3.4

**Minimales i3-Desktop-System auf Debian 12 — 3-Farben-Design, vollständig installierbar via `git clone`.**

> Stack: i3 · Polybar · Rofi · Dunst · Kitty · Picom · PipeWire · bluetui

---

## Installation

**Voraussetzung:** Debian 12 (Bookworm) minimal, x86_64, Internetverbindung

```bash
git clone https://github.com/Xr7-Code/SnowFoxOS
cd SnowFoxOS
sudo chown -R root:root .
sudo chmod -R go-w .
sudo bash install.sh
```

Der Installer:
- erkennt automatisch Laptop/Desktop, AMD/NVIDIA/Intel GPU
- konfiguriert DNS-over-TLS (Cloudflare + Quad9) **vor** der ersten Paketinstallation
- fragt interaktiv nach: Browser, Steam, VSCodium, OnlyOffice, Drucker-Support
- rendert das Theme-System (`snowfox-dark` als Standard)

---

## Design

Drei Farben. Nicht mehr.

| Token    | Wert      | Verwendung                                   |
|----------|-----------|----------------------------------------------|
| `BG`     | `#111111` | Hintergrund überall (Bar, Fenster, Terminal) |
| `ACCENT` | `#9966cc` | Lila — alles Aktive, Fokussierte, Icons      |
| `FG`     | `#e8e8e8` | Text, inaktive Elemente                      |

**Aktiver Workspace / Selektion:** invertiert — Lila als Hintergrund, Schwarz als Text.  
**Alert/Urgent:** `#ff5555` (fest, nicht theme-fähig — Warnungen sollen immer rot sein).

Themes wechseln:
```bash
snowfox theme             # aktuelles Theme anzeigen
snowfox theme snowfox-dark   # Standard (dunkel, Lila)
snowfox theme snowfox-light  # Hell
snowfox theme snowfox-mono   # Monochrom (schwarz/weiß)
```

---

## Tastenkürzel

| Kürzel              | Aktion                        |
|---------------------|-------------------------------|
| `Super + Enter`     | Terminal (Kitty)              |
| `Super + Space`     | App-Launcher (Rofi)           |
| `Super + Tab`       | Fensterwechsel (Rofi)         |
| `Super + e`         | Dateimanager (PCManFM)        |
| `Super + n`         | Netzwerk-Einstellungen        |
| `Super + w`         | Hintergrundbild wechseln      |
| `Super + l`         | Bildschirm sperren            |
| `Super + p`         | Display-Einstellungen         |
| `Super + q`         | Fenster schließen             |
| `Super + f`         | Vollbild                      |
| `Super + Shift + e` | Power-Menü                    |
| `Print`             | Screenshot (Auswahl mit GUI)  |
| `Super + Print`     | Screenshot (Region)           |

---

## Struktur

```
install.sh          Haupt-Installer (sudo bash install.sh)
lib/                Installer-Module (10 Schritte)
cli/                snowfox CLI-Module
  theme.sh          Theme-Renderer (templates → ~/.config/)
themes/             Theme-Definitionen (BG, ACCENT, FG)
  snowfox-dark.theme
  snowfox-light.theme
  snowfox-mono.theme
  theme.conf        Aktives Theme + Render-Regeln
templates/          Config-Vorlagen mit ${BG} ${ACCENT} ${FG}
  polybar.ini.tmpl
  rofi.rasi.tmpl
  kitty.conf.tmpl
  i3-colors.conf.tmpl
  dunstrc.tmpl
  picom.conf.tmpl
  gtk-3.0.css.tmpl
  gtk-4.0.css.tmpl
  gtkrc-2.0.tmpl
configs/            Theme-unabhängige Laufzeit-Configs
  i3/config         Window Manager (importiert i3/colors.conf)
  polybar/          Statusbar + Skripte
  rofi/             Launcher-Stil (Standard-Fallback)
  dunst/            Benachrichtigungen (Standard-Fallback)
  kitty/            Terminal (Standard-Fallback)
wallpapers/         Hintergrundbilder
assets/             Logo, Grafiken
```

---

## Wie das Theme-System funktioniert

```
themes/snowfox-dark.theme   →   BG="#111111" ACCENT="#9966cc" FG="#e8e8e8"
         ↓
cli/theme.sh liest Tokens, ersetzt ${BG}/${ACCENT}/${FG} in allen templates/
         ↓
~/.config/polybar/config.ini
~/.config/rofi/config.rasi
~/.config/kitty/kitty.conf
~/.config/i3/colors.conf
~/.config/dunst/dunstrc
~/.config/picom.conf
~/.config/gtk-3.0/gtk.css
~/.config/gtk-4.0/gtk.css
~/.gtkrc-2.0
```

Ein neues Theme anlegen: Datei `themes/mein-theme.theme` mit `BG`, `ACCENT`, `FG` erstellen, dann `snowfox theme mein-theme`.

---

## Bluetooth

```bash
bluetui        # Bluetooth-TUI (Geräte suchen, verbinden, trennen)
```

Die Polybar zeigt den Bluetooth-Status. `bluetui` öffnet die vollständige TUI-Oberfläche.

---

## DNS

Beim Install wird DNS-over-TLS (strict) konfiguriert:

- Primary: `1.1.1.1` (Cloudflare)
- Fallback: `9.9.9.9` (Quad9)
- DNSSEC: aktiv
- Cleartext-Fallback: **deaktiviert** (strict mode)

Status prüfen: `systemd-resolve --status`

---

## Anforderungen

- Debian 12 (Bookworm) minimal
- x86_64 CPU
- Internetverbindung während der Installation
- mind. 4 GB Speicherplatz

---

## Lizenz

GPL-3.0 · Copyright © 2026 Alexander Valentin Ludwig (Xr7-Code)
