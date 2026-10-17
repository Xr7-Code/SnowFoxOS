#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Network Manager (Gum TUI)
#  Wi-Fi list, connect, disconnect, forget, details.
#  snowfox net        → Gum TUI
#  snowfox net gui    → classic Rofi menu (~/.config/snowfox-network.sh)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# ── Active SSID ──────────────────────────────────────────────
_net_active_ssid() {
    nmcli -t -f active,ssid dev wifi 2>/dev/null \
        | grep "^yes" | cut -d: -f2- | sed 's/\\:/:/g' | head -1
}

# ── Connect to a network ─────────────────────────────────────
_net_connect() {
    local ssid="$1" sec="$2"
    local active
    active=$(_net_active_ssid)

    if [[ -n "$active" && "$active" == "$ssid" ]]; then
        ok "Already connected to '$ssid'."
        sleep 1
        return 0
    fi

    # Saved connection?
    if nmcli connection show "$ssid" &>/dev/null; then
        if nmcli connection up "$ssid" &>/dev/null; then
            ok "Connected to '$ssid'."
        else
            err "Connection failed."
        fi
        sleep 1
        return 0
    fi

    # Open network
    if [[ -z "$sec" || "$sec" == "OPEN" || "$sec" == "--" ]]; then
        if nmcli device wifi connect "$ssid" &>/dev/null; then
            ok "Connected to '$ssid'."
        else
            err "Connection failed."
        fi
        sleep 1
        return 0
    fi

    # Secured network → ask for the password
    local pass
    pass=$(sf_secret "Password for '$ssid'" "Wi-Fi password")
    [[ -z "$pass" ]] && return 0

    echo ""
    if nmcli device wifi connect "$ssid" password "$pass"; then
        ok "Connected to '$ssid'."
    else
        err "Connection failed — check the password."
    fi
    sleep 1.2
}

# ── Forget a saved network ───────────────────────────────────
_net_forget() {
    local saved
    saved=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep wireless | cut -d: -f1)

    if [[ -z "$saved" ]]; then
        err "No saved networks."
        sleep 1.2
        return 0
    fi

    local choice st
    choice=$(printf '%s\n' "$saved" | sf_filter "Forget a network" "Type to filter — Enter to select" 10)
    st=$?
    [[ $st -ne 0 || -z "$choice" ]] && return 0

    if sf_yesno "Delete saved network '$choice'?" "Forget" "Cancel" no; then
        if nmcli connection delete "$choice" &>/dev/null; then
            ok "Forgotten: $choice"
        else
            err "Failed to delete '$choice'."
        fi
        sleep 1
    fi
}

# ── Connection details ───────────────────────────────────────
_net_details() {
    local iface ip gw dns mac ssid
    iface=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | grep ":connected" | cut -d: -f1 | head -1)

    if [[ -z "$iface" ]]; then
        err "No active connection."
        sleep 1.2
        return 0
    fi

    ip=$(nmcli -g IP4.ADDRESS device show "$iface" | head -1)
    gw=$(nmcli -g IP4.GATEWAY device show "$iface" | head -1)
    dns=$(nmcli -g IP4.DNS device show "$iface" | head -1)
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
    ssid=$(_net_active_ssid)

    sf_banner "Network Details"
    row "Interface" "$iface"
    row "SSID"      "${ssid:-—}"
    row "IP"        "${ip:-—}"
    row "Gateway"   "${gw:-—}"
    row "DNS"       "${dns:-—}"
    row "MAC"       "${mac:-—}"
    echo ""
    sf_pause "Press Enter to go back…"
}

# ── Main TUI loop ────────────────────────────────────────────
_network_tui() {
    while true; do
        local wifi_state active
        wifi_state=$(nmcli radio wifi 2>/dev/null)
        active=$(_net_active_ssid)

        sf_banner "Network"
        sf_note "WiFi: ${wifi_state:-unknown}   ·   Connected: ${active:-nothing}"

        # Rescan in the background, then list networks
        nmcli device wifi rescan &>/dev/null &

        local -a entries=() labels=() secs=()
        local inuse ssid signal sec ssid_clean label
        while IFS=: read -r inuse ssid signal sec; do
            [[ -z "$ssid" || "$ssid" == "--" ]] && continue
            ssid_clean=$(echo "$ssid" | sed 's/\\:/:/g')
            if [[ "$inuse" == "*" ]]; then
                label="🔗 $ssid_clean"
            else
                label="📶 $ssid_clean"
            fi
            entries+=("$label  (${signal:-0}% · ${sec:-OPEN})")
            labels+=("$label  (${signal:-0}% · ${sec:-OPEN})")
            secs+=("${sec:-OPEN}|${ssid_clean}")
        done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | sort -t: -k3 -rn | head -20)

        entries+=("──────────────────────────────")
        if [[ "$wifi_state" == "enabled" ]]; then
            entries+=("📴  Disable WiFi")
        else
            entries+=("📶  Enable WiFi")
        fi
        entries+=("🔌  Disconnect")
        entries+=("🗑️   Forget a network")
        entries+=("📊  Connection details")
        entries+=("🔄  Rescan")
        entries+=("↩️   Back")

        local choice st idx=-1 i
        choice=$(sf_choose "WiFi networks" 16 "${entries[@]}")
        st=$?

        if [[ $st -ne 0 || -z "$choice" ]]; then
            return 0
        fi

        # Find which network (if any) was selected
        for i in "${!labels[@]}"; do
            if [[ "${labels[$i]}" == "$choice" ]]; then
                idx=$i
                break
            fi
        done

        if [[ $idx -ge 0 ]]; then
            local sec ssid_sel
            sec="${secs[$idx]%%|*}"
            ssid_sel="${secs[$idx]##*|}"
            _net_connect "$ssid_sel" "$sec"
            continue
        fi

        case "$choice" in
            *"Disable WiFi"*)  nmcli radio wifi off && sleep 0.8 ;;
            *"Enable WiFi"*)   nmcli radio wifi on  && sleep 0.8 ;;
            *Disconnect*)
                local conn
                conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -1)
                if [[ -n "$conn" ]]; then
                    nmcli connection down "$conn" &>/dev/null && sleep 0.8
                else
                    err "No active connection."
                    sleep 1
                fi
                ;;
            *"Forget a network"*)  _net_forget ;;
            *"Connection details"*) _net_details ;;
            *Rescan*)              continue ;;
            *"──────────────"*)    continue ;;
            *Back*)                return 0 ;;
        esac
    done
}

# ============================================================
# snowfox net — entry point
# ============================================================
cmd_network() {
    case "$1" in
        gui)
            exec "$HOME/.config/snowfox-network.sh"
            ;;
    esac

    if ! command -v nmcli &>/dev/null; then
        err "NetworkManager (nmcli) not found."
        info "  Install: sudo apt install network-manager"
        return 1
    fi

    if sf_can_tui; then
        _network_tui
        return 0
    fi

    # No gum/TTY → try the graphical Rofi menu
    if [[ -n "$DISPLAY" && -x "$HOME/.config/snowfox-network.sh" ]]; then
        exec "$HOME/.config/snowfox-network.sh"
    fi

    header "Network"
    local ip iface
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
    [[ -n "$ip" ]] && row "Network" "${ip}  (${iface})" "$GREEN" || row "Network" "not connected" "$RED"
    echo ""
    info "Interactive TUI: install gum and run 'snowfox net' in a terminal."
    info "Graphical menu:  run inside X11 (Rofi)."
    echo ""
}
