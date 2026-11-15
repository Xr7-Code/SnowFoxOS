#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — DNS + DNS-over-TLS bootstrap
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Runs at the very top of install.sh, BEFORE any apt install.
#  Reason: without a working resolver + DoT, apt-get calls in the
#  middle of the installer hang silently. Configuring resolved
#  here guarantees a stable DNS path for the whole installation.
#
#  Idempotent. Safe in chroot (only `enable`, no `restart`).
# ============================================================

# Source-guard: safe to source repeatedly. The if-block form
# keeps shellcheck happy (SC2317: no unreachable `return 0`).
if [[ -n "${_SNOWFOX_DNS_SETUP_LOADED:-}" ]]; then
    return 0 2>/dev/null
fi
_SNOWFOX_DNS_SETUP_LOADED=1

# ── DoT config file ────────────────────────────────────────
# Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) with strict TLS.
# Strict mode: resolved FAILS rather than falling back to cleartext.
_dns_write_dot_config() {
    install -d -m 0755 /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/snowfox.conf <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=9.9.9.9#dns.quad9.net
DNSSEC=yes
DNSOverTLS=yes
EOF
    chmod 0644 /etc/systemd/resolved.conf.d/snowfox.conf
}

# ── resolv.conf: point to the stub (or fallback) ───────────
_dns_point_resolv_conf() {
    if [[ -e /run/systemd/resolve/stub-resolv.conf ]]; then
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        return 0
    fi
    if [[ -e /run/systemd/resolve/resolv.conf ]]; then
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        return 0
    fi
    # Fallback for the chroot bootstrap: write static nameservers
    # so apt can resolve names. resolved overwrites this on first
    # real start (stub-resolv.conf will exist by then).
    warn "systemd-resolved stub not yet available — writing static /etc/resolv.conf"
    cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF
}

# ── main entry ─────────────────────────────────────────────
configure_dns_and_dot() {
    info "Configuring DNS + DNS-over-TLS (bootstrap before apt)..."

    # 1. dnsmasq off — it conflicts with systemd-resolved
    systemd_safe stop    dnsmasq
    systemd_safe disable dnsmasq
    systemd_safe mask    dnsmasq

    # 2. Ensure systemd-resolved is installed. In the git-clone path
    #    it is normally already pulled in by base_system.sh, but
    #    base_system.sh runs AFTER this function — so we install it
    #    explicitly here. On a fresh Debian 12 system, apt-get
    #    install resolves names via the system default (which works
    #    before we touch /etc/resolv.conf).
    if ! command -v resolvectl >/dev/null 2>&1; then
        info "Installing systemd-resolved (DNS bootstrap)..."
        apt-get update -qq 2>/dev/null || warn "apt-get update failed — resolver may be stale"
        apt-get install -y systemd-resolved \
            || { warn "systemd-resolved install failed — continuing with current DNS"; return 1; }
    fi

    # 3. Write DoT config (strict)
    _dns_write_dot_config

    # 4. Enable (and start, if we are in a live session)
    if require_systemd_session; then
        systemd_safe enable systemd-resolved
        systemd_safe restart systemd-resolved
    else
        systemd_safe enable systemd-resolved
        info "chroot: systemd-resolved enabled (not started)"
    fi

    # 5. Point resolv.conf at the stub (or write fallback)
    _dns_point_resolv_conf

    # 6. Verify name resolution actually works. Non-fatal: the
    #    installer may still succeed on a cached apt index, and we
    #    do not want to abort the whole run over a transient DNS
    #    hiccup.
    if timeout 10 bash -c 'exec 3<>/dev/tcp/deb.debian.org/80' 2>/dev/null; then
        success "DNS + DoT configured (Cloudflare + Quad9, strict TLS)"
        return 0
    fi

    warn "DNS resolution not yet working — apt may fail until network is up"
    return 0
}