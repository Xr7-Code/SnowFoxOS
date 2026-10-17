#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Settings Manager
#  Terminal + Rofi interface for system settings
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snowfox"
CONFIG_FILE="$CONFIG_DIR/snowfox.conf"

# ── Config file helpers ──────────────────────────────────────
_init_settings() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$CONFIG_DIR"
        cat <<'EOF' > "$CONFIG_FILE"
# ============================================================
#  SnowFoxOS — Default applications & preferences
# ============================================================

DEFAULT_BROWSER=zen-browser
DEFAULT_TERMINAL=kitty
DEFAULT_EDITOR=geany
DEFAULT_FILEMANAGER=pcmanfm
EOF
        chmod 644 "$CONFIG_FILE"
    fi
}

get_setting() {
    _init_settings
    local key="$1"
    local default_val="$2"
    local val
    key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
    val=$(grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2-)
    echo "${val:-$default_val}"
}

set_setting() {
    _init_settings
    local key="$1"
    local val="$2"
    key=$(echo "$key" | tr '[:lower:]' '[:upper:]')

    if grep -q -E "^${key}=" "$CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CONFIG_FILE"
    else
        echo "${key}=${val}" >> "$CONFIG_FILE"
    fi
}

# ============================================================
# snowfox set — Terminal overview
# ============================================================
cmd_settings() {
    local subcmd="${1:-}"

    case "$subcmd" in
        gui)      cmd_settings_gui ;;
        overview) cmd_settings_overview ;;
        "")
            if sf_can_tui; then
                _settings_tui
            else
                cmd_settings_overview
            fi
            ;;
        *)
            err "Unknown settings subcommand: $subcmd"
            info "  Usage: snowfox set [overview|gui]"
            return 1
            ;;
    esac
}

cmd_settings_overview() {
    header "Settings"

    # ── Default applications ─────────────────────────────────
    section "Default Applications"
    row "Browser"      "$(get_setting DEFAULT_BROWSER zen-browser)"
    row "Terminal"     "$(get_setting DEFAULT_TERMINAL kitty)"
    row "Editor"       "$(get_setting DEFAULT_EDITOR geany)"
    row "File manager" "$(get_setting DEFAULT_FILEMANAGER pcmanfm)"
    hint "Change: snowfox def set <browser|terminal|editor|fm> <command>"

    # ── Keyboard & language ──────────────────────────────────
    section "Keyboard & Language"
    local kb
    kb=$(localectl status 2>/dev/null | grep "X11 Layout" | awk '{print $3}')
    row "Keyboard" "${kb:-de}"
    hint "Change: snowfox kb <layout>  (e.g. de, us)"

    local lang
    lang=$(localectl status 2>/dev/null | grep "System Locale" | cut -d'=' -f2)
    row "Language" "${lang:-en_US.UTF-8}"
    hint "Change: snowfox lang <locale>  (e.g. en_US.UTF-8)"

    # ── Timezone ─────────────────────────────────────────────
    section "Time & Location"
    local tz
    tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
    row "Timezone" "$tz"
    row "System time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    hint "Change: snowfox tz <zone>  (e.g. Europe/Berlin)"

    # ── Bluetooth ────────────────────────────────────────────
    section "Bluetooth"
    local bt_state="off"
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && bt_state="on"
    bool_row "Bluetooth" "$([[ "$bt_state" == "on" ]] && echo true || echo false)" "on" "off"

    local boot_state="off"
    if grep -iE '^\s*AutoEnable\s*=\s*true' /etc/bluetooth/main.conf &>/dev/null; then
        boot_state="on"
    fi
    bool_row "Autostart on boot" "$([[ "$boot_state" == "on" ]] && echo true || echo false)" "on" "off"
    hint "Change: snowfox bt <on|off|toggle|boot-on|boot-off>"

    # ── User ─────────────────────────────────────────────────
    section "User"
    row "Current user" "$USER"
    row "Home"         "$HOME"
    hint "Change: snowfox user <passwd|add|del> [username]"

    divider
    info "Graphical settings menu: snowfox set gui"
    echo ""
}

# ============================================================
# snowfox set gui — Rofi menu
# ============================================================
cmd_settings_gui() {
    if ! command -v rofi &>/dev/null; then
        err "Rofi not installed — graphical settings unavailable"
        info "  Use the terminal interface: snowfox set"
        return 1
    fi

    if [[ -z "$DISPLAY" ]]; then
        err "No graphical session (DISPLAY not set)"
        info "  Use the terminal interface: snowfox set"
        return 1
    fi

    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    [[ ! -f "$ROFI_THEME" ]] && ROFI_THEME=""

    while true; do
        local CHOICE
        CHOICE=$(echo -e \
            "  Default Applications\n  Keyboard Layout\n  System Language\n  Timezone\n  Bluetooth\n  User Management\n  ─────────────────────────────\n  Back" \
            | rofi -dmenu -p "🦊 Settings" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 420 -lines 10)

        [[ -z "$CHOICE" ]] && return 0

        case "$CHOICE" in
            *"Default Applications"*) _gui_defaults ;;
            *"Keyboard Layout"*)      _gui_keyboard ;;
            *"System Language"*)      _gui_language ;;
            *"Timezone"*)             _gui_timezone ;;
            *"Bluetooth"*)            _gui_bluetooth ;;
            *"User Management"*)      _gui_user ;;
            *"Back"*)                 return 0 ;;
        esac
    done
}

_gui_defaults() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local CHOICE
    CHOICE=$(echo -e "  Browser\n  Terminal\n  Editor\n  File Manager\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 Defaults" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 7)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    local KEY
    case "$CHOICE" in
        *"Browser"*)      KEY="browser" ;;
        *"Terminal"*)     KEY="terminal" ;;
        *"Editor"*)       KEY="editor" ;;
        *"File Manager"*) KEY="fm" ;;
    esac

    local NEW
    NEW=$(rofi -dmenu -p "🦊 New command for $KEY" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 0)

    [[ -z "$NEW" ]] && return

    set_setting "DEFAULT_$(echo "$KEY" | tr '[:lower:]' '[:upper:]')" "$NEW"
    notify-send "🦊 SnowFox" "Default $KEY set to: $NEW" 2>/dev/null || true
}

_gui_keyboard() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local CHOICE
    CHOICE=$(echo -e "  de   — German\n  us   — English (US)\n  gb   — English (UK)\n  fr   — French\n  es   — Spanish\n  it   — Italian\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 Keyboard Layout" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 9)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    local LAYOUT
    LAYOUT=$(echo "$CHOICE" | awk '{print $1}')
    [[ -z "$LAYOUT" ]] && return

    sudo localectl set-x11-keymap "$LAYOUT" 2>/dev/null
    setxkbmap "$LAYOUT" 2>/dev/null || true
    notify-send "🦊 SnowFox" "Keyboard layout: $LAYOUT" 2>/dev/null || true
}

_gui_language() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local CHOICE
    CHOICE=$(echo -e "  en_US.UTF-8   — English (US)\n  en_GB.UTF-8   — English (UK)\n  de_DE.UTF-8   — German\n  de_AT.UTF-8   — German (Austria)\n  fr_FR.UTF-8   — French\n  es_ES.UTF-8   — Spanish\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 System Language" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 420 -lines 10)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    local LOCALE
    LOCALE=$(echo "$CHOICE" | awk '{print $1}')
    [[ -z "$LOCALE" ]] && return

    sudo localectl set-locale LANG="$LOCALE" 2>/dev/null
    notify-send "🦊 SnowFox" "Language: $LOCALE (relogin required)" 2>/dev/null || true
}

_gui_timezone() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local CHOICE
    CHOICE=$(echo -e "  Europe/Berlin\n  Europe/Vienna\n  Europe/Zurich\n  Europe/London\n  Europe/Paris\n  America/New_York\n  America/Los_Angeles\n  Asia/Tokyo\n  Australia/Sydney\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 Timezone" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 420 -lines 13)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    local TZ
    TZ=$(echo "$CHOICE" | awk '{print $1}')
    [[ -z "$TZ" ]] && return

    sudo timedatectl set-timezone "$TZ" 2>/dev/null
    notify-send "🦊 SnowFox" "Timezone: $TZ" 2>/dev/null || true
}

_gui_bluetooth() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local bt_state="off"
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && bt_state="on"

    local CHOICE
    CHOICE=$(echo -e "  Turn on\n  Turn off\n  Toggle\n  Enable autostart on boot\n  Disable autostart on boot\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 Bluetooth (currently: $bt_state)" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 420 -lines 9)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    case "$CHOICE" in
        *"Turn on"*)                    _bt_on ;;
        *"Turn off"*)                   _bt_off ;;
        *"Toggle"*)                     _bt_toggle ;;
        *"Enable autostart"*)           _bt_boot_on ;;
        *"Disable autostart"*)          _bt_boot_off ;;
    esac
}

_gui_user() {
    local ROFI_THEME="$HOME/.config/rofi/config.rasi"
    local CHOICE
    CHOICE=$(echo -e "  Change password\n  Add user\n  Delete user\n  ─────────────────────────────\n  Back" \
        | rofi -dmenu -p "🦊 User Management" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 6)

    [[ -z "$CHOICE" || "$CHOICE" == *"Back"* ]] && return

    case "$CHOICE" in
        *"Change password"*)
            exec kitty -e sudo passwd
            ;;
        *"Add user"*)
            local NEWUSER
            NEWUSER=$(rofi -dmenu -p "🦊 New username" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 0)
            [[ -z "$NEWUSER" ]] && return
            exec kitty -e sudo adduser "$NEWUSER"
            ;;
        *"Delete user"*)
            local DELUSER
            DELUSER=$(rofi -dmenu -p "🦊 Username to delete" ${ROFI_THEME:+-theme "$ROFI_THEME"} -width 400 -lines 0)
            [[ -z "$DELUSER" ]] && return
            exec kitty -e sudo deluser --remove-home "$DELUSER"
            ;;
    esac
}

# ============================================================
#  Gum TUI — Settings manager
# ============================================================
_settings_tui() {
    while true; do
        sf_banner "Settings"
        sf_note "System preferences · defaults stored in $CONFIG_FILE"

        local choice st
        choice=$(sf_choose "What would you like to configure?" 11 \
            "🌐  Default Applications" \
            "⌨️   Keyboard Layout" \
            "🌍  System Language" \
            "🕒  Timezone" \
            "🔵  Bluetooth" \
            "👤  User Management" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *"Default Applications"*) _defaults_tui ;;
            *Keyboard*)               _keyboard_tui ;;
            *Language*)               _language_tui ;;
            *Timezone*)               _timezone_tui ;;
            *Bluetooth*)              _bt_tui ;;
            *User*)                   _user_tui ;;
        esac
    done
}

# ── Default applications ─────────────────────────────────────
_defaults_tui() {
    local browser terminal editor fm
    browser=$(get_setting DEFAULT_BROWSER zen-browser)
    terminal=$(get_setting DEFAULT_TERMINAL kitty)
    editor=$(get_setting DEFAULT_EDITOR geany)
    fm=$(get_setting DEFAULT_FILEMANAGER pcmanfm)

    sf_banner "Default Applications"

    local choice st
    choice=$(sf_choose "Pick an application class to change" 9 \
        "🌐  Browser       — $browser" \
        "💻  Terminal      — $terminal" \
        "📝  Editor        — $editor" \
        "📁  File manager  — $fm" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local key label current
    case "$choice" in
        *Browser*)        key="DEFAULT_BROWSER";     label="browser";      current="$browser"  ;;
        *Terminal*)       key="DEFAULT_TERMINAL";    label="terminal";     current="$terminal" ;;
        *Editor*)         key="DEFAULT_EDITOR";      label="editor";       current="$editor"   ;;
        *"File manager"*) key="DEFAULT_FILEMANAGER"; label="file manager"; current="$fm"       ;;
        *) return 0 ;;
    esac

    local new
    new=$(sf_ask "New command for the $label" "$current")
    [[ -z "$new" ]] && return 0

    if ! command -v "${new%% *}" &>/dev/null; then
        sf_confirm "'${new%% *}' is not installed — save anyway?" "Save" "Cancel" no || return 0
    fi

    set_setting "$key" "$new"
    ok "Default $label set to '$new'."
    sleep 1.2
}

# ── Keyboard layout ──────────────────────────────────────────
_keyboard_tui() {
    local current
    current=$(localectl status 2>/dev/null | grep "X11 Layout" | awk '{print $3}')
    current="${current:-de}"

    sf_banner "Keyboard Layout"
    sf_note "Current layout: $current"

    local choice st
    choice=$(sf_choose "Select a keyboard layout" 11 \
        "de   — German" \
        "us   — English (US)" \
        "gb   — English (UK)" \
        "fr   — French" \
        "es   — Spanish" \
        "it   — Italian" \
        "✏️   Custom layout code…" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local layout
    if [[ "$choice" == *Custom* ]]; then
        layout=$(sf_ask "Layout code (e.g. de, us, dvorak)" "$current")
    else
        layout=$(echo "$choice" | awk '{print $1}')
    fi
    [[ -z "$layout" ]] && return 0

    if sudo localectl set-x11-keymap "$layout" 2>/dev/null; then
        ok "Keyboard layout set to '$layout'."
        setxkbmap "$layout" 2>/dev/null || true
    else
        err "Could not set keyboard layout '$layout'."
    fi
    sleep 1.5
}

# ── System language ──────────────────────────────────────────
_language_tui() {
    local current
    current=$(localectl status 2>/dev/null | grep "System Locale" | cut -d'=' -f2)
    current="${current:-en_US.UTF-8}"

    sf_banner "System Language"
    sf_note "Current locale: $current"

    local choice st
    choice=$(sf_choose "Select a system language" 11 \
        "en_US.UTF-8  — English (US)" \
        "en_GB.UTF-8  — English (UK)" \
        "de_DE.UTF-8  — German" \
        "de_AT.UTF-8  — German (Austria)" \
        "fr_FR.UTF-8  — French" \
        "es_ES.UTF-8  — Spanish" \
        "✏️   Custom locale…" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local locale
    if [[ "$choice" == *Custom* ]]; then
        locale=$(sf_ask "Locale (e.g. en_US.UTF-8)" "$current")
    else
        locale=$(echo "$choice" | awk '{print $1}')
    fi
    [[ -z "$locale" ]] && return 0

    if sudo localectl set-locale LANG="$locale" 2>/dev/null; then
        ok "System language set to '$locale' (relogin required)."
    else
        err "Could not set locale '$locale'."
    fi
    sleep 1.5
}

# ── Timezone ─────────────────────────────────────────────────
_timezone_tui() {
    local current
    current=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")

    sf_banner "Timezone"
    sf_note "Current timezone: $current · $(date '+%H:%M:%S %Z')"

    local choice st
    choice=$(sf_choose "Select a timezone" 13 \
        "Europe/Berlin" \
        "Europe/Vienna" \
        "Europe/Zurich" \
        "Europe/London" \
        "Europe/Paris" \
        "America/New_York" \
        "America/Los_Angeles" \
        "Asia/Tokyo" \
        "Australia/Sydney" \
        "🔍  Search all timezones…" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local tz
    if [[ "$choice" == *Search* ]]; then
        tz=$(timedatectl list-timezones 2>/dev/null | sf_filter "Timezone" "Type to search · Enter to select" 15)
    else
        tz="$choice"
    fi
    [[ -z "$tz" ]] && return 0

    if sudo timedatectl set-timezone "$tz" 2>/dev/null; then
        ok "Timezone set to '$tz'."
    else
        err "Invalid timezone: $tz"
    fi
    sleep 1.5
}

# ── Bluetooth ────────────────────────────────────────────────
_bt_tui() {
    while true; do
        local state="off"
        bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && state="on"

        local boot_state="off"
        grep -iE '^\s*AutoEnable\s*=\s*true' /etc/bluetooth/main.conf &>/dev/null && boot_state="on"

        sf_banner "Bluetooth"
        sf_note "Adapter: $state · Autostart on boot: $boot_state"

        local choice st
        choice=$(sf_choose "Bluetooth" 10 \
            "🔛  Turn on" \
            "⏹️   Turn off" \
            "🔁  Toggle" \
            "🚀  Enable autostart on boot" \
            "🛑  Disable autostart on boot" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *"Turn on"*)           _bt_on ;;
            *"Turn off"*)          _bt_off ;;
            *Toggle*)              _bt_toggle ;;
            *"Enable autostart"*)  _bt_boot_on ;;
            *"Disable autostart"*) _bt_boot_off ;;
        esac
        sleep 1.2
    done
}

# ── User management ──────────────────────────────────────────
_user_tui() {
    sf_banner "User Management"
    sf_note "Current user: $USER · Home: $HOME"

    local choice st
    choice=$(sf_choose "User management" 8 \
        "🔑  Change password" \
        "➕  Add user" \
        "➖  Delete user" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    local name
    case "$choice" in
        *"Change password"*)
            name=$(sf_ask "User to change the password for" "$USER")
            [[ -z "$name" ]] && return 0
            info "Changing password for: $name"
            if [[ "$name" == "$USER" ]]; then
                passwd
            else
                sudo passwd "$name"
            fi
            ;;
        *"Add user"*)
            name=$(sf_ask "New username")
            [[ -z "$name" ]] && return 0
            sf_confirm "Create user '$name'?" "Create" "Cancel" no || return 0
            sudo adduser "$name"
            ;;
        *"Delete user"*)
            name=$(sf_ask "Username to delete")
            [[ -z "$name" ]] && return 0
            sf_confirm "Delete user '$name' including home directory?" "Delete" "Cancel" no || return 0
            sudo deluser --remove-home "$name"
            ;;
    esac
    sf_pause
}

# ============================================================
# snowfox bt — Bluetooth
# ============================================================
_bt_on() {
    sudo systemctl enable --now bluetooth &>/dev/null
    rfkill unblock bluetooth &>/dev/null
    bluetoothctl power on &>/dev/null
    ok "Bluetooth enabled."
}

_bt_off() {
    bluetoothctl power off &>/dev/null
    rfkill block bluetooth &>/dev/null
    ok "Bluetooth disabled."
}

_bt_toggle() {
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        _bt_off
    else
        _bt_on
    fi
}

_bt_boot_on() {
    sudo sed -i -E 's/^#?\s*AutoEnable\s*=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    ok "Bluetooth will be ON after next boot."
}

_bt_boot_off() {
    sudo sed -i -E 's/^#?\s*AutoEnable\s*=.*/AutoEnable=false/' /etc/bluetooth/main.conf
    ok "Bluetooth will be OFF after next boot."
}

_bt_status() {
    header "Bluetooth"
    local state="off"
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && state="on"
    bool_row "Current" "$([[ "$state" == "on" ]] && echo true || echo false)" "on" "off"

    local boot_state="off"
    grep -iE '^\s*AutoEnable\s*=\s*true' /etc/bluetooth/main.conf &>/dev/null && boot_state="on"
    bool_row "On boot" "$([[ "$boot_state" == "on" ]] && echo true || echo false)" "on" "off"
    echo ""
    info "Commands: snowfox bt <on|off|toggle|boot-on|boot-off>"
    echo ""
}

cmd_bluetooth() {
    case "$1" in
        on)       _bt_on ;;
        off)      _bt_off ;;
        toggle)   _bt_toggle ;;
        boot-on)  _bt_boot_on ;;
        boot-off) _bt_boot_off ;;
        status)   _bt_status ;;
        "")
            if sf_can_tui; then _bt_tui; else _bt_status; fi
            ;;
        *)
            err "Usage: snowfox bt <on|off|toggle|boot-on|boot-off|status>"
            return 1
            ;;
    esac
}

# ============================================================
# snowfox kb — Keyboard layout
# ============================================================
cmd_keyboard() {
    if [[ -n "$1" ]]; then
        sudo localectl set-x11-keymap "$1" 2>/dev/null
        setxkbmap "$1" 2>/dev/null || true
        ok "Keyboard layout set to '$1'."
    elif sf_can_tui; then
        _keyboard_tui
    else
        header "Keyboard Layout"
        local current
        current=$(localectl status 2>/dev/null | grep "X11 Layout" | awk '{print $3}')
        row "Current" "${current:-de}"
        echo ""
        info "Change: snowfox kb <layout>  (e.g. de, us, gb, fr)"
        echo ""
    fi
}

# ============================================================
# snowfox lang — System language
# ============================================================
cmd_language() {
    if [[ -n "$1" ]]; then
        sudo localectl set-locale LANG="$1" 2>/dev/null
        ok "System language set to '$1' (relogin required)."
    elif sf_can_tui; then
        _language_tui
    else
        header "System Language"
        local current
        current=$(localectl status 2>/dev/null | grep "System Locale" | cut -d'=' -f2)
        row "Current" "${current:-en_US.UTF-8}"
        echo ""
        info "Change: snowfox lang <locale>  (e.g. en_US.UTF-8, de_DE.UTF-8)"
        echo ""
    fi
}

# ============================================================
# snowfox tz — Timezone
# ============================================================
cmd_timezone() {
    if [[ -n "$1" ]]; then
        if sudo timedatectl set-timezone "$1" 2>/dev/null; then
            ok "Timezone set to '$1'."
        else
            err "Invalid timezone: $1"
            info "  List available: timedatectl list-timezones"
            return 1
        fi
    elif sf_can_tui; then
        _timezone_tui
    else
        header "Timezone"
        local tz
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
        row "Current" "$tz"
        row "System time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
        info "Change: snowfox tz <zone>  (e.g. Europe/Berlin)"
        echo ""
    fi
}

# ============================================================
# snowfox user — User management
# ============================================================
cmd_user() {
    local action="$1"
    local username="$2"

    case "$action" in
        passwd)
            local target="${username:-$USER}"
            info "Changing password for: $target"
            if [[ "$target" == "$USER" ]]; then
                passwd
            else
                sudo passwd "$target"
            fi
            ;;
        add)
            if [[ -z "$username" ]]; then
                err "Usage: snowfox user add <username>"
                return 1
            fi
            sudo adduser "$username"
            ;;
        del)
            if [[ -z "$username" ]]; then
                err "Usage: snowfox user del <username>"
                return 1
            fi
            sudo deluser --remove-home "$username"
            ;;
        status)
            _user_status
            ;;
        "")
            if sf_can_tui; then
                _user_tui
            else
                _user_status
            fi
            ;;
        *)
            err "Usage: snowfox user <passwd|add|del|status>"
            return 1
            ;;
    esac
}

_user_status() {
    header "User Management"
    row "Current user" "$USER"
    row "Home"         "$HOME"
    echo ""
    info "Commands:"
    info "  snowfox user passwd [username]   — Change password"
    info "  snowfox user add <username>      — Create new user"
    info "  snowfox user del <username>      — Delete user"
    echo ""
}

# ============================================================
# snowfox def — Default applications
# ============================================================
cmd_defaults() {
    local action="$1"
    local key="$2"
    local value="$3"

    case "$action" in
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                err "Usage: snowfox def set <browser|terminal|editor|fm> <command>"
                return 1
            fi
            case "$key" in
                browser)         set_setting "DEFAULT_BROWSER" "$value" ;;
                terminal)        set_setting "DEFAULT_TERMINAL" "$value" ;;
                editor)          set_setting "DEFAULT_EDITOR" "$value" ;;
                fm|filemanager)  set_setting "DEFAULT_FILEMANAGER" "$value" ;;
                *)
                    err "Unknown category: $key (allowed: browser, terminal, editor, fm)"
                    return 1
                    ;;
            esac
            ok "Default $key set to '$value'."
            ;;
        status|"")
            if [[ -z "$action" ]] && sf_can_tui; then
                _defaults_tui
            else
                header "Default Applications"
                row "Browser"      "$(get_setting DEFAULT_BROWSER zen-browser)"
                row "Terminal"     "$(get_setting DEFAULT_TERMINAL kitty)"
                row "Editor"       "$(get_setting DEFAULT_EDITOR geany)"
                row "File manager" "$(get_setting DEFAULT_FILEMANAGER pcmanfm)"
                echo ""
                info "Change: snowfox def set <category> <command>"
                echo ""
            fi
            ;;
        *)
            err "Usage: snowfox def [set] <category> <command>"
            return 1
            ;;
    esac
}
