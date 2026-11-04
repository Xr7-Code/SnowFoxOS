#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Desktop
#  Autostart, Layout, WebApps
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - No eval(): webapp launch goes through gtk-launch/xdg-open
#   - Strict $name / $url validation before any .desktop write
#   - Exec= line uses single quotes (desktop-entry safe), no shell eval
#   - sed metacharacters escaped before i3 config edits
#   - Empty $safe (no alnum) rejected — prevents rm -rf on $WEBAPP_DIR
#   - curl forced to https, TLS 1.2+, no Google favicon proxy
#   - .desktop validated with desktop-file-validate before display
#   - Private dirs 0700, .desktop dir 0755
#   - return instead of exit in library functions
#   - Controlled PATH, absolute binary paths
# ============================================================

# ─── Controlled environment ─────────────────────────────────
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

# ─── Binary paths ───────────────────────────────────────────
readonly GREP_BIN="/usr/bin/grep"
readonly SED_BIN="/usr/bin/sed"
readonly AWK_BIN="/usr/bin/awk"
readonly TR_BIN="/usr/bin/tr"
readonly CUT_BIN="/usr/bin/cut"
readonly HEAD_BIN="/usr/bin/head"
readonly CURL_BIN="/usr/bin/curl"
readonly FILE_BIN="/usr/bin/file"
readonly MKDIR_BIN="/usr/bin/mkdir"
readonly CHMOD_BIN="/usr/bin/chmod"
readonly RM_BIN="/usr/bin/rm"
readonly CAT_BIN="/usr/bin/cat"
readonly BASENAME_BIN="/usr/bin/basename"
readonly UPDATE_DB_BIN="/usr/bin/update-desktop-database"
readonly DESKTOP_VALIDATE_BIN="/usr/bin/desktop-file-validate"
readonly GTK_LAUNCH_BIN="/usr/bin/gtk-launch"
readonly XDG_OPEN_BIN="/usr/bin/xdg-open"
readonly I3_MSG_BIN="/usr/bin/i3-msg"

[[ -x "$UPDATE_DB_BIN" ]]        || UPDATE_DB_BIN=""
[[ -x "$DESKTOP_VALIDATE_BIN" ]] || DESKTOP_VALIDATE_BIN=""
[[ -x "$GTK_LAUNCH_BIN" ]]       || GTK_LAUNCH_BIN=""
[[ -x "$XDG_OPEN_BIN" ]]         || XDG_OPEN_BIN=""
[[ -x "$I3_MSG_BIN" ]]           || I3_MSG_BIN=""

# ─── Constants ──────────────────────────────────────────────
readonly I3_CONFIG="$HOME/.config/i3/config"
readonly WEBAPP_DIR="$HOME/.config/snowfox/webapps"
readonly WEBAPP_DESK="$HOME/.local/share/applications"
readonly WEBAPP_ICONS="$HOME/.config/snowfox/webapps/icons"

# ============================================================
#  Validation helpers
# ============================================================

# Program name for autostart/layout: alnum, dot, dash, slash, underscore.
# Rejects anything that could break sed or a file path.
_valid_program_name() {
    local n="$1"
    [[ -z "$n" ]] && return 1
    [[ ${#n} -gt 128 ]] && return 1
    [[ "$n" =~ ^[a-zA-Z0-9._/-]+$ ]]
}

# WebApp display name: alnum, space, dash, underscore, max 64.
_valid_webapp_name() {
    local n="$1"
    [[ -z "$n" ]] && return 1
    [[ ${#n} -gt 64 ]] && return 1
    [[ "$n" =~ ^[a-zA-Z0-9][a-zA-Z0-9\ _-]{0,63}$ ]]
}

# URL: http(s) only, no whitespace, no quotes/backticks, max 2048.
_valid_url() {
    local u="$1"
    [[ -z "$u" ]] && return 1
    [[ ${#u} -gt 2048 ]] && return 1
    [[ "$u" =~ ^https?://[^[:space:]\"\'\`\\]+$ ]]
}

# Slug from name: lowercase, spaces→dash, strip non [a-z0-9-].
# Returns empty string if the result would be empty.
_webapp_slug() {
    local n="$1"
    local s
    s=$(printf '%s' "$n" \
        | "$TR_BIN" '[:upper:]' '[:lower:]' \
        | "$TR_BIN" ' ' '-' \
        | "$TR_BIN" -cd '[:alnum:]-')
    [[ -z "$s" ]] && return 1
    [[ ${#s} -gt 64 ]] && return 1
    printf '%s' "$s"
}

# Escape sed metacharacters in a literal string.
_sed_escape() {
    printf '%s' "$1" | "$SED_BIN" 's/[][\\.^$*&|]/\\&/g'
}

# Escape a literal string for desktop-entry Exec= value.
# Desktop Entry spec: quoted values use "..." with \\, \", \$, \` escapes.
# We instead use single quotes as the outermost layer and double the inner
# single quotes, which .desktop parsers handle literally.
_desktop_quote() {
    local s="$1"
    s=${s//\'/\'\\\'\'}
    printf "'%s'" "$s"
}

# ============================================================
# snowfox auto — Autostart management
# ============================================================
cmd_start() {
    case "${1:-}" in
        list|"")
            _auto_list
            return $?
            ;;
        enable)
            _auto_enable "${2:-}"
            return $?
            ;;
        disable)
            _auto_disable "${2:-}"
            return $?
            ;;
        *)
            err "Usage: snowfox auto [list|enable|disable] [program]"
            return 1
            ;;
    esac
}

_auto_list() {
    header "Autostart"

    local AUTO_DIR="$HOME/.config/autostart"
    section "User Applications"

    if [[ -d "$AUTO_DIR" ]]; then
        local found=false
        local desktop name hidden
        for desktop in "$AUTO_DIR"/*.desktop; do
            [[ -e "$desktop" ]] || continue

            # Validate before displaying — a malformed .desktop could hide
            # a different Exec= line from the user.
            if [[ -n "$DESKTOP_VALIDATE_BIN" ]]; then
                if ! "$DESKTOP_VALIDATE_BIN" "$desktop" >/dev/null 2>&1; then
                    printf "  ${RED}%-4s${RESET} ${GRAY}%s (invalid .desktop)${RESET}\n" \
                        "[!!]" "$("$BASENAME_BIN" "$desktop" .desktop)"
                    found=true
                    continue
                fi
            fi

            name=$("$GREP_BIN" -m1 "^Name=" "$desktop" | "$CUT_BIN" -d= -f2-)
            hidden=$("$GREP_BIN" -m1 "^Hidden=" "$desktop" | "$CUT_BIN" -d= -f2-)
            [[ -z "$name" ]] && name=$("$BASENAME_BIN" "$desktop" .desktop)

            if [[ "$hidden" == "true" ]]; then
                printf "  ${RED}%-4s${RESET} ${GRAY}%s${RESET}\n" "[off]" "$name"
            else
                printf "  ${GREEN}%-4s${RESET} ${CYAN}%s${RESET}\n" "[on]" "$name"
            fi
            found=true
        done
        $found || info "  No user autostart entries."
    else
        info "  No autostart directory found."
    fi

    section "i3 Session"

    local i3_entries
    i3_entries=$("$GREP_BIN" -n "^exec " "$I3_CONFIG" 2>/dev/null)
    if [[ -n "$i3_entries" ]]; then
        while IFS= read -r entry; do
            local cmd
            cmd=$(printf '%s' "$entry" | "$CUT_BIN" -d: -f2- | "$SED_BIN" 's/^exec //')
            printf "  ${GREEN}%-4s${RESET} ${CYAN}%s${RESET}\n" "[on]" "$cmd"
        done <<< "$i3_entries"
    else
        info "  No exec entries in i3 config."
    fi

    local i3_disabled
    i3_disabled=$("$GREP_BIN" -n "^#exec " "$I3_CONFIG" 2>/dev/null)
    if [[ -n "$i3_disabled" ]]; then
        while IFS= read -r entry; do
            local cmd
            cmd=$(printf '%s' "$entry" | "$CUT_BIN" -d: -f2- | "$SED_BIN" 's/^#exec //')
            printf "  ${RED}%-4s${RESET} ${GRAY}%s${RESET}\n" "[off]" "$cmd"
        done <<< "$i3_disabled"
    fi

    divider
    info "Enable:  snowfox auto enable <program>"
    info "Disable: snowfox auto disable <program>"
    echo ""
    return 0
}

_auto_enable() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox auto enable <program>"
        return 1
    fi
    if ! _valid_program_name "$target"; then
        err "Invalid program name: $target"
        info "Allowed characters: a-z A-Z 0-9 . _ - /"
        return 1
    fi

    local esc
    esc=$(_sed_escape "$target")

    if "$GREP_BIN" -q "^#exec.*${esc}" "$I3_CONFIG" 2>/dev/null; then
        "$SED_BIN" -i "s|^#exec \(.*${esc}.*\)|exec \1|" "$I3_CONFIG"
        [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" reload &>/dev/null || true
        ok "$target enabled in i3."
        return 0
    fi

    local desktop="$HOME/.config/autostart/$target.desktop"
    if [[ -f "$desktop" ]]; then
        "$SED_BIN" -i 's/^Hidden=true/Hidden=false/' "$desktop"
        ok "$target enabled in autostart."
        return 0
    fi

    err "$target not found in i3 config or autostart."
    return 1
}

_auto_disable() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox auto disable <program>"
        return 1
    fi
    if ! _valid_program_name "$target"; then
        err "Invalid program name: $target"
        info "Allowed characters: a-z A-Z 0-9 . _ - /"
        return 1
    fi

    local esc
    esc=$(_sed_escape "$target")

    if "$GREP_BIN" -q "^exec.*${esc}" "$I3_CONFIG" 2>/dev/null; then
        "$SED_BIN" -i "s|^exec \(.*${esc}.*\)|#exec \1|" "$I3_CONFIG"
        [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" reload &>/dev/null || true
        ok "$target disabled in i3."
        return 0
    fi

    local desktop="$HOME/.config/autostart/$target.desktop"
    if [[ -f "$desktop" ]]; then
        "$SED_BIN" -i 's/^Hidden=false/Hidden=true/' "$desktop"
        ok "$target disabled in autostart."
        return 0
    fi

    err "$target not found in i3 config or autostart."
    return 1
}

# ============================================================
# snowfox lay — Window layout mode
# ============================================================
cmd_layout() {
    case "${1:-}" in
        tiling)
            [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" "workspace_layout default" &>/dev/null || true
            [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" '[class=".*"] floating disable' &>/dev/null || true
            "$SED_BIN" -i \
                's/^for_window \[class=".*"\] floating enable/# for_window [class=".*"] floating enable/' \
                "$I3_CONFIG" 2>/dev/null || true
            [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" reload &>/dev/null || true
            ok "Layout: ${BOLD}Tiling${RESET}"
            info "  New windows are arranged side by side (i3 default)"
            return 0
            ;;
        floating)
            if "$GREP_BIN" -q 'for_window \[class=".*"\] floating enable' "$I3_CONFIG" 2>/dev/null; then
                "$SED_BIN" -i \
                    's/^# for_window \[class=".*"\] floating enable/for_window [class=".*"] floating enable/' \
                    "$I3_CONFIG"
            else
                printf '%s\n' 'for_window [class=".*"] floating enable' >> "$I3_CONFIG"
            fi
            [[ -n "$I3_MSG_BIN" ]] && "$I3_MSG_BIN" reload &>/dev/null || true
            ok "Layout: ${BOLD}Floating${RESET}"
            info "  New windows float freely — classic desktop mode"
            return 0
            ;;
        status|"")
            header "Window Layout"
            if "$GREP_BIN" -q '^for_window \[class=".*"\] floating enable' "$I3_CONFIG" 2>/dev/null; then
                row "Current" "Floating (classic desktop)" "$CYAN"
            else
                row "Current" "Tiling (i3 default)" "$CYAN"
            fi
            echo ""
            info "snowfox lay tiling    — windows arranged side by side"
            info "snowfox lay floating  — windows float freely"
            echo ""
            return 0
            ;;
        *)
            err "Usage: snowfox lay [tiling|floating|status]"
            return 1
            ;;
    esac
}

# ============================================================
# snowfox web — WebApps (Zen Browser, app mode)
# ============================================================
cmd_webapp() {
    "$MKDIR_BIN" -p "$WEBAPP_DIR" "$WEBAPP_DESK" "$WEBAPP_ICONS" || {
        err "Cannot create WebApp directories."
        return 1
    }
    "$CHMOD_BIN" 700 "$WEBAPP_DIR" "$WEBAPP_ICONS" 2>/dev/null || true
    "$CHMOD_BIN" 755 "$WEBAPP_DESK" 2>/dev/null || true

    case "${1:-}" in
        add)    _webapp_add "${2:-}" "${3:-}"; return $? ;;
        list)   _webapp_list;                  return $? ;;
        open)   _webapp_open "${2:-}";         return $? ;;
        remove) _webapp_remove "${2:-}";       return $? ;;
        *)
            header "snowfox web"
            info "  snowfox web add <name> <url>  — create new web app"
            info "  snowfox web list             — list all web apps"
            info "  snowfox web open <name>      — launch web app"
            info "  snowfox web remove <name>    — remove web app"
            echo ""
            return 0
            ;;
    esac
}

# ── Zen Browser executable ───────────────────────────────────
_webapp_zen_bin() {
    if command -v zen-browser &>/dev/null; then
        command -v zen-browser
    elif [[ -x /opt/zen-browser.AppImage ]]; then
        printf '%s\n' "/opt/zen-browser.AppImage"
    else
        return 1
    fi
}

# ── Add a WebApp ────────────────────────────────────────────
_webapp_add() {
    local name="$1"
    local url="$2"

    if [[ -z "$name" || -z "$url" ]]; then
        err "Usage: snowfox web add <name> <url>"
        err "Example: snowfox web add ChatGPT https://chatgpt.com"
        return 1
    fi

    if ! _valid_webapp_name "$name"; then
        err "Invalid name: $name"
        info "Allowed: letters, digits, space, dash, underscore (max 64)"
        return 1
    fi

    if ! _valid_url "$url"; then
        err "Invalid URL: $url"
        info "Must be http(s)://... with no whitespace or quotes"
        return 1
    fi

    local safe
    if ! safe=$(_webapp_slug "$name"); then
        err "Name produces an empty slug: $name"
        return 1
    fi

    local zen_bin
    if ! zen_bin=$(_webapp_zen_bin); then
        err "Zen Browser not found."
        info "WebApps need Zen Browser — reinstall it with the SnowFoxOS installer."
        return 1
    fi

    fox "New WebApp: ${BOLD}$name${RESET}"
    info "  URL: $url"

    # ── Favicon (https only, no Google proxy) ───────────────
    local icon="web-browser"
    local icon_path="$WEBAPP_ICONS/${safe}.png"
    local domain
    domain=$(printf '%s' "$url" \
        | "$SED_BIN" -E 's|^https?://||' \
        | "$CUT_BIN" -d'/' -f1)

    if [[ -n "$domain" ]]; then
        info "  Fetching favicon from $domain..."
        local favicon_urls=(
            "https://${domain}/favicon.ico"
            "https://${domain}/favicon.png"
        )
        local furl
        for furl in "${favicon_urls[@]}"; do
            if "$CURL_BIN" -sfL --proto '=https' --tlsv1.2 --max-time 10 \
                "$furl" -o "$icon_path" 2>/dev/null; then
                if "$FILE_BIN" "$icon_path" 2>/dev/null \
                    | "$GREP_BIN" -qiE 'image|icon|PNG|GIF|JPEG'; then
                    icon="$icon_path"
                    ok "Favicon loaded"
                    break
                fi
            fi
        done
        [[ "$icon" == "web-browser" ]] && warn "No favicon found — using default icon"
    fi

    # ── Zen profile ─────────────────────────────────────────
    local profile_dir="$WEBAPP_DIR/$safe/zen-profile"
    "$MKDIR_BIN" -p "$profile_dir/chrome" || {
        err "Cannot create profile directory."
        return 1
    }
    "$CHMOD_BIN" 700 "$WEBAPP_DIR/$safe" 2>/dev/null || true

    "$CAT_BIN" > "$profile_dir/chrome/userChrome.css" << 'CSSEOF'
/* SnowFox WebApp — hide all browser chrome */
#navigator-toolbox,
#sidebar-box,
#sidebar-main,
#tabbrowser-tabs,
#urlbar-container,
#PersonalToolbar,
#TabsToolbar {
    display: none !important;
}
#browser {
    margin-top: 0 !important;
}
CSSEOF

    "$CAT_BIN" > "$profile_dir/user.js" << 'JSEOF'
// SnowFox WebApp preferences
user_pref("browser.tabs.drawInTitlebar", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.fullscreen.autohide", true);
user_pref("dom.disable_open_during_load", false);
JSEOF

    # ── .desktop entry (no shell quoting, no eval) ──────────
    # Exec= uses single quotes per desktop-entry spec. The values are
    # already validated, so no further escaping is needed beyond the
    # quoting helper.
    local q_zen q_profile q_url q_icon q_name q_comment
    q_zen=$(_desktop_quote "$zen_bin")
    q_profile=$(_desktop_quote "$profile_dir")
    q_url=$(_desktop_quote "$url")
    q_icon=$(_desktop_quote "$icon")
    q_name=$(_desktop_quote "$name")
    q_comment=$(_desktop_quote "SnowFox WebApp — $url")

    local desktop_file="$WEBAPP_DESK/snowfox-webapp-${safe}.desktop"
    "$CAT_BIN" > "$desktop_file" <<-DEOF
[Desktop Entry]
Name=${q_name}
Comment=${q_comment}
Exec=${q_zen} --profile ${q_profile} --new-window ${q_url}
Icon=${q_icon}
Type=Application
Categories=Network;WebApp;
StartupNotify=true
StartupWMClass=zen
DEOF
    "$CHMOD_BIN" 644 "$desktop_file" 2>/dev/null || true

    [[ -n "$UPDATE_DB_BIN" ]] && "$UPDATE_DB_BIN" "$WEBAPP_DESK" 2>/dev/null || true

    ok "WebApp '${BOLD}$name${RESET}' created"
    info "  Launch: snowfox web open $safe"
    info "  Rofi:   search for '$name'"
    echo ""
    return 0
}

# ── List WebApps ────────────────────────────────────────────
_webapp_list() {
    header "WebApps"

    if [[ ! -d "$WEBAPP_DESK" ]]; then
        info "No WebApps found."
        return 0
    fi

    local found=false
    local desktop name url
    for desktop in "$WEBAPP_DESK"/snowfox-webapp-*.desktop; do
        [[ -e "$desktop" ]] || continue

        if [[ -n "$DESKTOP_VALIDATE_BIN" ]]; then
            if ! "$DESKTOP_VALIDATE_BIN" "$desktop" >/dev/null 2>&1; then
                printf "  ${RED}%-24s${RESET} ${GRAY}(invalid .desktop)${RESET}\n" \
                    "$("$BASENAME_BIN" "$desktop" .desktop)"
                found=true
                continue
            fi
        fi

        name=$("$GREP_BIN" -m1 "^Name=" "$desktop" | "$CUT_BIN" -d= -f2-)
        url=$("$GREP_BIN" -m1 "^Comment=" "$desktop" | "$SED_BIN" 's/.*— //')
        printf "  ${CYAN}%-24s${RESET} ${GRAY}%s${RESET}\n" "$name" "$url"
        found=true
    done

    $found || info "No WebApps found."
    echo ""
    return 0
}

# ── Open WebApp (no eval) ───────────────────────────────────
_webapp_open() {
    local name="$1"
    if [[ -z "$name" ]]; then
        err "Usage: snowfox web open <name>"
        return 1
    fi

    local safe
    if ! safe=$(_webapp_slug "$name"); then
        err "Invalid name: $name"
        return 1
    fi

    local desktop_id="snowfox-webapp-${safe}"
    local desktop_file="$WEBAPP_DESK/${desktop_id}.desktop"
    if [[ ! -f "$desktop_file" ]]; then
        err "WebApp '$name' not found. List: snowfox web list"
        return 1
    fi

    # Validate the .desktop file before trusting it.
    if [[ -n "$DESKTOP_VALIDATE_BIN" ]]; then
        if ! "$DESKTOP_VALIDATE_BIN" "$desktop_file" >/dev/null 2>&1; then
            err "WebApp '$name' has an invalid .desktop file — refusing to launch."
            info "Remove and re-create: snowfox web remove $name && snowfox web add $name <url>"
            return 1
        fi
    fi

    fox "Opening ${BOLD}$name${RESET}..."

    # Prefer gtk-launch (uses the desktop ID, no shell). Fall back to
    # xdg-open on the URL extracted from the .desktop file, never eval.
    if [[ -n "$GTK_LAUNCH_BIN" ]]; then
        "$GTK_LAUNCH_BIN" "$desktop_id" >/dev/null 2>&1 &
        return 0
    fi

    local exec_line url
    exec_line=$("$GREP_BIN" -m1 "^Exec=" "$desktop_file" | "$CUT_BIN" -d= -f2-)
    # Extract the last quoted argument; it is the URL by construction.
    url=$(printf '%s' "$exec_line" \
        | "$GREP_BIN" -oE "'[^']*'$" \
        | "$TR_BIN" -d "'")
    if [[ -n "$url" ]] && _valid_url "$url" && [[ -n "$XDG_OPEN_BIN" ]]; then
        "$XDG_OPEN_BIN" "$url" >/dev/null 2>&1 &
        return 0
    fi

    err "Cannot launch WebApp: neither gtk-launch nor xdg-open available."
    return 1
}

# ── Remove WebApp ───────────────────────────────────────────
_webapp_remove() {
    local name="$1"
    if [[ -z "$name" ]]; then
        err "Usage: snowfox web remove <name>"
        return 1
    fi

    local safe
    if ! safe=$(_webapp_slug "$name"); then
        err "Invalid name: $name"
        return 1
    fi

    # Belt and braces: refuse if the resolved path is not under $WEBAPP_DIR.
    local target_dir="$WEBAPP_DIR/$safe"
    case "$target_dir" in
        "$WEBAPP_DIR"/*) ;;
        *)
            err "Refusing to remove path outside WebApp directory: $target_dir"
            return 1
            ;;
    esac

    "$RM_BIN" -f "$WEBAPP_DESK/snowfox-webapp-${safe}.desktop"
    "$RM_BIN" -rf "$target_dir"
    "$RM_BIN" -f "$WEBAPP_ICONS/${safe}.png"

    [[ -n "$UPDATE_DB_BIN" ]] && "$UPDATE_DB_BIN" "$WEBAPP_DESK" 2>/dev/null || true
    ok "WebApp '$name' removed."
    return 0
}
