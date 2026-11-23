<div align="center">

<img src="assets/snowfoxos-fox-symmetric-head.png" width="120" alt="SnowFox Logo"/>

# SnowFoxOS v4

**A lean, privacy-oriented i3 desktop based on Debian 12**

![Version](https://img.shields.io/badge/version-v4-9B59B6?style=flat-square)
![Debian](https://img.shields.io/badge/base-Debian%2012-A81D33?style=flat-square&logo=debian&logoColor=white)
![i3](https://img.shields.io/badge/desktop-i3%2FX11-3a86ff?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-9B59B6?style=flat-square)

</div>

---

## What is SnowFoxOS?

SnowFoxOS is a single-script installer that transforms a minimal Debian 12 (Bookworm) netinstall into a fully configured i3 desktop. It is not its own operating system — it is Debian 12, configured the way most people would configure it if they had the time and knew how.

The installer works through ~10 steps: kernel selection, driver setup, desktop environment, security hardening, theming, CLI tools. The result is a system that is immediately usable, with the most important privacy and performance settings already active — and a measured idle RAM of around **153 MB PSS**.

**What SnowFoxOS is not:** A high-security system for adversarial threat models. For protection against state actors or active attackers, use Tails or Whonix.

---

## What's new in v4?

v4 is a substantial rewrite of v3. The core stack (i3, polybar, rofi, PipeWire, kitty) stays unchanged; almost everything else was rethought.

**foxdock** — a new application dock written in pure C (Xlib + Imlib2). No GTK, no GLib, ~5–10 MB RAM. Left-edge vertical icon bar, hover highlight, palette live-reload via SIGHUP, reads `.desktop` files automatically or uses a hand-crafted `dock.conf`.

**Theme engine v4** — reduced from 31 color tokens to 8 core values + a terminal block. All other values are derived. No alpha/transparency anywhere in the system — a deliberate design rule. Themes are plain `key=value` files in `~/.config/snowfox/themes/`; `snowfox theme <name>` renders all configs (i3, polybar, rofi, kitty, dunst, GTK2/3/4, picom) in-place, idempotently, with an automatic backup. Three bundled themes: **nightfox** (dark, purple accent), **dayfox** (light), **mono** (grey).

**Auto-palette from wallpaper** — `snowfox wallpaper auto <path>` extracts dominant colors via ImageMagick, picks bg/accent/fg by contrast ratio (WCAG-inspired), and activates the result as a live theme.

**Phase-layer / ISO preparation** — `install.sh` now accepts `--phase iso-base|iso-gpu|firstboot` for unattended chroot installs, enabling a proper bootable ISO path.

**AIDE file integrity** — baseline for `/usr/bin`, `/usr/sbin`, `/usr/local/bin`, `/etc` and autostart paths, initialised at first boot and checked daily.

**Automatic security updates** — `unattended-upgrades` configured for the Debian Security pocket only, daily, with unused dependency cleanup.

**Config snapshots** — `snowfox snap save|restore|diff|list` saves and restores the full `~/.config/snowfox/` state.

**Removed from v4:** mesh network module, gaming/AI launcher, Ollama, Tor mode (available via `snowfox stash`), browser pre-selection (Firefox ESR is the default; alternatives via stash), Kitty transparency (design rule: no alpha).

---

## Why this project?

Most desktop Linux setups are either too complex to configure for privacy and performance, or too comfortable with telemetry and cloud dependencies. SnowFoxOS attempts a third way: a system that is sensibly configured out of the box, without requiring the user to understand every decision behind it.

The underlying conviction: a computer should belong to the user — not to the services they run on it.

> *Your computer belongs to you. Not Microsoft. Not anyone else.*
> — Alexander Valentin Ludwig

Whether SnowFoxOS fulfills that for you is something you can verify yourself using the means described below.

---

## Security & Privacy

### What SnowFoxOS concretely does

**Kernel hardening** — the following sysctl values are set in `/etc/sysctl.d/99-snowfox-security.conf`:

```
kernel.kptr_restrict=2              # Hide kernel pointers from userspace
kernel.perf_event_paranoid=3        # Restrict performance events
kernel.unprivileged_bpf_disabled=1  # BPF for root only
net.core.bpf_jit_harden=2          # JIT spray protection
kernel.dmesg_restrict=1             # dmesg for root only
fs.suid_dumpable=0                  # No core dumps for SUID programs
kernel.core_pattern=|/bin/false     # Core dumps discarded
```

**Network hardening** — in `/etc/sysctl.d/99-snowfox.conf`:

```
net.ipv4.conf.all.rp_filter=1               # Reverse path filtering
net.ipv4.conf.all.accept_redirects=0        # Reject ICMP redirects
net.ipv4.tcp_syncookies=1                   # SYN flood protection
net.ipv6.conf.all.use_tempaddr=2            # IPv6 privacy extensions
net.core.default_qdisc=fq                  # Fair queuing
net.ipv4.tcp_congestion_control=bbr        # BBR congestion control
```

**DNS-over-TLS** — `/etc/systemd/resolved.conf` is configured so that all DNS requests run encrypted via Cloudflare (1.1.1.1) and Quad9 (9.9.9.9). DNS is bootstrapped before the first `apt` call during installation, so no package fetch leaks plain DNS. Verify with:

```bash
resolvectl status
# Shows: DNS over TLS: yes
```

**Firewall** — UFW with default-deny incoming, default-allow outgoing. SSH is disabled and masked. Check with:

```bash
sudo ufw status verbose
systemctl is-enabled ssh
# Output: disabled
```

**AIDE file integrity** — baseline covers `/usr/bin`, `/usr/sbin`, `/usr/local/bin`, `/etc`, and user autostart paths. Checked daily. Initialised automatically at first boot.

**Automatic security updates** — `unattended-upgrades` runs daily, Debian Security pocket only. No other pocket, no auto-reboot.

### What you can verify yourself

```bash
snowfox audit        # active connections with process + destination
snowfox audit live   # live refresh every 2 seconds
sysctl kernel.kptr_restrict
sysctl net.core.bpf_jit_harden
```

### Limits — what SnowFoxOS does not protect against

**X11 is structurally insecure.** Any running application can read the screen contents of all other applications under X11 and intercept keyboard input — without root privileges. This is not a SnowFoxOS problem but a fundamental X11 problem. Anyone who wants to avoid this needs Wayland.

**No AppArmor or SELinux.** Processes run without Mandatory Access Control. A compromised process has full user rights in its own home directory.

**No anonymity network built in.** Tor is available via `snowfox stash` as an opt-in transparent proxy, but it is not a substitute for Tails or Whonix.

**Security updates are automatic; other updates are not.** Run `snowfox update` manually for non-security packages.

---

## Performance

### RAM measurement

The following measurement was taken with `smem` on an HP 250 G8 (Intel i5-1135G7, 8 GB RAM), directly after startup with no open applications other than the desktop stack:

```bash
smem -tk -s pss -r | tail -1
# Result: ~153 MB PSS (Proportional Set Size)
```

PSS is the most accurate method — shared libraries are counted proportionally instead of double. The value from `free -h` is higher because it includes the page cache, which is immediately released when needed.

**Running processes during measurement:** Xorg, i3, polybar, foxdock, picom, pipewire, wireplumber, dunst, lxpolkit, xsettingsd, clip-saver, xss-lock, dbus

| State | RAM (PSS) |
|---|---|
| Desktop stack idle | ~153 MB |
| + Kitty Terminal | ~175 MB |
| + Firefox ESR (5 tabs) | ~700–900 MB |
| + OnlyOffice | +500 MB |
| + Steam in background | +300 MB |

For comparison (community benchmarks, `free -h` `used` value — not directly comparable with PSS):

| System | Idle RAM |
|---|---|
| Windows 11 | ~3.5 GB |
| Ubuntu (GNOME) | ~1.5 GB |
| KDE Plasma | ~900 MB |
| Arch Linux with i3 | ~400–500 MB |
| **SnowFoxOS v4 (`free -h`)** | **~673 MB** |
| **SnowFoxOS v4 (PSS)** | **~153 MB** |

> The comparison values for other systems come from community benchmarks and use `free -h` — a different measurement method than PSS. A direct comparison is therefore only partially possible. What can be said with certainty: SnowFoxOS is a lean system.

### What performance concretely means

**zram** replaces traditional swap — compressed swap in RAM with lz4, 50% RAM size, `PRIORITY=100`. `vm.swappiness=10` keeps data in RAM as long as possible.

**No display manager** — i3 starts directly from TTY1, no GDM/LightDM running in the background.

**XanMod LTS kernel** — installed on CPUs with AVX2 (Intel Haswell 2013+ / AMD Excavator 2015+). Automatic fallback to the standard Debian kernel on older hardware.

**Disabled services** during installation: `cups-browsed`, `avahi-daemon`, `ModemManager`, `colord`, `apt-daily`, `apt-daily-upgrade`, `NetworkManager-wait-online`.

**`fstab` with `noatime`** — no access timestamps written, reduces disk I/O.

**foxdock** — pure C dock, no GTK dependency, ~5–10 MB RAM.

---

## Features

- **i3 WM** — tiling window manager with smart gaps. Floating windows automatically receive a title bar, accent-colored border, fixed size and centering. Back to tiling: everything is automatically removed.
- **foxdock** — custom application dock in pure C (Xlib + Imlib2). Left-edge vertical icon bar, hover highlight, palette live-reload via SIGHUP, reads `.desktop` files automatically.
- **Polybar** — status bar with RAM, battery, network, volume, Bluetooth and system tray. Minimal 2-color design: seamless pills, accent border-bottom, JetBrainsMono Nerd Font.
- **Rofi** — app launcher with SnowFox theme
- **Kitty** — GPU-accelerated terminal with SnowFox color palette, JetBrainsMono Nerd Font
- **picom** — compositor with rounded corners and soft shadows. No transparency anywhere — design rule.
- **Zen Browser** — privacy-focused browser based on Firefox (optional, via stash)
- **PipeWire** — modern audio stack with WirePlumber
- **Dunst** — notification daemon, themed to the active palette
- **Theme engine** — 8 core color tokens, everything else derived. `snowfox theme <name>` renders all configs in-place. Three bundled themes: nightfox, dayfox, mono.
- **Auto-palette from wallpaper** — `snowfox wallpaper auto <path>` generates a theme from dominant image colors
- **Clip-Saver** — keeps clipboard contents active even after closing the source window (`clipnotify` + `xclip`)
- **Flameshot** — screenshot tool with area selection and annotation
- **Neovim** — lightweight code editor, minimal config
- **WebApps** — `snowfox web add <name> <url>` creates isolated browser instances with app-like appearance
- **Stash** — `snowfox stash` to find, inspect and install software by category
- **Config snapshots** — `snowfox snap` saves and restores the full config state
- **Live network audit** — `snowfox audit live` refreshes active connections every 2 seconds
- **fastfetch** — system info with SnowFox logo
- **zram** — compressed swap in RAM (lz4, 50%)
- **tlp** — battery optimization for laptops
- **earlyoom** — OOM protection, kills on 4% RAM / 10% swap
- **ufw** — firewall, default-deny incoming
- **DNS-over-TLS** — via systemd-resolved, Cloudflare + Quad9
- **AIDE** — file integrity baseline, checked daily
- **Automatic security updates** — Debian Security pocket only
- **GPU detection** — automatic driver installation for AMD, NVIDIA, Intel, Hybrid
- **XanMod LTS kernel** — on AVX2-capable CPUs; automatic Debian kernel fallback on older hardware
- **Hybrid GPU freeze fix** — PSR deactivation and Scatter-Gather Display fix for AMD+NVIDIA dual-monitor setups
- **Dark mode** — theme-aware across GTK2/3/4 and Qt
- **Smart Lock** — does not lock when video is playing or fullscreen is active, blurred wallpaper as background
- **yt-dlp** — video/audio without browser
- **redshift** — color temperature adjustment

---

## snowfox CLI

`snowfox` is the central control. All functions are accessible via a single command with short flat aliases. `snowfox help` shows the overview, `snowfox <command> --help` shows details for a command.

### System & Status

| Command | Description |
|---|---|
| `snowfox help` / `h` | Help: overview of all commands |
| `snowfox status` / `st` | System overview: RAM, disk, uptime, GPU mode, network |
| `snowfox status battery` | Battery, consumption & health |
| `snowfox update` / `up` | Update system & CLI (including yt-dlp) |
| `snowfox profile [name]` | Switch profile: balanced, performance, battery, privacy |
| `snowfox doctor` / `doc` | Diagnostics: RAM, drivers, configs |
| `snowfox reset` / `rst` | Factory reset — resets to minimal Debian state, deletes all data |

### Hardware & Privacy

| Command | Description |
|---|---|
| `snowfox kill [mic\|cam\|all\|restore]` | Hardware kill switches (microphone, webcam, or microphone + camera + wireless; `restore` resets all) |
| `snowfox air [on\|off\|status]` | Disable all wireless interfaces |
| `snowfox audit` | Active network connections with process and destination IP |
| `snowfox audit live` | Live mode: refreshes active connections every 2 seconds |
| `snowfox gpu` | GPU information and driver status |

### Media

| Command | Description |
|---|---|
| `snowfox stream <search\|URL>` | Stream video/audio directly in mpv — no browser, no tracking |
| `snowfox download` / `dl <URL>` | Download video or audio |
| `snowfox fetch <URL>` | High-speed download via parallel connections |

### Theme & Wallpaper

| Command | Description |
|---|---|
| `snowfox theme [name]` | Switch theme; without argument: list with color preview |
| `snowfox theme check` | Validate all theme files |
| `snowfox theme gui` | Rofi-based theme picker |
| `snowfox wallpaper` / `wall` | Wallpaper selector |
| `snowfox wallpaper auto <path>` | Generate and activate palette from image |

### Software & Desktop

| Command | Description |
|---|---|
| `snowfox stash` | Software stash: overview of categories |
| `snowfox stash <category>` | List software in a category |
| `snowfox stash find <term>` | Search for software |
| `snowfox stash install <name>` | Install software |
| `snowfox snap [save\|restore\|diff\|list]` | Config snapshots |
| `snowfox web [add\|list\|open\|remove]` | Manage web apps |
| `snowfox auto [list\|enable\|disable]` | Manage autostart |
| `snowfox layout` / `lay [tiling\|floating]` | Switch window mode |
| `snowfox net` | Network manager |
| `snowfox disp` | Display configuration |
| `snowfox lock` | Lock screen |

### Settings

| Command | Description |
|---|---|
| `snowfox set` | Settings overview (terminal) |
| `snowfox set gui` | Settings overview (Rofi menu) |
| `snowfox bt [on\|off\|toggle]` | Bluetooth control |
| `snowfox kb [layout]` | Keyboard layout (e.g. `de`, `us`) |
| `snowfox lang [locale]` | System language (e.g. `en_US.UTF-8`) |
| `snowfox tz [zone]` | Timezone (e.g. `Europe/Berlin`) |
| `snowfox user [passwd\|add\|del]` | User management |
| `snowfox def [set] <key> <val>` | Default applications |

### System Profiles

| Profile | CPU Governor | Swappiness | Network |
|---|---|---|---|
| `balanced` | schedutil | 10 | on |
| `performance` | performance | 10 | on |
| `battery` | powersave | 60 | on |
| `privacy` | schedutil | 10 | everything off |

---

## Installation

**Prerequisite:** Fresh **Debian 12 (Bookworm) minimal installation** with a normal (non-root) user. Only Debian 12 is supported — Ubuntu, Mint, Kali and derivatives do not work. x86-64 only.

### Step 1 — Install Debian 12 minimal

Download ISO: [debian.org/distrib/netinst](https://www.debian.org/distrib/netinst/)

During software selection, **deselect everything** — including the desktop. Leave only "Standard system utilities" or leave completely empty.

### Step 2 — Preparation

```bash
su -
apt-get install -y sudo git
usermod -aG sudo YOURUSERNAME
exit
exit
```

Log out and back in so the group change takes effect.

### Step 3 — Clone and run

```bash
git clone https://github.com/Xr7-Code/SnowFoxOS.git
cd SnowFoxOS
sudo bash install.sh
```

The installer is interactive: it asks about language, timezone, keyboard layout, and optional packages. Duration depending on internet speed: **20–60 minutes**.

### Step 4 — Reboot

```bash
sudo reboot
```

i3 starts automatically from TTY1. No display manager.

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Super + Return` | Terminal (Kitty) |
| `Super + Space` | App launcher (Rofi) |
| `Super + Tab` | Switch window |
| `Super + E` | File manager (PCManFM) |
| `Super + N` | Network manager |
| `Super + W` | Wallpaper selector |
| `Super + P` | Display configuration |
| `Super + L` | Lock screen |
| `Super + Q` | Close window |
| `Super + F` | Toggle fullscreen |
| `Super + H / V` | Split horizontal / vertical |
| `Super + Shift + Space` | Floating toggle (auto size, auto border, centering) |
| `Super + 1–9` | Switch workspace |
| `Super + Shift + 1–9` | Move window to workspace |
| `Super + R` | Resize mode |
| `Super + Shift + R` | Reload i3 |
| `Super + Shift + E` | Power menu |
| `Print` | Screenshot (Flameshot, full screen → clipboard + saved) |
| `Super + Print` | Flameshot area screenshot + annotation → clipboard |

---

## Stack

| Component | Package / Source | Notes |
|---|---|---|
| Base | Debian 12 Bookworm | Minimal install, no recommends |
| Kernel | XanMod LTS (xanmod.org) | AVX2 CPUs only; Debian kernel as fallback |
| WM | i3 | Tiling, no compositor bloat |
| Compositor | picom | Rounded corners only, no transparency |
| Bar | polybar | Minimal modules, theme-aware colors |
| Dock | foxdock (custom, pure C) | Xlib + Imlib2, no GTK, ~5–10 MB PSS |
| Launcher | rofi | App launcher + window switcher |
| Terminal | Kitty | GPU-accelerated, ligature support |
| Editor | Neovim | Minimal config, no IDE plugins |
| File manager | PCManFM | Lightweight, no Qt |
| Notifications | dunst | Themeable, low overhead |
| Network | nmtui / NetworkManager | CLI + TUI, no applet daemon |
| Display | arandr + autorandr | Multi-monitor profiles |
| Screenshots | Flameshot | Area + annotation |
| Lock screen | i3lock-color | Blurred screenshot lock |
| Audio | PipeWire + WirePlumber | ALSA/PulseAudio compatible |
| Fonts | JetBrainsMono Nerd Font | Verified checksum download |
| Cursor | Bibata Modern Ice | Verified checksum download |
| Icons | Papirus-Dark | — |
| Clipboard | xclip + clip-saver | Keeps clipboard alive after window close |
| RAM swap | zram (lz4, 50% RAM) | PRIORITY=100, swappiness=10 |
| OOM guard | earlyoom | Kills on 4% RAM / 10% swap |
| Firewall | UFW | Default-deny, no open ports |
| Integrity | AIDE | Custom rules for /usr/bin, /etc, autostart |
| DNS | systemd-resolved (DoT) | Cloudflare 1.1.1.1 / Quad9 |
| Updates | unattended-upgrades | Security pocket only, no reboots |
| Battery | tlp | Laptops only, auto-detected |
| Night light | redshift | — |
| Media player | mpv + yt-dlp | — |
| Screenshot fallback | scrot | — |
| Brightness | brightnessctl | — |
| Media control | playerctl | — |
| Printer | cups | — |
| GTK theme | Arc-Dark + SnowFox overrides | — |
| Thermal | thermald | — |
| Bluetooth UI | bluetui | — |

---

## Limitations

- **Debian 12 only.** No Ubuntu, Mint, Kali or other derivatives. The installer is not portable.
- **x86-64 only.** ARM and 32-bit are not supported.
- **Single-user assumption.** The setup is designed for one user per machine; multi-user scenarios are untested.
- **No Wayland.** SnowFoxOS is built on X11 (Xorg). Wayland is explicitly not planned.
- **No NVIDIA proprietary drivers.** NVIDIA Nouveau works. For proprietary drivers, install them manually after setup.
- **Internet required.** The installer downloads packages, fonts, and the XanMod kernel at runtime. Offline installs are not supported.
- **foxdock tooltips not wired yet.** `draw_tooltip()` in `draw.c` is complete and functional, but the main event loop in `main.c` does not call it. Planned for v4.1.

### Hardware Requirements

**XanMod kernel requires AVX2** — Intel Haswell (2013) or newer, AMD Excavator (2015) or newer. The installer detects this automatically and falls back to the standard Debian kernel. Check:

```bash
grep avx2 /proc/cpuinfo | head -1
```

**NVIDIA: Maxwell (2014) or newer** — GTX 750 / GTX 900 series and newer, all RTX generations. Older cards are not supported.

**AMD + NVIDIA Hybrid** — two fixes are applied automatically by the installer:

1. **PSR fix** — `dcfeaturemask=0x8` disables Panel Self Refresh in the AMD display engine, which caused `dma_fence_wait_timeout` deadlocks on wakeup. Set in `/etc/modprobe.d/amdgpu.conf`.

2. **Scatter-Gather Display fix** — `sg_display=0` disables Scatter-Gather memory for the AMD display controller. On PRIME setups where AMD acts as output-slave to NVIDIA, the AMD display engine can enter a `dma_fence_wait_timeout` deadlock while waiting for a fence signal from the NVIDIA side. Since AMD renders nothing itself in this configuration, Scatter-Gather provides no benefit. Also set in `/etc/modprobe.d/amdgpu.conf`.

Additionally, picom is configured with `backend = "glx"` instead of `xrender`. The xrender backend has no native synchronisation with the NVIDIA driver and causes the AMD output to freeze.

Verify all three settings:

```bash
cat /etc/modprobe.d/amdgpu.conf
# Should contain:
# options amdgpu dcfeaturemask=0x8
# options amdgpu runpm=0
# options amdgpu sg_display=0

grep "backend" ~/.config/picom.conf
# Should show: backend = "glx";
```

### Known Issues

**Dual-monitor tray popups** may appear on the wrong monitor — known i3/GTK issue. Workaround: `Super + mouse click` to move.

**VirtualBox** injects Wayland variables into the environment which interferes with picom and other X11 tools. SnowFoxOS is designed for real hardware, not VMs.

---

## License

SnowFoxOS is released under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

---

<div align="center">
<sub>Built by Alexander Valentin Ludwig (Xr7-Code) on Debian 12</sub>
</div>
