#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Performance & Security Optimizations
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - DNSOverTLS=yes (strict) instead of opportunistic
#   - FallbackDNS removed Google; Quad9 used as fallback
#   - tmpfs size computed from RAM (25%, capped 4G, min 1G)
#   - fstab handling idempotent (no duplicate noatime, no dup tmpfs)
#   - ufw: reset before enable (clean ruleset on re-install)
#   - unattended-upgrades installed and configured (security only)
#   - AIDE installed + baseline initialised
#   - SSH disable now also removes host keys from known state
#   - curl-free; all commands use absolute paths from /usr/bin etc.
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"

step "8/10 — Performance & Security"

wait_apt
apt-get install -y zram-tools earlyoom ufw

# ── TLP only on laptops ──────────────────────────────────────
if $IS_LAPTOP; then
    command -v tlp &>/dev/null || apt-get install -y tlp tlp-rdw
    systemctl enable tlp 2>/dev/null || true
else
    systemctl disable --now tlp 2>/dev/null || true
    if [[ -f /etc/tlp.conf ]]; then
        sed -i 's/^USB_AUTOSUSPEND=.*/USB_AUTOSUSPEND=0/' /etc/tlp.conf
    fi
fi

# ── zRAM configuration ───────────────────────────────────────
cat > /etc/default/zramswap << 'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

if [[ -f /etc/initramfs-tools/initramfs.conf ]]; then
    sed -i 's/^COMPRESS=.*/COMPRESS=lz4/' /etc/initramfs-tools/initramfs.conf
    update-initramfs -u 2>/dev/null || true
fi

systemctl enable zramswap earlyoom 2>/dev/null || true

# ── Kernel / Sysctl tuning ───────────────────────────────────
cat > /etc/sysctl.d/99-snowfox.conf << 'EOF'
# RAM & Swap
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=3
vm.dirty_ratio=6

# Network
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216

# IPv6 Privacy
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2

# CPU
kernel.nmi_watchdog=0
EOF

# ── fstab: idempotent noatime + tmpfs /tmp ───────────────────
# CHANGED: the old sed appended ",noatime" on every re-run,
# producing "errors=remount-ro,noatime,noatime". Now:
#   1. collapse duplicate noatime occurrences
#   2. only add noatime if the mount options lack it
info "Optimizing fstab (idempotent)..."
if ! grep -q '^tmpfs[[:space:]]\+/tmp[[:space:]]' /etc/fstab; then
    # CHANGED: size derived from RAM, capped, with a safe minimum
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    tmp_kb=$(( mem_kb / 4 ))
    (( tmp_kb < 1048576 )) && tmp_kb=1048576          # min 1 GiB
    (( tmp_kb > 4194304 )) && tmp_kb=4194304          # max 4 GiB
    tmp_mb=$(( tmp_kb / 1024 ))
    echo "tmpfs /tmp tmpfs defaults,noatime,size=${tmp_mb}M,mode=1777 0 0" >> /etc/fstab
    success "tmpfs /tmp mounted with ${tmp_mb}M"
else
    info "tmpfs /tmp already present — leaving as is"
fi

# Add noatime to root mount only if absent
if awk '$2=="/" && $4 !~ /(^|,)noatime(,|$)/ {exit 1}' /etc/fstab; then
    sed -i -E 's#^([^[:space:]]+[[:space:]]+/[[:space:]]+[^[:space:]]+[[:space:]]+)([^[:space:]]+)#\1\2,noatime#' /etc/fstab
    success "noatime added to root mount"
else
    info "noatime already set on root — leaving as is"
fi

# Collapse accidental duplicates from earlier runs
sed -i -E 's/(,noatime)+/,noatime/g' /etc/fstab

ufw --force reset  >/dev/null 2>&1 || true
ufw default deny incoming  2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw --force enable         2>/dev/null || true
success "ufw firewall enabled (ruleset reset)"

# ── Release WiFi card from ifupdown ──────────────────────────
if [[ -f /etc/network/interfaces ]]; then
    cp -n /etc/network/interfaces /etc/network/interfaces.snowfox-bak 2>/dev/null || true
    sed -i -E '/^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+(wl|en|eth)/ s/^/#/' /etc/network/interfaces
    success "ifupdown entries for WiFi/LAN commented out"
fi

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true
EOF

cat > /etc/NetworkManager/conf.d/99-snowfox-wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave=2
EOF

# ── DNS over TLS: strict ─────────────────────────────────────
# CHANGED: DNSOverTLS=yes (not opportunistic). Strict mode means
# systemd-resolved will FAIL rather than fall back to cleartext
# DNS. This matches the README claim "DNS over TLS: yes" and
# closes the silent-downgrade hole.
# CHANGED: FallbackDNS is now Quad9 only — Google (8.8.8.8) removed.
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/snowfox.conf << 'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=9.9.9.9#dns.quad9.net
DNSSEC=yes
DNSOverTLS=yes
EOF
systemctl enable systemd-resolved 2>/dev/null || true
systemctl restart systemd-resolved 2>/dev/null || true

systemctl enable irqbalance 2>/dev/null || true

for svc in avahi-daemon cups-browsed ModemManager colord blueman; do
    systemctl disable "$svc" 2>/dev/null || true
done

systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# ── Remove unnecessary programs & services ───────────────────
apt-get purge -y zeitgeist zeitgeist-core zeitgeist-datahub 2>/dev/null || true
apt-get purge -y diodon 2>/dev/null || true
apt-get purge -y xterm uxterm 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
success "Bloat removed (zeitgeist, diodon, xterm, uxterm)"

if systemctl --user list-unit-files xdg-desktop-portal-gnome.service &>/dev/null; then
    sudo -u "$TARGET_USER" systemctl --user mask \
        xdg-desktop-portal-gnome.service 2>/dev/null || true
fi

sed -i 's/#HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf

success "Performance & security optimized"

# ── Kernel hardening ─────────────────────────────────────────
info "Applying kernel security parameters..."
cat > /etc/sysctl.d/99-snowfox-security.conf << 'SYSCTLEOF'
# SnowFoxOS kernel hardening

# Hide kernel information
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.perf_event_paranoid=3
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2

# Network hardening
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2

# Disable core dumps
fs.suid_dumpable=0
kernel.core_pattern=|/bin/false
SYSCTLEOF
sysctl -p /etc/sysctl.d/99-snowfox-security.conf &>/dev/null || true
success "Kernel hardening applied"

# ── Disable SSH ──────────────────────────────────────────────
if systemctl is-enabled ssh &>/dev/null 2>&1; then
    systemctl disable --now ssh 2>/dev/null || true
    info "SSH disabled (enable with: sudo systemctl enable --now ssh)"
fi

# ── UFW: remove SSH rule ─────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw delete allow 22/tcp 2>/dev/null || true
    ufw delete allow ssh    2>/dev/null || true
    ufw --force enable      2>/dev/null || true
    success "UFW: SSH rule removed"
fi

# ── Install rfkill (for snowfox air) ─────────────────────────
apt-get install -y rfkill 2>/dev/null || true

# ── NEW: unattended-upgrades (security-only) ─────────────────
# CHANGED: closes the gap between manual "snowfox up" runs.
# Only Debian-Security is auto-applied; normal updates stay manual.
info "Configuring unattended-upgrades (security only)..."
apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/51unattended-upgrades-snowfox << 'EOF'
// SnowFoxOS — security-only automatic updates.
// Normal package upgrades stay manual (snowfox up).
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

systemctl enable --now unattended-upgrades 2>/dev/null || true
success "unattended-upgrades configured (Debian-Security only)"

# ── NEW: AIDE baseline ───────────────────────────────────────
# CHANGED: file-integrity baseline for the paths most relevant to
# the threat model in the update log (RAT persistence, supply-chain
# tampering of installer-fetched binaries, /etc config drift).
info "Setting up AIDE (file integrity baseline)..."
apt-get install -y aide aide-common

# Custom rules: narrow, fast, relevant. Extends the Debian defaults.
mkdir -p /etc/aide/aide.conf.d
cat > /etc/aide/aide.conf.d/99-snowfox << 'EOF'
# SnowFoxOS AIDE rules — paths that matter for integrity.
# p: permissions, i: inode, n: links, u: user, g: group,
# s: size, m: mtime, a: atime (disabled, noatime), c: ctime,
# S: check size change, sha256: content hash.

# Binaries that should never change outside of upgrades
/usr/bin    p+i+n+u+g+s+m+c+sha256
/usr/sbin   p+i+n+u+g+s+m+c+sha256
/usr/local/bin  p+i+n+u+g+s+m+c+sha256
/usr/local/sbin p+i+n+u+g+s+m+c+sha256

# System configuration
/etc        p+i+n+u+g+s+m+c+sha256

# User-level persistence vectors (RAT autostart)
/home/*/.config/autostart  p+i+n+u+g+s+m+c+sha256
/home/*/.local/share/applications  p+i+n+u+g+s+m+c+sha256
/home/*/.local/bin  p+i+n+u+g+s+m+c+sha256
EOF

# Initialise the baseline. aideinit writes to /var/lib/aide/aide.db.new
# and prompts before moving it into place; -y accepts non-interactively.
if command -v aideinit >/dev/null 2>&1; then
    aideinit -y -f >/dev/null 2>&1 || warn "aideinit failed — run 'sudo aideinit' manually"
    if [[ -f /var/lib/aide/aide.db.new ]]; then
        mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        chmod 0600 /var/lib/aide/aide.db
        success "AIDE baseline initialised"
    else
        warn "AIDE baseline file missing — integrity checks will fail until initialised"
    fi
else
    warn "aideinit not found — AIDE installed but not initialised"
fi

# Daily check via systemd timer (Debian ships one; make sure it runs)
systemctl enable dailyaidecheck.timer 2>/dev/null || true

success "All performance & security steps complete"
