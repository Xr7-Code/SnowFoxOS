#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Music & Streaming (Gum TUI)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
#
#  Requires: gum (TUI), mpv (playback), yt-dlp (search/stream)
#  If gum is missing, install instructions are shown.
# ============================================================

MUSIC_CONFIG_DIR="$HOME/.config/snowfox"
PLAYLIST_FILE="$MUSIC_CONFIG_DIR/playlists.json"
PREF_FILE="$MUSIC_CONFIG_DIR/music_source.txt"

# Ensure config dir exists
mkdir -p "$MUSIC_CONFIG_DIR"

# ── SnowFox theme for Gum (matches Polybar / Kitty palette) ──
GUM_PURPLE="#9d6fe8"
GUM_PURPLE_LT="#b899ff"
GUM_RED="#e87a7a"
GUM_DIM="#6e6a8a"
GUM_FG="#e0d9f5"

# ============================================================
#  Source preference
# ============================================================
_get_source() {
    if [[ -f "$PREF_FILE" ]]; then
        cat "$PREF_FILE"
    else
        echo "ytmusic"
    fi
}

_set_source() {
    echo "$1" > "$PREF_FILE"
}

_music_src_display() {
    case "$(_get_source)" in
        ytmusic)    echo "YouTube Music" ;;
        spotify)    echo "Spotify (via YouTube search)" ;;
        soundcloud) echo "SoundCloud" ;;
        youtube)    echo "YouTube" ;;
        *)          echo "YouTube Music" ;;
    esac
}

# ── URL-Encoding (ohne python3/jq-Abhängigkeit) ──────────────
_music_urlencode() {
    printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/&/%26/g' \
                         -e 's/?/%3F/g' -e 's/#/%23/g' -e 's/"/%22/g' \
                         -e "s/'/%27/g"
}

# ── Search-Target für yt-dlp ─────────────────────────────────
# yt-dlp kennt nur echte Search-Prefixes:
#   ytsearch:   → YouTube
#   scsearch:   → SoundCloud
# Es gibt KEIN "ytsearchmusic:" und KEIN "spsearch:" (yt-dlp hat keinen
# Spotify-Extractor). YouTube Music wird über die echte Such-URL
# music.youtube.com/search erreicht.
_music_search_target() {
    # _music_search_target <query> — yt-dlp-Ziel für die aktive Quelle
    local query="$1" enc
    enc=$(_music_urlencode "$query")
    case "$(_get_source)" in
        ytmusic)    echo "https://music.youtube.com/search?q=${enc}" ;;
        soundcloud) echo "scsearch10:${query}" ;;
        spotify)    echo "ytsearch10:${query}" ;;
        *)          echo "ytsearch10:${query}" ;;
    esac
}

# ============================================================
#  Gum widgets (SnowFox themed)
# ============================================================
_music_banner() {
    # _music_banner [subtitle]
    # Draws to stderr — stdout stays reserved for widget results.
    local title="🦊  SnowFox Music"
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

_music_choose() {
    # _music_choose <header> <height> <item...>
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

_music_input() {
    # _music_input <header> <placeholder>
    gum input \
        --header "$1" \
        --placeholder "$2" \
        --prompt "❯ " \
        --width 64 \
        --prompt.foreground "$GUM_PURPLE_LT" \
        --cursor.foreground "$GUM_PURPLE_LT" \
        --header.foreground "$GUM_PURPLE" \
        --placeholder.foreground "$GUM_DIM"
}

_music_spin() {
    # _music_spin <title> <command...>
    local title="$1"
    shift
    gum spin \
        --spinner dot \
        --title "$title" \
        --spinner.foreground "$GUM_PURPLE_LT" \
        --title.foreground "$GUM_FG" \
        -- "$@"
}

_music_filter() {
    # _music_filter <header> <placeholder> <height>   (list on stdin)
    gum filter \
        --header "$1" \
        --placeholder "$2" \
        --height "$3" \
        --indicator "❯ " \
        --indicator.foreground "$GUM_PURPLE_LT" \
        --header.foreground "$GUM_PURPLE" \
        --selected-indicator.foreground "$GUM_PURPLE_LT" \
        --unselected-prefix.foreground "$GUM_DIM"
}

# ============================================================
#  Playlist storage (JSON via python3)
# ============================================================
_init_playlists() {
    if [[ ! -f "$PLAYLIST_FILE" ]]; then
        echo "{}" > "$PLAYLIST_FILE"
    fi
}

_pl_list() {
    # name<TAB>count — one line per playlist
    python3 - "$PLAYLIST_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
for name, tracks in data.items():
    if isinstance(tracks, list):
        print(f"{name}\t{len(tracks)}")
PYEOF
}

_pl_count() {
    _pl_list | wc -l | tr -d ' '
}

_pl_track_count() {
    python3 - "$PLAYLIST_FILE" "$1" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
    tracks = data.get(sys.argv[2], [])
    print(len(tracks) if isinstance(tracks, list) else 0)
except Exception:
    print(0)
PYEOF
}

_pl_create() {
    python3 - "$PLAYLIST_FILE" "$1" <<'PYEOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path, "r") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
if name in data:
    sys.exit(1)
data[name] = []
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
}

_pl_delete() {
    python3 - "$PLAYLIST_FILE" "$1" <<'PYEOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path, "r") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
if not isinstance(data, dict) or name not in data:
    sys.exit(1)
del data[name]
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
}

_pl_add() {
    python3 - "$PLAYLIST_FILE" "$1" "$2" "$3" "$4" <<'PYEOF'
import sys, json
path, name, title, url, src = sys.argv[1:6]
try:
    with open(path, "r") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data.setdefault(name, [])
data[name].append({"title": title, "url": url, "source": src})
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
}

_pl_dump() {
    # Pretty track list for the pager
    python3 - "$PLAYLIST_FILE" "$1" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
    tracks = data.get(sys.argv[2], [])
except Exception:
    tracks = []
print(f"{sys.argv[2]} — {len(tracks)} tracks")
print("─" * 52)
print()
if not tracks:
    print("  (empty)")
for i, t in enumerate(tracks, 1):
    print(f"  {i:>3}.  {t.get('title', 'Unknown')}")
    print(f"        {t.get('source', 'Web')} · {t.get('url', '')}")
PYEOF
}

_pl_urls() {
    # Write all track URLs to $2, print the number of queued tracks
    python3 - "$PLAYLIST_FILE" "$1" "$2" <<'PYEOF'
import sys, json
path, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, "r") as f:
        data = json.load(f)
    tracks = data.get(name, [])
except Exception:
    tracks = []
count = 0
with open(out, "w") as f:
    for t in tracks:
        url = t.get("url", "")
        if url:
            f.write(url + "\n")
            count += 1
print(count)
PYEOF
}

# ============================================================
#  Missing dependency: gum
# ============================================================
_music_gum_missing() {
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
    err "\"gum\" is not installed — it is required for the snowfox music TUI."
    echo ""
    echo -e "  ${BOLD}Install gum once, then run ${CYAN}snowfox music${RESET}${BOLD} again:${RESET}"
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
#  Screens
# ============================================================
_music_immersion_label() {
    # Compact state label for the main menu header
    if declare -F _imm_enabled &>/dev/null && [[ "$(_imm_enabled)" == "true" ]]; then
        echo "ON · $(_imm_get IMMERSION_PROFILE inhead)"
    else
        echo "OFF"
    fi
}

_music_main_menu() {
    _music_banner
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 2" \
        "Source: $(_music_src_display)    ·    Playlists: $(_pl_count)    ·    Immersion: $(_music_immersion_label)" 1>&2
    echo "" >&2
    _music_choose "What would you like to do?" 8 \
        "🎵  Browse & Search" \
        "📂  Playlists" \
        "🎧  Streaming Source" \
        "🔗  Stream direct URL" \
        "🧠  Immersion Mode" \
        "🚪  Quit"
}

_music_browse() {
    local src source_name
    src="$(_get_source)"
    source_name="$(_music_src_display)"

    local query st
    query=$(_music_input "Search · $source_name" "Song, artist or genre — empty = top recommendations")
    st=$?
    [[ $st -ne 0 ]] && return

    if [[ -z "$query" ]]; then
        case "$src" in
            ytmusic)    query="top hits 2026 trending music" ;;
            spotify)    query="global top 50 popular hits" ;;
            soundcloud) query="electronic chill mix 2026" ;;
            *)          query="top music playlist" ;;
        esac
    fi

    local tmp
    tmp=$(mktemp)

    local target
    target=$(_music_search_target "$query")

    _music_spin "Searching $source_name …" \
        bash -c 'yt-dlp --force-ipv4 --extractor-args "youtube:player_client=web,android" --print "%(title)s|%(id)s" --flat-playlist "$1" > "$2" 2>/dev/null' \
        _ "$target" "$tmp"

    local -a results=()
    mapfile -t results < "$tmp"

    if [[ ${#results[@]} -eq 0 ]]; then
        _music_spin "Trying standard YouTube search …" \
            bash -c 'yt-dlp --force-ipv4 --print "%(title)s|%(id)s" --flat-playlist "ytsearch10:$1" > "$2" 2>/dev/null' \
            _ "$query" "$tmp"
        mapfile -t results < "$tmp"
    fi
    rm -f "$tmp"

    if [[ ${#results[@]} -eq 0 ]]; then
        err "No results found."
        sleep 2
        return
    fi

    local -a titles=()
    local r
    for r in "${results[@]}"; do
        titles+=("${r%|*}")
    done

    local selected
    selected=$(printf '%s\n' "${titles[@]}" | _music_filter \
        "Results for \"$query\" · $source_name" \
        "Type to filter — Enter to select" 15)
    st=$?
    [[ $st -ne 0 || -z "$selected" ]] && return

    # Resolve selected title back to its video ID / URL
    local id="" url=""
    for r in "${results[@]}"; do
        if [[ "${r%|*}" == "$selected" ]]; then
            id="${r##*|}"
            break
        fi
    done
    if [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
        url="https://www.youtube.com/watch?v=$id"
    else
        url="ytsearch1:$selected"
    fi

    local action
    action=$(_music_choose "🎵  $selected" 4 \
        "▶   Play now" \
        "➕   Add to playlist" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$action" ]] && return

    case "$action" in
        *Play*) _music_play "$selected" "$url" "$source_name" ;;
        *Add*)  _music_add_to_playlist "$selected" "$url" "$source_name" ;;
    esac
}

_music_play() {
    # _music_play <title> <url> <source> [ask_to_save: 0|1]
    local title="$1" url="$2" src="$3" ask_save="${4:-1}"

    _music_banner "Now Playing"
    echo "" >&2
    gum style --border normal --border-foreground "$GUM_PURPLE" \
        --padding "1 3" \
        "▶   $title" \
        "📡  $src" 1>&2
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 4" \
        "mpv — [Space] pause · [←/→] seek · [9/0] volume · [q] quit" 1>&2
    echo "" >&2
    fox "Streaming…"
    immersion_mpv_args
    immersion_beats_session_start
    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" "${IMM_MPV_ARGS[@]}" "$url"
    immersion_beats_session_stop

    if [[ "$ask_save" == "1" ]] && \
       gum confirm "Add \"$title\" to a playlist?" \
            --affirmative "Yes, save it" \
            --negative "No thanks" \
            --prompt.foreground "$GUM_PURPLE_LT" \
            --selected.background "$GUM_PURPLE"; then
        _music_add_to_playlist "$title" "$url" "$src"
    fi
}

_music_add_to_playlist() {
    local title="$1" url="$2" src="$3"

    local -a names=()
    local name count
    while IFS=$'\t' read -r name count; do
        [[ -n "$name" ]] && names+=("$name")
    done < <(_pl_list)

    local target
    if [[ ${#names[@]} -gt 0 ]]; then
        target=$({ printf '%s\n' "${names[@]}"; printf '%s\n' "➕  Create new playlist …"; } | _music_filter \
            "Add to playlist · $title" \
            "Filter playlists or create a new one" 12)
        local st=$?
        [[ $st -ne 0 || -z "$target" ]] && return
    else
        target="➕  Create new playlist …"
    fi

    if [[ "$target" == *"Create new playlist"* ]]; then
        target=$(_music_input "New playlist" "Playlist name")
        [[ -z "$target" ]] && return
        _pl_create "$target" || true
    fi

    if _pl_add "$target" "$title" "$url" "$src"; then
        ok "Added \"$title\" to playlist \"$target\"."
    else
        err "Could not save track to \"$target\"."
    fi
    sleep 1
}

_music_playlists_menu() {
    while true; do
        _music_banner "Playlists"

        local -a names=() entries=()
        local name count
        while IFS=$'\t' read -r name count; do
            [[ -z "$name" ]] && continue
            names+=("$name")
            entries+=("📁  $name  ($count tracks)")
        done < <(_pl_list)

        local choice st
        choice=$(_music_choose "" 15 "${entries[@]}" \
            "➕  Create new playlist" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" ]] && return

        case "$choice" in
            *"Create new playlist"*) _music_playlist_create ;;
            *Back*)                  return ;;
            *)
                local i
                for i in "${!entries[@]}"; do
                    if [[ "${entries[$i]}" == "$choice" ]]; then
                        _music_playlist_actions "${names[$i]}"
                        break
                    fi
                done
                ;;
        esac
    done
}

_music_playlist_actions() {
    local name="$1" count
    count=$(_pl_track_count "$name")

    local action st
    action=$(_music_choose "📁  $name  ·  $count tracks" 6 \
        "▶   Play playlist" \
        "👁   View tracks" \
        "🗑   Delete playlist" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$action" ]] && return

    case "$action" in
        *Play*)   _music_playlist_play "$name" ;;
        *View*)   _music_playlist_view "$name" ;;
        *Delete*) _music_playlist_delete "$name" ;;
    esac
}

_music_playlist_create() {
    local name
    name=$(_music_input "Create a new playlist" "e.g. Chill Vibes")
    [[ -z "$name" ]] && return

    if _pl_create "$name"; then
        ok "Playlist \"$name\" created."
    else
        warn "Playlist \"$name\" already exists."
    fi
    sleep 1
}

_music_playlist_view() {
    local name="$1" tmp
    _music_banner "Playlist · $name"

    tmp=$(mktemp)
    _pl_dump "$name" > "$tmp"
    gum pager --show-line-numbers \
        --line-number.foreground "$GUM_DIM" \
        --match.foreground "$GUM_PURPLE_LT" < "$tmp"
    rm -f "$tmp"
}

_music_playlist_play() {
    local name="$1" urls_file count
    urls_file=$(mktemp)
    count=$(_pl_urls "$name" "$urls_file")

    if [[ ! -s "$urls_file" ]]; then
        rm -f "$urls_file"
        err "Playlist \"$name\" is empty."
        sleep 1
        return
    fi

    _music_banner "Playing · $name"
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 4" \
        "$count tracks queued in mpv — [q] to stop" 1>&2
    echo "" >&2
    immersion_mpv_args
    immersion_beats_session_start
    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" "${IMM_MPV_ARGS[@]}" --playlist="$urls_file"
    immersion_beats_session_stop
    rm -f "$urls_file"
}

_music_playlist_delete() {
    local name="$1" count
    count=$(_pl_track_count "$name")

    if gum confirm "Delete playlist \"$name\" ($count tracks)?" \
        --affirmative "Delete" \
        --negative "Cancel" \
        --prompt.foreground "$GUM_PURPLE_LT" \
        --selected.background "$GUM_RED"; then
        if _pl_delete "$name"; then
            ok "Playlist \"$name\" deleted."
        else
            err "Could not delete playlist \"$name\"."
        fi
        sleep 1
    fi
}

_music_source_menu() {
    _music_banner "Streaming Source"
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 2" \
        "Active: $(_music_src_display) — used by Browse & Search" 1>&2
    echo "" >&2

    local choice st
    choice=$(_music_choose "Pick a search backend" 7 \
        "🎵  YouTube Music — best music catalog (default)" \
        "🎧  Spotify — track search via YouTube" \
        "☁️   SoundCloud — indie artists & mixes" \
        "▶️   YouTube — standard video search" \
        "↩   Back")
    st=$?
    [[ $st -ne 0 || -z "$choice" ]] && return

    local new_src="" label=""
    case "$choice" in
        *"YouTube Music"*) new_src="ytmusic";    label="YouTube Music" ;;
        *Spotify*)         new_src="spotify";    label="Spotify" ;;
        *SoundCloud*)      new_src="soundcloud"; label="SoundCloud" ;;
        *YouTube*)         new_src="youtube";    label="YouTube" ;;
        *)                 return ;;
    esac

    _set_source "$new_src"
    ok "Streaming source set to $label."
    sleep 1
}

_music_stream_url() {
    _music_banner "Stream Direct URL"
    echo "" >&2

    local url st
    url=$(_music_input "Paste a direct link (YouTube, SoundCloud, …)" "https://…")
    st=$?
    [[ $st -ne 0 || -z "$url" ]] && return

    _music_play "Direct stream" "$url" "Direct URL" 0
}

_music_exit() {
    _music_banner
    ok "Exiting SnowFox Music — see you next time! 🦊"
    sleep 1
}

# ============================================================
#  Entry point
# ============================================================
cmd_music() {
    # ── Dependency checks ────────────────────────────────────
    if ! command -v gum &>/dev/null; then
        _music_gum_missing
        return 1
    fi
    if ! command -v mpv &>/dev/null; then
        err "mpv not found. Install: sudo apt install mpv"
        return 1
    fi
    if ! command -v yt-dlp &>/dev/null; then
        err "yt-dlp not found. Install: sudo apt install yt-dlp"
        return 1
    fi

    _init_playlists

    while true; do
        local choice st
        choice=$(_music_main_menu)
        st=$?
        if [[ $st -ne 0 || -z "$choice" ]]; then
            return 0                    # ESC / Ctrl-C → leave the app
        fi
        case "$choice" in
            *Browse*)        _music_browse ;;
            *Playlists*)     _music_playlists_menu ;;
            *Source*)        _music_source_menu ;;
            *"direct URL"*)  _music_stream_url ;;
            *Immersion*)
                local imm_state
                imm_state=$(immersion_quick_toggle)
                if [[ "$imm_state" == "on" ]]; then
                    ok "Immersion mode ON — profile: $(_imm_get IMMERSION_PROFILE inhead)"
                    info "  Starts with the next track · tune: snowfox immersion tune"
                elif [[ "$imm_state" == "error" ]]; then
                    err "Immersion chain failed on this system — staying OFF."
                    info "  Diagnostics: snowfox immersion doctor"
                else
                    warn "Immersion mode OFF — raw signal for the next track."
                fi
                sleep 1
                ;;
            *Quit*)          _music_exit; return 0 ;;
        esac
    done
}
