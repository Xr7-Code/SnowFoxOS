#!/bin/bash
# ============================================================
#  SnowFoxOS v3.4 — Polybar Bluetooth Status & Toggle
#  Colors: neutral grey base · purple accent only
# ============================================================

COLOR_ACCENT="%{F#9966cc}"   # purple — connected
COLOR_DIM="%{F#888888}"      # grey   — on but idle
COLOR_MUTED="%{F#4a4a4a}"    # dark grey — off
RESET="%{F-}"

# ── Toggle (bar click) ───────────────────────────────────────
if [[ "$1" == "toggle" ]]; then
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        bluetoothctl power off &>/dev/null || rfkill block bluetooth &>/dev/null
    else
        rfkill unblock bluetooth &>/dev/null
        bluetoothctl power on &>/dev/null
    fi
    exit 0
fi

# ── Status display ───────────────────────────────────────────
IS_POWERED=$(bluetoothctl show 2>/dev/null | grep "Powered: yes")

if [[ -z "$IS_POWERED" ]]; then
    echo "${COLOR_MUTED}󰂲 off${RESET}"
    exit 0
fi

DEV=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)

if [[ -n "$DEV" ]]; then
    echo "${COLOR_ACCENT}󰂱${RESET} $DEV"
else
    echo "${COLOR_DIM}󰂯${RESET} on"
fi
