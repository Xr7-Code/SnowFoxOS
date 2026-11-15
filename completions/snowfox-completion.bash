#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — bash completion
#  Matches the v4 dispatcher (mesh/ai/music/immersion/node/tor removed)
# ============================================================

_snowfox_commands() {
    printf '%s\n' \
        help status update profile doctor reset \
        gpu kill air audit \
        stream download fetch \
        auto layout web \
        stash theme wallpaper \
        set bt kb lang tz user def \
        snap
}

_snowfox_aliases() {
    printf '%s\n' h st up prof doc rst wall lay dl
}

_snowfox_complete() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(_snowfox_commands) $(_snowfox_aliases)" -- "$cur")
        return 0
    fi

    case "$prev" in
        theme)
            mapfile -t COMPREPLY < <(compgen -W "list show gui color check reset $(ls "$HOME/.config/snowfox/themes" 2>/dev/null | sed 's/\.theme$//')" -- "$cur")
            ;;
        wallpaper)
            mapfile -t COMPREPLY < <(compgen -W "list set auto gui" -- "$cur")
            ;;
        profile)
            mapfile -t COMPREPLY < <(compgen -W "balanced performance battery privacy" -- "$cur")
            ;;
        kill)
            mapfile -t COMPREPLY < <(compgen -W "mic cam all restore status" -- "$cur")
            ;;
        air)
            mapfile -t COMPREPLY < <(compgen -W "on off status" -- "$cur")
            ;;
        audit)
            mapfile -t COMPREPLY < <(compgen -W "live once snapshot" -- "$cur")
            ;;
        bt)
            mapfile -t COMPREPLY < <(compgen -W "on off toggle" -- "$cur")
            ;;
        layout)
            mapfile -t COMPREPLY < <(compgen -W "tiling floating" -- "$cur")
            ;;
        stash)
            mapfile -t COMPREPLY < <(compgen -W "browser media office dev privacy games list find info install remove" -- "$cur")
            ;;
        snap)
            mapfile -t COMPREPLY < <(compgen -W "list save restore diff delete" -- "$cur")
            ;;
        status)
            mapfile -t COMPREPLY < <(compgen -W "battery" -- "$cur")
            ;;
        download)
            COMPREPLY=()
            ;;
        *) ;;
    esac
    return 0
}

complete -F _snowfox_complete snowfox