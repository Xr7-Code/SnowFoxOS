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
_ai_pick_model() {
    local requested="$1"
    local available
    available=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$')

    if [[ -z "$available" ]]; then
        echo ""
        return
    fi

    # Explicit request
    if [[ -n "$requested" ]]; then
        if echo "$available" | grep -qF "$requested"; then
            echo "$requested"
            return
        fi
        warn "Model '$requested' not found. Available:"
        echo "$available" | while read -r m; do info "  $m"; done
        echo ""
        return
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
    if ! sf_yesno "No language model installed — download llama3.2 now? (~2 GB)" "Download" "Cancel" no; then
        return 1
    fi

    if sf_can_tui; then
        local log
        log=$(mktemp)
        if sf_spin_do "Pulling llama3.2…" _ai_pull_run "$log" llama3.2; then
            ok "Model llama3.2 downloaded."
        else
            err "Download failed."
            tail -n 5 "$log" 2>/dev/null
        fi
        rm -f "$log"
    else
        ollama pull llama3.2
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

# ── Reports (used by the TUI pager) ──────────────────────────
_ai_models_report() {
    local list
    list=$(ollama list 2>/dev/null | tail -n +2)

    echo "Installed models"
    echo "──────────────────────────────────────────────────"
    echo ""
    if [[ -z "$list" ]]; then
        echo "  No models installed."
        echo ""
        echo "  Pull one: snowfox ai pull llama3.2"
    else
        local name size
        echo "$list" | while IFS= read -r line; do
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $3, $4}')
            printf '  %-28s %s\n' "$name" "$size"
        done
    fi
    echo ""
}

_ai_history_report() {
    local n="${1:-20}"
    if [[ ! -f "$_AI_HISTORY_FILE" ]]; then
        echo "No history yet."
        return
    fi
    tail -n "$n" "$_AI_HISTORY_FILE" 2>/dev/null | while IFS= read -r line; do
        local role ts content
        role=$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("role","?"))' 2>/dev/null)
        ts=$(echo   "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("ts",""))' 2>/dev/null)
        content=$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("content",""))' 2>/dev/null)
        if [[ "$role" == "user" ]]; then
            echo "You  [$ts]"
        else
            echo "AI   [$ts]"
        fi
        echo "  $content"
        echo ""
    done
}

_ai_pull_run() {
    ollama pull "$1"
}

# ── Chat session (shared by classic mode + TUI) ──────────────
_ai_chat_session() {
    local MODEL_ARG="${1:-}"

    # ── Ensure ollama is available ────────────────────────────
    if ! command -v ollama &>/dev/null; then
        err "Ollama not found."
        info "Install: curl -fsSL https://ollama.com/install.sh | sh"
        info "Then:    ollama pull llama3.2"
        return 1
    fi

    local OLLAMA_WAS_RUNNING
    OLLAMA_WAS_RUNNING=$(_ai_ensure_running)

    # ── Pick model ────────────────────────────────────────────
    local MODEL
    MODEL=$(_ai_pick_model "$MODEL_ARG")

    if [[ -z "$MODEL" ]]; then
        if ! _ai_pull_model; then
            [[ "$OLLAMA_WAS_RUNNING" == "false" ]] && sudo systemctl stop ollama 2>/dev/null
            return 0
        fi
        MODEL=$(_ai_pick_model "")
        if [[ -z "$MODEL" ]]; then
            err "No model available after pull."
            return 1
        fi
    fi

    # ── Chat UI ───────────────────────────────────────────────
    if sf_can_tui; then
        sf_banner "SnowFox AI"
        sf_note "$MODEL · runs locally · no cloud — commands: exit, clear, models"
    else
        divider
        echo -e "${PURPLE}${BOLD}  🦊 SnowFox AI — ${LPURPLE}$MODEL${RESET}"
        echo -e "${GRAY}  Runs locally. No cloud. No data leaves this machine.${RESET}"
        echo -e "${GRAY}  Commands: 'exit' · 'clear' (reset history) · 'models' (list)${RESET}"
        divider
        echo ""
    fi

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

    local _ai_halt=0
    trap '_ai_halt=1' INT TERM

    local INPUT st
    while true; do
        [[ "$_ai_halt" == 1 ]] && break

        if sf_can_tui; then
            INPUT=$(sf_input "You → SnowFox AI" "Ask anything — 'exit' to quit")
            st=$?
            [[ $st -ne 0 ]] && break
        else
            read -rp "$(echo -e "${CYAN}${BOLD}You: ${RESET}")" INPUT || break
        fi

        case "$INPUT" in
            exit|quit) break ;;
            "")        continue ;;
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

    trap - INT TERM
    [[ "$OLLAMA_WAS_RUNNING" == "false" ]] && sudo systemctl stop ollama 2>/dev/null
    if ! sf_can_tui; then
        echo ""
        fox "See you next time."
    fi
    return 0
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
                return 1
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
            _ai_history_report "$n"
            return
            ;;
        clear)
            rm -f "$_AI_HISTORY_FILE"
            ok "Chat history cleared."
            return
            ;;
        chat)
            MODEL_ARG="$2"
            ;;
        "")
            if sf_can_tui; then
                _ai_tui
                return
            fi
            ;;
        *)
            MODEL_ARG="$1"
            ;;
    esac

    _ai_chat_session "$MODEL_ARG"
}

# ============================================================
#  Gum TUI — SnowFox AI
# ============================================================
_ai_tui() {
    while true; do
        sf_banner "SnowFox AI"
        sf_note "Local Ollama · no cloud · no data leaves this machine"

        local choice st
        choice=$(sf_choose "SnowFox AI" 9 \
            "💬  Start chat" \
            "📋  Installed models" \
            "⬇️   Pull a model" \
            "🕘  Recent history" \
            "🗑️   Clear history" \
            "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$choice" || "$choice" == *Back* ]] && return 0

        case "$choice" in
            *"Start chat"*) _ai_tui_chat ;;
            *Installed*)    _ai_tui_models ;;
            *Pull*)         _ai_tui_pull ;;
            *History*)      _ai_tui_history ;;
            *Clear*)        _ai_tui_clear ;;
        esac
    done
}

_ai_tui_chat() {
    local -a models=()
    local m
    while IFS= read -r m; do
        [[ -n "$m" ]] && models+=("$m")
    done < <(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$')

    local model=""
    if [[ ${#models[@]} -gt 0 ]]; then
        local sel st
        sel=$(sf_choose "Which model?" 12 "🤖  Auto (recommended)" "${models[@]}" "↩   Back")
        st=$?
        [[ $st -ne 0 || -z "$sel" || "$sel" == *Back* ]] && return 0
        [[ "$sel" != *Auto* ]] && model="$sel"
    fi

    _ai_chat_session "$model"
    sf_pause "Press Enter to return to the AI menu…"
}

_ai_tui_models() {
    local tmp
    tmp=$(mktemp)
    _ai_models_report > "$tmp"
    sf_page "AI — Installed Models" "$tmp"
    rm -f "$tmp"
}

_ai_tui_pull() {
    local model
    model=$(sf_ask_ph "Model to pull" "e.g. llama3.2, gemma2, phi3")
    [[ -z "$model" ]] && return 0

    sf_yesno "Download model '$model'?" "Download" "Cancel" yes || return 0

    local log
    log=$(mktemp)
    if sf_spin_do "Pulling '$model'… this can take a while" _ai_pull_run "$log" "$model"; then
        ok "Model '$model' downloaded."
    else
        err "Pull failed."
        tail -n 5 "$log" 2>/dev/null | while IFS= read -r l; do info "  $l"; done
    fi
    rm -f "$log"
    sf_pause
}

_ai_tui_history() {
    local tmp
    tmp=$(mktemp)
    _ai_history_report 30 > "$tmp"
    sf_page "AI — Chat History" "$tmp"
    rm -f "$tmp"
}

_ai_tui_clear() {
    if [[ ! -f "$_AI_HISTORY_FILE" ]]; then
        ok "No history to clear."
        sleep 1
        return 0
    fi
    if sf_yesno "Delete the whole chat history?" "Delete" "Cancel" no; then
        rm -f "$_AI_HISTORY_FILE"
        ok "Chat history cleared."
        sleep 1
    fi
}
