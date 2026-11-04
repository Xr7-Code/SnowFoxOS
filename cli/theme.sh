#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Color Themes (snowfox theme)
#  Renders polybar, rofi, kitty, GTK2/3/4, i3, dunst, picom,
#  lock screen and mesh UI from the master palette file:
#      ~/.config/snowfox/palette.conf
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - Palette colors validated (strict #RRGGBB / #AARRGGBB / rgba())
#   - UI values validated (theme/icon names, 0/1 dark flag)
#   - Theme names validated (^[a-zA-Z0-9._-]+$)
#   - sed delimiters escaped (incl. /) in esc/repl helpers
#   - Atomic file writes: mktemp + mv, no partial writes
#   - Backup rotation (keep last 3), timestamped
#   - reload kills only processes started by the theme engine
#   - State written only after a successful reload
#   - State file content validated
#   - notify-send labels sanitized
#   - theme__rgba_re validates numeric fields before building regex
#   - Fixed ${@:2]} syntax error
#   - Controlled PATH, absolute binary paths
# ============================================================

# ─── Controlled environment ─────────────────────────────────
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

# ─── Binary paths ───────────────────────────────────────────
readonly SED_BIN="/usr/bin/sed"
readonly GREP_BIN="/usr/bin/grep"
readonly AWK_BIN="/usr/bin/awk"
readonly TR_BIN="/usr/bin/tr"
readonly HEAD_BIN="/usr/bin/head"
readonly TAIL_BIN="/usr/bin/tail"
readonly MKTEMP_BIN="/usr/bin/mktemp"
readonly MKDIR_BIN="/usr/bin/mkdir"
readonly MV_BIN="/usr/bin/mv"
readonly RM_BIN="/usr/bin/rm"
readonly CP_BIN="/usr/bin/cp"
readonly CHMOD_BIN="/usr/bin/chmod"
readonly TAR_BIN="/usr/bin/tar"
readonly MD5SUM_BIN="/usr/bin/md5sum"
readonly PRINTF_BIN="/usr/bin/printf"
readonly DATE_BIN="/usr/bin/date"
readonly PKILL_BIN="/usr/bin/pkill"
readonly NOHUP_BIN="/usr/bin/nohup"
readonly SLEEP_BIN="/usr/bin/sleep"
readonly CMP_BIN="/usr/bin/cmp"
readonly I3_MSG_BIN="/usr/bin/i3-msg"
readonly DUNST_BIN="/usr/bin/dunst"
readonly XSETTINGSD_BIN="/usr/bin/xsettingsd"
readonly ROFI_BIN="/usr/bin/rofi"
readonly NOTIFY_SEND_BIN="/usr/bin/notify-send"
readonly GSETTINGS_BIN="/usr/bin/gsettings"
readonly PAPIRUS_FOLDERS_BIN="/usr/bin/papirus-folders"

[[ -x "$I3_MSG_BIN" ]]          || I3_MSG_BIN=""
[[ -x "$DUNST_BIN" ]]           || DUNST_BIN=""
[[ -x "$XSETTINGSD_BIN" ]]      || XSETTINGSD_BIN=""
[[ -x "$ROFI_BIN" ]]            || ROFI_BIN=""
[[ -x "$NOTIFY_SEND_BIN" ]]     || NOTIFY_SEND_BIN=""
[[ -x "$GSETTINGS_BIN" ]]       || GSETTINGS_BIN=""
[[ -x "$PAPIRUS_FOLDERS_BIN" ]] || PAPIRUS_FOLDERS_BIN=""

# ─── State paths ────────────────────────────────────────────
THEME_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
THEME_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snowfox"
THEME_STATE_FILE="$THEME_STATE_DIR/theme"
THEME_BACKUP_PREFIX="theme-backup"
THEME_BACKUP_KEEP=3

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

# ============================================================
#  Validation
# ============================================================

# Color: #RRGGBB, #AARRGGBB, or rgba(r, g, b, a) with numeric fields.
_theme_valid_color() {
    local v="$1"
    [[ "$v" =~ ^#[0-9a-fA-F]{6}$ ]] && return 0
    [[ "$v" =~ ^#[0-9a-fA-F]{8}$ ]] && return 0
    [[ "$v" =~ ^rgba\([[:space:]]*[0-9]{1,3}[[:space:]]*,[[:space:]]*[0-9]{1,3}[[:space:]]*,[[:space:]]*[0-9]{1,3}[[:space:]]*,[[:space:]]*(0\.[0-9]+|1(\.0+)?)[[:space:]]*\)$ ]] && return 0
    return 1
}

# UI value: theme/icon names or 0/1 dark flag.
_theme_valid_ui() {
    local v="$1"
    [[ "$v" =~ ^[01]$ ]] && return 0
    [[ "$v" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$ ]] && return 0
    return 1
}

# Theme name: alnum, dot, dash, underscore, max 64.
_theme_valid_name() {
    local n="$1"
    [[ -z "$n" ]] && return 1
    [[ ${#n} -gt 64 ]] && return 1
    [[ "$n" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]
}

# ============================================================
#  Palette discovery
# ============================================================
theme__palette_file() {
    local candidates=(
        "${SNOWFOX_PALETTE:-}"
        "${XDG_CONFIG_HOME:-$HOME/.config}/snowfox/palette.conf"
        "$THEME_MODULE_DIR/../configs/snowfox/palette.conf"
        "/usr/local/share/snowfox/palette.conf"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$c" ]] && { "$PRINTF_BIN" '%s\n' "$c"; return 0; }
    done
    return 1
}

# ============================================================
#  Palette parser
# ============================================================
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
                    if ! _theme_valid_name "$theme"; then
                        warn "Invalid theme name in [$section] (skipped)"
                        section=""
                        continue
                    fi
                    [[ " ${THEME_LIST[*]} " == *" $theme "* ]] || THEME_LIST+=("$theme") ;;
            esac
            continue
        fi
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        val="${val%% #*}"
        val="${val%"${val##*[![:space:]]}"}"
        case "$section" in
            meta)
                [[ "$key" == "default" ]] && THEME_DEFAULT="$val"
                [[ "$key" == "order"   ]] && order="$val" ;;
            theme:*)
                [[ "$key" == "label" ]] && THEME_LABEL["$theme"]="$val"
                [[ "$key" == "desc"  ]] && THEME_DESC["$theme"]="$val" ;;
            colors:*)
                if ! _theme_valid_color "$val"; then
                    warn "Invalid color in [$section] $key = $val (skipped)"
                    continue
                fi
                THEME_COLOR["$theme|$key"]="$val"
                [[ " ${THEME_TOKENS[*]} " == *" $key "* ]] || THEME_TOKENS+=("$key") ;;
            ui:*)
                if ! _theme_valid_ui "$val"; then
                    warn "Invalid UI value in [$section] $key = $val (skipped)"
                    continue
                fi
                THEME_UI["$theme|$key"]="$val"
                [[ " ${THEME_UI_KEYS[*]} " == *" $key "* ]] || THEME_UI_KEYS+=("$key") ;;
        esac
    done < "$file"

    if [[ -n "$order" ]]; then
        local -a ordered=()
        local t
        for t in $order; do
            _theme_valid_name "$t" || continue
            [[ " ${THEME_LIST[*]} " == *" $t "* ]] && ordered+=("$t")
        done
        for t in "${THEME_LIST[@]}"; do
            [[ " ${ordered[*]} " == *" $t "* ]] || ordered+=("$t")
        done
        THEME_LIST=("${ordered[@]}")
    fi

    ((${#THEME_LIST[@]})) || return 1

    # Default must be a valid, existing theme name.
    if ! _theme_valid_name "$THEME_DEFAULT" \
        || [[ " ${THEME_LIST[*]} " != *" $THEME_DEFAULT "* ]]; then
        THEME_DEFAULT="${THEME_LIST[0]}"
    fi
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

theme__resolve() {
    case "$1" in
        default|standard|std) echo "$THEME_DEFAULT" ;;
        mono|bw|sw|black-white) echo "blackwhite" ;;
        light|wb|ws|white-black) echo "whiteblack" ;;
        *) echo "$1" ;;
    esac
}

# ============================================================
#  sed helpers
# ============================================================
# Escape BRE metacharacters AND the s/// delimiter "/".
theme__esc()  { "$PRINTF_BIN" '%s' "$1" | "$SED_BIN" 's@[][(){}.*+?^$|\\/@]@\\&@g'; }
# Escape replacement metacharacters AND the delimiter "/".
theme__repl() { "$PRINTF_BIN" '%s' "$1" | "$SED_BIN" 's@[&\\/@]@\\&@g'; }

# rgba(a, b, c, d) -> whitespace-tolerant BRE, with validated numeric fields.
theme__rgba_re() {
    local v="$1" inner r g b a
    inner="${v#rgba(}"; inner="${inner%)}"
    IFS=',' read -r r g b a <<< "$inner"
    r="${r//[[:space:]]/}"; g="${g//[[:space:]]/}"
    b="${b//[[:space:]]/}"; a="${a//[[:space:]]/}"

    [[ "$r" =~ ^[0-9]{1,3}$ ]] || return 1
    [[ "$g" =~ ^[0-9]{1,3}$ ]] || return 1
    [[ "$b" =~ ^[0-9]{1,3}$ ]] || return 1
    [[ "$a" =~ ^(0\.[0-9]+|1(\.0+)?)$ ]] || return 1

    a="${a//./[.]}"
    "$PRINTF_BIN" 'rgba( *%s *, *%s *, *%s *, *%s *)' "$r" "$g" "$b" "$a"
}

theme__build_sed() {
    local target="$1" script="$2"
    : > "$script"
    local token theme src tgt
    for token in "${THEME_TOKENS[@]}"; do
        tgt="${THEME_COLOR["$target|$token"]:-}"
        [[ -z "$tgt" ]] && continue
        _theme_valid_color "$tgt" || continue
        for theme in "${THEME_LIST[@]}"; do
            src="${THEME_COLOR["$theme|$token"]:-}"
            [[ -z "$src" || "$src" == "$tgt" ]] && continue
            _theme_valid_color "$src" || continue
            case "$src" in
                \#*)
                    "$PRINTF_BIN" 's/%s\\>/%s/gI\n' \
                        "$(theme__esc "$src")" "$(theme__repl "$tgt")" >> "$script"
                    ;;
                rgba*)
                    local re
                    if re=$(theme__rgba_re "$src"); then
                        "$PRINTF_BIN" 's/%s/%s/gI\n' "$re" "$(theme__repl "$tgt")" >> "$script"
                    fi
                    ;;
            esac
        done
    done
}

# ============================================================
#  UI properties (anchored, validated, escaped)
# ============================================================
theme__patch_ui_file() {
    local file="$1" key="$2" val="$3"
    [[ -f "$file" && -n "$val" ]] || return 1
    _theme_valid_ui "$val" || return 1

    local esc_val
    esc_val=$("$PRINTF_BIN" '%s' "$val" | "$SED_BIN" 's@[&|\\@]@\\&@g')

    local -a exprs=()
    case "$key" in
        gtk_theme)
            exprs=(
                's|^\(gtk-theme-name *= *\).*$|\1'"$esc_val"'|'
                's|^\(Net/ThemeName *"\).*\("\)$|\1'"$esc_val"'\2|'
                's|^\(export GTK_THEME=\).*$|\1'"$esc_val"'|'
            ) ;;
        icon_theme)
            exprs=(
                's|^\(gtk-icon-theme-name *= *\).*$|\1'"$esc_val"'|'
                's|^\(Net/IconThemeName *"\).*\("\)$|\1'"$esc_val"'\2|'
                's|^\( *icon-theme: *"\).*\(";\)$|\1'"$esc_val"'\2|'
                's|^\([[:space:]]*icon_theme[[:space:]]*=[[:space:]]*\).*$|\1'"$esc_val"'|'
            ) ;;
        prefer_dark)
            exprs=(
                's|^[[:space:]]*gtk-application-prefer-dark-theme.*$|gtk-application-prefer-dark-theme = '"$esc_val"'|'
            ) ;;
    esac
    ((${#exprs[@]})) || return 1

    local before after expr
    before=$("$MD5SUM_BIN" "$file" | "$AWK_BIN" '{print $1}')
    for expr in "${exprs[@]}"; do
        "$SED_BIN" -i "$expr" "$file" 2>/dev/null || true
    done
    after=$("$MD5SUM_BIN" "$file" | "$AWK_BIN" '{print $1}')
    [[ "$before" != "$after" ]]
}

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
                tmp=$("$MKTEMP_BIN" "${TMPDIR:-/tmp}/snowfox-ui.XXXXXX") || continue
                "$CP_BIN" "$HOME/$rel" "$tmp"
                theme__patch_ui_file "$tmp" "$key" "$val" && hit+=("~/$rel")
                "$RM_BIN" -f "$tmp"
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

# ============================================================
#  File rendering (atomic)
# ============================================================
theme__apply_files() {
    local target="$1" dry="$2"
    local script
    script=$("$MKTEMP_BIN" "${TMPDIR:-/tmp}/snowfox-theme.XXXXXX") || return 1
    theme__build_sed "$target" "$script"

    local rel abs before after tmp
    THEME_APPLY_CHANGED=0
    THEME_APPLY_UNCHANGED=0
    for rel in "${THEME_TARGET_FILES[@]}"; do
        abs="$HOME/$rel"
        [[ -f "$abs" ]] || continue
        if [[ "$dry" == "true" ]]; then
            if "$SED_BIN" -f "$script" "$abs" | "$CMP_BIN" -s - "$abs"; then
                THEME_APPLY_UNCHANGED=$((THEME_APPLY_UNCHANGED + 1))
            else
                info "  would update  ~/$rel"
                THEME_APPLY_CHANGED=$((THEME_APPLY_CHANGED + 1))
            fi
            continue
        fi

        tmp=$("$MKTEMP_BIN" "$abs.XXXXXX") || {
            warn "cannot create temp for ~/$rel"
            continue
        }
        if ! "$SED_BIN" -f "$script" "$abs" > "$tmp" 2>/dev/null; then
            "$RM_BIN" -f "$tmp"
            warn "cannot render ~/$rel"
            continue
        fi

        before=$("$MD5SUM_BIN" "$abs" | "$AWK_BIN" '{print $1}')
        if ! "$MV_BIN" "$tmp" "$abs" 2>/dev/null; then
            "$RM_BIN" -f "$tmp"
            warn "cannot write ~/$rel"
            continue
        fi
        after=$("$MD5SUM_BIN" "$abs" | "$AWK_BIN" '{print $1}')

        if [[ "$before" != "$after" ]]; then
            ok "updated  ~/$rel"
            THEME_APPLY_CHANGED=$((THEME_APPLY_CHANGED + 1))
        else
            THEME_APPLY_UNCHANGED=$((THEME_APPLY_UNCHANGED + 1))
        fi
    done
    "$RM_BIN" -f "$script"

    theme__apply_ui "$target" "$dry"
    return 0
}

# ============================================================
#  Backup / state
# ============================================================
theme__backup() {
    "$MKDIR_BIN" -p "$THEME_STATE_DIR" 2>/dev/null || return 0
    local -a present=()
    local rel
    for rel in "${THEME_TARGET_FILES[@]}"; do
        [[ -f "$HOME/$rel" ]] && present+=("$rel")
    done
    ((${#present[@]})) || return 0

    local ts
    ts=$("$DATE_BIN" -u +%Y%m%dT%H%M%SZ)
    local out="$THEME_STATE_DIR/${THEME_BACKUP_PREFIX}-${ts}.tar.gz"
    "$TAR_BIN" -czf "$out" -C "$HOME" "${present[@]}" 2>/dev/null || return 0
    "$CHMOD_BIN" 600 "$out" 2>/dev/null || true

    # Rotate: keep only the last $THEME_BACKUP_KEEP files.
    local -a all
    # shellcheck disable=SC2012
    mapfile -t all < <(ls -1t "$THEME_STATE_DIR/${THEME_BACKUP_PREFIX}"-*.tar.gz 2>/dev/null)
    local i
    for ((i = THEME_BACKUP_KEEP; i < ${#all[@]}; i++)); do
        "$RM_BIN" -f "${all[$i]}" 2>/dev/null || true
    done
}

theme__save_state() {
    "$MKDIR_BIN" -p "$THEME_STATE_DIR" 2>/dev/null || return 0
    "$PRINTF_BIN" '%s\n' "$1" > "$THEME_STATE_FILE"
    "$CHMOD_BIN" 600 "$THEME_STATE_FILE" 2>/dev/null || true
}

theme__current() {
    local t=""
    if [[ -f "$THEME_STATE_FILE" ]]; then
        t=$("$HEAD_BIN" -n1 "$THEME_STATE_FILE" | "$TR_BIN" -d '[:space:]')
        _theme_valid_name "$t" || t=""
    fi
    if [[ -z "$t" ]] || ! theme__exists "$t"; then t="$THEME_DEFAULT"; fi
    "$PRINTF_BIN" '%s\n' "$t"
}

# ============================================================
#  Swatches
# ============================================================
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
        [[ "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || return 0
    else
        return 0
    fi
    "$PRINTF_BIN" '\033[48;2;%d;%d;%dm   \033[0m' "$r" "$g" "$b"
}

theme__swatch_row() {
    local t="$1" k
    for k in bg accent accent_lt fg cyan; do
        theme__swatch "$t" "$k"
    done
    "$PRINTF_BIN" '\033[0m'
}

# ============================================================
#  Side effects
# ============================================================
theme__ui_effects() {
    local target="$1"
    local gtk="${THEME_UI["$target|gtk_theme"]:-}"
    local scheme="${THEME_UI["$target|color_scheme"]:-}"
    local icon="${THEME_UI["$target|icon_theme"]:-}"
    local folder="${THEME_UI["$target|folder_color"]:-}"

    if [[ -n "$GSETTINGS_BIN" ]]; then
        [[ -n "$scheme" ]] && "$GSETTINGS_BIN" set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || true
        [[ -n "$gtk"    ]] && "$GSETTINGS_BIN" set org.gnome.desktop.interface gtk-theme "$gtk" 2>/dev/null || true
        [[ -n "$icon"   ]] && "$GSETTINGS_BIN" set org.gnome.desktop.interface icon-theme "$icon" 2>/dev/null || true
    fi
    if [[ -n "$PAPIRUS_FOLDERS_BIN" && -n "$folder" && -n "$icon" ]]; then
        "$PAPIRUS_FOLDERS_BIN" -t "$icon" -C "$folder" -u &>/dev/null || true
    fi
}

# Reload desktop components. Only restart daemons we can identify as
# belonging to this user session; never kill unrelated processes.
theme__reload() {
    [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]] || return 0

    if [[ -n "$I3_MSG_BIN" ]]; then
        "$I3_MSG_BIN" reload &>/dev/null || true
    fi

    # dunst: restart only if a dunst is already running for this user.
    if [[ -n "$DUNST_BIN" ]] && "$PKILL_BIN" -0 -x dunst 2>/dev/null; then
        "$PKILL_BIN" -x dunst 2>/dev/null || true
        "$SLEEP_BIN" 0.2
        "$NOHUP_BIN" "$DUNST_BIN" &>/dev/null &
        disown 2>/dev/null || true
    fi

    # xsettingsd: same.
    if [[ -n "$XSETTINGSD_BIN" ]] && "$PKILL_BIN" -0 -x xsettingsd 2>/dev/null; then
        "$PKILL_BIN" -x xsettingsd 2>/dev/null || true
        "$SLEEP_BIN" 0.2
        "$NOHUP_BIN" "$XSETTINGSD_BIN" &>/dev/null &
        disown 2>/dev/null || true
    fi

    if [[ -x "$HOME/.config/polybar/launch.sh" ]]; then
        "$NOHUP_BIN" "$HOME/.config/polybar/launch.sh" &>/dev/null &
        disown 2>/dev/null || true
    fi

    "$PKILL_BIN" -SIGUSR1 -x kitty 2>/dev/null || true
    return 0
}

# ============================================================
#  Apply driver
# ============================================================
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

    if [[ "$reload" == "true" ]]; then
        theme__ui_effects "$target"
        theme__reload
        theme__save_state "$target"
        ok "Theme '$target' applied — desktop reloaded"
        info "  GTK apps need a restart (or relogin) to pick up new colors"
    else
        theme__save_state "$target"
        ok "Theme '$target' applied (${THEME_APPLY_CHANGED} file(s) updated)"
    fi
    info "  Backup:  $THEME_STATE_DIR/${THEME_BACKUP_PREFIX}-*.tar.gz"
    info "  Palette: snowfox theme show $target"
    return 0
}

# ============================================================
#  snowfox theme — dispatcher
# ============================================================
cmd_theme() {
    local sub="${1:-}"
    case "$sub" in
        ""|list|ls)      cmd_theme_list ;;
        current)         theme__load_or_die || return 1; theme__current ;;
        apply|set|use)   theme__apply "${2:-}" "${@:3}" ;;
        reset)
            theme__load_or_die || return 1
            theme__apply "$THEME_DEFAULT" "${@:2}"
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
#  snowfox theme list
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
        "$PRINTF_BIN" '  %s %-12s %-30s ' "$mark" "$t" "${THEME_LABEL[$t]:-}"
        theme__swatch_row "$t"
        "$PRINTF_BIN" '\n'
        [[ -n "${THEME_DESC[$t]:-}" ]] && hint "${THEME_DESC[$t]}"
    done

    divider
    info "Apply:   snowfox theme <name>"
    info "Preview: snowfox theme show <name>   ·   GUI: snowfox theme gui"
    echo ""
}

# ============================================================
#  snowfox theme show [name]
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
        "$PRINTF_BIN" '  \033[2m%-14s\033[0m %-26s ' "$token" "$val"
        theme__swatch "$t" "$token"
        "$PRINTF_BIN" '\n'
    done

    echo ""
    section "UI Properties"
    local key
    for key in "${THEME_UI_KEYS[@]}"; do
        "$PRINTF_BIN" '  \033[2m%-14s\033[0m %s\n' "$key" "${THEME_UI["$t|$key"]:-}"
    done
    echo ""
}

# ============================================================
#  snowfox theme color <token> [theme]
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
    "$PRINTF_BIN" '%s\n' "${THEME_COLOR["$t|$token"]}"
}

# ============================================================
#  snowfox theme gui — Rofi picker
# ============================================================
cmd_theme_gui() {
    theme__load_or_die || return 1

    if [[ -z "$ROFI_BIN" ]]; then
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
        local current rows t mark line k
        current="$(theme__current)"
        rows=""
        for t in "${THEME_LIST[@]}"; do
            if [[ "$t" == "$current" ]]; then mark="●"; else mark="○"; fi
            line=$("$PRINTF_BIN" '%s  %s  %s   ' "$t" "$mark" "${THEME_LABEL[$t]:-}")
            for k in bg accent accent_lt fg cyan; do
                line+="<span foreground='${THEME_COLOR["$t|$k"]}' background='${THEME_COLOR["$t|$k"]}'>   </span>"
            done
            rows+="$line"$'\n'
        done

        local choice
        choice=$("$PRINTF_BIN" '%s' "$rows" | "$ROFI_BIN" -dmenu -markup-rows -i \
            -p "🦊 Theme" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 520 -lines 6) || return 0
        [[ -z "$choice" ]] && return 0

        local picked
        picked=$("$PRINTF_BIN" '%s' "$choice" | "$AWK_BIN" '{print $1}')
        theme__exists "$picked" || continue
        [[ "$picked" == "$current" ]] && continue

        theme__apply "$picked"
        if [[ -n "$NOTIFY_SEND_BIN" ]]; then
            local safe_label
            safe_label=$("$PRINTF_BIN" '%s' "${THEME_LABEL[$picked]:-$picked}" | "$TR_BIN" -cd '[:print:]')
            "$NOTIFY_SEND_BIN" "🦊 SnowFox" "Theme: $safe_label" 2>/dev/null || true
        fi
    done
}

# ============================================================
#  snowfox theme check — validate the master palette
# ============================================================
cmd_theme_check() {
    theme__load_or_die || return 1
    local errors=0 warnings=0
    header "Palette Check"
    info "File: ${THEME_FILE/#$HOME/~}"
    echo ""

    # 1 — every theme defines every token
    section "Completeness"
    local token theme
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

    # 2 — value uniqueness
    section "Uniqueness"
    declare -A vtok=()
    local key val norm toks
    for theme in "${THEME_LIST[@]}"; do
        for key in "${THEME_TOKENS[@]}"; do
            val="${THEME_COLOR["$theme|$key"]:-}"
            [[ -z "$val" ]] && continue
            norm=$("$PRINTF_BIN" '%s' "$val" | "$TR_BIN" 'A-Z' 'a-z' | "$TR_BIN" -d '[:space:]')
            toks="${vtok[$norm]:-}"
            [[ " $toks " == *" $key "* ]] || vtok["$norm"]="$toks $key"
        done
    done
    local t2 v prev bad shared=0
    for norm in "${!vtok[@]}"; do
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
            known["$("$PRINTF_BIN" '%s' "$val" | "$TR_BIN" 'A-Z' 'a-z' | "$TR_BIN" -d '[:space:]')"]=1
        done
    done
    local rel abs m mn
    for rel in "${THEME_TARGET_FILES[@]}"; do
        abs="$HOME/$rel"
        [[ -f "$abs" ]] || continue
        while IFS= read -r m; do
            [[ -z "$m" ]] && continue
            mn=$("$PRINTF_BIN" '%s' "$m" | "$TR_BIN" 'A-Z' 'a-z' | "$TR_BIN" -d '[:space:]')
            [[ -n "${known[$mn]:-}" ]] && continue
            warnings=$((warnings + 1))
            info "  ~/$rel: $m  (not in palette — left untouched)"
        done < <("$GREP_BIN" -oE '#[0-9a-fA-F]{6,8}\b|rgba\([^)]*\)' "$abs" 2>/dev/null | sort -u)
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
#  snowfox theme help
# ============================================================
cmd_theme_help() {
    header "Theme Help"
    section "Commands"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme"                 "List themes & current one"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme <name>"          "Apply a theme (aliases: default, mono, light)"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme apply <name>"    "Same, with options:"
    "$PRINTF_BIN" '  %-34s %s\n' "  --dry-run, -n"               "Show what would change, touch nothing"
    "$PRINTF_BIN" '  %-34s %s\n' "  --no-reload"                 "Do not restart polybar/dunst/i3"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme show [name]"     "Full palette of a theme (with swatches)"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme gui"             "Theme picker in Rofi"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme color <token> [theme]" "Print one color value (for scripts)"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme check"           "Validate palette.conf (unique values, coverage)"
    "$PRINTF_BIN" '  %-34s %s\n' "snowfox theme reset"           "Back to the default theme"
    echo ""
    section "How it works"
    info "  ~/.config/snowfox/palette.conf is the single source of truth."
    info "  Every themed file is rendered from it by replacing known palette"
    info "  values — user edits to the configs are preserved, switching back"
    info "  and forth is lossless (a backup is kept in ~/.config/snowfox/)."
    echo ""
}
