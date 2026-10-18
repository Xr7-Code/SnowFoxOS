#!/bin/bash
# ============================================================
#  SnowFoxOS — Polybar Bluetooth Status & Toggle Script
#  Path: ~/.config/polybar/scripts/bluetooth.sh
#  Colors are palette tokens — rendered from
#  ~/.config/snowfox/palette.conf (snowfox theme color)
# ============================================================

COLOR_CYAN="%{F#89dceb}"
COLOR_GREEN="%{F#89c98a}"
COLOR_DIM="%{F#6e6a8a}"
RESET="%{F-}"

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

# ── 2. Status display (called every X seconds by Polybar) ────

# Check if Bluetooth is powered on
IS_POWERED=$(bluetoothctl show 2>/dev/null | grep "Powered: yes")

if [[ -z "$IS_POWERED" ]]; then
    # Always visible, even when service/radio is off
    echo "${COLOR_DIM}󰂲 off${RESET}"
    exit 0
fi

# Get connected device
DEV=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)

if [[ -n "$DEV" ]]; then
    # Connected (green icon + name)
    echo "${COLOR_GREEN}󰂱${RESET} $DEV"
else
    # Powered on but not connected (cyan icon + "on")
    echo "${COLOR_CYAN}󰂯${RESET} on"
fi
