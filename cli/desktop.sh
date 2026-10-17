#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Desktop
#  Autostart, Layout, WebApps
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

I3_CONFIG="$HOME/.config/i3/config"
WEBAPP_DIR="$HOME/.config/snowfox/webapps"
WEBAPP_DESK="$HOME/.local/share/applications"
WEBAPP_ICONS="$HOME/.config/snowfox/webapps/icons"

# ============================================================
# snowfox auto — Autostart management
# ============================================================
cmd_start() {
    local action="${1:-}"

    # ── Gum TUI: autostart menu ──────────────────────────────
    if [[ -z "$action" ]] && sf_can_tui; then
        _auto_tui
        return 0
    fi

    case "$action" in
        list|"")
            _auto_list
            ;;
        enable)
            _auto_enable "$2"
            ;;
        disable)
            _auto_disable "$2"
            ;;
        *)
            err "Usage: snowfox auto [list|enable|disable] [program]"
            return 1
            ;;
    esac
}

_auto_list() {
    header "Autostart"

    # ── User applications (snowfox-managed) ─────────────────
    local AUTO_DIR="$HOME/.config/autostart"
    section "User Applications"

    if [[ -d "$AUTO_DIR" ]]; then
        local found=false
        for desktop in "$AUTO_DIR"/*.desktop; do
            [[ -e "$desktop" ]] || continue
            local name hidden
            name=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
            hidden=$(grep -m1 "^Hidden=" "$desktop" | cut -d= -f2-)
            [[ -z "$name" ]] && name=$(basename "$desktop" .desktop)

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

    # ── i3 session components ───────────────────────────────
    section "i3 Session"

    local i3_entries
    i3_entries=$(grep -n "^exec " "$I3_CONFIG" 2>/dev/null)
    if [[ -n "$i3_entries" ]]; then
        while IFS= read -r entry; do
            local cmd
            cmd=$(echo "$entry" | cut -d: -f2- | sed 's/^exec //')
            printf "  ${GREEN}%-4s${RESET} ${CYAN}%s${RESET}\n" "[on]" "$cmd"
        done <<< "$i3_entries"
    else
        info "  No exec entries in i3 config."
    fi

    local i3_disabled
    i3_disabled=$(grep -n "^#exec " "$I3_CONFIG" 2>/dev/null)
    if [[ -n "$i3_disabled" ]]; then
        while IFS= read -r entry; do
            local cmd
            cmd=$(echo "$entry" | cut -d: -f2- | sed 's/^#exec //')
            printf "  ${RED}%-4s${RESET} ${GRAY}%s${RESET}\n" "[off]" "$cmd"
        done <<< "$i3_disabled"
    fi

    divider
    info "Enable:  snowfox auto enable <program>"
    info "Disable: snowfox auto disable <program>"
    echo ""
}

_auto_enable() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox auto enable <program>"
        return 1
    fi

    if grep -q "^#exec.*$target" "$I3_CONFIG" 2>/dev/null; then
        sed -i "s|^#exec \(.*$target.*\)|exec \1|" "$I3_CONFIG"
        i3-msg reload &>/dev/null || true
        ok "$target enabled in i3."
        return 0
    fi

    local desktop="$HOME/.config/autostart/$target.desktop"
    if [[ -f "$desktop" ]]; then
        sed -i 's/^Hidden=true/Hidden=false/' "$desktop"
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

    if grep -q "^exec.*$target" "$I3_CONFIG" 2>/dev/null; then
        sed -i "s|^exec \(.*$target.*\)|#exec \1|" "$I3_CONFIG"
        i3-msg reload &>/dev/null || true
        ok "$target disabled in i3."
        return 0
    fi

    local desktop="$HOME/.config/autostart/$target.desktop"
    if [[ -f "$desktop" ]]; then
        sed -i 's/^Hidden=false/Hidden=true/' "$desktop"
        ok "$target disabled in autostart."
        return 0
    fi

    err "$target not found in i3 config or autostart."
    return 1
}

# ── Gum TUI: autostart ───────────────────────────────────────
_auto_tui() {
    while true; do
        sf_banner "Autostart"
        _auto_list

        local choice st
        choice=$(sf_choose "Manage autostart" 5 \
            "✅  Enable an entry" \
            "⛔  Disable an entry" \
            "🔄  Refresh" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *Enable*)  _auto_tui_pick enable ;;
            *Disable*) _auto_tui_pick disable ;;
        esac
    done
}

_auto_tui_pick() {
    local mode="$1"
    local -a entries=() targets=()
    local line cmd base name hidden desktop

    # Disabled i3 exec entries
    while IFS= read -r line; do
        cmd=$(echo "$line" | sed 's/^#exec[[:space:]]*//; s/--no-startup-id[[:space:]]*//' | awk '{print $1}')
        [[ -z "$cmd" ]] && continue
        cmd="${cmd/#\~/$HOME}"
        base=$(basename "$cmd")
        [[ -z "$base" ]] && continue
        entries+=("🪟  $base  (i3, disabled)")
        targets+=("$base")
    done < <(grep "^#exec " "$I3_CONFIG" 2>/dev/null)

    # Autostart entries
    for desktop in "$HOME/.config/autostart"/*.desktop; do
        [[ -e "$desktop" ]] || continue
        base=$(basename "$desktop" .desktop)
        name=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
        [[ -z "$name" ]] && name="$base"
        hidden=$(grep -m1 "^Hidden=" "$desktop" | cut -d= -f2-)
        if [[ "$mode" == "disable" ]]; then
            [[ "$hidden" == "true" ]] && continue
            entries+=("🧩  $name  (autostart, enabled)")
        else
            [[ "$hidden" != "true" ]] && continue
            entries+=("🧩  $name  (autostart, disabled)")
        fi
        targets+=("$base")
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        warn "Nothing found to $mode."
        sleep 1.2
        return 0
    fi

    local label="Enable which entry?"
    [[ "$mode" == "disable" ]] && label="Disable which entry?"

    local pick st i
    pick=$(sf_choose "$label" 12 "${entries[@]}")
    st=$?
    [[ $st -ne 0 || -z "$pick" ]] && return 0

    for i in "${!entries[@]}"; do
        if [[ "${entries[$i]}" == "$pick" ]]; then
            if [[ "$mode" == "enable" ]]; then
                _auto_enable "${targets[$i]}"
            else
                _auto_disable "${targets[$i]}"
            fi
            break
        fi
    done
    sleep 1
}

# ============================================================
# snowfox lay — Window layout mode
# ============================================================
cmd_layout() {
    local mode="${1:-}"

    # ── Gum TUI: layout picker ───────────────────────────────
    if [[ -z "$mode" ]] && sf_can_tui; then
        _layout_tui
        return 0
    fi

    case "$mode" in
        tiling)
            i3-msg "workspace_layout default" &>/dev/null
            i3-msg "[class=\".*\"] floating disable" &>/dev/null || true
            sed -i 's/^for_window \[class=".*"\] floating enable/# for_window [class=".*"] floating enable/' \
                "$I3_CONFIG" 2>/dev/null || true
            i3-msg reload &>/dev/null
            ok "Layout: ${BOLD}Tiling${RESET}"
            info "  New windows are arranged side by side (i3 default)"
            ;;
        floating)
            if grep -q 'for_window \[class=".*"\] floating enable' "$I3_CONFIG" 2>/dev/null; then
                sed -i 's/^# for_window \[class=".*"\] floating enable/for_window [class=".*"] floating enable/' \
                    "$I3_CONFIG"
            else
                echo 'for_window [class=".*"] floating enable' >> "$I3_CONFIG"
            fi
            i3-msg reload &>/dev/null
            ok "Layout: ${BOLD}Floating${RESET}"
            info "  New windows float freely — classic desktop mode"
            ;;
        status|"")
            header "Window Layout"
            if grep -q '^for_window \[class=".*"\] floating enable' "$I3_CONFIG" 2>/dev/null; then
                row "Current" "Floating (classic desktop)" "$CYAN"
            else
                row "Current" "Tiling (i3 default)" "$CYAN"
            fi
            echo ""
            info "snowfox lay tiling    — windows arranged side by side"
            info "snowfox lay floating  — windows float freely"
            echo ""
            ;;
        *)
            err "Usage: snowfox lay [tiling|floating|status]"
            return 1
            ;;
    esac
}

# ── Gum TUI: window layout ───────────────────────────────────
_layout_tui() {
    while true; do
        local current="Tiling (i3 default)"
        grep -q '^for_window \[class=".*"\] floating enable' "$I3_CONFIG" 2>/dev/null \
            && current="Floating (classic desktop)"

        sf_banner "Window Layout"
        sf_note "Current: $current"

        local choice st
        choice=$(sf_choose "Layout mode" 5 \
            "🪟  Tiling — windows arranged side by side" \
            "🪟  Floating — classic desktop windows" \
            "🔄  Refresh" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *Tiling*)   cmd_layout tiling ;;
            *Floating*) cmd_layout floating ;;
        esac
        sleep 1
    done
}

# ============================================================
# snowfox web — WebApps (Zen Browser, app mode)
# ============================================================
cmd_webapp() {
    mkdir -p "$WEBAPP_DIR" "$WEBAPP_DESK" "$WEBAPP_ICONS"

    local action="${1:-}"

    # ── Gum TUI: webapp menu ─────────────────────────────────
    if [[ -z "$action" ]] && sf_can_tui; then
        _webapp_tui
        return 0
    fi

    case "$action" in
        add)    _webapp_add "$2" "$3" ;;
        list)   _webapp_list ;;
        open)   _webapp_open "$2" ;;
        remove) _webapp_remove "$2" ;;
        *)
            header "snowfox web"
            info "  snowfox web add <name> <url>  — create new web app"
            info "  snowfox web list             — list all web apps"
            info "  snowfox web open <name>      — launch web app"
            info "  snowfox web remove <name>    — remove web app"
            echo ""
            ;;
    esac
}

# ── Gum TUI: webapps ─────────────────────────────────────────
_webapp_tui() {
    while true; do
        sf_banner "WebApps"
        _webapp_list

        local choice st
        choice=$(sf_choose "WebApps" 6 \
            "➕  Create new WebApp" \
            "🚀  Open a WebApp" \
            "🗑️   Remove a WebApp" \
            "🔄  Refresh list" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *Create*)
                local name url
                name=$(sf_ask_ph "WebApp name" "e.g. ChatGPT")
                [[ -z "$name" ]] && continue
                url=$(sf_ask_ph "WebApp URL" "https://…")
                [[ -z "$url" ]] && continue
                _webapp_add "$name" "$url"
                sf_pause "Press Enter to continue…"
                ;;
            *Open*)   _webapp_tui_pick open ;;
            *Remove*) _webapp_tui_pick remove ;;
        esac
    done
}

_webapp_tui_pick() {
    local mode="$1"
    local -a entries=()
    local desktop name

    for desktop in "$WEBAPP_DESK"/snowfox-webapp-*.desktop; do
        [[ -e "$desktop" ]] || continue
        name=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
        [[ -z "$name" ]] && name=$(basename "$desktop" .desktop)
        entries+=("$name")
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        err "No WebApps found."
        sleep 1.2
        return 0
    fi

    local label pick st
    if [[ "$mode" == "open" ]]; then
        label="Open which WebApp?"
    else
        label="Remove which WebApp?"
    fi

    pick=$(printf '%s\n' "${entries[@]}" | sf_filter "$label" "Type to filter — Enter to select" 10)
    st=$?
    [[ $st -ne 0 || -z "$pick" ]] && return 0

    if [[ "$mode" == "open" ]]; then
        _webapp_open "$pick"
    else
        if sf_yesno "Remove WebApp '$pick'?" "Remove" "Cancel" no; then
            _webapp_remove "$pick"
        fi
        sleep 1
    fi
}

# ── Zen Browser executable ───────────────────────────────────
# The SnowFoxOS installer drops Zen at /opt/zen-browser.AppImage
# (there is no "zen-browser" command in PATH by default).
_webapp_zen_bin() {
    if command -v zen-browser &>/dev/null; then
        command -v zen-browser
    elif [[ -x /opt/zen-browser.AppImage ]]; then
        echo "/opt/zen-browser.AppImage"
    else
        return 1
    fi
}

_webapp_add() {
    local name="$1"
    local url="$2"

    if [[ -z "$name" || -z "$url" ]]; then
        err "Usage: snowfox web add <name> <url>"
        err "Example: snowfox web add ChatGPT https://chatgpt.com"
        return 1
    fi

    local zen_bin
    if ! zen_bin=$(_webapp_zen_bin); then
        err "Zen Browser not found."
        info "WebApps need Zen Browser — reinstall it with the SnowFoxOS installer."
        return 1
    fi

    local safe
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    fox "New WebApp: ${BOLD}$name${RESET}"
    info "  URL: $url"

    # ── Download favicon ─────────────────────────────────────
    local icon="web-browser"
    local icon_path="$WEBAPP_ICONS/${safe}.png"
    local domain
    domain=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)

    info "  Fetching favicon from $domain..."
    local favicon_urls=(
        "https://www.google.com/s2/favicons?domain=${domain}&sz=128"
        "https://${domain}/favicon.ico"
        "https://${domain}/favicon.png"
    )
    for furl in "${favicon_urls[@]}"; do
        if curl -sfL --max-time 5 "$furl" -o "$icon_path" 2>/dev/null; then
            if file "$icon_path" 2>/dev/null | grep -qiE "image|icon|PNG|GIF|JPEG"; then
                icon="$icon_path"
                ok "Favicon loaded"
                break
            fi
        fi
    done
    [[ "$icon" == "web-browser" ]] && warn "No favicon found — using default icon"

    # ── Zen Browser app mode ─────────────────────────────────
    local profile_dir="$WEBAPP_DIR/$safe/zen-profile"
    mkdir -p "$profile_dir/chrome"

    cat > "$profile_dir/chrome/userChrome.css" << 'CSSEOF'
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

    cat > "$profile_dir/user.js" << 'JSEOF'
// SnowFox WebApp preferences
user_pref("browser.tabs.drawInTitlebar", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.fullscreen.autohide", true);
user_pref("dom.disable_open_during_load", false);
JSEOF

    local exec_cmd="$zen_bin --profile \"$profile_dir\" --new-window \"$url\""

    # ── Create .desktop entry ────────────────────────────────
    cat > "$WEBAPP_DESK/snowfox-webapp-${safe}.desktop" << DEOF
[Desktop Entry]
Name=$name
Comment=SnowFox WebApp — $url
Exec=$exec_cmd
Icon=$icon
Type=Application
Categories=Network;WebApp;
StartupNotify=true
StartupWMClass=zen
DEOF

    update-desktop-database "$WEBAPP_DESK" 2>/dev/null || true

    ok "WebApp '${BOLD}$name${RESET}' created"
    info "  Launch: snowfox web open $safe"
    info "  Rofi:   search for '$name'"
    echo ""
}

_webapp_list() {
    header "WebApps"

    if [[ ! -d "$WEBAPP_DESK" ]]; then
        info "No WebApps found."
        exit 0
    fi

    local found=false
    for desktop in "$WEBAPP_DESK"/snowfox-webapp-*.desktop; do
        [[ -e "$desktop" ]] || continue
        local name url
        name=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
        url=$(grep -m1 "^Comment=" "$desktop" | sed 's/.*— //')
        printf "  ${CYAN}%-24s${RESET} ${GRAY}%s${RESET}\n" "$name" "$url"
        found=true
    done

    $found || info "No WebApps found."
    echo ""
}

_webapp_open() {
    local name="$1"
    if [[ -z "$name" ]]; then
        err "Usage: snowfox web open <name>"
        return 1
    fi

    local safe
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    local desktop="$WEBAPP_DESK/snowfox-webapp-${safe}.desktop"
    if [[ ! -f "$desktop" ]]; then
        err "WebApp '$name' not found. List: snowfox web list"
        return 1
    fi

    local exec_cmd
    exec_cmd=$(grep "^Exec=" "$desktop" | cut -d= -f2-)
    fox "Opening ${BOLD}$name${RESET}..."
    eval "$exec_cmd" &
}

_webapp_remove() {
    local name="$1"
    if [[ -z "$name" ]]; then
        err "Usage: snowfox web remove <name>"
        return 1
    fi

    local safe
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    rm -f "$WEBAPP_DESK/snowfox-webapp-${safe}.desktop"
    rm -rf "$WEBAPP_DIR/$safe"
    rm -f "$WEBAPP_ICONS/${safe}.png"

    update-desktop-database "$WEBAPP_DESK" 2>/dev/null || true
    ok "WebApp '$name' removed."
}

# ============================================================
# snowfox wall — Wallpaper picker (Gum TUI)
#   snowfox wall      → Gum TUI
#   snowfox wall gui  → classic Rofi menu (~/.config/snowfox-wallpaper.sh)
# ============================================================
cmd_wallpaper() {
    case "${1:-}" in
        gui) exec "$HOME/.config/snowfox-wallpaper.sh" ;;
    esac

    if sf_can_tui; then
        _wallpaper_tui
        return 0
    fi

    if [[ -n "$DISPLAY" && -x "$HOME/.config/snowfox-wallpaper.sh" ]]; then
        exec "$HOME/.config/snowfox-wallpaper.sh"
    fi

    err "No interactive terminal (gum) and no graphical session."
    info "  Run in a terminal with gum installed, or inside X11 for the Rofi menu."
    return 1
}

_wallpaper_tui() {
    local wp_dir="$HOME/Pictures/wallpapers"
    [[ -d "$wp_dir" ]] || wp_dir="$HOME/wallpapers"

    if [[ ! -d "$wp_dir" ]]; then
        err "Wallpaper folder not found (~/Pictures/wallpapers)."
        sleep 1.2
        return 1
    fi

    local -a files=()
    local f
    while IFS= read -r f; do
        files+=("$f")
    done < <(ls "$wp_dir" 2>/dev/null | grep -iE "\.(jpg|jpeg|png|webp)$" | sort)

    if [[ ${#files[@]} -eq 0 ]]; then
        err "No wallpapers found in $wp_dir"
        sleep 1.2
        return 1
    fi

    local current
    current=$(grep -oP "(?<=--bg-fill ').*(?=')" "$HOME/.fehbg" 2>/dev/null | head -1)
    current=$(basename "${current:-unknown}")

    sf_banner "Wallpaper"
    sf_note "Current: $current · ${#files[@]} available"

    local choice st
    choice=$(printf '%s\n' "${files[@]}" | sf_filter "Select a wallpaper" "Type to filter — Enter applies it" 14)
    st=$?
    [[ $st -ne 0 || -z "$choice" ]] && return 0

    if ! command -v feh &>/dev/null; then
        err "feh not installed (sudo apt install feh)."
        sleep 1.2
        return 1
    fi
    if [[ -z "$DISPLAY" ]]; then
        err "No graphical session — cannot set the wallpaper."
        sleep 1.2
        return 1
    fi

    if feh --bg-fill "$wp_dir/$choice" 2>/dev/null; then
        ok "Wallpaper set: $choice"
    else
        err "Failed to set wallpaper."
    fi
    sleep 1
}

# ============================================================
# snowfox disp — Display setup (Gum TUI)
#   snowfox disp      → Gum TUI
#   snowfox disp gui  → classic Rofi menu (~/.config/snowfox-display.sh)
# ============================================================
cmd_display() {
    case "${1:-}" in
        gui) exec "$HOME/.config/snowfox-display.sh" ;;
    esac

    if sf_can_tui && command -v xrandr &>/dev/null && [[ -n "$DISPLAY" ]]; then
        _display_tui
        return 0
    fi

    if [[ -n "$DISPLAY" && -x "$HOME/.config/snowfox-display.sh" ]]; then
        exec "$HOME/.config/snowfox-display.sh"
    fi

    err "Display manager needs an active X session (xrandr)."
    return 1
}

_display_notify() {
    command -v notify-send &>/dev/null && notify-send "🦊 SnowFox Display" "$1" 2>/dev/null || true
}

_display_reload() {
    if pgrep -x i3 &>/dev/null; then
        i3-msg reload &>/dev/null || true
        sleep 0.5
        if [[ -x "$HOME/.config/polybar/launch.sh" ]]; then
            bash "$HOME/.config/polybar/launch.sh" &>/dev/null &
        fi
    fi
}

_display_tui() {
    while true; do
        local -a mons=()
        mapfile -t mons < <(xrandr --query | grep " connected" | awk '{print $1}')

        if [[ ${#mons[@]} -eq 0 ]]; then
            err "No monitors detected."
            sleep 1.2
            return 1
        fi

        sf_banner "Display Setup"

        local -a entries=()
        local m state primary
        for m in "${mons[@]}"; do
            if xrandr --query | grep "^$m " | grep -q "\*"; then state="ON "; else state="OFF"; fi
            primary=""
            xrandr --query | grep "^$m " | grep -q "connected primary" && primary="★"
            entries+=("🖥️   $m  [$state] $primary")
        done
        entries+=("──────────────────────────────")
        entries+=("🪞  Mirror all monitors")
        entries+=("↔️   Extend all (left–right)")
        entries+=("1️⃣   Primary monitor only")
        entries+=("🛠️   Configure arrangement")
        entries+=("🔄  Hybrid-Sync Refresh")
        entries+=("↩️   Back")

        local choice st
        choice=$(sf_choose "Displays" 14 "${entries[@]}")
        st=$?
        [[ $st -ne 0 || -z "$choice" ]] && return 0

        case "$choice" in
            *"Mirror all"*)           _display_mirror "${mons[@]}" ;;
            *"Extend all"*)           _display_extend "${mons[@]}" ;;
            *"Primary monitor only"*) _display_primary_only "${mons[@]}" ;;
            *"Configure arrangement"*) _display_arrange "${mons[@]}" ;;
            *"Hybrid-Sync"*)
                xrandr --auto && _display_notify "Hybrid-Sync buffer refreshed"
                _display_reload
                sleep 1
                ;;
            *Back*)                   return 0 ;;
            *"──────────────"*)       continue ;;
            *)
                # Monitor toggle (name is the second field)
                local mon
                mon=$(echo "$choice" | awk '{print $2}')
                [[ -z "$mon" ]] && continue
                if xrandr --query | grep "^$mon " | grep -q "\*"; then
                    xrandr --output "$mon" --off
                    _display_notify "$mon turned off"
                else
                    xrandr --output "$mon" --auto
                    _display_notify "$mon turned on"
                fi
                _display_reload
                sleep 1
                ;;
        esac
    done
}

_display_mirror() {
    local first="" m
    for m in "$@"; do
        xrandr --output "$m" --auto
        if [[ -z "$first" ]]; then
            xrandr --output "$m" --primary
            first="$m"
        else
            xrandr --output "$m" --same-as "$first"
        fi
    done
    _display_notify "All monitors mirrored"
    _display_reload
    sleep 1
}

_display_extend() {
    local primary anchor m
    primary=$(xrandr --query | grep " connected primary" | awk '{print $1}')
    anchor="${primary:-$1}"
    xrandr --output "$anchor" --auto --primary
    for m in "$@"; do
        if [[ "$m" != "$anchor" ]]; then
            xrandr --output "$m" --auto --right-of "$anchor"
        fi
    done
    _display_notify "Extended (left to right)"
    _display_reload
    sleep 1
}

_display_primary_only() {
    local primary m
    primary=$(xrandr --query | grep " connected primary" | awk '{print $1}')
    for m in "$@"; do
        if [[ "$m" == "$primary" ]]; then
            xrandr --output "$m" --auto --primary
        else
            xrandr --output "$m" --off
        fi
    done
    _display_notify "Primary monitor only"
    _display_reload
    sleep 1
}

_display_arrange() {
    local new_primary other pos st

    new_primary=$(sf_choose "Choose primary monitor" 8 "$@")
    st=$?
    [[ $st -ne 0 || -z "$new_primary" ]] && return 0

    other=""
    local m
    for m in "$@"; do
        [[ "$m" != "$new_primary" ]] && { other="$m"; break; }
    done

    if [[ -n "$other" ]]; then
        pos=$(sf_choose "$other position" 7 \
            "➡️   Right of $new_primary" \
            "⬅️   Left of $new_primary" \
            "⬆️   Above $new_primary" \
            "⬇️   Below $new_primary" \
            "⛔  Turn off" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$pos" || "$pos" == *Back* ]] && return 0

        xrandr --output "$new_primary" --auto --primary
        case "$pos" in
            *Right*)     xrandr --output "$other" --auto --right-of "$new_primary" ;;
            *Left*)      xrandr --output "$other" --auto --left-of  "$new_primary" ;;
            *Above*)     xrandr --output "$other" --auto --above    "$new_primary" ;;
            *Below*)     xrandr --output "$other" --auto --below    "$new_primary" ;;
            *"Turn off"*) xrandr --output "$other" --off ;;
        esac
    else
        xrandr --output "$new_primary" --auto --primary
    fi

    _display_notify "$new_primary is now primary"
    _display_reload
    sleep 1
}
