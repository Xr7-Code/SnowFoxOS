#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Theme Engine
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Parity with v3:
#    - GTK2: full murrine style blocks via ~/.gtkrc-2.0.mine
#    - GTK3: @define-color + widget selectors
#    - GTK4: :root libadwaita tokens + same widget selectors
#  Theme stays Arc-Dark everywhere. No Adwaita fallback.
# ============================================================

if [[ -n "${_SNOWFOX_THEME_ENGINE_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_SNOWFOX_THEME_ENGINE_LOADED=1

THEME_DIR="${THEME_DIR:-${TARGET_HOME:-$HOME}/.config/snowfox/themes}"
PALETTE_FILE="${PALETTE_FILE:-${TARGET_HOME:-$HOME}/.config/snowfox/palette.conf}"
THEME_BACKUP="${THEME_BACKUP:-${TARGET_HOME:-$HOME}/.config/snowfox/theme-backup.tar.gz}"
CONFIG_ROOT="${CONFIG_ROOT:-${TARGET_HOME:-$HOME}/.config}"

# ============================================================
#  Theme loading & derivation
# ============================================================

theme_load() {
    local file="$1"
    [[ -r "$file" ]] || { echo "theme_load: cannot read $file" >&2; return 1; }

    local line key val
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val%"${val##*[![:space:]]}"}"
            key="${key//./_}"
            key="${key^^}"
            export "THEME_${key}=${val}"
        fi
    done < "$file"

    local req var_name
    for req in ACCENT ACCENT2 ACCENT3 BG BG2 FG FG_DIM DARK; do
        var_name="THEME_${req}"
        if [[ -z "${!var_name:-}" ]]; then
            echo "theme_load: missing required key '${req,,}' in $file" >&2
            return 1
        fi
    done

    local c
    for c in ACCENT ACCENT2 ACCENT3 BG BG2 FG FG_DIM; do
        var_name="THEME_${c}"
        if [[ ! "${!var_name}" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
            echo "theme_load: '${c,,}' must be #RRGGBB, got '${!var_name}'" >&2
            return 1
        fi
    done

    _theme_derive_terminal
    _theme_derive_status
    _theme_derive_extra

    if [[ -z "${THEME_ICON_COLOR:-}" ]]; then THEME_ICON_COLOR="violet"; fi
    if [[ -z "${THEME_ICON_THEME:-}" ]]; then THEME_ICON_THEME="Papirus-Dark"; fi
    if [[ -z "${THEME_GTK_THEME:-}" ]];  then THEME_GTK_THEME="Arc-Dark"; fi
    if [[ -z "${THEME_GTK_CURSOR:-}" ]]; then THEME_GTK_CURSOR="Bibata-Modern-Classic"; fi
    export THEME_ICON_COLOR THEME_ICON_THEME THEME_GTK_THEME THEME_GTK_CURSOR
}

_theme_derive_terminal() {
    local dark="${THEME_DARK:-true}"

    if [[ -z "${THEME_TERM_BG:-}" ]];     then THEME_TERM_BG="${THEME_BG}"; fi
    if [[ -z "${THEME_TERM_FG:-}" ]];     then THEME_TERM_FG="${THEME_FG}"; fi
    if [[ -z "${THEME_TERM_CURSOR:-}" ]]; then THEME_TERM_CURSOR="${THEME_ACCENT}"; fi
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

_theme_derive_extra() {
    # Derived tokens used by GTK2/3/4 stylesheets.
    : "${THEME_BG_HOVER:=${THEME_ACCENT3}}"
    : "${THEME_BORDER:=${THEME_BG2}}"
    : "${THEME_TOOLTIP_BG:=${THEME_ACCENT3}}"
    : "${THEME_TOOLTIP_FG:=${THEME_FG}}"
    : "${THEME_LINK:=${THEME_ACCENT2}}"
    export THEME_BG_HOVER THEME_BORDER THEME_TOOLTIP_BG THEME_TOOLTIP_FG THEME_LINK
}

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

# ============================================================
#  Palette file & backup
# ============================================================

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
        echo "icon_color=${THEME_ICON_COLOR}"
        echo "icon_theme=${THEME_ICON_THEME}"
        echo "gtk_theme=${THEME_GTK_THEME}"
        echo "gtk_cursor=${THEME_GTK_CURSOR}"
    } > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$PALETTE_FILE"
}

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

# ============================================================
#  Generic block renderer
# ============================================================

_render_block() {
    local file="$1" begin="$2" end="$3" content="$4"
    if grep -qF "$begin" "$file" 2>/dev/null; then
        awk -v b="$begin" -v e="$end" '
            index($0,b){skip=1; next}
            index($0,e){skip=0; next}
            !skip
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
    [[ -s "$file" ]] && tail -c1 "$file" | grep -q $'\n' || echo >> "$file"
    {
        echo "$begin"
        echo "$content"
        echo "$end"
    } >> "$file"
}

# ============================================================
#  theme_render_all
# ============================================================

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
            *"/i3/config")                                _render_i3 "$f" ;;
            *"/polybar/config.ini")                       _render_polybar "$f" ;;
            *"/rofi/config.rasi")                         _render_rofi "$f" ;;
            *"/kitty/kitty.conf")                         _render_kitty "$f" ;;
            *"/dunst/dunstrc")                            _render_dunst "$f" ;;
            *"/picom.conf")                               _render_picom "$f" ;;
            *"/xsettingsd.conf")                          _render_xsettingsd "$f" ;;
            *"/gtk-3.0/settings.ini"|*"/gtk-4.0/settings.ini")
                                                          _render_gtk_settings "$f" ;;
            *"/gtk-3.0/gtk.css"|*"/gtk-4.0/gtk.css")     _render_gtk_css "$f" ;;
            *"/.gtkrc-2.0")                               _render_gtk2 "$f" ;;
            *"/qt5ct.conf"|*"/qt6ct.conf")                _render_qtct "$f" ;;
        esac
    done

    _theme_write_palette
}

# ============================================================
#  Renderers — i3
# ============================================================

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

# ============================================================
#  Renderers — Polybar
# ============================================================

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

# ============================================================
#  Renderers — Rofi
# ============================================================

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
    urgent:  ${THEME_STATUS_RED};
}
EOF
)
    _render_block "$f" "/* BEGIN SNOWFOX PALETTE */" "/* END SNOWFOX PALETTE */" "$content"
}

# ============================================================
#  Renderers — Kitty
# ============================================================

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

# ============================================================
#  Renderers — Dunst
# ============================================================

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

# ============================================================
#  Renderers — Picom
# ============================================================

_render_picom() {
    local f="$1"
    local content
    content=$(cat <<EOF
# SnowFoxOS palette (generated) — opacity is ALWAYS 1.0
shadow = true;
shadow-radius = 20;
shadow-offset-x = -10;
shadow-offset-y = 6;
shadow-opacity = 0.25;
shadow-color = "${THEME_BG}";
fading = false;
corner-radius = 12;
backend = "xrender";
vsync = false;
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

# ============================================================
#  Renderers — xsettingsd
# ============================================================

_render_xsettingsd() {
    local f="$1"
    local content
    content=$(cat <<EOF
Net/ThemeName "${THEME_GTK_THEME:-Arc-Dark}"
Net/IconThemeName "${THEME_ICON_THEME:-Papirus-Dark}"
Gtk/CursorThemeName "${THEME_GTK_CURSOR:-Bibata-Modern-Classic}"
Gtk/CursorThemeSize 24
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

# ============================================================
#  Renderers — GTK settings.ini (GTK3 + GTK4)
# ============================================================

_render_gtk_settings() {
    # NOTE: no [Settings] header here — the base template already provides it.
    # _render_block appends inside the existing section; a second [Settings]
    # header would create a duplicate group that GLib silently ignores.
    local f="$1"
    local dark_flag=0
    [[ "${THEME_DARK}" == "true" ]] && dark_flag=1
    local content
    content=$(cat <<EOF
gtk-theme-name=${THEME_GTK_THEME:-Arc-Dark}
gtk-icon-theme-name=${THEME_ICON_THEME:-Papirus-Dark}
gtk-font-name=Inter 11
gtk-cursor-theme-name=${THEME_GTK_CURSOR:-Bibata-Modern-Classic}
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=${dark_flag}
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

# ============================================================
#  Renderers — GTK3 + GTK4 CSS (single source, works for both)
# ============================================================

_render_gtk_css() {
    local f="$1"
    local content
    content=$(cat <<EOF
/* SnowFoxOS palette (generated) — GTK3 + GTK4 */

/* ── GTK3: @define-color tokens (Arc-Dark overrides) ─────── */
@define-color bg_color          ${THEME_BG};
@define-color bg_alt_color      ${THEME_BG2};
@define-color bg_hover_color    ${THEME_BG_HOVER};
@define-color fg_color          ${THEME_FG};
@define-color fg_dim_color      ${THEME_FG_DIM};
@define-color selected_bg_color ${THEME_ACCENT};
@define-color selected_fg_color ${THEME_BG};
@define-color purple_hover      ${THEME_ACCENT2};
@define-color purple_active     ${THEME_ACCENT3};
@define-color border_color      ${THEME_BORDER};
@define-color error_color       ${THEME_STATUS_RED};
@define-color success_color     ${THEME_STATUS_GREEN};
@define-color warning_color     ${THEME_STATUS_YELLOW};

@define-color theme_bg_color                     ${THEME_BG};
@define-color theme_fg_color                     ${THEME_FG};
@define-color theme_base_color                   ${THEME_BG2};
@define-color theme_text_color                   ${THEME_FG};
@define-color theme_selected_bg_color            ${THEME_ACCENT};
@define-color theme_selected_fg_color            ${THEME_BG};
@define-color theme_unfocused_bg_color           ${THEME_BG};
@define-color theme_unfocused_fg_color           ${THEME_FG_DIM};
@define-color theme_unfocused_base_color         ${THEME_BG2};
@define-color theme_unfocused_text_color         ${THEME_FG};
@define-color theme_unfocused_selected_bg_color  ${THEME_ACCENT3};
@define-color theme_unfocused_selected_fg_color  ${THEME_BG};
@define-color theme_tooltip_bg_color             ${THEME_TOOLTIP_BG};
@define-color theme_tooltip_fg_color             ${THEME_TOOLTIP_FG};
@define-color insensitive_bg_color               ${THEME_BG};
@define-color insensitive_fg_color               ${THEME_FG_DIM};
@define-color insensitive_base_color             ${THEME_BG2};
@define-color borders                            ${THEME_BORDER};
@define-color alt_borders                        ${THEME_BORDER};
@define-color borders_edge                       ${THEME_BORDER};
@define-color link_color                         ${THEME_LINK};
@define-color link_visited_color                 ${THEME_ACCENT3};
@define-color sidebar_bg_color                   ${THEME_BG2};
@define-color sidebar_fg_color                   ${THEME_FG};
@define-color sidebar_border_color               ${THEME_BORDER};
@define-color wm_title_focused_bg                ${THEME_BG2};
@define-color wm_title_unfocused_bg              ${THEME_BG};
@define-color wm_title_focused_fg                ${THEME_FG};
@define-color wm_title_unfocused_fg              ${THEME_FG_DIM};
@define-color wm_button_hover_bg                 ${THEME_ACCENT};
@define-color wm_button_close_bg                 ${THEME_STATUS_RED};

/* ── GTK4 / libadwaita: :root tokens ─────────────────────── */
:root {
    --accent-bg-color:          ${THEME_ACCENT};
    --accent-fg-color:          ${THEME_BG};
    --accent-color:             ${THEME_ACCENT2};

    --destructive-bg-color:     ${THEME_STATUS_RED};
    --destructive-fg-color:     ${THEME_BG};
    --destructive-color:        ${THEME_STATUS_RED};

    --success-bg-color:         ${THEME_STATUS_GREEN};
    --success-fg-color:         ${THEME_BG};
    --success-color:            ${THEME_STATUS_GREEN};

    --warning-bg-color:         ${THEME_STATUS_YELLOW};
    --warning-fg-color:         ${THEME_BG};
    --warning-color:            ${THEME_STATUS_YELLOW};

    --error-bg-color:           ${THEME_STATUS_RED};
    --error-fg-color:           ${THEME_BG};
    --error-color:              ${THEME_STATUS_RED};

    --window-bg-color:          ${THEME_BG};
    --window-fg-color:          ${THEME_FG};

    --view-bg-color:            ${THEME_BG2};
    --view-fg-color:            ${THEME_FG};

    --headerbar-bg-color:       ${THEME_BG2};
    --headerbar-fg-color:       ${THEME_FG};
    --headerbar-border-color:   ${THEME_BORDER};
    --headerbar-shade-color:    rgba(0,0,0,0.2);

    --sidebar-bg-color:         ${THEME_BG2};
    --sidebar-fg-color:         ${THEME_FG};
    --sidebar-border-color:     ${THEME_BORDER};

    --card-bg-color:            ${THEME_BG2};
    --card-fg-color:            ${THEME_FG};
    --card-shade-color:         rgba(0,0,0,0.15);

    --dialog-bg-color:          ${THEME_BG};
    --dialog-fg-color:          ${THEME_FG};

    --popover-bg-color:         ${THEME_BG_HOVER};
    --popover-fg-color:         ${THEME_FG};

    --shade-color:              rgba(0,0,0,0.25);
    --scrollbar-outline-color:  rgba(0,0,0,0.3);

    --thumbnail-bg-color:       ${THEME_BG_HOVER};
    --thumbnail-fg-color:       ${THEME_FG};
}

/* ── GTK3/GTK4: Widget selectors ─────────────────────────── */
window, .background { background-color: @bg_color; color: @fg_color; }

headerbar, .titlebar {
    background-color: @bg_alt_color;
    color: @fg_color;
    border-bottom: 1px solid @border_color;
}
headerbar:backdrop, .titlebar:backdrop {
    background-color: @bg_color;
    color: @fg_dim_color;
}

button {
    background-color: @bg_alt_color;
    background-image: none;
    box-shadow: none;
    text-shadow: none;
    color: @fg_color;
    border: 1px solid @border_color;
    border-radius: 5px;
    padding: 4px 10px;
    min-height: 22px;
}
button:hover { background-color: @bg_hover_color; border-color: @selected_bg_color; }
button:active, button:checked { background-color: @purple_active; color: @selected_fg_color; border-color: @selected_bg_color; }
button:disabled { background-color: @bg_color; color: @fg_dim_color; }
button.suggested-action { background-color: @selected_bg_color; color: @selected_fg_color; border-color: @selected_bg_color; }
button.suggested-action:hover { background-color: @purple_hover; border-color: @purple_hover; }
button.destructive-action { background-color: @error_color; color: @selected_fg_color; border-color: @error_color; }

toolbar, .toolbar { background-color: @bg_color; padding: 3px 4px; }
toolbar button { background-color: transparent; border-color: transparent; border-radius: 6px; padding: 4px 6px; }
toolbar button:hover { background-color: @bg_hover_color; border-color: alpha(@selected_bg_color, 0.5); }
toolbar button:checked, toolbar button:active { background-color: @purple_active; border-color: @selected_bg_color; color: @selected_fg_color; }
toolbar separator { background-color: @border_color; min-width: 1px; margin: 4px 4px; }

entry, spinbutton {
    background-color: @bg_alt_color;
    background-image: none;
    box-shadow: none;
    color: @fg_color;
    caret-color: @selected_bg_color;
    border: 1px solid alpha(@fg_dim_color, 0.45);
    border-radius: 5px;
    padding: 4px 8px;
    min-height: 22px;
}
entry:hover, spinbutton:hover { border-color: alpha(@purple_hover, 0.6); }
entry:focus, spinbutton:focus { border-color: @selected_bg_color; box-shadow: 0 0 0 1px alpha(@selected_bg_color, 0.35); }

textview, textview text { background-color: @bg_alt_color; color: @fg_color; caret-color: @selected_bg_color; }
textview border { background-color: transparent; }

selection, entry selection, spinbutton selection, textview text selection,
label selection, .view selection, *:selected {
    background-color: @selected_bg_color;
    color: @selected_fg_color;
}
selection:backdrop, entry selection:backdrop, textview text selection:backdrop,
label selection:backdrop, .view selection:backdrop, *:selected:backdrop {
    background-color: @purple_active;
    color: @selected_fg_color;
}

menubar { background-color: @bg_color; color: @fg_color; }
menubar > menuitem { padding: 4px 8px; border-radius: 5px; }
menubar > menuitem:hover { background-color: @bg_hover_color; color: @fg_color; }

menu, .menu {
    background-color: @bg_alt_color;
    color: @fg_color;
    border: 1px solid alpha(@fg_dim_color, 0.45);
    border-radius: 8px;
    padding: 4px;
}
menuitem { color: @fg_color; background-color: transparent; }
menu menuitem { padding: 5px 10px; border-radius: 5px; }
menuitem:hover { background-color: @selected_bg_color; color: @selected_fg_color; }
menuitem:disabled { color: @fg_dim_color; }
menu separator { background-color: @border_color; min-height: 1px; margin: 4px 6px; }

.sidebar, placessidebar, .placessidebar { background-color: @bg_alt_color; color: @fg_color; border-color: @border_color; }
.sidebar row:hover, placessidebar row:hover { background-color: @bg_hover_color; }
.sidebar row:selected, placessidebar row:selected { background-color: @selected_bg_color; color: @selected_fg_color; }

treeview, treeview.view, .view { background-color: @bg_color; color: @fg_color; }
treeview row { background-color: transparent; color: @fg_color; }
treeview.view:hover, treeview row:hover { background-color: @bg_hover_color; }

treeview.view:selected, treeview.view:selected:focus, treeview.view:selected:hover,
treeview.view row:selected, treeview.view row:selected:focus, treeview.view row:selected:hover,
treeview row:selected, treeview row:selected:focus, treeview row:selected:hover,
iconview:selected, iconview:selected:focus,
.view:selected, .view:selected:focus, .view:selected:hover,
list row:selected, list row:selected:focus, list row:selected:hover,
listbox row:selected, listbox row:selected:focus, listbox row:selected:hover,
row:selected, row:selected:focus, row:selected:hover,
cell:selected, cell:selected:focus {
    background-color: @selected_bg_color;
    color: @selected_fg_color;
}
treeview row:selected label, list row:selected label,
listbox row:selected label, row:selected label, row:selected image {
    color: @selected_fg_color;
}
treeview.view:selected:backdrop, treeview.view row:selected:backdrop,
treeview row:selected:backdrop, iconview:selected:backdrop,
.view:selected:backdrop, list row:selected:backdrop,
listbox row:selected:backdrop, row:selected:backdrop,
cell:selected:backdrop {
    background-color: @purple_active;
    color: @selected_fg_color;
}

treeview.view.expander { -gtk-icon-source: -gtk-icontheme("pan-end-symbolic"); color: @fg_dim_color; }
treeview.view.expander:hover { color: @purple_hover; }
treeview.view.expander:checked { -gtk-icon-source: -gtk-icontheme("pan-down-symbolic"); color: @selected_bg_color; }

treeview header button {
    background-color: @bg_alt_color;
    background-image: none;
    box-shadow: none;
    color: @fg_dim_color;
    padding: 4px 6px;
    min-height: 0;
    border-radius: 0;
    border-style: solid;
    border-width: 0 1px 1px 0;
    border-color: alpha(@fg_dim_color, 0.35);
}
treeview header button:hover { background-color: @bg_hover_color; color: @fg_color; }
treeview header button:active, treeview header button:checked { background-color: @purple_active; color: @selected_fg_color; }

notebook > header { background-color: @bg_alt_color; border-color: @border_color; }
notebook > header > tabs > tab { background-color: transparent; color: @fg_dim_color; padding: 5px 12px; border: 0 solid transparent; border-radius: 0; }
notebook > header > tabs > tab:checked { background-color: @bg_color; color: @fg_color; }
notebook > header > tabs > tab:hover { background-color: @bg_hover_color; color: @fg_color; }
notebook > header.top > tabs > tab:checked    { border-bottom: 2px solid @selected_bg_color; }
notebook > header.bottom > tabs > tab:checked { border-top: 2px solid @selected_bg_color; }
notebook > header.left > tabs > tab:checked   { border-right: 2px solid @selected_bg_color; }
notebook > header.right > tabs > tab:checked  { border-left: 2px solid @selected_bg_color; }

scrolledwindow.frame, scrolledwindow { border-color: alpha(@fg_dim_color, 0.35); }
scrollbar { background-color: transparent; border: none; }
scrollbar trough { background-color: @bg_alt_color; }
scrollbar slider { background-color: @fg_dim_color; background-clip: padding-box; min-width: 8px; min-height: 8px; border: 2px solid transparent; border-radius: 8px; }
scrollbar:hover slider, scrollbar slider:hover { background-color: @purple_hover; }
scrollbar slider:active { background-color: @selected_bg_color; }

tooltip { background-color: @bg_alt_color; color: @fg_color; border-color: @border_color; border-radius: 5px; }
tooltip label { color: @fg_color; background-color: transparent; }

popover { background-color: @bg_alt_color; border-color: @border_color; border-radius: 8px; }

list, listbox { background-color: @bg_color; color: @fg_color; }
list row:hover, listbox row:hover { background-color: @bg_hover_color; }

check:checked, radio:checked { background-color: @selected_bg_color; border-color: @selected_bg_color; color: @selected_fg_color; }
switch:checked { background-color: @selected_bg_color; border-color: @selected_bg_color; }
progressbar progress { background-color: @selected_bg_color; }
progressbar trough { background-color: @bg_alt_color; }
scale trough highlight { background-color: @selected_bg_color; }
scale slider { background-color: @selected_bg_color; border-color: @selected_bg_color; }
paned > separator { background-color: @bg_hover_color; background-image: none; min-width: 3px; min-height: 3px; }
paned > separator:hover { background-color: @selected_bg_color; }
statusbar { background-color: @bg_color; color: @fg_dim_color; padding: 2px 6px; }
label { color: @fg_color; background-color: transparent; }
label.dim-label { color: @fg_dim_color; }
label:disabled { color: @fg_dim_color; }
*:link    { color: @purple_hover; }
*:visited { color: @purple_active; }
EOF
)
    _render_block "$f" "/* BEGIN SNOWFOX PALETTE */" "/* END SNOWFOX PALETTE */" "$content"
}

# ============================================================
#  Renderers — GTK2 (.gtkrc-2.0.mine)
# ============================================================

_render_gtk2() {
    # ~/.gtkrc-2.0 is a static include-only file; we write the actual settings
    # into ~/.gtkrc-2.0.mine so the theme engine owns that file entirely and
    # never has to deal with duplicate keys or partial block replacement.
    local mine
    mine="$(dirname "$1")/.gtkrc-2.0.mine"
    local tmp
    tmp="$(mktemp "$(dirname "$mine")/.gtkrc-2.0.mine.XXXXXX")"

    # Derive a slightly lighter hover bg from BG2 for murrine bg[PRELIGHT].
    # We just use THEME_BG_HOVER which is already derived.
    cat > "$tmp" <<EOF
# SnowFoxOS palette — generated by theme_engine, do not edit

gtk-color-scheme = "bg_color:${THEME_BG}\nbg_alt_color:${THEME_BG2}\nbg_surface:${THEME_BG_HOVER}\nbg_hover:${THEME_BG_HOVER}\nfg_color:${THEME_FG}\nfg_dim_color:${THEME_FG_DIM}\nbase_color:${THEME_BG}\ntext_color:${THEME_FG}\nselected_bg_color:${THEME_ACCENT}\nselected_fg_color:${THEME_BG}\npurple_hover:${THEME_ACCENT2}\npurple_active:${THEME_ACCENT3}\nborder_color:${THEME_BORDER}\ntooltip_bg_color:${THEME_TOOLTIP_BG}\ntooltip_fg_color:${THEME_TOOLTIP_FG}\nlink_color:${THEME_LINK}"

gtk-theme-name = "${THEME_GTK_THEME:-Arc-Dark}"
gtk-icon-theme-name = "${THEME_ICON_THEME:-Papirus-Dark}"
gtk-font-name = "Inter 11"
gtk-cursor-theme-name = "${THEME_GTK_CURSOR:-Bibata-Modern-Classic}"
gtk-cursor-theme-size = 24

style "snowfox-colors" {
    base[NORMAL]      = "${THEME_BG}"
    base[ACTIVE]      = "${THEME_ACCENT3}"
    base[PRELIGHT]    = "${THEME_BG}"
    base[INSENSITIVE] = "${THEME_BG}"
    base[SELECTED]    = "${THEME_ACCENT}"

    bg[NORMAL]        = "${THEME_BG_HOVER}"
    bg[ACTIVE]        = "${THEME_BG2}"
    bg[INSENSITIVE]   = "${THEME_BG}"
    bg[SELECTED]      = "${THEME_ACCENT}"
    bg[PRELIGHT]      = "${THEME_BG_HOVER}"

    text[NORMAL]      = "${THEME_FG}"
    text[ACTIVE]      = "${THEME_BG}"
    text[PRELIGHT]    = "${THEME_FG}"
    text[SELECTED]    = "${THEME_BG}"
    text[INSENSITIVE] = "${THEME_FG_DIM}"

    fg[NORMAL]        = "${THEME_FG}"
    fg[ACTIVE]        = "${THEME_BG}"
    fg[SELECTED]      = "${THEME_BG}"
    fg[PRELIGHT]      = "${THEME_BG}"
    fg[INSENSITIVE]   = "${THEME_FG_DIM}"

    engine "murrine" {
        contrast            = 0.0
        gradient_shades     = { 1.0, 1.0, 1.0, 1.0 }
        lightborder_shade   = 1.0
        border_shades       = { 1.0, 1.0 }
        focus_color         = "${THEME_ACCENT2}"
    }
}

style "snowfox-view" {
    base[NORMAL]      = "${THEME_BG}"
    base[ACTIVE]      = "${THEME_ACCENT3}"
    base[SELECTED]    = "${THEME_ACCENT}"
    bg[NORMAL]        = "${THEME_BG}"
    text[NORMAL]      = "${THEME_FG}"
    text[ACTIVE]      = "${THEME_BG}"
    text[SELECTED]    = "${THEME_BG}"

    GtkTreeView::even-row-color       = "${THEME_BG}"
    GtkTreeView::odd-row-color        = "${THEME_BG}"
    GtkTreeView::vertical-separator   = 4
    GtkTreeView::horizontal-separator = 4
}

style "snowfox-textview" {
    base[NORMAL]      = "${THEME_BG}"
    base[ACTIVE]      = "${THEME_ACCENT3}"
    base[SELECTED]    = "${THEME_ACCENT}"
    text[NORMAL]      = "${THEME_FG}"
    text[ACTIVE]      = "${THEME_BG}"
    text[SELECTED]    = "${THEME_BG}"
}

style "snowfox-sidebar" {
    base[NORMAL]      = "${THEME_BG2}"
    base[ACTIVE]      = "${THEME_ACCENT3}"
    base[SELECTED]    = "${THEME_ACCENT}"
    bg[NORMAL]        = "${THEME_BG2}"
    bg[ACTIVE]        = "${THEME_BG_HOVER}"
    bg[PRELIGHT]      = "${THEME_BG_HOVER}"
    bg[SELECTED]      = "${THEME_ACCENT}"

    text[NORMAL]      = "${THEME_FG}"
    text[ACTIVE]      = "${THEME_BG}"
    text[SELECTED]    = "${THEME_BG}"
    fg[NORMAL]        = "${THEME_FG}"
    fg[PRELIGHT]      = "${THEME_BG}"
    fg[SELECTED]      = "${THEME_BG}"

    GtkScrolledWindow::shadow-type       = GTK_SHADOW_NONE
    GtkScrolledWindow::scrollbar-spacing = 0
    GtkTreeView::shadow-type             = GTK_SHADOW_NONE
    GtkTreeView::vertical-separator      = 5
    GtkTreeView::horizontal-separator    = 6

    engine "murrine" {
        contrast          = 0.0
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        lightborder_shade = 1.0
        roundness         = 6
        focus_color       = "${THEME_BG2}"
    }
}

style "snowfox-bars" {
    bg[NORMAL]        = "${THEME_BG}"
    bg[ACTIVE]        = "${THEME_BG2}"
    bg[PRELIGHT]      = "${THEME_BG_HOVER}"
    fg[NORMAL]        = "${THEME_FG}"

    engine "murrine" {
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        contrast          = 0.0
        lightborder_shade = 1.0
    }
}

style "snowfox-tabs" {
    bg[NORMAL]        = "${THEME_BG}"
    bg[ACTIVE]        = "${THEME_BG_HOVER}"
    bg[PRELIGHT]      = "${THEME_BG_HOVER}"
}

style "snowfox-entry" {
    base[NORMAL]      = "${THEME_BG2}"
    base[ACTIVE]      = "${THEME_ACCENT3}"
    base[SELECTED]    = "${THEME_ACCENT}"
    text[NORMAL]      = "${THEME_FG}"
    text[ACTIVE]      = "${THEME_BG}"
    text[SELECTED]    = "${THEME_BG}"

    engine "murrine" {
        contrast          = 0.0
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        lightborder_shade = 1.0
        border_shades     = { 1.0, 1.0 }
        roundness         = 8
        focus_color       = "${THEME_ACCENT2}"
    }
}

style "snowfox-widgets" {
    bg[NORMAL]        = "${THEME_BG_HOVER}"
    bg[PRELIGHT]      = "${THEME_BG_HOVER}"
    bg[ACTIVE]        = "${THEME_ACCENT}"
    fg[NORMAL]        = "${THEME_FG}"
    fg[PRELIGHT]      = "${THEME_BG}"
    fg[ACTIVE]        = "${THEME_BG}"

    engine "murrine" {
        contrast          = 0.0
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        lightborder_shade = 1.0
        glow_shade        = 1.0
        roundness         = 8
        focus_color       = "${THEME_ACCENT2}"
    }
}

style "snowfox-scrollbar" {
    bg[NORMAL]        = "${THEME_FG_DIM}"
    bg[PRELIGHT]      = "${THEME_ACCENT2}"
    bg[ACTIVE]        = "${THEME_ACCENT}"

    engine "murrine" {
        contrast          = 0.0
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        roundness         = 10
        trough_shades     = { 1.0, 1.0 }
    }
}

style "snowfox-separator" {
    bg[NORMAL]        = "${THEME_BG_HOVER}"
    bg[PRELIGHT]      = "${THEME_ACCENT2}"
    bg[ACTIVE]        = "${THEME_ACCENT}"

    GtkPaned::handle-size = 2

    engine "murrine" {
        contrast          = 0.0
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
    }
}

style "snowfox-menus" {
    base[NORMAL]      = "${THEME_BG_HOVER}"
    bg[NORMAL]        = "${THEME_BG_HOVER}"
    bg[PRELIGHT]      = "${THEME_ACCENT}"
    bg[SELECTED]      = "${THEME_ACCENT}"
    fg[NORMAL]        = "${THEME_FG}"
    fg[PRELIGHT]      = "${THEME_BG}"
    fg[SELECTED]      = "${THEME_BG}"
    text[NORMAL]      = "${THEME_FG}"
    text[PRELIGHT]    = "${THEME_BG}"

    engine "murrine" {
        gradient_shades   = { 1.0, 1.0, 1.0, 1.0 }
        contrast          = 0.0
        roundness         = 6
    }
}

style "snowfox-tooltip" {
    bg[NORMAL]        = "${THEME_TOOLTIP_BG}"
    fg[NORMAL]        = "${THEME_TOOLTIP_FG}"
}

class "GtkWidget"                    style "snowfox-colors"
class "GtkTreeView"                  style "snowfox-view"
class "GtkIconView"                  style "snowfox-view"
class "GtkTextView"                  style "snowfox-textview"
widget_class "*FmFolderView*"        style "snowfox-view"
class "GtkMenuBar"                   style "snowfox-bars"
class "GtkToolbar"                   style "snowfox-bars"
widget_class "*<GtkToolbar>*"        style "snowfox-bars"
class "GtkNotebook"                  style "snowfox-tabs"
class "GtkEntry"                     style "snowfox-entry"
class "GtkButton"                    style "snowfox-widgets"
class "GtkScrollbar"                 style "snowfox-scrollbar"
widget_class "*FmSidePane*"          style:highest "snowfox-sidebar"
widget_class "*FmPlacesView*"        style:highest "snowfox-sidebar"
widget_class "*FmDirTreeView*"       style:highest "snowfox-sidebar"
class "GtkPaned"                     style:highest "snowfox-separator"
widget_class "*<GtkMenu>*"           style:highest "snowfox-menus"
widget_class "*<GtkMenuItem>*"       style:highest "snowfox-menus"
widget "gtk-tooltip*"                style "snowfox-tooltip"
widget "gtk-tooltips*"               style "snowfox-tooltip"
EOF
    chmod 0644 "$tmp"
    mv -f "$tmp" "$mine"
}

# ============================================================
#  Renderers — Qt5ct / Qt6ct
# ============================================================

_render_qtct() {
    local f="$1"
    local content
    content=$(cat <<EOF
[Appearance]
style=gtk2
color_scheme_path=
custom_palette=false
icon_theme=${THEME_ICON_THEME:-Papirus-Dark}
EOF
)
    _render_block "$f" "# BEGIN SNOWFOX PALETTE" "# END SNOWFOX PALETTE" "$content"
}

# ============================================================
#  theme_apply & theme_reset
# ============================================================

theme_apply() {
    local name="$1"
    local file="$THEME_DIR/${name}.theme"
    if [[ ! -r "$file" ]]; then
        echo "theme_apply: theme '$name' not found in $THEME_DIR" >&2
        return 1
    fi
    theme_load "$file" || return 1
    theme_render_all

    # Apply Papirus folder color if the tool is installed
    if command -v papirus-folders >/dev/null 2>&1; then
        papirus-folders -t "$THEME_ICON_THEME" -C "$THEME_ICON_COLOR" -u >/dev/null 2>&1 || true
    fi

    local sel="${TARGET_HOME:-$HOME}/.config/snowfox/theme"
    mkdir -p "$(dirname "$sel")"
    printf '%s\n' "$name" > "$sel"

    # Reload running components so the theme takes effect immediately.
    if command -v pkill >/dev/null 2>&1; then
        # foxdock: SIGHUP triggers palette_reload (live color swap, no restart)
        pkill -HUP -x foxdock 2>/dev/null || true

        # xsettingsd: SIGHUP re-reads its config and broadcasts to all GTK apps
        # via the XSETTINGS protocol — no GTK app restart needed.
        pkill -HUP -x xsettingsd 2>/dev/null || true

        # polybar: must be restarted (no reload signal); the launch script
        # handles monitor detection and kills the old instance.
        local polybar_launch="${CONFIG_ROOT:-${TARGET_HOME:-$HOME}/.config}/polybar/launch.sh"
        if [[ -x "$polybar_launch" ]]; then
            bash "$polybar_launch" &
        else
            pkill -x polybar 2>/dev/null || true
        fi

        # dunst: SIGUSR2 reloads the config file
        pkill -USR2 -x dunst 2>/dev/null || true
    fi
    return 0
}

theme_reset() {
    local default="${1:-nightfox}"
    theme_apply "$default"
}
