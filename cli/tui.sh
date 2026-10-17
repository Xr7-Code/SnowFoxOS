#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Gum Control Center (main TUI)
#  Opened by plain "snowfox" (interactive terminal) or
#  "snowfox tui". Every entry point opens its own Gum TUI.
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

cmd_tui() {
    # cmd_tui [force] — force = invoked explicitly via "snowfox tui"
    local explicit="${1:-}"

    if ! sf_have_gum; then
        if [[ "$explicit" == "force" ]]; then
            sf_gum_missing "the snowfox control center"
            return 1
        fi
        cmd_help
        return 0
    fi

    if ! sf_can_tui; then
        if [[ "$explicit" == "force" ]]; then
            err "The TUI needs an interactive terminal (gum needs a TTY)."
            info "  Open a terminal and run: snowfox tui"
            return 1
        fi
        cmd_help
        return 0
    fi

    while true; do
        sf_banner "Control Center"
        sf_note "Everything — one fox, one menu · SNOWFOX_TUI=0 disables the TUI"

        local choice st
        choice=$(sf_choose "What would you like to do?" 20 \
            "📊  System Status" \
            "🔋  Battery" \
            "⬆️   System Update" \
            "⚡  Power Profiles" \
            "🩺  Doctor Diagnostics" \
            "🎮  GPU Information" \
            "🎤  Hardware Kill Switches" \
            "✈️   Air Mode" \
            "🔍  Network Audit" \
            "🧅  Tor Proxy" \
            "🎵  Music (TUI Player)" \
            "📺  Stream (mpv)" \
            "⬇️   Download (yt-dlp)" \
            "🔗  Fetch (aria2)" \
            "📶  Network Manager" \
            "🖼️   Wallpaper" \
            "🖥️   Display Setup" \
            "🚀  Autostart" \
            "🪟  Window Layout" \
            "🌐  WebApps" \
            "📦  Software Stash" \
            "⚙️   Settings" \
            "💾  Snapshots" \
            "🤖  SnowFox AI" \
            "❓  Help" \
            "🚪  Exit")
        st=$?

        if [[ $st -ne 0 || -z "$choice" ]]; then
            clear
            return 0
        fi

        case "$choice" in
            *"System Status"*)   cmd_status ;;
            *Battery*)           cmd_battery ;;
            *"System Update"*)   cmd_update ;;
            *Profiles*)          cmd_profile ;;
            *Doctor*)            cmd_doctor ;;
            *GPU*)               cmd_gpu ;;
            *Kill*)              cmd_kill ;;
            *"Air Mode"*)        cmd_air ;;
            *Audit*)             cmd_audit ;;
            *Tor*)               cmd_tor ;;
            *Music*)             cmd_music ;;
            *Stream*)            cmd_stream ;;
            *Download*)          cmd_download ;;
            *Fetch*)             cmd_fetch ;;
            *"Network Manager"*) cmd_network ;;
            *Wallpaper*)         cmd_wallpaper ;;
            *Display*)           cmd_display ;;
            *Autostart*)         cmd_start ;;
            *Layout*)            cmd_layout ;;
            *WebApps*)           cmd_webapp ;;
            *Stash*)             cmd_stash ;;
            *Settings*)          cmd_settings ;;
            *Snapshots*)         cmd_snap ;;
            *"SnowFox AI"*)      cmd_ai ;;
            *Help*)              cmd_help ;;
            *Exit*)              clear; return 0 ;;
        esac

        # Keep finished command output readable before redrawing.
        if [[ "$choice" != *Exit* && "$choice" != *Help* ]]; then
            sf_pause "Press Enter to return to the control center…"
        fi
    done
}
