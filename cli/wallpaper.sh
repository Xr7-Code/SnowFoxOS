#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — CLI: wallpaper
#  TODO(Prompt 6): auto-palette from image (plan §3)
# ============================================================

if [[ -n "${_SNOWFOX_CLI_WALLPAPER_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_SNOWFOX_CLI_WALLPAPER_LOADED=1

cmd_wallpaper() {
    local sub="${1:-}"
    case "$sub" in
        ""|list)  _wall_list ;;
        set)      _wall_set "${2:-}" ;;
        auto)     _wall_auto "${2:-}" ;;
        *)        err "usage: snowfox wallpaper <list|set|auto>"; return "$SNOWFOX_EXIT_ERROR" ;;
    esac
}

_wall_list() {
    header "snowfox wallpaper"
    local dir="$HOME/Pictures/wallpapers"
    [[ -d "$dir" ]] || { info "no wallpapers in $dir"; return 0; }
    local f
    for f in "$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.png "$dir"/*.webp; do
        [[ -e "$f" ]] || continue
        row "$(basename "$f")" ""
    done
}

_wall_set() {
    local img="${1:-}"
    [[ -z "$img" ]] && { err "usage: snowfox wallpaper set <path>"; return "$SNOWFOX_EXIT_ERROR"; }
    if feh --bg-fill "$img"; then
        ok "wallpaper set: $img"
    else
        err "feh failed"
        return "$SNOWFOX_EXIT_ERROR"
    fi
}

_wall_auto() {
    err "not implemented yet — Prompt 6"
    return "$SNOWFOX_EXIT_ERROR"
}
