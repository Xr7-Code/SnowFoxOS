#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — CLI: system
#  update / profile / reset
# ============================================================

if [[ -n "${_SNOWFOX_CLI_SYSTEM_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_SNOWFOX_CLI_SYSTEM_LOADED=1

# ---------------------------------------------------------------------------
# _snowfox_source_dir — locate the SnowFoxOS source tree at runtime.
#   Priority:
#     1. SNOWFOX_SRC_DIR env var (set by CI or manual override)
#     2. The git repo that contains this CLI file (works when running from a
#        development clone or after "git pull")
#     3. /usr/local/share/snowfox  (installed package location)
#   Returns "" when none of the above exist.
# ---------------------------------------------------------------------------
_snowfox_source_dir() {
    local d
    # 1. Explicit override
    [[ -n "${SNOWFOX_SRC_DIR:-}" && -d "$SNOWFOX_SRC_DIR" ]] && { echo "$SNOWFOX_SRC_DIR"; return; }
    # 2. Derive from this file's real path (resolve symlinks)
    d="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
    # Climb until we find install.sh (project root)
    while [[ -n "$d" && "$d" != "/" ]]; do
        d="$(dirname "$d")"
        [[ -f "$d/install.sh" ]] && { echo "$d"; return; }
    done
    # 3. Standard installed location
    [[ -d /usr/local/share/snowfox ]] && { echo "/usr/local/share/snowfox"; return; }
    echo ""
}

# ---------------------------------------------------------------------------
# _fix_script_permissions PATH [PATH …]
#   Makes every *.sh file under the given directories executable (0755).
# ---------------------------------------------------------------------------
_fix_script_permissions() {
    local path
    for path in "$@"; do
        [[ -d "$path" ]] || continue
        find "$path" -type f -name "*.sh" -exec chmod 0755 {} +
    done
}

cmd_update() {
    header "snowfox update"

    if [[ $EUID -ne 0 ]]; then
        err "This command must be run as root (try: sudo snowfox update)"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        err "apt-get not found"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    if ! timeout 5 bash -c 'exec 3<>/dev/tcp/deb.debian.org/80' 2>/dev/null; then
        err "network unavailable"
        return "$SNOWFOX_EXIT_NETWORK"
    fi

    # ── 1. APT packages ─────────────────────────────────────
    info "apt-get update"
    apt-get update -qq || { err "apt-get update failed"; return "$SNOWFOX_EXIT_ERROR"; }
    info "apt-get upgrade"
    apt-get upgrade -y || { err "apt-get upgrade failed"; return "$SNOWFOX_EXIT_ERROR"; }
    ok "APT packages updated"

    # ── 2. SnowFoxOS source update ───────────────────────────
    local src_dir
    src_dir="$(_snowfox_source_dir)"

    if [[ -z "$src_dir" ]]; then
        warn "SnowFoxOS source directory not found — skipping CLI/Lib/Configs/foxdock update"
        warn "Set SNOWFOX_SRC_DIR or place source at /usr/local/share/snowfox"
    else
        info "Source dir: $src_dir"

        # git pull (if inside a git repo)
        if [[ -d "$src_dir/.git" ]]; then
            info "git pull (source update)"
            if git -C "$src_dir" pull --ff-only 2>&1 | grep -v "^Already up to date"; then
                ok "git pull successful"
            else
                warn "git pull skipped or failed — continuing with current source"
            fi
        fi

        # ── 2a. CLI scripts ─────────────────────────────────
        if [[ -d "$src_dir/cli" ]]; then
            info "Updating CLI scripts → /usr/local/lib/snowfox/cli/"
            mkdir -p /usr/local/lib/snowfox/cli
            cp "$src_dir/cli/"*.sh /usr/local/lib/snowfox/cli/
            chmod 0644 /usr/local/lib/snowfox/cli/*.sh
            ok "CLI scripts updated"
        fi

        # ── 2b. snowfox main binary ──────────────────────────
        if [[ -f "$src_dir/snowfox" ]]; then
            info "Updating /usr/local/bin/snowfox"
            cp "$src_dir/snowfox" /usr/local/bin/snowfox
            chmod 0755 /usr/local/bin/snowfox
            ok "snowfox binary updated"
        fi

        # ── 2c. Lib (theme_engine + other libs) ─────────────
        if [[ -d "$src_dir/lib" ]]; then
            info "Updating lib → /usr/local/lib/snowfox/lib/"
            mkdir -p /usr/local/lib/snowfox/lib
            cp "$src_dir/lib/"*.sh /usr/local/lib/snowfox/lib/
            chmod 0644 /usr/local/lib/snowfox/lib/*.sh
            ok "Lib scripts updated"
        fi

        # ── 2d. User configs (polybar, rofi, dunst, …) ──────
        #   Only overwrite files that also exist in the source tree; never
        #   touch user-customised files that have no source counterpart.
        local target_home="${TARGET_HOME:-$HOME}"
        local config_dir="$target_home/.config"
        if [[ -d "$src_dir/configs" && -d "$config_dir" ]]; then
            info "Syncing config templates → $config_dir"
            # rsync-style copy: update only, preserve newer user files
            find "$src_dir/configs" -type f | while IFS= read -r src_file; do
                local rel="${src_file#"$src_dir/configs/"}"
                local dst_file="$config_dir/$rel"
                # Skip palette/theme state files — user-owned
                case "$rel" in
                    snowfox/palette.conf|snowfox/theme) continue ;;
                esac
                mkdir -p "$(dirname "$dst_file")"
                cp "$src_file" "$dst_file"
            done
            ok "Config templates synced"

            # Enforce execute bit on all scripts under ~/.config
            _fix_script_permissions "$config_dir/scripts" \
                                    "$config_dir/polybar/scripts"
            ok "Config script permissions enforced"
        fi

        # ── 2e. foxdock rebuild & install ───────────────────
        if [[ -d "$src_dir/foxdock" && -f "$src_dir/foxdock/Makefile" ]]; then
            if command -v make >/dev/null 2>&1; then
                info "Rebuilding foxdock…"
                if make -C "$src_dir/foxdock" -j"$(nproc)" 2>&1; then
                    if make -C "$src_dir/foxdock" install 2>&1; then
                        ok "foxdock rebuilt and installed"
                        # Signal running instance to reload palette
                        pkill -HUP -x foxdock 2>/dev/null || true
                    else
                        warn "foxdock install step failed"
                    fi
                else
                    warn "foxdock build failed — libx11-dev/libimlib2-dev missing?"
                fi
            else
                warn "make not found — skipping foxdock rebuild"
            fi
        fi

        # ── 2f. Bash completion ──────────────────────────────
        if [[ -f "$src_dir/completions/snowfox-completion.bash" ]]; then
            mkdir -p /usr/local/lib/snowfox/completions
            cp "$src_dir/completions/snowfox-completion.bash" \
               /usr/local/lib/snowfox/completions/snowfox-completion.bash
            [[ -d /etc/bash_completion.d ]] && \
                ln -sf /usr/local/lib/snowfox/completions/snowfox-completion.bash \
                       /etc/bash_completion.d/snowfox 2>/dev/null || true
            ok "Bash completion updated"
        fi
    fi

    # ── 3. Always enforce permissions on installed lib scripts ──
    _fix_script_permissions \
        /usr/local/lib/snowfox \
        "${TARGET_HOME:-$HOME}/.config/scripts" \
        "${TARGET_HOME:-$HOME}/.config/polybar/scripts"

    ok "system updated"
}

cmd_profile() {
    local which="${1:-}"
    case "$which" in
        ""|list)
            header "snowfox profile"
            info "available: balanced · performance · battery · privacy"
            local cur
            cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
            row "CPU governor" "$cur"
            return 0
            ;;
        balanced)
            header "profile: balanced"
            _set_governor schedutil 2>/dev/null || _set_governor powersave || true
            row_dot "CPU governor" ok "balanced"
            ;;
        performance)
            header "profile: performance"
            _set_governor performance
            row_dot "CPU governor" ok "performance"
            ;;
        battery)
            header "profile: battery"
            _set_governor powersave
            row_dot "CPU governor" ok "powersave"
            ;;
        privacy)
            header "profile: privacy"
            systemctl restart systemd-resolved 2>/dev/null || true
            row_dot "DNS" ok "DoT strict"
            ;;
        *)
            err "unknown profile: $which"
            return "$SNOWFOX_EXIT_ERROR"
            ;;
    esac
}

_set_governor() {
    local g="$1"
    local c
    for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -w "$c" ]] && echo "$g" > "$c" 2>/dev/null || true
    done
}

cmd_reset() {
    header "snowfox reset"
    warn "this will delete all user data and restore SnowFoxOS to defaults"
    local confirm
    read -rp "  type 'RESET' to continue: " confirm
    if [[ "$confirm" != "RESET" ]]; then
        info "aborted"
        return "$SNOWFOX_EXIT_OK"
    fi
    info "resetting…"
    if [[ -x /usr/local/bin/snowfox-reset ]]; then
        /usr/local/bin/snowfox-reset
    else
        err "snowfox-reset not installed"
        return "$SNOWFOX_EXIT_ERROR"
    fi
}
