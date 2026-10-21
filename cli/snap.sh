#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Config Snapshots
#  snowfox snap [save|list|restore|diff|delete]
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

SNAP_DIR="$HOME/.config/snowfox/snapshots"
SNOWFOX_CONFIG_DIR="$HOME/.config/snowfox"

# ── Directories included in a snapshot ──────────────────────
_SNAP_SOURCES=(
    "$HOME/.config/i3"
    "$HOME/.config/polybar"
    "$HOME/.config/rofi"
    "$HOME/.config/dunst"
    "$HOME/.config/kitty"
    "$HOME/.config/picom.conf"
    "$HOME/.config/snowfox"
    "$HOME/.config/gtk-3.0"
    "$HOME/.config/gtk-4.0"
)

cmd_snap() {
    case "$1" in
        save|s)     _snap_save "$2"    ;;
        list|ls|"") _snap_list         ;;
        restore|r)  _snap_restore "$2" ;;
        diff|d)     _snap_diff "$2"    ;;
        delete|rm)  _snap_delete "$2"  ;;
        *)
            header "snowfox snap"
            info "  snowfox snap              — list snapshots"
            info "  snowfox snap save [name]  — save current config"
            info "  snowfox snap restore <id> — restore a snapshot"
            info "  snowfox snap diff <id>    — compare snapshot to current"
            info "  snowfox snap delete <id>  — delete a snapshot"
            echo ""
            ;;
    esac
}

# ── Save ─────────────────────────────────────────────────────
_snap_save() {
    local label="${1:-$(date '+%Y%m%d_%H%M%S')}"
    # Sanitize label
    label=$(echo "$label" | tr -cs '[:alnum:]_-' '_' | head -c 48)

    local id
    id=$(date '+%Y%m%d_%H%M%S')
    local snap_path="$SNAP_DIR/${id}_${label}"
    mkdir -p "$snap_path"

    spin_start "Saving snapshot '$label'..."

    local count=0
    for src in "${_SNAP_SOURCES[@]}"; do
        [[ -e "$src" ]] || continue
        local dest="$snap_path$(dirname "$src")/"
        mkdir -p "$dest"

        # ~/.config/snowfox contains the snapshot directory itself — copying
        # it wholesale would recurse into the snapshot ("cp: cannot copy a
        # directory into itself") and silently drop the SnowFox config.
        # Copy entry by entry and skip "snapshots".
        if [[ "$src" == "$SNOWFOX_CONFIG_DIR" ]]; then
            mkdir -p "$dest/snowfox"
            local entry
            for entry in "$src"/*; do
                [[ -e "$entry" ]] || continue
                [[ "$(basename "$entry")" == "snapshots" ]] && continue
                cp -r "$entry" "$dest/snowfox/" 2>/dev/null || true
            done
            count=$((count + 1))
        else
            cp -r "$src" "$dest" 2>/dev/null && count=$((count + 1))
        fi
    done

    # Meta file
    {
        echo "label=$label"
        echo "id=$id"
        echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "files=$count"
        echo "kernel=$(uname -r)"
        echo "profile=$(cat "$HOME/.config/snowfox/profile" 2>/dev/null || echo 'balanced')"
    } > "$snap_path/meta.conf"

    spin_ok "Snapshot saved: ${BOLD}${id}_${label}${RESET}"
    info "  $count config source(s) archived → $snap_path"
    echo ""
}

# ── List ─────────────────────────────────────────────────────
_snap_list() {
    header "Config Snapshots"

    if [[ ! -d "$SNAP_DIR" ]] || [[ -z "$(ls -A "$SNAP_DIR" 2>/dev/null)" ]]; then
        info "No snapshots yet."
        hint "Create one: snowfox snap save [name]"
        echo ""
        return
    fi

    printf "  ${BOLD}%-22s %-20s %-10s %s${RESET}\n" "ID" "Label" "Profile" "Date (UTC)"
    divider

    local i=1
    for snap in "$SNAP_DIR"/*/; do
        [[ -f "$snap/meta.conf" ]] || continue
        local label id date profile
        label=$(grep '^label=' "$snap/meta.conf" | cut -d= -f2-)
        id=$(grep '^id=' "$snap/meta.conf" | cut -d= -f2-)
        date=$(grep '^date=' "$snap/meta.conf" | cut -d= -f2-)
        profile=$(grep '^profile=' "$snap/meta.conf" | cut -d= -f2-)

        printf "  ${CYAN}%-22s${RESET} %-20s ${DGRAY}%-10s %s${RESET}\n" \
            "${id}" "${label}" "${profile}" "${date}"
        i=$((i + 1))
    done

    echo ""
    hint "Restore: snowfox snap restore <id>  |  Compare: snowfox snap diff <id>"
    echo ""
}

# ── Restore ──────────────────────────────────────────────────
_snap_restore() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap restore <id>"
        info "  List snapshots: snowfox snap"
        exit 1
    fi

    # Find snapshot directory (allow partial id match)
    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]] || [[ ! -f "$snap_path/meta.conf" ]]; then
        err "Snapshot not found: $target"
        info "  List snapshots: snowfox snap"
        exit 1
    fi

    local label date
    label=$(grep '^label=' "$snap_path/meta.conf" | cut -d= -f2-)
    date=$(grep '^date=' "$snap_path/meta.conf" | cut -d= -f2-)

    header "Restore Snapshot"
    row "Snapshot" "$label" "$CYAN"
    row "Saved"    "$date"
    echo ""

    warn "This will overwrite your current configuration!"
    read -rp "$(echo -e "${ORANGE}${BOLD}Restore? [y/N]: ${RESET}")" CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && { info "Cancelled."; return; }

    # Auto-save current state first
    info "Saving current config as backup..."
    _snap_save "pre-restore" &>/dev/null

    spin_start "Restoring '$label'..."

    # Restore: strip snap_path prefix, copy to /
    (cd "$snap_path" && find . -not -name 'meta.conf' -not -type d | while read -r rel; do
        local dst="/${rel#./}"
        mkdir -p "$(dirname "$dst")"
        cp -r "$snap_path/$rel" "$dst" 2>/dev/null
    done)

    spin_ok "Snapshot '$label' restored."
    echo ""

    # Reload i3 + polybar if running
    if pgrep -x i3 &>/dev/null; then
        i3-msg reload &>/dev/null && ok "i3 reloaded"
        if pgrep -x polybar &>/dev/null; then
            pkill polybar; sleep 0.3
            bash "$HOME/.config/polybar/launch.sh" &>/dev/null &
            ok "Polybar restarted"
        fi
    fi

    info "Reopen your terminal to apply all changes."
    echo ""
}

# ── Diff ─────────────────────────────────────────────────────
_snap_diff() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap diff <id>"
        exit 1
    fi

    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]] || [[ ! -f "$snap_path/meta.conf" ]]; then
        err "Snapshot not found: $target"
        exit 1
    fi

    local label
    label=$(grep '^label=' "$snap_path/meta.conf" | cut -d= -f2-)
    header "Diff — $label vs current"

    local changed=0
    local rel snap_file live_file
    # The loop must NOT run in a subshell — otherwise the counter is lost
    # and the diff always reports "no differences".
    while IFS= read -r rel; do
        snap_file="$snap_path/$rel"
        live_file="/${rel#./}"

        if [[ ! -f "$live_file" ]]; then
            printf "  ${RED}-missing${RESET}  %s\n" "${live_file}"
            changed=$((changed + 1))
            continue
        fi
        if ! diff -q "$snap_file" "$live_file" &>/dev/null; then
            printf "  ${ORANGE}~mod${RESET}  %s\n" "${live_file}"
            changed=$((changed + 1))
        fi
    done < <(cd "$snap_path" && find . -not -name 'meta.conf' -not -type d | sort)

    if [[ $changed -eq 0 ]]; then
        ok "No differences found."
    else
        info "$changed difference(s) between snapshot and current config."
    fi
    echo ""
}

# ── Delete ────────────────────────────────────────────────────
_snap_delete() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap delete <id>"
        exit 1
    fi

    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]]; then
        err "Snapshot not found: $target"
        exit 1
    fi

    local label
    label=$(grep '^label=' "$snap_path/meta.conf" 2>/dev/null | cut -d= -f2-)

    read -rp "$(echo -e "${RED}${BOLD}Delete '$label'? [y/N]: ${RESET}")" CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && { info "Cancelled."; return; }

    rm -rf "$snap_path"
    ok "Snapshot '$label' deleted."
    echo ""
}
