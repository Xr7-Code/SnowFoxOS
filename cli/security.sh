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
readonly SLEEP_BIN="/usr/bin/sleep"

# Debian 12 uses merged-usr; /bin is a symlink to /usr/bin.
# Fallbacks keep this working if the layout ever differs.
[[ -x "$SS_BIN" ]]      || SS_BIN="/bin/ss"
[[ -x "$TIMEOUT_BIN" ]] || TIMEOUT_BIN="/bin/timeout"
[[ -x "$AWK_BIN" ]]     || AWK_BIN="/usr/bin/gawk"
[[ -x "$AWK_BIN" ]]     || AWK_BIN="/bin/awk"
[[ -x "$GREP_BIN" ]]    || GREP_BIN="/bin/grep"
[[ -x "$TR_BIN" ]]      || TR_BIN="/bin/tr"
[[ -x "$SED_BIN" ]]     || SED_BIN="/bin/sed"
[[ -x "$SLEEP_BIN" ]]   || SLEEP_BIN="/bin/sleep"

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

# ─── Parse one ss -tunpH line ───────────────────────────────
# Sets globals: _p_proto _p_remote _p_proc
# Returns 0 if the line represents an active (non-listening) connection,
# 1 if it should be skipped.
_audit_parse_line() {
    local line="$1"
    local netid state recvq sendq local_addr peer_addr proc_field
    local proc ip

    _p_proto=""
    _p_remote=""
    _p_proc=""

    # ss -tunpH field layout:
    #   Netid State Recv-Q Send-Q Local Peer Process
    # Process may be empty (no -p permission).
    read -r netid state recvq sendq local_addr peer_addr proc_field <<< "$line"

    _p_proto="$netid"
    _p_remote="$peer_addr"

    # Skip sockets with no peer (listening) or wildcard peer.
    [[ -z "$_p_remote" ]] && return 1
    [[ "$_p_remote" == "*" || "$_p_remote" == "*:*" ]] && return 1
    [[ "$_p_remote" == "0.0.0.0:*" ]] && return 1
    [[ "$_p_remote" == "[::]:*" ]] && return 1

    # Extract process name — all users:((...)) entries, not just first.
    # Format: users:(("name",pid=...,fd=...),("name2",pid=...,fd=...))
    if [[ -n "$proc_field" ]]; then
        # Sanitize to printable ASCII first (prevents terminal escapes)
        proc_field=$("$TR_BIN" -cd '[:print:]' <<< "$proc_field")
        # Grab every quoted name after users:((
        proc=$("$GREP_BIN" -oP 'users:\(\(\("\K[^"]+' <<< "$proc_field" 2>/dev/null \
               | "$AWK_BIN" '!seen[$0]++' \
               | "$AWK_BIN" 'BEGIN{sep=""} {printf "%s%s", sep, $0; sep=","}')
    fi
    [[ -z "$proc" ]] && proc="unknown"

    _p_proc="$proc"

    # Strip port / brackets from peer address to get bare IP.
    ip=$(printf '%s' "$_p_remote" \
         | "$SED_BIN" -E 's/^\[([^]]+)\]:[0-9]+$/\1/; s/^([^:]+):[0-9]+$/\1/')
    _p_remote="$ip"

    return 0
}

# ─── Classify IP: sets _p_color ─────────────────────────────
_audit_classify_ip() {
    local ip="$1"
    if printf '%s' "$ip" | "$GREP_BIN" -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.|::1|fe80:|fc|fd)'; then
        _p_color="${GRAY}"
    else
        _p_color="${ORANGE}"
    fi
}

# ─── Render one connection row ──────────────────────────────
_audit_render_row() {
    local proc="$1" proto="$2" ip="$3" color="$4"
    printf "  ${CYAN}%-24s${RESET} %-6s ${color}%s${RESET}\n" "$proc" "$proto" "$ip"
}

# ─── Snapshot: shared worker ────────────────────────────────
# Parses $1 (ss output) and prints rows. Sets _p_count.
_audit_render_snapshot_body() {
    local ss_out="$1"
    local line count=0

    _p_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _audit_parse_line "$line" || continue
        _audit_classify_ip "$_p_remote"
        _audit_render_row "$_p_proc" "$_p_proto" "$_p_remote" "$_p_color"
        count=$((count + 1))
    done <<< "$ss_out"

    _p_count=$count
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

    local ss_out ss_rc
    ss_out=$("$TIMEOUT_BIN" "$SS_TIMEOUT" "$SS_BIN" -tunpH 2>/dev/null)
    ss_rc=$?

    if [[ $ss_rc -ne 0 ]]; then
        divider
        err "ss failed (exit $ss_rc) — cannot audit connections."
        err "Try: sudo snowfox audit"
        echo ""
        return 1
    fi

    _audit_render_snapshot_body "$ss_out"

    divider

    if [[ $_p_count -eq 0 ]]; then
        info "No active connections."
    else
        info "$_p_count active connection(s)."
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

    # Restore terminal state on any exit path.
    # Save previous traps so we do not clobber the caller's.
    local _prev_int _prev_term _prev_exit
    _prev_int=$(trap -p INT)
    _prev_term=$(trap -p TERM)
    _prev_exit=$(trap -p EXIT)

    _audit_live_cleanup() {
        printf '\033[?25h\033[?1049l'
    }

    # Enter alternate screen, hide cursor.
    printf '\033[?1049h\033[?25l'
    trap '_audit_live_cleanup; return 0' INT TERM EXIT

    local ss_out ss_rc line
    while true; do
        # Re-render without a subshell; no eval, no sh -c.
        printf '\033[H\033[2J'
        printf "  ${BOLD}SnowFoxOS Network Audit — live (Ctrl+C to exit)${RESET}\n"
        divider
        printf "  ${BOLD}%-24s %-6s %s${RESET}\n" "Process" "Proto" "Destination"
        divider

        ss_out=$("$TIMEOUT_BIN" "$SS_TIMEOUT" "$SS_BIN" -tunpH 2>/dev/null)
        ss_rc=$?

        if [[ $ss_rc -ne 0 ]]; then
            err "ss failed (exit $ss_rc) — cannot audit."
        elif [[ -z "$ss_out" ]]; then
            info "No active connections."
        else
            local live_count=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                _audit_parse_line "$line" || continue
                _audit_classify_ip "$_p_remote"
                _audit_render_row "$_p_proc" "$_p_proto" "$_p_remote" "$_p_color"
                live_count=$((live_count + 1))
            done <<< "$ss_out"

            divider
            info "$live_count active connection(s)."
        fi

        "$SLEEP_BIN" 2
    done

    # Unreachable — the trap returns on INT/TERM.
    # Restore previous traps in case the loop ever exits normally.
    eval "${_prev_int:-trap - INT}"
    eval "${_prev_term:-trap - TERM}"
    eval "${_prev_exit:-trap - EXIT}"
}
