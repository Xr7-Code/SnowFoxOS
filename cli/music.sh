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

# ── SnowFox theme for Gum (shared in cli/gum.sh) ─────────────
# Defaults keep this module usable if gum.sh was not sourced.
: "${GUM_PURPLE:=#9d6fe8}"
: "${GUM_PURPLE_LT:=#b899ff}"
: "${GUM_RED:=#e87a7a}"
: "${GUM_DIM:=#6e6a8a}"
: "${GUM_FG:=#e0d9f5}"

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
        spotify)    echo "Spotify (via yt-dlp)" ;;
        soundcloud) echo "SoundCloud" ;;
        youtube)    echo "YouTube" ;;
        *)          echo "YouTube Music" ;;
    esac
}

_music_src_prefix() {
    case "$(_get_source)" in
        ytmusic)    echo "ytsearchmusic" ;;
        spotify)    echo "spsearch" ;;
        soundcloud) echo "scsearch" ;;
        *)          echo "ytsearch" ;;
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
    # Delegates to the shared Gum library (cli/gum.sh)
    if declare -F sf_gum_missing &>/dev/null; then
        sf_gum_missing "the snowfox music TUI"
        return 0
    fi

    # Standalone fallback (gum.sh not loaded)
    echo ""
    err "\"gum\" is not installed — it is required for the snowfox music TUI."
    echo ""
    echo -e "  ${BOLD}Install gum once, then run ${CYAN}snowfox music${RESET}${BOLD} again:${RESET}"
    echo -e "  ${DGRAY}sudo apt install gum${RESET}   or   https://github.com/charmbracelet/gum#installation"
    echo ""
}

# ============================================================
#  Screens
# ============================================================
_music_main_menu() {
    _music_banner
    echo "" >&2
    gum style --foreground "$GUM_DIM" --padding "0 2" \
        "Source: $(_music_src_display)    ·    Playlists: $(_pl_count)" 1>&2
    echo "" >&2
    _music_choose "What would you like to do?" 7 \
        "🎵  Browse & Search" \
        "📂  Playlists" \
        "🎧  Streaming Source" \
        "🔗  Stream direct URL" \
        "🚪  Quit"
}

_music_browse() {
    local src prefix source_name
    src="$(_get_source)"
    prefix="$(_music_src_prefix)"
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

    _music_spin "Searching $source_name …" \
        bash -c 'yt-dlp --force-ipv4 --extractor-args "youtube:player_client=web,android" --print "%(title)s|%(id)s" --flat-playlist "${1}10:${2}" > "$3" 2>/dev/null' \
        _ "$prefix" "$query" "$tmp"

    local -a results=()
    mapfile -t results < "$tmp"

    if [[ ${#results[@]} -eq 0 ]]; then
        _music_spin "Trying standard YouTube search …" \
            bash -c 'yt-dlp --force-ipv4 --print "%(title)s|%(id)s" --flat-playlist "ytsearch10:${1}" > "$2" 2>/dev/null' \
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
    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" "$url"

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
    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" --playlist="$urls_file"
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
        "🎧  Spotify — track search via yt-dlp" \
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
            *Quit*)          _music_exit; return 0 ;;
        esac
    done
}
