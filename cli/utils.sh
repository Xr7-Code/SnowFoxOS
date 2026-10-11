#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Utilities (Colors & Output Helpers)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

# ── Colors ───────────────────────────────────────────────────
PURPLE='\033[0;35m'
LPURPLE='\033[1;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
DGRAY='\033[2;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Output Helpers ───────────────────────────────────────────
header() {
    local title="$1"
    local width=48
    local pad=$(( (width - ${#title} - 2) / 2 ))
    local line
    line=$(printf '─%.0s' $(seq 1 $width))
    echo -e ""
    echo -e "${PURPLE}${BOLD}  ┌${line}┐${RESET}"
    echo -e "${PURPLE}${BOLD}  │$(printf '%*s' $((width)) '')│${RESET}"
    printf "${PURPLE}${BOLD}  │%*s${LPURPLE}🦊 %s${PURPLE}%*s│${RESET}\n" \
        $pad "" "$title" $pad ""
    echo -e "${PURPLE}${BOLD}  │$(printf '%*s' $((width)) '')│${RESET}"
    echo -e "${PURPLE}${BOLD}  └${line}┘${RESET}"
    echo ""
}

divider() {
    echo -e "${PURPLE}${DIM}  ────────────────────────────────────────────────${RESET}"
}

section() {
    echo ""
    echo -e "${LPURPLE}${BOLD}  $1${RESET}"
    divider
}

row() {
    # row "Label" "Value" [color]
    local label="$1"
    local value="$2"
    local color="${3:-$RESET}"
    printf "  ${DGRAY}%-16s${RESET} ${color}${BOLD}%s${RESET}\n" "$label" "$value"
}

bool_row() {
    # bool_row "Label" true|false [true_label] [false_label]
    local label="$1"
    local state="$2"
    local true_label="${3:-active}"
    local false_label="${4:-inactive}"
    if [[ "$state" == "true" ]]; then
        row "$label" "$true_label" "$GREEN"
    else
        row "$label" "$false_label" "$RED"
    fi
}

hint() {
    # Subtle hint below a row
    echo -e "  ${DGRAY}  $1${RESET}"
}

ok()   { echo -e "  ${GREEN}${BOLD}✓${RESET}  $1"; }
warn() { echo -e "  ${ORANGE}${BOLD}⚠${RESET}  $1"; }
err()  { echo -e "  ${RED}${BOLD}✗${RESET}  $1"; }
info() { echo -e "  ${DGRAY}$1${RESET}"; }
fox()  { echo -e "\n  ${LPURPLE}${BOLD}🦊  $1${RESET}\n"; }

# ── Progress bar ─────────────────────────────────────────────
# bar <value> <max>  — guards against div-by-zero and out-of-range
bar() {
    local val="${1:-0}"
    local max="${2:-100}"
    local width=20

    # Guard: max must be positive
    [[ "$max" -le 0 ]] && max=100
    # Clamp val to [0, max]
    [[ "$val" -lt 0 ]]      && val=0
    [[ "$val" -gt "$max" ]] && val=$max

    local filled=$(( val * width / max ))
    local empty=$(( width - filled ))
    local pct=$(( val * 100 / max ))
    local b="${PURPLE}${BOLD}"
    local d="${DGRAY}"
    printf "  ["
    [[ $filled -gt 0 ]] && printf "${b}%0.s█${RESET}" $(seq 1 $filled)
    [[ $empty  -gt 0 ]] && printf "${d}%0.s░${RESET}" $(seq 1 $empty)
    printf "] ${BOLD}%s%%${RESET}\n" "$pct"
}

# ── Spinner ──────────────────────────────────────────────────
# spin_start "message" — spin_ok/spin_err/spin_stop to finish
_SPIN_PID=""
_SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

spin_start() {
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            printf "\r  ${PURPLE}%s${RESET}  %s " "${_SPIN_FRAMES[$i]}" "$msg"
            i=$(( (i + 1) % ${#_SPIN_FRAMES[@]} ))
            sleep 0.08
        done
    ) &
    _SPIN_PID=$!
    disown "$_SPIN_PID" 2>/dev/null || true
}

_spin_kill() {
    if [[ -n "$_SPIN_PID" ]]; then
        kill "$_SPIN_PID" 2>/dev/null
        wait "$_SPIN_PID" 2>/dev/null || true
        printf "\r\033[K"
        _SPIN_PID=""
    fi
}

spin_stop()  { _spin_kill; }
spin_ok()    { _spin_kill; ok   "$1"; }
spin_err()   { _spin_kill; err  "$1"; }
spin_warn()  { _spin_kill; warn "$1"; }

# ── Human-readable bytes ─────────────────────────────────────
human_bytes() {
    local bytes="${1:-0}"
    if   [[ "$bytes" -ge 1073741824 ]]; then awk "BEGIN {printf \"%.1f GB\", $bytes/1073741824}"
    elif [[ "$bytes" -ge 1048576 ]];    then awk "BEGIN {printf \"%.1f MB\", $bytes/1048576}"
    elif [[ "$bytes" -ge 1024 ]];       then awk "BEGIN {printf \"%.0f KB\", $bytes/1024}"
    else echo "${bytes} B"
    fi
}
