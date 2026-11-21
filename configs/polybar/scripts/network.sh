#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Polybar Network Status Script
#  Path: ~/.config/polybar/scripts/network.sh
# ============================================================

# Aktive Standard-Schnittstelle über Routing ermitteln
DEFAULT_IFACE=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')

if [[ -z "$DEFAULT_IFACE" ]]; then
    echo "󰤭 offline"
    exit 0
fi

# WLAN?
if [[ -d "/sys/class/net/$DEFAULT_IFACE/wireless" || \
      -d "/sys/class/net/$DEFAULT_IFACE/phy80211" ]]; then
    SSID=""

    if command -v iw &>/dev/null; then
        SSID=$(iw dev "$DEFAULT_IFACE" link 2>/dev/null \
            | grep 'SSID:' | sed 's/^[ \t]*SSID: //')
    fi

    if [[ -z "$SSID" ]] && command -v nmcli &>/dev/null; then
        SSID=$(LC_ALL=C nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null \
            | grep '^yes:' | cut -d: -f2)
    fi

    if [[ -z "$SSID" ]] && command -v iwgetid &>/dev/null; then
        SSID=$(iwgetid -r "$DEFAULT_IFACE" 2>/dev/null)
    fi

    [[ -z "$SSID" ]] && SSID="WLAN"
    echo "󰤨 $SSID"
    exit 0
fi

# LAN / Ethernet
echo "󰌘 LAN"
