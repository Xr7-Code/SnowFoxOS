# SnowFoxOS — ToDo / offene Punkte

> Stand: Review vom 21.10.2026 (statische Analyse, kein Ausführen der Logik).
> Legende: 🔴 kritisch · 🟠 wichtig · 🟡 klein · 💡 Idee/Feature · ✅ erledigt
> Verwendete Schreibweise: `datei.sh:Zeile` → Ort der Stelle.

---

## 0. Erledigt in diesem Durchgang (kritische Fehler)

| # | Problem | Fix | Datei |
|---|---|---|---|
| ✅ A1 | `snowfox mesh start` brach immer ab: `lora_port: unbound variable` (`set -u`) | `local lora_port="${3:-}"` in `_mesh_start_reticulum`, Argument wird durchgereicht | `configs/snowfox-mesh.sh:204` |
| ✅ A2 | `mesh.state` unquoted geschrieben → SSID zerstört, `source`-Fehler | `printf 'KEY=%q\n'`, Datei jetzt `chmod 600` | `configs/snowfox-mesh.sh:934` |
| ✅ A3 | `snowfox snap diff` meldete immer „No differences" (Zähler in Subshell) + Abbruch bei erster neuer Datei | Schleife via Process-Substitution, Zähler im Parent, `continue` statt `return`, Markierung `-missing` | `cli/snap.sh:196` |
| ✅ A4 | Snapshot speicherte `~/.config/snowfox` nie (Rekursion „cannot copy a directory into itself") | Einträge einzeln kopieren, `snapshots/` auslassen | `cli/snap.sh:57` |
| ✅ A5 | Ungültige yt-dlp-Prefixes (`ytsearchmusic`, `spsearch` existieren nicht) → Default „YouTube Music" fiel still auf YouTube zurück | echte Such-URL `music.youtube.com/search?q=…`, nur `ytsearch:`/`scsearch:` bleiben, Spotify ehrlich als „via YouTube search" | `cli/music.sh:39` |
| ✅ A6 | AI-Chat: Strg+D ⇒ Endlosschleife mit 100 % CPU | `read`-Rückgabewert prüfen, EOF beendet die Schleife | `cli/ai.sh:240` |
| ✅ A7 | Fehlermeldungen landeten in Werten (`$(…)`-Captures): Theme-Reset, Modellname | `warn`/`err` schreiben jetzt nach **stderr**; Capturing-Stellen umgebaut (`_ai_pick_model` gibt Rückgabecode, `theme reset` löst selbst auf) | `cli/utils.sh:73`, `cli/theme.sh:470`, `cli/ai.sh:48` |
| ✅ M1 | `((x++))` mit Startwert 0 ⇒ Status 1 ⇒ Abbruch unter `set -e` (4 Stellen im Mesh-Skript) | `x=$((x + 1))` | `configs/snowfox-mesh.sh` (290, 302, 618, 409) + alle CLI-Stellen |
| ✅ M2 | `set -u`-Abbrüche: `_mesh_find_interface` (pipefail), `_mesh_start`-Optionen, `_mesh_share/-share_all/-get/-gateway`, `_mesh_chat` ohne Argumente | `${1:-}`-Defaults, `\|\| true` an Pipes, `chat` reicht `"$@"` durch | diverse Stellen in `configs/snowfox-mesh.sh` |
| ✅ M3 | `nmcli`-Parsing: `GENERAL.MANAGED:yes` wurde nie gelesen | `cut -d: -f2` statt `awk '{print $2}'` | `configs/snowfox-mesh.sh:117` |

---

## 1. Offene Logikfehler (🟠/🔴)

### 1.1 Installer (`lib/`)

| Prio | Ort | Problem | Lösungsrichtung |
|---|---|---|---|
| 🔴 | `lib/base_system.sh:50` | **`python3` wird nie installiert** — wird aber von `music.sh` (Playlists), `ai.sh` (History) und 5 Installer-Stellen benötigt | `python3 python3-venv` in die Paketliste von Schritt 1 |
| 🔴 | `lib/mesh_module.sh:30` | `pipx install rns` läuft **als root** → landet in `/root/.local/bin`, für den Benutzer unbenutzbar; `pipx ensurepath` schreibt nach `/root/.bashrc` | `sudo -u "$TARGET_USER" -H pipx install rns` + `pipx ensurepath` für den User; `PATH` des Users ergänzen |
| 🟠 | `lib/kernel_drivers.sh:242` | Erfolgsmeldung „NVIDIA DKMS modules built" erscheint **auch bei Fehlschlag** | Meldung in den Erfolgspfad verschieben |
| 🟠 | `lib/kernel_drivers.sh:106` | `grub-set-default` nutzt „SnowFoxOS GNU/Linux", zu diesem Zeitpunkt ist `GRUB_DISTRIBUTOR` noch „Debian" ⇒ Befehl scheitert still | Submenü-Name aus `GRUB_DISTRIBUTOR` ableiten oder nach `set_system_version` ausführen |
| 🟠 | `lib/kernel_drivers.sh:99` | `GRUB_CMDLINE_LINUX_DEFAULT` wird **überschrieben** — eigene Kernel-Parameter des Nutzers gehen verloren | Bestehende Werte parsen und ergänzen statt ersetzen |
| 🟠 | `lib/system_setup.sh:103` | `/etc/os-release` wird ohne `DEBIAN_VERSION`/`VERSION_CODENAME` und mit `ID=snowfoxos` überschrieben ⇒ Distro-Skripte (NVIDIA-Installer, `check-release`, cloud-init) können brechen | `ID=debian` behalten, nur `PRETTY_NAME`/`NAME` ändern, `DEBIAN_VERSION` ergänzen |
| 🟠 | `lib/base_system.sh:34` | `/etc/apt/sources.list` wird vollständig überschrieben ⇒ Suite-Pinning auf bookworm, auch auf trixie | Vorher sichern, nur fehlende Zeilen ergänzen |
| 🟠 | `lib/base_system.sh:110` | `sudo -u "$TARGET_USER" xdg-user-dirs-update` ohne `-H` ⇒ HOME=/root | `sudo -u "$TARGET_USER" -H …` |
| 🟠 | `lib/desktop_environment.sh:93` | Bluetooth-Start-Logik invertiert: `systemctl start` im Hintergrund + `kill -0`-Prüfung ⇒ bei langsamem Start wird `systemctl` abgebrochen, Erfolg wird trotzdem gemeldet | `systemctl is-active bluetooth` prüfen statt PID-Race |
| 🟠 | `lib/performance_security.sh:156` | `rp_filter=1` (strict) kann Tor/VPN/asymmetrisches Routing brechen | auf `2` (loose) setzen oder auskommentieren |
| 🟠 | `lib/performance_security.sh:68` | `fstab`-Patch nicht idempotent (2. Lauf ⇒ `noatime,noatime`) | Muster prüfen, bevor ersetzt wird |
| 🟡 | `lib/performance_security.sh:70` | `tmpfs /tmp size=4G` — auf 2-GB-Systemen mehr als der RAM | `size=50%` |
| 🟡 | `lib/theming_finishing.sh:161` | `cp -r configs/* ~/.config/` landet auch in `~/.config/applications`, `~/.config/modprobe`, `~/.config/xorg` (falsche Orte) | separate Zielpfade je Config-Gruppe |
| 🟡 | `lib/kernel_drivers.sh:114` | Fritz-Check matcht jeden Realtek-USB (`0x0bda`) und lädt `mt76x2u` (nur für MT7612U) | auf echte VID/PID einschränken |
| 🟡 | `lib/default_apps.sh:90` | `curl -o /usr/local/bin/yt-dlp` ohne Fehlerprüfung ⇒ defekte Datei bleibt liegen | Download prüfen, bei Fehler löschen |

### 1.2 CLI (`cli/`)

| Prio | Ort | Problem | Lösungsrichtung |
|---|---|---|---|
| 🔴 | `cli/system.sh:443` | Factory-Reset löscht **alles** in `$HOME` (inkl. `~/.ssh`, `~/.gnupg`) ohne Backup/Second-Confirmation | Schlüssel vorher sichern oder verschlüsseltes Backup anbieten; Bestätigung mit Pfadliste |
| 🟠 | `cli/system.sh:215` | `snowfox up` überschreibt `~/.config/kitty`, `i3`, `rofi`, `dunst`, `gtk-*`, `picom.conf` — gesichert wird nur ein Teil | Backup über alle Zielpfade, Diff anzeigen, `snowfox rollback` |
| 🟠 | `cli/system.sh:60` | `echo performance \| sudo tee …/scaling_governor` schreibt den Namen mit Newline; Governor fehlt auf manchen CPUs | Wert trimmen, Existenz prüfen |
| 🟠 | `cli/settings.sh:362` + `configs/polybar/scripts/bluetooth.sh:17` | `rfkill block/unblock bluetooth` **ohne sudo** ⇒ wirkungslos | `sudo rfkill …` (mit Polkit-Alternative) |
| 🟠 | `cli/tor.sh:193` | Bestehende Verbindungen (`ESTABLISHED,RELATED → ACCEPT`) laufen **nicht** durch Tor ⇒ Leak | Verbindungen beim Aktivieren beenden (`conntrack -D` o. ä.) |
| 🟠 | `cli/tor.sh:190` | `iptables -F OUTPUT` überschreibt eigene Firewall-Regeln (Backup existiert, ist aber grob) | eigene Chains (`SNOWFOX_TOR`) statt Chains leeren |
| 🟠 | `cli/doctor.sh:28` | `trap … RETURN` bleibt nach `cmd_doctor` aktiv ⇒ feuert bei jeder folgenden Funktion (`rm -f ""`) | Trap im Trap zurücksetzen (`trap - RETURN`) |
| 🟠 | `cli/doctor.sh:44` | `RAM_PCT` kann `?` werden (kein `bc`) ⇒ „integer expression expected" | `bc` prüfen, sonst Bash-Arithmetik nutzen |
| 🟡 | `cli/status.sh:199` | gleiches Problem bei `HEALTH`/`bar` | Zahlen validieren, bevor verglichen wird |
| 🟡 | `cli/doctor.sh:436` | Geprüfte Tools: git curl gpg pactl rfkill yt-dlp mpv — **`python3`, `gum`, `jq`, `ffmpeg`, `aria2c`, `bc`, `iw`, `nmcli` fehlen** | Liste erweitern (Relevanz: `music`, `mesh`, `immersion`) |
| 🟡 | `cli/music.sh:128` | WLAN-Passwort via `nmcli … password "$PASS"` ⇒ sichtbar in `ps` | `nmcli --ask`/Passwort über stdin |
| 🟡 | `cli/music.sh:15` | `mkdir` beim **Sourcen** des Moduls (Side-Effect bei jedem `snowfox`-Aufruf) | in `_init_playlists` verschieben |
| 🟡 | `cli/immersion.sh:33` | Run-Verzeichnis unter `/tmp` ⇒ PID-File manipulierbar (`beats off` killt fremde PIDs) | `install -d -m 700` + Ownership prüfen |
| 🟡 | `cli/desktop.sh:294` | `.desktop`-`Exec=` mit unescapten `"` ⇒ Spec verlangt `\"`; Pfade mit Leerzeichen brechen | Quotes escapen |
| 🟡 | `cli/desktop.sh:352` | `eval "$exec_cmd"` auf einen Datei-Inhalt | ohne `eval` starten (Array-Argumente) |
| 🟡 | `cli/snap.sh:150` | Restore schreibt absolute Pfade aus dem Snapshot-Zeitpunkt ⇒ nach Home-Umzug falscher Ort | relativen Pfad im Meta-File speichern |
| 🟡 | `cli/theme.sh:700` | Warnungen zählen als `errors` ⇒ „Palette has N error(s)" | getrennt zählen |
| 🟡 | `snowfox:86-89` | `exec ~/.config/snowfox-*.sh` ohne Existenzprüfung ⇒ „No such file or directory" | vorher prüfen, sauber melden |
| 🟡 | `snowfox:28-45` | Nur `music.sh`/`immersion.sh` werden auf Vollständigkeit geprüft | alle Module prüfen, klare Fehlermeldung |
| 🟡 | `cli/ai.sh:232` | `sudo systemctl start ollama` fragt im CLI interaktiv nach dem Passwort | `systemctl --user` bevorzugen, sudo nur als Fallback |
| 🟡 | `cli/system.sh:174` | `_node_server` ruft `sudo tlp ac` — TLP ist auf Desktops deaktiviert | nur ausführen, wenn TLP aktiv ist |

### 1.3 Mesh-Modul (`configs/snowfox-mesh.sh`)

| Prio | Ort | Problem | Lösungsrichtung |
|---|---|---|---|
| 🔴 | `:2108` | `chat` reicht Argumente nicht durch — `snowfox mesh chat @all "hi"` öffnet nur den interaktiven Chat | `chat) _mesh_chat "$@" ;;` (kommt mit diesem Patch) + Argument-Auswertung in `_mesh_chat` |
| 🔴 | `:1448` | `for resource in RNS.Transport.resources:` iteriert **dict-Keys** (bytes) → `resource.hash` → AttributeError ⇒ `mesh get` funktioniert nie | `RNS.Transport.resources.values()` + Hex-Vergleich über `str(resource.hash)` |
| 🟠 | `:1104`, `:1876` | `@name`-Privatnachrichten werden als Hex-Hash geparst (`bytes.fromhex`) ⇒ immer Fehler; `_mesh_nodes` zeigt nur `hash[:16]…` ⇒ kein kopierbarer Hash | Namen→Hash-Mapping persistent halten, vollen Hash anzeigen |
| 🟠 | `:1953` | `_mesh_start_services` startet zwei Endlos-Schleifen im Hintergrund ⇒ `services.pid` zeigt auf eine bereits beendete Subshell; `mesh stop` meldet Erfolg, die Schleifen laufen weiter | echte PIDs der Schleifen speichern, per PID-Datei stoppen |
| 🟠 | `:2115` | `web) _mesh_web ;;` läuft im Vordergrund, blockiert das Terminal, keine PID-Registrierung | im Hintergrund starten + PID speichern |
| 🟠 | `:584` | Web-UI bindet auf `0.0.0.0`; Token-Prüfung entfällt ohne `--token` ⇒ im Netz offen | Token immer erzeugen, Default-Bind auf `127.0.0.1` |
| 🟠 | `:861` | `sudo pkill -f "dnsmasq"` killt auch NetworkManagers dnsmasq ⇒ DNS-Ausfall systemweit | nur eigenen dnsmasq per PID-File beenden |
| 🟠 | `:1566` | `sudo iptables -F FORWARD` leert die **gesamte** FORWARD-Chain | eigene Chain verwenden |
| 🟠 | `:1521` vs `:1569` | `net.ipv4.ip_forward=1` wird beim Deaktivieren nur zur Laufzeit zurückgesetzt ⇒ nach Reboot weiter aktiv | auch `/etc/sysctl.conf` zurücksetzen |
| 🟠 | `:934` | Passwort/Token stehen im Klartext in `mesh.state` (jetzt `chmod 600`) | Schlüssel in `psk.key` belassen, State nur Referenzen speichern |
| 🟡 | `:1712` | `pkill -f "snowfox mesh"` matcht den aufrufenden Prozess selbst | eigenes Muster präziser fassen |
| 🟡 | `:1716` | Abschieds-Broadcast wird **nach** dem Kill von `rnsd` gesendet ⇒ kommt nie an | vor dem Stoppen senden |
| 🟡 | `:1890` | `_mesh_write_config` ist toter Code (Duplikat von Z. 214) | löschen |
| 🟡 | `:32-41`, `:902` | `MESH_CONFIG`, `MESH_NODES`, `MESH_MESSAGES`, `MESH_TEMP`, `MESH_PSK_FILE` werden nie benutzt | entfernen |
| 🟡 | `:1052`, `:1056`, `:1746`, `:1799` | quoted heredoc ⇒ `${GRAY}`/`${RESET}` werden **literal** gedruckt | Heredoc ohne Quotes + Werte escaped einsetzen |
| 🟡 | `:2076` | Web-UI behauptet „Verbunden mit dem Mesh!" — eingehende Nachrichten werden nie angezeigt | Receiver auch im Web-Modus starten |
| 🟡 | `:2080` | Hilfe behauptet „NetworkManager wird deaktiviert" — im `hotspot`-Modus wird er explizit **verwaltet** | Hilfe an das Verhalten anpassen |

---

## 2. Konsistenz & Dokumentation (🟡)

| Ort | Problem |
|---|---|
| `README.md:114` | Behauptet „MAC address is randomized" bei Tor — `cli/tor.sh` randomisiert nichts (macchanger liegt nur in der `stash`-Kategorie) |
| `README.md:249` | `snowfox st` zeigt „GPU mode" — angezeigt werden nur GPU-Namen |
| `README.md:270` | Music-TUI verspricht „YT Music, Spotify, SoundCloud" — Spotify ging nicht (jetzt ehrlich beschriftet) |
| `README.md:264` | `snowfox kill` beschreibt einen Umfang, den der Code nicht kennt (`mic\|cam\|all\|restore`) |
| `cli/ai.sh:13` | System-Prompt listet `apps` — dieses Kommando existiert nicht |
| `snowfox:49` | Version hartcodiert („v3 (CLI v3.2.0)") — keine zentrale `VERSION`-Datei |
| `lib/system_setup.sh:15` | `set_system_language` (en_US) wird nie aufgerufen ⇒ System bleibt `de_AT` (aus `kernel_drivers.sh:20`), CLI englisch, Greeting deutsch — Sprachkonzept festlegen |
| `cli/help.sh:115` | `snowfox mesh` ist auskommentiert, existiert aber (`snowfox:111`) |
| `completions/…:43` | Completion kennt die Aliase `st, bat, up, prof, doc, rst, net, wall, disp, def, kb, lang, tz, dl, fetch, m, imm` nicht |
| `configs/powermenu.sh:22` | `i3lock -c 0d0d0d` — hart codierte Farbe, folgt dem Theme nicht (Datei fehlt in `THEME_TARGET_FILES`) |
| `cli/theme.sh:16` | `THEME_TARGET_FILES` enthält `~/.config/snowfox-mesh.sh` — Mesh-UI-Farben folgen damit dem Theme, der Lock-Skript-Code aber nicht vollständig |

**XDG-Inkonsistenz (🟠):** `theme.sh`, `settings.sh`, `immersion.sh` nutzen `XDG_CONFIG_HOME`; `music.sh`, `snap.sh`, `ai.sh`, `desktop.sh`, `media.sh`, `system.sh`, `status.sh`, `doctor.sh` hartcodieren `$HOME/.config`. Folge: bei gesetztem `XDG_CONFIG_HOME` findet `snowfox up` das gespeicherte Theme nicht (`cli/system.sh:223`).
→ **Fix-Idee:** `cli/paths.sh` mit `SF_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snowfox"`, das alle Module sourcen.

---

## 3. Weitere Robustheits-Punkte (🟡)

* `cli/utils.sh:137` `human_bytes`, `cli/ai.sh:109` `_ai_ask`, `cli/utils.sh:134` `spin_warn` — toter Code → entfernen.
* `cli/doctor.sh:397` — `SECURITY_UPDATES` zählt Zeilen mit „security" im Simulations-Output (ungenau).
* `cli/stash.sh:164,345,442` — Logs landen in `/tmp/*.log` (lesbar für alle, werden nicht rotiert) → `~/.cache/snowfox/logs/`.
* `configs/snowfox-greeting.sh:17` — vorhersagbare Datei in `/tmp` (Symlink-Angriff) → `mktemp`.
* `configs/snowfox-network.sh:128` — Passwort im Kommandozeilen-Argument (siehe 1.2).
* `cli/status.sh:46` — `ip route get` ohne Gateway ⇒ Feldzuordnung stimmt nicht → Default-Interface robuster bestimmen.
* `cli/settings.sh:83` — `localectl status` ist lokalisiert ("X11 Layout" → dt. "X11-Tastaturbelegung") ⇒ Parser bricht in Nicht-Englischen Locales → `localectl status --no-pager` + Locale `C` setzen.
* `cli/theme.sh:481` — `sed`-Regeln nutzen den `I`-Flag (GNU-sed ≥ 4.2) — auf alten Systemen prüfen.
* `cli/immersion.sh:653` — Status zeigt „Limiter" auch bei leerer Kette.
* `lib/`-Installer: alle `apt-get`-Aufrufe ohne `-y`-Fallback/Statusprüfung brechen den Ablauf nicht ab, melden aber Erfolg → einheitliche Fehlerbehandlung.

---

## 4. 💡 Ideen — wie SnowFoxOS besser, besonderer und nützlicher wird

### 4.1 Qualität & Nachhaltigkeit (Priorität 1)

* [ ] **CI**: `shellcheck` + `bash -n` + `shfmt` + **bats-Testsuite** (Theme-Roundtrip, `snap save/restore/diff`, `stash info`, `theme check`).
* [ ] **`snowfox doctor --fix`**: erkannte Probleme automatisch beheben (fehlende Pakete, python3/gum/jq, Rechte, XDG-Pfade, defekte Symlinks).
* [ ] **Einheitliche Pfade** (`cli/paths.sh`) → behebt die XDG-Inkonsistenz komplett.
* [ ] **Transaktionale Updates**: vor `snowfox up` / `theme apply` ein Snapshot-Punkt + `snowfox rollback`.
* [ ] **Idempotente Patches** (fstab, GRUB, sources.list, os-release): Backup + Prüfen statt blindem `sed`.
* [ ] **`--json`-Ausgabe** für alle Statusbefehle → Skripte, Waybar, Docks.
* [ ] **Sprachpaket (i18n)**: CLI-Meldungen über `gettext`; ein Ziel-Locale statt drei Sprachen.

### 4.2 Neue Funktionen

* [ ] **Profil-Pakete**: `snowfox prof work|gaming|media|travel` schaltet *Theme + Audio + Netz + Tasten + Leistung* als Set um (statt nur CPU-Governor).
* [ ] **Fokus-Modus**: `snowfox focus 25` — dimmt Hintergrund, pausiert Dunst, startet Timer.
* [ ] **Boot-Zeit-Wächter**: `systemd-analyze` im `snowfox st` + „Boot +0,4 s seit letztem Update".
* [ ] **`snowfox health`**: Langzeitwerte (RAM-Leak, Temperatur, Akkuzyklen, SMART) mit Verlauf.
* [ ] **Tasten-Editor** `snowfox keys` (i3-Bindings live editieren, Reload, Sicherheitskopie).
* [ ] **Git-Integration** in Polybar (Branch, Dirty-Status) + `snowfox git` (Repos, Credentials, `git config`).
* [ ] **Container-Policy** `snowfox docker policy` — nur signierte Images, kein `latest`, kein Host-Netzwerk.
* [ ] **Self-Update ohne root**: eigenes Verzeichnis, atomar, mit Rollback.
* [ ] **Update-Kanäle** (stable/testing) + Rückroll auf die Vorversion.
* [ ] **`snowfox firstrun`**: interaktiver Guide, der die 10 Installationsschritte nachvollzieht.
* [ ] **Offline-Paket-Cache**: `snowfox stash --offline` lädt Pakete lokal → Installation ohne Netz.
* [ ] **Rofi-/TUI-Kommandozentrum** über *alle* CLI-Befehle (heute über 19 Module verteilt).

### 4.3 Besonders machen

* [ ] **Theme-Engine neu**: tokenbasiertes Rendering statt Wert→Wert-`sed` (heute bricht sie bei doppelten Werten) + Themes: Nord, Catppuccin, Gruvbox, Dracula, Solarized + Vorschau im Terminal.
* [ ] **AI mit Aktionen**: `snowfox ai "schalte Datenschutzprofil an"` → bestätigbarer Plan (diff-artig), nicht nur Text; lokal via Ollama.
* [ ] **Mesh ausbauen**: Schlüssel-Management, signierte Identitäten, Chat über Reticulum, Datei-Austausch Ende-zu-Ende.
* [ ] **Energie-Bilanz**: `snowfox st` zeigt Energieverbrauch der letzten Stunde (aus `/sys/class/power_supply`).
* [ ] **Wayland-Pfad** (Sway), um das im README ehrlich genannte X11-Problem adressierbar zu machen.

### 4.4 Sicherheit & Datenschutz

* [ ] **Privacy-Presse**: `snowfox privacy on` = kein WLAN/BT, kein SSH, kein Telemetrie, gehärteter sysctl, kein ICMP, `unattended-upgrades` aus.
* [ ] **SHA256-Prüfung aller Binaries** (gum, fastfetch, Zen, bluetui, Nerd Fonts, Proton-GE) — aktuell wird alles ungeprüft installiert.
* [ ] **sudo → PolicyKit**: rfkill/modprobe/apt über `pkexec`-Regeln ⇒ kein Passwort-Prompt im CLI.
* [ ] **Tor härten**: MAC-Randomisierung (wie im README versprochen), QUIC/DoH-Block, IPv4-UDP-Killswitch, DNS-Leak-Selbsttest.
* [ ] **Audit-Log** aller Root-eskalierten Aktionen (`~/.config/snowfox/audit.log`).
* [ ] **Secrets-Scan** vor dem Factory-Reset (SSH-/GPG-Schlüssel automatisch sichern statt löschen).
* [ ] **Sandbox für WebApps** (Zen) über Flatpak/Snap.

---

## 5. Checkliste für den nächsten Durchgang

- [ ] `python3` in den Installer aufnehmen → Music-TUI + AI-History funktionieren überall
- [ ] `pipx`/`rns` als Benutzer installieren → Mesh startet
- [ ] Tor: MAC-Randomisierung + bestehende Verbindungen kappen (README-Versprechen einlösen)
- [ ] Factory-Reset: Backup der Schlüssel + Pfadliste vor dem Löschen
- [ ] `cli/paths.sh` einführen → XDG konsistent
- [ ] `snowfox doctor --fix` + CI (shellcheck/bats)
- [ ] Theme-Engine auf tokenbasiertes Rendering umstellen
- [ ] README mit dem tatsächlichen Verstand abgleichen (Tor, kill, st, music, mesh)
- [ ] Wayland/Sway-Bereich als Alternativ-Desktop skizzieren
