#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Installer Entry Point
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Behaviour changes vs v3:
#   - Argument parsing, phase mapping and guards moved into
#     lib/phase.sh (single source of truth).
#   - The default (no-arg) flow is BYTE-FOR-BYTE the same as
#     v3: same module order, same env exports, same hooks.
#   - --phase iso-base uses phase_modules() from phase.sh so
#     the module list stays in one place.
#   - --phase extras: deprecated alias -> warn + exit 0
#     (handled inside phase_parse_args).
# ============================================================

# ── Basic checks before sourcing lib ─────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo: sudo bash install.sh"
    exit 1
fi

# Resolve symlinks so SCRIPT_DIR is the real directory.
SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
export SCRIPT_DIR

# Refuse to run from a directory writable by a non-root user
# (supply-chain hardening, unchanged from v3).
_owner_check() {
    local path="$1"
    local st
    st=$(stat -c '%U %a' "$path" 2>/dev/null) || return 0
    local owner="${st%% *}"
    local mode="${st##* }"
    if [[ "$owner" != "root" ]]; then
        echo "Refusing to run: $path is owned by '$owner', not root." >&2
        echo "Fix with: sudo chown -R root:root \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
    local g="${mode: -2:1}" w="${mode: -1:1}"
    if (( (g & 2) || (w & 2) )); then
        echo "Refusing to run: $path is group- or world-writable (mode $mode)." >&2
        echo "Fix with: sudo chmod -R go-w \"$SCRIPT_DIR\"" >&2
        exit 1
    fi
}
_owner_check "$SCRIPT_DIR"
_owner_check "$SCRIPT_DIR/lib"

if [[ ! -r "$SCRIPT_DIR/lib/checksums.sh" ]]; then
    echo "Missing $SCRIPT_DIR/lib/checksums.sh — installer is fail-closed." >&2
    exit 1
fi

# ── Load utils and phase layer ──────────────────────────────
# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"
# shellcheck source=lib/phase.sh
source "$SCRIPT_DIR/lib/phase.sh"

# ── Parse args + establish phase env ────────────────────────
# (--phase extras exits 0 here with a deprecation warning.)
phase_parse_args "$@"

# ── Debian version check ────────────────────────────────────
if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "This script is optimized for Debian 12 (Bookworm)."
fi

# ── APT policy (lean system, explicit packages only) ────────
APT_POLICY="/etc/apt/apt.conf.d/99-snowfox"
if [[ ! -f "$APT_POLICY" ]] || \
   ! grep -q 'APT::Install-Recommends "false"' "$APT_POLICY"; then
    install -d -m 0755 "$(dirname "$APT_POLICY")"
    cat > "$APT_POLICY" <<'EOF'
// SnowFoxOS APT policy — lean system, explicit packages only
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
    success "APT policy installed (no recommends, no suggests)"
else
    info "APT policy already present: $APT_POLICY"
fi

# ── Target user ────────────────────────────────────────────
detect_target_user

# ── DKMS hook bookkeeping (unchanged from v3) ──────────────
DKMS_HOOKS_FILE="/run/snowfox-dkms-hooks"
cat > "$DKMS_HOOKS_FILE" <<'EOF'
/etc/kernel/postinst.d/dkms
/etc/kernel/prerm.d/dkms
/usr/lib/kernel/install.d/50-dkms.install
EOF
chmod 0600 "$DKMS_HOOKS_FILE"
export DKMS_HOOKS_FILE

# ── Hardware flags (cheap early detection) ─────────────────
export HAS_NVIDIA=false
export HAS_AMD=false
export HAS_INTEL=false
export IS_LAPTOP=false

detect_hardware() {
    local gpu_info=""
    if command -v lspci >/dev/null 2>&1; then
        gpu_info="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"
    fi
    echo "$gpu_info" | grep -qi "nvidia" && HAS_NVIDIA=true
    echo "$gpu_info" | grep -qi "amd"    && HAS_AMD=true
    echo "$gpu_info" | grep -qi "intel"  && HAS_INTEL=true

    IS_LAPTOP=false
    [[ "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true
    ls /sys/class/power_supply/BAT* >/dev/null 2>&1 && IS_LAPTOP=true
    return 0
}
detect_hardware

# ── Network state (ISO phases only) ────────────────────────
export SNOWFOX_NETWORK="online"
if [[ "$SNOWFOX_PHASE" != "full" ]]; then
    if [[ -f /var/lib/snowfox/net-offline ]]; then
        SNOWFOX_NETWORK="offline"
    elif ! timeout 10 bash -c 'exec 3<>/dev/tcp/deb.debian.org/80' 2>/dev/null; then
        SNOWFOX_NETWORK="offline"
    fi
    info "Network state for phase '$SNOWFOX_PHASE': $SNOWFOX_NETWORK"
fi

# ── Chroot systemctl shim (moved to phase.sh) ──────────────
install_chroot_systemctl_shim

# ── Defaults for MIME-related module variables ─────────────
export DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
export DEFAULT_EDITOR_DESKTOP="geany.desktop"
export DEFAULT_FM_DESKTOP="pcmanfm.desktop"

# ── system_setup functions (loaded once, before any module) ─
# shellcheck source=lib/system_setup.sh
source "$SCRIPT_DIR/lib/system_setup.sh"

# ── Module runner ──────────────────────────────────────────
run_module() {
    local module="$1"
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/lib/$module"
}

# ── Flow ───────────────────────────────────────────────────
if [[ "$SNOWFOX_PHASE" == "full" ]]; then
    # Default path — unchanged order and set, as in v3.
    source "$SCRIPT_DIR/lib/base_system.sh"
    source "$SCRIPT_DIR/lib/kernel_drivers.sh"
    source "$SCRIPT_DIR/lib/desktop_environment.sh"
    source "$SCRIPT_DIR/lib/audio_terminal.sh"
    source "$SCRIPT_DIR/lib/default_apps.sh"
    source "$SCRIPT_DIR/lib/performance_security.sh"
    source "$SCRIPT_DIR/lib/boot_screen.sh"
    source "$SCRIPT_DIR/lib/theming_finishing.sh"
    source "$SCRIPT_DIR/lib/cleanup_final.sh"
else
    # Phase-driven path. The module list lives in lib/phase.sh.
    local rc=0
    while IFS= read -r mod; do
        [[ -z "$mod" ]] && continue
        run_module "$mod"
        rc=$?
        if ((rc != 0)); then
            exit "$rc"
        fi
    done < <(phase_modules "$SNOWFOX_PHASE")
fi
