#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Phase Layer
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Central place for everything phase-specific:
#   - CLI argument parsing (--phase <name>, --defaults)
#   - phase -> module list mapping (phase_modules)
#   - chroot / no-systemd guards (require_tty,
#     require_systemd_session, systemd_safe)
#   - target-user detection (detect_target_user)
#   - the systemctl shim for the d-i chroot
#     (install_chroot_systemctl_shim, moved here from v3
#     install.sh — behaviour unchanged)
#
#  Valid phases (v4):
#    full       interactive full install (default, unchanged)
#    iso-base   chroot-safe base install
#    iso-gpu    kernel/GPU phase (may exit 75)
#    firstboot  live-session completion after first reboot
#    extras     DEPRECATED alias -> warns + exit 0
# ============================================================

if [[ -n "${_SNOWFOX_PHASE_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_SNOWFOX_PHASE_LOADED=1

# ── Argument parsing ─────────────────────────────────────────
# Usage: phase_parse_args "$@"
#   --phase <name>   set SNOWFOX_PHASE (validated)
#   --phase=<name>   inline form
#   --defaults       set SNOWFOX_DEFAULTS=true
#   -h|--help        print usage and exit 0
# Unknown options: usage to stderr + exit 1 (fail-closed).
phase_usage() {
    cat <<'EOF'
SnowFoxOS v4 installer

Usage: sudo bash install.sh [options]

Options:
  --phase <name>   full | iso-base | iso-gpu | firstboot   (default: full)
                   (extras: deprecated alias, does nothing)
  --defaults       Answer every prompt with its documented default
  -h, --help       Show this help

Phase mode never creates users and never prompts. The ISO path
detects the user created by debian-installer via UID 1000.
EOF
}

phase_parse_args() {
    SNOWFOX_PHASE="full"
    SNOWFOX_DEFAULTS=false
    while (($#)); do
        case "$1" in
            --phase)
                if [[ -z "${2:-}" ]]; then
                    echo "Missing argument for --phase" >&2
                    phase_usage >&2
                    exit 1
                fi
                SNOWFOX_PHASE="$2"
                shift 2
                ;;
            --phase=*)
                SNOWFOX_PHASE="${1#*=}"
                shift
                ;;
            --defaults)
                SNOWFOX_DEFAULTS=true
                shift
                ;;
            -h|--help)
                phase_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                phase_usage >&2
                exit 1
                ;;
        esac
    done

    case "$SNOWFOX_PHASE" in
        full|iso-base|iso-gpu|firstboot|extras) ;;
        *)
            echo "Unknown phase: $SNOWFOX_PHASE" >&2
            echo "Expected one of: full, iso-base, iso-gpu, firstboot, extras" >&2
            exit 1
            ;;
    esac

    if [[ "$SNOWFOX_PHASE" == "extras" ]]; then
        warn "[deprecated] --phase extras: use 'snowfox stash' instead. Nothing installed."
        exit 0
    fi

    export SNOWFOX_PHASE
    export SNOWFOX_DEFAULTS

    # Backwards compatibility with v3 module code that reads
    # SNOWFOX_UNATTENDED. Meaning: "no interactive prompts".
    if [[ "$SNOWFOX_PHASE" != "full" || "$SNOWFOX_DEFAULTS" == "true" ]]; then
        export SNOWFOX_UNATTENDED=true
    else
        export SNOWFOX_UNATTENDED="${SNOWFOX_UNATTENDED:-false}"
    fi
}

# ── Phase -> module list ─────────────────────────────────────
# Prints the module list, one per line, in execution order.
# install.sh sources lib/system_setup.sh once before the loop.
phase_modules() {
    case "$1" in
        iso-base)
            printf '%s\n' \
                base_system.sh \
                desktop_environment.sh \
                audio_terminal.sh \
                default_apps.sh \
                performance_security.sh \
                boot_screen.sh \
                theming_finishing.sh \
                cleanup_final.sh
            ;;
        iso-gpu)
            printf '%s\n' kernel_drivers.sh
            ;;
        firstboot)
            printf '%s\n' firstboot.sh
            ;;
        *)
            echo "phase_modules: unknown phase '$1'" >&2
            return 1
            ;;
    esac
}

# ── Guards ───────────────────────────────────────────────────
# require_tty: prompt safety.
#   Interactive mode: abort if no TTY (can't prompt).
#   Defaults mode: log + continue (auto-answers are fine).
require_tty() {
    if [[ "${SNOWFOX_DEFAULTS:-false}" == "true" \
       || "${SNOWFOX_UNATTENDED:-false}" == "true" ]]; then
        if [[ ! -t 0 ]]; then
            info "[default] no tty, continuing"
        fi
        return 0
    fi
    if [[ ! -t 0 ]]; then
        error "This step needs an interactive terminal (no TTY)."
    fi
    return 0
}

# require_systemd_session: true iff we are in a live systemd session.
# Chroot checks use this; prompts use require_tty.
require_systemd_session() {
    [[ -d /run/systemd/system ]]
}

# systemd_safe <verb> <unit>
#   enable|disable|mask  -> always executed
#   start|restart|reload -> downgraded to `enable` outside a
#                           live systemd session
#   daemon-reload        -> no-op outside a live systemd session
# This is the high-level API; the low-level systemctl override
# lives in install_chroot_systemctl_shim() further below.
systemd_safe() {
    local verb="$1" unit="$2"
    case "$verb" in
        enable|disable|mask)
            systemctl "$verb" "$unit" 2>/dev/null || true
            ;;
        start|restart|reload|try-restart)
            if require_systemd_session; then
                systemctl "$verb" "$unit" 2>/dev/null || true
            else
                systemctl enable "$unit" 2>/dev/null || true
            fi
            ;;
        daemon-reload)
            if require_systemd_session; then
                systemctl daemon-reload 2>/dev/null || true
            else
                info "chroot: daemon-reload skipped ($unit)"
            fi
            ;;
        *)
            echo "systemd_safe: unknown verb '$verb'" >&2
            return 1
            ;;
    esac
}

# ── Target user detection ────────────────────────────────────
# Exports TARGET_USER and TARGET_HOME.
#   Phase mode: UID 1000 must exist (else exit 1).
#   Interactive: fall back to SUDO_USER/logname, then prompt.
detect_target_user() {
    local phase="${SNOWFOX_PHASE:-full}"
    local user=""

    if [[ "$phase" == "full" ]]; then
        user="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
        if [[ -z "$user" || "$user" == "root" ]]; then
            read -rp "Username: " user
        fi
        if [[ -z "$user" || "$user" == "root" ]]; then
            error "no valid target user provided"
        fi
    else
        user="$(getent passwd 1000 | cut -d: -f1)"
        if [[ -z "$user" ]]; then
            error "no target user with uid 1000 found"
        fi
    fi

    local home
    home="$(getent passwd "$user" | cut -d: -f6)"
    if [[ -z "$home" || ! -d "$home" ]]; then
        error "home directory for '$user' not found"
    fi

    export TARGET_USER="$user"
    export TARGET_HOME="$home"
}

# ── systemctl shim for the d-i chroot ────────────────────────
# Moved verbatim (behaviour-preserving) from v3 install.sh.
# Installs a `systemctl` shell function that maps the verbs a
# live session would support onto ones that work without a
# running systemd. No-op in a live session, so safe to call
# unconditionally.
install_chroot_systemctl_shim() {
    [[ "${SNOWFOX_PHASE:-full}" == "full" ]] && return 0
    [[ -d /run/systemd/system ]] && return 0

    # shellcheck disable=SC2317,SC2329  # invoked indirectly by modules
    systemctl() {
        local action=""
        local -a units=()
        while (($#)); do
            case "$1" in
                --user) return 1 ;;
                --now|--no-block|--quiet|-q) shift ;;
                daemon-reload) return 0 ;;
                start|stop|restart|reload|try-restart|enable|disable|mask|unmask)
                    action="$1"; shift ;;
                is-enabled|is-active|status)
                    command systemctl "$@" 2>/dev/null; return $? ;;
                *) units+=("$1"); shift ;;
            esac
        done
        case "$action" in
            start|restart|reload|try-restart) action="enable" ;;
            stop) action="disable" ;;
            "") return 0 ;;
        esac
        command systemctl "$action" "${units[@]}" 2>/dev/null || true
    }
}
