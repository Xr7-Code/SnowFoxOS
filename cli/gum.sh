#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Gum TUI Library
#  Shared theme + widgets for all SnowFox TUI frontends.
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
#
#  Rule: widgets print their result on stdout, all decoration
#  is drawn on stderr, so $( ) captures stay clean.
# ============================================================

# ── SnowFox theme for Gum (matches Polybar / Kitty palette) ──
: "${GUM_PURPLE:=#9d6fe8}"
: "${GUM_PURPLE_LT:=#b899ff}"
: "${GUM_RED:=#e87a7a}"
: "${GUM_DIM:=#6e6a8a}"
: "${GUM_FG:=#e0d9f5}"

# ============================================================
#  TUI detection
# ============================================================
# The dispatcher calls sf_tui_detect once at startup. Modules
# sourced directly fall back to a live check.
# Override: SNOWFOX_TUI=0 (never) / SNOWFOX_TUI=1 (force).
sf_tui_detect() {
    case "${SNOWFOX_TUI:-auto}" in
        0|off|false|never)
            _SF_TUI=0
            ;;
        1|on|true|always)
            if command -v gum &>/dev/null; then _SF_TUI=1; else _SF_TUI=0; fi
            ;;
        *)
            if command -v gum &>/dev/null && [[ -t 0 && -t 1 ]]; then
                _SF_TUI=1
            else
                _SF_TUI=0
            fi
            ;;
    esac
}

sf_can_tui() {
    if [[ -n "${_SF_TUI:-}" ]]; then
        [[ "$_SF_TUI" == "1" ]]
    else
        command -v gum &>/dev/null && [[ -t 0 && -t 1 ]]
    fi
}

sf_have_gum() { command -v gum &>/dev/null; }

# ============================================================
#  Missing dependency: gum
# ============================================================
sf_gum_missing() {
    # sf_gum_missing [context] — context defaults to "the snowfox TUI"
    local context="${1:-the snowfox TUI}"
    local arch
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l)        arch="armv7" ;;
        armv6l)        arch="armv6" ;;
        i386|i686)     arch="i386" ;;
        *)             arch="x86_64" ;;
    esac

    local bin_cmd='    V=$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest | python3 -c "import sys,json;print(json.load(sys.stdin)[\"tag_name\"].lstrip(\"v\"))")
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${V}/gum_${V}_Linux_ARCH.tar.gz" | sudo tar -xz -C /usr/local/bin --strip-components=1 --wildcards "gum_*/gum"'
    bin_cmd="${bin_cmd//ARCH/$arch}"

    echo ""
    err "\"gum\" is not installed — it is required for $context."
    echo ""
    echo -e "  ${BOLD}Install gum once, then try again:${RESET}"
    divider
    echo ""
    echo -e "  ${LPURPLE}${BOLD}Option 1 — Charm APT repository ${DGRAY}(recommended on SnowFoxOS / Debian)${RESET}"
    echo -e "${DGRAY}"
    cat <<'EOF'
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install gum
EOF
    echo -e "${RESET}"
    echo -e "  ${LPURPLE}${BOLD}Option 2 — Prebuilt binary ${DGRAY}(no repository needed)${RESET}"
    echo -e "${DGRAY}"
    printf '%s\n' "$bin_cmd"
    echo -e "${RESET}"
    echo -e "  ${LPURPLE}${BOLD}Option 3 — Go ${DGRAY}(>= 1.21)${RESET}"
    echo -e "  ${DGRAY}    go install charm.land/gum/v2@latest${RESET}"
    echo ""
    divider
    info "More information: https://github.com/charmbracelet/gum#installation"
    info "Fresh SnowFoxOS installs include gum automatically (install.sh)."
    echo ""
}

# ============================================================
#  Decoration (stderr only)
# ============================================================
sf_banner() {
    # sf_banner [subtitle]
    local title="🦊  SnowFoxOS"
    [[ -n "${1:-}" ]] && title="$title  ·  $1"
    clear >&2
    gum style \
        --border rounded \
        --border-foreground "$GUM_PURPLE" \
        --foreground "$GUM_PURPLE_LT" \
        --bold \
        --padding "0 3" \
        --margin "1 0" \
        "$title" 1>&2
}

sf_note() {
    # Dim information line on stderr
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 2" "$1" 1>&2
    echo "" >&2
}

sf_keyhint() {
    # Subtle control hint on stderr
    gum style --foreground "$GUM_DIM" --padding "0 4" "$1" 1>&2
}

# ============================================================
#  Widgets (result on stdout)
# ============================================================
sf_choose() {
    # sf_choose <header> <height> <item...>
    local header="$1" height="$2"
    shift 2
    gum choose \
        --header "$header" \
        --height "$height" \
        --cursor "❯ " \
        --cursor.foreground "$GUM_PURPLE_LT" \
        --header.foreground "$GUM_PURPLE" \
        --selected.foreground "$GUM_PURPLE_LT" \
        "$@"
}

sf_input() {
    # sf_input <header> [placeholder] [value]
    local header="$1" placeholder="${2:-}" value="${3:-}"
    local args=(
        --header "$header"
        --placeholder "$placeholder"
        --prompt "❯ "
        --width 64
        --prompt.foreground "$GUM_PURPLE_LT"
        --cursor.foreground "$GUM_PURPLE_LT"
        --header.foreground "$GUM_PURPLE"
        --placeholder.foreground "$GUM_DIM"
    )
    [[ -n "$value" ]] && args+=(--value "$value")
    gum input "${args[@]}"
}

sf_secret() {
    # sf_secret <header> [placeholder]
    gum input --password \
        --header "$1" \
        --placeholder "${2:-Password}" \
        --prompt "❯ " \
        --width 48 \
        --prompt.foreground "$GUM_PURPLE_LT" \
        --cursor.foreground "$GUM_PURPLE_LT" \
        --header.foreground "$GUM_PURPLE" \
        --placeholder.foreground "$GUM_DIM"
}

sf_filter() {
    # sf_filter <header> [placeholder] [height]   (list on stdin)
    gum filter \
        --header "$1" \
        --placeholder "${2:-Type to filter}" \
        --height "${3:-12}" \
        --indicator "❯ " \
        --indicator.foreground "$GUM_PURPLE_LT" \
        --header.foreground "$GUM_PURPLE" \
        --selected-indicator.foreground "$GUM_PURPLE_LT" \
        --unselected-prefix.foreground "$GUM_DIM"
}

sf_confirm() {
    # sf_confirm <question> [affirm] [neg] [default: yes|no]
    local q="$1" aff="${2:-Yes}" neg="${3:-No}" def="${4:-yes}"
    local extra=(--default=true)
    [[ "$def" == "no" ]] && extra=(--default=false)
    gum confirm "$q" \
        --affirmative "$aff" \
        --negative "$neg" \
        --prompt.foreground "$GUM_PURPLE_LT" \
        --selected.background "$GUM_PURPLE" \
        "${extra[@]}"
}

sf_spin() {
    # sf_spin <title> <command...>
    local title="$1"
    shift
    gum spin \
        --spinner dot \
        --title "$title" \
        --spinner.foreground "$GUM_PURPLE_LT" \
        --title.foreground "$GUM_FG" \
        -- "$@"
}

sf_spin_do() {
    # sf_spin_do <title> <function> <out-file> [args...]
    # Runs a *shell function* under a gum spinner; output goes
    # to <out-file> so the TUI stays clean.
    local title="$1" fn="$2" out="$3"
    shift 3
    ( "$fn" "$@" > "$out" 2>&1 ) &
    local pid=$!
    gum spin \
        --spinner dot \
        --title "$title" \
        --spinner.foreground "$GUM_PURPLE_LT" \
        --title.foreground "$GUM_FG" \
        -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.15; done"
    wait "$pid" 2>/dev/null
    return $?
}

sf_pager() {
    # sf_pager [-n] — reads stdin, -n = line numbers
    local args=(--match.foreground "$GUM_PURPLE_LT")
    if [[ "${1:-}" == "-n" ]]; then
        args+=(--show-line-numbers --line-number.foreground "$GUM_DIM")
        shift
    fi
    gum pager "${args[@]}"
}

sf_strip_ansi() {
    # Remove ANSI escape sequences (for the pager)
    sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

sf_page() {
    # sf_page <title> <file> — banner + pager view of a text file
    local title="$1" file="$2"
    sf_banner "$title"
    sf_strip_ansi < "$file" | sf_pager
}

sf_pause() {
    # sf_pause [message] — wait for Enter
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 2" "${1:-Press Enter to continue…}" 1>&2
    read -r _ >&2 || true
}

# ============================================================
#  TUI-aware prompts (fall back to plain read without gum)
# ============================================================
sf_yesno() {
    # sf_yesno <question> [affirm] [neg] [default: yes|no]
    local q="$1" aff="${2:-Yes}" neg="${3:-No}" def="${4:-no}"
    if sf_can_tui; then
        sf_confirm "$q" "$aff" "$neg" "$def"
        return $?
    fi
    local ans hint="[y/N]"
    [[ "$def" == "yes" ]] && hint="[Y/n]"
    read -rp "$(echo -e "${PURPLE}${BOLD}${q} ${hint}: ${RESET}")" ans
    if [[ "$def" == "yes" ]]; then
        [[ ! "$ans" =~ ^[nN]$ ]]
    else
        [[ "$ans" =~ ^[yY]$ ]]
    fi
}

sf_ask() {
    # sf_ask <question> [default] — prints the answer
    local q="$1" def="${2:-}"
    if sf_can_tui; then
        sf_input "$q" "" "$def"
    else
        local ans
        read -rp "$(echo -e "${PURPLE}${BOLD}${q}${def:+ [${def}]}: ${RESET}")" ans
        echo "${ans:-$def}"
    fi
}

sf_ask_ph() {
    # sf_ask_ph <question> [placeholder] [default]
    # Like sf_ask, but the second argument is a *placeholder* hint
    # (shown inside the empty TUI input instead of pre-filled).
    local q="$1" ph="${2:-}" def="${3:-}"
    if sf_can_tui; then
        sf_input "$q" "$ph" "$def"
    else
        local ans hint=""
        [[ -n "$ph" ]] && hint=" ${DGRAY}(${ph})${RESET}"
        read -rp "$(echo -e "${PURPLE}${BOLD}${q}${hint}${def:+ [${def}]}: ${RESET}")" ans
        echo "${ans:-$def}"
    fi
}

sf_ask_secret() {
    # sf_ask_secret <question> — prints the answer
    local q="$1"
    if sf_can_tui; then
        sf_secret "$q" "Password"
    else
        local ans
        read -rsp "$(echo -e "${PURPLE}${BOLD}${q}: ${RESET}")" ans
        echo ""
        echo "$ans"
    fi
}
