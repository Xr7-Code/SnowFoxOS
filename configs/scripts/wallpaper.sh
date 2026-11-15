#!/usr/bin/env bash
# SnowFoxOS — Wallpaper Selector via Rofi
WP_DIR="$HOME/Pictures/wallpapers"

if [[ ! -d "$WP_DIR" ]]; then
    notify-send "🦊 SnowFox" "Wallpaper folder not found: $WP_DIR"
    exit 1
fi

FILES=$(ls "$WP_DIR" 2>/dev/null | grep -iE "\.jpg$|\.png$|\.webp$|\.jpeg$")

CHOICE=$(echo -e "$FILES" | rofi -dmenu \
    -p "Wallpaper" \
    -theme ~/.config/rofi/config.rasi \
    -width 400 \
    -lines 10)

if [[ -n "$CHOICE" ]] && [[ -f "$WP_DIR/$CHOICE" ]]; then
    feh --bg-fill "$WP_DIR/$CHOICE" 2>/dev/null
    notify-send "🦊 SnowFox" "Wallpaper updated: $CHOICE"
fi

