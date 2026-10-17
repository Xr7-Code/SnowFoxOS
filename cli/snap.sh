#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Config Snapshots
#  snowfox snap [save|list|restore|diff|delete]
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

SNAP_DIR="$HOME/.config/snowfox/snapshots"

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
        list|ls)    _snap_list         ;;
        restore|r)  _snap_restore "$2" ;;
        diff|d)     _snap_diff "$2"    ;;
        delete|rm)  _snap_delete "$2"  ;;
        "")
            if sf_can_tui; then _snap_tui; else _snap_list; fi
            ;;
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

# ── Collect (shared by save + TUI; prints path and file count) ─
_snap_collect() {
    local label="${1:-$(date '+%Y%m%d_%H%M%S')}"
    # Sanitize label
    label=$(echo "$label" | tr -cs '[:alnum:]_-' '_' | head -c 48)

    local id
    id=$(date '+%Y%m%d_%H%M%S')
    local snap_path="$SNAP_DIR/${id}_${label}"
    mkdir -p "$snap_path"

    local count=0
    local src dest
    for src in "${_SNAP_SOURCES[@]}"; do
        [[ -e "$src" ]] || continue
        dest="$snap_path$(dirname "$src")/"
        mkdir -p "$dest"
        cp -r "$src" "$dest" 2>/dev/null && ((count++))
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

    echo "$snap_path"
    echo "$count"
}

# ── Save ─────────────────────────────────────────────────────
_snap_save() {
    local label="${1:-$(date '+%Y%m%d_%H%M%S')}"

    spin_start "Saving snapshot '$label'..."

    local out snap_path count
    out=$(_snap_collect "$label")
    snap_path=$(echo "$out" | sed -n 1p)
    count=$(echo "$out" | sed -n 2p)

    spin_ok "Snapshot saved: ${BOLD}${snap_path##*/}${RESET}"
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
        ((i++))
    done

    echo ""
    hint "Restore: snowfox snap restore <id>  |  Compare: snowfox snap diff <id>"
    echo ""
}

# ── Apply (copy snapshot files back + reload desktop) ────────
_snap_apply() {
    local snap_path="$1"

    # Auto-save current state first
    _snap_collect "pre-restore" >/dev/null 2>&1

    # Restore: strip snap_path prefix, copy to /
    (cd "$snap_path" && find . -not -name 'meta.conf' -not -type d | while read -r rel; do
        local dst="/${rel#./}"
        mkdir -p "$(dirname "$dst")"
        cp -r "$snap_path/$rel" "$dst" 2>/dev/null
    done)

    # Reload i3 + polybar if running
    if pgrep -x i3 &>/dev/null; then
        i3-msg reload &>/dev/null && ok "i3 reloaded"
        if pgrep -x polybar &>/dev/null; then
            pkill polybar; sleep 0.3
            bash "$HOME/.config/polybar/launch.sh" &>/dev/null &
            ok "Polybar restarted"
        fi
    fi
}

# ── Restore ──────────────────────────────────────────────────
_snap_restore() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap restore <id>"
        info "  List snapshots: snowfox snap"
        return 1
    fi

    # Find snapshot directory (allow partial id match)
    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]] || [[ ! -f "$snap_path/meta.conf" ]]; then
        err "Snapshot not found: $target"
        info "  List snapshots: snowfox snap"
        return 1
    fi

    local label date
    label=$(grep '^label=' "$snap_path/meta.conf" | cut -d= -f2-)
    date=$(grep '^date=' "$snap_path/meta.conf" | cut -d= -f2-)

    header "Restore Snapshot"
    row "Snapshot" "$label" "$CYAN"
    row "Saved"    "$date"
    echo ""

    warn "This will overwrite your current configuration!"
    if ! sf_yesno "Restore? A backup of the current config is saved first." "Restore" "Cancel" no; then
        info "Cancelled."
        return 0
    fi

    spin_start "Restoring '$label'..."
    _snap_apply "$snap_path" >/dev/null 2>&1
    spin_ok "Snapshot '$label' restored."
    echo ""

    info "Reopen your terminal to apply all changes."
    echo ""
}

# ── Diff report (prints changed files vs the live system) ────
_snap_diff_text() {
    local snap_path="$1"
    (cd "$snap_path" && find . -not -name 'meta.conf' -not -type d | while read -r rel; do
        local snap_file="$snap_path/$rel"
        local live_file="/${rel#./}"
        if [[ ! -f "$live_file" ]]; then
            printf '  +new  %s\n' "${live_file}"
            continue
        fi
        diff -q "$snap_file" "$live_file" &>/dev/null || printf '  ~mod  %s\n' "${live_file}"
    done)
}

# ── Diff ─────────────────────────────────────────────────────
_snap_diff() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap diff <id>"
        return 1
    fi

    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]] || [[ ! -f "$snap_path/meta.conf" ]]; then
        err "Snapshot not found: $target"
        return 1
    fi

    local label
    label=$(grep '^label=' "$snap_path/meta.conf" | cut -d= -f2-)
    header "Diff — $label vs current"

    local report
    report=$(_snap_diff_text "$snap_path")
    if [[ -z "$report" ]]; then
        ok "No differences found."
    else
        echo "$report"
    fi
    echo ""
}

# ── Delete ────────────────────────────────────────────────────
_snap_delete() {
    local target="$1"
    if [[ -z "$target" ]]; then
        err "Usage: snowfox snap delete <id>"
        return 1
    fi

    local snap_path
    snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)

    if [[ -z "$snap_path" ]]; then
        err "Snapshot not found: $target"
        return 1
    fi

    local label
    label=$(grep '^label=' "$snap_path/meta.conf" 2>/dev/null | cut -d= -f2-)

    if ! sf_yesno "Delete snapshot '$label'?" "Delete" "Cancel" no; then
        info "Cancelled."
        return 0
    fi

    rm -rf "$snap_path"
    ok "Snapshot '$label' deleted."
    echo ""
}

# ============================================================
#  Gum TUI — Config Snapshots
# ============================================================
_snap_tui() {
    while true; do
        sf_banner "Snapshots"

        local count=0
        if [[ -d "$SNAP_DIR" ]]; then
            count=$(find "$SNAP_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        fi
        sf_note "$count snapshot(s) · $SNAP_DIR"

        local choice st
        choice=$(sf_choose "Config snapshots" 7 \
            "💾  Create snapshot" \
            "📋  Browse snapshots" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *Create*) _snap_tui_create ;;
            *Browse*) _snap_tui_list ;;
        esac
    done
}

_snap_tui_create() {
    local label
    label=$(sf_ask_ph "Snapshot label (optional)" "e.g. before-theme-change")
    [[ -z "$label" ]] && label=$(date '+%Y%m%d_%H%M%S')

    local tmp
    tmp=$(mktemp)
    sf_spin_do "Saving snapshot '$label'…" _snap_collect "$tmp" "$label"

    local out snap_path count
    out=$(cat "$tmp")
    rm -f "$tmp"
    snap_path=$(echo "$out" | sed -n 1p)
    count=$(echo "$out" | sed -n 2p)

    if [[ -n "$snap_path" && -f "$snap_path/meta.conf" ]]; then
        ok "Snapshot saved: $(basename "$snap_path")"
        info "  $count config source(s) archived."
    else
        err "Snapshot failed."
        [[ -n "$out" ]] && info "  $out"
    fi
    echo ""
    sf_pause
}

_snap_tui_list() {
    if [[ ! -d "$SNAP_DIR" ]] || [[ -z "$(ls -A "$SNAP_DIR" 2>/dev/null)" ]]; then
        sf_banner "Snapshots"
        sf_note "No snapshots yet — create one first."
        sleep 1.5
        return 0
    fi

    local -a lines=()
    local snap label id date profile
    for snap in "$SNAP_DIR"/*/; do
        [[ -f "$snap/meta.conf" ]] || continue
        label=$(grep '^label=' "$snap/meta.conf" | cut -d= -f2-)
        id=$(grep '^id=' "$snap/meta.conf" | cut -d= -f2-)
        date=$(grep '^date=' "$snap/meta.conf" | cut -d= -f2-)
        profile=$(grep '^profile=' "$snap/meta.conf" | cut -d= -f2-)
        lines+=("$id  │  $label  │  $date  │  $profile")
    done
    [[ ${#lines[@]} -eq 0 ]] && return 0

    local sel st
    sel=$(printf '%s\n' "${lines[@]}" | sf_filter "Snapshots" "Type to filter · Enter for actions" 14)
    st=$?
    [[ $st -ne 0 || -z "$sel" ]] && return 0

    local target
    target=$(echo "$sel" | awk '{print $1}')

    local snap_path="$SNAP_DIR/${target}"
    [[ -d "$snap_path" ]] || snap_path=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${target}*" 2>/dev/null | head -1)
    [[ -n "$snap_path" && -f "$snap_path/meta.conf" ]] && _snap_tui_manage "$snap_path"
}

_snap_tui_manage() {
    local snap_path="$1"
    local label date
    label=$(grep '^label=' "$snap_path/meta.conf" | cut -d= -f2-)
    date=$(grep '^date=' "$snap_path/meta.conf" | cut -d= -f2-)

    sf_banner "Snapshot"
    sf_note "$label · $date"

    local choice st
    choice=$(sf_choose "What would you like to do?" 8 \
        "🔁  Restore this snapshot" \
        "🔍  Diff against current" \
        "🗑️   Delete snapshot" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

    case "$choice" in
        *Restore*)
            sf_yesno "Restore '$label'? Current config is backed up first." "Restore" "Cancel" no || return 0

            local tmp
            tmp=$(mktemp)
            sf_spin_do "Restoring '$label'…" _snap_apply "$tmp" "$snap_path"
            rm -f "$tmp"

            ok "Snapshot '$label' restored."
            info "  Reopen your terminal to apply all changes."
            echo ""
            sf_pause
            ;;
        *Diff*)
            local tmp
            tmp=$(mktemp)
            {
                echo "Snapshot : $label"
                echo "Saved    : $date"
                echo ""
                divider
                echo ""
                local report
                report=$(_snap_diff_text "$snap_path")
                if [[ -z "$report" ]]; then
                    echo "  ✓  No differences found."
                else
                    echo "$report"
                fi
            } > "$tmp"
            sf_page "Diff — $label" "$tmp"
            rm -f "$tmp"
            ;;
        *Delete*)
            if sf_yesno "Delete snapshot '$label'?" "Delete" "Cancel" no; then
                rm -rf "$snap_path"
                ok "Snapshot '$label' deleted."
                sleep 1
            fi
            ;;
    esac
}
