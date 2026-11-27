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
    # 1. Explicit override
    [[ -n "${SNOWFOX_SRC_DIR:-}" && -d "$SNOWFOX_SRC_DIR" ]] && { echo "$SNOWFOX_SRC_DIR"; return; }
    # 2. Standard location: /home/$SUDO_USER/SnowFoxOS
    #    When run as root via sudo, $HOME is /root but the source lives in the
    #    invoking user's home. Use $SUDO_USER → getent as fallback.
    local real_user="${SUDO_USER:-}"
    if [[ -z "$real_user" ]]; then
        # Not via sudo — use the current user
        real_user="$(id -un 2>/dev/null)"
    fi
    local real_home
    real_home="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6)"
    if [[ -n "$real_home" ]]; then
        local home_src="$real_home/SnowFoxOS"
        [[ -d "$home_src" && -f "$home_src/install.sh" ]] && { echo "$home_src"; return; }
    fi
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
        # Resolve real user home — $HOME is /root when run via sudo
        local _cfg_user="${SUDO_USER:-$(id -un)}"
        local target_home="${TARGET_HOME:-$(getent passwd "$_cfg_user" 2>/dev/null | cut -d: -f6)}"
        target_home="${target_home:-$HOME}"
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

            # Re-apply the current theme so the palette block is written into
            # the freshly copied config files (e.g. new polybar/config.ini needs
            # a fresh [colors] block before it can resolve ${colors.primary}).
            local saved_theme="nightfox"
            [[ -f "$target_home/.config/snowfox/theme" ]] && \
                saved_theme="$(head -n1 "$target_home/.config/snowfox/theme" | tr -d '[:space:]')"
            local theme_engine="/usr/local/lib/snowfox/lib/theme_engine.sh"
            [[ -f "$src_dir/lib/theme_engine.sh" ]] && \
                theme_engine="$src_dir/lib/theme_engine.sh"
            if [[ -f "$theme_engine" ]]; then
                info "Re-applying theme '$saved_theme' to updated configs…"
                sudo -u "$_cfg_user" \
                    HOME="$target_home" \
                    XDG_CONFIG_HOME="$target_home/.config" \
                    bash -c "source '$theme_engine' && theme_apply '$saved_theme'" \
                    && ok "Theme '$saved_theme' re-applied" \
                    || warn "theme_apply failed — run 'snowfox theme $saved_theme' manually"
            fi
        fi

        # ── 2e. foxdock rebuild & install ───────────────────
        if [[ -d "$src_dir/foxdock" && -f "$src_dir/foxdock/Makefile" ]]; then
            if command -v make >/dev/null 2>&1; then
                info "Rebuilding foxdock…"
                if make -C "$src_dir/foxdock" -j"$(nproc)" 2>&1; then
                    if make -C "$src_dir/foxdock" install 2>&1; then
                        ok "foxdock rebuilt and installed"
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
    # Resolve the real user home (sudo sets $HOME to /root)
    local _perm_home="${TARGET_HOME:-}"
    if [[ -z "$_perm_home" ]]; then
        local _perm_user="${SUDO_USER:-$(id -un)}"
        _perm_home="$(getent passwd "$_perm_user" 2>/dev/null | cut -d: -f6)"
        _perm_home="${_perm_home:-$HOME}"
    fi
    _fix_script_permissions \
        /usr/local/lib/snowfox \
        "$_perm_home/.config/scripts" \
        "$_perm_home/.config/polybar/scripts"

    # ── 4. Reload running desktop components as the real user ───
    # All signals and restarts must run in the user's session, not as root.
    local _reload_user="${SUDO_USER:-}"
    local _reload_home="$_perm_home"
    if [[ -z "$_reload_user" ]]; then
        _reload_user="$(id -un)"
    fi

    # Helper: run a command as the real user with their DISPLAY/DBUS env
    _as_user() {
        local uid
        uid="$(id -u "$_reload_user" 2>/dev/null)" || return 1
        local dbus_addr="unix:path=/run/user/${uid}/bus"
        sudo -u "$_reload_user" \
            DISPLAY="${DISPLAY:-:0}" \
            DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
            XDG_RUNTIME_DIR="/run/user/${uid}" \
            HOME="$_reload_home" \
            "$@"
    }

    # Helper: start a detached background process as the real user.
    # setsid entkoppelt den Prozess von der aktuellen Session, nohup
    # verhindert SIGHUP beim Schliessen des Terminals.
    _as_user_detached() {
        local uid
        uid="$(id -u "$_reload_user" 2>/dev/null)" || return 1
        local dbus_addr="unix:path=/run/user/${uid}/bus"
        sudo -u "$_reload_user" \
            DISPLAY="${DISPLAY:-:0}" \
            DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
            XDG_RUNTIME_DIR="/run/user/${uid}" \
            HOME="$_reload_home" \
            setsid nohup "$@" >/dev/null 2>&1 &
    }

    info "Reloading desktop components for user: $_reload_user"

    # foxdock — nach Rebuild komplett neu starten, damit das neue
    # Binary aktiv wird. SIGHUP allein laedt nur die Palette neu,
    # nicht die ausfuehrbare Datei.
    #
    # Ablauf:
    #   1. Laufende Instanz per SIGTERM beenden (sauberer Shutdown)
    #   2. Kurz warten, bis der Prozess wirklich weg ist
    #   3. Neue Instanz als der echte User starten
    #
    # Wenn foxdock vorher nicht lief, wird es trotzdem gestartet --
    # ein Update soll den Dock in jedem Fall in den laufenden Zustand
    # versetzen.
    local foxdock_bin="/usr/local/bin/foxdock"
    if [[ -x "$foxdock_bin" ]]; then
        if _as_user pgrep -x foxdock >/dev/null 2>&1; then
            info "foxdock: stopping running instance"
            _as_user pkill -TERM -x foxdock 2>/dev/null || true
            # Bis zu 2 s auf sauberes Ende warten
            local _i
            for _i in 1 2 3 4; do
                _as_user pgrep -x foxdock >/dev/null 2>&1 || break
                sleep 0.5
            done
            # Falls SIGTERM nicht gereicht hat: hart beenden
            if _as_user pgrep -x foxdock >/dev/null 2>&1; then
                warn "foxdock: SIGTERM ignored — sending SIGKILL"
                _as_user pkill -KILL -x foxdock 2>/dev/null || true
                sleep 0.3
            fi
        fi

        # Neue Instanz starten — detached, damit sie den Update-Prozess
        # ueberlebt.
        info "foxdock: starting new instance"
        _as_user_detached "$foxdock_bin"
        sleep 1

        if _as_user pgrep -x foxdock >/dev/null 2>&1; then
            ok "foxdock: restarted"
        else
            warn "foxdock: failed to start — check DISPLAY/permissions"
        fi
    else
        warn "foxdock binary not found at $foxdock_bin — skipping restart"
    fi

    # xsettingsd — SIGHUP broadcasts GTK settings to all running GTK apps
    if _as_user pkill -HUP -x xsettingsd 2>/dev/null; then
        ok "xsettingsd: settings broadcast"
    fi

    # dunst — SIGUSR2 reloads config
    if _as_user pkill -USR2 -x dunst 2>/dev/null; then
        ok "dunst: config reloaded"
    fi

    # i3 — reload config in-place (no restart, keybindings + bar update)
    if _as_user i3-msg reload 2>/dev/null; then
        ok "i3: config reloaded"
    fi

    # picom — restart (no reload signal)
    if _as_user pkill -x picom 2>/dev/null; then
        sleep 0.5
        _as_user picom --daemon 2>/dev/null &
        ok "picom: restarted"
    fi

    # polybar — kill all instances, re-launch via the user's launch script
    if _as_user pkill -x polybar 2>/dev/null; then
        sleep 0.3
        local launch_script="$_reload_home/.config/polybar/launch.sh"
        if [[ -x "$launch_script" ]]; then
            _as_user bash "$launch_script" &
            ok "polybar: restarted via launch.sh"
        else
            ok "polybar: stopped (launch.sh not found — start manually)"
        fi
    fi

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
