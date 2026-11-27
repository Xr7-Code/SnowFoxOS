#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — CLI: ai
#  Launcher for the external snowfox-ai binary.
# ============================================================

if [[ -n "${_SNOWFOX_CLI_AI_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_SNOWFOX_CLI_AI_LOADED=1

cmd_ai() {
    case "${1:-}" in
        -h|--help)
            header "snowfox ai"
            info "Terminal AI chat with canvas and agentic commands"
            info ""
            info "usage: snowfox ai [args…]"
            info ""
            info "The external binary 'snowfox-ai' is invoked directly, so"
            info "any flags it accepts work here too."
            info ""
            info "Install:  sudo snowfox stash install snowfox-ai"
            info "Remove:   sudo snowfox stash remove snowfox-ai"
            return 0
            ;;
    esac

    if ! command -v snowfox-ai >/dev/null 2>&1; then
        err "snowfox-ai is not installed"
        info ""
        info "Install it with:"
        info "  sudo snowfox stash install snowfox-ai"
        return "$SNOWFOX_EXIT_ERROR"
    fi

    exec snowfox-ai "$@"
}
