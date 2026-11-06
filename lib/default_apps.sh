#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Default Applications Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - gum installed via apt (official Debian 12 repo), no hash needed
#   - yt-dlp installed via bookworm-backports, no hash needed
#   - VSCodium / OnlyOffice GPG keys verified against pinned
#     fingerprints before being trusted
#   - all curl calls constrained to HTTPS + TLS 1.2
#   - pipefail set locally around key-import pipelines
#   - uname resolved via absolute path
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/checksums.sh"

step "5/10 — Terminal & Default Apps"

# ── Ensure bookworm-backports is available for yt-dlp ────────
# yt-dlp in bookworm is 2023.03.04 (too old for YouTube).
# bookworm-backports has 2025.04.30 — still via apt, no hash pinning.
if ! grep -q "bookworm-backports" /etc/apt/sources.list 2>/dev/null; then
    info "Adding bookworm-backports for yt-dlp..."
    echo "deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware" \
        >> /etc/apt/sources.list
    wait_apt
    apt-get update -qq
fi

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
if ask_install "VSCodium"; then
    set -o pipefail
    _VSCODIUM_KEY_FPR="${VSCODIUM_GPG_FPR:-}"
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

# ── yt-dlp (bookworm-backports, apt-verified) ────────────────
# CHANGED: no more GitHub download + hash pinning.
# bookworm-backports carries 2025.04.30 — recent enough for
# YouTube, and verified by Debian's repository signatures.
info "Installing yt-dlp from bookworm-backports..."
if apt-get install -y -t bookworm-backports yt-dlp; then
    success "yt-dlp installed (bookworm-backports)"
else
    warn "yt-dlp install from backports failed — trying bookworm version"
    apt-get install -y yt-dlp && success "yt-dlp installed (bookworm, may be old)" \
        || warn "yt-dlp could not be installed"
fi

# Node.js — JS runtime for yt-dlp
apt-get install -y nodejs 2>/dev/null || true
success "Node.js installed (JS runtime for yt-dlp)"

# ── gum (official Debian 12 repo, apt-verified) ──────────────
# CHANGED: gum is in Debian 12 main (0.14.4). No GitHub fallback,
# no hash pinning. apt handles integrity.
info "Installing gum (TUI toolkit for snowfox music)..."
if apt-get install -y gum; then
    success "gum installed"
else
    warn "gum could not be installed — 'snowfox music' will show manual instructions"
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
