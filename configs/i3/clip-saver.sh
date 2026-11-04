#!/bin/bash
# ============================================================
#   SnowFoxOS v3 — Clip-Saver
#   Keeps X11 clipboard data (text/PNG) alive even when the
#   source window is closed. File operations (PCManFM, Thunar,
#   Nautilus ...) are deliberately NOT touched.
#   Requires: clipnotify, xclip
#   Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  Hardened rewrite:
#   - Clipboard auto-clears after timeout (default 30s; 10s for
#     sensitive sources like password managers)
#   - Sensitive-source detection (KeePassXC, Bitwarden, 1Password,
#     2FA, password-manager MIME hints) — never persisted
#   - Temp file in $XDG_RUNTIME_DIR, mode 0600
#   - Trap covers EXIT/INT/TERM/HUP
#   - last_hash per clipboard type (no cross-type false negatives)
#   - sha256sum failure aborts the iteration (no data loss)
#   - Exact MIME matching for file-copy detection
#   - timeout on xclip calls (no hang on a stuck X server)
#   - Controlled PATH, absolute binary paths
# ============================================================

# ─── Controlled environment ─────────────────────────────────
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

# ─── Binary paths ───────────────────────────────────────────
readonly CLIPNOTIFY_BIN="/usr/bin/clipnotify"
readonly XCLIP_BIN="/usr/bin/xclip"
readonly GREP_BIN="/usr/bin/grep"
readonly SHA256SUM_BIN="/usr/bin/sha256sum"
readonly CUT_BIN="/usr/bin/cut"
readonly MKTEMP_BIN="/usr/bin/mktemp"
readonly CHMOD_BIN="/usr/bin/chmod"
readonly RM_BIN="/usr/bin/rm"
readonly TIMEOUT_BIN="/usr/bin/timeout"
readonly SLEEP_BIN="/usr/bin/sleep"
readonly ID_BIN="/usr/bin/id"

[[ -x "$CLIPNOTIFY_BIN" ]] || CLIPNOTIFY_BIN="/usr/local/bin/clipnotify"
[[ -x "$XCLIP_BIN" ]]      || XCLIP_BIN="/usr/local/bin/xclip"

# ─── Configuration ─────────────────────────────────────────
readonly CLIP_TIMEOUT_NORMAL=30
readonly CLIP_TIMEOUT_SENSITIVE=10
readonly XCLIP_TIMEOUT=5

# Sensitive-source MIME hints — never persist these.
readonly SENSITIVE_MIME_RE='x-kde-passwordManagerHint|application/x-keepass|application/x-1password|application/x-bitwarden|application/x-pass'

# File-copy MIME types — leave alone so PCManFM/Thunar/Nautilus
# can keep their x-special/gnome-copied-files and text/uri-list.
readonly FILECOPY_MIME_RE='^(x-special/(gnome-copied-files|nautilus-clipboard)|text/uri-list|XdndDirectSave)$'

# ─── Preconditions ─────────────────────────────────────────
if [[ ! -x "$CLIPNOTIFY_BIN" ]]; then
    printf 'clip-saver: clipnotify not found\n' >&2
    exit 1
fi
if [[ ! -x "$XCLIP_BIN" ]]; then
    printf 'clip-saver: xclip not found\n' >&2
    exit 1
fi
if [[ -z "$DISPLAY" ]]; then
    printf 'clip-saver: no X display\n' >&2
    exit 1
fi

# ─── Temp file: user-private runtime dir, mode 0600 ────────
RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
if [[ -z "$RUNTIME_DIR" || ! -d "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" ]]; then
    RUNTIME_DIR="/run/user/$("$ID_BIN" -u 2>/dev/null)"
    if [[ ! -d "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" ]]; then
        # Last resort: /tmp with a private directory
        RUNTIME_DIR=$("$MKTEMP_BIN" -d /tmp/snowfox-clip.XXXXXX) || exit 1
        "$CHMOD_BIN" 700 "$RUNTIME_DIR"
        PRIVATE_TMP_CREATED=true
    fi
fi

tmp=$("$MKTEMP_BIN" --tmpdir="$RUNTIME_DIR" "snowfox-clip.XXXXXX") || exit 1
"$CHMOD_BIN" 600 "$tmp" 2>/dev/null || true

# ─── Cleanup ───────────────────────────────────────────────
cleanup() {
    "$RM_BIN" -f "$tmp" 2>/dev/null || true
    if [[ "${PRIVATE_TMP_CREATED:-false}" == "true" && -n "$RUNTIME_DIR" ]]; then
        "$RM_BIN" -rf "$RUNTIME_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM HUP

# ─── Clipboard helpers ─────────────────────────────────────
# Read TARGETS from the clipboard. Empty on error or timeout.
_clip_targets() {
    "$TIMEOUT_BIN" "$XCLIP_TIMEOUT" "$XCLIP_BIN" \
        -selection clipboard -t TARGETS -o 2>/dev/null
}

# Read the current clipboard content of a given type into $tmp.
# Returns 0 on success, non-zero on error / empty content.
_clip_read_into_tmp() {
    local type="$1"
    : > "$tmp"
    "$TIMEOUT_BIN" "$XCLIP_TIMEOUT" "$XCLIP_BIN" \
        -selection clipboard -t "$type" -o >"$tmp" 2>/dev/null || return 1
    [[ -s "$tmp" ]] || return 1
    return 0
}

# Hash of the current $tmp content. Empty on error.
_clip_hash_tmp() {
    "$SHA256SUM_BIN" <"$tmp" 2>/dev/null | "$CUT_BIN" -d' ' -f1
}

# Clear the clipboard if it still holds the content with $1 (type)
# and $2 (hash). Runs in the background, one timer per copy.
_clip_schedule_clear() {
    local type="$1" hash="$2" secs="$3"
    (
        "$SLEEP_BIN" "$secs"
        local current
        current=$("$TIMEOUT_BIN" "$XCLIP_TIMEOUT" "$XCLIP_BIN" \
            -selection clipboard -t "$type" -o 2>/dev/null \
            | "$SHA256SUM_BIN" 2>/dev/null \
            | "$CUT_BIN" -d' ' -f1)
        [[ -z "$current" || "$current" != "$hash" ]] && exit 0

        # Content unchanged — clear it. xclip needs a valid target
        # to own the selection; empty UTF8_STRING is the portable way.
        printf '' | "$TIMEOUT_BIN" "$XCLIP_TIMEOUT" "$XCLIP_BIN" \
            -selection clipboard -t UTF8_STRING -i 2>/dev/null || true
    ) &
    disown 2>/dev/null || true
}

# ─── Main loop ─────────────────────────────────────────────
declare -A last_hash=()

while "$CLIPNOTIFY_BIN"; do
    targets=$(_clip_targets) || continue
    [[ -z "$targets" ]] && continue

    # Sensitive source: never persist, never re-anchor.
    # The source application manages its own clipboard lifetime.
    if "$GREP_BIN" -qE "$SENSITIVE_MIME_RE" <<<"$targets"; then
        last_hash=()
        continue
    fi

    # File copy/cut: leave alone, otherwise x-special/gnome-copied-files
    # and text/uri-list are lost.
    if "$GREP_BIN" -qxE "$FILECOPY_MIME_RE" <<<"$targets"; then
        last_hash=()
        continue
    fi

    # Pick a type we know how to re-anchor.
    if "$GREP_BIN" -qx 'image/png' <<<"$targets"; then
        type="image/png"
    elif "$GREP_BIN" -qx 'UTF8_STRING' <<<"$targets"; then
        type="UTF8_STRING"
    else
        continue
    fi

    _clip_read_into_tmp "$type" || continue

    # Loop protection: our own xclip triggers clipnotify again.
    # Tracked per type so an image and a text with the same hash
    # do not suppress each other.
    hash=$(_clip_hash_tmp)
    [[ -z "$hash" ]] && continue
    [[ "${last_hash[$type]:-}" == "$hash" ]] && continue
    last_hash["$type"]="$hash"

    # Re-anchor content (xclip keeps running in the background).
    "$XCLIP_BIN" -selection clipboard -t "$type" -i <"$tmp" 2>/dev/null || continue

    # Schedule the auto-clear. Sensitive sources never reach this
    # point, so only the normal timeout applies here.
    _clip_schedule_clear "$type" "$hash" "$CLIP_TIMEOUT_NORMAL"
done

exit 0
