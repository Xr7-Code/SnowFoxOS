#!/bin/bash
# ============================================================
#   SnowFoxOS — CLI Module: stash (Package Manager)
#   Curated categories + apt-cache search + size preview.
#   Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

STASH_CACHE_DIR="$HOME/.cache/snowfox"
STASH_INSTALLED_FILE="$STASH_CACHE_DIR/installed.list"

# ── Protected packages (never removable via stash) ───────────
STASH_PROTECTED=(
    i3 i3-wm i3status i3lock polybar rofi dunst
    xorg xserver-xorg-core xinit x11-xserver-utils
    network-manager bluez systemd dbus
    pipewire pipewire-pulse wireplumber
    kitty pcmanfm sudo
)

_stash_is_protected() {
    local pkg="$1"
    for p in "${STASH_PROTECTED[@]}"; do
        [[ "$pkg" == "$p" ]] && return 0
    done
    return 1
}

# ── Curated categories ───────────────────────────────────────
declare -A STASH_CATEGORIES=(
    ["internet"]="zen-browser librewolf brave-browser chromium firefox-esr thunderbird"
    ["office"]="onlyoffice-desktopeditors libreoffice gimp inkscape"
    ["ide"]="geany codium vim neovim emacs bluefish kate"
    ["media"]="vlc mpv audacity obs-studio kdenlive"
    ["gaming"]="steam lutris heroic-games-launcher gamemode mangohud"
    ["games"]="supertuxkart 0ad gnome-games"
    ["ai"]="ollama"
    ["security"]="keepassxc pass gnupg age tor torsocks macchanger"
    ["development"]="git build-essential python3 nodejs rustc golang"
    ["system"]="htop btop ncdu rsync tmux zsh fish"
    ["network"]="nmap wireshark tcpdump curl wget aria2 rsync"
    ["multimedia"]="ffmpeg imagemagick yt-dlp flameshot scrot"
)

# ── Spinner — delegates to shared spin_start/spin_stop in utils.sh ──
_stash_spinner_start() { spin_start "$1"; }
_stash_spinner_stop()  { spin_stop;       }

# ── Size preview via apt simulation / cache ──────────────────
_stash_preview_size() {
    local pkg="$1"
    local size_bytes
    
    # Try apt-cache first
    size_bytes=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 '^Size:' | awk '{print $2}')
    
    # Fallback: parse from apt-get simulation if size is missing
    if [[ -z "$size_bytes" || "$size_bytes" -eq 0 ]]; then
        size_bytes=$(apt-get install --simulate "$pkg" 2>/dev/null | grep -i "need to get" | grep -oE '[0-9.,]+ [kMG]?B' | head -1)
        echo "${size_bytes:-unknown}"
        return
    fi

    local size_str="unknown"
    if [[ -n "$size_bytes" && "$size_bytes" -gt 0 ]]; then
        if   [[ "$size_bytes" -ge 1073741824 ]]; then
            size_str=$(awk "BEGIN {printf \"%.1f GB\", $size_bytes/1073741824}")
        elif [[ "$size_bytes" -ge 1048576 ]]; then
            size_str=$(awk "BEGIN {printf \"%.1f MB\", $size_bytes/1048576}")
        elif [[ "$size_bytes" -ge 1024 ]]; then
            size_str=$(awk "BEGIN {printf \"%.0f KB\", $size_bytes/1024}")
        else
            size_str="${size_bytes} B"
        fi
    fi

    echo "$size_str"
}

# ============================================================
# snowfox stash — Main dispatcher
# ============================================================
cmd_stash() {
    # ── Gum TUI: interactive package manager ─────────────────
    if [[ -z "${1:-}" ]] && sf_can_tui; then
        _stash_tui
        return 0
    fi

    if [[ -z "${1:-}" ]]; then
        _stash_categories
        return
    fi

    if [[ -n "${STASH_CATEGORIES[$1]}" ]]; then
        _stash_show_category "$1"
        return
    fi

    case "$1" in
        find)
            shift
            _stash_find "$*"
            ;;
        info)
            _stash_info "$2"
            ;;
        install)
            _stash_install "$2"
            ;;
        list)
            _stash_installed_list
            ;;
        remove)
            _stash_remove "$2"
            ;;
        upgrade)
            _stash_upgrade
            ;;
        *)
            header "snowfox stash"
            info "  snowfox stash              — show curated categories"
            info "  snowfox stash <category>   — list packages in a category"
            info "  snowfox stash find <query> — search apt repositories"
            info "  snowfox stash info <pkg>   — show package details"
            info "  snowfox stash install <pkg>— install a package"
            info "  snowfox stash list         — list installed apps"
            info "  snowfox stash remove <pkg> — remove a package"
            info "  snowfox stash upgrade      — upgrade all installed packages"
            echo ""
            divider
            info "Categories: internet, office, ide, media, gaming, games,"
            info "            ai, security, development, system, network, multimedia"
            echo ""
            ;;
    esac
}

# ============================================================
# Upgrade all installed packages
# ============================================================
_stash_upgrade() {
    header "stash — Upgrade"

    info "Checking for updates..."
    local updates
    updates=$(apt-get --simulate upgrade 2>/dev/null | grep "^Inst" | wc -l)

    if [[ "$updates" -eq 0 ]]; then
        ok "All packages are up to date."
        echo ""
        return
    fi

    row "Upgradeable" "$updates package(s)" "$ORANGE"
    echo ""

    # Show what will be upgraded
    apt-get --simulate upgrade 2>/dev/null | grep "^Inst" | awk '{printf "  \033[0;36m%s\033[0m\n", $2}' | head -20
    [[ "$updates" -gt 20 ]] && info "  ... and $((updates-20)) more"
    echo ""

    read -rp "$(echo -e "${PURPLE}${BOLD}Upgrade all? [y/N]: ${RESET}")" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        info "Cancelled."
        return 0
    fi

    echo ""
    spin_start "Upgrading packages..."
    sudo apt-get upgrade -y > /tmp/stash-upgrade.log 2>&1
    local EXIT=$?
    spin_stop

    if [[ $EXIT -eq 0 ]]; then
        ok "Upgrade complete."
    else
        err "Upgrade failed. Log: /tmp/stash-upgrade.log"
        return 1
    fi
    sudo apt-get autoremove -y >> /tmp/stash-upgrade.log 2>&1
    echo ""
}

# ============================================================
# Category overview
# ============================================================
_stash_categories() {
    header "stash — Categories"

    for cat in internet office ide media gaming games ai security development system network multimedia; do
        local count
        count=$(echo "${STASH_CATEGORIES[$cat]}" | wc -w)
        printf "  ${CYAN}%-14s${RESET} ${DGRAY}%2d packages${RESET}\n" "$cat" "$count"
    done

    divider
    info "Show category: snowfox stash <category>"
    info "Search all:    snowfox stash find <query>"
    echo ""
}

# ============================================================
# List packages in a category
# ============================================================
_stash_show_category() {
    local cat="$1"

    header "stash — $cat"

    local pkgs="${STASH_CATEGORIES[$cat]}"
    for pkg in $pkgs; do
        local status status_color
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            status="installed"
            status_color="$GREEN"
        elif apt-cache show "$pkg" &>/dev/null; then
            status="available"
            status_color="$CYAN"
        else
            status="unavailable"
            status_color="$RED"
        fi
        printf "  ${status_color}%-32s${RESET} ${DGRAY}%s${RESET}\n" "$pkg" "$status"
    done

    divider
    info "Install: snowfox stash install <package>"
    echo ""
}

# ============================================================
# Search apt repositories
# ============================================================
_stash_find() {
    local query="$1"

    if [[ -z "$query" ]]; then
        err "Usage: snowfox stash find <query>"
        return 1
    fi

    header "stash — Search: $query"

    local results
    results=$(apt-cache search "$query" 2>/dev/null | head -30)

    if [[ -z "$results" ]]; then
        info "No results for '$query'."
        return 0
    fi

    while IFS= read -r line; do
        local pkg desc
        pkg=$(echo "$line" | cut -d' ' -f1)
        desc=$(echo "$line" | cut -d' ' -f2- | cut -c1-60)

        local color="$CYAN"
        dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && color="$GREEN"

        printf "  ${color}%-28s${RESET} ${DGRAY}%s${RESET}\n" "$pkg" "$desc"
    done <<< "$results"

    divider
    info "Install: snowfox stash install <package>"
    echo ""
}

# ============================================================
# Package info
# ============================================================
_stash_info() {
    local pkg="$1"

    if [[ -z "$pkg" ]]; then
        err "Usage: snowfox stash info <package>"
        return 1
    fi

    if ! apt-cache show "$pkg" &>/dev/null; then
        err "Package '$pkg' not found."
        return 1
    fi

    header "stash — $pkg"

    local version size desc homepage
    version=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 "^Version:" | awk '{print $2}')
    size=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 "^Size:" | awk '{print $2}')
    desc=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 "^Description-en:" | cut -d: -f2- | xargs)
    homepage=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 "^Homepage:" | awk '{print $2}')

    row "Version" "${version:-unknown}"
    if [[ -n "$size" ]]; then
        local size_mb
        size_mb=$(awk "BEGIN {printf \"%.1f\", $size/1024/1024}")
        row "Size" "${size_mb} MB"
    fi
    [[ -n "$homepage" ]] && row "Homepage" "$homepage"
    echo ""
    [[ -n "$desc" ]] && info "$desc"

    divider
    info "Install: snowfox stash install $pkg"
    echo ""
}

# ============================================================
# Install a package
# ============================================================
_stash_install() {
    local pkg="$1"

    if [[ -z "$pkg" ]]; then
        err "Usage: snowfox stash install <package>"
        return 1
    fi

    if ! apt-cache show "$pkg" &>/dev/null; then
        err "Package '$pkg' not found."
        info "  Search: snowfox stash find <query>"
        return 1
    fi

    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        info "Package '$pkg' is already installed."
        return 0
    fi

    header "stash — Install: $pkg"

    info "Analyzing package..."
    local download_size
    download_size=$(_stash_preview_size "$pkg")

    echo ""
    if [[ "$download_size" != "unknown" ]]; then
        row "Download size" "$download_size"
    else
        row "Download size" "unknown" "$ORANGE"
    fi
    echo ""

    read -rp "$(echo -e ${PURPLE}${BOLD}"Install? [y/N]: "${RESET})" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        info "Cancelled."
        return 0
    fi

    echo ""
    _stash_spinner_start "Installing $pkg..."
    sudo apt-get install -y "$pkg" > /tmp/stash-install.log 2>&1
    local EXIT=$?
    _stash_spinner_stop

    if [[ $EXIT -eq 0 ]]; then
        ok "$pkg installed."
    else
        err "Installation failed."
        info "  Log: /tmp/stash-install.log"
        return 1
    fi
}

# ============================================================
# List installed apps
# ============================================================
_stash_installed_list() {
    header "stash — Installed Apps"

    local dirs=("/usr/share/applications" "$HOME/.local/share/applications")
    local found=false

    printf "  ${DGRAY}%-32s %s${RESET}\n" "App" "Package"
    divider

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.desktop; do
            [[ -e "$file" ]] || continue
            grep -q "^NoDisplay=true" "$file" 2>/dev/null && continue

            local app_name pkg
            app_name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
            [[ -z "$app_name" ]] && app_name=$(basename "$file" .desktop)

            pkg=$(dpkg -S "applications/$(basename "$file")" 2>/dev/null | cut -d: -f1 | head -1)
            [[ -z "$pkg" ]] && pkg="(manual)"

            if [[ "$pkg" == "(manual)" ]]; then
                printf "  ${CYAN}%-32s${RESET} ${GRAY}%s${RESET}\n" "$app_name" "$pkg"
            elif _stash_is_protected "$pkg"; then
                printf "  ${CYAN}%-32s${RESET} ${ORANGE}%s [protected]${RESET}\n" "$app_name" "$pkg"
            else
                printf "  ${CYAN}%-32s${RESET} ${DGRAY}%s${RESET}\n" "$app_name" "$pkg"
            fi
            found=true
        done
    done

    $found || info "No applications found."
    divider
    info "Remove: snowfox stash remove <package>"
    echo ""
}

# ============================================================
# Remove a package
# ============================================================
_stash_remove() {
    local pkg="$1"

    if [[ -z "$pkg" ]]; then
        err "Usage: snowfox stash remove <package>"
        info "  List installed: snowfox stash list"
        return 1
    fi

    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        err "Package '$pkg' is not installed."
        return 1
    fi

    if _stash_is_protected "$pkg"; then
        err "'$pkg' is a system component and cannot be removed."
        warn "Removing it would break SnowFoxOS."
        return 1
    fi

    header "stash — Remove: $pkg"

    local size
    size=$(dpkg-query -W --showformat='${Installed-Size}' "$pkg" 2>/dev/null)
    if [[ -n "$size" ]]; then
        local size_mb
        size_mb=$(awk "BEGIN {printf \"%.1f\", $size/1024}")
        row "Installed size" "${size_mb} MB"
    fi
    echo ""

    read -rp "$(echo -e ${ORANGE}${BOLD}"Remove $pkg? [y/N]: "${RESET})" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        info "Cancelled."
        return 0
    fi

    echo ""
    _stash_spinner_start "Removing $pkg..."
    sudo apt-get purge -y "$pkg" > /tmp/stash-remove.log 2>&1
    local EXIT=$?
    sudo apt-get autoremove -y >> /tmp/stash-remove.log 2>&1
    _stash_spinner_stop

    if [[ $EXIT -eq 0 ]]; then
        ok "$pkg removed."
    else
        err "Removal failed."
        info "  Log: /tmp/stash-remove.log"
        return 1
    fi
}

# ============================================================
#  Gum TUI — Software Stash
# ============================================================
_stash_tui() {
    while true; do
        sf_banner "Software Stash"

        local installed_total
        installed_total=$(dpkg -l 2>/dev/null | grep -c "^ii")
        sf_note "$installed_total packages installed · curated catalog + apt search"

        local choice st
        choice=$(sf_choose "What would you like to do?" 9 \
            "📂  Browse categories" \
            "🔍  Search apt repositories" \
            "📋  Installed applications" \
            "⬆️   Upgrade all packages" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *categories*)  _stash_tui_categories ;;
            *Search*)      _stash_tui_search ;;
            *Installed*)   _stash_tui_installed ;;
            *Upgrade*)     _stash_tui_upgrade ;;
        esac
    done
}

_stash_tui_categories() {
    local cats=(internet office ide media gaming games ai security development system network multimedia)
    local -a display=()
    local c
    for c in "${cats[@]}"; do
        display+=("📦  $c  ($(echo "${STASH_CATEGORIES[$c]}" | wc -w) packages)")
    done
    display+=("↩   Back")

    local choice st
    choice=$(sf_choose "Category" 15 "${display[@]}")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local cat
    cat=$(echo "$choice" | awk '{print $2}')
    [[ -z "${STASH_CATEGORIES[$cat]:-}" ]] && return 0

    local -a entries=()
    local pkg status
    for pkg in ${STASH_CATEGORIES[$cat]}; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            status="✅ installed"
        elif apt-cache show "$pkg" &>/dev/null; then
            status="⬇️  available"
        else
            status="❌ unavailable"
        fi
        entries+=("$pkg  $status")
    done

    local pkg_line
    pkg_line=$(printf '%s\n' "${entries[@]}" | sf_filter "stash · $cat" "Type to filter — Enter for actions" 12)
    st=$?
    [[ $st -ne 0 || -z "$pkg_line" ]] && return 0

    pkg=$(echo "$pkg_line" | awk '{print $1}')
    [[ -n "$pkg" ]] && _stash_tui_package "$pkg"
}

_stash_tui_search() {
    local q
    q=$(sf_ask_ph "Search apt repositories" "e.g. editor, video, python")
    [[ -z "$q" ]] && return 0

    local tmp
    tmp=$(mktemp)
    gum spin --spinner dot \
        --title "Searching apt for \"$q\"…" \
        --spinner.foreground "$GUM_PURPLE_LT" \
        --title.foreground "$GUM_FG" \
        -- bash -c 'apt-cache search "$1" 2>/dev/null | head -80 > "$2"' _ "$q" "$tmp"

    if [[ ! -s "$tmp" ]]; then
        err "No results for '$q'."
        rm -f "$tmp"
        sleep 1.2
        return 0
    fi

    local line st
    line=$(sf_filter "Results for \"$q\"" "Type to filter — Enter for actions" 15 < "$tmp")
    st=$?
    rm -f "$tmp"
    [[ $st -ne 0 || -z "$line" ]] && return 0

    local pkg
    pkg=$(echo "$line" | cut -d' ' -f1)
    [[ -n "$pkg" ]] && _stash_tui_package "$pkg"
}

_stash_tui_installed() {
    local -a entries=()
    local dir file app pkg

    for dir in /usr/share/applications "$HOME/.local/share/applications"; do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.desktop; do
            [[ -e "$file" ]] || continue
            grep -q "^NoDisplay=true" "$file" 2>/dev/null && continue
            app=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
            [[ -z "$app" ]] && app=$(basename "$file" .desktop)
            pkg=$(dpkg -S "applications/$(basename "$file")" 2>/dev/null | cut -d: -f1 | head -1)
            [[ -z "$pkg" ]] && pkg="(manual)"
            entries+=("$app — $pkg")
        done
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        info "No applications found."
        sleep 1.2
        return 0
    fi

    local line st
    line=$(printf '%s\n' "${entries[@]}" | sf_filter "Installed applications" "Type to filter — Enter for actions" 15)
    st=$?
    [[ $st -ne 0 || -z "$line" ]] && return 0

    pkg="${line##*— }"
    [[ -z "$pkg" || "$pkg" == "(manual)" ]] && return 0
    _stash_tui_package "$pkg"
}

_stash_tui_package() {
    local pkg="$1"
    local installed=false
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && installed=true

    local -a actions=("👁   Show details")
    if $installed; then
        actions+=("🗑   Remove package")
    else
        actions+=("⬇   Install package")
    fi
    actions+=("↩   Back")

    local choice st
    choice=$(sf_choose "$pkg" 5 "${actions[@]}")
    st=$?
    [[ $st -ne 0 || -z "$choice" ]] && return 0

    case "$choice" in
        *details*) _stash_tui_info "$pkg" ;;
        *Install*) _stash_tui_install "$pkg" ;;
        *Remove*)  _stash_tui_remove "$pkg" ;;
    esac
}

_stash_tui_info() {
    local pkg="$1" tmp
    tmp=$(mktemp)
    _stash_info "$pkg" > "$tmp" 2>&1
    sf_page "stash · $pkg" "$tmp"
    rm -f "$tmp"
}

_stash_tui_install() {
    local pkg="$1"

    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "'$pkg' is already installed."
        sleep 1
        return 0
    fi
    if ! apt-cache show "$pkg" &>/dev/null; then
        err "Package '$pkg' not found."
        sleep 1.2
        return 1
    fi

    local size
    size=$(_stash_preview_size "$pkg")

    if ! sf_yesno "Install '$pkg'? (download: $size)" "Install" "Cancel" yes; then
        return 0
    fi

    echo ""
    sudo apt-get install -y "$pkg"
    if [[ $? -eq 0 ]]; then
        ok "$pkg installed."
    else
        err "Installation failed — see the output above."
    fi
    sf_pause "Press Enter to continue…"
}

_stash_tui_remove() {
    local pkg="$1"

    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        err "Package '$pkg' is not installed."
        sleep 1.2
        return 1
    fi
    if _stash_is_protected "$pkg"; then
        err "'$pkg' is a system component and cannot be removed."
        sleep 1.5
        return 1
    fi

    if ! sf_yesno "Remove '$pkg' and clean up unused dependencies?" "Remove" "Cancel" no; then
        return 0
    fi

    echo ""
    sudo apt-get purge -y "$pkg"
    local rc=$?
    sudo apt-get autoremove -y
    if [[ $rc -eq 0 ]]; then
        ok "$pkg removed."
    else
        err "Removal failed — see the output above."
    fi
    sf_pause "Press Enter to continue…"
}

_stash_tui_upgrade() {
    local updates
    updates=$(apt-get --simulate upgrade 2>/dev/null | grep "^Inst" | wc -l)

    if [[ "$updates" -eq 0 ]]; then
        ok "All packages are up to date."
        sleep 1.2
        return 0
    fi

    sf_note "$updates package(s) can be upgraded"
    if ! sf_yesno "Upgrade all $updates packages now?" "Upgrade" "Cancel" no; then
        return 0
    fi

    echo ""
    sudo apt-get upgrade -y
    local rc=$?
    sudo apt-get autoremove -y
    if [[ $rc -eq 0 ]]; then
        ok "Upgrade complete."
    else
        err "Upgrade failed — see the output above."
    fi
    sf_pause "Press Enter to continue…"
}
