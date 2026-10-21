#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Color Themes (snowfox theme)
#  Renders polybar, rofi, kitty, GTK2/3/4, i3, dunst, picom,
#  lock screen and mesh UI from the master palette file:
#      ~/.config/snowfox/palette.conf
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

THEME_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
THEME_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snowfox"
THEME_STATE_FILE="$THEME_STATE_DIR/theme"
THEME_BACKUP_FILE="$THEME_STATE_DIR/theme-backup.tar.gz"

# Files rendered by the theme engine (paths relative to $HOME).
THEME_TARGET_FILES=(
    .config/polybar/config.ini
    .config/polybar/scripts/bluetooth.sh
    .config/polybar/scripts/network-status.sh
    .config/rofi/config.rasi
    .config/kitty/kitty.conf
    .gtkrc-2.0
    .config/gtk-3.0/gtk.css
    .config/gtk-3.0/settings.ini
    .config/gtk-4.0/gtk.css
    .config/gtk-4.0/settings.ini
    .config/xsettingsd/xsettingsd.conf
    .config/i3/config
    .config/dunst/dunstrc
    .config/picom.conf
    .config/snowfox-lock.sh
    .config/snowfox-mesh.sh
    .xinitrc
)

declare -gA THEME_LABEL THEME_DESC THEME_COLOR THEME_UI
declare -ga THEME_LIST THEME_TOKENS THEME_UI_KEYS
THEME_DEFAULT=""
THEME_FILE=""
THEME_APPLY_CHANGED=0
THEME_APPLY_UNCHANGED=0

# ── Palette discovery ────────────────────────────────────────
theme__palette_file() {
    local candidates=(
        "${SNOWFOX_PALETTE:-}"
        "${XDG_CONFIG_HOME:-$HOME/.config}/snowfox/palette.conf"
        "$THEME_MODULE_DIR/../configs/snowfox/palette.conf"
        "/usr/local/share/snowfox/palette.conf"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

# ── Palette parser ───────────────────────────────────────────
# Reads [meta] / [theme:NAME] / [colors:NAME] / [ui:NAME].
theme__load() {
    local file="$1"
    THEME_FILE="$file"
    THEME_LABEL=(); THEME_DESC=(); THEME_COLOR=(); THEME_UI=()
    THEME_LIST=(); THEME_TOKENS=(); THEME_UI_KEYS=()
    THEME_DEFAULT=""

    local line section="" theme="" key="" val="" order=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            case "$section" in
                colors:*|ui:*|theme:*)
                    theme="${section#*:}"
                    [[ " ${THEME_LIST[*]} " == *" $theme "* ]] || THEME_LIST+=("$theme") ;;
            esac
            continue
        fi
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        val="${val%% #*}"                          # drop trailing comment
        val="${val%"${val##*[![:space:]]}"}"       # right-trim
        case "$section" in
            meta)
                [[ "$key" == "default" ]] && THEME_DEFAULT="$val"
                [[ "$key" == "order"   ]] && order="$val" ;;
            theme:*)
                [[ "$key" == "label" ]] && THEME_LABEL["$theme"]="$val"
                [[ "$key" == "desc"  ]] && THEME_DESC["$theme"]="$val" ;;
            colors:*)
                THEME_COLOR["$theme|$key"]="$val"
                [[ " ${THEME_TOKENS[*]} " == *" $key "* ]] || THEME_TOKENS+=("$key") ;;
            ui:*)
                THEME_UI["$theme|$key"]="$val"
                [[ " ${THEME_UI_KEYS[*]} " == *" $key "* ]] || THEME_UI_KEYS+=("$key") ;;
        esac
    done < "$file"

    # meta order wins over discovery order
    if [[ -n "$order" ]]; then
        local -a ordered=()
        local t
        for t in $order; do
            [[ " ${THEME_LIST[*]} " == *" $t "* ]] && ordered+=("$t")
        done
        for t in "${THEME_LIST[@]}"; do
            [[ " ${ordered[*]} " == *" $t "* ]] || ordered+=("$t")
        done
        THEME_LIST=("${ordered[@]}")
    fi

    ((${#THEME_LIST[@]})) || return 1
    [[ -n "$THEME_DEFAULT" ]] || THEME_DEFAULT="${THEME_LIST[0]}"
    return 0
}

theme__load_or_die() {
    local file
    if ! file="$(theme__palette_file)"; then
        err "Palette file not found"
        info "  Expected: ~/.config/snowfox/palette.conf"
        info "  Reinstall configs: cd <repo> && cp configs/snowfox/palette.conf ~/.config/snowfox/"
        return 1
    fi
    if ! theme__load "$file"; then
        err "Could not parse palette: $file"
        return 1
    fi
    return 0
}

theme__exists() {
    local n="$1" t
    for t in "${THEME_LIST[@]}"; do
        [[ "$t" == "$n" ]] && return 0
    done
    return 1
}

# Short aliases -> canonical theme names
theme__resolve() {
    case "$1" in
        default|standard|std) echo "$THEME_DEFAULT" ;;
        mono|bw|sw|black-white) echo "blackwhite" ;;
        light|wb|ws|white-black) echo "whiteblack" ;;
        *) echo "$1" ;;
    esac
}

# ── sed helpers ──────────────────────────────────────────────
theme__esc()  { printf '%s' "$1" | sed 's@[][(){}.*+?^$|\\]@\\&@g'; }
theme__repl() { printf '%s' "$1" | sed 's@[&\\]@\\&@g'; }

# rgba(26, 24, 37, 0.85) -> whitespace tolerant regex
theme__rgba_re() {
    local v="$1" inner r g b a
    inner="${v#rgba(}"; inner="${inner%)}"
    IFS=',' read -r r g b a <<< "$inner"
    r="${r//[[:space:]]/}"; g="${g//[[:space:]]/}"
    b="${b//[[:space:]]/}"; a="${a//[[:space:]]/}"
    a="${a//./[.]}"
    # NOTE: in BRE, plain ( ) are literal — \( \) would open a group
    # and never match the literal parentheses of an rgba() value.
    printf 'rgba( *%s *, *%s *, *%s *, *%s *)' "$r" "$g" "$b" "$a"
}

# Builds the replacement script: every known palette value of the
# source themes maps to the value of the target theme.  Because all
# values of a token are identical across themes or unique, the
# mapping is unambiguous and idempotent (apply twice = apply once).
theme__build_sed() {
    local target="$1" script="$2"
    : > "$script"
    local token theme src tgt
    for token in "${THEME_TOKENS[@]}"; do
        tgt="${THEME_COLOR["$target|$token"]:-}"
        [[ -z "$tgt" ]] && continue
        for theme in "${THEME_LIST[@]}"; do
            src="${THEME_COLOR["$theme|$token"]:-}"
            [[ -z "$src" || "$src" == "$tgt" ]] && continue
            case "$src" in
                \#*)   printf 's/%s\\>/%s/gI\n' "$(theme__esc "$src")" "$(theme__repl "$tgt")" >> "$script" ;;
                rgba*) printf 's/%s/%s/gI\n' "$(theme__rgba_re "$src")" "$(theme__repl "$tgt")" >> "$script" ;;
            esac
        done
    done
}

# ── UI properties (theme names, dark-mode flag) ──────────────
# These are matched on their exact config lines — never globally —
# so that values like "0", "1", "Arc" or "Papirus" can not touch
# unrelated text.  Keys: gtk_theme, icon_theme, prefer_dark.
theme__patch_ui_file() {
    local file="$1" key="$2" val="$3"
    [[ -f "$file" && -n "$val" ]] || return 1
    local -a exprs=()
    case "$key" in
        gtk_theme)
            exprs=(
                's|^\(gtk-theme-name *= *\).*$|\1'"$val"'|'
                's|^\(Net/ThemeName *"\).*\("\)$|\1'"$val"'\2|'
                's|^\(export GTK_THEME=\).*$|\1'"$val"'|'
            ) ;;
        icon_theme)
            exprs=(
                's|^\(gtk-icon-theme-name *= *\).*$|\1'"$val"'|'
                's|^\(Net/IconThemeName *"\).*\("\)$|\1'"$val"'\2|'
                's|^\( *icon-theme: *"\).*\(";\)$|\1'"$val"'\2|'
                's|^\([[:space:]]*icon_theme[[:space:]]*=[[:space:]]*\).*$|\1'"$val"'|'
            ) ;;
        prefer_dark)
            # no backreference: the value is a single digit
            exprs=(
                's|^[[:space:]]*gtk-application-prefer-dark-theme.*$|gtk-application-prefer-dark-theme = '"$val"'|'
            ) ;;
    esac
    ((${#exprs[@]})) || return 1
    local before after expr
    before="$(md5sum "$file" | cut -d' ' -f1)"
    for expr in "${exprs[@]}"; do
        sed -i "$expr" "$file" 2>/dev/null || true
    done
    after="$(md5sum "$file" | cut -d' ' -f1)"
    [[ "$before" != "$after" ]]
}

# Applies all UI keys to the known files.  Prints one line per key.
theme__apply_ui() {
    local target="$1" dry="$2"
    local -A files_for=(
        [gtk_theme]=".config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini .config/xsettingsd/xsettingsd.conf .xinitrc"
        [icon_theme]=".config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini .config/xsettingsd/xsettingsd.conf .config/rofi/config.rasi .config/dunst/dunstrc"
        [prefer_dark]=".config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini"
    )
    local key val rel tmp
    local -a hit
    for key in gtk_theme icon_theme prefer_dark; do
        val="${THEME_UI["$target|$key"]:-}"
        [[ -z "$val" ]] && continue
        hit=()
        for rel in ${files_for[$key]}; do
            [[ -f "$HOME/$rel" ]] || continue
            if [[ "$dry" == "true" ]]; then
                tmp="$(mktemp "${TMPDIR:-/tmp}/snowfox-ui.XXXXXX")"
                cp "$HOME/$rel" "$tmp"
                theme__patch_ui_file "$tmp" "$key" "$val" && hit+=("~/$rel")
                rm -f "$tmp"
            else
                theme__patch_ui_file "$HOME/$rel" "$key" "$val" && hit+=("~/$rel")
            fi
        done
        if ((${#hit[@]})); then
            if [[ "$dry" == "true" ]]; then
                info "  would update  ui · $key → $val"
                info "                ${hit[*]}"
            else
                ok "ui · $key → $val"
            fi
        fi
    done
    return 0
}

# ── File rendering ───────────────────────────────────────────
theme__apply_files() {
    local target="$1" dry="$2"
    local script
    script="$(mktemp "${TMPDIR:-/tmp}/snowfox-theme.XXXXXX")" || return 1
    theme__build_sed "$target" "$script"

    local rel abs before after
    THEME_APPLY_CHANGED=0
    THEME_APPLY_UNCHANGED=0
    for rel in "${THEME_TARGET_FILES[@]}"; do
        abs="$HOME/$rel"
        [[ -f "$abs" ]] || continue
        if [[ "$dry" == "true" ]]; then
            if sed -f "$script" "$abs" | cmp -s - "$abs"; then
                THEME_APPLY_UNCHANGED=$((THEME_APPLY_UNCHANGED + 1))
            else
                info "  would update  ~/$rel"
                THEME_APPLY_CHANGED=$((THEME_APPLY_CHANGED + 1))
            fi
            continue
        fi
        before="$(md5sum "$abs" | cut -d' ' -f1)"
        if ! sed -i -f "$script" "$abs" 2>/dev/null; then
            warn "cannot write ~/$rel"
            continue
        fi
        after="$(md5sum "$abs" | cut -d' ' -f1)"
        if [[ "$before" != "$after" ]]; then
            ok "updated  ~/$rel"
            THEME_APPLY_CHANGED=$((THEME_APPLY_CHANGED + 1))
        else
            THEME_APPLY_UNCHANGED=$((THEME_APPLY_UNCHANGED + 1))
        fi
    done
    rm -f "$script"

    # UI properties (theme names, dark-mode flag) — anchored rules
    theme__apply_ui "$target" "$dry"
    return 0
}

# ── Backup / state ───────────────────────────────────────────
theme__backup() {
    mkdir -p "$THEME_STATE_DIR" 2>/dev/null || return 0
    local -a present=()
    local rel
    for rel in "${THEME_TARGET_FILES[@]}"; do
        [[ -f "$HOME/$rel" ]] && present+=("$rel")
    done
    ((${#present[@]})) || return 0
    tar -czf "$THEME_BACKUP_FILE" -C "$HOME" "${present[@]}" 2>/dev/null || true
}

theme__save_state() {
    mkdir -p "$THEME_STATE_DIR" 2>/dev/null || return 0
    printf '%s\n' "$1" > "$THEME_STATE_FILE"
}

theme__current() {
    local t=""
    [[ -f "$THEME_STATE_FILE" ]] && t="$(head -n1 "$THEME_STATE_FILE" | tr -d '[:space:]')"
    if [[ -z "$t" ]] || ! theme__exists "$t"; then t="$THEME_DEFAULT"; fi
    printf '%s\n' "$t"
}

# ── Swatches (truecolor) ─────────────────────────────────────
theme__swatch() {
    local hex="${THEME_COLOR["$1|$2"]:-}"
    [[ -z "$hex" ]] && return 0
    local r g b
    if [[ "$hex" == \#* ]]; then
        hex="${hex: -6}"
        r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
    elif [[ "$hex" == rgba* ]]; then
        local inner="${hex#rgba(}"; inner="${inner%)}"
        local -a p; IFS=',' read -ra p <<< "$inner"
        r="${p[0]// /}"; g="${p[1]// /}"; b="${p[2]// /}"
    else
        return 0
    fi
    printf '\033[48;2;%d;%d;%dm   \033[0m' "$r" "$g" "$b"
}

# Swatch row used in lists: bg | accent | accent_lt | fg | cyan
theme__swatch_row() {
    local t="$1" k
    for k in bg accent accent_lt fg cyan; do
        theme__swatch "$t" "$k"
    done
    printf '\033[0m'
}

# ── Side effects ─────────────────────────────────────────────
theme__ui_effects() {
    local target="$1"
    local gtk="${THEME_UI["$target|gtk_theme"]:-}"
    local scheme="${THEME_UI["$target|color_scheme"]:-}"
    local icon="${THEME_UI["$target|icon_theme"]:-}"
    local folder="${THEME_UI["$target|folder_color"]:-}"

    if command -v gsettings &>/dev/null; then
        [[ -n "$scheme" ]] && gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || true
        [[ -n "$gtk"    ]] && gsettings set org.gnome.desktop.interface gtk-theme "$gtk" 2>/dev/null || true
        [[ -n "$icon"   ]] && gsettings set org.gnome.desktop.interface icon-theme "$icon" 2>/dev/null || true
    fi
    if command -v papirus-folders &>/dev/null && [[ -n "$folder" && -n "$icon" ]]; then
        papirus-folders -t "$icon" -C "$folder" -u &>/dev/null || true
    fi
}

theme__reload() {
    [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]] || return 0
    if command -v i3-msg &>/dev/null; then
        i3-msg reload &>/dev/null || true
    fi
    if command -v dunst &>/dev/null; then
        pkill -x dunst 2>/dev/null || true
        sleep 0.2
        nohup dunst &>/dev/null &
        disown 2>/dev/null || true
    fi
    if command -v xsettingsd &>/dev/null; then
        pkill -x xsettingsd 2>/dev/null || true
        sleep 0.2
        nohup xsettingsd &>/dev/null &
        disown 2>/dev/null || true
    fi
    if [[ -x "$HOME/.config/polybar/launch.sh" ]]; then
        nohup "$HOME/.config/polybar/launch.sh" &>/dev/null &
        disown 2>/dev/null || true
    fi
    pkill -SIGUSR1 -x kitty 2>/dev/null || true
    return 0
}

# ── Apply driver ─────────────────────────────────────────────
theme__apply() {
    local name="$1"; shift
    local dry="false" reload="true" arg
    for arg in "$@"; do
        case "$arg" in
            -n|--dry-run) dry="true" ;;
            --no-reload)  reload="false" ;;
            *) err "Unknown option: $arg"; return 1 ;;
        esac
    done

    theme__load_or_die || return 1

    local target
    target="$(theme__resolve "$name")"
    if ! theme__exists "$target"; then
        err "Unknown theme: $name"
        info "  Available: ${THEME_LIST[*]}"
        info "  Aliases:   default · mono · light"
        return 1
    fi

    local current
    current="$(theme__current)"

    header "Color Theme"
    row "From" "$current — ${THEME_LABEL[$current]:-}"
    row "To"   "$target — ${THEME_LABEL[$target]:-}"
    echo ""

    if [[ "$dry" == "true" ]]; then
        info "Dry run — no files are changed:"
    elif [[ "$current" != "$target" ]]; then
        theme__backup
    fi

    theme__apply_files "$target" "$dry"
    echo ""

    if [[ "$dry" == "true" ]]; then
        info "  ${THEME_APPLY_CHANGED} file(s) would change · ${THEME_APPLY_UNCHANGED} unchanged"
        return 0
    fi

    theme__save_state "$target"

    if [[ "$reload" == "true" ]]; then
        theme__ui_effects "$target"
        theme__reload
        ok "Theme '$target' applied — desktop reloaded"
        info "  GTK apps need a restart (or relogin) to pick up new colors"
    else
        ok "Theme '$target' applied (${THEME_APPLY_CHANGED} file(s) updated)"
    fi
    info "  Backup:  ${THEME_BACKUP_FILE/#$HOME/~}"
    info "  Palette: snowfox theme show $target"
    return 0
}

# ============================================================
# snowfox theme — dispatcher
# ============================================================
cmd_theme() {
    local sub="${1:-}"
    case "$sub" in
        ""|list|ls)      cmd_theme_list ;;
        current)         theme__load_or_die || return 1; theme__current ;;
        apply|set|use)   theme__apply "${2:-}" "${@:3}" ;;
        reset)
            # Load the palette first, then resolve the default name from it.
            # (Never capture theme__load_or_die — its diagnostics must not
            #  become the theme name.)
            theme__load_or_die || return 1
            theme__apply "$THEME_DEFAULT" "${@:2]}"
            ;;
        show|info|preview) cmd_theme_show "${2:-}" ;;
        color|colour)    cmd_theme_color "${2:-}" "${3:-}" ;;
        gui|picker)      cmd_theme_gui ;;
        check|validate)  cmd_theme_check ;;
        h|help|-h|--help) cmd_theme_help ;;
        *)
            theme__load_or_die || return 1
            if theme__exists "$(theme__resolve "$sub")"; then
                theme__apply "$sub" "${@:2}"
            else
                err "Unknown theme: $sub"
                info "  Available: ${THEME_LIST[*]}"
                info "  Aliases:   default · mono · light"
                info "  Help:      snowfox theme help"
                return 1
            fi ;;
    esac
}

# ============================================================
# snowfox theme list
# ============================================================
cmd_theme_list() {
    theme__load_or_die || return 1
    local current
    current="$(theme__current)"

    header "Color Themes"
    row "Current" "$current — ${THEME_LABEL[$current]:-}"
    row "Palette" "${THEME_FILE/#$HOME/~}"
    echo ""
    section "Available Themes"

    local t mark
    for t in "${THEME_LIST[@]}"; do
        if [[ "$t" == "$current" ]]; then mark="●"; else mark="○"; fi
        printf '  %s %-12s %-30s ' "$mark" "$t" "${THEME_LABEL[$t]:-}"
        theme__swatch_row "$t"
        printf '\n'
        [[ -n "${THEME_DESC[$t]:-}" ]] && hint "${THEME_DESC[$t]}"
    done

    divider
    info "Apply:   snowfox theme <name>"
    info "Preview: snowfox theme show <name>   ·   GUI: snowfox theme gui"
    echo ""
}

# ============================================================
# snowfox theme show [name]
# ============================================================
cmd_theme_show() {
    theme__load_or_die || return 1
    local name="${1:-}"
    local t
    if [[ -z "$name" ]]; then
        t="$(theme__current)"
    else
        t="$(theme__resolve "$name")"
        if ! theme__exists "$t"; then
            err "Unknown theme: $name"
            info "  Available: ${THEME_LIST[*]}"
            return 1
        fi
    fi

    header "Palette — $t"
    row "Label" "${THEME_LABEL[$t]:-}"
    row "Info"  "${THEME_DESC[$t]:-}"
    echo ""
    section "Colors"

    local token val
    for token in "${THEME_TOKENS[@]}"; do
        val="${THEME_COLOR["$t|$token"]:-}"
        [[ -z "$val" ]] && continue
        printf '  \033[2m%-14s\033[0m %-26s ' "$token" "$val"
        theme__swatch "$t" "$token"
        printf '\n'
    done

    echo ""
    section "UI Properties"
    local key
    for key in "${THEME_UI_KEYS[@]}"; do
        printf '  \033[2m%-14s\033[0m %s\n' "$key" "${THEME_UI["$t|$key"]:-}"
    done
    echo ""
}

# ============================================================
# snowfox theme color <token> [theme]
# ============================================================
cmd_theme_color() {
    theme__load_or_die || return 1
    local token="${1:-}" name="${2:-}" t
    if [[ -z "$token" ]]; then
        err "Usage: snowfox theme color <token> [theme]"
        info "  Tokens: ${THEME_TOKENS[*]}"
        return 1
    fi
    t="${name:-$(theme__current)}"
    t="$(theme__resolve "$t")"
    if [[ -z "${THEME_COLOR["$t|$token"]:-}" ]]; then
        err "Unknown token '$token' for theme '$t'"
        info "  Tokens: ${THEME_TOKENS[*]}"
        return 1
    fi
    printf '%s\n' "${THEME_COLOR["$t|$token"]}"
}

# ============================================================
# snowfox theme gui — Rofi picker
# ============================================================
cmd_theme_gui() {
    theme__load_or_die || return 1

    if ! command -v rofi &>/dev/null; then
        err "Rofi not installed — use: snowfox theme <name>"
        return 1
    fi
    if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" ]]; then
        err "No graphical session — use: snowfox theme <name>"
        return 1
    fi

    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    [[ -f "$ROFI_THEME" ]] || ROFI_THEME=""

    while true; do
        local current rows t mark line
        current="$(theme__current)"
        rows=""
        for t in "${THEME_LIST[@]}"; do
            if [[ "$t" == "$current" ]]; then mark="●"; else mark="○"; fi
            line="$(printf '%s  %s  %s   ' "$t" "$mark" "${THEME_LABEL[$t]:-}")"
            local k
            for k in bg accent accent_lt fg cyan; do
                line+="<span foreground='${THEME_COLOR["$t|$k"]}' background='${THEME_COLOR["$t|$k"]}'>   </span>"
            done
            rows+="$line"$'\n'
        done

        local choice
        choice="$(printf '%s' "$rows" | rofi -dmenu -markup-rows -i \
            -p "🦊 Theme" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 520 -lines 6)" || return 0
        [[ -z "$choice" ]] && return 0

        local picked
        picked="$(printf '%s' "$choice" | awk '{print $1}')"
        theme__exists "$picked" || continue
        [[ "$picked" == "$current" ]] && continue

        theme__apply "$picked"
        notify-send "🦊 SnowFox" "Theme: ${THEME_LABEL[$picked]:-$picked}" 2>/dev/null || true
    done
}

# ============================================================
# snowfox theme check — validate the master palette
# ============================================================
cmd_theme_check() {
    theme__load_or_die || return 1
    local errors=0 warnings=0
    header "Palette Check"
    info "File: ${THEME_FILE/#$HOME/~}"
    echo ""

    # 1 — every theme defines every token
    section "Completeness"
    local base="${THEME_LIST[0]}" token theme
    for theme in "${THEME_LIST[@]}"; do
        local missing=()
        for token in "${THEME_TOKENS[@]}"; do
            [[ -z "${THEME_COLOR["$theme|$token"]:-}" ]] && missing+=("$token")
        done
        if ((${#missing[@]})); then
            warn "$theme: missing ${missing[*]}"
            errors=$((errors + 1))
        else
            ok "$theme — ${#THEME_TOKENS[@]} color tokens, ${#THEME_UI_KEYS[@]} UI keys"
        fi
    done

    # 2 — value uniqueness: a value may not belong to two different
    #     tokens whose values differ in any other theme
    section "Uniqueness"
    declare -A vtok=()
    local key val norm toks
    for theme in "${THEME_LIST[@]}"; do
        for key in "${THEME_TOKENS[@]}"; do
            val="${THEME_COLOR["$theme|$key"]:-}"
            [[ -z "$val" ]] && continue
            norm="$(printf '%s' "$val" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
            toks="${vtok[$norm]:-}"
            [[ " $toks " == *" $key "* ]] || vtok["$norm"]="$toks $key"
        done
    done
    local t2 v prev bad shared=0
    for norm in "${!vtok[@]}"; do
        # shellcheck disable=SC2086
        set -- ${vtok[$norm]}
        (($# > 1)) || continue
        bad=""
        for t2 in "${THEME_LIST[@]}"; do
            prev=""
            for key in "$@"; do
                v="${THEME_COLOR["$t2|$key"]:-}"
                [[ -n "$prev" && "$v" != "$prev" ]] && bad="$t2"
                prev="$v"
            done
        done
        if [[ -n "$bad" ]]; then
            warn "value '$norm' used by tokens:$* — but they differ in theme '$bad'"
            errors=$((errors + 1))
        else
            shared=$((shared + 1))
            info "  '$norm' shared by tokens:$* — identical in every theme (harmless)"
        fi
    done
    if [[ $errors -eq 0 ]]; then
        ok "all color values map unambiguously (${shared} shared value(s))"
    fi

    # 3 — default theme is valid
    section "Meta"
    if theme__exists "$THEME_DEFAULT"; then
        ok "default theme: $THEME_DEFAULT"
    else
        warn "default theme '$THEME_DEFAULT' is not defined"
        errors=$((errors + 1))
    fi
    info "themes: ${THEME_LIST[*]}"

    # 4 — scan configs for unknown colors
    section "Config Scan"
    declare -A known=()
    for theme in "${THEME_LIST[@]}"; do
        for key in "${THEME_TOKENS[@]}"; do
            val="${THEME_COLOR["$theme|$key"]:-}"
            [[ -z "$val" ]] && continue
            known["$(printf '%s' "$val" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"]=1
        done
    done
    local rel abs m mn
    for rel in "${THEME_TARGET_FILES[@]}"; do
        abs="$HOME/$rel"
        [[ -f "$abs" ]] || continue
        while IFS= read -r m; do
            [[ -z "$m" ]] && continue
            mn="$(printf '%s' "$m" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
            [[ -n "${known[$mn]:-}" ]] && continue
            warnings=$((warnings + 1))
            info "  ~/$rel: $m  (not in palette — left untouched)"
        done < <(grep -oE '#[0-9a-fA-F]{6,8}\b|rgba\([^)]*\)' "$abs" 2>/dev/null | sort -u)
    done
    if [[ $warnings -eq 0 ]]; then
        ok "every color in the desktop configs is covered by the palette"
    else
        info "  ${warnings} color(s) are intentionally theme-independent"
    fi

    echo ""
    if [[ $errors -eq 0 ]]; then
        ok "Palette OK — ${#THEME_LIST[@]} themes · $((errors)) errors · $((warnings)) notes"
        return 0
    fi
    err "Palette has ${errors} error(s)"
    return 1
}

# ============================================================
# snowfox theme help
# ============================================================
cmd_theme_help() {
    header "Theme Help"
    section "Commands"
    printf '  %-34s %s\n' "snowfox theme"                 "List themes & current one"
    printf '  %-34s %s\n' "snowfox theme <name>"          "Apply a theme (aliases: default, mono, light)"
    printf '  %-34s %s\n' "snowfox theme apply <name>"    "Same, with options:"
    printf '  %-34s %s\n' "  --dry-run, -n"               "Show what would change, touch nothing"
    printf '  %-34s %s\n' "  --no-reload"                 "Do not restart polybar/dunst/i3"
    printf '  %-34s %s\n' "snowfox theme show [name]"     "Full palette of a theme (with swatches)"
    printf '  %-34s %s\n' "snowfox theme gui"             "Theme picker in Rofi"
    printf '  %-34s %s\n' "snowfox theme color <token> [theme]" "Print one color value (for scripts)"
    printf '  %-34s %s\n' "snowfox theme check"           "Validate palette.conf (unique values, coverage)"
    printf '  %-34s %s\n' "snowfox theme reset"           "Back to the default theme"
    echo ""
    section "How it works"
    info "  ~/.config/snowfox/palette.conf is the single source of truth."
    info "  Every themed file is rendered from it by replacing known palette"
    info "  values — user edits to the configs are preserved, switching back"
    info "  and forth is lossless (a backup is kept in ~/.config/snowfox/)."
    echo ""
}
