#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — CLI: wallpaper
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Subcommands:
#    list                 list wallpapers in ~/Pictures/wallpapers
#    set <path>           set wallpaper via feh
#    auto <path>          derive a theme (incl. dark/light mode), activate it
#    (no subcommand)      rofi picker: list + "auto" entry
#
#  auto (§3):
#    1. resize image to <= 256 px on the long edge
#    2. extract 8 dominant colours WITH area weights (histogram)
#    3. pick bg = neutral colour with largest area share
#       → mode (dark/light) is derived from bg luma, not the other way round
#    4. pick accent = most saturated colour with contrast >= 2.5 vs bg
#    5. derive accent2/accent3 by hue shift
#    6. fg / fg_dim strictly follow mode
#    7. write ~/.config/snowfox/themes/wallpaper-auto.theme
#       (including `dark = true|false`)
#    8. activate via theme_apply
#    9. log source + mode in ~/.config/snowfox/wallpaper.conf
# ============================================================

if [[ -n "${_SNOWFOX_CLI_WALLPAPER_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_SNOWFOX_CLI_WALLPAPER_LOADED=1

# Resolve theme_engine.sh whether installed or running from repo.
_wall_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -r "$_wall_self_dir/lib/theme_engine.sh" ]]; then
    # shellcheck source=../lib/theme_engine.sh
    source "$_wall_self_dir/lib/theme_engine.sh"
elif [[ -r /usr/local/lib/snowfox/lib/theme_engine.sh ]]; then
    # shellcheck source=/dev/null
    source /usr/local/lib/snowfox/lib/theme_engine.sh
else
    err "theme_engine.sh not found (repo or /usr/local/lib/snowfox/lib)"
fi

WALL_DIR="${WALL_DIR:-$HOME/Pictures/wallpapers}"
WALL_CONF="${WALL_CONF:-$HOME/.config/snowfox/wallpaper.conf}"
WALL_THEME_NAME="wallpaper-auto"
WALL_THEME_PATH="${THEME_DIR:-$HOME/.config/snowfox/themes}/${WALL_THEME_NAME}.theme"

# ── Dispatcher ─────────────────────────────────────────────
cmd_wallpaper() {
    local sub="${1:-}"
    case "$sub" in
        ""|gui)        _wall_gui ;;
        list)          _wall_list ;;
        set)           _wall_set "${2:-}" ;;
        auto)          _wall_auto "${2:-}" ;;
        -h|--help)     _wall_usage ;;
        *)             err "usage: snowfox wallpaper <list|set|auto|gui>"; return 1 ;;
    esac
}

_wall_usage() {
    cat <<'EOF'
Usage: snowfox wallpaper [subcommand]

  (none) | gui   Rofi picker (wallpapers + "auto" toggle)
  list           list wallpapers in ~/Pictures/wallpapers
  set <path>     set the wallpaper via feh
  auto <path>    derive a theme (incl. dark/light mode) and activate it
EOF
}

# ── list ───────────────────────────────────────────────────
_wall_list() {
    header "snowfox wallpaper"
    [[ -d "$WALL_DIR" ]] || { info "no wallpapers in $WALL_DIR"; return 0; }
    local f
    for f in "$WALL_DIR"/*.jpg "$WALL_DIR"/*.jpeg "$WALL_DIR"/*.png "$WALL_DIR"/*.webp; do
        [[ -e "$f" ]] || continue
        row "$(basename "$f")" ""
    done
    info "snowfox wallpaper auto <file>   derive theme from image"
    info "snowfox wallpaper set <file>    set wallpaper only"
}

# ── set ────────────────────────────────────────────────────
_wall_set() {
    local img="${1:-}"
    [[ -z "$img" ]] && { err "usage: snowfox wallpaper set <path>"; return 1; }
    if [[ ! -f "$img" ]]; then
        if [[ -f "$WALL_DIR/$img" ]]; then
            img="$WALL_DIR/$img"
        else
            err "not found: $img"
            return 1
        fi
    fi

    if ! command -v feh >/dev/null 2>&1; then
        err "feh not installed"
        return 1
    fi

    if feh --bg-fill "$img"; then
        _wall_log_source "$img"
        ok "wallpaper set: $img"
    else
        err "feh failed"
        return 1
    fi
}

# ── gui (rofi) ─────────────────────────────────────────────
_wall_gui() {
    if ! command -v rofi >/dev/null 2>&1; then
        err "rofi not installed"
        return 1
    fi
    if [[ ! -d "$WALL_DIR" ]]; then
        err "no wallpapers in $WALL_DIR"
        return 1
    fi

    local -a entries=()
    local f
    for f in "$WALL_DIR"/*.jpg "$WALL_DIR"/*.jpeg "$WALL_DIR"/*.png "$WALL_DIR"/*.webp; do
        [[ -e "$f" ]] || continue
        entries+=("$(basename "$f")")
    done
    [[ ${#entries[@]} -eq 0 ]] && { info "no wallpapers found"; return 0; }

    local choice
    choice=$(printf 'auto\n%s\n' "$(printf '%s\n' "${entries[@]}")" \
             | rofi -dmenu -p "wallpaper" -no-custom)
    [[ -z "$choice" ]] && return 0

    if [[ "$choice" == "auto" ]]; then
        local current=""
        [[ -f "$WALL_CONF" ]] && current="$(sed -n 's/^source=//p' "$WALL_CONF" | tail -n1)"
        if [[ -n "$current" && -f "$current" ]]; then
            _wall_auto "$current"
        else
            local pick
            pick=$(printf '%s\n' "${entries[@]}" | rofi -dmenu -p "auto from")
            [[ -z "$pick" ]] && return 0
            _wall_auto "$WALL_DIR/$pick"
        fi
        return 0
    fi

    _wall_set "$WALL_DIR/$choice"
}

# ── auto ───────────────────────────────────────────────────
_wall_auto() {
    local src="${1:-}"
    [[ -z "$src" ]] && { err "usage: snowfox wallpaper auto <path>"; return 1; }
    [[ -f "$src" ]] || { err "not found: $src"; return 1; }

    if ! command -v convert >/dev/null 2>&1; then
        err "ImageMagick (convert) not installed"
        return 1
    fi
    if [[ -z "${THEME_DIR:-}" ]] || ! declare -F theme_apply >/dev/null 2>&1; then
        err "theme engine not loaded"
        return 1
    fi

    header "snowfox wallpaper auto"

    local tmp
    tmp="$(mktemp --suffix=.png)"
    if ! convert "$src" -resize '256x256>' "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        err "convert resize failed"
        return 1
    fi

    # ── Farben + Flächenanteile (Histogramm) extrahieren ──
    # convert … -colors 8 -format %c histogram:info:-
    # Ausgabezeilen z.B.: "  12345: ( 12, 34, 56) #0C2238 srgb(12,34,56)"
    local -a colours=() weights=()
    local line count hex
    while IFS= read -r line; do
        # Anteil (erste Zahl vor ':')
        count="$(sed -E 's/^[[:space:]]*([0-9]+):.*/\1/' <<<"$line")"
        [[ "$count" =~ ^[0-9]+$ ]] || continue
        # Hex
        hex="$(grep -oE '#[0-9A-Fa-f]{6}' <<<"$line" | head -n1)"
        [[ -n "$hex" ]] || continue
        colours+=("${hex^^}")
        weights+=("$count")
    done < <(convert "$tmp" -colors 8 -format %c histogram:info:- 2>/dev/null)
    rm -f "$tmp"

    if [[ ${#colours[@]} -eq 0 ]]; then
        err "no colours extracted from $src"
        return 1
    fi

    info "extracted ${#colours[@]} colours (with area weights)"
    local i
    for i in "${!colours[@]}"; do
        local c="${colours[$i]}" w="${weights[$i]}"
        printf '  %s  w=%-6s %s\n' "$c" "$w" "$(printf '\033[38;2;%d;%d;%dm████\033[0m' \
            "$((16#${c:1:2}))" "$((16#${c:3:2}))" "$((16#${c:5:2}))")"
    done

    # ── 1. bg = neutraler Kandidat mit größtem Flächenanteil ──
    # Neutral = Sättigung < 40. Fallback: alle Farben.
    local bg=""
    bg="$(_wall_pick_bg "${colours[@]}" -- "${weights[@]}")"
    if [[ -z "$bg" ]]; then
        bg="$(_wall_pick_bg "${colours[@]}" -- "${weights[@]}" --all)"
    fi
    if [[ -z "$bg" ]]; then
        # letzter Fallback: dunkelster/hellster je nach Mittelwert
        local mean
        mean="$(_wall_mean_rel_luma "${colours[@]}")"
        if (( mean < 128 )); then bg="#111318"; else bg="#F4F4F6"; fi
        warn "no neutral colour found — using fallback bg $bg"
    fi

    # ── 2. Mode aus bg-Luma ableiten (NICHT umgekehrt!) ──
    local bg_luma mode dark
    bg_luma="$(_wall_rel_luma "$bg")"
    if (( bg_luma < 128 )); then
        mode="dark"; dark=true
    else
        mode="light"; dark=false
    fi
    info "bg=$bg (rel-luma=$bg_luma) → mode=$mode"

    # ── 3. accent = gesättigtester Kandidat mit Kontrast >= 2.5 ──
    local accent=""
    local -a sorted
    mapfile -t sorted < <(_wall_sort_by_saturation "${colours[@]}")
    local cand cr
    for cand in "${sorted[@]}"; do
        [[ "$cand" == "$bg" ]] && continue
        cr="$(_wall_contrast "$cand" "$bg")"
        if (( cr >= 250 )); then
            accent="$cand"; break
        fi
    done
    # Zweiter Pass: nur Sättigung, wenn kein Kandidat 2.5 erreicht
    if [[ -z "$accent" ]]; then
        for cand in "${sorted[@]}"; do
            [[ "$cand" == "$bg" ]] && continue
            accent="$cand"; break
        done
    fi
    if [[ -z "$accent" ]]; then
        accent="${THEME_ACCENT:-#9B59B6}"
        warn "no accent candidate — using active accent ($accent)"
    fi
    info "accent=$accent"

    # ── 4. Akzent-Varianten ────────────────────────────────
    local accent2 accent3
    accent2="$(_wall_hue_shift "$accent" -15 0.85)"
    accent3="$(_wall_hue_shift "$accent" +15 1.15)"

    # ── 5. fg strikt an Mode ───────────────────────────────
    local fg fg_dim
    if $dark; then
        fg="#F5F5F5"
        fg_dim="#8A919E"
    else
        fg="#1A1A1A"
        fg_dim="#5A6068"
    fi

    # ── 6. Theme schreiben (inkl. dark = …) ────────────────
    mkdir -p "$(dirname "$WALL_THEME_PATH")"
    cat > "$WALL_THEME_PATH" <<EOF
# SnowFoxOS theme: ${WALL_THEME_NAME}
# Generated from: ${src}
# detected mode: ${mode}
# bg rel-luma: ${bg_luma}
dark = ${dark}

accent  = ${accent}
accent2 = ${accent2}
accent3 = ${accent3}
bg      = ${bg}
bg2     = ${bg}
fg      = ${fg}
fg_dim  = ${fg_dim}
EOF
    success "theme written: $WALL_THEME_PATH (mode=${mode})"

    if theme_apply "$WALL_THEME_NAME"; then
        success "theme applied: $WALL_THEME_NAME ($mode)"
    else
        err "theme_apply failed"
        return 1
    fi

    _wall_log_source "$src" "$mode"
    return 0
}

# ── bg-Auswahl: neutral + größter Flächenanteil ────────────
# Usage: _wall_pick_bg <colours...> -- <weights...> [--all]
#   Farben und Gewichte sind durch "--" getrennt (gleiche Reihenfolge).
#   --all überspringt den Neutral-Filter.
_wall_pick_bg() {
    local -a cols=() ws=()
    local seen_sep=0 all=0
    local a
    for a in "$@"; do
        if [[ "$a" == "--" ]]; then seen_sep=1; continue; fi
        if [[ "$a" == "--all" ]]; then all=1; continue; fi
        if (( seen_sep )); then ws+=("$a"); else cols+=("$a"); fi
    done

    local best="" best_w=-1
    local i c w sat
    for i in "${!cols[@]}"; do
        c="${cols[$i]}"; w="${ws[$i]:-0}"
        if (( ! all )); then
            sat="$(_wall_saturation "$c")"
            (( sat >= 40 )) && continue
        fi
        if (( w > best_w )); then best="$c"; best_w=$w; fi
    done
    printf '%s\n' "$best"
}

# ── helpers ────────────────────────────────────────────────
_wall_sort_by_saturation() {
    local c
    for c in "$@"; do
        printf '%s\t%d\n' "$c" "$(_wall_saturation "$c")"
    done | sort -k2 -nr | cut -f1
}

_wall_mean_rel_luma() {
    local n=$# sum=0 c
    (( n == 0 )) && { echo 0; return; }
    for c in "$@"; do sum=$(( sum + $(_wall_rel_luma "$c") )); done
    echo $(( sum / n ))
}

_wall_luma() {
    local c="$1"
    local r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
    echo $(( (299*r + 587*g + 114*b) / 1000 ))
}

_wall_saturation() {
    local c="$1"
    local r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
    local max=$r min=$r
    (( g > max )) && max=$g
    (( g < min )) && min=$g
    (( b > max )) && max=$b
    (( b < min )) && min=$b
    echo $(( max - min ))
}

_wall_contrast() {
    local a="$1" b="$2"
    local la lb ha hb
    la="$(_wall_rel_luma "$a")"
    lb="$(_wall_rel_luma "$b")"
    if (( la > lb )); then ha=$la; hb=$lb; else ha=$lb; hb=$la; fi
    echo $(( (ha + 50) * 100 / (hb + 50) ))
}

_wall_rel_luma() {
    local c="$1"
    local r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
    local lr lg lb
    lr=$(_wall_linearize "$r")
    lg=$(_wall_linearize "$g")
    lb=$(_wall_linearize "$b")
    echo $(( (2126*lr + 7152*lg + 722*lb) / 10000 ))
}

_wall_linearize() {
    local v="$1"
    if (( v <= 10 )); then
        echo $(( v * 1000 / 3294 ))
    else
        echo $(( (v * v) / 65 ))
    fi
}

_wall_hue_shift() {
    local hex="$1" deg="$2" scale="$3"
    awk -v hex="$hex" -v deg="$deg" -v scale="$scale" '
    function hex2dec(h,   i,c, n) {
        n = 0
        h = tolower(h)
        for (i=1; i<=length(h); i++) {
            c = substr(h,i,1)
            n = n * 16 + index("0123456789abcdef", c) - 1
        }
        return n
    }
    function dec2hex(n) {
        return sprintf("%02X", n)
    }
    function max(a,b){return a>b?a:b}
    function min(a,b){return a<b?a:b}
    function hue2rgb(p, q, t,   r) {
        if (t < 0) t += 1
        if (t > 1) t -= 1
        if (t < 1/6) return p + (q - p) * 6 * t
        if (t < 1/2) return q
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6
        return p
    }
    BEGIN {
        h = substr(hex, 2, 6)
        r = hex2dec(substr(h,1,2)) / 255
        g = hex2dec(substr(h,3,2)) / 255
        b = hex2dec(substr(h,5,2)) / 255
        mx = max(r, max(g, b)); mn = min(r, min(g, b))
        l = (mx + mn) / 2
        if (mx == mn) { hh = 0; s = 0 }
        else {
            d = mx - mn
            s = (l > 0.5) ? d / (2 - mx - mn) : d / (mx + mn)
            if (mx == r)      hh = (g - b) / d + (g < b ? 6 : 0)
            else if (mx == g) hh = (b - r) / d + 2
            else              hh = (r - g) / d + 4
            hh = hh / 6
        }
        hh = hh + deg / 360
        while (hh < 0) hh += 1
        while (hh >= 1) hh -= 1
        l = l * scale
        if (l < 0) l = 0; if (l > 1) l = 1
        if (s == 0) { r = g = b = l }
        else {
            q = (l < 0.5) ? l * (1 + s) : l + s - l * s
            p = 2 * l - q
            r = hue2rgb(p, q, hh + 1/3)
            g = hue2rgb(p, q, hh)
            b = hue2rgb(p, q, hh - 1/3)
        }
        printf("#%s%s%s\n", dec2hex(int(r*255+0.5)), dec2hex(int(g*255+0.5)), dec2hex(int(b*255+0.5)))
    }'
}

_wall_log_source() {
    local src="$1" mode="${2:-}"
    mkdir -p "$(dirname "$WALL_CONF")"
    {
        echo "# SnowFoxOS wallpaper log"
        echo "# Rewritten on every successful set/auto"
        echo "source=$src"
        [[ -n "$mode" ]] && echo "mode=$mode"
        echo "timestamp=$(date -Iseconds)"
        if [[ -f "$WALL_THEME_PATH" ]]; then
            echo "auto_theme=$WALL_THEME_PATH"
        fi
    } > "$WALL_CONF"
}
