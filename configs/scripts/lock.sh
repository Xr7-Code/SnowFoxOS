#!/usr/bin/env bash
# ============================================================
#   SnowFoxOS v4 — Lock Screen
#   Only invoked manually via $mod+l (i3). No timer, no media
#   checks, no fullscreen detection — those belong to the
#   caller, not the lock screen itself.
# ============================================================

WALLPAPER=$(grep -oP "(?<=--bg-fill ').*(?=')" ~/.fehbg 2>/dev/null || true)
LOCK_IMG="/tmp/snowfox-lock.png"

if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
    convert "$WALLPAPER" \
        -scale 1920x1080! \
        -blur 0x8 \
        -fill "#15161A" \
        -colorize 30 \
        "$LOCK_IMG"
else
    convert -size 1920x1080 xc:#15161A "$LOCK_IMG"
fi

i3lock -i "$LOCK_IMG" --nofork
rm -f "$LOCK_IMG"

