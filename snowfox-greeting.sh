#!/bin/bash
# ============================================================
#  SnowFoxOS — Terminal Greeting
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - State file in $XDG_RUNTIME_DIR (0700, user-owned), not /tmp
#   - Atomic state creation via noclobber (no TOCTOU, no symlink)
#   - $USER removed from path, sanitized for output
#   - Absolute binary paths (no PATH hijacking)
#   - touch failure aborts cleanly instead of repeating greeting
#   - df via --output=avail (column-stable)
#   - Non-TTY exit without creating a state file
# ============================================================

# ─── Controlled environment ─────────────────────────────────
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

# ─── Binary paths ───────────────────────────────────────────
readonly DATE_BIN="/usr/bin/date"
readonly UPTIME_BIN="/usr/bin/uptime"
readonly AWK_BIN="/usr/bin/awk"
readonly SED_BIN="/usr/bin/sed"
readonly DF_BIN="/usr/bin/df"
readonly TTY_BIN="/usr/bin/tty"
readonly BASENAME_BIN="/usr/bin/basename"
readonly ID_BIN="/usr/bin/id"
readonly TR_BIN="/usr/bin/tr"
readonly SLEEP_BIN="/usr/bin/sleep"
readonly PRINTF_BIN="/usr/bin/printf"

[[ -x "$DATE_BIN" ]]   || DATE_BIN="/bin/date"
[[ -x "$UPTIME_BIN" ]] || UPTIME_BIN="/bin/uptime"
[[ -x "$DF_BIN" ]]     || DF_BIN="/bin/df"
[[ -x "$TTY_BIN" ]]    || TTY_BIN="/bin/tty"
[[ -x "$SLEEP_BIN" ]]  || SLEEP_BIN="/bin/sleep"

# ─── Colors ────────────────────────────────────────────────
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Non-TTY: nothing to greet ─────────────────────────────
# Reading tty state must not create a state file: a non-interactive
# shell (cron, scp, git hooks) should exit silently.
TTY_NAME=$("$TTY_BIN" 2>/dev/null) || exit 0
[[ -z "$TTY_NAME" || "$TTY_NAME" == "not a tty" ]] && exit 0

# ─── State file: XDG_RUNTIME_DIR, atomic, per-tty ──────────
RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
if [[ -z "$RUNTIME_DIR" || ! -d "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" ]]; then
    # Fallback: /run/user/<uid> (systemd-logind) or skip
    RUNTIME_DIR="/run/user/$("$ID_BIN" -u 2>/dev/null)"
    if [[ ! -d "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" ]]; then
        exit 0
    fi
fi

SESSION_ID=$("$BASENAME_BIN" "$TTY_NAME" 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

STATE_FILE="${RUNTIME_DIR}/snowfox-greeted-${SESSION_ID}"

# Atomic: noclobber fails if the file already exists, even under a race.
if ! ( set -o noclobber; : > "$STATE_FILE" ) 2>/dev/null; then
    exit 0
fi
# State file must never be world-readable.
"$PRINTF_BIN" '' >/dev/null 2>&1 || true
chmod 600 "$STATE_FILE" 2>/dev/null || true

# ─── Time & date ───────────────────────────────────────────
HOUR=$("$DATE_BIN" +%H)
DATE=$("$DATE_BIN" '+%A, %d. %B %Y')

if   [[ $HOUR -ge 5  && $HOUR -lt 12 ]]; then GREETING="Guten Morgen"
elif [[ $HOUR -ge 12 && $HOUR -lt 18 ]]; then GREETING="Guten Tag"
elif [[ $HOUR -ge 18 && $HOUR -lt 22 ]]; then GREETING="Guten Abend"
else GREETING="Gute Nacht"
fi

# ─── System info ───────────────────────────────────────────
UPTIME=$("$UPTIME_BIN" -p 2>/dev/null | "$SED_BIN" 's/^up //')
[[ -z "$UPTIME" ]] && UPTIME="unknown"

RAM_TOTAL=$("$AWK_BIN" '/^MemTotal:/     {print int($2/1024)}' /proc/meminfo 2>/dev/null)
RAM_AVAIL=$("$AWK_BIN" '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
[[ -z "$RAM_TOTAL" ]] && RAM_TOTAL="?"
[[ -z "$RAM_AVAIL" ]] && RAM_AVAIL="?"

DISK_FREE=$("$DF_BIN" -h --output=avail / 2>/dev/null | "$AWK_BIN" 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/,""); print}')
[[ -z "$DISK_FREE" ]] && DISK_FREE="?"

# ─── User (sanitized for output) ───────────────────────────
SAFE_USER=$(printf '%s' "${USER:-}" | "$TR_BIN" -cd '[:alnum:]_.-')
[[ -z "$SAFE_USER" ]] && SAFE_USER="user"

# ─── Quotes ────────────────────────────────────────────────
QUOTES=(
    "\"Your computer belongs to you. Not to Microsoft.\""
    "\"Windows is checking for updates... SnowFox is already done.\""
    "\"No telemetry. No ads. No subscriptions. Just your machine.\""
    "\"While others collect your data, SnowFox deletes it.\""
    "\"Freedom is not a feature. It is the foundation.\""
    "\"You are not a product. You are a person.\""
    "\"Somewhere, a Windows user is waiting for a reboot.\""
    "\"The best surveillance tool is the one you willingly install.\""
    "\"Small is fast. Fast is free. Free is SnowFox.\""
    "\"You deserve a computer that works for you — not against you.\""
)
QUOTE="${QUOTES[$RANDOM % ${#QUOTES[@]}]}"

# ─── Render ────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -ne "${PURPLE}${BOLD}  🦊 ( - . - )  SnowFoxOS${RESET}\r"
"$SLEEP_BIN" 0.5
echo -ne "${PURPLE}${BOLD}  🦊 ( o . o )  SnowFoxOS${RESET}\r"
"$SLEEP_BIN" 0.5
echo -e  "${PURPLE}${BOLD}  🦊 ( ^ . ^ )  SnowFoxOS${RESET}  ${GRAY}— ${DATE}${RESET}"
echo -e  "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

echo -e "  ${CYAN}${GREETING}, ${SAFE_USER}.${RESET}"
echo ""
echo -e "  ${GRAY}Uptime:   ${BOLD}${UPTIME}${RESET}"
echo -e "  ${GRAY}RAM:      ${BOLD}${RAM_AVAIL}MB available of ${RAM_TOTAL}MB${RESET}"
echo -e "  ${GRAY}Disk:     ${BOLD}${DISK_FREE} free${RESET}"
echo ""
echo -e "  ${ORANGE}${QUOTE}${RESET}"
echo ""
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${GRAY}You are not a product. You are not data. You are a person.${RESET}"
echo -e "  ${GRAY}                       — Alexander Valentin Ludwig${RESET}"
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
