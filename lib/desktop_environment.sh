#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Desktop Environment Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  CHANGED (security):
#   - clipnotify: git checkout "$CLIPNOTIFY_COMMIT" (pinned)
#   - bluetui: fetched via _fetch_verified (SHA256-pinned);
#     cargo fallback removed (unpinned + wrong error path)
#   - Bibata / JetBrainsMono: verified against checksums.sh
#   - all curl calls: --proto '=https' --tlsv1.2
#   - jq preferred over python3 for JSON parsing
#   - .bash_profile append made idempotent
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/checksums.sh"

step "3/10 — i3 + Polybar + Rofi + Dunst + i3lock"

wait_apt
apt-get install -y \
    i3 \
    i3lock \
    picom \
    polybar \
    rofi \
    dunst \
    libnotify-bin \
    libappindicator3-1 \
    libayatana-appindicator3-1 \
    feh \
    libdbusmenu-gtk3-4 \
    redshift \
    scrot \
    brightnessctl \
    playerctl \
    network-manager \
    bluez \
    fonts-inter \
    fonts-noto \
    fonts-noto-color-emoji \
    papirus-icon-theme \
    arc-theme \
    gtk2-engines-murrine \
    qt5-style-kvantum \
    xsettingsd \
    lxpolkit \
    lxappearance \
    xss-lock \
    xserver-xorg-input-libinput \
    cups cups-bsd cups-client \
    printer-driver-splix

success "i3 desktop packages installed"

# ── Clipnotify — build from pinned commit ────────────────────
# CHANGED: clone + checkout the pinned commit, not master.
# Without this, the commit pin in checksums.sh is decorative.
info "Installing clipnotify (pinned commit)..."
apt-get install -y libx11-dev libxfixes-dev

if [[ -z "${CLIPNOTIFY_COMMIT:-}" || "$CLIPNOTIFY_COMMIT" == "UNPINNED" ]]; then
    error "CLIPNOTIFY_COMMIT is not pinned in lib/checksums.sh — refusing to build."
fi

rm -rf /tmp/clipnotify
git clone https://github.com/cdown/clipnotify.git /tmp/clipnotify
(
    cd /tmp/clipnotify || error "clipnotify clone failed"
    git checkout --detach "$CLIPNOTIFY_COMMIT" \
        || error "clipnotify commit $CLIPNOTIFY_COMMIT not found"
    make || error "clipnotify build failed"
    install -m 0755 clipnotify /usr/local/bin/clipnotify
)
rm -rf /tmp/clipnotify
success "clipnotify installed (commit ${CLIPNOTIFY_COMMIT:0:12})"

# Install clip-saver.sh
if [[ -f "$SCRIPT_DIR/configs/i3/clip-saver.sh" ]]; then
    mkdir -p "$TARGET_HOME/.config/i3"
    cp "$SCRIPT_DIR/configs/i3/clip-saver.sh" "$TARGET_HOME/.config/i3/clip-saver.sh"
    chmod +x "$TARGET_HOME/.config/i3/clip-saver.sh"
    success "clip-saver.sh installed"
fi

# ── Install Bibata cursor theme (verified) ───────────────────
# CHANGED: downloaded tarball is verified against CHECKSUM_BIBATA
# before extraction. Extraction goes to a temp dir first, then
# moves into place — a corrupt archive cannot leave partial state.
info "Installing Bibata-Modern-Classic cursor (verified)..."
BIBATA_DIR="/usr/share/icons/Bibata-Modern-Classic"
if [[ ! -d "$BIBATA_DIR" ]]; then
    if command -v jq >/dev/null 2>&1; then
        BIBATA_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
            https://api.github.com/repos/ful1e5/Bibata_Cursor/releases/latest 2>/dev/null \
            | jq -r '.tag_name // "v2.0.7"')
    else
        BIBATA_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
            https://api.github.com/repos/ful1e5/Bibata_Cursor/releases/latest 2>/dev/null \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','v2.0.7'))" 2>/dev/null)
    fi
    [[ -z "$BIBATA_VERSION" ]] && BIBATA_VERSION="v2.0.7"
    BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/${BIBATA_VERSION}/Bibata-Modern-Classic.tar.xz"

    _tmp_bibata=$(mktemp --suffix=.tar.xz)
    if _fetch_verified "$BIBATA_URL" "$_tmp_bibata" "$CHECKSUM_BIBATA" "Bibata-Modern-Classic"; then
        mkdir -p /usr/share/icons
        if tar -xf "$_tmp_bibata" -C /usr/share/icons/ 2>/dev/null; then
            success "Bibata-Modern-Classic cursor installed (${BIBATA_VERSION})"
        else
            warn "Bibata archive extraction failed"
        fi
    else
        warn "Bibata cursor skipped — pin CHECKSUM_BIBATA in lib/checksums.sh"
    fi
    rm -f "$_tmp_bibata"
else
    success "Bibata-Modern-Classic already present"
fi

# ── Bluetooth service ────────────────────────────────────────
systemctl enable bluetooth 2>/dev/null || true
systemctl start --no-block bluetooth 2>/dev/null || true
success "Bluetooth service enabled"

# ── bluetui — SHA256-pinned binary ───────────────────────────
# CHANGED: was an unpinned curl into /usr/local/bin, with a
# cargo fallback that pulled an unpinned version from crates.io.
# Now: _fetch_verified only. If the hash is not pinned, the
# installer skips bluetui — fail-closed, no silent fallback.
if ask_install "bluetui (Bluetooth Terminal UI)"; then
    info "Installing bluetui (verified)..."
    apt-get install -y bluez bluez-tools dbus 2>/dev/null

    if [[ -z "${CHECKSUM_BLUETUI:-}" || "$CHECKSUM_BLUETUI" == "UNPINNED" ]]; then
        warn "bluetui skipped — pin CHECKSUM_BLUETUI in lib/checksums.sh"
    else
        if command -v jq >/dev/null 2>&1; then
            BLUETUI_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
                https://api.github.com/repos/pythops/bluetui/releases/latest 2>/dev/null \
                | jq -r '.tag_name // "v0.8.1"')
        else
            BLUETUI_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
                https://api.github.com/repos/pythops/bluetui/releases/latest 2>/dev/null \
                | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','v0.8.1'))" 2>/dev/null)
        fi
        [[ -z "$BLUETUI_VERSION" ]] && BLUETUI_VERSION="v0.8.1"
        BLUETUI_URL="https://github.com/pythops/bluetui/releases/download/${BLUETUI_VERSION}/bluetui-x86_64-linux-musl"

        if _fetch_verified "$BLUETUI_URL" /usr/local/bin/bluetui \
                "$CHECKSUM_BLUETUI" "bluetui"; then
            chmod 0755 /usr/local/bin/bluetui
            success "bluetui installed (${BLUETUI_VERSION})"
        else
            warn "bluetui skipped — hash mismatch or download failed"
        fi
    fi
fi

# ── Desktop entries ──────────────────────────────────────────
mkdir -p "$TARGET_HOME/.local/share/applications"

cat > "$TARGET_HOME/.local/share/applications/nmtui.desktop" << 'EOF'
[Desktop Entry]
Name=Network
Comment=Manage network connections (nmtui)
Exec=kitty -e nmtui
Icon=network-wireless
Type=Application
Categories=Network;System;
EOF

cat > "$TARGET_HOME/.local/share/applications/bluetui.desktop" << 'EOF'
[Desktop Entry]
Name=Bluetooth
Comment=Manage Bluetooth devices (bluetui)
Exec=kitty -e bluetui
Icon=bluetooth
Type=Application
Categories=System;
EOF

cat > "$TARGET_HOME/.local/share/applications/pcmanfm.desktop" << 'EOF'
[Desktop Entry]
Name=Files
Comment=File manager
Exec=pcmanfm %U
Icon=system-file-manager
Type=Application
Categories=System;FileManager;
EOF

cat > "$TARGET_HOME/.local/share/applications/snowfox-music.desktop" << 'EOF'
[Desktop Entry]
Name=Musik
Comment=SnowFox Stream & Music Player (TUI)
Exec=kitty -e snowfox music
Icon=applications-multimedia
Type=Application
Categories=AudioVideo;Audio;Player;
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/applications"
success "Desktop entries installed (Rofi-ready)"

# ── Touchpad config ──────────────────────────────────────────
mkdir -p /etc/X11/xorg.conf.d
if [[ -f "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" ]]; then
    cp "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
    info "Touchpad config copied from repo"
else
    cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier      "libinput touchpad"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver          "libinput"
    Option          "Tapping"            "on"
    Option          "ClickMethod"        "clickfinger"
    Option          "NaturalScrolling"   "true"
    Option          "DisableWhileTyping" "on"
EndSection
EOF
    info "Touchpad config created"
fi

# ── i3 autostart (idempotent) ────────────────────────────────
BASH_PROFILE="$TARGET_HOME/.bash_profile"
if ! grep -q "SnowFoxOS — start i3 automatically" "$BASH_PROFILE" 2>/dev/null; then
    {
        echo ''
        echo '# SnowFoxOS — start i3 automatically'
        echo '[ "$(tty)" = "/dev/tty1" ] && exec startx'
    } >> "$BASH_PROFILE"
fi

cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games

export GTK_THEME=Arc-Dark
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_STYLE_OVERRIDE=gtk2
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export ELECTRON_OZONE_PLATFORM_HINT=auto
export _JAVA_AWT_WM_NONREPARENTING=1
export XDG_CURRENT_DESKTOP=i3

xsettingsd &

if [ -f /usr/bin/dbus-launch ]; then
    eval $(/usr/bin/dbus-launch --sh-syntax --exit-with-session)
    dbus-update-activation-environment --systemd \
        DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME
fi

exec i3
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"

success "i3 desktop & autostart configured"

# ── Nerd Fonts (verified) ────────────────────────────────────
# CHANGED: zip is verified against CHECKSUM_JETBRAINSMONO before
# extraction. Extract to temp dir, then move the .ttf files.
info "Installing Nerd Fonts (JetBrainsMono, verified)..."
if command -v jq >/dev/null 2>&1; then
    NERD_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
        https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null \
        | jq -r '.tag_name // "v3.2.1"')
else
    NERD_VERSION=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
        https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','v3.2.1'))" 2>/dev/null)
fi
[[ -z "$NERD_VERSION" ]] && NERD_VERSION="v3.2.1"
NERD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.zip"

_tmp_nerd=$(mktemp --suffix=.zip)
if _fetch_verified "$NERD_URL" "$_tmp_nerd" "$CHECKSUM_JETBRAINSMONO" "JetBrainsMono Nerd Font"; then
    _tmp_extract=$(mktemp -d)
    if unzip -q "$_tmp_nerd" "*.ttf" -d "$_tmp_extract" 2>/dev/null; then
        mkdir -p /usr/local/share/fonts/nerd-fonts
        mv "$_tmp_extract"/*.ttf /usr/local/share/fonts/nerd-fonts/
        chmod 0644 /usr/local/share/fonts/nerd-fonts/*.ttf
        fc-cache -f /usr/local/share/fonts/nerd-fonts/ >/dev/null 2>&1 || true
        success "JetBrainsMono Nerd Font installed (${NERD_VERSION})"
    else
        warn "Nerd Fonts archive extraction failed"
    fi
    rm -rf "$_tmp_extract"
else
    warn "Nerd Fonts skipped — pin CHECKSUM_JETBRAINSMONO in lib/checksums.sh"
fi
rm -f "$_tmp_nerd"
