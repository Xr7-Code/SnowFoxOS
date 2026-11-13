#!/bin/bash
# ============================================================
#    SnowFoxOS v3.4 — cli/theme.sh
#    Handles: snowfox theme [name]
#    Renders all templates with the active theme's tokens.
#    Tokens: BG, ACCENT, FG (3 only — single source of truth)
# ============================================================

# ── Bootstrap ────────────────────────────────────────────────
SNOWFOX_LIB="${SNOWFOX_LIB:-/usr/local/lib/snowfox}"
source "$SNOWFOX_LIB/cli/00-bootstrap.sh" 2>/dev/null || {
    # Fallback for running directly from repo (dev mode)
    SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
    REPO_DIR="$(dirname "$SCRIPT_DIR")"
    THEMES_DIR="$REPO_DIR/themes"
    TEMPLATES_DIR="$REPO_DIR/templates"
}

THEMES_DIR="${THEMES_DIR:-/usr/local/lib/snowfox/themes}"
TEMPLATES_DIR="${TEMPLATES_DIR:-/usr/local/lib/snowfox/templates}"
THEME_CONF="$THEMES_DIR/theme.conf"

# ── Colors for output ────────────────────────────────────────
_ok()   { printf '\033[0;35m✓\033[0m %s\n' "$*"; }
_info() { printf '\033[0;37m·\033[0m %s\n' "$*"; }
_err()  { printf '\033[0;31m✗\033[0m %s\n' "$*" >&2; }

# ── Load active theme conf ───────────────────────────────────
_load_theme_conf() {
    [[ -f "$THEME_CONF" ]] || { _err "Missing: $THEME_CONF"; exit 1; }
    source "$THEME_CONF"
}

# ── Load a specific theme file ───────────────────────────────
_load_theme() {
    local name="$1"
    local file="$THEMES_DIR/${name}.theme"
    [[ -f "$file" ]] || { _err "Theme not found: $name  (looked in $THEMES_DIR)"; exit 1; }
    source "$file"
    # Validate required tokens
    [[ -z "$BG"     ]] && { _err "Theme $name: BG not set";     exit 1; }
    [[ -z "$ACCENT" ]] && { _err "Theme $name: ACCENT not set"; exit 1; }
    [[ -z "$FG"     ]] && { _err "Theme $name: FG not set";     exit 1; }
}

# ── Render one template ──────────────────────────────────────
_render() {
    local tmpl="$1"
    local target="$2"
    local desc="$3"

    local full_tmpl="$TEMPLATES_DIR/$tmpl"
    [[ -f "$full_tmpl" ]] || { _err "Template missing: $full_tmpl"; return 1; }

    mkdir -p "$(dirname "$target")"

    # Simple token substitution: ${BG} ${ACCENT} ${FG} ${THEME_NAME}
    sed \
        -e "s|\${BG}|$BG|g" \
        -e "s|\${ACCENT}|$ACCENT|g" \
        -e "s|\${FG}|$FG|g" \
        -e "s|\${THEME_NAME}|$THEME_NAME|g" \
        "$full_tmpl" > "$target"

    _ok "$desc  →  $target"
}

# ── List available themes ────────────────────────────────────
cmd_theme_list() {
    _load_theme_conf
    echo ""
    echo "Available themes:"
    for f in "$THEMES_DIR"/*.theme; do
        local n; n="$(basename "$f" .theme)"
        if [[ "$n" == "$ACTIVE_THEME" ]]; then
            printf '  \033[0;35m● %s\033[0m  (active)\n' "$n"
        else
            printf '  \033[0;37m○ %s\033[0m\n' "$n"
        fi
    done
    echo ""
}

# ── Set + render theme ───────────────────────────────────────
cmd_theme_set() {
    local name="$1"
    _load_theme_conf
    _load_theme "$name"

    echo ""
    _info "Rendering theme: $THEME_LABEL  ($BG · $ACCENT · $FG)"
    echo ""

    # Render all configured templates
    for rule in "${RENDER_RULES[@]}"; do
        local target tmpl desc
        target="${rule%%|*}"
        rest="${rule#*|}"
        tmpl="${rest%%|*}"
        desc="${rest##*|}"
        _render "$tmpl" "$target" "$desc"
    done

    # Persist active theme
    sed -i "s|^ACTIVE_THEME=.*|ACTIVE_THEME=\"$name\"|" "$THEME_CONF"

    echo ""
    _ok "Theme applied: $THEME_LABEL"
    _info "Restart i3 (Mod+Shift+R) or run: i3-msg restart"
    echo ""
}

# ── Re-render current theme (after update) ──────────────────
cmd_theme_reload() {
    _load_theme_conf
    cmd_theme_set "$ACTIVE_THEME"
}

# ── Main dispatcher ──────────────────────────────────────────
cmd_theme() {
    case "${1:-}" in
        "")         _load_theme_conf; _info "Active theme: $ACTIVE_THEME"; cmd_theme_list ;;
        list)       cmd_theme_list ;;
        reload)     cmd_theme_reload ;;
        *)          cmd_theme_set "$1" ;;
    esac
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cmd_theme "$@"
fi
