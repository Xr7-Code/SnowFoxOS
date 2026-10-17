#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Media (Download & Stream)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

COOKIE_FILE="$HOME/.config/snowfox/cookies.txt"
DOWNLOAD_DIR="$HOME/Downloads"

# ── Cookie helper ────────────────────────────────────────────
# Returns an array in COOKIE_OPT suitable for yt-dlp.
# Order: existing file → browser extraction → empty (no cookies).
_prepare_cookies() {
    COOKIE_OPT=()

    # 1. Existing cookie file (no browser needed)
    if [[ -f "$COOKIE_FILE" && -s "$COOKIE_FILE" ]]; then
        # Refresh if older than 1 day AND a browser is available
        if [[ $(find "$COOKIE_FILE" -mtime +1 2>/dev/null) ]]; then
            for browser in firefox chromium chrome brave; do
                if command -v "$browser" &>/dev/null; then
                    yt-dlp --cookies-from-browser "$browser" \
                        --cookies "$COOKIE_FILE" \
                        --simulate --skip-download 2>/dev/null && break || true
                fi
            done
        fi
        COOKIE_OPT=(--cookies "$COOKIE_FILE")
        return 0
    fi

    # 2. No cookie file → try browser extraction (optional, silent failure)
    for browser in firefox chromium chrome brave; do
        if command -v "$browser" &>/dev/null; then
            mkdir -p "$(dirname "$COOKIE_FILE")"
            if yt-dlp --cookies-from-browser "$browser" \
                --cookies "$COOKIE_FILE" \
                --simulate --skip-download 2>/dev/null; then
                if [[ -f "$COOKIE_FILE" && -s "$COOKIE_FILE" ]]; then
                    COOKIE_OPT=(--cookies "$COOKIE_FILE")
                    return 0
                fi
            fi
        fi
    done

    # 3. No cookies available — continue without them
    return 0
}

# ============================================================
# snowfox fetch — High-speed download via aria2
# ============================================================
cmd_fetch() {
    if ! command -v aria2c &>/dev/null; then
        err "aria2c not found. Install: sudo apt install aria2"
        return 1
    fi

    local URL="${1:-}"
    if [[ -z "$URL" ]] && sf_can_tui; then
        URL=$(sf_ask_ph "Download URL (16 parallel connections)" "https://…")
        [[ -z "$URL" ]] && return 0
    fi
    if [[ -z "$URL" ]]; then
        err "Usage: snowfox fetch <URL> [output-dir]"
        return 1
    fi

    local OUTDIR="${2:-$DOWNLOAD_DIR}"
    mkdir -p "$OUTDIR"

    header "Fetch"
    row "URL" "$URL"
    row "Destination" "$OUTDIR"
    row "Connections" "16 parallel"
    echo ""

    info "Starting download..."
    echo ""

    aria2c \
        --max-connection-per-server=16 \
        --split=16 \
        --min-split-size=1M \
        --file-allocation=none \
        --continue=true \
        --summary-interval=1 \
        --console-log-level=warn \
        --dir="$OUTDIR" \
        "$URL"

    if [[ $? -eq 0 ]]; then
        echo ""
        ok "Download complete: $OUTDIR"
    else
        echo ""
        err "Download failed."
        return 1
    fi
}

# ============================================================
# snowfox dl — Download video/audio via yt-dlp
# ============================================================
cmd_download() {
    if ! command -v yt-dlp &>/dev/null; then
        err "yt-dlp not found. Install: sudo apt install yt-dlp"
        return 1
    fi

    local URL="${1:-}"
    if [[ -z "$URL" ]] && sf_can_tui; then
        URL=$(sf_ask_ph "Video or audio URL" "https://…")
        [[ -z "$URL" ]] && return 0
    fi
    if [[ -z "$URL" ]]; then
        err "Usage: snowfox dl <URL>"
        return 1
    fi

    _prepare_cookies

    header "Download"
    row "URL" "$URL"

    if [[ ${#COOKIE_OPT[@]} -eq 0 ]]; then
        row "Cookies" "none (public access only)" "$ORANGE"
    else
        row "Cookies" "loaded" "$GREEN"
    fi
    echo ""

    local FORMAT=""
    if sf_can_tui; then
        local pick st
        pick=$(sf_choose "Format" 5 \
            "🎬  Video — best quality" \
            "🎵  Audio only — mp3" \
            "🎧  Audio only — opus (smaller)" \
            "↩   Cancel")
        st=$?
        [[ $st -ne 0 || -z "$pick" || "$pick" == *Cancel* ]] && return 0
        case "$pick" in
            *Video*) FORMAT="1" ;;
            *mp3*)   FORMAT="2" ;;
            *opus*)  FORMAT="3" ;;
        esac
    else
        echo -e "  ${CYAN}1${RESET}) Video (best quality)"
        echo -e "  ${CYAN}2${RESET}) Audio only (mp3)"
        echo -e "  ${CYAN}3${RESET}) Audio only (opus, smaller)"
        echo ""
        read -rp "$(echo -e ${PURPLE}${BOLD}"Format [1-3]: "${RESET})" FORMAT
    fi

    mkdir -p "$DOWNLOAD_DIR"

    local BASE_OPTS=(
        --force-ipv4
        --user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        --extractor-args "youtube:player_client=web,android"
        "${COOKIE_OPT[@]}"
    )

    echo ""

    case "$FORMAT" in
        1)
            yt-dlp "${BASE_OPTS[@]}" \
                -f "bestvideo+bestaudio" \
                --merge-output-format mkv \
                -o "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
                "$URL"
            ;;
        2)
            yt-dlp "${BASE_OPTS[@]}" \
                -x \
                --audio-format mp3 \
                --audio-quality 2 \
                --embed-thumbnail \
                --add-metadata \
                -o "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
                "$URL"
            ;;
        3)
            yt-dlp "${BASE_OPTS[@]}" \
                -x \
                --audio-format opus \
                --embed-thumbnail \
                --add-metadata \
                -o "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
                "$URL"
            ;;
        *)
            err "Invalid selection."
            return 1
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        echo ""
        ok "Saved to: $DOWNLOAD_DIR"
    else
        echo ""
        err "Download failed. Try: yt-dlp --update"
        return 1
    fi
}

# ── Search helper (uses globals: _STREAM_QUERY, COOKIE_OPT) ──
_stream_search() {
    yt-dlp --force-ipv4 \
        --extractor-args "youtube:player_client=web,android" \
        "${COOKIE_OPT[@]}" \
        --print "%(title)s|%(id)s" \
        --flat-playlist "ytsearch5:${_STREAM_QUERY}" 2>/dev/null
}

# ============================================================
# snowfox stream — Stream video/audio via mpv
# ============================================================
cmd_stream() {
    if ! command -v mpv &>/dev/null; then
        err "mpv not found. Install: sudo apt install mpv"
        return 1
    fi

    if ! command -v yt-dlp &>/dev/null; then
        err "yt-dlp not found. Install: sudo apt install yt-dlp"
        return 1
    fi

    local AUDIO_ONLY=false
    if [[ "$1" == "-a" || "$1" == "--audio" ]]; then
        AUDIO_ONLY=true
        shift
    fi

    local QUERY="$*"

    # ── Gum TUI: playback mode + search prompt ───────────────
    if [[ -z "$QUERY" ]] && sf_can_tui; then
        sf_banner "Stream"
        local mode_pick st
        mode_pick=$(sf_choose "Playback mode" 5 \
            "🎬  Video (default)" \
            "🎵  Audio only" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$mode_pick" || "$mode_pick" == *Back* ]] && return 0
        [[ "$mode_pick" == *"Audio only"* ]] && AUDIO_ONLY=true

        QUERY=$(sf_ask_ph "Search video or music" "Song, artist, title — or a direct URL")
        [[ -z "$QUERY" ]] && return 0
    fi

    if [[ -z "$QUERY" ]]; then
        read -rp "$(echo -e ${PURPLE}${BOLD}"Search (video/music): "${RESET})" QUERY
        [[ -z "$QUERY" ]] && return 0
    fi

    _prepare_cookies

    local URL
    if [[ "$QUERY" =~ ^http ]]; then
        URL="$QUERY"
    else
        if ! sf_can_tui; then
            header "Stream"
            fox "Searching YouTube: ${BOLD}$QUERY${RESET}"
        fi

        local -a RESULTS
        local tmp
        tmp=$(mktemp)
        _STREAM_QUERY="$QUERY"
        if sf_can_tui; then
            sf_spin_do "Searching YouTube for \"$QUERY\"…" _stream_search "$tmp"
        else
            _stream_search > "$tmp"
        fi
        mapfile -t RESULTS < "$tmp"
        rm -f "$tmp"

        if [[ ${#RESULTS[@]} -eq 0 ]]; then
            err "No results found."
            return 1
        fi

        local ID="" TITLE=""
        if sf_can_tui; then
            local -a titles=()
            local r
            for r in "${RESULTS[@]}"; do
                titles+=("${r%|*}")
            done

            local selected st
            selected=$(printf '%s\n' "${titles[@]}" | sf_filter \
                "Results for \"$QUERY\"" "Type to filter — Enter to play" 12)
            st=$?
            [[ $st -ne 0 || -z "$selected" ]] && return 0

            for r in "${RESULTS[@]}"; do
                if [[ "${r%|*}" == "$selected" ]]; then
                    ID="${r##*|}"
                    TITLE="$selected"
                    break
                fi
            done
        else
            divider
            local i
            for i in "${!RESULTS[@]}"; do
                echo -e "  ${CYAN}$((i+1))${RESET}) ${RESULTS[$i]%|*}"
            done
            divider
            echo ""

            local CHOICE
            read -rp "$(echo -e ${PURPLE}${BOLD}"Select [1-${#RESULTS[@]}]: "${RESET})" CHOICE
            [[ -z "$CHOICE" || ! "$CHOICE" =~ ^[0-9]+$ ]] && return 0
            [[ "$CHOICE" -lt 1 || "$CHOICE" -gt "${#RESULTS[@]}" ]] && return 0

            ID="${RESULTS[$((CHOICE-1))]##*|}"
            TITLE="${RESULTS[$((CHOICE-1))]%|*}"
        fi

        if [[ ! "$ID" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
            URL="ytsearch1:$TITLE"
        else
            URL="https://www.youtube.com/watch?v=$ID"
        fi
    fi

    local EXTRA_OPTS=""
    if $AUDIO_ONLY; then
        info "Audio-only mode active."
        EXTRA_OPTS="--no-video"
    elif [[ -z "$DISPLAY" ]]; then
        info "No graphical session detected — starting in audio-only mode."
        EXTRA_OPTS="--no-video"
    fi

    echo ""
    echo -e "${PURPLE}${BOLD}  mpv controls:${RESET}"
    echo -e "    ${CYAN}Space${RESET}       —  Pause / Play"
    echo -e "    ${CYAN}9 / 0${RESET}       —  Volume down / up"
    echo -e "    ${CYAN}m${RESET}           —  Mute"
    echo -e "    ${CYAN}← / →${RESET}       —  10 seconds back / forward"
    echo -e "    ${CYAN}q${RESET}           —  Quit"
    echo ""

    fox "Starting stream..."
    mpv \
        --ytdl-raw-options="force-ipv4=,no-check-certificate=" \
        --ytdl-format="bestvideo[vcodec^=vp9][height<=1080]+bestaudio/bestvideo[vcodec^=avc1][height<=1080]+bestaudio/best[height<=1080]" \
        --script-opts=ytdl_hook-ytdl_path=yt-dlp \
        --cache=yes \
        --demuxer-max-bytes=150MiB \
        --demuxer-max-back-bytes=75MiB \
        $EXTRA_OPTS \
        "$URL"
}
