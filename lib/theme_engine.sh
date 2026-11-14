#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Theme Engine
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Loads .theme files (Key=Value), validates required keys,
#  derives terminal colors, renders every component config
#  in-place (idempotent), and writes palette.conf atomically
#  so foxdock's SIGHUP never sees a half-written file.
#
#  Design rules (plan §2.2):
#   - one bg per surface, one accent for text/highlight
#   - active/selected = INVERTED (bg = accent, fg = bg)
#   - NO transparency anywhere (no alpha, no opacity)
#   - semantic status colors derived, not stored in themes
# ============================================================

if [[ -n "${_SNOWFOX_THEME_ENGINE_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_SNOWFOX_THEME_ENGINE_LOADED=1

# Paths (overridable for tests)
THEME_DIR="${THEME_DIR:-${TARGET_HOME:-$HOME}/.config/snowfox/themes}"
PALETTE_FILE="${PALETTE_FILE:-${TARGET_HOME:-$HOME}/.config/snowfox/palette.conf}"
THEME_BACKUP="${THEME_BACKUP:-${TARGET_HOME:-$HOME}/.config/snowfox/theme-backup.tar.gz}"
CONFIG_ROOT="${CONFIG_ROOT:-${TARGET_HOME:-$HOME}/.config}"

# ── Theme file parsing ───────────────────────────────────────
# theme_load <path>  ->  exports THEME_* vars (accent, bg, ...)
# Unknown keys are exported as THEME_<upper> for forward-compat.
theme_load() {
    local file="$1"
    [[ -r "$file" ]] || { echo "theme_load: cannot read $file" >&2; return 1; }

    local line key val
    while IFS= read -r line; do
        # strip comments and surrounding whitespace
        line="${line%%#*}"
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # trim trailing whitespace from val
            val="${val%"${val##*[![:space:]]}"}"
            # Normalise key: dark -> DARK, term.color0 -> TERM_COLOR0
            key="${key//./_}"
            key="${key^^}"
            export "THEME_${key}=${val}"
        fi
    done < "$file"

    # Required keys (plan §2.1): 7 core colors + dark
    local req
    for req in ACCENT ACCENT2 ACCENT3 BG BG2 FG FG_DIM DARK; do
        if [[ -z "${!THEME_${req}:-}" ]]; then
            echo "theme_load: missing required key '${req,,}' in $file" >&2
            return 1
        fi
    done

    # Validate hex format for core colors
    local c
    for c in ACCENT ACCENT2 ACCENT3 BG BG2 FG FG_DIM; do
        if [[ ! "${!THEME_${c}}" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
            echo "theme_load: '${c,,}' must be #RRGGBB, got '${!THEME_${c}}'" >&2
            return 1
        fi
    done

    # Derive terminal colors if absent (plan §2.1)
    _theme_derive_terminal
    # Derive semantic status colors (plan §2.2 rule 5)
    _theme_derive_status
}

_theme_derive_terminal() {
    # term.bg / term.fg / term.cursor default from core palette.
    # 16 ANSI slots: sensible fixed defaults that respect bg/fg.
    local dark="${THEME_DARK:-true}"
    : "${THEME_TERM_BG:=${THEME_BG}}"
    : "${THEME_TERM_FG:=${THEME_FG}}"
    : "${THEME_TERM_CURSOR:=${THEME_ACCENT}}"
    export THEME_TERM_BG THEME_TERM_FG THEME_TERM_CURSOR

    if [[ "$dark" == "true" ]]; then
        : "${THEME_TERM_COLOR0:=${THEME_BG2}}"
        : "${THEME_TERM_COLOR8:=${THEME_FG_DIM}}"
        : "${THEME_TERM_COLOR7:=${THEME_FG}}"
        : "${THEME_TERM_COLOR15:=${THEME_FG}}"
    else
        : "${THEME_TERM_COLOR0:=${THEME_FG_DIM}}"
        : "${THEME_TERM_COLOR8:=${THEME_FG}}"
        : "${THEME_TERM_COLOR7:=${THEME_BG2}}"
        : "${THEME_TERM_COLOR15:=${THEME_BG}}"
    fi
    # ANSI 1-6 / 9-14: fixed hue defaults; accent overrides 5/13
    : "${THEME_TERM_COLOR1:=#BF616A}"
    : "${THEME_TERM_COLOR2:=#A3BE8C}"
    : "${THEME_TERM_COLOR3:=#EBCB8B}"
    : "${THEME_TERM_COLOR4:=#81A1C1}"
    : "${THEME_TERM_COLOR5:=${THEME_ACCENT}}"
    : "${THEME_TERM_COLOR6:=#88C0D0}"
    : "${THEME_TERM_COLOR9:=#D07A7F}"
    : "${THEME_TERM_COLOR10:=#B1C89A}"
    : "${THEME_TERM_COLOR11:=#E4CE91}"
    : "${THEME_TERM_COLOR12:=#93B5CC}"
    : "${THEME_TERM_COLOR13:=${THEME_ACCENT3}}"
    : "${THEME_TERM_COLOR14:=#9BCAD8}"
    local i
    for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        export "THEME_TERM_COLOR${i}"
    done
}

_theme_derive_status() {
    # Fixed hues, brightness nudged toward bg for readability.
    # green / yellow / red / orange — never stored in .theme files.
    if [[ "${THEME_DARK:-true}" == "true" ]]; then
        export THEME_STATUS_GREEN="#7FB069"
        export THEME_STATUS_YELLOW="#D4B86A"
        export THEME_STATUS_RED="#C96A6A"
        export THEME_STATUS_ORANGE="#D4956A"
    else
        export THEME_STATUS_GREEN="#4F7A3A"
        export THEME_STATUS_YELLOW="#8A6D1F"
        export THEME_STATUS_RED="#A63D3D"
        export THEME_STATUS_ORANGE="#A6632D"
    fi
}

# ── Theme listing / validation ───────────────────────────────
theme_list() {
    local f name
    for f in "$THEME_DIR"/*.theme; do
        [[ -e "$f" ]] || continue
        name="$(basename "$f" .theme)"
        ( theme_load "$f" >/dev/null 2>&1 \
            && printf '%s\t%s\t%s\n' "$name" "${THEME_ACCENT:-?}" "${THEME_BG:-?}" ) \
          || printf '%s\tINVALID\t-\n' "$name"
    done
}

theme_check() {
    local f name rc=0
    for f in "$THEME_DIR"/*.theme; do
        [[ -e "$f" ]] || continue
        name="$(basename "$f" .theme)"
        if ! ( theme_load "$f" >/dev/null 2>&1 ); then
            echo "INVALID: $name ($f)" >&2
            rc=1
        fi
    done
    [[ $rc -eq 0 ]] && echo "all themes valid"
    return $rc
}

# ── Atomic palette write ─────────────────────────────────────
# foxdock reads palette.conf on SIGHUP. Never truncate in place.
_theme_write_palette() {
    local dir tmp
    dir="$(dirname "$PALETTE_FILE")"
    mkdir -p "$dir"
    tmp="$(mktemp "${dir}/.palette.XXXXXX")"
    {
        echo "# Generated by snowfox theme — do not edit"
        echo "dark=${THEME_DARK}"
        echo "accent=${THEME_ACCENT}"
        echo "accent2=${THEME_ACCENT2}"
        echo "accent3=${THEME_ACCENT3}"
        echo "bg=${THEME_BG}"
        echo "bg2=${THEME_BG2}"
        echo "fg=${THEME_FG}"
        echo "fg_dim=${THEME_FG_DIM}"
        echo "status_green=${THEME_STATUS_GREEN}"
        echo "status_yellow=${THEME_STATUS_YELLOW}"
        echo "status_red=${THEME_STATUS_RED}"
        echo "status_orange=${THEME_STATUS_ORANGE}"
    } > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$PALETTE_FILE"
}

# ── Renderer ─────────────────────────────────────────────────
# Replaces known color values in-place. Idempotent by construction:
# it rewrites from a canonical marker block, not by string-replacing
# arbitrary hex values (which would be fragile and non-idempotent).
# Backup taken once per invocation before any file is touched.
theme_render_all() {
    local files=(
        "$CONFIG_ROOT/i3/config"
        "$CONFIG_ROOT/polybar/config.ini"
        "$CONFIG_ROOT/rofi/config.rasi"
        "$CONFIG_ROOT/kitty/kitty.conf"
        "$CONFIG_ROOT/dunst/dunstrc"
        "$CONFIG_ROOT/picom.conf"
        "$CONFIG_ROOT/xsettingsd/xsettingsd.conf"
        "$CONFIG_ROOT/gtk-3.0/settings.ini"
        "$CONFIG_ROOT/gtk-4.0/settings.ini"
        "$CONFIG_ROOT/gtk-3.0/gtk.css"
        "$CONFIG_ROOT/gtk-4.0/gtk.css"
        "${TARGET_HOME:-$HOME}/.gtkrc-2.0"
        "$CONFIG_ROOT/qt5ct/qt5ct.conf"
        "$CONFIG_ROOT/qt6ct/qt6ct.conf"
    )
    local f
    for f in "${files[@]}"; do
        [[ -f "$f" ]] && _theme_backup_add "$f"
    done
    _theme_backup_flush

    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        case "$f" in
            *"/i3/config")            _render_i3 "$f" ;;
            *"/polybar/config.ini")   _render_polybar "$f" ;;
            *"/rofi/config.rasi")     _render_rofi "$f" ;;
            *"/kitty/kitty.conf")     _render_kitty "$f" ;;
            *"/dunst/dunstrc")        _render_dunst "$f" ;;
            *"/picom.conf")           _render_picom "$f" ;;
            *"/xsettingsd.conf")      _render_xsettingsd "$f" ;;
            *"/gtk-3.0/settings.ini"|*"/gtk-4.0/settings.ini")
                                      _render_gtk_settings "$f" ;;
            *"/gtk-3.0/gtk.css"|*"/gtk-4.0/gtk.css")
                                      _render_gtk_css "$f" ;;
            *"/.gtkrc-2.0")           _render_gtk2 "$f" ;;
            *"/qt5ct.conf"|*"/qt6ct.conf")
                                      _render_qtct "$f" ;;
        esac
    done

    _theme_write_palette
}

# Backup helpers (single tarball per render, plan §2.3)
_theme_backup_tmp=""
_theme_backup_add() {
    if [[ -z "$_theme_backup_tmp" ]]; then
        _theme_backup_tmp="$(mktemp -d)"
    fi
    mkdir -p "$_theme_backup_tmp/$(dirname "${1#/}")" 2>/dev/null || true
    cp -p "$1" "$_theme_backup_tmp/$(dirname "${1#/}")/" 2>/dev/null || true
}
_theme_backup_flush() {
    [[ -n "$_theme_backup_tmp" ]] || return 0
    mkdir -p "$(dirname "$THEME_BACKUP")"
    tar -czf "$THEME_BACKUP" -C "$_theme_backup_tmp" . 2>/dev/null || true
    rm -rf "$_theme_backup_tmp"
    _theme_backup_tmp=""
}

# ── Per-component renderers ──────────────────────────────────
# Strategy: each config carries a canonical marker block. We
# remove everything between BEGIN/END and rewrite it. This is
# idempotent: same theme -> byte-identical file.

_render_block() {
    local file="$1" begin="$2" end="$3" content="$4"
    # Remove old block, then append fresh one
    if grep -qF "$begin" "$file" 2>/dev/null; then
        awk -v b="$begin" -v e="$end" '
            index($0,b){skip=1; next}
            index($0,e){skip=0; next}
            !skip
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
    # Ensure trailing newline before block
    [[ -s "$file" ]] && tail -c1 "$file" | grep -q $'\n' || echo >> "$file"
    {
        echo "$begin"
        echo "$content"
        echo "$end"
    } >> "$file"
}

_render_i3() {
    local f="$1"
    local content
    content=$(cat <<EOF
# SnowFoxOS palette (generated)
set \$bg        ${THEME_BG}
set \$bg2       ${THEME_BG2}
set \$fg        ${THEME_FG}
set \$fg_dim    ${THEME_FG_DIM}
set \$accent    ${THEME_ACCENT}
set \$accent2   ${THEME_ACCENT2}
set \$accent3   ${THEME_ACCENT3}
client.focused          \$accent  \$bg  \$bg     \$accent  \$accent
client.focused_inactive \$bg2     \$bg  \$fg_dim \$bg2     \$bg2
client.unfocused        \$bg      \$bg  \$fg_dim \$bg      \$bg
client.urgent           \$accent2 \$bg  \$bg     \$accent2 \$accent2
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_polybar() {
    local f="$1"
    local content
    content=$(cat <<EOF
[colors]
background = ${THEME_BG}
background-alt = ${THEME_BG2}
foreground = ${THEME_FG}
foreground-alt = ${THEME_FG_DIM}
primary = ${THEME_ACCENT}
secondary = ${THEME_ACCENT2}
alert = ${THEME_STATUS_RED}
EOF
)
    _render_block "$f" "; BEGIN SNOWFOX PALETTE" "; END SNOWFOX PALETTE" "$content"
}

_render_rofi() {
    local f="$1"
    local content
    content=$(cat <<EOF
/* SnowFoxOS palette (generated) */
* {
    bg:      ${THEME_BG};
    bg2:     ${THEME_BG2};
    fg:      ${THEME_FG};
    fg-dim:  ${THEME_FG_DIM};
    accent:  ${THEME_ACCENT};
    accent2: ${THEME_ACCENT2};
}
EOF
)
    _render_block "$f" "/* BEGIN SNOWFOX PALETTE */" "/* END SNOWFOX PALETTE */" "$content"
}

_render_kitty() {
    local f="$1"
    local content
    content=$(cat <<EOF
background            ${THEME_TERM_BG}
foreground            ${THEME_TERM_FG}
cursor                ${THEME_TERM_CURSOR}
cursor_text_color     ${THEME_BG}
selection_background  ${THEME_ACCENT}
selection_foreground  ${THEME_BG}
color0  ${THEME_TERM_COLOR0}
color1  ${THEME_TERM_COLOR1}
color2  ${THEME_TERM_COLOR2}
color3  ${THEME_TERM_COLOR3}
color4  ${THEME_TERM_COLOR4}
color5  ${THEME_TERM_COLOR5}
color6  ${THEME_TERM_COLOR6}
color7  ${THEME_TERM_COLOR7}
color8  ${THEME_TERM_COLOR8}
color9  ${THEME_TERM_COLOR9}
color10 ${THEME_TERM_COLOR10}
color11 ${THEME_TERM_COLOR11}
color12 ${THEME_TERM_COLOR12}
color13 ${THEME_TERM_COLOR13}
color14 ${THEME_TERM_COLOR14}
color15 ${THEME_TERM_COLOR15}
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_dunst() {
    local f="$1"
    local content
    content=$(cat <<EOF
[global]
frame_color = "${THEME_ACCENT}"
separator_color = "${THEME_FG_DIM}"

[urgency_low]
background = "${THEME_BG}"
foreground = "${THEME_FG_DIM}"
frame_color = "${THEME_FG_DIM}"
highlight = "${THEME_ACCENT2}"

[urgency_normal]
background = "${THEME_BG2}"
foreground = "${THEME_FG}"
frame_color = "${THEME_ACCENT}"
highlight = "${THEME_ACCENT}"

[urgency_critical]
background = "${THEME_BG2}"
foreground = "${THEME_FG}"
frame_color = "${THEME_STATUS_RED}"
highlight = "${THEME_STATUS_RED}"
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_picom() {
    local f="$1"
    # plan §2.2 rule 4: fully opaque, no fading, no blur.
    local content
    content=$(cat <<EOF
# SnowFoxOS palette (generated) — opacity is ALWAYS 1.0
shadow = true;
shadow-radius = 7;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-color = "${THEME_BG}";
fading = false;
corner-radius = 6;
backend = "glx";
vsync = true;
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_xsettingsd() {
    local f="$1"
    local content
    content=$(cat <<EOF
Net/ThemeName "${THEME_GTK_THEME:-Arc-Dark}"
Net/IconThemeName "${THEME_GTK_ICON:-Papirus-Dark}"
Gtk/CursorThemeName "${THEME_GTK_CURSOR:-Bibata-Modern-Classic}"
Gtk/CursorThemeSize 24
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_gtk_settings() {
    local f="$1"
    local dark_flag=0
    [[ "${THEME_DARK}" == "true" ]] && dark_flag=1
    local content
    content=$(cat <<EOF
[Settings]
gtk-theme-name=${THEME_GTK_THEME:-Arc-Dark}
gtk-icon-theme-name=${THEME_GTK_ICON:-Papirus-Dark}
gtk-font-name=Inter 11
gtk-cursor-theme-name=${THEME_GTK_CURSOR:-Bibata-Modern-Classic}
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=${dark_flag}
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_gtk_css() {
    local f="$1"
    local content
    content=$(cat <<EOF
/* SnowFoxOS palette (generated) */
@define-color theme_bg_color ${THEME_BG};
@define-color theme_fg_color ${THEME_FG};
@define-color theme_base_color ${THEME_BG2};
@define-color theme_text_color ${THEME_FG};
@define-color theme_selected_bg_color ${THEME_ACCENT};
@define-color theme_selected_fg_color ${THEME_BG};
@define-color insensitive_fg_color ${THEME_FG_DIM};
EOF
)
    _render_block "$f" "/* BEGIN SNOWFOX PALETTE */" "/* END SNOWFOX PALETTE */" "$content"
}

_render_gtk2() {
    local f="$1"
    local content
    content=$(cat <<EOF
# SnowFoxOS palette (generated)
gtk-theme-name = "${THEME_GTK_THEME:-Arc-Dark}"
gtk-icon-theme-name = "${THEME_GTK_ICON:-Papirus-Dark}"
gtk-font-name = "Inter 11"
gtk-cursor-theme-name = "${THEME_GTK_CURSOR:-Bibata-Modern-Classic}"
gtk-cursor-theme-size = 24
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

_render_qtct() {
    local f="$1"
    local content
    content=$(cat <<EOF
[Appearance]
style=gtk2
color_scheme_path=
custom_palette=false
icon_theme=${THEME_GTK_ICON:-Papirus-Dark}
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

# ── Public entry points ──────────────────────────────────────
# theme_apply <name>: load, render all, persist selection.
theme_apply() {
    local name="$1"
    local file="$THEME_DIR/${name}.theme"
    if [[ ! -r "$file" ]]; then
        echo "theme_apply: theme '$name' not found in $THEME_DIR" >&2
        return 1
    fi
    theme_load "$file" || return 1
    theme_render_all
    # Persist selection (used by firstboot re-apply)
    local sel="${TARGET_HOME:-$HOME}/.config/snowfox/theme"
    mkdir -p "$(dirname "$sel")"
    printf '%s\n' "$name" > "$sel"
    # Live-reload foxdock if it's running (plan §2.3, §4)
    if command -v pkill >/dev/null 2>&1; then
        pkill -HUP -x foxdock 2>/dev/null || true
    fi
    return 0
}

theme_reset() {
    local default="${1:-nightfox}"
    theme_apply "$default"
}
