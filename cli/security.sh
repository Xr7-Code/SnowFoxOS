#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Security (Network Audit)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - Absolute binary paths / controlled PATH (no PATH hijacking)
#   - Empirical root/capability detection (no EUID guessing)
#   - Robust ss -tunpH parsing (named fields, all processes)
#   - Fail-loud instead of fail-silent on ss errors
#   - Terminal escape sanitizing on process names
#   - No watch(1) subshell (no sh -c, no $SHELL, no $TERM hijack)
#   - timeouts on ss to survive socket floods
#   - return instead of exit in library functions
#   - live mode warns about missing root, same as snapshot
# ============================================================

# ─── Controlled environment ─────────────────────────────────
# Never trust the caller's PATH (sudo without secure_path, ~/.bashrc, ...)
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset SHELL 2>/dev/null || true
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

readonly SS_BIN="/usr/sbin/ss"
readonly TIMEOUT_BIN="/usr/bin/timeout"
readonly AWK_BIN="/usr/bin/awk"
readonly GREP_BIN="/usr/bin/grep"
readonly TR_BIN="/usr/bin/tr"
readonly SED_BIN="/usr/bin/sed"
readonly CAT_BIN="/usr/bin/cat"
readonly DATE_BIN="/usr/bin/date"
readonly SLEEP_BIN="/usr/bin/sleep"
readonly CLEAR_BIN="/usr/bin/clear"
readonly STTY_BIN="/usr/bin/stty"

# Fallback if ss lives in /bin (merged-usr is standard on Debian 12,
# but be defensive)
if [[ ! -x "$SS_BIN" && -x /bin/ss ]]; then
    SS_BIN="/bin/ss"
fi

readonly SS_TIMEOUT=10

# ============================================================
#  snowfox audit — Active network connections
# ============================================================
cmd_audit() {
    case "${1:-}" in
        live|ongoing|l)
            _audit_live
            return $?
            ;;
        ""|once|snapshot)
            _audit_snapshot
            return $?
            ;;
        -h|--help|help)
            _audit_usage
            return 0
            ;;
        *)
            err "Unknown audit mode: $1"
            _audit_usage
            return 1
            ;;
    esac
}

_audit_usage() {
    cat <<'EOF'
Usage: snowfox audit [mode]

Modes:
  (none) | once | snapshot   One-shot snapshot of active connections
  live | ongoing | l         Live refresh (Ctrl+C to exit)
  help                       Show this help
EOF
}

# ─── Preflight: ss present and usable? ──────────────────────
_audit_preflight() {
    if [[ ! -x "$SS_BIN" ]]; then
        err "ss not found at $SS_BIN — install iproute2"
        return 1
    fi
    if ! "$SS_BIN" -h >/dev/null 2>&1; then
        err "ss is not executable or broken: $SS_BIN"
        return 1
    fi
    return 0
}

# ─── Do we actually see process info? (empirical, not EUID) ─
# Returns 0 if at least one socket exposes users:(...), 1 otherwise.
_audit_can_see_processes() {
    local out
    out=$("$TIMEOUT_BIN" "$SS_TIMEOUT" "$SS_BIN" -tunpH 2>/dev/null) || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out" | "$GREP_BIN" -q 'users:('
}

# ─── One-shot snapshot ───────────────────────────────────────
_audit_snapshot() {
    header "Network Audit"

    _audit_preflight || return 1

    if ! _audit_can_see_processes; then
        info "Process names are not visible (need root or CAP_NET_ADMIN)."
        info "For full output: sudo snowfox audit"
        echo ""
    fi

    divider
    printf "  ${BOLD}%-24s %-6s %s${RESET}\n" "Process" "Proto" "Destination"
    divider

    local count=0
    local ss_out
    # Single capture, then parse — avoids re-running ss per line
    ss_out=$("$TIMEOUT_BIN" "$SS_TIMEOUT" "$SS_BIN" -tunpH 2>/dev/null)
    local ss_rc=$?

    if [[ $ss_rc -ne 0 ]]; then
        divider
        err "ss failed (exit $ss_rc) — cannot audit connections."
        err "Try: sudo snowfox audit"
        echo ""
        return 1
    fi

    local netid state recvq sendq local_addr peer_addr proc_field
    local proto remote proc ip ip_color

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # ss -tunpH field layout:
        #   Netid State Recv-Q Send-Q Local Peer Process
        # Process may be empty (no -p permission).
        read -r netid state recvq sendq local_addr peer_addr proc_field <<< "$line"

        proto="$netid"
        remote="$peer_addr"

        # Skip sockets with no peer (listening) or wildcard peer.
        [[ -z "$remote" ]] && continue
        [[ "$remote" == "*" || "$remote" == "*:*" ]] && continue
        [[ "$remote" == "0.0.0.0:*" ]] && continue
        [[ "$remote" == "[::]:*" ]] && continue

        # Extract process name — all users:((...)) entries, not just first.
        # Format: users:(("name",pid=...,fd=...),("name2",pid=...,fd=...))
        proc=""
        if [[ -n "$proc_field" ]]; then
            # Sanitize to printable ASCII first (prevents terminal escapes)
            proc_field=$("$TR_BIN" -cd '[:print:]' <<< "$proc_field")
            # Grab every quoted name after users:((
            proc=$("$GREP_BIN" -oP 'users:\(\(\("\K[^"]+' <<< "$proc_field" 2>/dev/null \
                   | "$AWK_BIN" '!seen[$0]++' \
                   | paste -sd ',' - 2>/dev/null)
        fi
        [[ -z "$proc" ]] && proc="unknown"

        # Strip port / brackets from peer address to get bare IP.
        ip=$(echo "$remote" | "$SED_BIN" -E 's/^\[([^]]+)\]:[0-9]+$/\1/; s/^([^:]+):[0-9]+$/\1/')

        # Color code: local networks gray, external orange.
        if echo "$ip" | "$GREP_BIN" -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.|::1|fe80:|fc|fd)'; then
            ip_color="${GRAY}"
        else
            ip_color="${ORANGE}"
        fi

        printf "  ${CYAN}%-24s${RESET} %-6s ${IP_COLOR_PLACEHOLDER:-$ip_color}%s${RESET}\n" "$proc" "$proto" "$ip"
        count=$((count + 1))
    done <<< "$ss_out"

    divider

    if [[ $count -eq 0 ]]; then
        info "No active connections."
    else
        info "$count active connection(s)."
    fi
    echo ""
    return 0
}

# ─── Live mode (Ctrl+C to exit) ──────────────────────────────
# Replaces watch(1) which runs via sh -c and respects $PATH/$SHELL/$TERM.
_audit_live() {
    _audit_preflight || return 1

    if ! _audit_can_see_processes; then
        info "Process names are not visible (need root or CAP_NET_ADMIN)."
        info "For full output: sudo snowfox audit live"
        echo ""
    fi

    info "Live audit — press Ctrl+C to exit."
    "$SLEEP_BIN" 1

    # Save cursor, enter alternate screen, hide cursor.
    printf '\033[?1049h\033[?25l'
    # Restore on exit (trap covers Ctrl+C and normal return).
    # shellcheck disable=SC2064
    trap 'printf "\033[?25h\033[?1049l"; return 0' INT TERM EXIT

    local ss_out
    while true; do
        # Re-render without a subshell; no eval, no sh -c.
        printf '\033[H\033[2J'
        printf "  ${BOLD}SnowFoxOS Network Audit — live (Ctrl+C to exit)${RESET}\n"
        divider

        ss_out=$("$TIMEOUT_BIN" "$SS_TIMEOUT" "$SS_BIN" -tunpH 2>/dev/null)
        local ss_rc=$?

        if [[ $ss_rc -ne 0 ]]; then
            err "ss failed (exit $ss_rc) — cannot audit."
        elif [[ -z "$ss_out" ]]; then
            info "No active connections."
        else
            printf "  ${BOLD}%-24s %-6s %s${RESET}\n" "Process" "Proto" "Destination"
            divider

            local netid state recvq sendq local_addr peer_addr proc_field
            local proto remote proc ip ip_color
            local live_count=0

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                read -r netid state recvq sendq local_addr peer_addr proc_field <<< "$line"

                proto="$netid"
                remote="$peer_addr"

                [[ -z "$remote" ]] && continue
                [[ "$remote" == "*" || "$remote" == "*:*" ]] && continue
                [[ "$remote" == "0.0.0.0:*" ]] && continue
                [[ "$remote" == "[::]:*" ]] && continue

                proc=""
                if [[ -n "$proc_field" ]]; then
                    proc_field=$("$TR_BIN" -cd '[:print:]' <<< "$proc_field")
                    proc=$("$GREP_BIN" -oP 'users:\(\(\("\K[^"]+' <<< "$proc_field" 2>/dev/null \
                           | "$AWK_BIN" '!seen[$0]++' \
                           | paste -sd ',' - 2>/dev/null)
                fi
                [[ -z "$proc" ]] && proc="unknown"

                ip=$(echo "$remote" | "$SED_BIN" -E 's/^\[([^]]+)\]:[0-9]+$/\1/; s/^([^:]+):[0-9]+$/\1/')

                if echo "$ip" | "$GREP_BIN" -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.|::1|fe80:|fc|fd)'; then
                    ip_color="${GRAY}"
                else
                    ip_color="${ORANGE}"
                fi

                printf "  ${CYAN}%-24s${RESET} %-6s ${ip_color}%s${RESET}\n" "$proc" "$proto" "$ip"
                live_count=$((live_count + 1))
            done <<< "$ss_out"

            divider
            info "$live_count active connection(s)."
        fi

        "$SLEEP_BIN" 2
    done
}
