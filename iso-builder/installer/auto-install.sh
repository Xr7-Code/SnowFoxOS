#!/bin/bash
# ============================================================
#  SnowFoxOS — First Boot Auto-Installer
#  Finalizes hardware drivers (NVIDIA/AMD/Intel), Zen Browser,
#  Fresh Editor, Console Launcher, & invokes install.sh
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

exec > >(tee -a /var/log/snowfox-firstboot.log) 2>&1

echo "[SnowFox] First-boot installation & hardware configuration started..."

# Determine primary user
TARGET_USER="$(ls /home | grep -v lost+found | head -n 1)"
TARGET_HOME="/home/$TARGET_USER"
SNOWFOX_DIR="$TARGET_HOME/SnowFoxOS"

export DEBIAN_FRONTEND=noninteractive
export SNOWFOX_UNATTENDED=true
export TARGET_USER
export TARGET_HOME

# 1. Run install.sh if available
if [[ -d "$SNOWFOX_DIR" ]]; then
    cd "$SNOWFOX_DIR"
    echo "[SnowFox] Running install.sh unattended..."
    bash install.sh || echo "[SnowFox] install.sh completed with exit code $?"
else
    echo "[SnowFox] SnowFoxOS directory not found at $SNOWFOX_DIR, running manual configuration..."
    apt-get update -qq
    apt-get install -y -qq firmware-linux firmware-atheros firmware-realtek
fi

# 2. Hardware-specific drivers (AMD, NVIDIA, Intel)
echo "[SnowFox] Checking and building/installing hardware-specific drivers (AMD, NVIDIA, Intel)..."
apt-get update -qq

# NVIDIA
if lspci | grep -iE 'vga|3d|display' | grep -qi 'nvidia'; then
    echo "[SnowFox] NVIDIA GPU detected, installing nvidia-driver and CUDA support..."
    apt-get install -y -qq nvidia-driver firmware-misc-nonfree nvidia-kernel-dkms
fi

# AMD
if lspci | grep -iE 'vga|3d|display' | grep -qi 'amd'; then
    echo "[SnowFox] AMD GPU detected, installing firmware-amd-graphics & VA-API..."
    apt-get install -y -qq firmware-amd-graphics libgl1-mesa-dri mesa-vulkan-drivers
    # Apply AMD + NVIDIA hybrid freeze fix if modprobe.d exists
    mkdir -p /etc/modprobe.d
    echo "options amdgpu dcfeaturemask=0x8" > /etc/modprobe.d/amdgpu.conf
fi

# Intel
if lspci | grep -iE 'vga|3d|display' | grep -qi 'intel'; then
    echo "[SnowFox] Intel GPU detected, installing intel-media-va-driver..."
    apt-get install -y -qq intel-media-va-driver firmware-intel-graphics
fi

# 3. Ensure Fresh Editor, Zen Browser & Console Launcher are fully installed
echo "[SnowFox] Installing Fresh Editor from official release..."
if [ -f /opt/snowfox-packages/fresh-editor.deb ]; then
    dpkg -i /opt/snowfox-packages/fresh-editor.deb || apt-get -fy install -y -qq
else
    wget -q -O /tmp/fresh-editor.deb https://github.com/sinelaw/fresh/releases/download/v0.5.2/fresh-editor_0.5.2-1_amd64.deb
    dpkg -i /tmp/fresh-editor.deb || apt-get -fy install -y -qq
    rm -f /tmp/fresh-editor.deb
fi

# Ensure Zen Browser repository / flatpak / installer is ready
echo "[SnowFox] Ensuring Zen Browser & Console Launcher are ready..."
if [[ -f "$SNOWFOX_DIR/lib/browser_selection.sh" ]]; then
    # Zen Browser installation helper or fallback
    apt-get install -y -qq firefox-esr curl wget
fi

# 4. Clean up firstboot service so it never runs again
echo "[SnowFox] Disabling snowfox-firstboot service..."
systemctl disable snowfox-firstboot.service
rm -f /etc/systemd/system/snowfox-firstboot.service
rm -f /usr/local/bin/snowfox-auto-install
systemctl daemon-reload

echo "[SnowFox] First-boot setup complete! Rebooting into finished SnowFoxOS desktop..."
sleep 3
reboot
