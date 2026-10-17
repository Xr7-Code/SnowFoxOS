#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Music & Streaming TUI App
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

MUSIC_CONFIG_DIR="$HOME/.config/snowfox"
PLAYLIST_FILE="$MUSIC_CONFIG_DIR/playlists.json"
PREF_FILE="$MUSIC_CONFIG_DIR/music_source.txt"

# Ensure config dir exists
mkdir -p "$MUSIC_CONFIG_DIR"

# Get current source (default: ytmusic)
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

# Python helper for JSON playlists
_json_py() {
    python3 -c "$1" 2>/dev/null
}

_init_playlists() {
    if [[ ! -f "$PLAYLIST_FILE" ]]; then
        echo "{}" > "$PLAYLIST_FILE"
    fi
}

cmd_music() {
    if ! command -v mpv &>/dev/null; then
        err "mpv not found. Install: sudo apt install mpv"
        exit 1
    fi
    if ! command -v yt-dlp &>/dev/null; then
        err "yt-dlp not found. Install: sudo apt install yt-dlp"
        exit 1
    fi

    _init_playlists

    local LAST_TRACK_TITLE=""
    local LAST_TRACK_URL=""
    local LAST_TRACK_SOURCE=""

    while true; do
        clear
        header "SnowFox Music & Stream"
        
        local current_src="$(_get_source)"
        local src_display="YouTube Music"
        case "$current_src" in
            ytmusic) src_display="YouTube Music (ytsearchmusic:)" ;;
            spotify) src_display="Spotify (spsearch:)" ;;
            soundcloud) src_display="SoundCloud (scsearch:)" ;;
            youtube) src_display="YouTube (ytsearch:)" ;;
        esac

        row "Active Source" "$src_display" "$GREEN"
        row "Playlists" "$(python3 -c 'import json; print(len(json.load(open("'"$PLAYLIST_FILE"'"))))' 2>/dev/null || echo 0) stored" "$CYAN"
        divider
        echo ""
        echo -e "  ${CYAN}1${RESET}) 🎵 Browse Recommendations & Search"
        echo -e "  ${CYAN}2${RESET}) 📂 Manage & Play Playlists"
        echo -e "  ${CYAN}3${RESET}) ⚙️  Change Streaming Source"
        echo -e "  ${CYAN}4${RESET}) 🔗 Stream Direct URL"
        echo -e "  ${CYAN}5${RESET}) 🚪 Exit"
        echo ""
        divider
        read -rp "$(echo -e ${PURPLE}${BOLD}"Select option [1-5]: "${RESET})" CHOICE

        case "$CHOICE" in
            1)
                _music_search_and_play
                ;;
            2)
                _music_playlists_menu
                ;;
            3)
                _music_change_source_menu
                ;;
            4)
                read -rp "$(echo -e ${PURPLE}${BOLD}"Enter Stream URL: "${RESET})" direct_url
                if [[ -n "$direct_url" ]]; then
                    fox "Streaming URL..."
                    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" "$direct_url"
                fi
                ;;
            5|q|quit)
                echo ""
                ok "Exiting SnowFox Music."
                exit 0
                ;;
            *)
                warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

_music_change_source_menu() {
    clear
    header "Select Streaming Source"
    echo -e "  ${CYAN}1${RESET}) YouTube Music (Recommended for music)"
    echo -e "  ${CYAN}2${RESET}) Spotify (Track search via yt-dlp)"
    echo -e "  ${CYAN}3${RESET}) SoundCloud (Independent artists & mixes)"
    echo -e "  ${CYAN}4${RESET}) Standard YouTube"
    echo -e "  ${CYAN}5${RESET}) Back"
    echo ""
    read -rp "$(echo -e ${PURPLE}${BOLD}"Choice [1-5]: "${RESET})" src_choice
    case "$src_choice" in
        1) _set_source "ytmusic"; ok "Source set to YouTube Music";;
        2) _set_source "spotify"; ok "Source set to Spotify";;
        3) _set_source "soundcloud"; ok "Source set to SoundCloud";;
        4) _set_source "youtube"; ok "Source set to YouTube";;
        *) return;;
    esac
    sleep 1
}

_music_search_and_play() {
    clear
    local src="$(_get_source)"
    local prefix="ytsearchmusic"
    local source_name="YouTube Music"
    case "$src" in
        ytmusic) prefix="ytsearchmusic"; source_name="YouTube Music";;
        spotify) prefix="spsearch"; source_name="Spotify";;
        soundcloud) prefix="scsearch"; source_name="SoundCloud";;
        youtube) prefix="ytsearch"; source_name="YouTube";;
    esac

    header "Browse / Search ($source_name)"
    echo -e "  ${DGRAY}Tip: Enter a song title, artist, or genre (or leave empty for top recommendations)${RESET}"
    echo ""
    read -rp "$(echo -e ${PURPLE}${BOLD}"Search query: "${RESET})" query

    if [[ -z "$query" ]]; then
        case "$src" in
            ytmusic) query="top hits 2026 trending music";;
            spotify) query="global top 50 popular hits";;
            soundcloud) query="electronic chill mix 2026";;
            *) query="top music playlist";;
        esac
    fi

    fox "Fetching recommendations from $source_name..."

    local -a RESULTS
    mapfile -t RESULTS < <(yt-dlp --force-ipv4 \
        --extractor-args "youtube:player_client=web,android" \
        --print "%(title)s|%(id)s" \
        --flat-playlist "${prefix}10:$query" 2>/dev/null)

    if [[ ${#RESULTS[@]} -eq 0 ]]; then
        # Fallback to standard ytsearch if specialized prefix returns nothing
        mapfile -t RESULTS < <(yt-dlp --force-ipv4 \
            --print "%(title)s|%(id)s" \
            --flat-playlist "ytsearch10:$query" 2>/dev/null)
    fi

    if [[ ${#RESULTS[@]} -eq 0 ]]; then
        err "No results found."
        read -rp "Press Enter to continue..."
        return
    fi

    clear
    header "Results for: $query"
    for i in "${!RESULTS[@]}"; do
        local title="${RESULTS[$i]%|*}"
        echo -e "  ${CYAN}$((i+1))${RESET}) $title"
    done
    divider
    echo -e "  ${CYAN}a [1-N]${RESET}) Add song to playlist"
    echo -e "  ${CYAN}[1-N]${RESET}  ) Play track immediately"
    echo -e "  ${CYAN}b${RESET}      ) Back"
    echo ""
    read -rp "$(echo -e ${PURPLE}${BOLD}"Selection (e.g. '1' or 'a 1'): "${RESET})" action_choice

    if [[ "$action_choice" =~ ^[bB]$ ]]; then
        return
    elif [[ "$action_choice" =~ ^[aA][[:space:]]+([0-9]+)$ ]]; then
        local idx="${BASH_REMATCH[1]}"
        if [[ "$idx" -ge 1 && "$idx" -le "${#RESULTS[@]}" ]]; then
            local sel="${RESULTS[$((idx-1))]}"
            local title="${sel%|*}"
            local id="${sel##*|}"
            local url=""
            if [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
                url="https://www.youtube.com/watch?v=$id"
            else
                url="ytsearch1:$title"
            fi
            _music_add_to_playlist_prompt "$title" "$url" "$source_name"
        fi
    elif [[ "$action_choice" =~ ^[0-9]+$ ]]; then
        local idx="$action_choice"
        if [[ "$idx" -ge 1 && "$idx" -le "${#RESULTS[@]}" ]]; then
            local sel="${RESULTS[$((idx-1))]}"
            local title="${sel%|*}"
            local id="${sel##*|}"
            local url=""
            if [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
                url="https://www.youtube.com/watch?v=$id"
            else
                url="ytsearch1:$title"
            fi
            
            LAST_TRACK_TITLE="$title"
            LAST_TRACK_URL="$url"
            LAST_TRACK_SOURCE="$source_name"

            clear
            header "Now Playing"
            row "Track" "$title" "$GREEN"
            row "Source" "$source_name" "$CYAN"
            echo ""
            echo -e "${PURPLE}${BOLD}  mpv controls:${RESET}"
            echo -e "    ${CYAN}Space${RESET} — Pause/Play | ${CYAN}9/0${RESET} — Volume | ${CYAN}q${RESET} — Quit"
            echo ""
            fox "Streaming..."
            mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" "$url"
            
            echo ""
            read -rp "Add this track to a playlist? [y/N]: " add_YN
            if [[ "$add_YN" =~ ^[yY]$ ]]; then
                _music_add_to_playlist_prompt "$title" "$url" "$source_name"
            fi
        fi
    fi
}

_music_playlists_menu() {
    while true; do
        clear
        header "Playlist Manager"

        python3 - "$PLAYLIST_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    if not data:
        print("  (No playlists created yet)")
    else:
        for i, (name, tracks) in enumerate(data.items(), 1):
            print(f"  {i}) 📁 {name} ({len(tracks)} tracks)")
except Exception:
    print("  (No playlists created yet)")
PYEOF

        echo ""
        echo -e "  ${CYAN}c${RESET}) Create new playlist"
        echo -e "  ${CYAN}p [N]${RESET}) Play playlist N"
        echo -e "  ${CYAN}v [N]${RESET}) View tracks in playlist N"
        echo -e "  ${CYAN}d [N]${RESET}) Delete playlist N"
        echo -e "  ${CYAN}b${RESET}) Back to main menu"
        echo ""
        divider
        read -rp "$(echo -e ${PURPLE}${BOLD}"Action: "${RESET})" pl_action

        if [[ "$pl_action" =~ ^[bB]$ ]]; then
            break
        elif [[ "$pl_action" =~ ^[cC][[:space:]]*$|^[cC]$ ]]; then
            read -rp "Enter new playlist name: " pl_name
            if [[ -n "$pl_name" ]]; then
                python3 - "$PLAYLIST_FILE" "$pl_name" <<'PYEOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path, 'r') as f:
        data = json.load(f)
except:
    data = {}
if name not in data:
    data[name] = []
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Playlist '{name}' created successfully.")
else:
    print(f"Playlist '{name}' already exists.")
PYEOF
                ok "Playlist created!"
                sleep 1
            fi
        elif [[ "$pl_action" =~ ^[vV][[:space:]]+([0-9]+)$ ]]; then
            local idx="${BASH_REMATCH[1]}"
            _music_view_playlist "$idx"
        elif [[ "$pl_action" =~ ^[pP][[:space:]]+([0-9]+)$ ]]; then
            local idx="${BASH_REMATCH[1]}"
            _music_play_playlist "$idx"
        elif [[ "$pl_action" =~ ^[dD][[:space:]]+([0-9]+)$ ]]; then
            local idx="${BASH_REMATCH[1]}"
            python3 - "$PLAYLIST_FILE" "$idx" <<'PYEOF'
import sys, json
path, idx = sys.argv[1], int(sys.argv[2])
try:
    with open(path, 'r') as f:
        data = json.load(f)
    keys = list(data.keys())
    if 1 <= idx <= len(keys):
        removed = keys[idx-1]
        del data[removed]
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Removed playlist '{removed}'.")
except Exception as e:
    print(f"Error: {e}")
PYEOF
            ok "Playlist deleted."
            sleep 1
        fi
    done
}

_music_add_to_playlist_prompt() {
    local title="$1"
    local url="$2"
    local source="$3"

    clear
    header "Add to Playlist"
    echo -e "Track: ${BOLD}$title${RESET}"
    echo ""

    python3 - "$PLAYLIST_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    if not data:
        print("  No playlists available.")
    else:
        for i, name in enumerate(data.keys(), 1):
            print(f"  {i}) {name}")
except:
    print("  No playlists available.")
PYEOF

    echo ""
    read -rp "Select playlist number (or 'c' to create new): " pl_choice
    if [[ "$pl_choice" =~ ^[cC]$ ]]; then
        read -rp "New playlist name: " pl_name
        if [[ -n "$pl_name" ]]; then
            python3 - "$PLAYLIST_FILE" "$pl_name" "$title" "$url" "$source" <<'PYEOF'
import sys, json
path, name, title, url, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
try:
    with open(path, 'r') as f:
        data = json.load(f)
except:
    data = {}
if name not in data:
    data[name] = []
data[name].append({"title": title, "url": url, "source": src})
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
            ok "Created playlist '$pl_name' and added track!"
            sleep 1
        fi
    elif [[ "$pl_choice" =~ ^[0-9]+$ ]]; then
        python3 - "$PLAYLIST_FILE" "$pl_choice" "$title" "$url" "$source" <<'PYEOF'
import sys, json
path, idx, title, url, src = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
try:
    with open(path, 'r') as f:
        data = json.load(f)
    keys = list(data.keys())
    if 1 <= idx <= len(keys):
        name = keys[idx-1]
        data[name].append({"title": title, "url": url, "source": src})
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Added to '{name}'.")
except Exception as e:
    print(f"Error: {e}")
PYEOF
        ok "Track added to playlist successfully!"
        sleep 1
    fi
}

_music_view_playlist() {
    local idx="$1"
    clear
    python3 - "$PLAYLIST_FILE" "$idx" <<'PYEOF'
import sys, json
path, idx = sys.argv[1], int(sys.argv[2])
try:
    with open(path, 'r') as f:
        data = json.load(f)
    keys = list(data.keys())
    if 1 <= idx <= len(keys):
        name = keys[idx-1]
        tracks = data[name]
        print(f"Playlist: {name} ({len(tracks)} tracks)\n" + "─"*40)
        for i, t in enumerate(tracks, 1):
            print(f"  {i}. {t.get('title')} [{t.get('source', 'Web')}]")
    else:
        print("Invalid playlist index.")
except Exception as e:
    print(f"Error: {e}")
PYEOF
    echo ""
    read -rp "Press Enter to return..."
}

_music_play_playlist() {
    local idx="$1"
    local urls_file
    urls_file=$(mktemp)

    python3 - "$PLAYLIST_FILE" "$idx" "$urls_file" <<'PYEOF'
import sys, json
path, idx, outpath = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    with open(path, 'r') as f:
        data = json.load(f)
    keys = list(data.keys())
    if 1 <= idx <= len(keys):
        name = keys[idx-1]
        with open(outpath, 'w') as out:
            for t in data[name]:
                out.write(t.get('url') + "\n")
except Exception as e:
    pass
PYEOF

    if [[ ! -s "$urls_file" ]]; then
        err "Playlist is empty or invalid."
        rm -f "$urls_file"
        sleep 1
        return
    fi

    fox "Playing playlist via mpv..."
    mpv --no-video --ytdl-raw-options="force-ipv4=,no-check-certificate=" --playlist="$urls_file"
    rm -f "$urls_file"
}
