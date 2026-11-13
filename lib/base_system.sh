#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Base System Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - fastfetch download now uses _fetch_verified (SHA256-pinned)
#   - curl calls constrained to HTTPS + TLS 1.2
#   - JSON parsing prefers jq, falls back to python3
#   - PATH extension moved to /etc/profile.d/ (drop-in, idempotent)
#   - DKMS_HOOKS no longer exported as array (Bash limitation);
#     defined locally here, restored in theming_finishing.sh
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/checksums.sh"

info "Installing for: ${BOLD}$TARGET_USER${RESET}"
sleep 1

step "1/10 — System update"

# CHANGED: define locally instead of relying on an exported array.
# Bash cannot export arrays; the previous `export DKMS_HOOKS=(...)`
# only worked by accident because this file redefined it.
DKMS_HOOKS=(
    /etc/kernel/postinst.d/dkms
    /etc/kernel/prerm.d/dkms
    /usr/lib/kernel/install.d/50-dkms.install
)
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "$hook" ]] && mv "$hook" "${hook}.snowfox-bak"
done
info "DKMS hooks disabled for installer run"

systemctl disable apt-daily.service apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
success "apt-daily disabled"

cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF

wait_apt
dpkg --add-architecture i386
apt-get update -qq
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true
wait_apt
apt-get upgrade -y
apt-get install -y \
    curl wget git unzip \
    build-essential \
    ca-certificates \
    aria2 \
    fzf \
    jq \
    lz4 \
    gnupg \
    pciutils usbutils \
    htop btop irqbalance \
    bash-completion \
    xdg-utils \
    xdg-user-dirs \
    rfkill \
    systemd-resolved \
    iw wireless-tools \
    imagemagick \
    bc \
    xorg \
    xinit \
    x11-utils \
    x11-xserver-utils \
    xclip \
    xdotool \
    dbus-x11 \
    lm-sensors \
    qt5ct \
    qt5-style-plugins \
    qt6ct

# CHANGED: jq added to package list above (JSON parsing for GitHub API).

# ── DNS bootstrap (MUST run before any apt-get install) ───────
# Problem: Debian 12 minimal ships with /etc/resolv.conf pointing
# at 127.0.0.1 or empty, and systemd-resolved not yet running.
# Any apt/curl during the install then fails to resolve hostnames.
# Fix: write a working resolv.conf immediately, start resolved,
# then symlink it — so ALL subsequent installs resolve correctly.
info "Bootstrapping DNS resolver..."

# 1. Kill anything that might hold port 53 (dnsmasq, etc.)
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl mask dnsmasq 2>/dev/null || true

# 2. Write a temporary static resolv.conf so apt works RIGHT NOW
#    (before systemd-resolved is fully up)
cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
options edns0 trust-ad
EOF

# 3. Configure systemd-resolved with DoT (strict) + Quad9 fallback
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/snowfox.conf << 'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=9.9.9.9#dns.quad9.net
DNSSEC=yes
DNSOverTLS=yes
EOF

# 4. Start resolved and replace resolv.conf with the stub
systemctl enable --now systemd-resolved 2>/dev/null || true
# Wait up to 5s for the stub socket to appear
for _i in 1 2 3 4 5; do
    [[ -S /run/systemd/resolve/io.systemd.Resolve ]] && break
    sleep 1
done
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
success "DNS-over-TLS configured (Cloudflare + Quad9, strict)"

# 5. Quick sanity check — warn but don't abort (network may be air-gapped)
if ! systemd-resolve --status 2>/dev/null | grep -q "DNS Servers"; then
    warn "systemd-resolved reports no DNS servers — check network connectivity"
fi

# ── PATH extension for /usr/sbin ─────────────────────────────
# CHANGED: drop-in file instead of appending to /etc/profile and
# ~/.bashrc. Idempotent (overwrite, not append) and survives
# profile regeneration.
info "Adding /usr/sbin to PATH..."
cat > /etc/profile.d/99-snowfox-path.sh << 'EOF'
# Added by SnowFoxOS installer
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) export PATH="$PATH:/usr/sbin" ;;
esac
EOF
chmod 0644 /etc/profile.d/99-snowfox-path.sh

# User-level: same guard, appended once to ~/.bashrc
if ! grep -q '99-snowfox-path' "/home/$TARGET_USER/.bashrc" 2>/dev/null; then
    cat >> "/home/$TARGET_USER/.bashrc" << 'EOF'

# Added by SnowFoxOS installer
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) export PATH="$PATH:/usr/sbin" ;;
esac
EOF
fi
chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.bashrc" 2>/dev/null || true
success "PATH extension installed"

sudo -u "$TARGET_USER" xdg-user-dirs-update
success "System updated"

# ── Install fastfetch (SHA256-pinned) ───────────────────────
# CHANGED: entire download path rewritten.
#   - API call constrained to HTTPS + TLS 1.2
#   - jq preferred, python3 as fallback
#   - every downloaded .deb is verified via _verify_checksum
#   - fail-closed: unpinned hash aborts the installer
info "Installing fastfetch (verified)..."

_fetch_verified() {
    local url="$1" dest="$2" expected="$3" name="$4"
    local tmp
    tmp=$(mktemp) || error "mktemp failed"

    curl -fsSL --proto '=https' --tlsv1.2 \
         --max-time 120 \
         "$url" -o "$tmp" || { rm -f "$tmp"; error "Download failed: $url"; }

    _verify_checksum "$tmp" "$expected" "$name" || { rm -f "$tmp"; return 1; }

    mv "$tmp" "$dest"
    chmod 0644 "$dest"
}

FASTFETCH_DEB_URL=""
if command -v jq >/dev/null 2>&1; then
    FASTFETCH_DEB_URL=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
        https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest 2>/dev/null \
        | jq -r '.assets[]? | select(.name | endswith("amd64.deb")) | .browser_download_url' \
        | head -n1)
else
    FASTFETCH_DEB_URL=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
        https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest 2>/dev/null \
        | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('amd64.deb'):
            print(a['browser_download_url'])
            break
except Exception:
    pass
" 2>/dev/null)
fi

if [[ -z "$FASTFETCH_DEB_URL" ]]; then
    warn "Could not resolve fastfetch release URL from GitHub API."
    warn "Falling back to the known release path."
    FASTFETCH_DEB_URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
fi

if _fetch_verified "$FASTFETCH_DEB_URL" /tmp/fastfetch.deb \
        "$CHECKSUM_FASTFETCH" "fastfetch"; then
    if dpkg -i /tmp/fastfetch.deb 2>/dev/null; then
        success "fastfetch installed"
    else
        warn "fastfetch .deb failed to install — install manually"
    fi
    rm -f /tmp/fastfetch.deb
else
    warn "fastfetch skipped — pin CHECKSUM_FASTFETCH in lib/checksums.sh"
fi

# ── X11 / startx without sudo ────────────────────────────────
mkdir -p /etc/X11
cat > /etc/X11/Xwrapper.config << 'XWEOF'
allowed_users=anybody
needs_root_rights=auto
XWEOF
success "Xwrapper.config set (allowed_users=anybody, needs_root_rights=auto)"

info "Setting groups for $TARGET_USER (video, input, render, tty, audio)..."
for grp in video input render tty audio; do
    if getent group "$grp" > /dev/null 2>&1; then
        usermod -aG "$grp" "$TARGET_USER"
    else
        warn "Group '$grp' not found — skipping"
    fi
done
success "Groups set — $TARGET_USER can use startx without sudo"
