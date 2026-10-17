#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Hardware (GPU, Kill, Air)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# ============================================================
# snowfox gpu — GPU information (read-only)
# ============================================================
cmd_gpu() {
    if [[ -z "${1:-}" ]] && sf_can_tui; then
        local tmp
        tmp=$(mktemp)
        sf_spin_do "Reading GPU information…" _gpu_report "$tmp"
        sf_page "GPU Information" "$tmp"
        rm -f "$tmp"
        return 0
    fi

    header "GPU Information"
    _gpu_report
}

# ── Plain report (shared by CLI and TUI) ─────────────────────
_gpu_report() {
    # ── Detect GPUs via lspci ────────────────────────────────
    local -a GPUS
    mapfile -t GPUS < <(lspci 2>/dev/null | grep -iE "VGA|3D|Display")

    if [[ ${#GPUS[@]} -eq 0 ]]; then
        warn "No GPU detected via lspci"
        return 0
    fi

    section "Detected GPUs"
    for gpu in "${GPUS[@]}"; do
        local vendor=""
        echo "$gpu" | grep -qi nvidia && vendor="NVIDIA"
        echo "$gpu" | grep -qi amd    && vendor="AMD"
        echo "$gpu" | grep -qi intel  && vendor="Intel"

        local name
        name=$(echo "$gpu" | sed 's/^[0-9a-f:.]* [^:]*: //')

        if [[ -n "$vendor" ]]; then
            row "$vendor" "$name"
        else
            row "Unknown" "$name"
        fi
    done

    # ── Loaded kernel modules ────────────────────────────────
    section "Loaded Kernel Modules"

    local -A MODULES=(
        ["nvidia"]="NVIDIA proprietary"
        ["nouveau"]="NVIDIA open-source"
        ["amdgpu"]="AMD"
        ["radeon"]="AMD (legacy)"
        ["i915"]="Intel"
    )

    local loaded_any=false
    for mod in "${!MODULES[@]}"; do
        if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$mod"; then
            row "${MODULES[$mod]}" "$mod"
            loaded_any=true
        fi
    done

    if ! $loaded_any; then
        warn "No GPU kernel module loaded"
    fi

    # ── NVIDIA specifics ─────────────────────────────────────
    if lspci 2>/dev/null | grep -qi nvidia; then
        section "NVIDIA Details"

        if command -v nvidia-smi &>/dev/null; then
            local driver
            driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
            if [[ -n "$driver" ]]; then
                row "Driver" "$driver" "$GREEN"
            else
                row "Driver" "installed, no output" "$ORANGE"
            fi

            # GPU mode (which GPU is rendering)
            local gpu_count
            gpu_count=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
            row "GPUs" "$gpu_count"
        else
            row "Driver" "nvidia-smi not found" "$RED"
            info "  Install: sudo apt install nvidia-driver"
        fi
    fi

    # ── AMD specifics ────────────────────────────────────────
    if lspci 2>/dev/null | grep -qi amd; then
        section "AMD Details"

        if lsmod 2>/dev/null | grep -q "^amdgpu"; then
            row "Driver" "amdgpu" "$GREEN"
        elif lsmod 2>/dev/null | grep -q "^radeon"; then
            row "Driver" "radeon (legacy)" "$ORANGE"
        else
            row "Driver" "not loaded" "$RED"
        fi

        # PSR / Scatter-Gather config from installer
        if [[ -f /etc/modprobe.d/amdgpu.conf ]]; then
            if grep -q "dcfeaturemask=0x8" /etc/modprobe.d/amdgpu.conf 2>/dev/null; then
                row "PSR fix" "active" "$GREEN"
            else
                row "PSR fix" "not set" "$ORANGE"
            fi
        fi
    fi

    # ── Intel specifics ──────────────────────────────────────
    if lspci 2>/dev/null | grep -qi "Intel.*Graphics\|Intel.*VGA"; then
        section "Intel Details"

        if lsmod 2>/dev/null | grep -q "^i915"; then
            row "Driver" "i915" "$GREEN"
        else
            row "Driver" "not loaded" "$RED"
        fi
    fi

    # ── VA-API (hardware video decode) ───────────────────────
    section "Hardware Video Decode"

    if command -v vainfo &>/dev/null; then
        if vainfo &>/dev/null 2>&1; then
            row "VA-API" "available" "$GREEN"
        else
            row "VA-API" "not functional" "$ORANGE"
            info "  Packages: intel-media-va-driver / mesa-va-drivers / nvidia-vaapi-driver"
        fi
    else
        row "VA-API" "vainfo not installed" "$DGRAY"
        info "  Install: sudo apt install vainfo"
    fi

    divider
    info "GPU mode can only be changed via BIOS/UEFI or kernel boot parameters."
    info "SnowFoxOS does not switch GPU modes at runtime."
    echo ""
}

# ============================================================
# snowfox kill — Hardware kill switches
# ============================================================
cmd_kill() {
    local action="${1:-}"

    # ── Gum TUI: kill switch menu ────────────────────────────
    if [[ -z "$action" ]] && sf_can_tui; then
        _kill_tui
        return 0
    fi

    case "$action" in
        mic)
            local MIC_ID
            MIC_ID=$(pactl list sources short 2>/dev/null | grep -v monitor | awk '{print $1}' | head -1)
            if [[ -z "$MIC_ID" ]]; then
                err "No microphone found."
                return 1
            fi
            pactl set-source-mute "$MIC_ID" 1 2>/dev/null && \
                ok "Microphone disabled." || err "Failed to disable microphone."
            ;;
        cam)
            if ls /dev/video* &>/dev/null || lsmod 2>/dev/null | grep -q "^uvcvideo"; then
                sudo modprobe -r uvcvideo 2>/dev/null && \
                    ok "Camera disabled." || err "Failed to disable camera."
            else
                warn "No camera found."
            fi
            ;;
        all)
            local MIC_ID
            MIC_ID=$(pactl list sources short 2>/dev/null | grep -v monitor | awk '{print $1}' | head -1)
            [[ -n "$MIC_ID" ]] && pactl set-source-mute "$MIC_ID" 1 2>/dev/null && ok "Microphone disabled." || true
            sudo modprobe -r uvcvideo 2>/dev/null && ok "Camera disabled." || true
            sudo rfkill block all && ok "All wireless interfaces disabled."
            warn "Device is now in full silence mode."
            ;;
        restore)
            local MIC_ID
            MIC_ID=$(pactl list sources short 2>/dev/null | grep -v monitor | awk '{print $1}' | head -1)
            [[ -n "$MIC_ID" ]] && pactl set-source-mute "$MIC_ID" 0 2>/dev/null && ok "Microphone re-enabled." || true
            sudo modprobe uvcvideo 2>/dev/null && ok "Camera re-enabled." || true
            sudo rfkill unblock all && ok "Wireless re-enabled."
            ;;
        status)
            _kill_status
            ;;
        *)
            if [[ -z "$action" ]]; then
                _kill_status
                return 0
            fi
            err "Usage: snowfox kill [mic|cam|all|restore|status]"
            return 1
            ;;
    esac
}

# ── Status rows (shared by CLI and TUI) ──────────────────────
_kill_status_rows() {
    # Microphone
    local MIC_ID MIC_MUTE
    MIC_ID=$(pactl list sources short 2>/dev/null | grep -v monitor | awk '{print $1}' | head -1)
    if [[ -z "$MIC_ID" ]]; then
        row "Microphone" "none found" "$DGRAY"
    else
        MIC_MUTE=$(pactl get-source-mute "$MIC_ID" 2>/dev/null | awk '{print $2}')
        if [[ "$MIC_MUTE" == "yes" ]]; then
            row "Microphone" "muted — killed" "$RED"
        else
            row "Microphone" "active" "$GREEN"
        fi
    fi

    # Camera
    if lsmod 2>/dev/null | grep -q "^uvcvideo"; then
        row "Camera" "driver loaded — active" "$GREEN"
    elif modinfo uvcvideo &>/dev/null 2>&1; then
        row "Camera" "disabled — killed" "$RED"
    else
        row "Camera" "none found" "$DGRAY"
    fi

    # Wireless
    if rfkill list all 2>/dev/null | grep -q "blocked: yes"; then
        row "Wireless" "blocked — killed" "$RED"
    else
        row "Wireless" "active" "$GREEN"
    fi
}

_kill_status() {
    header "Kill Switches"
    _kill_status_rows
    echo ""
    info "Commands: snowfox kill <mic|cam|all|restore|status>"
    echo ""
}

_kill_tui() {
    while true; do
        sf_banner "Kill Switches"
        _kill_status_rows

        local choice st
        choice=$(sf_choose "Hardware kill switches" 8 \
            "🎤  Mute microphone" \
            "📷  Disable camera" \
            "🧨  Full silence mode (mic + cam + radios)" \
            "🔄  Restore all devices" \
            "📊  Refresh status" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *microphone*) cmd_kill mic ;;
            *camera*)     cmd_kill cam ;;
            *silence*)    cmd_kill all ;;
            *Restore*)    cmd_kill restore ;;
        esac
        sleep 1
    done
}

# ============================================================
# snowfox air — Airplane mode (all wireless off)
# ============================================================
cmd_air() {
    local action="${1:-}"

    # ── Gum TUI: air mode menu ───────────────────────────────
    if [[ -z "$action" ]] && sf_can_tui; then
        _air_tui
        return 0
    fi

    case "$action" in
        on)
            fox "Enabling air mode..."
            sudo rfkill block all
            ok "All wireless interfaces disabled (WiFi, Bluetooth, etc.)"
            warn "No network available. Use 'snowfox air off' to restore."
            ;;
        off)
            fox "Disabling air mode..."
            sudo rfkill unblock all
            ok "Wireless interfaces re-enabled."
            ;;
        status|"")
            header "Air Mode"
            if rfkill list all 2>/dev/null | grep -q "blocked: yes"; then
                row "Status" "ACTIVE — wireless off" "$RED"
            else
                row "Status" "off — wireless active" "$GREEN"
            fi
            echo ""
            info "Commands: snowfox air <on|off|status>"
            echo ""
            ;;
        *)
            err "Usage: snowfox air [on|off|status]"
            return 1
            ;;
    esac
}

_air_tui() {
    while true; do
        sf_banner "Air Mode"
        if rfkill list all 2>/dev/null | grep -q "blocked: yes"; then
            sf_note "Status: ACTIVE — all wireless interfaces are off"
        else
            sf_note "Status: off — wireless interfaces are active"
        fi

        local choice st
        choice=$(sf_choose "Air mode" 5 \
            "✈️   Enable — disable all wireless" \
            "📶  Disable — restore wireless" \
            "📊  Refresh status" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *Enable*)  cmd_air on ;;
            *Disable*) cmd_air off ;;
        esac
        sleep 1
    done
}
