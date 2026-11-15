#!/usr/bin/env bash
# SnowFoxOS — polybar bluetooth status
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    echo "󰂲"
    exit 0
fi
DEV=$(bluetoothctl devices Connected 2>/dev/null \
    | head -n1 \
    | awk "{\$1=\"\"; \$2=\"\"; print \$0}" \
    | xargs)
if [[ -n "$DEV" ]]; then
    echo "󰂱 $DEV"
else
    echo "󰂯"
fi

