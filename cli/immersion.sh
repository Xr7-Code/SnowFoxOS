#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Immersion Mode
#  Deep-listening DSP for everything SnowFox plays
#
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
#
#  Signal path (all processed by FFmpeg/libavfilter inside mpv
#  in real time — nothing is re-encoded, nothing is downloaded):
#
#     trim ──▶ bass ──▶ virtualbass ──▶ space ──▶ haas ──▶ crossfeed ──▶ alimiter
#     │        │        │               │         │         │             │
#     │        │        │               │         │         │             └ safety net
#     │        │        │               │         │         └ headphone stage (out of your head)
#     │        │        │               │         └ stereo width (the room)
#     │        │        │               └ super stereo (inside your head)
#     │        │        └ psychoacoustic sub harmonics (feel the low end)
#     │        └ low shelf (body)
#     └ headroom trim (keeps the limiter transparent)
#
#  Plus an optional binaural-beat layer: two pure tones, one per
#  ear, whose frequency difference is the beat the brain hears.
# ============================================================

IMM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snowfox"
IMM_FILE="$IMM_CONFIG_DIR/immersion.conf"

IMM_RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/snowfox-immersion"
IMM_PID_FILE="$IMM_RUN_DIR/beats.pid"
IMM_MODE_FILE="$IMM_RUN_DIR/beats.mode"

IMM_MPV_DIR="$HOME/.config/mpv"
IMM_MPV_INCLUDE="$IMM_MPV_DIR/snowfox-immersion.conf"
IMM_MPV_CONF="$IMM_MPV_DIR/mpv.conf"

# Global array filled by immersion_mpv_args() — expanded by the
# playback front-ends (music TUI, snowfox stream, …).
IMM_MPV_ARGS=()

# Internal testing hook: override the audio output used by the
# beat generator and the test signal (e.g. SNOWFOX_IMM_AO=null).
IMM_AO="${SNOWFOX_IMM_AO:-}"

# ============================================================
#  Config file
# ============================================================
_imm_init() {
    mkdir -p "$IMM_CONFIG_DIR"
    if [[ ! -f "$IMM_FILE" ]]; then
        cat <<'EOF' > "$IMM_FILE"
# ============================================================
#  SnowFoxOS — Immersion Mode
#  Managed by: snowfox immersion · tune with the CLI, not here
# ============================================================
IMMERSION_ENABLED=false
IMMERSION_PROFILE=brain
IMMERSION_CROSSFEED=0
IMMERSION_BASS=6
IMMERSION_VB=0
IMMERSION_WIDTH=1.10
IMMERSION_SPACE=1.50
IMMERSION_BEATS=true
IMMERSION_BEAT=10
IMMERSION_CARRIER=300
IMMERSION_BEAT_VOL=0.04
IMMERSION_TRIM=-3.5
IMMERSION_MPV_INCLUDE=false
EOF
        chmod 600 "$IMM_FILE"
    fi
}

_imm_get() {
    # _imm_get <KEY> <default>
    _imm_init
    local key="$1" default="$2" val
    val=$(grep -E "^${key}=" "$IMM_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
    echo "${val:-$default}"
}

_imm_set() {
    # _imm_set <KEY> <value>
    _imm_init
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$IMM_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$IMM_FILE"
    else
        echo "${key}=${val}" >> "$IMM_FILE"
    fi
}

_imm_enabled() {
    # echoes true|false
    [[ "$(_imm_get IMMERSION_ENABLED false)" == "true" ]] && echo true || echo false
}

_imm_is_num() {
    # _imm_is_num <value> <min> <max>
    # LC_ALL=C: the config always uses dots as decimal separators,
    # as does the generated FFmpeg graph.
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    LC_ALL=C awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v >= lo && v <= hi) }'
}

_imm_gt() {
    # _imm_gt <value> <reference>  — true when value > reference
    LC_ALL=C awk -v v="$1" -v r="$2" 'BEGIN { exit !(v > r) }'
}

# ============================================================
#  Profiles — named presets
# ============================================================
_imm_profile_norm() {
    # map aliases to canonical profile names
    case "$1" in
        head|clarity|natural|kopf|klar)      echo "head" ;;
        body|deep|bass|koerper|körper)       echo "body" ;;
        mind|focus|brains|beats|gehirn)      echo "mind" ;;
        brain|imkopf|inkopf|schaedel|schädel) echo "brain" ;;
        total|all|full|everything|ganz)      echo "total" ;;
        *)                                   echo "$1" ;;
    esac
}

_imm_profile_desc() {
    case "$1" in
        head)  echo "Headphone stage — crossfeed lifts the music out of your head" ;;
        body)  echo "Physical bass — clean low shelf + wide super stereo" ;;
        mind)  echo "Binaural focus — two pure tones, one per ear, under the music" ;;
        brain) echo "In-head — super stereo + binaural beats, no crossfeed" ;;
        total) echo "Everything — crossfeed + bass + super stereo + binaural beats" ;;
        *)     echo "Unknown profile" ;;
    esac
}

_imm_profile_apply() {
    # _imm_profile_apply <name> — returns 1 on unknown profile
    local p
    p="$(_imm_profile_norm "$1")"
    case "$p" in
        head)
            _imm_set IMMERSION_CROSSFEED 0.35
            _imm_set IMMERSION_BASS 0
            _imm_set IMMERSION_VB 0
            _imm_set IMMERSION_WIDTH 1.10
            _imm_set IMMERSION_SPACE 1.00
            _imm_set IMMERSION_TRIM 0
            _imm_set IMMERSION_BEATS false
            ;;
        body)
            _imm_set IMMERSION_CROSSFEED 0.20
            _imm_set IMMERSION_BASS 8
            _imm_set IMMERSION_VB 0
            _imm_set IMMERSION_WIDTH 1.15
            _imm_set IMMERSION_SPACE 1.10
            _imm_set IMMERSION_TRIM -3.0
            _imm_set IMMERSION_BEATS false
            ;;
        mind)
            _imm_set IMMERSION_CROSSFEED 0.25
            _imm_set IMMERSION_BASS 0
            _imm_set IMMERSION_VB 0
            _imm_set IMMERSION_WIDTH 1.05
            _imm_set IMMERSION_SPACE 1.10
            _imm_set IMMERSION_TRIM 0
            _imm_set IMMERSION_BEATS true
            ;;
        brain)
            _imm_set IMMERSION_CROSSFEED 0
            _imm_set IMMERSION_BASS 6
            _imm_set IMMERSION_VB 0
            _imm_set IMMERSION_WIDTH 1.10
            _imm_set IMMERSION_SPACE 1.50
            _imm_set IMMERSION_TRIM -3.5
            _imm_set IMMERSION_BEATS true
            ;;
        total)
            _imm_set IMMERSION_CROSSFEED 0.25
            _imm_set IMMERSION_BASS 5
            _imm_set IMMERSION_VB 0
            _imm_set IMMERSION_WIDTH 1.10
            _imm_set IMMERSION_SPACE 1.20
            _imm_set IMMERSION_TRIM -1.5
            _imm_set IMMERSION_BEATS true
            ;;
        *)  return 1 ;;
    esac
    _imm_set IMMERSION_PROFILE "$p"
    return 0
}

# ============================================================
#  Filter graph builders
# ============================================================
_imm_chain_af() {
    # Echoes the lavfi filter chain for --af=lavfi=[…] (may be empty)
    local cf bass vb width space trim
    cf="$(_imm_get IMMERSION_CROSSFEED 0)"
    bass="$(_imm_get IMMERSION_BASS 6)"
    vb="$(_imm_get IMMERSION_VB 0)"
    width="$(_imm_get IMMERSION_WIDTH 1.10)"
    space="$(_imm_get IMMERSION_SPACE 1.50)"
    trim="$(_imm_get IMMERSION_TRIM -3.5)"

    local parts=()
    _imm_gt "$bass" 0     && parts+=("bass=f=55:w=1.2:g=$bass")
    if _imm_gt "$vb" 0; then
        # FFmpeg's virtualbass "strength" is inverted (0.5 = maximum,
        # 3.0 = almost off). Map the user-facing value so higher = stronger.
        local vbs
        vbs=$(LC_ALL=C awk -v u="$vb" 'BEGIN { s = 3.5 - u; if (s < 0.5) s = 0.5; if (s > 3) s = 3; printf "%.2f", s }')
        parts+=("virtualbass=cutoff=140:strength=$vbs")
    fi
    if _imm_gt "$space" 1.0; then
        # Clean mid/side super stereo: sides ×space, centre untouched.
        # (extrastereo behaves erratically after the bass stage; pan is exact.)
        local a b
        a=$(LC_ALL=C awk -v s="$space" 'BEGIN { printf "%.4f", (1 + s) / 2 }')
        b=$(LC_ALL=C awk -v s="$space" 'BEGIN { printf "%.4f", (1 - s) / 2 }')
        parts+=("pan=stereo|c0=${a}*c0${b}*c1|c1=${b}*c0+${a}*c1")
    fi
    _imm_gt "$width" 1.0  && parts+=("haas=side_gain=$width:middle_source=mid")
    _imm_gt "$cf" 0       && parts+=("crossfeed=strength=$cf:range=0.5:slope=0.5:level_in=1")

    [[ ${#parts[@]} -eq 0 ]] && return 0
    # Headroom: the boosts raise loudness; the limiter catches peaks.
    # The trim is calibrated per profile (see _imm_profile_apply) so the
    # limiter stays transparent on loud masters and the bass stays clean.
    parts=("volume=${trim}dB" "${parts[@]}")
    parts+=("alimiter=limit=0.97")

    local IFS=,
    echo "${parts[*]}"
}

_imm_beats_on() {
    [[ "$(_imm_get IMMERSION_BEATS true)" == "true" ]] && echo true || echo false
}

_imm_beat_freqs() {
    # echoes "<left> <right>" carrier frequencies (beat = difference)
    local carrier beat
    carrier="$(_imm_get IMMERSION_CARRIER 300)"
    beat="$(_imm_get IMMERSION_BEAT 10)"
    LC_ALL=C awk -v c="$carrier" -v b="$beat" 'BEGIN { printf "%g %g\n", c - b / 2, c + b / 2 }'
}

_imm_beats_graph() {
    # lavfi-complex graph for the beat generator process:
    # an infinite, phase-continuous two-channel tone source.
    local vol l r
    vol="$(_imm_get IMMERSION_BEAT_VOL 0.04)"
    read -r l r <<< "$(_imm_beat_freqs)"
    printf 'aevalsrc=exprs=%s*sin(2*PI*%s*t)|%s*sin(2*PI*%s*t):s=48000:c=stereo:d=86400[ao]' \
        "$vol" "$l" "$vol" "$r"
}

# ============================================================
#  mpv front-end integration
# ============================================================
_imm_build_mpv_args() {
    # Fills IMM_MPV_ARGS from the current configuration (no state check)
    IMM_MPV_ARGS=()
    local af
    af="$(_imm_chain_af)"
    [[ -n "$af" ]] && IMM_MPV_ARGS+=(--af="lavfi=[$af]")
    return 0
}

immersion_mpv_args() {
    # Used by the playback front-ends: adds the DSP chain when the
    # mode is enabled. Leaves IMM_MPV_ARGS empty otherwise.
    IMM_MPV_ARGS=()
    [[ "$(_imm_enabled)" == "true" ]] || return 0
    _imm_build_mpv_args
}

immersion_validate() {
    # Runs the configured chain for a few silent frames.
    command -v mpv &>/dev/null || return 1
    local af
    af="$(_imm_chain_af)"
    [[ -z "$af" ]] && return 0
    timeout 15 mpv --no-config --no-video --ao=null --really-quiet --length=0.3 \
        --af="lavfi=[$af]" \
        'av://lavfi:sine=frequency=440:duration=0.3' &>/dev/null
}

_imm_validate_beats() {
    command -v mpv &>/dev/null || return 1
    timeout 15 mpv --no-config --no-video --ao=null --really-quiet --length=0.3 \
        --lavfi-complex="$(_imm_beats_graph)" \
        'av://lavfi:anullsrc=r=48000:cl=stereo' &>/dev/null
}

# ============================================================
#  Binaural beat layer (background generator process)
# ============================================================
_imm_beats_pid() {
    [[ -f "$IMM_PID_FILE" ]] && cat "$IMM_PID_FILE" || echo ""
}

_imm_beats_running() {
    local pid
    pid="$(_imm_beats_pid)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

_imm_beats_cleanup() {
    rm -f "$IMM_PID_FILE" "$IMM_MODE_FILE" 2>/dev/null
}

_imm_beats_stop() {
    local pid i
    pid="$(_imm_beats_pid)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        for i in {1..20}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    fi
    _imm_beats_cleanup
}

_imm_beats_start() {
    # _imm_beats_start <auto|manual>
    local mode="${1:-manual}"
    command -v mpv &>/dev/null || return 1
    [[ "$(_imm_beats_on)" == "true" ]] || return 1
    _imm_beats_running && return 0

    mkdir -p "$IMM_RUN_DIR"
    chmod 700 "$IMM_RUN_DIR" 2>/dev/null

    local -a cmd=(mpv --no-config --no-video --no-terminal --really-quiet
                  --audio-client-name=snowfox-immersion-beats)
    [[ -n "$IMM_AO" ]] && cmd+=(--ao="$IMM_AO")
    cmd+=(--lavfi-complex="$(_imm_beats_graph)"
          'av://lavfi:anullsrc=r=48000:cl=stereo')

    # The inner shell writes its own PID (which becomes mpv via exec)
    # into the pid file, then execs the generator in a new session:
    # it survives the front-end, but stays fully under our control.
    #
    #   auto   = tied to a playback session — 2 h safety net in case
    #            the front-end dies without running its cleanup
    #   manual = user-controlled, runs until 'beats off'
    if [[ "$mode" == "auto" ]]; then
        setsid bash -c 'echo $$ > "$1"; shift; exec timeout 7200 "$@"' \
            _ "$IMM_PID_FILE" "${cmd[@]}" &>/dev/null &
    else
        setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' \
            _ "$IMM_PID_FILE" "${cmd[@]}" &>/dev/null &
    fi
    disown 2>/dev/null || true
    echo "$mode" > "$IMM_MODE_FILE"

    # wait for the generator to come up (max ~1 s)
    local i
    for i in {1..20}; do
        _imm_beats_running && return 0
        sleep 0.05
    done
    _imm_beats_cleanup
    return 1
}

# Playback front-ends: start the beat layer around a playback session.
immersion_beats_session_start() {
    [[ "$(_imm_enabled)" == "true" ]] || return 0
    [[ "$(_imm_beats_on)" == "true" ]] || return 0
    if _imm_beats_running; then
        return 0                    # manual layer already running → keep it
    fi
    _imm_beats_start auto
}

immersion_beats_session_stop() {
    local mode=""
    [[ -f "$IMM_MODE_FILE" ]] && mode="$(cat "$IMM_MODE_FILE")"
    [[ "$mode" == "auto" ]] && _imm_beats_stop
    return 0
}

# ============================================================
#  mpv-wide integration (opt-in include file)
# ============================================================
_imm_mpv_include_write() {
    # Regenerates the include file used by ~/.config/mpv/mpv.conf
    local af
    af="$(_imm_chain_af)"
    mkdir -p "$IMM_MPV_DIR"
    {
        echo "# ============================================================"
        echo "#  SnowFoxOS — Immersion Mode (mpv-wide DSP)"
        echo "#  Generated by: snowfox immersion mpv on"
        echo "#  Do not edit by hand — re-run the command instead."
        echo "# ============================================================"
        echo ""
        if [[ -n "$af" ]]; then
            echo "af=lavfi=[$af]"
        else
            echo "# (no filters active — tune with: snowfox immersion tune)"
        fi
    } > "$IMM_MPV_INCLUDE"
}

_imm_mpv_include_enabled() {
    [[ -f "$IMM_MPV_CONF" ]] && grep -q '^include=~~/snowfox-immersion.conf' "$IMM_MPV_CONF" 2>/dev/null
}

_imm_mpv_include_sync() {
    _imm_mpv_include_enabled || return 0
    _imm_mpv_include_write
}

_imm_mpv_include_add() {
    mkdir -p "$IMM_MPV_DIR"
    [[ -f "$IMM_MPV_CONF" ]] && cp -n "$IMM_MPV_CONF" "$IMM_MPV_CONF.snowfox-backup" 2>/dev/null
    sed -i '/^# SnowFox Immersion (managed)$/d; /^include=~~\/snowfox-immersion.conf$/d' "$IMM_MPV_CONF" 2>/dev/null
    {
        echo "# SnowFox Immersion (managed)"
        echo "include=~~/snowfox-immersion.conf"
    } >> "$IMM_MPV_CONF"
    _imm_mpv_include_write
    _imm_set IMMERSION_MPV_INCLUDE true
}

_imm_mpv_include_remove() {
    if [[ -f "$IMM_MPV_CONF" ]]; then
        sed -i '/^# SnowFox Immersion (managed)$/d; /^include=~~\/snowfox-immersion.conf$/d' "$IMM_MPV_CONF"
    fi
    rm -f "$IMM_MPV_INCLUDE"
    _imm_set IMMERSION_MPV_INCLUDE false
}

# ============================================================
#  Output device detection (best effort)
# ============================================================
_imm_default_sink() {
    command -v pactl &>/dev/null || return 0
    pactl get-default-sink 2>/dev/null || \
        pactl info 2>/dev/null | sed -n 's/^Default Sink: //p'
}

_imm_output_type() {
    # echoes: headphones | bluetooth | hdmi | speakers | unknown
    local sink port
    sink="$(_imm_default_sink)"
    [[ -z "$sink" ]] && { echo "unknown"; return 0; }

    port=$(pactl list sinks 2>/dev/null | awk -v name="$sink" '
        $1 == "Name:" { cur = $2 }
        cur == name && $1 == "Active" && $2 == "Port:" { print $3; exit }')

    case "$sink" in
        bluez_output*|bluez_sink*)            echo "bluetooth" ;;
        *headphone*|*headset*)                echo "headphones" ;;
        *)
            case "$port" in
                *headphone*|*headset*)        echo "headphones" ;;
                *hdmi*|*displayport*)         echo "hdmi" ;;
                ""|*)                         echo "speakers" ;;
            esac
            ;;
    esac
}

_imm_output_hint() {
    case "$(_imm_output_type)" in
        headphones) echo "headphones detected — binaural content works as intended" ;;
        bluetooth)  echo "Bluetooth output — assuming headphones/earbuds" ;;
        speakers)   echo "speakers detected — crossfeed tunes for headphones, bass still works" ;;
        hdmi)       echo "HDMI/display output — immersion is tuned for headphone listening" ;;
        *)          echo "output could not be detected" ;;
    esac
}

# ============================================================
#  Test signal (A/B check)
# ============================================================
_imm_test_signal() {
    command -v ffmpeg &>/dev/null || return 1
    mkdir -p "$IMM_RUN_DIR"
    local out="$IMM_RUN_DIR/test-signal.wav"
    local fade="afade=t=in:d=0.05,afade=t=out:st=3.95:d=0.05"
    ffmpeg -hide_banner -v error -y \
        -f lavfi -i "anoisesrc=color=pink:amplitude=0.20:duration=4:sample_rate=48000" \
        -f lavfi -i "aevalsrc=exprs=0.28*sin(2*PI*1000*t)|0:s=48000:c=stereo:d=4" \
        -f lavfi -i "aevalsrc=exprs=0|0.28*sin(2*PI*1000*t):s=48000:c=stereo:d=4" \
        -f lavfi -i "aevalsrc=exprs=0.32*sin(2*PI*45*t)|0.32*sin(2*PI*45*t):s=48000:c=stereo:d=4" \
        -filter_complex "[0:a]aformat=channel_layouts=stereo,$fade[a0];[1:a]$fade[a1];[2:a]$fade[a2];[3:a]$fade[a3];[a0][a1][a2][a3]concat=n=4:v=0:a=1[out]" \
        -map "[out]" "$out" &>/dev/null || return 1
    echo "$out"
}

# ============================================================
#  snowfox immersion — status
# ============================================================
_imm_cmd_status() {
    _imm_init
    header "Immersion Mode"

    local en prof
    en="$(_imm_enabled)"
    prof="$(_imm_get IMMERSION_PROFILE brain)"

    section "State"
    bool_row "Mode" "$en" "ON" "OFF"
    row "Profile" "$prof  —  $(_imm_profile_desc "$prof")"

    section "Signal Path"
    local cf bass vb width space trim
    cf="$(_imm_get IMMERSION_CROSSFEED 0)"
    bass="$(_imm_get IMMERSION_BASS 6)"
    vb="$(_imm_get IMMERSION_VB 0)"
    width="$(_imm_get IMMERSION_WIDTH 1.10)"
    space="$(_imm_get IMMERSION_SPACE 1.50)"
    trim="$(_imm_get IMMERSION_TRIM -3.5)"

    if _imm_gt "$bass" 0; then
        row "Bass (body)" "low shelf  ${bass} dB @ 55 Hz" "$GREEN"
    else
        row "Bass (body)" "off"
    fi
    if _imm_gt "$vb" 0; then
        row "Virtual bass" "strength ${vb} · cutoff 140 Hz" "$GREEN"
    else
        row "Virtual bass" "off"
    fi
    if _imm_gt "$space" 1.0; then
        row "Super stereo" "side gain ${space} · inside your head" "$GREEN"
    else
        row "Super stereo" "off"
    fi
    if _imm_gt "$width" 1.0; then
        row "Stereo width" "Haas hybrid, side gain ${width}" "$GREEN"
    else
        row "Stereo width" "off"
    fi
    if _imm_gt "$cf" 0; then
        row "Crossfeed" "strength ${cf} · range 0.5" "$GREEN"
    else
        row "Crossfeed" "off"
    fi
    row "Limiter" "lookahead, 0.97 ceiling" "$GREEN"
    row "Level trim" "${trim} dB · headroom (keeps the limiter transparent)"

    section "Brain Layer (binaural beats)"
    if [[ "$(_imm_beats_on)" == "true" ]]; then
        local l r beat
        read -r l r <<< "$(_imm_beat_freqs)"
        beat="$(_imm_get IMMERSION_BEAT 10)"
        row "Beats" "on — ${beat} Hz difference" "$GREEN"
        row "Carrier" "${l} Hz left · ${r} Hz right"
        row "Level" "amplitude $(_imm_get IMMERSION_BEAT_VOL 0.04)"
    else
        row "Beats" "off"
    fi

    section "Playback"
    row "Applies to" "snowfox music · snowfox stream · snowfox immersion test"
    if _imm_beats_running; then
        row "Beat layer" "running (pid $(_imm_beats_pid))" "$GREEN"
    else
        row "Beat layer" "idle"
    fi
    if _imm_mpv_include_enabled; then
        row "mpv-wide DSP" "enabled  (via $IMM_MPV_INCLUDE)" "$GREEN"
    else
        row "mpv-wide DSP" "disabled  —  snowfox immersion mpv on"
    fi

    section "Output"
    local otype
    otype="$(_imm_output_type)"
    if [[ "$otype" == "headphones" || "$otype" == "bluetooth" ]]; then
        row "Device" "$otype" "$GREEN"
    else
        row "Device" "$otype"
    fi
    hint "$(_imm_output_hint)"

    echo ""
    info "Commands: snowfox immersion <on|off|toggle|profile|tune|beats|test|mpv|doctor|about>"
    echo ""
}

# ============================================================
#  snowfox immersion on/off/toggle
# ============================================================
_imm_cmd_on() {
    _imm_init

    if ! command -v mpv &>/dev/null; then
        err "mpv not found. Install: sudo apt install mpv"
        exit 1
    fi

    if [[ -n "${1:-}" ]]; then
        if ! _imm_profile_apply "$1"; then
            err "Unknown profile: $1"
            info "  Profiles: head · body · mind · brain · total"
            exit 1
        fi
    fi

    fox "Checking the signal path …"
    if ! immersion_validate; then
        err "The DSP chain failed on this system — immersion stays OFF."
        info "  Diagnostics: snowfox immersion doctor"
        _imm_set IMMERSION_ENABLED false
        exit 1
    fi

    if [[ "$(_imm_beats_on)" == "true" ]]; then
        if ! _imm_validate_beats; then
            warn "The binaural beat generator failed — disabling the brain layer."
            _imm_set IMMERSION_BEATS false
        fi
    fi

    _imm_set IMMERSION_ENABLED true
    _imm_sync_all

    echo ""
    ok "Immersion mode ON — profile: $(_imm_get IMMERSION_PROFILE brain)"
    row "Chain" "$(_imm_describe_chain)"
    local otype
    otype="$(_imm_output_type)"
    if [[ "$(_imm_beats_on)" == "true" && "$otype" != "headphones" && "$otype" != "bluetooth" ]]; then
        warn "Beats are for headphones — output looks like: $otype"
    fi
    info "Applies to the next tracks you start (snowfox music / snowfox stream)."
    if [[ "$(_imm_beats_on)" == "true" ]]; then
        info "The brain layer starts and stops with your playback."
    fi
    info "Best: wear headphones, then run  snowfox immersion test"
    echo ""
}

_imm_cmd_off() {
    _imm_init
    _imm_set IMMERSION_ENABLED false
    _imm_beats_stop
    ok "Immersion mode OFF — raw signal restored."
    if _imm_mpv_include_enabled; then
        info "  Note: mpv-wide DSP is still active — disable: snowfox immersion mpv off"
    fi
}

_imm_cmd_toggle() {
    if [[ "$(_imm_enabled)" == "true" ]]; then
        _imm_cmd_off
    else
        _imm_cmd_on "${1:-}"
    fi
}

immersion_quick_toggle() {
    # Used by the music TUI — echoes the new state (on|off|error)
    if [[ "$(_imm_enabled)" == "true" ]]; then
        _imm_set IMMERSION_ENABLED false
        _imm_beats_stop
        echo "off"
    else
        if ! immersion_validate; then
            echo "error"
            return 1
        fi
        _imm_set IMMERSION_ENABLED true
        echo "on"
    fi
}

_imm_describe_chain() {
    local af
    af="$(_imm_chain_af)"
    [[ -z "$af" ]] && { echo "empty (all filters off)"; return; }
    echo "$af"
}

# ============================================================
#  snowfox immersion profiles / profile
# ============================================================
_imm_cmd_profiles() {
    header "Immersion Profiles"
    local p
    for p in head body mind brain total; do
        if [[ "$p" == "$(_imm_get IMMERSION_PROFILE brain)" ]]; then
            row "$p" "$(_imm_profile_desc "$p")" "$GREEN"
        else
            row "$p" "$(_imm_profile_desc "$p")"
        fi
    done
    echo ""
    info "Select: snowfox immersion profile <name>   ·   or: snowfox immersion on <name>"
    echo ""
}

_imm_cmd_profile() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        _imm_cmd_profiles
        return
    fi
    if ! _imm_profile_apply "$name"; then
        err "Unknown profile: $name"
        info "  Profiles: head · body · mind · brain · total"
        exit 1
    fi
    _imm_sync_all
    ok "Profile: $(_imm_get IMMERSION_PROFILE brain) — $(_imm_profile_desc "$(_imm_get IMMERSION_PROFILE brain)")"
    if [[ "$(_imm_enabled)" != "true" ]]; then
        info "  Enabled? snowfox immersion on"
    fi
}

# ============================================================
#  snowfox immersion tune
# ============================================================
_imm_band_hz() {
    case "$1" in
        delta) echo 2.5  ;;
        theta) echo 6    ;;
        alpha) echo 10   ;;
        smr)   echo 13.5 ;;
        beta)  echo 18   ;;
        gamma) echo 40   ;;
        *)     echo ""   ;;
    esac
}

_imm_cmd_tune() {
    local key="${1:-}" val="${2:-}"
    if [[ -z "$key" || -z "$val" ]]; then
        header "Tune Immersion"
        row "crossfeed" "0 – 1        headphone stage strength"
        row "bass"      "0 – 12 dB    low shelf (0 = off)"
        row "vb"        "0 / 0.5 – 3  psychoacoustic bass · higher = stronger"
        row "space"     "1 – 2        super stereo · inside your head (1 = off)"
        row "trim"      "-12 – +6 dB  headroom (lower = more limiter space)"
        row "width"     "1 – 1.6      stereo width (1 = off)"
        row "beats"     "on|off|band|Hz   binaural layer"
        row "carrier"   "40 – 500 Hz  binaural carrier tone"
        row "beatvol"   "0.005 – 0.3  binaural level"
        echo ""
        info "Example: snowfox immersion tune beatvol 0.04"
        info "Bands: delta 2.5 · theta 6 · alpha 10 · smr 13.5 · beta 18 · gamma 40 Hz"
        echo ""
        return
    fi

    case "$key" in
        crossfeed)
            _imm_is_num "$val" 0 1 || { err "crossfeed must be 0 – 1"; exit 1; }
            _imm_set IMMERSION_CROSSFEED "$val" ;;
        bass)
            _imm_is_num "$val" 0 12 || { err "bass must be 0 – 12 dB"; exit 1; }
            _imm_set IMMERSION_BASS "$val" ;;
        vb)
            if ! _imm_is_num "$val" 0 3 || \
               ! LC_ALL=C awk -v v="$val" 'BEGIN { exit !(v == 0 || v >= 0.5) }'; then
                err "vb must be 0 (off) or 0.5 – 3 (higher = stronger)"
                exit 1
            fi
            _imm_set IMMERSION_VB "$val" ;;
        width)
            _imm_is_num "$val" 1 1.6 || { err "width must be 1 – 1.6"; exit 1; }
            _imm_set IMMERSION_WIDTH "$val" ;;
        space)
            _imm_is_num "$val" 1 2 || { err "space must be 1 – 2"; exit 1; }
            _imm_set IMMERSION_SPACE "$val" ;;
        trim)
            if ! [[ "$val" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || \
               ! LC_ALL=C awk -v v="$val" 'BEGIN { exit !(v >= -12 && v <= 6) }'; then
                err "trim must be -12 – +6 dB"
                exit 1
            fi
            _imm_set IMMERSION_TRIM "$val" ;;
        beats)
            case "$val" in
                on|true|yes)   _imm_set IMMERSION_BEATS true ;;
                off|false|no)  _imm_set IMMERSION_BEATS false ;;
                *)
                    local hz=""
                    hz="$(_imm_band_hz "$val")"
                    [[ -z "$hz" ]] && hz="$val"
                    _imm_is_num "$hz" 0.5 40 || {
                        err "beats: use on|off, a band (delta|theta|alpha|beta|gamma) or 0.5 – 40 Hz"
                        exit 1
                    }
                    _imm_set IMMERSION_BEAT "$hz"
                    _imm_set IMMERSION_BEATS true
                    ;;
            esac ;;
        carrier)
            _imm_is_num "$val" 40 500 || { err "carrier must be 40 – 500 Hz"; exit 1; }
            _imm_set IMMERSION_CARRIER "$val" ;;
        beatvol)
            _imm_is_num "$val" 0.005 0.3 || { err "beatvol must be 0.005 – 0.3"; exit 1; }
            _imm_set IMMERSION_BEAT_VOL "$val" ;;
        *)
            err "Unknown key: $key"
            info "  Keys: crossfeed · bass · vb · space · trim · width · beats · carrier · beatvol"
            exit 1 ;;
    esac

    _imm_sync_all
    ok "Immersion: $key = $val"

    # live layers pick the change up immediately
    if _imm_beats_running; then
        local mode="manual"
        [[ -f "$IMM_MODE_FILE" ]] && mode="$(cat "$IMM_MODE_FILE")"
        _imm_beats_stop
        if [[ "$(_imm_beats_on)" == "true" ]]; then
            _imm_beats_start "$mode"
            info "  Beat layer restarted with the new setting."
        fi
    fi
}

_imm_sync_all() {
    # Keep generated artifacts in sync with the config
    _imm_mpv_include_sync
}

# ============================================================
#  snowfox immersion show
# ============================================================
_imm_cmd_show() {
    _imm_init
    header "Immersion — Signal Path"

    section "mpv arguments (snowfox music · snowfox stream)"
    local af
    af="$(_imm_chain_af)"
    if [[ -z "$af" ]]; then
        info "  (empty — every filter is off)"
    else
        echo -e "  ${CYAN}--af=lavfi=[${RESET}"
        echo -e "  ${CYAN}  ${af}${RESET}"
        echo -e "  ${CYAN}]${RESET}"
    fi

    section "Binaural beat generator"
    if [[ "$(_imm_beats_on)" == "true" ]]; then
        local l r
        read -r l r <<< "$(_imm_beat_freqs)"
        echo -e "  ${CYAN}${l} Hz → left ear   ·   ${r} Hz → right ear${RESET}"
        echo -e "  ${DGRAY}beat difference: $(_imm_get IMMERSION_BEAT 10) Hz${RESET}"
        echo -e "  ${DGRAY}$(_imm_beats_graph)${RESET}"
    else
        info "  (brain layer off)"
    fi

    section "Manual playback"
    if [[ -n "$af" ]]; then
        echo -e "  ${DGRAY}mpv --af=\"lavfi=[$af]\" <file or URL>${RESET}"
    fi
    echo -e "  ${DGRAY}Config: ${IMM_FILE}${RESET}"

    if _imm_mpv_include_enabled; then
        echo ""
        info "mpv-wide DSP is active via: $IMM_MPV_INCLUDE"
    fi
    echo ""
}

# ============================================================
#  snowfox immersion beats — manual brain layer
# ============================================================
_imm_cmd_beats() {
    local action="${1:-status}"
    case "$action" in
        on|start)
            if [[ "$(_imm_beats_on)" != "true" ]]; then
                err "Binaural beats are disabled for the current profile."
                info "  Enable: snowfox immersion tune beats on"
                exit 1
            fi
            if [[ "$(_imm_enabled)" != "true" ]]; then
                # the brain layer is part of immersion mode
                _imm_cmd_on
                echo ""
            fi
            if _imm_beats_start manual; then
                ok "Beat layer running — it mixes over every player (browser, music, video)."
                info "  Stop: snowfox immersion beats off"
            else
                err "Could not start the beat generator."
                exit 1
            fi ;;
        off|stop)
            _imm_beats_stop
            ok "Beat layer stopped." ;;
        status|"")
            if _imm_beats_running; then
                local mode="manual"
                [[ -f "$IMM_MODE_FILE" ]] && mode="$(cat "$IMM_MODE_FILE")"
                bool_row "Beat layer" true "running ($mode, pid $(_imm_beats_pid))" ""
            else
                bool_row "Beat layer" false "stopped" ""
            fi
            info "  Start: snowfox immersion beats on   ·   Stop: snowfox immersion beats off" ;;
        *)
            err "Usage: snowfox immersion beats <on|off|status>"
            exit 1 ;;
    esac
}

# ============================================================
#  snowfox immersion mpv — mpv-wide DSP (opt-in)
# ============================================================
_imm_cmd_mpv() {
    local action="${1:-status}"
    case "$action" in
        on)
            if ! command -v mpv &>/dev/null; then
                err "mpv not found. Install: sudo apt install mpv"
                exit 1
            fi
            _imm_mpv_include_write
            if ! timeout 15 mpv --no-config --no-video --ao=null --really-quiet --length=0.3 \
                    --include="$IMM_MPV_INCLUDE" \
                    'av://lavfi:sine=frequency=440:duration=0.3' &>/dev/null; then
                err "The chain failed — mpv-wide DSP not enabled."
                rm -f "$IMM_MPV_INCLUDE"
                exit 1
            fi
            _imm_mpv_include_add
            ok "mpv-wide DSP enabled — every mpv playback now uses the immersion chain."
            info "  File: $IMM_MPV_INCLUDE"
            [[ -f "$IMM_MPV_CONF.snowfox-backup" ]] && info "  Backup: $IMM_MPV_CONF.snowfox-backup"
            info "  Note: the brain layer is not part of this file (video files without audio)."
            ;;
        off)
            _imm_mpv_include_remove
            ok "mpv-wide DSP disabled." ;;
        status|"")
            if _imm_mpv_include_enabled; then
                bool_row "mpv-wide DSP" true "enabled"
                row "Include" "$IMM_MPV_INCLUDE"
                if [[ -f "$IMM_MPV_INCLUDE" ]]; then
                    hint "$(grep -m1 '^af=' "$IMM_MPV_INCLUDE" 2>/dev/null || echo 'no active filters')"
                fi
            else
                bool_row "mpv-wide DSP" false "disabled"
            fi ;;
        *)
            err "Usage: snowfox immersion mpv <on|off|status>"
            exit 1 ;;
    esac
}

# ============================================================
#  snowfox immersion test — A/B check
# ============================================================
_imm_cmd_test() {
    local raw=false
    [[ "${1:-}" == "raw" || "${1:-}" == "--raw" ]] && raw=true

    command -v mpv &>/dev/null || { err "mpv not found. Install: sudo apt install mpv"; exit 1; }
    command -v ffmpeg &>/dev/null || { err "ffmpeg not found. Install: sudo apt install ffmpeg"; exit 1; }

    local file
    file="$(_imm_test_signal)" || { err "Could not generate the test signal."; exit 1; }

    header "Immersion Test Signal"
    echo -e "  ${DGRAY}16 seconds · four segments of 4 s${RESET}"
    echo ""
    echo -e "  ${CYAN}1${RESET})  Pink noise          — overall warmth"
    echo -e "  ${CYAN}2${RESET})  1 kHz hard left     — crossfeed: should not be 100% left"
    echo -e "  ${CYAN}3${RESET})  1 kHz hard right    — crossfeed: should not be 100% right"
    echo -e "  ${CYAN}4${RESET})  45 Hz bass tone     — body: feel it, not only hear it"
    echo ""

    local -a args=()
    if $raw; then
        warn "RAW mode — no immersion processing (for A/B comparison)."
    else
        if [[ "$(_imm_enabled)" == "true" ]]; then
            ok "Playing through immersion mode, profile: $(_imm_get IMMERSION_PROFILE brain)"
        else
            warn "Immersion mode is OFF — playing the configured chain for this test anyway."
        fi
        _imm_build_mpv_args
        args=("${IMM_MPV_ARGS[@]}")
        if [[ "$(_imm_beats_on)" == "true" ]]; then
            info "  Brain layer included: $(_imm_get IMMERSION_BEAT 10) Hz beat"
        fi
    fi

    local -a ao=()
    [[ -n "$IMM_AO" ]] && ao+=(--ao="$IMM_AO")

    echo ""
    fox "Listen closely — [q] quits"
    # The test deliberately works even when the mode itself is off,
    # so the chain can be auditioned before committing to it.
    if ! $raw && [[ "$(_imm_beats_on)" == "true" ]]; then
        _imm_beats_start auto
    fi
    mpv --no-config --no-video --audio-display=no --really-quiet \
        ${ao[@]+"${ao[@]}"} ${args[@]+"${args[@]}"} "$file"
    immersion_beats_session_stop
    echo ""
    ok "Test finished. Compare: snowfox immersion test raw"
    echo ""
}

# ============================================================
#  snowfox immersion about — the science, briefly
# ============================================================
_imm_cmd_about() {
    header "Immersion Mode — Why It Sounds Different"
    # printf %b turns the ${COLOR} variables into real ANSI escapes
    printf '%b\n' "$(cat <<EOF

  ${LPURPLE}${BOLD}1 · Crossfeed — the music leaves your head${RESET}
  ${DGRAY}On headphones the left driver hits only the left ear; your brain
  notices this and places the band inside your skull. Real speakers
  always bleed into both ears. Crossfeed (Bauer / bs2b style) mixes a
  little of L into R and vice versa, delayed and low-passed — the
  stage moves in front of you and long sessions hurt less.
  Want the opposite — music INSIDE the head? Use the 'brain' profile,
  which turns crossfeed off.${RESET}

  ${LPURPLE}${BOLD}2 · Low shelf — the body channel${RESET}
  ${DGRAY}Below ~80 Hz you feel more than you hear. A low shelf lifts that
  region, cleanly and without distortion — chest and gut bass even on
  headphones. The optional virtual bass adds harmonics that the ear
  places back at the missing fundamental; off by default because it
  can sound fuzzy (enable: tune vb 1.5).${RESET}

  ${LPURPLE}${BOLD}3 · Super stereo — the inside-your-head stage${RESET}
  ${DGRAY}The side signal (what the two ears don't share) creates width and
  in-head focus. A clean mid/side matrix raises it: the centre stays
  exactly where it is, the sides press against your ears. This is the
  stage that pins music INSIDE the head.${RESET}
    ${DGRAY}Knob: tune space 1.0 (off) … 2.0 (extreme)${RESET}

  ${LPURPLE}${BOLD}4 · Haas widening — the room${RESET}
  ${DGRAY}A few milliseconds of delay between the channels (side gain)
  widens the stereo image — more space between the instruments,
  without hollowing out the centre.${RESET}

  ${LPURPLE}${BOLD}5 · Binaural beats — the brain channel${RESET}
  ${DGRAY}Each ear receives a pure tone; the difference between them is the
  beat (e.g. 295 Hz left / 305 Hz right = 10 Hz alpha). The beat is
  not in the air — it is created in the brainstem when the two tone
  streams meet. Alpha relates to calm focus.${RESET}
    ${DGRAY}delta 0.5 – 4 Hz  deep sleep   ·  theta 4 – 8 Hz  drifting
    alpha 8 – 12 Hz  calm focus  ·  beta 13 – 30 Hz  alert
    gamma 30+ Hz     high attention${RESET}

  ${LPURPLE}${BOLD}6 · Limiter + trim — the safety net${RESET}
  ${DGRAY}A lookahead limiter catches peaks caused by the boosts, so the
  chain cannot clip. A small headroom trim in front keeps the output
  the same loudness as the raw signal — loud masters stay clean
  instead of pumping into the limiter.${RESET}

  ${PURPLE}${BOLD}Good to know${RESET}
  ${DGRAY}· Beats need headphones — on speakers both ears hear both tones
    and the effect mostly collapses into a flutter.
  · Too hissy? Keep width ≤ 1.15 and space moderate — side boosts
    amplify hiss and lossy artefacts; lowering beatvol helps too.
  · brain is the default profile; push it further with tune space 1.7.
  · Effects are subtle by design: they should survive long
    sessions, not shout at you.
  · Binaural beats are researched but not settled science — they are
    an atmosphere, not a medical treatment.
  · Everything runs locally in mpv/libavfilter: ~0.5 % of one CPU
    core, no network, no re-encoding, no telemetry.${RESET}

  ${DGRAY}Tune it:   snowfox immersion tune <key> <value>
  Compare:  snowfox immersion test   ·   snowfox immersion test raw${RESET}

EOF
)"
}

# ============================================================
#  snowfox immersion doctor / reset / help
# ============================================================
_imm_cmd_reset() {
    _imm_init
    _imm_profile_apply brain || true
    _imm_set IMMERSION_BEAT 10
    _imm_set IMMERSION_CARRIER 300
    _imm_set IMMERSION_BEAT_VOL 0.04
    _imm_sync_all
    ok "Immersion settings back to defaults (profile: brain)."
}

_imm_cmd_doctor() {
    header "Immersion Doctor"
    local ok_count=0 fail_count=0

    section "Requirements"
    if command -v mpv &>/dev/null; then
        ok "mpv found: $(mpv --version 2>/dev/null | head -n1)"
        ((ok_count++))
    else
        err "mpv missing — install: sudo apt install mpv"
        ((fail_count++))
    fi

    if command -v ffmpeg &>/dev/null; then
        ok "ffmpeg found: $(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $1, $3}')"
        ((ok_count++))
    else
        warn "ffmpeg missing — only needed for the test signal"
    fi

    section "Filter chain"
    local af
    af="$(_imm_chain_af)"
    row "Chain" "${af:-empty}"
    if immersion_validate; then
        ok "Chain initializes cleanly."
        ((ok_count++))
    else
        err "Chain failed to initialize on this system."
        ((fail_count++))
        info "  This usually means mpv was built without libavfilter,"
        info "  or the installed FFmpeg lacks: bass, virtualbass, haas, crossfeed, alimiter."
    fi

    if [[ "$(_imm_beats_on)" == "true" ]]; then
        if _imm_validate_beats; then
            ok "Beat generator initializes cleanly."
            ((ok_count++))
        else
            err "Beat generator failed — run: snowfox immersion tune beats off"
            ((fail_count++))
        fi
    else
        info "Beat layer disabled — nothing to check."
    fi

    section "Output & state"
    row "Output device" "$(_imm_output_type)"
    hint "$(_imm_output_hint)"
    bool_row "Mode" "$(_imm_enabled)" "ON" "OFF"
    if _imm_beats_running; then
        row "Beat layer" "running (pid $(_imm_beats_pid))" "$GREEN"
    else
        row "Beat layer" "idle"
    fi
    bool_row "mpv-wide DSP" "$(_imm_mpv_include_enabled && echo true || echo false)" "enabled" "disabled"
    row "Config" "$IMM_FILE"

    echo ""
    divider
    if [[ $fail_count -eq 0 ]]; then
        ok "All checks passed ($ok_count ok)."
    else
        err "$fail_count check(s) failed."
    fi
    echo ""
}

_imm_cmd_help() {
    header "Immersion Mode"
    row "on [profile]"   "enable (validates the chain first)"
    row "off"            "disable · restores the raw signal"
    row "toggle"         "flip the state"
    row "status"         "full state overview"
    row "profile <name>" "head · body · mind · brain · total"
    row "tune <key> <v>" "crossfeed bass vb space trim width beats carrier beatvol"
    row "beats <on|off>" "manual brain layer for any player"
    row "test [raw]"     "16 s A/B test signal"
    row "mpv <on|off>"   "apply the chain to every mpv start (opt-in)"
    row "show"           "print the exact filter chains"
    row "about"          "why it sounds different (the science)"
    row "doctor"         "check dependencies and the graph"
    row "reset"          "back to defaults"
    echo ""
}

# ============================================================
#  Entry point
# ============================================================
cmd_immersion() {
    local sub="${1:-status}"
    case "$sub" in
        ""|status|st)       _imm_cmd_status ;;
        on)                 shift; _imm_cmd_on "$@" ;;
        off)                _imm_cmd_off ;;
        toggle|t)           shift; _imm_cmd_toggle "$@" ;;
        profiles)           _imm_cmd_profiles ;;
        profile)            _imm_cmd_profile "$2" ;;
        tune|set)           shift; _imm_cmd_tune "$@" ;;
        beats|beat)         shift; _imm_cmd_beats "$@" ;;
        show)               _imm_cmd_show ;;
        test)               shift; _imm_cmd_test "$@" ;;
        mpv)                shift; _imm_cmd_mpv "$@" ;;
        reset)              _imm_cmd_reset ;;
        doctor|doc)         _imm_cmd_doctor ;;
        about|why)          _imm_cmd_about ;;
        help|-h|--help)     _imm_cmd_help ;;
        *)
            err "Unknown immersion subcommand: $sub"
            info "  Usage: snowfox immersion <on|off|toggle|status|profile|tune|beats|test|mpv|show|reset|doctor|about>"
            exit 1 ;;
    esac
}
