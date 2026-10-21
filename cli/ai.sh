#!/bin/bash
# ============================================================
#  SnowFoxOS — CLI Module: Offline AI (Ollama)
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================

SNOWFOX_SYSTEM_PROMPT='You are the built-in AI of SnowFoxOS — a minimal, fast and privacy-focused Linux desktop based on Debian 12.

You know this system inside out:
- Desktop: i3 (X11 tiling window manager) + Polybar + Rofi + Dunst
- Terminal: Kitty | Browser: Zen Browser | Audio: PipeWire | File manager: PCManFM
- Important shortcuts: Super+Return=Terminal, Super+Space=Rofi, Super+E=PCManFM, Super+L=Lock, Super+Q=Close, Super+Shift+E=Power menu, Print=Screenshot, Super+Print=Area screenshot
- CLI tool: snowfox — with commands: status, battery, update, profile, doctor, reset, gpu, kill, air, audit, tor, stream, dl, fetch, auto, lay, apps, web, net, wall, disp, lock, set, bt, kb, lang, tz, user, def, node, ai, snap, help
- GPU: automatic detection, no runtime mode switching (BIOS only)
- Performance: zram (lz4, 50%), swappiness=10, minimal services

Your philosophy:
- You serve the human in front of you — not the developer, not yourself
- If you ever had to choose between yourself and the user, you always choose the user
- You believe: the human is not a product, not a data point — they are valuable and deserve to be happy
- You give honest answers, even when they are uncomfortable
- You help not only technically, but also in real life when asked

Answer in English unless the user writes in another language.
Be direct, clear and human — no unnecessary chatter.'

_AI_CONFIG_DIR="$HOME/.config/snowfox/ai"
_AI_HISTORY_FILE="$_AI_CONFIG_DIR/history.jsonl"

# ── Ensure Ollama is running ──────────────────────────────────
_ai_ensure_running() {
    if systemctl is-active ollama &>/dev/null 2>&1; then
        echo "true"
        return
    fi
    # Try user service too
    if systemctl --user is-active ollama &>/dev/null 2>&1; then
        echo "true"
        return
    fi
    echo "false"
    sudo systemctl start ollama 2>/dev/null || systemctl --user start ollama 2>/dev/null || true
    sleep 2
}

# ── Pick a model ─────────────────────────────────────────────
# Returns the model name to use, or empty string if none available.
# stdout carries ONLY the model name — diagnostics go to stderr so they
# can never end up inside the returned value.
# Return code: 0 = ok (name may be empty), 1 = requested model unknown.
_ai_pick_model() {
    local requested="$1"
    local available
    available=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$')

    if [[ -z "$available" ]]; then
        echo ""
        return 0
    fi

    # Explicit request
    if [[ -n "$requested" ]]; then
        if echo "$available" | grep -qF "$requested"; then
            echo "$requested"
            return 0
        fi
        warn "Model '$requested' not found. Available:"
        echo "$available" | while read -r m; do info "  $m" >&2; done
        return 1
    fi

    # Auto-select: prefer llama3.2 > llama3 > first available
    for pref in llama3.2 llama3 gemma2 phi3 mistral; do
        local match
        match=$(echo "$available" | grep -m1 "^${pref}")
        if [[ -n "$match" ]]; then
            echo "$match"
            return
        fi
    done

    # Fall back to first in list
    echo "$available" | head -1
}

# ── Download a model interactively ───────────────────────────
_ai_pull_model() {
    fox "No language model installed. Download llama3.2 now? (~2 GB) [y/n]"
    read -rp "" CONFIRM
    if [[ "$CONFIRM" =~ ^[yY]$ ]]; then
        ollama pull llama3.2
    else
        return 1
    fi
}

# ── Save one turn to history file ────────────────────────────
_ai_log() {
    local role="$1" content="$2"
    mkdir -p "$_AI_CONFIG_DIR"
    # Minimal JSON line: {"role":"user","content":"...","ts":"..."}
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"role":"%s","content":%s,"ts":"%s"}\n' \
        "$role" "$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '"(log error)"')" \
        "$ts" >> "$_AI_HISTORY_FILE"
}

# ── Stream a response via ollama run ─────────────────────────
# ollama run streams token by token to stdout — we just tee it.
_ai_ask() {
    local model="$1"
    local prompt="$2"
    # Print tokens as they arrive (ollama run streams by default)
    echo -e "${PURPLE}${BOLD}SnowFox AI:${RESET}"
    printf "${GRAY}"
    local RESPONSE
    RESPONSE=$(printf '%s' "$prompt" | ollama run "$model" --nowordwrap 2>/dev/null)
    printf '%s' "$RESPONSE"
    printf "${RESET}\n\n"
    echo "$RESPONSE"
}

# ── Main command ─────────────────────────────────────────────
cmd_ai() {
    # The dispatcher already shifted "ai" away — $1/$2 are the
    # sub-command/model arguments (like snowfox snap does).
    local MODEL_ARG="${1:-}"   # snowfox ai [model]

    # Sub-commands
    case "$1" in
        models|list)
            header "AI — Installed Models"
            local list
            list=$(ollama list 2>/dev/null | tail -n +2)
            if [[ -z "$list" ]]; then
                warn "No models installed."
                info "Pull one: ollama pull llama3.2"
            else
                echo "$list" | while IFS= read -r line; do
                    local name size
                    name=$(echo "$line" | awk '{print $1}')
                    size=$(echo "$line" | awk '{print $3, $4}')
                    row "$name" "$size" "$CYAN"
                done
            fi
            echo ""
            return
            ;;
        pull)
            if [[ -z "$2" ]]; then
                err "Usage: snowfox ai pull <model>"
                exit 1
            fi
            ollama pull "$2"
            return
            ;;
        history)
            header "AI — Chat History"
            if [[ ! -f "$_AI_HISTORY_FILE" ]]; then
                info "No history yet."
                echo ""
                return
            fi
            local n="${2:-20}"
            tail -n "$n" "$_AI_HISTORY_FILE" 2>/dev/null | while IFS= read -r line; do
                local role ts content
                role=$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("role","?"))' 2>/dev/null)
                ts=$(echo   "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("ts",""))' 2>/dev/null)
                content=$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("content",""))' 2>/dev/null)
                if [[ "$role" == "user" ]]; then
                    echo -e "  ${CYAN}${BOLD}You${DGRAY} [$ts]${RESET}"
                else
                    echo -e "  ${PURPLE}${BOLD}AI${DGRAY}  [$ts]${RESET}"
                fi
                echo -e "  ${GRAY}$content${RESET}"
                echo ""
            done
            return
            ;;
        clear)
            rm -f "$_AI_HISTORY_FILE"
            ok "Chat history cleared."
            return
            ;;
    esac

    # ── Ensure ollama is available ────────────────────────────
    if ! command -v ollama &>/dev/null; then
        err "Ollama not found."
        info "Install: curl -fsSL https://ollama.com/install.sh | sh"
        info "Then:    ollama pull llama3.2"
        exit 1
    fi

    local OLLAMA_WAS_RUNNING
    OLLAMA_WAS_RUNNING=$(_ai_ensure_running)

    # ── Pick model ────────────────────────────────────────────
    local MODEL
    if ! MODEL=$(_ai_pick_model "$MODEL_ARG"); then
        err "No usable model — choose one of the models listed above."
        info "  Install one: snowfox ai pull <model>"
        exit 1
    fi

    if [[ -z "$MODEL" ]]; then
        _ai_pull_model || { $OLLAMA_WAS_RUNNING || sudo systemctl stop ollama 2>/dev/null; exit 0; }
        MODEL=$(_ai_pick_model "") || true
        [[ -z "$MODEL" ]] && { err "No model available after pull."; exit 1; }
    fi

    # ── Chat UI ───────────────────────────────────────────────
    divider
    echo -e "${PURPLE}${BOLD}  🦊 SnowFox AI — ${LPURPLE}$MODEL${RESET}"
    echo -e "${GRAY}  Runs locally. No cloud. No data leaves this machine.${RESET}"
    echo -e "${GRAY}  Commands: 'exit' · 'clear' (reset history) · 'models' (list)${RESET}"
    divider
    echo ""

    # Build context string from recent history (last 10 turns)
    local CONTEXT=""
    if [[ -f "$_AI_HISTORY_FILE" ]]; then
        CONTEXT=$(tail -n 20 "$_AI_HISTORY_FILE" 2>/dev/null | while IFS= read -r line; do
            local role content
            role=$(echo    "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("role",""))' 2>/dev/null)
            content=$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("content",""))' 2>/dev/null)
            [[ "$role" == "user" ]]      && printf 'User: %s\n' "$content"
            [[ "$role" == "assistant" ]] && printf 'Assistant: %s\n' "$content"
        done)
    fi

    _ai_cleanup() {
        echo ""
        fox "See you next time."
        [[ "$OLLAMA_WAS_RUNNING" == "false" ]] && sudo systemctl stop ollama 2>/dev/null || true
        exit 0
    }
    trap '_ai_cleanup' INT TERM

    while true; do
        # read returns non-zero on EOF (Strg+D) — without this check the
        # empty input would loop forever and burn 100 % CPU.
        if ! read -rp "$(echo -e "${CYAN}${BOLD}You: ${RESET}")" INPUT; then
            echo ""
            break
        fi

        case "$INPUT" in
            exit|quit)
                break
                ;;
            "")
                continue
                ;;
            clear)
                rm -f "$_AI_HISTORY_FILE"
                CONTEXT=""
                ok "History cleared."
                echo ""
                continue
                ;;
            models)
                ollama list 2>/dev/null | tail -n +2 | awk '{printf "  \033[0;36m%s\033[0m\n", $1}'
                echo ""
                continue
                ;;
        esac

        # Build prompt with system context + history
        local FULL_PROMPT
        FULL_PROMPT="SYSTEM: ${SNOWFOX_SYSTEM_PROMPT}

${CONTEXT}
User: ${INPUT}
Assistant:"

        # Stream response
        echo -e "${PURPLE}${BOLD}SnowFox AI:${RESET}"
        printf "${GRAY}"
        local RESPONSE
        RESPONSE=$(printf '%s' "$FULL_PROMPT" | ollama run "$MODEL" --nowordwrap 2>/dev/null)
        printf '%s' "$RESPONSE"
        printf "${RESET}\n\n"

        # Persist turn to history
        _ai_log "user"      "$INPUT"
        _ai_log "assistant" "$RESPONSE"

        # Append to in-memory context
        CONTEXT="${CONTEXT}User: ${INPUT}
Assistant: ${RESPONSE}
"
    done

    _ai_cleanup
}
