#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Polybar Bluetooth Status & Toggle Script
#  Path: ~/.config/polybar/scripts/bluetooth.sh
# ============================================================

# ── 1. Toggle logic (triggered on bar click) ─────────────────
if [[ "$1" == "toggle" ]]; then
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        bluetoothctl power off &>/dev/null || rfkill block bluetooth &>/dev/null
    else
        rfkill unblock bluetooth &>/dev/null
        bluetoothctl power on &>/dev/null
    fi
    exit 0
fi

# ── 2. Status display ────────────────────────────────────────
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    echo "󰂲 off"
    exit 0
fi

DEV=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)

if [[ -n "$DEV" ]]; then
    echo "󰂱 $DEV"
else
    echo "󰂯 on"
fi
