#!/bin/bash
# ============================================================
#  SnowFoxOS v3.0 — Audio and Terminal Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# Load utilities (assumes SCRIPT_DIR is set before sourcing)
source "$SCRIPT_DIR/lib/utils.sh"

# Global variables from main script (assumed to be sourced/exported):
# TARGET_USER, TARGET_HOME

step "4/10 — Audio (PipeWire)"

wait_apt
apt-get install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    pipewire-audio \
    wireplumber \
    pavucontrol \
    pulseaudio-utils \
    libspa-0.2-bluetooth \
    bluez-obexd

apt-get remove --purge -y pulseaudio pulseaudio-bluetooth 2>/dev/null || true

# PipeWire Bluetooth profile: prevents "br-connection-profile-unavailable"
# BlueZ explicitly needs the policy for all profiles including A2DP and HFP/HSP.
mkdir -p /etc/pipewire/wireplumber.conf.d
cat > /etc/pipewire/wireplumber.conf.d/51-bluez-config.conf << 'BTWEOF'
monitor.bluez.properties = {
  bluez5.enable-sbc-xq    = true
  bluez5.enable-msbc      = true
  bluez5.enable-hw-volume = true
  bluez5.headset-roles    = [ hsp_hs hsp_ag hfp_hf hfp_ag ]
  bluez5.a2dp.codecs      = [ sbc sbc_xq aac ldac aptx aptx_hd ]
}
BTWEOF

# BlueZ main configuration: prevents hanging on A2DP connections
# AutoEnable=true starts BT automatically after boot without manual "power on"
mkdir -p /etc/bluetooth
cat > /etc/bluetooth/main.conf << 'BZEOF'
[Policy]
AutoEnable=true

[General]
Enable=Source,Sink,Media,Socket
ControllerMode=dual
FastConnectable=true
ReconnectAttempts=7
ReconnectIntervals=1,2,4,8,16,32,64
BZEOF

# systemctl --user in a sudo context is unreliable (no DBUS_SESSION_BUS_ADDRESS).
# Instead, enable loginctl-linger so user services start at boot.
loginctl enable-linger "$TARGET_USER" 2>/dev/null || true

# Create symlinks for PipeWire autostart in user systemd
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/systemd/user/default.target.wants"
for svc in pipewire.service pipewire-pulse.service wireplumber.service; do
    src="/usr/lib/systemd/user/$svc"
    dst="$TARGET_HOME/.config/systemd/user/default.target.wants/$svc"
    [[ -f "$src" ]] && sudo -u "$TARGET_USER" ln -sf "$src" "$dst" 2>/dev/null || true
done

success "PipeWire + Bluetooth audio installed (A2DP, HFP, HSP)"

# ── Kitty Terminal Configuration ─────────────────────────────
info "Configuring Kitty terminal..."
mkdir -p "$TARGET_HOME/.config/kitty"
# NOTE: Step 10 (theming_finishing.sh) installs the canonical
# configs/kitty/kitty.conf, which is rendered from the master
# palette (~/.config/snowfox/palette.conf). This heredoc is only
# the fallback for partial installs and uses the same colors.
cat > "$TARGET_HOME/.config/kitty/kitty.conf" << 'KITTYEOF'
# SnowFox Kitty Theme
background #11111b
foreground #e0d9f5
window_padding_width 8

# Cursor
cursor            #9d6fe8
cursor_text_color #ffffff

# Selection
selection_background #8139e8
selection_foreground #ffffff

# Colors (SnowFox palette tokens)
color0  #1e1e2e
color1  #e87a7a
color2  #89c98a
color3  #e8c97a
color4  #9d6fe8
color5  #b899ff
color6  #7acfe8
color7  #e0d9f5
color8  #6e6a8a
color9  #e87a7a
color10 #89c98a
color11 #e8c97a
color12 #9d6fe8
color13 #b899ff
color14 #89dceb
color15 #f7f7fb

# Font
font_family      JetBrainsMono Nerd Font
font_size        11.0
KITTYEOF
success "Kitty configured"
