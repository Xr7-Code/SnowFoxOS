# ============================================================
#  SnowFoxOS — Bash completion for the snowfox CLI
#  Source this file or put it in /etc/bash_completion.d/
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# ── Palette helpers (theme names & tokens from the master file) ──
_snowfox_palette() {
    local p="${SNOWFOX_PALETTE:-$HOME/.config/snowfox/palette.conf}"
    [[ -f "$p" ]] && printf '%s\n' "$p"
}

_snowfox_themes() {
    local p
    p="$(_snowfox_palette)"
    if [[ -n "$p" ]]; then
        sed -n 's/^\[theme:\([^]]*\)\].*$/\1/p' "$p" | tr '\n' ' '
    else
        printf 'snowfox blackwhite whiteblack'
    fi
}

_snowfox_tokens() {
    local p
    p="$(_snowfox_palette)"
    [[ -n "$p" ]] || return 0
    awk -F= '
        /^\[colors:/ { s=1; next }
        /^\[/       { s=0 }
        s && /=/ {
            k = $1
            gsub(/[[:space:]]/, "", k)
            if (k != "" && k !~ /^#/) print k
        }' "$p" | sort -u | tr '\n' ' '
}

_snowfox_complete() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local CMDS="status battery update profile doctor reset
                gpu kill air audit tor
                stream download fetch music immersion
                auto layout stash web network wallpaper display lock
                settings bluetooth keyboard language timezone user defaults
                theme
                node ai snap mesh
                help version"

    case "$prev" in
        snowfox|sf)
            COMPREPLY=( $(compgen -W "$CMDS" -- "$cur") )
            return ;;
        stream)         COMPREPLY=( $(compgen -W "-a --audio" -- "$cur") ); return ;;
        music|m)
            COMPREPLY=(); return ;;
        immersion|imm)
            COMPREPLY=( $(compgen -W "on off toggle status profiles profile stage tune beats test mpv show reset doctor about help head inhead 3d body mind total brain alpha theta delta beta gamma space room spin trim carrier beatvol crossfeed bass vb raw channels" -- "$cur") )
            return ;;
        dl|download|fetch)
            COMPREPLY=(); return ;;
        profile|prof)
            COMPREPLY=( $(compgen -W "balanced performance battery privacy status" -- "$cur") )
            return ;;
        kill)
            COMPREPLY=( $(compgen -W "mic cam all restore status" -- "$cur") )
            return ;;
        air|airmode)
            COMPREPLY=( $(compgen -W "on off status" -- "$cur") )
            return ;;
        tor)
            COMPREPLY=( $(compgen -W "on off status" -- "$cur") )
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
            COMPREPLY=( $(compgen -W "gui" -- "$cur") )
            return ;;
        bluetooth|bt)
            COMPREPLY=( $(compgen -W "on off toggle status" -- "$cur") )
            return ;;
        theme|th)
            COMPREPLY=( $(compgen -W "list current apply show color gui check reset help --dry-run --no-reload $(_snowfox_themes)" -- "$cur") )
            return ;;
        apply|use)
            COMPREPLY=( $(compgen -W "$(_snowfox_themes) --dry-run --no-reload" -- "$cur") )
            return ;;
        show)
            COMPREPLY=( $(compgen -W "$(_snowfox_themes)" -- "$cur") )
            return ;;
        color|colour)
            COMPREPLY=( $(compgen -W "$(_snowfox_tokens)" -- "$cur") )
            return ;;
        node)
            COMPREPLY=( $(compgen -W "desktop server console status d s c" -- "$cur") )
            return ;;
        ai)
            COMPREPLY=( $(compgen -W "models list pull history clear" -- "$cur") )
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
