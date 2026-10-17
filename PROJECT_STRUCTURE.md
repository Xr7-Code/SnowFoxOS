# SnowFoxOS v3 — Project Structure & Script Documentation

Documentation of the complete project directory of **SnowFoxOS v3** (Debian 12 Bookworm base with i3 Window Manager). This file describes the logical architecture of the repository as well as the exact function and operation of every single script.

---

## 📁 Repository Structure at a Glance

```text
SnowFoxOS/
├── install.sh                        # Main installer script (entry point)
├── snowfox                           # Central CLI dispatcher (/usr/local/bin/snowfox)
├── snowfox-greeting.sh               # Terminal greeting script (visuals, quotes, stats)
├── note.txt                          # Project philosophy & core principles
├── README.md                         # Main documentation & feature overview
├── PROJECT_STRUCTURE.md              # English project structure & script documentation
├── SNOWFOX-SANCTUARY.MD              # Architecture & user guide for SnowFox Den (focus/sovereignty)
├── snowfoxos-iso_builder-readme.md   # Guide & process for the ISO builder
├── snowfoxos-v3_display-freeze.md    # Debugging report for AMD+NVIDIA Hybrid freeze fix
├── LICENSE                           # GNU General Public License v3.0 (GPL-3.0)
│
├── lib/                              # Modular installation steps for install.sh
│   ├── utils.sh                      # Colors, logging, helper functions & apt-lock waiter
│   ├── system_setup.sh               # Functions for locale switching, os-release & GRUB theme
│   ├── base_system.sh                # Step 1: System updates, base packages, Xwrapper & groups
│   ├── kernel_drivers.sh             # Step 2: XanMod/Debian kernel, GPU detection & drivers
│   ├── desktop_environment.sh        # Step 3: i3, Polybar, Rofi, Dunst, Bibata, fonts & .xinitrc
│   ├── audio_terminal.sh             # Step 4: PipeWire, WirePlumber, Bluetooth A2DP & Kitty
│   ├── default_apps.sh               # Step 5: PCManFM, Geany, Flameshot, yt-dlp, Console Launcher
│   ├── browser_selection.sh          # Step 6: Browser selection (Zen, LibreWolf, Brave, Firefox)
│   ├── mesh_module.sh                # Step 6b: Reticulum P2P Mesh Network integration
│   ├── gaming_ai.sh                  # Step 7/7b: Steam, GameMode, Proton GE, Ollama AI
│   ├── performance_security.sh       # Step 8: zRAM, sysctl tuning, UFW firewall, hardening
│   ├── boot_screen.sh                # Step 9: Plymouth boot theme & GRUB visuals
│   ├── theming_finishing.sh          # Step 10: GTK/Qt dark mode, Fastfetch, MIME & dotfiles
│   └── cleanup_final.sh              # Final: Cleaning apt caches & banner display
│
├── cli/                              # snowfox CLI modules (/usr/local/lib/snowfox/cli/)
│   ├── utils.sh                      # Terminal colors, headers, progress bar & spinner
│   ├── gum.sh                        # Shared Gum TUI library: theme, widgets, TUI detection
│   ├── help.sh                       # Command overview & help (snowfox h)
│   ├── status.sh                     # System status & battery diagnostics (snowfox st / bat)
│   ├── system.sh                     # System update, power profiles & reset (snowfox up/prof/rst)
│   ├── hardware.sh                   # GPU info, kill switches & airmode (snowfox gpu/kill/air)
│   ├── security.sh                   # Network audit & live connections (snowfox audit)
│   ├── media.sh                      # Video/audio stream & high-speed fetch (snowfox stream/dl/fetch)
│   ├── music.sh                      # Gum TUI: music search, playlists, sources (snowfox music)
│   ├── desktop.sh                    # Autostart, layout, WebApps, wallpaper & display (snowfox auto/lay/web/wall/disp)
│   ├── network.sh                    # Gum TUI: NetworkManager frontend (snowfox net)
│   ├── stash.sh                      # Integrated package manager / Software Stash (snowfox stash)
│   ├── settings.sh                   # System settings in terminal, Gum TUI & Rofi GUI (snowfox set)
│   ├── doctor.sh                     # Deep system diagnostics & integrity check (snowfox doc)
│   ├── mesh.sh                       # Wrapper for the P2P Mesh module (snowfox mesh)
│   ├── ai.sh                         # Local offline AI with Ollama & Chat UI (snowfox ai)
│   ├── snap.sh                       # Configuration snapshots & restore (snowfox snap)
│   ├── tor.sh                        # Transparent Tor proxying & fail-closed security (snowfox tor)
│   └── tui.sh                        # Main Gum control center (snowfox / snowfox tui)
│
├── configs/                          # Configuration files & helper scripts (~/.config/)
│   ├── snowfox-wallpaper.sh          # Rofi-based wallpaper selector
│   ├── snowfox-display.sh            # Rofi-based display & multi-monitor manager
│   ├── snowfox-network.sh            # Rofi-based Wi-Fi/network management tool
│   ├── snowfox-lock.sh               # Smart lock screen (does not lock during media playback)
│   ├── powermenu.sh                  # Rofi power menu (shutdown, reboot, suspend, lock)
│   ├── snowfox-mesh.sh               # Standalone Reticulum P2P Mesh Engine v5.0
│   ├── picom.conf                    # Picom compositor config (GLX backend, rounded corners)
│   ├── gtkrc-2.0                     # GTK2 dark theme override
│   ├── i3/
│   │   ├── config                    # i3 Window Manager main configuration
│   │   └── clip-saver.sh             # Clipboard persistence script (text/PNG protection)
│   ├── polybar/
│   │   ├── config.ini                # Polybar status bar configuration
│   │   ├── launch.sh                 # Automatic Polybar launcher (laptop vs desktop)
│   │   └── scripts/
│   │       ├── bluetooth.sh          # Polybar Bluetooth status & click-toggle
│   │       └── network-status.sh     # Polybar network status indicator (Wi-Fi SSID / LAN)
│   ├── rofi/
│   │   └── config.rasi               # Rofi app launcher theme in SnowFox design
│   ├── kitty/
│   │   └── kitty.conf                # Kitty GPU terminal config (JetBrainsMono, transparency)
│   ├── dunst/
│   │   └── dunstrc                   # Dunst notification daemon configuration
│   ├── gtk-3.0/ & gtk-4.0/           # GTK3/GTK4 settings.ini & custom gtk.css overrides
│   ├── xsettingsd/                   # XSettings daemon configuration
│   ├── modprobe/                     # Kernel module options (NVIDIA, AMD GPU freeze fix)
│   ├── xorg/                         # X11 touchpad configuration (30-touchpad.conf)
│   └── applications/                 # .desktop files for Rofi (Network, Bluetooth, LF)
│
├── iso-builder/                      # Standalone bootable ISO creation (currently under active revision / empty)
│
├── completions/
│   └── snowfox-completion.bash       # Auto-completion for snowfox CLI in Bash
│
├── assets/                           # Logos and screenshots for documentation & Plymouth
└── wallpapers/                       # Official SnowFoxOS wallpapers
```

---

## 🛠️ Main & Installation Scripts (Root Directory)

### 1. `install.sh`
- **Purpose:** Central installation script for a fresh Debian 12 minimal installation.
- **Functionality:** 
  - Verifies root privileges and the Debian 12 environment.
  - Determines target user (`TARGET_USER`) and home directory.
  - Sequentially loads all installation modules from the `lib/` directory via `source`.
  - Manages global exported variables (`HAS_NVIDIA`, `HAS_AMD`, `HAS_INTEL`, `IS_LAPTOP`, `DEFAULT_BROWSER_DESKTOP`, etc.) to share state across submodules.

### 2. `snowfox`
- **Purpose:** Primary Command Line Interface (CLI) to control the entire system.
- **Functionality:**
  - Checks for the existence of CLI modules under `/usr/local/lib/snowfox/cli/`.
  - Sources all submodules (`utils.sh`, `gum.sh`, `status.sh`, `system.sh`, `hardware.sh`, `media.sh`, `security.sh`, `desktop.sh`, `network.sh`, `stash.sh`, `settings.sh`, `doctor.sh`, `mesh.sh`, `ai.sh`, `snap.sh`, `tor.sh`, `help.sh`, `tui.sh`).
  - Detects once whether a Gum TUI is possible (`gum` installed + interactive terminal) and caches the result (`SNOWFOX_TUI=0/1` overrides it).
  - Acts as a dispatcher for all `snowfox <command>` calls with short aliases (e.g., `st`, `up`, `prof`, `doc`, `air`, `dl`, `wall`).
  - Plain `snowfox` (or `snowfox tui`) opens the Gum **control center**; when gum/TTY is unavailable it falls back to the classic help text.
  - **TUI convention:** every command *without arguments* opens its own Gum TUI in an interactive terminal; supplying arguments keeps the classic, scriptable behaviour (`SNOWFOX_TUI=0` forces plain output).

### 3. `snowfox-greeting.sh`
- **Purpose:** Interactive greeting banner shown when opening new terminal sessions.
- **Functionality:**
  - Prevents multiple displays per terminal session using a temporary state file in `/tmp/`.
  - Determines time of day, date, system uptime, available RAM, and free disk space.
  - Displays a short fox ASCII animation (`🦊 ( - . - )` -> `🦊 ( ^ . ^ )`) and presents a random project quote.

---

## 📚 Installation Modules (`lib/`)

Scripts in the `lib/` directory execute individual setup phases. They run within the same process context as `install.sh`.

### `lib/utils.sh`
- Defines standard color variables (`PURPLE`, `ORANGE`, `GREEN`, etc.) for consistent console output.
- Provides helper functions: `info()`, `success()`, `warn()`, `error()`, `step()`, `ask_install()`.
- Includes `wait_apt()` to prevent installation failures caused by blocked `dpkg`/`apt` locks.

### `lib/system_setup.sh`
- Reusable system functions:
  - `set_system_language()`: Switches system locales and console keyboard layout.
  - `set_system_version()`: Writes `/etc/os-release`, `/etc/issue`, and syncs distro name with GRUB.
  - `set_grub_theme()`: Installs a centered, minimalist SnowFox GRUB boot menu.

### `lib/base_system.sh` (Step 1)
- Disables background `apt-daily` services during setup.
- Configures Debian `sources.list` including `contrib`, `non-free`, and `non-free-firmware`.
- Enables `i386` architecture for multiarch support.
- Installs essential packages (`curl`, `git`, `htop`, `btop`, `aria2`, `xorg`, `xinit`, `xclip`, `qt5ct`, etc.).
- Configures `systemd-resolved` and masks conflicting `dnsmasq`.
- Sets up `/etc/X11/Xwrapper.config` (`allowed_users=anybody`, `needs_root_rights=auto`) and adds the user to key groups (`video`, `input`, `render`, `tty`, `audio`) so rootless `startx` works without sudo.
- Downloads and installs system info tool `fastfetch`.

### `lib/kernel_drivers.sh` (Step 2)
- Inspects CPU for AVX2 support: On modern CPUs, installs high-performance `linux-xanmod-lts-x64v3` kernel; falls back to standard Debian LTS kernel on older hardware.
- Automatically detects GPUs (NVIDIA, AMD, Intel, Hybrid):
  - **NVIDIA:** Installs CUDA drivers, Vulkan ICDs, and builds DKMS kernel modules.
  - **AMD / Hybrid Fix:** Configures `/etc/modprobe.d/amdgpu.conf` (`dcfeaturemask=0x8`) to disable Panel Self Refresh (PSR), fixing freezes/deadlocks on AMD+NVIDIA laptops.
  - **Intel:** Installs VA-API drivers for hardware video decoding.
- Sets up kernel boot parameters in GRUB to prevent PCIe AER loops and USB autosuspend issues.
- Installs laptop optimizations (`tlp`, `thermald`) if notebook hardware is detected.

### `lib/desktop_environment.sh` (Step 3)
- Installs desktop stack: `i3`, `i3lock`, `picom`, `polybar`, `rofi`, `dunst`, `feh`, `redshift`, `scrot`, `brightnessctl`, `playerctl`, `cups`, etc.
- Builds `clipnotify` from source and sets up `clip-saver.sh`.
- Downloads and installs `Bibata-Modern-Classic` cursor theme and `JetBrainsMono Nerd Font`.
- Builds and installs `bluetui` (Terminal Bluetooth Manager).
- Creates Rofi-compatible `.desktop` entries for network and Bluetooth.
- Generates `~/.xinitrc` with environment variables (`GTK_THEME=Arc-Dark`, `QT_QPA_PLATFORMTHEME=qt5ct`, `XDG_CURRENT_DESKTOP=i3`) and launches `xsettingsd` alongside `i3`.

### `lib/audio_terminal.sh` (Step 4)
- Configures modern audio stack based on `PipeWire` and `WirePlumber` (purges legacy PulseAudio).
- Configures WirePlumber & BlueZ for high-quality Bluetooth audio profiles (A2DP, SBC-XQ, LDAC, aptX).
- Enables user services for the target user via `loginctl enable-linger`.
- Configures GPU-accelerated terminal `Kitty` with the SnowFox color palette and transparency.

### `lib/default_apps.sh` (Step 5)
- Installs standard applications (`kitty`, `mc`, `ristretto`, `file-roller`, `mpv`, `ffmpeg`).
- Prompts for file manager (`PCManFM`), code editor (`Geany` with selected plugins like Git, Ctags, ProjectOrganizer), and screenshot tool (`Flameshot`).
- Allows optional installation of `GIMP`, `VSCodium`, and `OnlyOffice`.
- Installs `yt-dlp` along with `Node.js` (JavaScript runtime for signature decryption).
- Installs `gum` (Charm TUI toolkit for `snowfox music`) — via apt if available, otherwise as an arch-aware prebuilt binary from GitHub releases.
- Clones `SnowFox Console Launcher` for Steam and retro gaming.

### `lib/browser_selection.sh` (Step 6)
- Interactive browser installer offering:
  1. **Zen Browser** (Firefox-based privacy browser — default)
  2. **LibreWolf** (Hardened Firefox)
  3. **Brave** (Chromium-based)
  4. **Firefox-ESR** (Debian Stable default)
  5. **Chromium**
- Configures `.desktop` files and MIME types according to selection.

### `lib/mesh_module.sh` (Step 6b)
- Sets up decentralized **Reticulum P2P Mesh Network** via `pipx` / `pip3`.
- Copies advanced mesh script `snowfox-mesh.sh` to `~/.config/snowfox-mesh.sh`.
- Sets up folder structures for local downloads and mesh file sharing (`Downloads/MeshShare`).

### `lib/gaming_ai.sh` (Step 7/7b)
- **Steam & Gaming:** Optionally installs Steam, GameMode, i386 Vulkan drivers, and automatically downloads **Proton GE** into the Steam compatibility directory.
- **Ollama (AI):** Optionally installs local AI engine Ollama.
- **Console Launcher:** Configures game hub for Steam, GOG, and emulation.

### `lib/performance_security.sh` (Step 8)
- Installs and configures `zRAM` (lz4 compression, 50% RAM size as compressed swap).
- Optimizes kernel sysctl parameters in `/etc/sysctl.d/99-snowfox.conf` (`vm.swappiness=10`, `bbr` congestion control, IPv6 Privacy Extensions).
- Optimizes `/etc/fstab` with `noatime` and mounts `/tmp` on a 4GB `tmpfs` RAM disk.
- Configures `UFW` firewall (Default Deny incoming, Default Allow outgoing).
- Configures DNS-over-TLS via `systemd-resolved` using Cloudflare (1.1.1.1) and Quad9 (9.9.9.9).
- Disables unneeded background services (`cups-browsed`, `avahi-daemon`, `ModemManager`, `colord`).
- Applies kernel hardening (`/etc/sysctl.d/99-snowfox-security.conf`: restricts `dmesg`, `kptr_restrict`, `bpf_disabled`, hardlink/symlink protection).
- Disables SSH service by default for maximum security.

### `lib/boot_screen.sh` (Step 9)
- Generates a Plymouth boot theme featuring the SnowFox logo on a dark background.
- Applies minimalist GRUB boot theme.

### `lib/theming_finishing.sh` (Step 10)
- Sets distro identity (`SnowFoxOS v3`, hostname `snowfox`).
- Installs and configures themes for GTK2, GTK3, GTK4, and Qt5/Qt6 (`Arc-Dark`, `Papirus-Dark`, `Bibata-Modern-Classic`).
- Applies violet accent color to Papirus folders.
- Copies repository configurations (`configs/`) to `~/.config/`.
- Dynamically configures Polybar for detected hardware (laptop vs. desktop, battery and backlight device detection).
- Writes default MIME associations (`mimeapps.list`).
- Sets correct file ownership for target user.
- Restores disabled DKMS hooks and rebuilds `initramfs`.

### `lib/cleanup_final.sh`
- Cleans unneeded packages using `apt-get autoremove --purge`.
- Displays success banner and prompts for reboot.

---

## 🎮 CLI Control System (`cli/`)

CLI modules reside at `/usr/local/lib/snowfox/cli/` after installation and are managed by the main `snowfox` executable.

### `cli/utils.sh`
- Terminal output formatting utilities: ANSI color definitions, box headers (`header()`), dividers (`divider()`), status rows (`row()`, `bool_row()`), progress bars (`bar()`), and loading spinners (`spin_start()`).

### `cli/gum.sh` — shared Gum TUI library
- Central theme (SnowFox purple palette matching Polybar/Kitty) and reusable `sf_*` widgets used by every TUI module:
  - Detection: `sf_tui_detect` / `sf_can_tui` / `sf_have_gum` (cached; `SNOWFOX_TUI=0/1` override).
  - Decoration (stderr only, so `$( )` captures stay clean): `sf_banner`, `sf_note`, `sf_keyhint`.
  - Input widgets (result on stdout): `sf_choose`, `sf_input`, `sf_secret`, `sf_filter`, `sf_confirm`, `sf_spin`, `sf_spin_do`, `sf_pager`, `sf_page`, `sf_pause`.
  - TUI-aware prompts that fall back to plain `read` without gum: `sf_yesno`, `sf_ask`, `sf_ask_secret`.
  - `sf_gum_missing` prints shared install instructions (Charm APT repo, prebuilt binary, `go install`).

### `cli/tui.sh` — Gum control center (`snowfox` / `snowfox tui`)
- Main menu that launches every other command (status, battery, update, profiles, doctor, GPU, kill switches, air mode, audit, Tor, media, network, wallpaper, display, autostart, layout, WebApps, stash, settings, snapshots, AI, help).
- Plain `snowfox` opens it automatically in an interactive terminal; without gum/TTY it falls back to the help overview.

### `cli/help.sh` (`snowfox h` / `snowfox help`)
- Displays structured, colorized help for all available CLI commands; inside the TUI the overview opens in the Gum pager.

### `cli/status.sh` (`snowfox st` / `snowfox bat`)
- `cmd_status`: Provides real-time information on uptime, RAM usage, disk space, CPU, GPU, IP address, airmode, microphone/camera status, and current mode.
- `cmd_battery`: Detailed battery diagnostics including charge state, wattage draw, remaining time, and battery health %.

### `cli/system.sh` (`snowfox up` / `snowfox prof` / `snowfox node` / `snowfox rst`)
- `cmd_update`: Updates system packages or the entire repository including CLI, configs, and `yt-dlp` (includes automatic config backup).
- `cmd_profile`: Toggles system power/performance profiles:
  - `balanced`: `schedutil` governor, swappiness 10, Redshift enabled.
  - `performance`: `performance` governor, swappiness 10.
  - `battery`: `powersave` governor, swappiness 60.
  - `privacy`: Blocks all wireless interfaces (Wi-Fi & Bluetooth).
- `cmd_node`: Switches system operational modes:
  - `d` (Desktop): Full i3 + Polybar desktop environment.
  - `s` (Server): Terminates X11, switches to `multi-user.target` for minimal footprint.
  - `c` (Console): Launches game hub on Workspace 8.
- `function_reset_system`: Factory resets the system to minimal Debian after explicit confirmation ("YES").

### `cli/hardware.sh` (`snowfox gpu` / `snowfox kill` / `snowfox air`)
- `cmd_gpu`: Displays loaded GPU drivers, NVIDIA-SMI status, AMD PSR fixes, and VA-API status.
- `cmd_kill`: Hardware kill switches for peripherals: `mic` (mute), `cam` (unloads `uvcvideo` module), `all` (complete silence mode), and `restore`.
- `cmd_air`: Disables all wireless interfaces (`rfkill block all`).

### `cli/security.sh` (`snowfox audit`)
- Inspects active TCP/UDP network connections, maps them to processes, and color-codes local vs. external IP addresses. Includes live refresh mode (`snowfox audit live`).

### `cli/media.sh` (`snowfox stream` / `snowfox dl` / `snowfox fetch`)
- `cmd_stream`: Searches YouTube and streams media directly in `mpv` without a browser (uses cookie extraction to bypass bot checks).
- `cmd_download`: Downloads videos or audio (MP3/Opus) via `yt-dlp`.
- `cmd_fetch`: Uses `aria2` for high-speed downloads across 16 parallel connections.

### `cli/music.sh` (`snowfox music`)
- Interactive **Gum-based TUI** for music streaming with the SnowFox color theme (rounded banners, themed pickers, spinners, pager).
- `Browse & Search`: Searches the active source (YouTube Music, Spotify, SoundCloud or YouTube via `yt-dlp`) and plays tracks directly in `mpv`, or saves them to a playlist.
- `Playlists`: Creates, views (pager), plays and deletes JSON playlists stored in `~/.config/snowfox/playlists.json`.
- `Streaming Source`: Changes the search backend (persisted in `~/.config/snowfox/music_source.txt`).
- `Stream direct URL`: Plays any direct media link through `mpv`.
- **Dependency check:** if `gum` is not installed, the command prints step-by-step installation instructions (Charm APT repository, prebuilt binary, or `go install`) and exits cleanly.

### `cli/desktop.sh` (`snowfox auto` / `snowfox lay` / `snowfox web` / `snowfox wall` / `snowfox disp`)
- `cmd_start`: Manages autostart entries in i3 and `~/.config/autostart/`.
- `cmd_layout`: Dynamically toggles between tiling window management and classic floating window mode.
- `cmd_webapp`: Creates isolated WebApps using Zen Browser (fetches favicons, hides browser UI elements via `userChrome.css`, and generates `.desktop` files for Rofi).
- `cmd_wallpaper`: Gum TUI wallpaper picker (filter list, applies via `feh`); `snowfox wall gui` starts the classic Rofi selector.
- `cmd_display`: Gum TUI display setup (mirror, extend, primary only, arrangement) for X11/xrandr; `snowfox disp gui` starts the classic Rofi manager.

### `cli/network.sh` (`snowfox net`)
- Gum TUI frontend for NetworkManager (`nmcli`): Wi-Fi scan/connect/disconnect, saved networks (forget), connection details, and an optional Rofi GUI (`snowfox net gui`).

### `cli/stash.sh` (`snowfox stash`)
- Integrated software catalog and package manager frontend for `apt` with a full Gum TUI (categories, apt search, installed apps, package actions, upgrades).
- Offers curated categories (`internet`, `office`, `ide`, `media`, `gaming`, `ai`, `security`, `system`, etc.), search features, size previews, and protection against accidental removal of core system components.

### `cli/settings.sh` (`snowfox set` / `snowfox bt` / `snowfox kb` / `snowfox lang` / `snowfox tz` / `snowfox user` / `snowfox def`)
- Gum TUI settings center (`snowfox set`) for default applications, keyboard layout, system language, timezone (incl. full timezone search), Bluetooth, and user management — each accessible directly via its own command (`snowfox bt`, `snowfox kb`, …).
- Classic terminal overview (`snowfox set overview`) and Rofi GUI (`snowfox set gui`) remain available.

### `cli/doctor.sh` (`snowfox doc`)
- Comprehensive diagnostic tool: Inspects RAM, swap, top RAM consumers, missing kernel firmware, GPU drivers, i3 syntax, running audio services, systemd failures, disk space, and security components.
- Inside the TUI the report runs under a spinner and opens in the Gum pager with an OK/WARN/FAIL summary.

### `cli/mesh.sh` (`snowfox mesh`)
- Wrapper script forwarding commands to the standalone P2P Mesh engine (`~/.config/snowfox-mesh.sh`).

### `cli/ai.sh` (`snowfox ai`)
- Interactive chat UI for local offline AI (Ollama) with a Gum TUI menu (start chat with model picker, installed models, pull, history, clear).
- Features pre-configured system prompts with deep knowledge of SnowFoxOS, model management (`pull`, `models`), and local chat history (`history`).

### `cli/snap.sh` (`snowfox snap`)
- Creates, compares (`diff`), and restores backups (`snapshots`) of personal desktop configurations (`i3`, `polybar`, `rofi`, `dunst`, `kitty`, `picom`).
- Gum TUI: create snapshots, browse/filter existing ones, and restore, diff or delete them; restores always auto-save a `pre-restore` backup first.

### `cli/tor.sh` (`snowfox tor`)
- **Transparent Tor Proxying:** Routes all TCP traffic and DNS queries through Tor (`iptables` redirect to TransPort `9040` & DNSPort `5353`).
- **Fail-Closed Security:** Blocks all network traffic if Tor service stops. Disables IPv6 to prevent leaks.
- Gum TUI menu (enable, disable, status, restart) that runs the individual steps under a spinner and shows the full report in the pager.

---

## ⚙️ Desktop Configurations & Helper Scripts (`configs/`)

### 1. `configs/snowfox-wallpaper.sh`
- Rofi menu for selecting wallpapers from `~/Pictures/wallpapers/`.
- Applies chosen wallpaper via `feh --bg-fill` and persists selection in `~/.fehbg`.

### 2. `configs/snowfox-display.sh`
- Rofi-based display manager for multi-monitor setups.
- Supports mirroring, extending, primary monitor selection, and includes a `Hybrid-Sync Refresh` feature for buffer resynchronization.
- Automatically reloads i3 and restarts Polybar.

### 3. `configs/snowfox-network.sh`
- Rofi GUI for NetworkManager (`nmcli`).
- Displays Wi-Fi networks with signal bars, prompts for passwords, disconnects, manages saved networks, and detects captive portals.

### 4. `configs/snowfox-lock.sh`
- **Smart Lock Screen:** Checks via `playerctl` and `xprop` if media is playing or an application is in fullscreen (prevents locking while watching movies).
- Generates a blurred and dimmed image of the current wallpaper as the background for `i3lock`.

### 5. `configs/powermenu.sh`
- Rofi power menu with Nerd Font icons for Shutdown, Reboot, Logout, Suspend, and Lock.

### 6. `configs/snowfox-mesh.sh`
- Standalone P2P Mesh Engine v5.0 based on Reticulum (RNS).
- Enables infrastructure-free communication over Wi-Fi Ad-Hoc or local Hotspot.
- Includes integrated web server (`Port 8080`) with smartphone chat UI, DHCP server (dnsmasq), and P2P file sharing with SHA-256 catalog.

### 7. `configs/i3/clip-saver.sh`
- Uses `clipnotify` and `xclip` to preserve clipboard contents (text & PNG images) even after source windows are closed. Ignores file manager copy operations to prevent data loss.

### 8. `configs/polybar/launch.sh`
- Polybar startup script. Detects primary monitors and laptop batteries, launching the appropriate profile (`snowfox` or `snowfox-laptop`).

### 9. `configs/polybar/scripts/bluetooth.sh`
- Polybar Bluetooth status module: Displays connection state/device name and toggles power on click.

### 10. `configs/polybar/scripts/network-status.sh`
- Polybar network status module: Dynamically detects default active route and displays Wi-Fi SSID or LAN status.

---

## 💿 ISO Builder (`iso-builder/`)

- `iso-builder/`: Currently under active revision / empty in preparation for updated ISO build tooling.

---

## ⌨️ Shell Completion & Media (`completions/`)

### `completions/snowfox-completion.bash`
- Provides bash auto-completion for `snowfox` CLI (completes main commands incl. `tui`/`menu`, subcommands like `tor restart` or `update packages`, profiles, package names via `apt-cache`, and snapshot IDs).

---

## 📄 Additional Documentation Files

- `README.md`: Main manual containing feature overview, keyboard shortcuts, RAM benchmarks, security hardening specs, and hardware limitations.
- `PROJECT_STRUCTURE.md`: Comprehensive project directory structure and script documentation.
- `SNOWFOX-SANCTUARY.MD`: Architecture, media gradient, and user guide for the SnowFox Den focus/sovereignty module.
- `snowfoxos-iso_builder-readme.md`: Technical documentation and usage guide for the ISO builder.
- `snowfoxos-v3_display-freeze.md`: In-depth analysis and debugging report for AMD+NVIDIA PRIME hybrid GPU freezes.
- `note.txt`: Summary of the 5 core tenets of SnowFoxOS (Sovereign-First, Zero-Infrastructure, Mesh-Native, Hyper-Resilient, Ultra-Low-Resource).
- `LICENSE`: Project license (GNU General Public License v3.0 - GPL-3.0).
