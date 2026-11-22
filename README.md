SnowFoxOS v4
A lean, privacy-focused i3 desktop — built on Debian 12. 153 MB PSS idle.
What is SnowFoxOS?
SnowFoxOS is a single-script installer that transforms a minimal Debian 12 (Bookworm) netinstall into a fully configured i3 desktop. It is not its own operating system — it is Debian 12, configured the way most people would configure it if they had the time and knew how.
The installer works through ~10 steps: kernel selection, driver setup, desktop environment, security hardening, theming, CLI tools. The result is a system that is immediately usable, with the most important privacy and performance settings already active — and a measured idle RAM of around 153 MB PSS.
What SnowFoxOS is not: A high-security system for adversarial threat models. For protection against state actors, use Tails or Whonix.
Why this project?
Most desktop Linux setups are either too complex to configure for privacy and performance, or too comfortable with telemetry and cloud dependencies. SnowFoxOS attempts a third way: a system that is sensibly configured out of the box, without requiring the user to understand every decision behind it.
The underlying conviction: a computer should belong to the user — not to the services they run on it.
Your computer belongs to you. Not Microsoft. Not anyone else. — Alexander Valentin Ludwig
Whether SnowFoxOS fulfills that for you is something you can verify yourself using the means described in the Security section below.
What's new in v4?
v4 is a substantial rewrite of v3. The core stack (i3, polybar, rofi, PipeWire, kitty) stays unchanged; almost everything else was rethought.
foxdock — a new application dock written in pure C (Xlib + Imlib2). No GTK, no GLib, ~5–10 MB RAM. Left-edge vertical icon bar, palette live-reload via SIGHUP, reads .desktop files automatically.
Theme engine v4 — reduced from 31 color tokens to 8 core values + a terminal block. All other values are derived. No alpha/transparency anywhere in the system — a deliberate design rule. Themes are plain key=value files in ~/.config/snowfox/themes/; snowfox theme <name> renders all configs in-place, idempotently, with an automatic backup.
Auto-palette from wallpaper — snowfox wallpaper auto <path> extracts dominant colors via ImageMagick, picks bg/accent/fg by contrast ratio (WCAG-inspired), and activates the result as a theme.
Phasen-Layer / ISO preparation — install.sh now accepts --phase iso-base|iso-gpu|firstboot for unattended chroot installs, enabling a proper bootable ISO path.
AIDE file integrity — baseline for /usr/bin, /etc and autostart paths, initialised at first boot.
Automatic security updates — unattended-upgrades configured for Debian Security pocket only, daily, with unused dependency cleanup.
Removed from v4: mesh network module, gaming/AI launcher, Ollama, Tor mode (available via snowfox stash), browser pre-selection (Firefox ESR is the default; alternatives via stash), Kitty transparency (design rule: no alpha).
Security & Privacy
What SnowFoxOS concretely does
Kernel hardening — /etc/sysctl.d/99-snowfox-security.conf:
kernel.kptr_restrict=2              # Hide kernel pointers from userspace
kernel.perf_event_paranoid=3        # Restrict performance events
kernel.unprivileged_bpf_disabled=1  # BPF for root only
net.core.bpf_jit_harden=2          # JIT spray protection
kernel.dmesg_restrict=1             # dmesg for root only
fs.suid_dumpable=0                  # No core dumps for SUID programs
kernel.core_pattern=|/bin/false     # Core dumps discarded
Network hardening — /etc/sysctl.d/99-snowfox.conf:
net.ipv4.conf.all.rp_filter=1       # Reverse path filtering
net.ipv4.conf.all.accept_redirects=0
net.ipv4.tcp_syncookies=1           # SYN flood protection
net.ipv6.conf.all.use_tempaddr=2    # IPv6 privacy extensions
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
DNS-over-TLS — all DNS requests go encrypted via Cloudflare (1.1.1.1) and Quad9 (9.9.9.9) through systemd-resolved. DNS is bootstrapped before the first apt call during installation, so no package fetch leaks plain DNS. Verify:
resolvectl status
# DNS over TLS: yes
Firewall — UFW with default-deny incoming, default-allow outgoing. SSH is disabled and masked:
sudo ufw status verbose
systemctl is-enabled ssh
# disabled
AIDE file integrity — baseline covers /usr/bin, /usr/sbin, /usr/local/bin, /etc, and user autostart paths. Checked daily.
Automatic security updates — unattended-upgrades runs daily, Debian Security pocket only. No other pocket, no auto-reboot.
What you can verify
snowfox audit        # active connections with process + destination
snowfox audit live   # live refresh every 2 seconds
sysctl kernel.kptr_restrict
sysctl net.core.bpf_jit_harden
Limits — what SnowFoxOS does not protect against
X11 is structurally insecure. Any running application can read the screen contents and intercept keyboard input of all other applications — without root. This is not a SnowFoxOS problem; it is a fundamental X11 property. Use Wayland if this matters to you.
No AppArmor or SELinux. A compromised process has full user rights in the home directory. Process-level confinement is not provided.
No anonymity network built in. Tor is available via snowfox stash as an opt-in transparent proxy, but it is not a substitute for Tails or Whonix.
Security updates are automatic; other updates are not. Run snowfox update manually for non-security packages.
Performance
RAM measurement
Measured with smem on an HP 250 G8 (Intel i5-1135G7, 8 GB RAM), directly after startup, no open applications other than the desktop stack:
smem -tk -s pss -r | tail -1
# Result: ~153 MB PSS
PSS (Proportional Set Size) is the most accurate method — shared libraries are counted proportionally, not double. The value from free -h is higher because it includes the page cache.
Running processes during measurement: Xorg, i3, polybar, foxdock, picom, pipewire, wireplumber, dunst, lxpolkit, xsettingsd, clip-saver, xss-lock, dbus
State
RAM (PSS)
Desktop stack idle
~153 MB
+ Kitty terminal
~175 MB
+ Firefox ESR (5 tabs)
~700–900 MB
+ OnlyOffice
+500 MB
+ Steam in background
+300 MB
For reference (community benchmarks, free -h — not directly comparable with PSS):
System
Idle RAM
Windows 11
~3.5 GB
Ubuntu (GNOME)
~1.5 GB
KDE Plasma
~900 MB
Arch Linux with i3
~400–500 MB
SnowFoxOS v4 (PSS)
~153 MB
What performance means in practice
zram — compressed swap in RAM (lz4, 50% RAM size, PRIORITY=100). vm.swappiness=10 keeps data in RAM as long as possible.
No display manager — i3 starts directly from TTY1; no GDM or LightDM running in the background.
XanMod LTS kernel — installed on CPUs with AVX2 (Intel Haswell 2013+ / AMD Excavator 2015+). Automatic fallback to the standard Debian kernel on older hardware.
Disabled services: cups-browsed, avahi-daemon, ModemManager, colord, apt-daily, NetworkManager-wait-online.
fstab with noatime — no access timestamps written, reduces disk I/O.
foxdock — pure C dock, no GTK dependency, ~5–10 MB RAM. Replaces heavier dock alternatives.
Features
• i3 WM — tiling window manager with smart gaps. Floating windows automatically receive a title bar, accent-colored border, fixed size and centering; back to tiling removes all of it automatically.
• foxdock — custom application dock in pure C (Xlib + Imlib2). Left-edge vertical icon bar, hover highlight, palette live-reload via SIGHUP, reads .desktop files automatically.
• Polybar — status bar with RAM, battery, network, volume, Bluetooth and system tray. 2-color minimal design: seamless pills, accent border-bottom, JetBrainsMono Nerd Font.
• Rofi — app launcher with SnowFox theme.
• Kitty — GPU-accelerated terminal, JetBrainsMono Nerd Font, SnowFox color palette.
• picom — compositor with rounded corners and soft shadows. No transparency anywhere — design rule.
• PipeWire + WirePlumber — modern audio stack.
• Dunst — notification daemon, themed to the active palette.
• Theme engine — 8 core color tokens, everything else derived. snowfox theme <name> renders all configs in-place (i3, polybar, rofi, kitty, dunst, GTK2/3/4, picom). Three bundled themes: nightfox (dark, purple accent), dayfox (light), mono (grey).
• Auto-palette from wallpaper — snowfox wallpaper auto <path> generates a theme from dominant image colors.
• Clip-Saver — keeps clipboard contents alive after the source window closes (clipnotify + xclip).
• Flameshot — screenshot tool with area selection and annotation.
• Geany — lightweight code editor with Git integration and project management.
• WebApps — snowfox web add <name> <url> creates isolated browser instances with app appearance.
• Stash — snowfox stash to find, inspect and install optional software by category.
• Live network audit — snowfox audit live refreshes active connections every 2 seconds.
• fastfetch — system info display with SnowFox logo.
• zram — compressed swap in RAM (lz4, 50%).
• earlyoom — OOM protection against system freeze.
• tlp — battery optimization (laptops only, auto-detected).
• UFW — firewall, default-deny incoming.
• DNS-over-TLS — via systemd-resolved, Cloudflare + Quad9.
• GPU detection — automatic driver installation for AMD, NVIDIA, Intel and hybrid configurations.
• XanMod LTS kernel — on AVX2-capable CPUs; automatic Debian kernel fallback on older hardware.
• Hybrid GPU freeze fixes — PSR deactivation and Scatter-Gather Display fix for AMD+NVIDIA dual-GPU setups.
• GTK2/3/4 + Qt dark mode — consistent theming across toolkits via xsettingsd, qt5ct, qt6ct.
• Smart Lock — does not lock during video playback or fullscreen; blurred wallpaper as lock screen background.
• yt-dlp — video and audio download without a browser.
• redshift — color temperature adjustment.
• AIDE — file integrity baseline, checked daily.
snowfox CLI
snowfox is the central control. All functions are accessible via a single command with short flat aliases. snowfox help shows the full overview; snowfox <command> --help shows details for a command.
System & Status
Command
Description
snowfox help / h
Help: overview of all commands
snowfox status / st
System overview: RAM, disk, uptime, GPU mode, network
snowfox status battery
Battery, consumption and health
snowfox update / up
Update system and CLI (including yt-dlp)
snowfox profile / prof [name]
Switch profile: balanced, performance, battery, privacy
snowfox doctor / doc
Diagnostics: RAM, drivers, configs
snowfox reset / rst
Factory reset — resets to minimal Debian state
Hardware & Privacy
Command
Description
snowfox kill [mic|cam|all|restore]
Hardware kill switches (microphone, webcam, or all wireless)
snowfox air [on|off|status]
Disable all wireless interfaces
snowfox audit
Active connections with process and destination IP
snowfox audit live
Live mode: refreshes every 2 seconds
snowfox gpu
GPU information and driver status
Media
Command
Description
snowfox stream <search|URL>
Stream video/audio directly in mpv — no browser
snowfox download / dl <URL>
Download video or audio
snowfox fetch <URL>
High-speed download via parallel connections
Theme & Wallpaper
Command
Description
snowfox theme [name]
Switch theme; without argument: list with color preview
snowfox theme check
Validate all theme files
snowfox theme gui
Rofi-based theme picker
snowfox wallpaper / wall
Wallpaper selector
snowfox wallpaper auto <path>
Generate and activate palette from image
Desktop & Settings
Command
Description
snowfox auto [list|enable|disable]
Manage autostart
snowfox layout / lay [tiling|floating]
Switch window mode
snowfox web [add|list|open|remove]
Manage web apps
snowfox stash [category|find|install]
Software stash
snowfox snap [save|restore|list]
Config snapshots
snowfox set
Settings overview
snowfox bt [on|off|toggle]
Bluetooth
snowfox kb [layout]
Keyboard layout
snowfox lang [locale]
System language
snowfox tz [zone]
Timezone
snowfox user [passwd|add|del]
User management
snowfox def [set] <key> <val>
Default applications
System Profiles
Profile
CPU Governor
Swappiness
Network
balanced
schedutil
10
on
performance
performance
10
on
battery
powersave
60
on
privacy
schedutil
10
everything off
Installation
Prerequisite: A fresh Debian 12 (Bookworm) minimal installation with a normal (non-root) user. Only Debian 12 is supported — Ubuntu, Mint, Kali and derivatives do not work.
Step 1 — Install Debian 12 minimal
Download the ISO from debian.org/distrib/netinst. During software selection, deselect everything — including the desktop environment. Leave only "Standard system utilities", or leave completely empty.
Step 2 — Preparation
su -
apt-get install -y sudo git
usermod -aG sudo YOURUSERNAME
exit
exit
Log out and back in so the group change takes effect.
Step 3 — Clone and run
git clone https://github.com/Xr7-Code/SnowFoxOS.git
cd SnowFoxOS
sudo bash install.sh
The installer is interactive: it asks about language, timezone, keyboard layout, and optional packages. Duration depending on internet speed: 20–60 minutes.
Step 4 — Reboot
sudo reboot
i3 starts automatically from TTY1. No display manager.
Keyboard shortcuts
Shortcut
Action
Super + Return
Terminal (Kitty)
Super + Space
App launcher (Rofi)
Super + Tab
Switch window
Super + E
File manager (PCManFM)
Super + N
Network manager
Super + W
Wallpaper selector
Super + P
Display configuration
Super + L
Lock screen
Super + Q
Close window
Super + F
Toggle fullscreen
Super + H / V
Split horizontal / vertical
Super + Shift + Space
Floating toggle (auto size, border, centering)
Super + 1–9
Switch workspace
Super + Shift + 1–9
Move window to workspace
Super + R
Resize mode
Super + Shift + R
Reload i3
Super + Shift + E
Power menu
Print
Screenshot (Flameshot, full screen → clipboard + saved)
Super + Print
Flameshot area screenshot + annotation
Stack
Component
Package / Source
Notes
Base
Debian 12 Bookworm
Minimal install, no recommends
Kernel
XanMod LTS (xanmod.org)
AVX2 CPUs only; Debian kernel as fallback
WM
i3 (i3wm.org)
Tiling, no compositor bloat
Compositor
picom
Rounded corners only, no blur/transparency
Bar
polybar
Minimal modules, theme-aware colors
Dock
foxdock (custom, pure C)
Xlib + Imlib2, no GTK, ~5–10 MB PSS
Launcher
rofi
App launcher + window switcher
Terminal
Kitty
GPU-accelerated, ligature support
Editor
Neovim
Minimal config, no IDE plugins
File manager
PCManFM
Lightweight Qt-free GTK2
Notifications
dunst
Themeable, low overhead
Network
nmtui / NetworkManager
CLI + TUI, no applet daemon
Display
arandr + autorandr
Multi-monitor profiles
Screenshots
Flameshot
Area + annotation
Lock screen
i3lock-color
Blurred screenshot lock
Audio
PipeWire + WirePlumber
ALSA/PulseAudio compatible
Fonts
JetBrainsMono Nerd Font
Verified checksum download
Cursor
Bibata Modern Ice
Verified checksum download
Icons
Papirus-Dark
Installed via script
Clipboard
xclip + clip-saver
History via rofi
RAM swap
zram (lz4, 50 % RAM)
PRIORITY=100, swappiness=10
OOM guard
earlyoom
Kills on 4 % RAM / 10 % swap
Firewall
UFW
Default-deny, no open ports
Integrity
AIDE
Custom rules for /usr/bin, /etc, autostart
DNS
systemd-resolved (DoT)
Cloudflare 1.1.1.1 / 1.0.0.1
Updates
unattended-upgrades
Security pocket only, no reboots
Limitations
• Debian 12 only. No Ubuntu, Mint, Kali or other derivatives. The installer is not portable.
• x86-64 only. ARM and 32-bit are not supported.
• Single-user assumption. The setup is designed for one user per machine; multi-user scenarios are untested.
• No Wayland. SnowFoxOS is built on X11 (Xorg). Wayland is explicitly not planned.
• No NVIDIA proprietary drivers. NVIDIA Nouveau works. For proprietary drivers, install them manually after setup.
• Internet required. The installer downloads packages, fonts, and the XanMod kernel at runtime. Offline installs are not supported.
• Tooltips in foxdock are not wired yet. The draw_tooltip() function exists in the source but is not connected to the event loop in v4.
License
MIT License — see LICENSE in the repository root.
SnowFoxOS is a personal project. It is provided as-is, without warranty of any kind. Use it, fork it, adapt it. Attribution appreciated but not required.
SnowFoxOS v4 — built by one person, one script, one idea: a desktop that stays out of your way.
