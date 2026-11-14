# SnowFoxOS v4 — Master-Plan

**Rolle dieses Dokuments:** Das ist der zentrale Plan. Du (der menschliche Planer) gibst die einzelnen Abschnitte als Prompts an andere KIs (z. B. Deepseek). Jede KI bekommt nur ihren eigenen Abschnitt plus den gemeinsamen Kontext am Anfang. Am Ende werden die Ergebnisse in dieses Repo integriert.

---

## 0. Gemeinsamer Kontext (in JEDEN Prompt kopieren)

```text
Projekt: SnowFoxOS v4 — ein Single-Script-Installer, der ein minimales Debian 12
(Bookworm) in ein konfiguriertes i3/X11-Desktop-System verwandelt. Kein eigenes OS.

Ziele v4:
- Debian 12 Bookworm, amd64, i3 WM auf X11 (kein Wayland).
- Klein, ressourceneffizient (Ziel: Idle-PSS unter ~180 MB), keine App-Empfehlungen.
- Starke Sicherheit: unattended-upgrades (Security-Pocket), UFW default-deny incoming,
  SSH deaktiviert, sysctl-Hardening, DNS-over-TLS (systemd-resolved), zram.
- Kernel: XanMod LTS (x64v3) wenn AVX2 vorhanden, sonst automatischer Fallback auf
  das Standard-Debian-Kernel. Fallback muss immer bootfähig bleiben.
- System- und CLI-Sprache: Englisch. Installer fragt: Sprache, Land/Zeitzone,
  Tastaturlayout.
- Theming: minimale Palette-Dateien (siehe Abschnitt 2 dieses Plans).
- DESIGN-GRUNDREGEL: 2-Farben-Minimalismus — eine Hintergrundfarbe, eine Akzentfarbe
  (die auch Text-Highlights übernimmt), abgeleitetes fg/fg_dim. KEINE Transparenz
  irgendwo im System (keine Alpha-Werte in polybar/rofi/kitty/i3/dunst Defaults;
  kitty-Transparenz aus v3 entfällt). Auswahl/Invertierung: aktiver Workspace und
  Rofi-Auswahl invertieren bg und accent (Hintergrund = accent, Schrift = bg).
  Nerd Fonts (JetBrainsMono Nerd Font) sind Standard. Design-Referenz: die alte
  minimalistische 3-Color-Polybar-Config (seamless pills, border-bottom in accent).
- Eigenes Dock in C (reines Xlib, keine Toolkit-Abhängigkeit).
- Zwei getrennte Installationspfade: git-clone (interaktiv) und ISO/simple-cdd
  (nicht-interaktiv, Phase-Modus).
- Alle Bash-Skripte: #!/usr/bin/env bash, set -euo pipefail, shellcheck-clean.
- Paketliste ohne Recommends (APT::Install-Recommends=false) — alles Nötige explizit.
- Lizenz: GPL-3.0.
- VERSION-Datei im Repo-Root enthält NUR die aktuelle Version (Semver, z. B. "4.0.0").
  Alle Version-Referenzen (install.sh-Banner, snowfox CLI, os-release/PRETTY_NAME,
  GRUB/Plymouth-Branding, build-stamp im ISO-Pfad, README-Badge) lesen sie aus
  lib/utils.sh (get_version(): cat VERSION, trim, Validierung gegen Semver).
  Keine hartcodierten Versionsnummern in anderen Dateien.
```

---

## 0b. Spezifikations-Entscheidungen aus Prompt 1 (verbindlich, gelten für alle Prompts)

1. **Phasen-API = `lib/phase.sh`.** Kein Modul parst `--phase` selbst. Neue Phase = ein `case`-Eintrag in `phase_modules()` + Tabelleneintrag in `installer/phases.md`.
2. **systemctl-Shim zentral** in `phase.sh` (`install_chroot_systemctl_shim`, aus v3-install.sh verschoben). Module rufen `systemd_safe <verb> <unit>` oder direkt `systemctl` (vom Shim abgefangen). Keine eigenen Chroot-Checks in Modulen.
3. **`ask_install <prompt> [default=no]`** — kein Regex-Matching. Wer Auto-Install will, übergibt `yes` explizit (z. B. `ask_install "unattended-upgrades (security only)" yes`).
4. **`extras` = toter Alias** mit Deprecation-Warnung + Exit 0. Prompt 7 entfernt den Aufruf aus `installer/overlay/40-firstboot.sh`; danach darf der Alias in v4.x gelöscht werden. Bis dahin nicht anfassen.
5. **Load-Guards:** `_SNOWFOX_UTILS_LOADED`, `_SNOWFOX_PHASE_LOADED`, `_SNOWFOX_THEME_ENGINE_LOADED` (falls Prompt 2 eine `lib/theme_engine.sh` anlegt; `cli/theme.sh` wird dünner Wrapper).
6. **Default-Flow-Parität:** `full` = v3-Reihenfolge minus `browser_selection.sh`, `mesh_module.sh`, `gaming_ai.sh`. Kein `--phase legacy-full`.
7. **`set -euo pipefail`** nur in `install.sh` und eigenständigen CLI-Modulen, **nicht** in `lib/*.sh` (werden gesourcret).
8. **`SCRIPT_DIR`** wird von `install.sh` exportiert und von allen Modulen nur gelesen. Reihenfolge in `install.sh`: source `utils.sh` → source `phase.sh` → `phase_parse_args "$@"`.
9. **Exportierte Variablen** (`TARGET_USER`, `TARGET_HOME`, `HAS_NVIDIA/AMD/INTEL`, `IS_LAPTOP`, `SNOWFOX_NETWORK`, `DKMS_HOOKS_FILE`, `DEFAULT_*_DESKTOP`) setzt nur `install.sh` bzw. `detect_target_user`/`detect_hardware` — Module lesen sie nur. Ausnahme: `kernel_drivers.sh` verfeinert `HAS_*` (wie v3). `performance_security.sh` nutzt `[[ "${IS_LAPTOP:-false}" == "true" ]]` (Fix aus Prompt 5).
10. **lib/firstboot.sh** existiert als Stub (wird von `phase_modules firstboot` erwartet; Lücke im Plan §1, durch Prompt 1 geschlossen).

---

## 1. Neue Repository-Struktur (v4)

```text
SnowFoxOS/
├── VERSION                         # NEU: einzige Version-Quelle (z. B. "4.0.0"), Single Source of Truth
├── install.sh                      # Einstieg: interaktiv (default) oder --phase <name>
├── snowfox                         # CLI-Dispatcher → /usr/local/bin/snowfox
├── lib/                            # Installations-Module (Steps, wie v3, refactored)
│   ├── utils.sh                    #   Farben, Logging, ask_install (defaults-aware), apt-lock
│   ├── phase.sh                    #   NEU: --phase-Argumente, --defaults, Chroot-Safety-Guards
│   ├── base_system.sh              #   Step 1: Basispakete, sources.list, i386, resolved, Xwrapper
│   ├── kernel_drivers.sh           #   Step 2: AVX2-Check → XanMod LTS / Debian-Fallback, GPU-Detection
│   ├── desktop_environment.sh      #   Step 3: i3, polybar, rofi, dunst, picom, foxdock-Build
│   ├── audio_terminal.sh           #   Step 4: PipeWire, WirePlumber, kitty
│   ├── default_apps.sh             #   Step 5: PCManFM, Geany, Flameshot, yt-dlp, mpv (keine Extras)
│   ├── performance_security.sh     #   Step 6: zram, sysctl, UFW, DoT, unattended-upgrades, Dienste aus
│   ├── theming_finishing.sh        #   Step 7: Theme-Engine-Setup, GTK 2/3/4, MIME, Fonts, Cursor
│   ├── boot_screen.sh              #   Step 8: Plymouth + GRUB-Theme
│   ├── firstboot.sh                #   Phase firstboot: Session-Reste, GPU-Retry (Stub aus Prompt 1)
│   └── cleanup_final.sh            #   Final: autoremove, Banner
├── cli/                            # snowfox-CLI-Module (/usr/local/lib/snowfox/cli/)
│   ├── utils.sh                    #   Farben, header/row/bar (neues, ruhigeres Design)
│   ├── help.sh                     #   snowfox help
│   ├── status.sh                   #   snowfox status / battery
│   ├── system.sh                   #   snowfox update / profile / reset
│   ├── hardware.sh                 #   snowfox kill / air / gpu
│   ├── security.sh                 #   snowfox audit / audit live
│   ├── media.sh                    #   snowfox stream / dl / fetch
│   ├── desktop.sh                  #   snowfox auto / layout / web
│   ├── stash.sh                    #   snowfox stash
│   ├── settings.sh                 #   snowfox set / bt / kb / lang / tz / user / def
│   ├── theme.sh                    #   snowfox theme (Palette-Engine, siehe Abschnitt 2)
│   ├── wallpaper.sh                #   snowfox wallpaper (inkl. Auto-Palette aus Bild, Abschnitt 3)
│   ├── doctor.sh                   #   snowfox doctor
│   └── snap.sh                     #   snowfox snap (Config-Backups)
├── foxdock/                        # NEU: eigenes Dock in C (reines Xlib)
│   ├── src/
│   │   ├── main.c
│   │   ├── config.c / config.h     #   liest dock.conf + palette
│   │   ├── launcher.c / launcher.h #   .desktop-Parsing (eigener Mini-Parser, keine GLib)
│   │   ├── draw.c / draw.h         #   Xlib-Rendering, Icons via Xpm/Imlib2 (eine Lib, minimal)
│   │   └── palette.c / palette.h   #   liest ~/.config/snowfox/palette.conf, live-reload via SIGHUP
│   ├── Makefile
│   └── README.md
├── configs/foxdock/dock.conf       # Dock-Einträge-Vorlage (wird in Prompt 3 angelegt)
├── configs/                        # Desktop-Konfigurationen → ~/.config/
│   ├── i3/config
│   ├── polybar/ (config.ini, launch.sh, scripts/)
│   ├── rofi/config.rasi
│   ├── kitty/kitty.conf
│   ├── dunst/dunstrc
│   ├── picom.conf
│   ├── snowfox/
│   │   ├── themes/                 #   Theme-Dateien (Abschnitt 2)
│   │   │   ├── nightfox.theme      #     schwarz/grau + Lila (Standard, aus deinem Bild)
│   │   │   ├── dayfox.theme        #     hell
│   │   │   └── mono.theme          #     grau, Akzent grau
│   │   ├── palette.conf            #   AKTIVE Palette (generiert aus gewähltem Theme)
│   │   └── wallpaper.conf          #   aktives Wallpaper + auto-color-Ergebnis
│   ├── scripts/ (lock.sh, powermenu.sh, network.sh, display.sh, clip-saver.sh)
│   └── gtk/ (gtkrc-2.0, gtk-3.0/, gtk-4.0/, xsettingsd/)
├── installer/                      # Vorbereitung für späteren ISO-Builder
│   ├── phases.md                   #   Phase-Doku (iso-base, iso-gpu, firstboot)
│   ├── preseed/snowfox.preseed     #   aus v3 übernommen (§2 der alten Work Order)
│   ├── overlay/                    #   late.sh, 10-apt-policy.sh, 20-base.sh, 30-gpu.sh,
│   │                               #   40-firstboot.sh, firstboot/ — Struktur aus v3-Work-Order
│   └── apt/99-snowfox              #   APT-Policy (Recommends off)
├── completions/snowfox-completion.bash
├── assets/  wallpapers/  docs/
└── README.md  LICENSE  PROJECT_STRUCTURE.md
```

**Entfernt gegenüber v3** (Kern-Only-Entscheidung): `mesh_module.sh`, `cli/mesh.sh`, `snowfox-mesh.sh`, `cli/immersion.sh`, `cli/music.sh`, `cli/ai.sh`, `gaming_ai.sh`, `browser_selection.sh` (Browser wird über `snowfox stash` nachinstalliert), `iso-builder/` (erstmal nur `installer/`-Vorbereitung).

**Bewusst behalten / wiederverwenden:** Theme-Engine-Idee aus `cli/theme.sh` (Master-Palette, in-place Rendering, idempotent, Backup), `cli/snap.sh`, `stash.sh`, `security.sh`, Tor-Modul optional als Stash-Paket, Hybrid-GPU-Fixes aus `kernel_drivers.sh`, die komplette ISO-Work-Order (Preseed, Overlay-Skripte, Phasen-Modus) in `installer/`.

---

## 2. Theme-System (Minimal-Palette) — Spezifikation

### 2.1 Theme-Datei-Format

Eine Theme-Datei (z. B. `~/.config/snowfox/themes/nightfox.theme`) ist schlichtes Key=Value:

```ini
# SnowFoxOS theme: nightfox
dark = true

# Kernfarben (das Herz: 3 Akzente + 4 Neutralwerte)
accent       = #9B59B6   # Primär-Akzent (Lila)
accent2      = #6C3483   # Sekundär-Akzent (dunkler Lila)
accent3      = #B07CC6   # Tertiär (heller Lila, Hover/Fokus)
bg           = #2B2F38   # Fenster-/Bar-Hintergrund
bg2          = #343945   # Erhöhte Flächen (Rofi, Popups)
fg           = #E5E9F0   # Vordergrund-Text
fg_dim       = #8A919E   # Gedimmter Text, Trenner

# Terminal-Palette (16 Farben + bg/fg/cursor) — Standardwerte je Theme
term.color0  = #3B4252
term.color1  = #BF616A
term.color2  = #A3BE8C
term.color3  = #EBCB8B
term.color4  = #81A1C1
term.color5  = #B48EAD
term.color6  = #88C0D0
term.color7  = #E5E9F0
term.color8  = #4C566A
term.color9  = #D07A7F
term.color10 = #B1C89A
term.color11 = #E4CE91
term.color12 = #93B5CC
term.color13 = #C09AB8
term.color14 = #9BCAD8
term.color15 = #ECEFF4
term.bg      = #2E3440
term.fg      = #E5E9F0
term.cursor  = #9B59B6
```

Regeln:
- Nur die 8 Kernfarben + `dark` sind Pflicht; Terminal-Farben haben Default-Werte, die aus den Kernfarben abgeleitet werden, wenn sie fehlen (`accent` färbt color5/13, `bg`/`fg` erben).
- Nutzer können eigene `.theme`-Dateien in `themes/` ablegen — sie erscheinen automatisch in `snowfox theme` und im Rofi-Picker.
- `dark = true|false` schaltet systemweit GTK-Präferenz (`gtk-application-prefer-dark-theme` für GTK3/4, GTK2-Theme-Wahl, Qt via qt5ct, xsettingsd) um.

### 2.2 Design-Prinzipien (2-Farben-Minimalismus) — verbindlich für ALLE Komponenten

1. **Eine Hintergrundfarbe pro Fläche.** Bar, Module, Rofi, Dunst, foxdock nutzen `bg` (bzw. `bg2` für erhöhte Flächen). Seamless pills wie in der alten Polybar-Config: Module erben die Bar-Hintergrundfarbe, keine farbigen Kacheln.
2. **Eine Akzentfarbe, die Text übernimmt.** `accent` färbt Icons, aktive Elemente, CLI-Kopfzeilen, Hover, Fokus-Rahmen (i3 `client.focused`), Dunst-Highlights, foxdock-Hover.
3. **Invertierung statt Hervorhebung.** Aktiver Workspace (polybar `label-focused`), Rofi-Auswahl und foxdock-aktives Icon: `background = accent`, `foreground = bg`. Nie beides mischen.
4. **Keine Transparenz.** Keine Alpha-Werte in Defaults (kein `#CC201e2e`, keine kitty-Opacity). `picom` läuft mit voll opaken Fenstern (rounded corners + shadows erlaubt, fading aus).
5. **Semantische Statusfarben** (grün/gelb/rot für Battery/Volume/Audit) sind fest definierte abgeleitete Werte der Engine, keine Theme-Pflicht-Keys — sie werden beim Rendern aus dem Theme berechnet (fixe Hue-Werte, an `bg`-Helligkeit angepasst).
6. **Nerd Fonts überall:** JetBrainsMono Nerd Font ist die Standard-Font für polybar, kitty, rofi, dunst, foxdock-Text.
7. **Design-Referenz:** die alte minimalistische 3-Color-Polybar-Config (36 px Bar, seamless pills, `border-bottom-size = 1` in Akzentfarbe, Launcher-Icon in `accent`, Workspaces mit invertiertem Fokus-Label). Diese Config wird als Ausgangsbasis für `configs/polybar/config.ini` übernommen, mit allen Farbwerten gegen die Palette getauscht und Alpha-Werte entfernt.

### 2.3 Aktive Palette & Rendering

- `snowfox theme <name>`: kopiert Theme → `~/.config/snowfox/palette.conf`, rendert dann alle Komponenten in-place (gleiche Technik wie v3-Engine: bekannte Farbwerte ersetzen, idempotent, Backup nach `~/.config/snowfox/theme-backup.tar.gz`).
- Betroffene Ziele: i3, polybar, rofi, kitty, dunst, picom, GTK2/3/4, xsettingsd, lock screen, foxdock (via SIGHUP live-reload, kein Neustart nötig).
- `snowfox theme` (ohne Argument) listet Themes mit Farbfeldern; `snowfox theme check` validiert Pflicht-Keys und Eindeutigkeit.
- Die 31 Token aus v3 werden auf ~12 reduziert: 8 Kernfarben + Terminal-Block. Alles andere wird aus diesen abgeleitet. Alpha-Varianten entfallen (Design-Regel 4).

---

## 3b. Standard-Browser (Empfehlung)

Drei Kategorien, jeweils ein Kandidat — installierbar über `snowfox stash browser`:

| Kategorie | Empfehlung | Begründung |
|---|---|---|
| **Firefox-Basis** | **Firefox ESR** (Debian-Repo) | Direkt aus dem Debian-Repo (kein Fremd-Repo, keine Flatpak-Abhängigkeit), Security-Updates über unattended-upgrades mit abgedeckt, ESR = stabile Oberfläche. Für mehr Privacy: **LibreWolf** als Stash-Option (hardened Firefox, eigenes Repo). |
| **Chromium-Basis** | **Chromium** (Debian-Repo) | Im offiziellen Debian-Repo, saubere Updates. **Brave** nur als Stash-Option (eigenes Repo nötig, aber stärkeres Tracking-Blocking out-of-the-box). |
| **Andere** | **Zen Browser** | Firefox-basiert, moderne UI, Arc-artiges Workspace-Konzept — passt zum i3-Workflow und war in v3 schon der Default. Nachteil: externes Repo, nicht in Debian. Alternativ für Minimalisten: **Falkon** (Qt, klein) oder **qutebrowser** (vim-like, perfekt für i3-Nutzer). |

**v4-Default:** Firefox ESR. Begründung: einzige Kategorie, die komplett über unattended-upgrades mitaktualisiert wird, ohne Fremd-Repo — konsistent mit dem Sicherheitsziel des Systems. Zen, LibreWolf, Brave, Chromium, qutebrowser bleiben Ein-Klick-Optionen im Stash.

---

## 3. Auto-Palette aus Wallpaper

- `snowfox wallpaper` opens Rofi-Wallpaper-Auswahl (Bestand aus v3) + Option `auto`.
- `snowfox wallpaper auto <pfad>` (bzw. Toggle in der Auswahl):
  1. Bild auf max. 256 px Kante mit ImageMagick (`convert -resize`) verkleinern.
  2. Farbanalyse: `convert <img> -colors 8 -unique-colors txt:` → 8 dominante Farben.
  3. Auswahlogik (kleines awk/bash-Skript oder in C im foxdock-Palette-Modul):
     - `bg` = dunkelste Farbe (bei Darkmode) bzw. hellste (bei Lightmode).
     - `accent` = Farbe mit höchster Sättigung, die zum `bg` genug Kontrast hat (WCAG-ähnliche Heuristik: Kontrastverhältnis ≥ 4.5 für Text auf bg, ≥ 3.0 für Akzent auf bg).
     - `accent2` = dunklere/aczentverwandte Variante, `accent3` = hellere Variante (HSL-Verschiebung, `accent` um ±15° Hue, bei Bedarf via `convert <color> -modulate`).
     - `fg` = weiß/near-weiß bei dunklem bg, near-schwarz bei hellem bg.
  4. Ergebnis wird als `wallpaper-auto.theme` gespeichert, aktiviert und in `wallpaper.conf` protokolliert (`source=<pfad>`).
- Nutzer kann mit `snowfox theme <name>` jederzeit zurück zu einem festen Theme.
- Abhängigkeit: `imagemagick` (ohne X-Extras), wird ohnehin für Lock-Screen-Blur genutzt.

---

## 4. foxdock — Dock in C (reines Xlib)

**Zweck:** schmaler Dock am linken Bildschirmrand (wie im Referenz-Bild), dient als kleines Startmenü.

- **Abhängigkeiten:** nur `libx11-dev` + eine Icon-Lib (`libxpm-dev` oder `imlib2` — Entscheidung im Task 2, Empfehlung: Imlib2, da PNG-Icons und Skalierung). Kein GTK, kein GLib → wenige MB, minimaler RAM (~5–10 MB).
- **Funktionen (v4.0, bewusst klein):**
  - Vertikale Icon-Leiste, Links ausrichtung, feste Icon-Größe (32/48 px konfigurierbar).
  - Einträge aus `~/.config/foxdock/dock.conf` (`name;icon;exec`) + Auto-Scan von `.desktop`-Dateien in `/usr/share/applications` (eigener Mini-Parser, kein GLib).
  - Klick startet Programm (`fork` + `exec`, Doppelklick-Schutz).
  - Hover-Effekt (Akzentfarbe), Tooltip mit Programmnamen.
  - Palette live-reload via SIGHUP.
  - Struts: reserviert Platz in i3 (`i3.config`: `for_window [class="FoxDock"] border none, sticky enable`).
- **Nicht in v4.0:** Fensterliste, Tray, Drag&Drop — ggf. v4.1.
- i3-Config: foxdock auf allen Workspaces sticky, polybar oben bleibt.

---

## 5. CLI-Redesign

Prinzipien: ruhig, minimal, englisch, keine Deko-ASCII-Art im Normalbetrieb.

- **Layout:** Kopfzeile `snowfox <command>` in Akzentfarbe, darunter Key-Value-Zeilen mit alignierten Spalten, Status als farbige Punkte (● grün/gelb/rot) statt langer Texte. Keine Spinner außer bei Aktionen > 2 s.
- **Befehlsnamen:** Klartext statt Kürzel als Primärform; Kürzel bleiben als Aliase:
  `status (st)`, `update (up)`, `profile (prof)`, `doctor (doc)`, `audit`, `theme`, `wallpaper (wall)`, `stash`, `set`, `kill`, `air`, `stream`, `dl`, `fetch`, `auto`, `layout (lay)`, `web`, `snap`, `reset`, `help (h)`.
- **Neu/entfallen:** `theme` und `wallpaper` werden eigene Top-Level-Befehle; `bat` → `status battery`; `st` → `status`; `node`/`tor`/`mesh`/`ai`/`music`/`immersion` entfallen (Tor später optional über stash).
- **Exit-Codes:** 0 ok, 1 Fehler, 75 "Netzwerk nicht verfügbar" (wichtig für ISO-Phase).
- `snowfox help` gruppiert nach System / Hardware & Privacy / Media / Desktop / Theme / Settings.

---

## 6. Installer & Phasen (Vorbereitung für ISO)

- `install.sh` bekommt `--phase <name>` und `--defaults` (aus der v3-ISO-Work-Order 1:1 übernommen):
  | Phase | Inhalt |
  |---|---|
  | (ohne) | Interaktiv, voller Flow — Verhalten identisch zu heute |
  | `iso-base` | Steps 1, 3, 4, 5 (defaults), 6 (performance_security), 7 (theming), 8 (boot) — chroot-sicher |
  | `iso-gpu` | Step 2 — darf mit Exit 75 scheitern (kein Netz), Fallback-Kernel bleibt |
  | `firstboot` | Session-Reste, Browser-Optional, GPU-Retry |
- Chroot-Regeln: `systemctl start/restart` nur wenn `[ -d /run/systemd/system ]`, sonst `enable`. Kein User-Create in Phase-Mode (`getent passwd 1000`).
- `installer/preseed/snowfox.preseed`: exakt die verbatim-Datei aus der alten Work Order (Sprache/Land/Keyboard bleiben interaktiv, Passwörter nie preseeded).
- `installer/overlay/`: late.sh + 10-apt-policy + 20-base + 30-gpu + 40-firstboot + firstboot-Unit, wie in der Work Order §4 beschrieben.
- **Neu in v4:** `unattended-upgrades` aktiviert (Security-Pocket only) — `lib/performance_security.sh` installiert und konfiguriert `50unattended-upgrades` (nur `-security`), Daily-Timer an. Das ersetzt das v3-Problem "keine automatischen Security-Updates".
- APT-Policy `installer/apt/99-snowfox` (Recommends/Suggests off) wird auf beiden Pfaden installiert; `lib/base_system.sh` auditet die Paketlisten dagegen (Dry-Run-Vergleich, Doku in `docs/PACKAGES.md`).
- Der eigentliche `iso-builder/` (simple-cdd, Tasks 1–10 der alten Work Order) wird erst nach stabilisierter v4-Struktur umgesetzt — die Work Order bleibt dafür die Grundlage, mit angepassten Step-Nummern.

---

## 7. Kernel & Sicherheit (Kernaussagen für alle Module)

- XanMod LTS `x64v3` nur bei AVX2 (`grep -q avx2 /proc/cpuinfo`), sonst Standard-Debian-Kernel; beides bleibt bootbar (GRUB-Eintrag für Fallback-Kernel).
- Unattended-Upgrades: Security-only, täglich, E-Mail aus, `Unattended-Upgrade::Remove-Unused-Dependencies "true"`.
- Sysctl-Hardening + Netzwerk-Sysctls aus v3 unverändert übernehmen (Dateien `99-snowfox-security.conf`, `99-snowfox.conf`).
- UFW default-deny incoming / allow outgoing, SSH disabled + masked.
- DoT via systemd-resolved (Cloudflare + Quad9).
- Dienste deaktiviert: cups-browsed, avahi-daemon, ModemManager, colord, apt-daily (nur während Installation), NetworkManager-wait-online.
- zram lz4 50 %, swappiness 10, fstab noatime, kein Display-Manager (startx aus TTY1).

---

## 8. Umsetzungs-Reihenfolge (Roadmap)

1. **Repo-Skelett** + `lib/phase.sh` + utils-Refactor (defaults-aware).
2. **Theme-Engine v4** (Palette-Format, Renderer, 3 Standard-Themes, GTK-Darkmode-Switch).
3. **foxdock** (C, Xlib/Imlib2, Makefile, i3-Integration).
4. **CLI-Redesign** (alle Module auf neues Design, englische Texte, Aliase).
5. **Installer-Refactor** (Phasen, unattended-upgrades, Recommends-Audit).
6. **Wallpaper-Auto-Palette** (ImageMagick-Analyse + Theme-Generierung).
7. **installer/ ISO-Vorbereitung** (Preseed + Overlay aus Work Order portieren).
8. **Doku** (README, PROJECT_STRUCTURE, docs/PACKAGES.md) + QEMU-Tests beider Pfade.

---
---

# KI-Prompts (nacheinander an andere KIs geben)

Jeder Prompt ist eigenständig. Kopiere den Block aus "Abschnitt 0" (gemeinsamer Kontext) an den Anfang jedes Prompts.

---

## Prompt 1 — Repo-Skelett & Phasen-Layer

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Erstelle die Repository-Struktur für SnowFoxOS v4 gemäß Abschnitt 1 und 6
dieses Plans und implementiere den Phasen-Layer:

1. Lege die komplette Ordnerstruktur an (nur Datei-Stubs mit korrektem Shebang und
   set -euo pipefail, keine Logik).
2. Schreibe lib/phase.sh:
   - Parst install.sh-Argumente: --phase iso-base|iso-gpu|firstboot, --defaults.
   - Exportiert SNOWFOX_PHASE und SNOWFOX_DEFAULTS.
   - Bietet Guard-Funktionen: require_tty (bricht ab in Chroot ohne /run/systemd/system),
     systemd_safe (enable statt start außerhalb echter Sessions),
     detect_target_user (getent passwd 1000, Fehler wenn fehlt und Phase-Mode).
3. Passe lib/utils.sh an: ask_install() respektiert SNOWFOX_DEFAULTS (auto-answer default),
   alle read-Prompts bekommen Timeout/Default im Phase-Mode.
4. install.sh: default = alter interaktiver Flow (unverändert!), mit --phase werden nur
   die in Abschnitt 6 genannten Module in der angegebenen Reihenfolge gesourcret.
5. Alles shellcheck-clean.

Akzeptanz: install.sh ohne Argument verhält sich exakt wie vorher (Modul-Liste
identisch); --phase iso-base sourcet nur die erlaubten Module; alle Stubs passieren
shellcheck.
```

---

## Prompt 2 — Theme-Engine v4

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Implementiere das Theme-System aus Abschnitt 2 des Plans komplett.

1. cli/theme.sh mit Subcommands: list, <name>, show, gui (Rofi), check, reset.
2. Parser für .theme-Dateien (Key=Value, Kommentare #, Pflicht-Keys: accent, accent2,
   accent3, bg, bg2, fg, fg_dim, dark; term.* optional mit Ableitung aus Kernfarben).
3. Renderer: ersetzt Farbwerte in-place in i3-, polybar-, rofi-, kitty-, dunst-,
   picom-, GTK2/3/4-, xsettingsd- und lock-Konfigs. Idempotent (Round-trip-Test),
   Backup nach ~/.config/snowfox/theme-backup.tar.gz vor jedem Wechsel.
4. dark=true/false: setzt gtk-application-prefer-dark-theme (GTK3/4 settings.ini),
   wählt passendes GTK2-Theme, schreibt xsettingsd-Config, qt5ct-Config.
5. Erstelle die drei Standard-Themes (nightfox: schwarz/grau + Lila-Akzent #9B59B6,
   dayfox: hell, mono: grau) als vollständige .theme-Dateien inkl. 16 Terminal-Farben.
6. snowfox theme check validiert Pflicht-Keys, Hex-Format und Eindeutigkeit.
7. Wende die Design-Prinzipien aus Abschnitt 2.2 an: keine Alpha/Transparenz-Werte
   in irgendwelchen gerenderten Configs; polybar-Workspaces und Rofi-Auswahl
   INVERTIERT rendern (background = accent, foreground = bg); polybar-Config auf
   Basis der minimalistischen 3-Color-Referenz-Config (seamless pills, 36 px,
   border-bottom in accent, JetBrainsMono Nerd Font) umbauen.
8. Berechne beim Rendern die semantischen Statusfarben (green/yellow/red/orange)
   aus dem Theme (fixe Hues, Helligkeit an bg angepasst) statt sie als Theme-Keys
   zu pflegen.

Akzeptanz: Theme-Wechsel zweimal hin und her erzeugt byte-identische Configs
(Round-trip); shellcheck clean; nightfox nutzt #9B59B6 als accent; grep -riE
'#[0-9a-f]{8}"?|opacity' über alle gerenderten Configs findet keine Alpha-Werte.
```

---

## Prompt 3 — foxdock (C, Xlib)

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Implementiere foxdock gemäß Abschnitt 4 des Plans.

1. foxdock/ mit src/main.c, config.c/h, launcher.c/h, draw.c/h, palette.c/h,
   Makefile, README.md. Zusätzlich: configs/foxdock/dock.conf als Vorlage
   (Beispieleinträge, Format name;icon;exec), die der Installer nach
   ~/.config/foxdock/dock.conf kopiert — diese Lücke im Plan §1 ist inzwischen
   im Baum nachgetragen.
2. Reines X11/Xlib (+ Imlib2 für Icons, begründe die Wahl im README). Kein GTK/GLib.
3. Features: vertikale Icon-Leiste links, sticky auf allen Workspaces, Einträge aus
   ~/.config/foxdock/dock.conf (Format name;icon;exec) plus Auto-Scan von
   /usr/share/applications (eigener Mini-.desktop-Parser: Name, Icon, Exec, NoDisplay).
4. Klick startet via fork/exec, Hover-Highlight in Akzentfarbe, Tooltip, Icon-Größe
   konfigurierbar (32/48).
5. palette.c liest ~/.config/snowfox/palette.conf (accent, bg, bg2, fg) und lädt bei
   SIGHUP neu, ohne Neustart.
6. X11-Cleanup sauber (WM_DELETE, SIGTERM-Handler), keine Speicherlecks (valgrind-clean
   für den Setup-Pfad).
7. Makefile: cc -O2 -Wall -Wextra -Werror, Target install (PREFIX-konform).

Akzeptanz: kompiliert ohne Warnungen, läuft unter i3, Palette-Wechsel + SIGHUP
foxdock aktualisiert Farben live.
```

---

## Prompt 4 — CLI-Redesign

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Redesign der snowfox-CLI gemäß Abschnitt 5 des Plans.

1. cli/utils.sh: neues Design-System — Kopfzeile in Akzentfarbe, Key-Value-Zeilen mit
   fester Spaltenbreite, Status-Punkte (●) in grün/gelb/rot, dezente Trennlinien,
   keine ASCII-Art-Logos im Normalbetrieb.
2. Alle Module aus Abschnitt 1 (cli/) auf das neue Design umstellen, Texte auf
   Englisch, Befehle mit Klartextnamen + Aliasen wie in Abschnitt 5.
   KLARE TRENNUNG (aus Prompt 1): lib/ = Installer-Laufzeit, cli/ = System-Laufzeit.
   Der snowfox-Dispatcher und alle cli/-Module nutzen ausschließlich cli/utils.sh,
   NIE lib/utils.sh oder andere lib/-Dateien.
3. Neue Top-Level-Befehle theme und wallpaper; status battery ersetzt bat.
4. Exit-Codes: 0 ok, 1 Fehler, 75 Netzwerk nicht verfügbar.
5. cli/help.sh: gruppierte Hilfe (System / Hardware & Privacy / Media / Desktop /
   Theme / Settings), konsistentes Layout.
6. Entferne alle Referenzen auf mesh/ai/music/immersion/node/tor aus dem Dispatcher
   und der Completion-Datei (completions/snowfox-completion.bash entsprechend anpassen).

Akzeptanz: snowfox help, snowfox status, snowfox theme --help zeigen das neue Design;
alle Aliase funktionieren; shellcheck clean.
```

---

## Prompt 5 — Installer-Refactor & Security

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Refactore die lib/-Module gemäß Abschnitt 6 und 7 des Plans.

1. kernel_drivers.sh: AVX2-Check → XanMod LTS x64v3, sonst Standard-Debian-Kernel;
   GRUB behält immer einen bootfähigen Fallback-Eintrag; GPU-Detection (AMD/NVIDIA/
   Intel/Hybrid) inkl. Hybrid-Fixes (dcfeaturemask=0x8, runpm=0, sg_display=0,
   picom glx-Backend) aus v3 übernehmen.
2. performance_security.sh: zusätzlich unattended-upgrades konfigurieren
   (Security-Pocket only, Daily, Remove-Unused-Dependencies true, 20auto-upgrades).
3. installer/apt/99-snowfox auf beiden Pfaden installieren; Paketlisten gegen
   Recommends-off auditieren (apt-get install --dry-run mit/ohne Policy, Differenzen
   dokumentieren in docs/PACKAGES.md, fehlende Requires explizit in die Arrays).
4. Chroot-Safety in allen Modulen: systemctl start/restart nur bei
   [ -d /run/systemd/system ], sonst enable; Session-abhängige Schritte nach
   Phase firstboot auslagern. Alle unset-Variablen absichern, insbesondere
   IS_LAPTOP: if [[ "${IS_LAPTOP:-false}" == "true" ]] statt if $IS_LAPTOP
   (Fix: v3 bricht bei ungesetzter Variable).
5. Keine App-Empfehlungen: keine optionalen Extras ohne explizite Nutzeranfrage;
   ask_install im interaktiven Modus fragt, im Defaults-Mode nimmt es den Default.

Akzeptanz: shellcheck clean; Dry-Run-Audit dokumentiert; Fallback-Kernel-Eintrag
nachweisbar in GRUB-Config.
```

---

## Prompt 6 — Wallpaper-Auto-Palette

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Implementiere die Auto-Palette aus Abschnitt 3 des Plans.

1. cli/wallpaper.sh: list, set <pfad>, auto <pfad>, Rofi-Auswahl (Bestand aus v3
   übernehmen und an neues CLI-Design anpassen).
2. auto: Bild auf 256 px verkleinern (ImageMagick), 8 dominante Farben extrahieren
   (convert -colors 8 -unique-colors), dann Heuristik:
   - bg = dunkelste (dark=true) bzw. hellste (dark=false) Farbe
   - accent = gesättigteste Farbe mit Kontrast ≥ 3.0 zu bg
   - accent2/accent3 = Hue-Verschiebung von accent (±15°, Helligkeit angepasst)
   - fg = near-white (dunkles bg) / near-black (helles bg), Kontrast ≥ 4.5
3. Schreibt ~/.config/snowfox/themes/wallpaper-auto.theme und aktiviert es über die
   bestehende Theme-Engine (cli/theme.sh <name>).
4. Protokolliert Quelle in ~/.config/snowfox/wallpaper.conf.
5. Fallback: wenn keine Farbe Kontrast-Kriterien erfüllt, nimm Standard-Akzent des
   aktiven Themes und gib eine Warnung aus.

Akzeptanz: snowfox wallpaper auto <bild> erzeugt valides Theme (besteht
snowfox theme check); shellcheck clean; Abhängigkeit nur imagemagick.
```

---

## Prompt 7 — installer/ (ISO-Vorbereitung)

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Portiere die ISO-Vorbereitung in installer/ gemäß Abschnitt 6 des Plans.
Die alte ISO-Work-Order (simple-cdd, Preseed verbatim, Overlay-Skripte late.sh/
10-apt-policy/20-base/30-gpu/40-firstboot + firstboot-Unit) ist die Grundlage und
wird 1:1 inhaltlich übernommen, nur mit den v4-Step-Nummern und Pfaden.

1. installer/preseed/snowfox.preseed — verbatim aus der Work Order §2.
2. installer/overlay/ — late.sh-Orchestrierung, 10-apt-policy.sh, 20-base.sh
   (install.sh --phase iso-base), 30-gpu.sh (Exit-75-Handling, Marker
   /var/lib/snowfox/firstboot-pending), 40-firstboot.sh + systemd-Unit.
3. installer/phases.md — Dokumentation der drei Phasen und Chroot-Regeln.
4. Passe die Step-Nummern an die v4-lib/ an (kein browser_selection/mesh/gaming mehr;
   Browser-Installation gehört zu firstboot optional bzw. snowfox stash).
   Entferne dabei den --phase extras-Aufruf aus 40-firstboot.sh (Entscheidung aus
   Prompt 1, Punkt 4) und hake das TODO in installer/phases.md ab.
5. Alles shellcheck-clean. Der eigentliche simple-cdd-Build kommt später (eigener
   Task), hier nur Vorbereitung + Trockenlauf-Skripte.

Akzeptanz: shellcheck clean; late.sh-Trockenlauf in debootstrap-Chroot mit
gestubbten apt-Aufrufen komplett durch.
```

---

## Prompt 8 — Doku & Tests

```text
[GEMEINSAMER KONTEXT HIER EINFÜGEN]

Aufgabe: Dokumentation und Tests für SnowFoxOS v4.

1. README.md im v3-Stil, aber: Features/Stack auf v4-Kern (inkl. foxdock und
   Theme-System mit Auto-Palette), Screenshots-Platzhalter, englisch.
2. PROJECT_STRUCTURE.md: exakte Beschreibung jeder Datei im v4-Layout (Abschnitt 1),
   inklusive der durch Prompt 1 geschlossenen Lücken: lib/firstboot.sh (Stub aus
   phase_modules firstboot) und configs/foxdock/dock.conf; außerdem die
   install.sh-Source-Reihenfolge (utils.sh → phase.sh → phase_parse_args).
3. docs/PACKAGES.md: Recommends-Audit-Ergebnisse aus Prompt 5.
4. Test-Skripte: tests/qemu-install-test.sh (QEMU, --offline und --online, basierend
   auf der alten Work Order §7 Task 7/8) und tests/expect-install.exp.
5. Definition of Done übernehmen: DoT aktiv, UFW aktiv, SSH disabled, i3 startet
   aus TTY1, snowfox status funktioniert, Idle-PSS < 200 MB gemessen mit smem.

Akzeptanz: alle Skripte shellcheck clean; README beschreibt nur existierende
Features.
```

---

## Arbeitsweise für dich (Planer)

1. **Web-Chat-Betrieb:** Die anderen KIs sehen weder Repo noch Plan. Jeder Prompt ist deshalb bewusst vollständig in sich — kopiere immer Abschnitt 0 + den jeweiligen Prompt-Block zusammen in EIN Chat-Fenster. Wenn eine KI Rückfragen hat, beantworte sie mit Verweis auf die Abschnitte hier (ggf. Abschnitt wörtlich hineinkopieren).
2. Prompts **nacheinander** abarbeiten (Reihenfolge oben = Abhängigkeitsreihenfolge). Nie zwei parallel mischen.
3. Nach jedem Prompt: Ergebnis in dein Repo mergen, `shellcheck` laufen lassen, kurz testen — erst dann der nächsten KI den nächsten Prompt geben. Ergebnisse pro Prompt in eigene Chats, nicht alles in einen (Kontextfenster).
4. Wenn eine KI vom Plan abweicht, korrigiere sie mit Verweis auf den konkreten Abschnitt hier — dieses Dokument ist die Single Source of Truth.
