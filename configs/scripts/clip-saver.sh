#!/usr/bin/env bash
# ============================================================
#   SnowFoxOS v4 — Clip-Saver
#   Keeps X11 clipboard data (text/PNG) alive even when the
#   source window is closed. File operations are deliberately
#   NOT touched.
# ============================================================

tmp=$(mktemp)
trap "rm -f \"$tmp\"" EXIT
last_hash=""

while clipnotify; do
    targets=$(xclip -selection clipboard -t TARGETS -o 2>/dev/null) || continue

    if grep -qE "x-special/|text/uri-list|XdndDirectSave" <<<"$targets"; then
        last_hash=""
        continue
    fi

    if grep -qx "image/png" <<<"$targets"; then
        type="image/png"
    elif grep -qx "UTF8_STRING" <<<"$targets"; then
        type="UTF8_STRING"
    else
        continue
    fi

    xclip -selection clipboard -t "$type" -o >"$tmp" 2>/dev/null || continue
    [ -s "$tmp" ] || continue

    hash=$(sha256sum <"$tmp" | cut -d" " -f1)
    [ "$hash" = "$last_hash" ] && continue
    last_hash="$hash"

    xclip -selection clipboard -t "$type" -i <"$tmp" 2>/dev/null
done

