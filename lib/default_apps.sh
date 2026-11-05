#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Default Applications Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - yt-dlp fetched via _fetch_verified (SHA256-pinned)
#   - gum GitHub fallback via _fetch_verified (SHA256-pinned)
#   - VSCodium / OnlyOffice GPG keys verified against pinned
#     fingerprints before being trusted
#   - all curl calls constrained to HTTPS + TLS 1.2
#   - pipefail set locally around key-import pipelines
#   - uname resolved via absolute path
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/checksums.sh"

step "5/10 — Terminal & Default Apps"

wait_apt
apt-get install -y \
    kitty \
    mc \
    ristretto \
    file-roller \
    mpv \
    ffmpeg

echo ""
echo -e "${PURPLE}${BOLD}  File manager:${RESET}"
echo -e "  1) PCManFM (graphical, lightweight — recommended)"
echo -e "  2) MC      (terminal, already installed)"
echo -e "  3) Both"
echo ""
if [[ "$SNOWFOX_UNATTENDED" == "true" ]] || [[ ! -t 0 ]]; then
    FM_CHOICE="1"
    info "Unattended mode: selecting PCManFM (1)"
else
    read -rp "$(echo -e ${PURPLE}${BOLD}"Choice [1-3]: "${RESET})" FM_CHOICE
fi
case "$FM_CHOICE" in
    1|3) apt-get install -y pcmanfm gvfs gvfs-backends
         success "PCManFM installed" ;;
    2)   success "MC already installed" ;;
    *)   apt-get install -y pcmanfm gvfs gvfs-backends
         success "PCManFM installed (default)" ;;
esac

if ask_install "VLC Media Player"; then
    apt-get install -y vlc && success "VLC installed"
fi

# ── Code Editor / IDE ────────────────────────────────────────
apt-get install -y geany \
    geany-plugin-addons \
    geany-plugin-autoclose \
    geany-plugin-codenav \
    geany-plugin-ctags \
    geany-plugin-git-changebar \
    geany-plugin-projectorganizer \
    geany-plugin-spellcheck \
    geany-plugin-treebrowser
success "Geany + plugins installed"

# ── Screenshot Tool ──────────────────────────────────────────
apt-get install -y flameshot
success "Flameshot installed"

# ── GIMP only as optional ────────────────────────────────────
if ask_install "GIMP (professional image editing, ~300 MB)"; then
    apt-get install -y gimp && success "GIMP installed"
fi

# ── VSCodium (third-party repo, pinned key) ──────────────────
# CHANGED: the GPG key is now verified against a pinned
# fingerprint before being installed. Without this check, a
# compromised gitlab.com endpoint could serve a different key
# on first import, and signed-by would then trust it forever.
if ask_install "VSCodium"; then
    set -o pipefail
    _VSCODIUM_KEY_FPR="${VSCODIUM_GPG_FPR:-}"   # pinned in checksums.sh
    if [[ -z "$_VSCODIUM_KEY_FPR" || "$_VSCODIUM_KEY_FPR" == "UNPINNED" ]]; then
        warn "VSCodium GPG fingerprint not pinned — skipping VSCodium."
        warn "Pin VSCODIUM_GPG_FPR in lib/checksums.sh to enable it."
    else
        _tmp_key=$(mktemp)
        if curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
             https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
             -o "$_tmp_key"; then
            _actual_fpr=$(gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null \
                | awk -F: '/^fpr:/ {print $10; exit}')
            if [[ "$_actual_fpr" == "$_VSCODIUM_KEY_FPR" ]]; then
                gpg --dearmor < "$_tmp_key" \
                    > /usr/share/keyrings/vscodium-archive-keyring.gpg
                chmod 0644 /usr/share/keyrings/vscodium-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" \
                    > /etc/apt/sources.list.d/vscodium.list
                chmod 0644 /etc/apt/sources.list.d/vscodium.list
                wait_apt; apt-get update -qq
                apt-get install -y codium && success "VSCodium installed" \
                    || warn "VSCodium install failed"
            else
                warn "VSCodium GPG key fingerprint mismatch — refusing to install."
                warn "  expected: $_VSCODIUM_KEY_FPR"
                warn "  actual:   $_actual_fpr"
            fi
        else
            warn "VSCodium key download failed"
        fi
        rm -f "$_tmp_key"
    fi
    set +o pipefail
fi

# ── OnlyOffice (third-party repo, pinned key) ────────────────
if ask_install "OnlyOffice"; then
    set -o pipefail
    _ONLYOFFICE_KEY_FPR="${ONLYOFFICE_GPG_FPR:-}"
    if [[ -z "$_ONLYOFFICE_KEY_FPR" || "$_ONLYOFFICE_KEY_FPR" == "UNPINNED" ]]; then
        warn "OnlyOffice GPG fingerprint not pinned — skipping OnlyOffice."
    else
        mkdir -p -m 755 /etc/apt/keyrings
        _tmp_key=$(mktemp)
        if curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
             https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
             -o "$_tmp_key"; then
            _actual_fpr=$(gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null \
                | awk -F: '/^fpr:/ {print $10; exit}')
            if [[ "$_actual_fpr" == "$_ONLYOFFICE_KEY_FPR" ]]; then
                gpg --dearmor < "$_tmp_key" \
                    > /etc/apt/keyrings/onlyoffice.gpg
                chmod 0644 /etc/apt/keyrings/onlyoffice.gpg
                echo "deb [signed-by=/etc/apt/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
                    > /etc/apt/sources.list.d/onlyoffice.list
                chmod 0644 /etc/apt/sources.list.d/onlyoffice.list
                wait_apt; apt-get update -qq
                apt-get install -y onlyoffice-desktopeditors && success "OnlyOffice installed" \
                    || warn "OnlyOffice install failed"
            else
                warn "OnlyOffice GPG key fingerprint mismatch — refusing to install."
                warn "  expected: $_ONLYOFFICE_KEY_FPR"
                warn "  actual:   $_actual_fpr"
            fi
        else
            warn "OnlyOffice key download failed"
        fi
        rm -f "$_tmp_key"
    fi
    set +o pipefail
fi

# ── yt-dlp (SHA256-pinned) ───────────────────────────────────
# CHANGED: was a bare curl into /usr/local/bin. Now verified.
# yt-dlp releases frequently — update CHECKSUM_YTDLP via
# "snowfox update-checksums" or manually.
info "Installing yt-dlp (verified)..."
_fetch_verified \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    /usr/local/bin/yt-dlp \
    "${CHECKSUM_YTDLP}" \
    "yt-dlp" \
    && chmod 0755 /usr/local/bin/yt-dlp \
    && success "yt-dlp installed" \
    || warn "yt-dlp skipped — pin CHECKSUM_YTDLP in lib/checksums.sh"

# Node.js — JS runtime for yt-dlp
apt-get install -y nodejs 2>/dev/null || true
success "Node.js installed (JS runtime for yt-dlp)"

# ── gum — Charm TUI toolkit for "snowfox music" ──────────────
if command -v gum &>/dev/null; then
    info "gum already installed"
else
    info "Installing gum (TUI toolkit for snowfox music)..."
    GUM_OK="false"

    # Try Debian/backports first (no pinning needed — apt handles it)
    if apt-get install -y gum 2>/dev/null; then
        GUM_OK="true"
    else
        # GitHub fallback — SHA256-pinned
        case "$(/usr/bin/uname -m)" in
            x86_64|amd64)  GUM_ARCH="x86_64" ;;
            aarch64|arm64) GUM_ARCH="arm64" ;;
            armv7l)        GUM_ARCH="armv7" ;;
            armv6l)        GUM_ARCH="armv6" ;;
            i386|i686)     GUM_ARCH="i386" ;;
            *)             GUM_ARCH="" ;;
        esac

        if [[ -n "$GUM_ARCH" ]]; then
            # Resolve latest version via jq (fallback to python3)
            if command -v jq >/dev/null 2>&1; then
                GUM_VER=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
                    "https://api.github.com/repos/charmbracelet/gum/releases/latest" 2>/dev/null \
                    | jq -r '.tag_name // empty' | sed 's/^v//')
            else
                GUM_VER=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
                    "https://api.github.com/repos/charmbracelet/gum/releases/latest" 2>/dev/null \
                    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null)
            fi

            if [[ -n "$GUM_VER" ]]; then
                _tmp_gum=$(mktemp --suffix=.tar.gz)
                if _fetch_verified \
                     "https://github.com/charmbracelet/gum/releases/download/v${GUM_VER}/gum_${GUM_VER}_Linux_${GUM_ARCH}.tar.gz" \
                     "$_tmp_gum" "${CHECKSUM_GUM}" "gum"; then
                    if tar -xzf "$_tmp_gum" -C /usr/local/bin --strip-components=1 'gum_*/gum'; then
                        chmod 0755 /usr/local/bin/gum
                        GUM_OK="true"
                    fi
                fi
                rm -f "$_tmp_gum"
            fi
        fi
    fi

    if [[ "$GUM_OK" == "true" ]]; then
        success "gum installed"
    else
        warn "gum could not be installed — 'snowfox music' will show manual instructions"
    fi
fi

# ── Clone SnowFox Console Launcher ───────────────────────────
info "Cloning SnowFox Console Launcher..."
if git clone --depth 1 https://github.com/Xr7-Code/SnowFox-Console-Launcher \
    "$TARGET_HOME/SnowFox-Console-Launcher" 2>/dev/null; then
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/SnowFox-Console-Launcher"
    success "SnowFox Console Launcher cloned to ~/SnowFox-Console-Launcher"
else
    warn "SnowFox Console Launcher could not be cloned — install manually"
fi
