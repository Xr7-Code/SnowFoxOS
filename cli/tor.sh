#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Tor (Transparent Proxy)
#  Routes all network traffic through Tor via iptables.
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - Atomic iptables loading via iptables-restore (no clear-net window)
#   - IPv4 OUTPUT default policy DROP; IPv6 OUTPUT default policy DROP
#   - DNS configured *after* iptables are in place and Tor is up
#   - Kill-switch survives Tor crash (rules stay, default DROP)
#   - Robust Tor UID detection via systemctl + /proc
#   - No silent torsocks fallback: curl --socks5-hostname is mandatory
#   - _tor_port_open restricted to 127.0.0.1
#   - Restart rolls back to safe state on failure
#   - Controlled PATH, absolute binary paths
#   - return instead of exit in library functions
# ============================================================

# ─── Controlled environment ─────────────────────────────────
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

# ─── Constants ──────────────────────────────────────────────
readonly TOR_TRANS_PORT="9040"
readonly TOR_DNS_PORT="5353"
readonly TOR_SOCKS_PORT="9050"
readonly TOR_CONFIG_DIR="/etc/tor"
readonly TORRC="${TOR_CONFIG_DIR}/torrc"
readonly TOR_SERVICE="tor"
readonly SNOWFOX_CONFIG_DIR="${HOME}/.config/snowfox"
readonly TOR_MODE_FILE="${SNOWFOX_CONFIG_DIR}/tor-mode"
readonly RESOLV_BAK="/etc/resolv.conf.snowfox-bak"
readonly IPTABLES_SAVE="/etc/iptables.snowfox-tor.rules"
readonly IPTABLES_SAVE_IP6="/etc/ip6tables.snowfox-tor.rules"
readonly IPTABLES_APPLY="/etc/iptables.snowfox-tor.apply"
readonly IPTABLES_APPLY_IP6="/etc/ip6tables.snowfox-tor.apply"

# ─── Binary paths ───────────────────────────────────────────
readonly IPTABLES_BIN="/usr/sbin/iptables"
readonly IP6TABLES_BIN="/usr/sbin/ip6tables"
readonly IPTABLES_RESTORE_BIN="/usr/sbin/iptables-restore"
readonly IP6TABLES_RESTORE_BIN="/usr/sbin/ip6tables-restore"
readonly IPTABLES_SAVE_BIN="/usr/sbin/iptables-save"
readonly IP6TABLES_SAVE_BIN="/usr/sbin/ip6tables-save"
readonly SYSCTL_BIN="/usr/sbin/sysctl"
readonly SYSTEMCTL_BIN="/usr/bin/systemctl"
readonly ID_BIN="/usr/bin/id"
readonly CAT_BIN="/usr/bin/cat"
readonly GREP_BIN="/usr/bin/grep"
readonly SED_BIN="/usr/bin/sed"
readonly AWK_BIN="/usr/bin/awk"
readonly SLEEP_BIN="/usr/bin/sleep"
readonly CURL_BIN="/usr/bin/curl"
readonly SS_BIN="/usr/sbin/ss"
readonly CHATTR_BIN="/usr/bin/chattr"
readonly TEE_BIN="/usr/bin/tee"
readonly CP_BIN="/usr/bin/cp"
readonly MKDIR_BIN="/usr/bin/mkdir"
readonly CHMOD_BIN="/usr/bin/chmod"
readonly RM_BIN="/usr/bin/rm"
readonly MV_BIN="/usr/bin/mv"
readonly NC_BIN="/usr/bin/nc"

# Fallbacks for merged-usr / minimal images
[[ -x "$IPTABLES_BIN" ]]         || IPTABLES_BIN="/sbin/iptables"
[[ -x "$IP6TABLES_BIN" ]]        || IP6TABLES_BIN="/sbin/ip6tables"
[[ -x "$IPTABLES_RESTORE_BIN" ]] || IPTABLES_RESTORE_BIN="/sbin/iptables-restore"
[[ -x "$IP6TABLES_RESTORE_BIN" ]]|| IP6TABLES_RESTORE_BIN="/sbin/ip6tables-restore"
[[ -x "$IPTABLES_SAVE_BIN" ]]    || IPTABLES_SAVE_BIN="/sbin/iptables-save"
[[ -x "$IP6TABLES_SAVE_BIN" ]]   || IP6TABLES_SAVE_BIN="/sbin/ip6tables-save"
[[ -x "$SYSCTL_BIN" ]]           || SYSCTL_BIN="/sbin/sysctl"
[[ -x "$SS_BIN" ]]               || SS_BIN="/bin/ss"
[[ -x "$NC_BIN" ]]               || NC_BIN="/bin/nc"

# ============================================================
#  Helpers
# ============================================================

# ─── Tor UID (robust: systemctl -> /proc -> name lookup) ────
_tor_get_uid() {
    local pid uid

    # 1) Ask systemd for the main PID of the tor service
    pid=$("$SYSTEMCTL_BIN" show -p MainPID --value "$TOR_SERVICE" 2>/dev/null)
    if [[ -n "$pid" && "$pid" != "0" && -d "/proc/$pid" ]]; then
        uid=$(stat -c '%u' "/proc/$pid" 2>/dev/null)
        if [[ -n "$uid" && "$uid" != "0" ]]; then
            printf '%s\n' "$uid"
            return 0
        fi
    fi

    # 2) Name-based fallback
    uid=$("$ID_BIN" -ur debian-tor 2>/dev/null) \
        || uid=$("$ID_BIN" -ur tor 2>/dev/null) \
        || uid=""
    if [[ -n "$uid" ]]; then
        printf '%s\n' "$uid"
        return 0
    fi

    return 1
}

# ─── Dependencies ───────────────────────────────────────────
_tor_check_deps() {
    local missing=()
    local deps=(tor iptables ip6tables curl)

    local cmd
    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    # ss and nc are only needed for port checks
    if ! command -v ss &>/dev/null && ! command -v nc &>/dev/null; then
        missing+=("iproute2")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing[*]}"
        info "Install with: sudo apt-get install -y ${missing[*]}"
        return 1
    fi
    return 0
}

# ─── Service running? ───────────────────────────────────────
_tor_service_running() {
    "$SYSTEMCTL_BIN" is-active --quiet "$TOR_SERVICE" 2>/dev/null
}

# ─── Port open on loopback only ─────────────────────────────
_tor_port_open() {
    local port="$1"
    # Prefer ss with a strict loopback match
    if [[ -x "$SS_BIN" ]]; then
        "$SS_BIN" -tln 2>/dev/null | "$GREP_BIN" -qE "127\.0\.0\.1:${port}[[:space:]]" && return 0
        "$SS_BIN" -uln 2>/dev/null | "$GREP_BIN" -qE "127\.0\.0\.1:${port}[[:space:]]" && return 0
    fi
    # Fallback: TCP connect test (only proves TCP, not UDP)
    if [[ -x "$NC_BIN" ]]; then
        "$NC_BIN" -z 127.0.0.1 "$port" 2>/dev/null && return 0
    fi
    return 1
}

# ─── IPv6 status ────────────────────────────────────────────
_tor_ipv6_disabled() {
    [[ "$("$CAT_BIN" /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]]
}

# ─── DNS via Tor? ───────────────────────────────────────────
_tor_dns_via_tor() {
    "$GREP_BIN" -q "^nameserver 127.0.0.1$" /etc/resolv.conf 2>/dev/null
}

# ─── resolv.conf backup ─────────────────────────────────────
_tor_backup_resolv() {
    if [[ ! -f "$RESOLV_BAK" && -f /etc/resolv.conf ]]; then
        sudo "$CP_BIN" /etc/resolv.conf "$RESOLV_BAK"
    fi
}

# ─── resolv.conf restore ────────────────────────────────────
_tor_restore_resolv() {
    info "Restoring system DNS..."
    sudo "$CHATTR_BIN" -i /etc/resolv.conf 2>/dev/null || true

    if [[ -f "$RESOLV_BAK" ]]; then
        sudo "$CP_BIN" "$RESOLV_BAK" /etc/resolv.conf
        ok "DNS restored from backup"
    else
        printf "nameserver 1.1.1.1\nnameserver 9.9.9.9\n" | sudo "$TEE_BIN" /etc/resolv.conf > /dev/null
        ok "DNS reset to defaults"
    fi

    if command -v NetworkManager &>/dev/null; then
        sudo "$SYSTEMCTL_BIN" restart NetworkManager 2>/dev/null || true
    fi
}

# ─── torrc ──────────────────────────────────────────────────
_tor_configure_torrc() {
    info "Configuring Tor transparent proxy..."

    if [[ ! -f "${TORRC}.snowfox-bak" && -f "$TORRC" ]]; then
        sudo "$CP_BIN" "$TORRC" "${TORRC}.snowfox-bak"
    fi

    sudo "$TEE_BIN" "$TORRC" > /dev/null << 'EOF'
## SnowFoxOS — Tor Transparent Proxy Configuration

SocksPort 127.0.0.1:9050
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:5353

## Automap .onion addresses
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1
AutomapHostsSuffixes .exit,.onion

## Logging
Log notice file /var/log/tor/notices.log

## Safety
SafeSocks 1
TestSocks 1

## Performance
CircuitBuildTimeout 60
NumEntryGuards 4
EOF

    sudo chown debian-tor:debian-tor "$TORRC" 2>/dev/null \
        || sudo chown tor:tor "$TORRC" 2>/dev/null || true
    sudo "$CHMOD_BIN" 644 "$TORRC"
    ok "Tor configured (TransPort: ${TOR_TRANS_PORT}, DNSPort: ${TOR_DNS_PORT})"
}

# ─── Start Tor ──────────────────────────────────────────────
_tor_start_service() {
    if _tor_service_running; then
        info "Tor service already running"
    else
        info "Starting Tor service..."
        sudo "$SYSTEMCTL_BIN" restart "$TOR_SERVICE" 2>/dev/null || {
            err "systemd could not start $TOR_SERVICE"
            return 1
        }
    fi

    local i=0
    while [[ $i -lt 30 ]]; do
        if _tor_port_open "$TOR_TRANS_PORT" && _tor_port_open "$TOR_DNS_PORT"; then
            ok "Tor ports are ready"
            return 0
        fi
        "$SLEEP_BIN" 1
        i=$((i + 1))
    done

    err "Tor failed to open ports within 30 seconds"
    return 1
}

# ─── Build atomic iptables ruleset (IPv4) ───────────────────
# Writes $IPTABLES_APPLY. Caller loads it with iptables-restore.
_tor_build_iptables_v4() {
    local tor_uid="$1"
    local tmp
    tmp=$(mktemp /tmp/snowfox-tor-v4.XXXXXX) || return 1

    cat > "$tmp" <<EOF
*nat
:OUTPUT ACCEPT [0:0]
-A OUTPUT -m owner --uid-owner ${tor_uid} -j RETURN
-A OUTPUT -d 127.0.0.0/8 -j RETURN
-A OUTPUT -d 192.168.0.0/16 -j RETURN
-A OUTPUT -d 10.0.0.0/8 -j RETURN
-A OUTPUT -d 172.16.0.0/12 -j RETURN
-A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports ${TOR_DNS_PORT}
-A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports ${TOR_DNS_PORT}
-A OUTPUT -p tcp --syn -j REDIRECT --to-ports ${TOR_TRANS_PORT}
COMMIT

*filter
:OUTPUT DROP [0:0]
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -d 127.0.0.0/8 -j ACCEPT
-A OUTPUT -d 192.168.0.0/16 -j ACCEPT
-A OUTPUT -d 10.0.0.0/8 -j ACCEPT
-A OUTPUT -d 172.16.0.0/12 -j ACCEPT
-A OUTPUT -m owner --uid-owner ${tor_uid} -j ACCEPT
-A OUTPUT -p tcp --dport ${TOR_SOCKS_PORT} -j ACCEPT
-A OUTPUT -p tcp --dport ${TOR_TRANS_PORT} -j ACCEPT
-A OUTPUT -p udp --dport ${TOR_DNS_PORT} -j ACCEPT
COMMIT
EOF

    sudo "$MV_BIN" "$tmp" "$IPTABLES_APPLY"
    sudo "$CHMOD_BIN" 600 "$IPTABLES_APPLY"
    return 0
}

# ─── Build atomic iptables ruleset (IPv6) ───────────────────
_tor_build_iptables_v6() {
    local tor_uid="$1"
    local tmp
    tmp=$(mktemp /tmp/snowfox-tor-v6.XXXXXX) || return 1

    cat > "$tmp" <<EOF
*filter
:OUTPUT DROP [0:0]
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -d ::1/128 -j ACCEPT
-A OUTPUT -m owner --uid-owner ${tor_uid} -j ACCEPT
COMMIT
EOF

    sudo "$MV_BIN" "$tmp" "$IPTABLES_APPLY_IP6"
    sudo "$CHMOD_BIN" 600 "$IPTABLES_APPLY_IP6"
    return 0
}

# ─── Apply rules atomically ─────────────────────────────────
_tor_apply_iptables() {
    local tor_uid
    tor_uid=$(_tor_get_uid) || {
        err "Could not determine Tor user UID"
        return 1
    }

    info "Applying atomic iptables rules (Tor UID: $tor_uid)..."

    # Save current state before touching anything
    sudo "$IPTABLES_SAVE_BIN" | sudo "$TEE_BIN" "$IPTABLES_SAVE" > /dev/null
    sudo "$IP6TABLES_SAVE_BIN" | sudo "$TEE_BIN" "$IPTABLES_SAVE_IP6" > /dev/null 2>&1 || true

    # Build both rulesets first (no live changes yet)
    _tor_build_iptables_v4 "$tor_uid" || { err "Failed to build IPv4 ruleset"; return 1; }
    _tor_build_iptables_v6 "$tor_uid" || { err "Failed to build IPv6 ruleset"; return 1; }

    # Load atomically — this is the only moment rules become live
    if ! sudo "$IPTABLES_RESTORE_BIN" < "$IPTABLES_APPLY"; then
        err "iptables-restore failed — rolling back"
        _tor_rollback_rules
        return 1
    fi

    if ! sudo "$IP6TABLES_RESTORE_BIN" < "$IPTABLES_APPLY_IP6"; then
        err "ip6tables-restore failed — rolling back"
        _tor_rollback_rules
        return 1
    fi

    ok "iptables rules applied atomically (IPv4 OUTPUT DROP, IPv6 OUTPUT DROP)"
    return 0
}

# ─── Rollback to saved rules ────────────────────────────────
_tor_rollback_rules() {
    info "Rolling back iptables rules..."
    if [[ -f "$IPTABLES_SAVE" ]]; then
        sudo "$IPTABLES_RESTORE_BIN" < "$IPTABLES_SAVE" 2>/dev/null || true
    fi
    if [[ -f "$IPTABLES_SAVE_IP6" ]]; then
        sudo "$IP6TABLES_RESTORE_BIN" < "$IPTABLES_SAVE_IP6" 2>/dev/null || true
    fi
}

# ─── Remove rules (restore saved state) ─────────────────────
_tor_remove_iptables() {
    info "Removing iptables rules..."

    _tor_rollback_rules

    # Clean up apply files
    sudo "$RM_BIN" -f "$IPTABLES_APPLY" "$IPTABLES_APPLY_IP6" 2>/dev/null || true

    ok "iptables rules removed"
}

# ─── DNS → Tor (after iptables are live and Tor is up) ──────
_tor_configure_dns() {
    _tor_backup_resolv

    info "Pointing DNS to Tor..."
    sudo "$CHATTR_BIN" -i /etc/resolv.conf 2>/dev/null || true
    printf "nameserver 127.0.0.1\n" | sudo "$TEE_BIN" /etc/resolv.conf > /dev/null
    if sudo "$CHATTR_BIN" +i /etc/resolv.conf 2>/dev/null; then
        ok "DNS set to 127.0.0.1 (locked)"
    else
        warn "chattr +i failed — resolv.conf is writable (NetworkManager may overwrite)"
        ok "DNS set to 127.0.0.1"
    fi
}

# ─── IPv6: block via ip6tables only, do not disable stack ───
# Disabling the stack kernel-wide is unreliable and can leave
# processes in a state where AF_INET6 sockets behave inconsistently.
# The ip6tables DROP policy is the authoritative block.
_tor_disable_ipv6() {
    if _tor_ipv6_disabled; then
        info "IPv6 stack already disabled at kernel level (rules still authoritative)"
    else
        info "IPv6 stack left enabled; ip6tables OUTPUT policy is DROP"
    fi
    return 0
}

# ─── Re-enable IPv6 (only if we disabled it) ────────────────
_tor_enable_ipv6() {
    if _tor_ipv6_disabled; then
        info "Re-enabling IPv6..."
        sudo "$SYSCTL_BIN" -w net.ipv6.conf.all.disable_ipv6=0 &>/dev/null
        sudo "$SYSCTL_BIN" -w net.ipv6.conf.default.disable_ipv6=0 &>/dev/null
        ok "IPv6 re-enabled"
    fi
}

# ─── Connection test via mandatory SOCKS5 ───────────────────
_tor_test_connection() {
    info "Testing Tor connection via SOCKS5..."
    "$SLEEP_BIN" 2

    local resp tor_ip
    resp=$("$CURL_BIN" -s --max-time 15 \
        --socks5-hostname "127.0.0.1:${TOR_SOCKS_PORT}" \
        https://check.torproject.org/api/ip 2>/dev/null)

    if [[ -z "$resp" ]]; then
        err "Tor connection test failed (no response via SOCKS5)"
        info "Manual test: curl --socks5-hostname 127.0.0.1:${TOR_SOCKS_PORT} https://check.torproject.org/api/ip"
        return 1
    fi

    tor_ip=$(printf '%s' "$resp" | "$GREP_BIN" -oE '"IP":"[0-9a-fA-F.:]+"' | "$SED_BIN" 's/"IP":"//; s/"//')

    if [[ -n "$tor_ip" ]] && printf '%s' "$resp" | "$GREP_BIN" -q '"IsTor":true'; then
        ok "Tor is working (Exit IP: $tor_ip)"
        return 0
    fi

    err "Tor connection test failed (IsTor not true)"
    return 1
}

# ============================================================
#  Enable / Disable / Status
# ============================================================

_tor_enable() {
    fox "Enabling Tor transparent proxy..."

    _tor_check_deps || return 1

    # 1) Configure and start Tor first (it must be able to reach the network)
    _tor_configure_torrc || return 1
    _tor_start_service || return 1

    # 2) Apply atomic kill-switch (IPv4 + IPv6 OUTPUT DROP)
    _tor_apply_iptables || return 1

    # 3) Point DNS at Tor DNSPort only after the kill-switch is live
    _tor_configure_dns || { _tor_rollback_rules; return 1; }

    # 4) IPv6 is blocked by ip6tables; stack state is informational
    _tor_disable_ipv6

    # 5) Verify via SOCKS5 (mandatory, no fallback)
    if ! _tor_test_connection; then
        err "Tor verification failed — disabling to avoid a false sense of security"
        _tor_disable
        return 1
    fi

    mkdir -p "$SNOWFOX_CONFIG_DIR"
    printf "tor\n" > "$TOR_MODE_FILE"
    "$CHMOD_BIN" 600 "$TOR_MODE_FILE"

    echo ""
    divider
    ok "Tor mode enabled — all traffic routed through Tor"
    echo ""
    info "SOCKS5:    127.0.0.1:${TOR_SOCKS_PORT}"
    info "TransPort: 127.0.0.1:${TOR_TRANS_PORT}"
    info "DNSPort:   127.0.0.1:${TOR_DNS_PORT}"
    echo ""
    warn "Network is fail-closed: if Tor stops, IPv4/IPv6 OUTPUT stays DROP"
    echo ""
}

_tor_disable() {
    fox "Disabling Tor mode..."

    _tor_remove_iptables
    _tor_restore_resolv
    _tor_enable_ipv6

    "$RM_BIN" -f "$TOR_MODE_FILE"

    echo ""
    divider
    ok "Tor mode disabled — normal network restored"
    echo ""
    info "Tor service still running: ${TOR_SERVICE}"
    info "Stop with: sudo systemctl stop ${TOR_SERVICE}"
    echo ""
}

_tor_status() {
    header "Tor Status"

    if [[ ! -f "$TOR_MODE_FILE" ]]; then
        row "Tor mode" "inactive" "$DGRAY"
        echo ""
        info "Enable: snowfox tor on"
        echo ""
        return
    fi

    if _tor_service_running; then
        row "Tor service" "running" "$GREEN"
    else
        row "Tor service" "stopped" "$RED"
    fi

    if _tor_port_open "$TOR_TRANS_PORT"; then
        row "TransPort" "127.0.0.1:${TOR_TRANS_PORT}" "$GREEN"
    else
        row "TransPort" "not reachable" "$RED"
    fi

    if _tor_port_open "$TOR_DNS_PORT"; then
        row "DNSPort" "127.0.0.1:${TOR_DNS_PORT}" "$GREEN"
    else
        row "DNSPort" "not reachable" "$RED"
    fi

    if _tor_dns_via_tor; then
        row "DNS" "via Tor" "$GREEN"
    else
        row "DNS" "standard" "$ORANGE"
    fi

    # Verify the kill-switch is actually in place
    local v4_policy v6_policy
    v4_policy=$(sudo "$IPTABLES_BIN" -S OUTPUT 2>/dev/null | "$GREP_BIN" '^-P OUTPUT' | "$AWK_BIN" '{print $3}')
    v6_policy=$(sudo "$IP6TABLES_BIN" -S OUTPUT 2>/dev/null | "$GREP_BIN" '^-P OUTPUT' | "$AWK_BIN" '{print $3}')

    if [[ "$v4_policy" == "DROP" ]]; then
        row "IPv4 kill-switch" "active (OUTPUT DROP)" "$GREEN"
    else
        row "IPv4 kill-switch" "NOT active (policy: ${v4_policy:-unknown})" "$RED"
    fi

    if [[ "$v6_policy" == "DROP" ]]; then
        row "IPv6 kill-switch" "active (OUTPUT DROP)" "$GREEN"
    else
        row "IPv6 kill-switch" "NOT active (policy: ${v6_policy:-unknown})" "$RED"
    fi

    echo ""
    info "Checking external IP via SOCKS5..."

    local resp tor_ip
    resp=$("$CURL_BIN" -s --max-time 15 \
        --socks5-hostname "127.0.0.1:${TOR_SOCKS_PORT}" \
        https://check.torproject.org/api/ip 2>/dev/null)

    if [[ -n "$resp" ]]; then
        tor_ip=$(printf '%s' "$resp" | "$GREP_BIN" -oE '"IP":"[0-9a-fA-F.:]+"' | "$SED_BIN" 's/"IP":"//; s/"//')
        if printf '%s' "$resp" | "$GREP_BIN" -q '"IsTor":true'; then
            row "Exit IP" "$tor_ip (verified)" "$GREEN"
        else
            row "Exit IP" "$tor_ip (NOT Tor)" "$RED"
        fi
    else
        row "Exit IP" "not reachable" "$RED"
    fi
    echo ""
}

# ============================================================
#  Main command
# ============================================================
cmd_tor() {
    case "${1:-}" in
        on|enable)
            _tor_enable
            return $?
            ;;
        off|disable)
            _tor_disable
            return $?
            ;;
        status|"")
            _tor_status
            return $?
            ;;
        restart)
            _tor_disable || return 1
            "$SLEEP_BIN" 2
            _tor_enable
            return $?
            ;;
        -h|--help|help)
            header "snowfox tor"
            echo ""
            row "snowfox tor on"      "Enable transparent Tor proxy"
            row "snowfox tor off"     "Disable Tor mode"
            row "snowfox tor status"  "Show current status"
            row "snowfox tor restart" "Restart Tor"
            echo ""
            divider
            info "Tor routes all TCP traffic and DNS queries through the Tor network."
            info "When enabled, non-Tor traffic is blocked (fail-closed)."
            echo ""
            return 0
            ;;
        *)
            err "Unknown tor command: $1"
            return 1
            ;;
    esac
}
