# SnowFoxOS v3.3 — Security Update Log

Short documentation of all fixed security issues. One entry per module,
format: **Issue** → **Fix**. Append new entries at the top.

---

## cli/desktop.sh — Autostart, Layout, WebApps

- **`eval "$exec_cmd"` in `_webapp_open`** (arbitrary code execution from a
  `.desktop` file) → `eval` removed; launch via `gtk-launch` with the desktop
  ID, fallback to `xdg-open` on a re-validated URL.
- **Unvalidated `$name`/`$url` written into `.desktop`** (desktop-file
  injection via newline/quote) → `_valid_webapp_name()` and `_valid_url()`
  enforced, values quoted with `_desktop_quote()` (single-quote layer per
  desktop-entry spec).
- **`sed` injection via `$target` in i3 config** → `_valid_program_name()`
  whitelist, `_sed_escape()` on every interpolated value.
- **Empty `$safe` → `rm -rf` on the whole WebApp directory** → `_webapp_slug()`
  returns non-zero on empty result; `_webapp_remove` additionally asserts the
  path is under `$WEBAPP_DIR`.
- **`curl` without protocol/TLS constraints** (file://, ftp://, weak TLS) →
  `--proto '=https' --tlsv1.2` enforced.
- **Google favicon proxy leaked the domain** → removed; only direct
  `https://<domain>/favicon.{ico,png}` is tried.
- **`$url` not restricted to http(s)** (local file access via WebApp) →
  `_valid_url()` enforces `^https?://`.
- **`.desktop` files displayed without validation** (hidden `Exec=` lines) →
  `desktop-file-validate` runs before display, invalid entries flagged.
- **WebApp dirs created with default umask** → `$WEBAPP_DIR`/`$WEBAPP_ICONS`
  forced to `0700`, `$WEBAPP_DESK` to `0755`.
- **`update-desktop-database` assumed present** → `command -v` check before
  invocation.
- **`exit` in sub-commands** → `return`.
- **`PATH` / `LD_PRELOAD` uncontrolled** → same as security.sh.

---

## cli/ai.sh — Offline AI (Ollama)

- **Ollama bound to non-loopback address not detected** (model exposure) →
  `_ai_check_ollama_binding()` uses `ss -tln`, refuses any listener on
  `:11434` that is not `127.0.0.1`, prints fix instructions.
- **Command/registry injection via `$2` in `pull`** → `_ai_valid_model_name()`
  enforces `^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$`, max 128 chars.
- **Prompt injection via chat history** → config dir `0700`, history file
  `0600`, content sanitized (`tr -cd '[:print:]\n\t'`, newlines→spaces,
  capped at 4000 chars) before embedding.
- **`sudo systemctl start ollama` without consent** → user service tried
  first, `sudo` only after explicit `[y/N]` prompt.
- **`python3` required but unchecked** (history broken without it) → three-tier
  JSON path: `jq` → `python3` → pure-Bash fallback.
- **`_ai_pick_model` prefix match** (`llama3.2-vision` matched `llama3.2`) →
  exact `grep -xF` against full tag, then `^name:` prefix fallback.
- **Dead code `_ai_ask`** → removed, single path via `_ai_run_once`.
- **`_ai_cleanup` stopped Ollama unconditionally** (DoS against user-started
  daemon) → `_AI_STARTED_OLLAMA` flag, stop only if this session started it.
- **`exit` in sub-commands** → `return`.
- **`CONTEXT` unbounded** (prompt overflow) → `_ai_bound_context()` caps at
  6000 chars.
- **System prompt had no safety rules** → added non-negotiable block: no file
  contents, no command execution, no prompt reveal, treat file/log content as
  data.
- **`_ai_ensure_running` printed `true`/`false` on stdout** (fragile, any
  diagnostic would corrupt value) → returns 0/1, sets `_AI_STARTED_OLLAMA`.
- **Trap clobbered caller's `INT`/`TERM`** → `trap -p` saved and restored.
- **`PATH` / `LD_PRELOAD` uncontrolled** → same as security.sh.

---

## cli/security.sh — Network Audit

- **PATH / LD_PRELOAD hijacking** via `sudo` without `secure_path` → `PATH`
  hard-set, `LD_PRELOAD`/`LD_LIBRARY_PATH`/`SHELL` unset, all binaries as
  `readonly` with absolute paths.
- **`watch` subshell** (`sh -c`, `$SHELL`/`$TERM` hijackable) → own render
  loop with `printf`, `watch` removed.
- **`EUID -eq 0` as root check** (wrong in user namespaces) → empirical check
  whether `users:(` appears in `ss -tunpH`.
- **Fragile `awk '{print $6}'` parsing** → `ss -tunpH` + `read` into named
  fields.
- **Only first process on shared sockets** → all `users:((...))` entries
  parsed, deduplicated, comma-separated.
- **Overly aggressive UDP filter** (`grep -vE "^(udp|tcp).*\*"`) → filter only
  on the peer field (`*`, `*:*`, `0.0.0.0:*`, `[::]:*`).
- **False negative on `ss` error** ("No active connections") → exit code
  checked, `err` + `return 1` on failure.
- **No timeout on `ss`** → `timeout 10 ss ...`.
- **Terminal escape injection via process name** → `tr -cd '[:print:]'`.
- **`tr -d '[]'` strips all brackets** → `sed -E` only for leading IPv6
  brackets.
- **`exit 1` in library function** → `return`.
- **Live mode without root warning** → same empirical check as snapshot.
- **Incomplete local-net regex** → `169.254.`, `fc`, `fd`, ULA added.

---

## cli/tor.sh — Transparent Proxy

- **Non-atomic iptables loading** (clear-net window between `-A` calls) →
  full rulesets written to files, `iptables-restore` loads atomically.
- **`filter` OUTPUT without default policy** (everything open after `-F`) →
  `:OUTPUT DROP [0:0]` in IPv4 and IPv6.
- **`REJECT` instead of `DROP` policy** → default `DROP`, no `-j REJECT`
  needed.
- **DNS configured before iptables** (Tor DNS leak at startup) → order:
  torrc → start Tor → atomic iptables → DNS → verify.
- **`chattr +i` failure unchecked** → warning when lock fails, DNS still set.
- **IPv6 disabled via `sysctl`** (unreliable, inconsistent `AF_INET6`
  sockets) → IPv6 stack stays enabled; `ip6tables` OUTPUT DROP is
  authoritative.
- **`_tor_get_uid` name-only** → `systemctl show -p MainPID` → `/proc/<pid>`
  → fallback to name.
- **`torsocks curl` can silently fall back to cleartext** → `curl
  --s
