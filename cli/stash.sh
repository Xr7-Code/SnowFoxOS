#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — CLI: stash (package manager)
#  + snowfox-ai source-based installer
# ============================================================

if [[ -n "${_SNOWFOX_CLI_STASH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_SNOWFOX_CLI_STASH_LOADED=1

# ── snowfox-ai install metadata ─────────────────────────────
_SNOWFOX_AI_REPO="https://github.com/Xr7-Code/snowfox-ai.git"
_SNOWFOX_AI_SRC="/usr/local/share/snowfox/ai"
_SNOWFOX_AI_BIN="/usr/local/bin/snowfox-ai"

cmd_stash() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        "")        _stash_categories ;;
        list)      _stash_list_installed ;;
        find)      _stash_find "${1:-}" ;;
        info)      _stash_info "${1:-}" ;;
        install)
            if [[ "${1:-}" == "snowfox-ai" ]]; then
                _stash_install_snowfox_ai
            else
                _stash_install "${1:-}"
            fi
            ;;
        remove)
            if [[ "${1:-}" == "snowfox-ai" ]]; then
                _stash_remove_snowfox_ai
            else
                _stash_remove "${1:-}"
            fi
            ;;
        browser)   _stash_browser ;;
        *)         _stash_category "$sub" ;;
    esac
}

_stash_categories() {
    header "snowfox stash"
    row "browser"    "Firefox ESR, Chromium, LibreWolf, Zen, Brave, qutebrowser"
    row "media"      "mpv, vlc, gimp, obs-studio, yt-dlp"
    row "office"     "libreoffice, onlyoffice-desktopeditors"
    row "dev"        "vscodium, geany, git"
    row "privacy"    "tor, torsocks, librewolf"
    row "games"      "steam, gamemode, mangohud"
    row "snowfox-ai" "Terminal AI chat (source install from GitHub)"
    info "snowfox stash find <query>   search apt"
    info "snowfox stash install <pkg>  install a package"
}

_stash_browser() {
    header "snowfox stash browser"
    info "v4 default: Firefox ESR (§3b)"
    info "  sudo apt install firefox-esr"
    info "Alternatives:"
    info "  LibreWolf    → snowfox stash install librewolf"
    info "  Chromium     → snowfox stash install chromium"
    info "  Brave        → requires own repo (snowfox stash info brave-browser)"
    info "  Zen Browser  → manual (AppImage)"
    info "  qutebrowser  → snowfox stash install qutebrowser"
}

_stash_list_installed() {
    header "snowfox stash list"
    local list
    list=$(apt-mark showmanual 2>/dev/null)
    if [[ -z "$list" ]]; then
        info "no manually installed packages"
        return 0
    fi
    printf '%s\n' "$list" | while IFS= read -r p; do
        row "$p" ""
    done

    # snowfox-ai status
    if command -v snowfox-ai >/dev/null 2>&1; then
        row_dot "snowfox-ai" ok "$(command -v snowfox-ai)"
    else
        row_dot "snowfox-ai" err "not installed"
    fi
}

_stash_find() {
    local query="${1:-}"
    [[ -z "$query" ]] && { err "usage: snowfox stash find <query>"; return "$SNOWFOX_EXIT_ERROR"; }
    header "snowfox stash find $query"
    apt-cache search "$query" 2>/dev/null | head -n 30 | while IFS=' - ' read -r pkg desc; do
        row "$pkg" "$desc"
    done
}

_stash_info() {
    local pkg="${1:-}"
    [[ -z "$pkg" ]] && { err "usage: snowfox stash info <package>"; return "$SNOWFOX_EXIT_ERROR"; }

    if [[ "$pkg" == "snowfox-ai" ]]; then
        header "snowfox stash info snowfox-ai"
        row "repo"  "$_SNOWFOX_AI_REPO"
        row "src"   "$_SNOWFOX_AI_SRC"
        row "bin"   "$_SNOWFOX_AI_BIN"
        if command -v snowfox-ai >/dev/null 2>&1; then
            row_dot "status" ok "installed"
        else
            row_dot "status" err "not installed"
        fi
        return 0
    fi

    header "snowfox stash info $pkg"
    apt-cache show "$pkg" 2>/dev/null | awk '
        /^Package:/     {print "  package:  " $2}
        /^Version:/     {print "  version:  " $2}
        /^Installed-Size:/ {print "  size:     " $2 " KB"}
        /^Description:/ {found=1; print "  desc:     " substr($0,14); next}
        found && /^ /  {print "            " substr($0,2)}
    ' | head -n 20
}

_stash_install() {
    local pkg="${1:-}"
    [[ -z "$pkg" ]] && { err "usage: snowfox stash install <package>"; return "$SNOWFOX_EXIT_ERROR"; }
    header "snowfox stash install $pkg"
    if apt-get install -y "$pkg"; then
        ok "$pkg installed"
    else
        err "$pkg install failed"
        return "$SNOWFOX_EXIT_ERROR"
    fi
}

_stash_remove() {
    local pkg="${1:-}"
    [[ -z "$pkg" ]] && { err "usage: snowfox stash remove <package>"; return "$SNOWFOX_EXIT_ERROR"; }
    header "snowfox stash remove $pkg"
    if apt-get remove --purge -y "$pkg"; then
        ok "$pkg removed"
    else
        err "$pkg remove failed"
        return "$SNOWFOX_EXIT_ERROR"
    fi
}

_stash_category() {
    local cat="$1"
    header "snowfox stash $cat"
    case "$cat" in
        browser) _stash_browser ;;
        media)   apt-cache search '^(mpv|vlc|gimp|obs-studio|yt-dlp)' 2>/dev/null | while IFS=' - ' read -r p d; do row "$p" "$d"; done ;;
        office)  apt-cache search '^(libreoffice|onlyoffice)' 2>/dev/null | while IFS=' - ' read -r p d; do row "$p" "$d"; done ;;
        dev)     apt-cache search '^(vscodium|geany|git)$' 2>/dev/null | while IFS=' - ' read -r p d; do row "$p" "$d"; done ;;
        privacy) apt-cache search '^(tor|torsocks|librewolf)' 2>/dev/null | while IFS=' - ' read -r p d; do row "$p" "$d"; done ;;
        games)   apt-cache search '^(steam|gamemode|mangohud)' 2>/dev/null | while IFS=' - ' read -r p d; do row "$p" "$d"; done ;;
        *) err "unknown category: $cat"; return "$SNOWFOX_EXIT_ERROR" ;;
    esac
}

# ============================================================
#  snowfox-ai: source install / remove
# ============================================================

_stash_install_snowfox_ai() {
    header "snowfox stash install snowfox-ai"

    if [[ $EUID -ne 0 ]]; then
        err "this command must be run as root (try: sudo snowfox stash install snowfox-ai)"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    if ! command -v git >/dev/null 2>&1; then
        err "git not found — install with: apt-get install git"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    # ── 1. Repo klonen oder aktualisieren ───────────────────
    if [[ -d "$_SNOWFOX_AI_SRC/.git" ]]; then
        info "updating existing source at $_SNOWFOX_AI_SRC"
        git -C "$_SNOWFOX_AI_SRC" pull --ff-only \
            || { err "git pull failed"; return "$SNOWFOX_EXIT_ERROR"; }
    else
        info "cloning $_SNOWFOX_AI_REPO → $_SNOWFOX_AI_SRC"
        mkdir -p "$(dirname "$_SNOWFOX_AI_SRC")"
        git clone --depth 1 "$_SNOWFOX_AI_REPO" "$_SNOWFOX_AI_SRC" \
            || { err "git clone failed"; return "$SNOWFOX_EXIT_NETWORK"; }
    fi

    # ── 2. build.sh ausführen ───────────────────────────────
    if [[ ! -f "$_SNOWFOX_AI_SRC/build.sh" ]]; then
        err "build.sh not found in $_SNOWFOX_AI_SRC"
        return "$SNOWFOX_EXIT_ERROR"
    fi
    [[ -x "$_SNOWFOX_AI_SRC/build.sh" ]] || chmod +x "$_SNOWFOX_AI_SRC/build.sh"

    info "running build.sh"
    if ! ( cd "$_SNOWFOX_AI_SRC" && ./build.sh ); then
        err "build.sh failed"
        return "$SNOWFOX_EXIT_ERROR"
    fi
    ok "build.sh completed"

    # ── 3. Binary nach /usr/local/bin kopieren ──────────────
    local built_bin="$_SNOWFOX_AI_SRC/snowfox-ai"
    if [[ ! -x "$built_bin" ]]; then
        built_bin="$(find "$_SNOWFOX_AI_SRC" -maxdepth 3 -type f -name 'snowfox-ai' -perm -u+x | head -n1)"
    fi
    if [[ -z "$built_bin" || ! -x "$built_bin" ]]; then
        err "built binary not found — check build.sh output"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    install -m 0755 "$built_bin" "$_SNOWFOX_AI_BIN"
    ok "installed $_SNOWFOX_AI_BIN"

    # ── 4. User-Konfiguration anlegen ───────────────────────
    local real_user="${SUDO_USER:-$(id -un)}"
    local real_home
    real_home="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6)"
    if [[ -n "$real_home" ]]; then
        mkdir -p "$real_home/.config/snowfox"
        chown "$real_user":"$real_user" "$real_home/.config/snowfox" 2>/dev/null || true
        local ai_conf="$real_home/.config/snowfox/ai.conf"
        if [[ ! -f "$ai_conf" ]]; then
            cat > "$ai_conf" <<'EOF'
# SnowFox AI configuration
# backend: ollama | gemini
backend = gemini
model = gemini-2.0-flash
# api_key via GEMINI_API_KEY env var (recommended)
# api_key =
EOF
            chown "$real_user":"$real_user" "$ai_conf" 2>/dev/null || true
            ok "created $ai_conf"
        fi
    fi

    info "run: snowfox ai"
}

_stash_remove_snowfox_ai() {
    header "snowfox stash remove snowfox-ai"

    if [[ $EUID -ne 0 ]]; then
        err "this command must be run as root"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    local confirm
    read -rp "  remove snowfox-ai and its source at $_SNOWFOX_AI_SRC? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "aborted"; return 0; }

    [[ -x "$_SNOWFOX_AI_BIN" ]] && rm -f "$_SNOWFOX_AI_BIN" && ok "removed $_SNOWFOX_AI_BIN"
    [[ -d "$_SNOWFOX_AI_SRC" ]] && rm -rf "$_SNOWFOX_AI_SRC" && ok "removed $_SNOWFOX_AI_SRC"

    info "user config at ~/.config/snowfox/ai.conf left in place"
}
