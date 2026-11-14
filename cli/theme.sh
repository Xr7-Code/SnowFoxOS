#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — snowfox theme
# ============================================================
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/theme_engine.sh
source "$SCRIPT_DIR/lib/theme_engine.sh"

cmd="${1:-list}"
shift || true

case "$cmd" in
    list)
        printf '%-16s %-10s %-10s\n' "THEME" "ACCENT" "BG"
        theme_list | while IFS=$'\t' read -r name accent bg; do
            printf '%-16s %-10s %-10s\n' "$name" "$accent" "$bg"
        done
        ;;
    check)
        theme_check
        ;;
    show)
        name="${1:-$(head -n1 "${TARGET_HOME:-$HOME}/.config/snowfox/theme" 2>/dev/null || echo nightfox)}"
        theme_load "$THEME_DIR/${name}.theme" || exit 1
        printf 'theme:    %s\n' "$name"
        printf 'dark:     %s\n' "$THEME_DARK"
        printf 'accent:   %s\n' "$THEME_ACCENT"
        printf 'accent2:  %s\n' "$THEME_ACCENT2"
        printf 'accent3:  %s\n' "$THEME_ACCENT3"
        printf 'bg:       %s\n' "$THEME_BG"
        printf 'bg2:      %s\n' "$THEME_BG2"
        printf 'fg:       %s\n' "$THEME_FG"
        printf 'fg_dim:   %s\n' "$THEME_FG_DIM"
        ;;
    reset)
        theme_reset "${1:-nightfox}"
        ;;
    *)
        # Treat unknown as theme name (snowfox theme nightfox)
        theme_apply "$cmd"
        ;;
esac
