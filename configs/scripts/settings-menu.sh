#!/usr/bin/env bash
# ============================================================
#   SnowFoxOS v4 — Settings Menu (Rofi)
#   Single entry point for the system menu. Every item is a
#   standalone action; nothing calls back into snowfox CLI
#   except where the CLI is the right tool.
# ============================================================

CHOICE=$(printf "%s\n" \
    "󰸉  Wallpaper" \
    "󰔎  Theme" \
    "󰍹  Display" \
    "󰖩  Network" \
    "󰂯  Bluetooth" \
    "󰌾  Lock" \
    "󰐥  Power" \
    "󰒓  snowfox settings" \
    | rofi -dmenu \
        -p "󰒓  Settings" \
        -theme ~/.config/rofi/config.rasi \
        -width 320 \
        -lines 8)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    *Wallpaper)
        snowfox wallpaper gui
        ;;
    *Theme)
        snowfox theme gui
        ;;
    *Display)
        ~/.config/scripts/display.sh
        ;;
    *Network)
        ~/.config/scripts/network.sh
        ;;
    *Bluetooth)
        if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
            bluetoothctl power off
            notify-send "󰂲 Bluetooth" "disabled"
        else
            bluetoothctl power on
            notify-send "󰂯 Bluetooth" "enabled"
        fi
        ;;
    *Lock)
        ~/.config/scripts/lock.sh
        ;;
    *Power)
        ~/.config/scripts/powermenu.sh
        ;;
    *"snowfox settings")
        kitty -e snowfox set
        ;;
esac

