#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — Locale & Keyboard Setup
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#  Behaviour:
#   full (interactive): prompts user to pick language + keyboard
#                       layout; falls back to en_US.UTF-8 / us
#   iso-base / any --defaults: silently sets en_US.UTF-8 / us
#                       (d-i asked the user already; locale was
#                        already written to /etc/default/locale
#                        by the installer — we just ensure English
#                        is ALSO available and set as LANG default
#                        if the user did not choose one)
# ============================================================

source "$SCRIPT_DIR/lib/utils.sh"

step "Locale & keyboard setup"

# ── Supported locales (name → locale string) ───────────────
declare -A SNOWFOX_LOCALES=(
    ["English (US)"]="en_US.UTF-8"
    ["English (UK)"]="en_GB.UTF-8"
    ["German"]="de_DE.UTF-8"
    ["French"]="fr_FR.UTF-8"
    ["Spanish"]="es_ES.UTF-8"
    ["Italian"]="it_IT.UTF-8"
    ["Portuguese (Brazil)"]="pt_BR.UTF-8"
    ["Polish"]="pl_PL.UTF-8"
    ["Russian"]="ru_RU.UTF-8"
    ["Japanese"]="ja_JP.UTF-8"
    ["Chinese (Simplified)"]="zh_CN.UTF-8"
    ["Korean"]="ko_KR.UTF-8"
    ["Dutch"]="nl_NL.UTF-8"
    ["Swedish"]="sv_SE.UTF-8"
    ["Czech"]="cs_CZ.UTF-8"
    ["Hungarian"]="hu_HU.UTF-8"
    ["Turkish"]="tr_TR.UTF-8"
    ["Arabic"]="ar_SA.UTF-8"
)

# Common keyboard layouts: "display label" -> "xkb-layout[:variant]"
declare -A SNOWFOX_KEYBOARDS=(
    ["us — English (US)"]="us"
    ["gb — English (UK)"]="gb"
    ["de — German"]="de"
    ["at — German (Austria)"]="at"
    ["fr — French"]="fr"
    ["es — Spanish"]="es"
    ["it — Italian"]="it"
    ["br — Portuguese (Brazil)"]="br"
    ["pl — Polish"]="pl"
    ["ru — Russian"]="ru"
    ["jp — Japanese"]="jp"
    ["cn — Chinese (Simplified)"]="cn"
    ["kr — Korean"]="kr"
    ["nl — Dutch"]="nl"
    ["se — Swedish"]="se"
    ["cz — Czech"]="cz"
    ["hu — Hungarian"]="hu"
    ["tr — Turkish"]="tr"
)

# ── Defaults ───────────────────────────────────────────────
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_KEYBOARD="us"

# ── Helper: generate sorted list ──────────────────────────
_locale_names_sorted() {
    local -a names=()
    local k
    for k in "${!SNOWFOX_LOCALES[@]}"; do
        names+=("$k")
    done
    printf '%s\n' "${names[@]}" | sort
}

_keyboard_names_sorted() {
    local -a names=()
    local k
    for k in "${!SNOWFOX_KEYBOARDS[@]}"; do
        names+=("$k")
    done
    printf '%s\n' "${names[@]}" | sort
}

# ── Interactive picker ─────────────────────────────────────
_pick_locale_interactive() {
    echo ""
    echo -e "${PURPLE}${BOLD}Available languages:${RESET}"
    echo ""

    local -a sorted_names=()
    mapfile -t sorted_names < <(_locale_names_sorted)

    local i=1
    local k
    for k in "${sorted_names[@]}"; do
        printf "  %2d) %s  (%s)\n" "$i" "$k" "${SNOWFOX_LOCALES[$k]}"
        i=$((i+1))
    done

    echo ""
    printf '%b[SnowFox] Select language [1-%d, default=1 (English US)]: %b' \
        "${PURPLE}${BOLD}" "${#sorted_names[@]}" "${RESET}"

    local choice
    read -r choice

    if [[ -z "$choice" || ! "$choice" =~ ^[0-9]+$ ]] \
       || (( choice < 1 || choice > ${#sorted_names[@]} )); then
        info "[default] English (US) selected"
        SNOWFOX_LOCALE="$DEFAULT_LOCALE"
        return
    fi

    local name="${sorted_names[$((choice-1))]}"
    SNOWFOX_LOCALE="${SNOWFOX_LOCALES[$name]}"
    info "Language selected: $name → $SNOWFOX_LOCALE"
}

_pick_keyboard_interactive() {
    echo ""
    echo -e "${PURPLE}${BOLD}Available keyboard layouts:${RESET}"
    echo ""

    local -a sorted_names=()
    mapfile -t sorted_names < <(_keyboard_names_sorted)

    local i=1
    local k
    for k in "${sorted_names[@]}"; do
        printf "  %2d) %s\n" "$i" "$k"
        i=$((i+1))
    done

    echo ""
    printf '%b[SnowFox] Select keyboard layout [1-%d, default=1 (us)]: %b' \
        "${PURPLE}${BOLD}" "${#sorted_names[@]}" "${RESET}"

    local choice
    read -r choice

    if [[ -z "$choice" || ! "$choice" =~ ^[0-9]+$ ]] \
       || (( choice < 1 || choice > ${#sorted_names[@]} )); then
        info "[default] us keyboard layout selected"
        SNOWFOX_KEYBOARD="$DEFAULT_KEYBOARD"
        return
    fi

    local name="${sorted_names[$((choice-1))]}"
    SNOWFOX_KEYBOARD="${SNOWFOX_KEYBOARDS[$name]}"
    info "Keyboard layout selected: $name → $SNOWFOX_KEYBOARD"
}

# ── Main logic ─────────────────────────────────────────────
configure_locale() {
    local phase="${SNOWFOX_PHASE:-full}"
    local unattended="${SNOWFOX_DEFAULTS:-false}"

    # In ISO phase: d-i already set the locale; honour it, ensure
    # en_US.UTF-8 is always also generated, do not override.
    if [[ "$phase" != "full" || "$unattended" == "true" ]]; then
        SNOWFOX_LOCALE="$DEFAULT_LOCALE"
        SNOWFOX_KEYBOARD="$DEFAULT_KEYBOARD"

        # In iso-base: read what d-i wrote
        if [[ "$phase" == "iso-base" ]]; then
            local di_lang
            di_lang="$(sed -n 's/^LANG=//p' /etc/default/locale \
                       2>/dev/null | tr -d '"' | head -n1)"
            if [[ -n "$di_lang" && "$di_lang" != "C" && "$di_lang" != "POSIX" ]]; then
                SNOWFOX_LOCALE="$di_lang"
            fi
            local di_kb
            di_kb="$(sed -n 's/^XKBLAYOUT=//p' /etc/default/keyboard \
                     2>/dev/null | tr -d '"' | head -n1)"
            if [[ -n "$di_kb" ]]; then
                SNOWFOX_KEYBOARD="$di_kb"
            fi
        fi

        info "[auto] locale=$SNOWFOX_LOCALE  keyboard=$SNOWFOX_KEYBOARD"
    else
        # Full interactive install: ask the user
        _pick_locale_interactive
        _pick_keyboard_interactive
    fi

    export SNOWFOX_LOCALE
    export SNOWFOX_KEYBOARD

    # ── Apply locale ───────────────────────────────────────
    apt-get install -y locales > /dev/null 2>&1 || true

    # Ensure both chosen locale AND en_US.UTF-8 are generated
    local loc
    for loc in "$SNOWFOX_LOCALE" "en_US.UTF-8"; do
        [[ -z "$loc" || "$loc" == "C" || "$loc" == "POSIX" ]] && continue
        [[ "$loc" == *.* ]] || loc="${loc}.UTF-8"
        if ! grep -q "^${loc} " /etc/locale.gen 2>/dev/null; then
            sed -i "s/^# *${loc} /${loc} /" /etc/locale.gen 2>/dev/null || true
            grep -q "^${loc} " /etc/locale.gen 2>/dev/null \
                || echo "${loc} UTF-8" >> /etc/locale.gen
        fi
    done
    locale-gen
    update-locale LANG="$SNOWFOX_LOCALE" LC_MESSAGES="POSIX"
    success "Locale configured: $SNOWFOX_LOCALE"

    # ── Apply keyboard layout ──────────────────────────────
    if command -v localectl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        localectl set-keymap "$SNOWFOX_KEYBOARD" 2>/dev/null || true
        localectl set-x11-keymap "$SNOWFOX_KEYBOARD" 2>/dev/null || true
    else
        # Chroot-safe: write /etc/default/keyboard directly
        install -d -m 0755 /etc/default
        cat > /etc/default/keyboard <<EOF
# Managed by SnowFoxOS installer
XKBMODEL="pc105"
XKBLAYOUT="${SNOWFOX_KEYBOARD}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
        # Apply via setupcon if available (d-i installs it)
        if command -v setupcon >/dev/null 2>&1; then
            setupcon --force --save-only 2>/dev/null || true
        fi
    fi
    success "Keyboard layout configured: $SNOWFOX_KEYBOARD"
}

configure_locale
