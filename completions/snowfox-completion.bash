# ============================================================
#  SnowFoxOS — Bash completion for the snowfox CLI
#  Source this file or put it in /etc/bash_completion.d/
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

_snowfox_complete() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local CMDS="tui menu status battery update profile doctor reset
                gpu kill air audit tor
                stream download fetch music
                auto layout stash web network wallpaper display lock
                settings bluetooth keyboard language timezone user defaults
                node ai snap mesh
                help version"

    case "$prev" in
        snowfox|sf)
            COMPREPLY=( $(compgen -W "$CMDS" -- "$cur") )
            return ;;
        profile|prof)
            COMPREPLY=( $(compgen -W "balanced performance battery privacy status" -- "$cur") )
            return ;;
        update|up)
            COMPREPLY=( $(compgen -W "packages all" -- "$cur") )
            return ;;
        kill)
            COMPREPLY=( $(compgen -W "mic cam all restore status" -- "$cur") )
            return ;;
        air|airmode)
            COMPREPLY=( $(compgen -W "on off status" -- "$cur") )
            return ;;
        tor)
            COMPREPLY=( $(compgen -W "on off status restart" -- "$cur") )
            return ;;
        auto|autostart)
            COMPREPLY=( $(compgen -W "list enable disable" -- "$cur") )
            return ;;
        layout|lay)
            COMPREPLY=( $(compgen -W "tiling floating" -- "$cur") )
            return ;;
        stash)
            COMPREPLY=( $(compgen -W "find info install list remove upgrade internet office ide media gaming games ai security development system network multimedia" -- "$cur") )
            return ;;
        settings|set)
            COMPREPLY=( $(compgen -W "overview gui" -- "$cur") )
            return ;;
        bluetooth|bt)
            COMPREPLY=( $(compgen -W "on off toggle boot-on boot-off status" -- "$cur") )
            return ;;
        keyboard|kb)
            COMPREPLY=( $(compgen -W "de us gb fr es it dvorak" -- "$cur") )
            return ;;
        language|lang)
            COMPREPLY=( $(compgen -W "en_US.UTF-8 en_GB.UTF-8 de_DE.UTF-8 de_AT.UTF-8 fr_FR.UTF-8 es_ES.UTF-8" -- "$cur") )
            return ;;
        user)
            COMPREPLY=( $(compgen -W "passwd add del status" -- "$cur") )
            return ;;
        defaults|def)
            COMPREPLY=( $(compgen -W "set status browser terminal editor fm" -- "$cur") )
            return ;;
        network|net|wallpaper|wall|display|disp)
            COMPREPLY=( $(compgen -W "gui" -- "$cur") )
            return ;;
        node)
            COMPREPLY=( $(compgen -W "desktop server console status d s c" -- "$cur") )
            return ;;
        ai)
            COMPREPLY=( $(compgen -W "chat models list pull history clear" -- "$cur") )
            return ;;
        snap)
            COMPREPLY=( $(compgen -W "save list restore diff delete" -- "$cur") )
            return ;;
        restore|diff|delete)
            local snap_dir="$HOME/.config/snowfox/snapshots"
            if [[ -d "$snap_dir" ]]; then
                COMPREPLY=( $(compgen -W "$(ls -1 "$snap_dir" 2>/dev/null)" -- "$cur") )
            fi
            return ;;
        install)
            if command -v apt-cache &>/dev/null && [[ -n "$cur" && ${#cur} -ge 2 ]]; then
                COMPREPLY=( $(compgen -W "$(apt-cache pkgnames "$cur" 2>/dev/null | head -30)" -- "$cur") )
            fi
            return ;;
    esac

    COMPREPLY=( $(compgen -W "$CMDS" -- "$cur") )
}

complete -F _snowfox_complete snowfox
