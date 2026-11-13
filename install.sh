#!/bin/bash
# ============================================================
#  SnowFoxOS v3.4 — Installer
#  Base:    Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#
#  Usage:
#    git clone https://github.com/Xr7-Code/SnowFoxOS
#    cd SnowFoxOS
#    sudo bash install.sh
#
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# ── Root check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo: sudo bash install.sh"
    exit 1
fi

# ── Resolve SCRIPT_DIR (symlink-safe) ────────────────────────
SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
export SCRIPT_DIR

# ── Security: refuse if installer dir is not root-owned ──────
_owner_check() {
    local path="$1"
    local st owner mode g w
    st=$(stat -c '%U %a' "$path" 2>/dev/null) || return 0
    owner="${st%% *}"; mode="${st##* }"
    if [[ "$owner" != "root" ]]; then
        echo "Refusing: $path is owned by '$owner', not root." >&2
        echo "Fix: sudo chown -R root:root \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
    g="${mode: -2:1}"; w="${mode: -1:1}"
    if (( (g & 2) || (w & 2) )); then
        echo "Refusing: $path is group/world-writable (mode $mode)." >&2
        echo "Fix: sudo chmod -R go-w \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
}
_owner_check "$SCRIPT_DIR"
_owner_check "$SCRIPT_DIR/lib"

# ── checksums.sh must exist ───────────────────────────────────
if [[ ! -r "$SCRIPT_DIR/lib/checksums.sh" ]]; then
    echo "Missing $SCRIPT_DIR/lib/checksums.sh — installer is fail-closed." >&2
    exit 1
fi

# ── Load utils ───────────────────────────────────────────────
source "$SCRIPT_DIR/lib/utils.sh"

# ── Debian 12 check ──────────────────────────────────────────
if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "This installer is optimised for Debian 12 (Bookworm)."
fi

# ── Determine target user ────────────────────────────────────
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Username to install for: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"
[[ ! -d "$TARGET_HOME" ]] && error "Home directory $TARGET_HOME not found."

export TARGET_USER TARGET_HOME

# ── DKMS hooks shared file ───────────────────────────────────
DKMS_HOOKS_FILE="/run/snowfox-dkms-hooks"
cat > "$DKMS_HOOKS_FILE" << 'EOF'
/etc/kernel/postinst.d/dkms
/etc/kernel/prerm.d/dkms
/usr/lib/kernel/install.d/50-dkms.install
EOF
chmod 0600 "$DKMS_HOOKS_FILE"
export DKMS_HOOKS_FILE

# ── GPU / Hardware detection ─────────────────────────────────
export HAS_NVIDIA=false
export HAS_AMD=false
export HAS_INTEL=false
export IS_LAPTOP=false

lspci 2>/dev/null | grep -qi "nvidia"           && HAS_NVIDIA=true
lspci 2>/dev/null | grep -qi "advanced micro"   && HAS_AMD=true
lspci 2>/dev/null | grep -qi "intel.*graphics"  && HAS_INTEL=true

CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
[[ "$CHASSIS" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true
ls /sys/class/power_supply/BAT* &>/dev/null     && IS_LAPTOP=true

export HAS_NVIDIA HAS_AMD HAS_INTEL IS_LAPTOP

info "SnowFoxOS v3.4 — Installer"
info "Target user : $TARGET_USER"
info "Home        : $TARGET_HOME"
info "Laptop      : $IS_LAPTOP"
info "NVIDIA      : $HAS_NVIDIA | AMD: $HAS_AMD | Intel: $HAS_INTEL"
sleep 1

# ── Run install modules ──────────────────────────────────────
source "$SCRIPT_DIR/lib/base_system.sh"
source "$SCRIPT_DIR/lib/kernel_drivers.sh"
source "$SCRIPT_DIR/lib/desktop_environment.sh"
source "$SCRIPT_DIR/lib/audio_terminal.sh"
source "$SCRIPT_DIR/lib/default_apps.sh"
source "$SCRIPT_DIR/lib/browser_selection.sh"
source "$SCRIPT_DIR/lib/gaming_ai.sh"
source "$SCRIPT_DIR/lib/performance_security.sh"
source "$SCRIPT_DIR/lib/theming_finishing.sh"
source "$SCRIPT_DIR/lib/cleanup_final.sh"
