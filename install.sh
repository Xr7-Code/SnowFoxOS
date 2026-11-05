#!/bin/bash
# ============================================================
#  SnowFoxOS v3 — Installer
#  Base: Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#  Run: sudo bash install.sh
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - SCRIPT_DIR ownership check (refuse to run from a directory
#     writable by a non-root user — prevents lib/*.sh tampering)
#   - checksums.sh presence is enforced up front
#   - DKMS_HOOKS no longer exported (Bash cannot export arrays
#     reliably); it is re-declared in base_system.sh and used by
#     theming_finishing.sh via a shared file
#   - SCRIPT_DIR resolved with readlink -f (symlink-safe)
# ============================================================

# ── Basic checks before sourcing lib ─────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo: sudo bash install.sh"
    exit 1
fi

# CHANGED: resolve symlinks so SCRIPT_DIR is the real directory
SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
export SCRIPT_DIR

# CHANGED: refuse to run if any part of SCRIPT_DIR is writable by
# a non-root user. A world-writable or group-writable installer
# directory is a supply-chain risk: someone could swap lib/*.sh
# between the time you cloned and the time you ran sudo.
_owner_check() {
    local path="$1"
    local st
    st=$(stat -c '%U %a' "$path" 2>/dev/null) || return 0
    local owner="${st%% *}"
    local mode="${st##* }"
    # owner must be root, and the directory must not be group/world writable
    if [[ "$owner" != "root" ]]; then
        echo "Refusing to run: $path is owned by '$owner', not root." >&2
        echo "Fix with: sudo chown -R root:root \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
    # last digit of mode: world permissions; middle: group permissions
    local g="${mode: -2:1}" w="${mode: -1:1}"
    if (( (g & 2) || (w & 2) )); then
        echo "Refusing to run: $path is group- or world-writable (mode $mode)." >&2
        echo "Fix with: sudo chmod -R go-w \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
}
_owner_check "$SCRIPT_DIR"
_owner_check "$SCRIPT_DIR/lib"

# CHANGED: checksums.sh must exist — the installer is fail-closed
# on unpinned dependencies.
if [[ ! -r "$SCRIPT_DIR/lib/checksums.sh" ]]; then
    echo "Missing $SCRIPT_DIR/lib/checksums.sh — installer is fail-closed." >&2
    exit 1
fi

# ── Load utils ───────────────────────────────────────────────
source "$SCRIPT_DIR/lib/utils.sh"

# ── Check Debian version ─────────────────────────────────────
if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "This script is optimized for Debian 12 (Bookworm)."
fi

# ── Determine target user ────────────────────────────────────
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Username: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"
[[ ! -d "$TARGET_HOME" ]] && error "Home $TARGET_HOME not found"

export TARGET_USER
export TARGET_HOME

# CHANGED: DKMS_HOOKS is NOT exported as an array (Bash limitation).
# base_system.sh declares it locally; theming_finishing.sh should
# re-declare the same array. If you prefer a single source of truth,
# write the list to /run/snowfox-dkms-hooks and read it back there.
DKMS_HOOKS_FILE="/run/snowfox-dkms-hooks"
cat > "$DKMS_HOOKS_FILE" << 'EOF'
/etc/kernel/postinst.d/dkms
/etc/kernel/prerm.d/dkms
/usr/lib/kernel/install.d/50-dkms.install
EOF
chmod 0600 "$DKMS_HOOKS_FILE"
export DKMS_HOOKS_FILE

# GPU and hardware flags
export HAS_NVIDIA=false
export HAS_AMD=false
export HAS_INTEL=false
export IS_LAPTOP=false

export DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
export DEFAULT_EDITOR_DESKTOP="geany.desktop"
export DEFAULT_FM_DESKTOP="pcmanfm.desktop"

# ============================================================
#  Load modules — all run in the same shell process (source)
# ============================================================

source "$SCRIPT_DIR/lib/system_setup.sh"
source "$SCRIPT_DIR/lib/base_system.sh"        # Step 1
source "$SCRIPT_DIR/lib/kernel_drivers.sh"     # Step 2
source "$SCRIPT_DIR/lib/desktop_environment.sh" # Step 3
source "$SCRIPT_DIR/lib/audio_terminal.sh"     # Step 4
source "$SCRIPT_DIR/lib/default_apps.sh"       # Step 5
source "$SCRIPT_DIR/lib/browser_selection.sh"  # Step 6
source "$SCRIPT_DIR/lib/mesh_module.sh"        # Step 6b
source "$SCRIPT_DIR/lib/gaming_ai.sh"          # Step 7/7b
source "$SCRIPT_DIR/lib/performance_security.sh" # Step 8
source "$SCRIPT_DIR/lib/boot_screen.sh"        # Step 9
source "$SCRIPT_DIR/lib/theming_finishing.sh"  # Step 10
source "$SCRIPT_DIR/lib/cleanup_final.sh"
