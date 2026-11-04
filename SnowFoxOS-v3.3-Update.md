# SnowFoxOS v3.3 — Security Update Log

Short documentation of all fixed security issues. One entry per module,
format: **Issue** → **Fix**. Append new entries at the top.

---

## snowfox — Central CLI Dispatcher

- **`$SCRIPT_DIR` fallback not symlink-resolved** (an attacker who places a
  symlink to `/usr/local/bin/snowfox` next to a `cli/` directory could get
  arbitrary modules `source`d) → script path resolved with `readlink -f`;
  dev fallback only with `SNOWFOX_DEV=1`.
- **`source` of each module without existence/readability check** (fail-open
  on missing or partially-installed modules) → `_cli_require()` checks
  `-f`/`-r`, aborts on load failure.
- **No post-load function check** (partial module = silent undefined-function
  call) → every required `cmd_*` is validated via `declare -F` after loading.
- **`exec ~/.config/snowfox-*.sh` without `-x`/realpath check** (missing
  target leaves the user in a dead shell; symlink outside `$HOME` would be
  followed) → `_run_user_script()` validates executable bit, resolves with
  `readlink -f`, and refuses paths outside `$HOME`.
- **`$2`/`$3`/`$4` expanded raw** (unset → empty string, silently passed to
  modules) → `${2:-}` form everywhere.
- **`-h`/`--help` not recognized** → added to help case.
- **`shift` vs `"${@:2}"` inconsistency** → unified on `"${@:2}"`.
- **No `set -u` / `set -o pipefail`** → both set; `set -e` deliberately
  omitted (modules tolerate errors).
- **`uname` from `$PATH`** → `readonly UNAME_BIN`.
- **Hardcoded colors in pre-utils errors** → replaced with `printf` using
  literal escape sequences.

---

## configs/i3/clip-saver.sh — Clipboard Persistence

- **No clipboard timeout** (passwords, 2FA codes, keys stayed in the
  clipboard indefinitely) → `_clip_schedule_clear()` clears the selection
  after 30 s if it still holds the same hash; runs detached, one timer per
  copy.
- **No sensitive-source detection** (password managers persisted like any
  other text) → `x-kde-passwordManagerHint`, `application/x-keepass`,
  `application/x-1password`, `application/x-bitwarden`, `application/x-pass`
  are matched and skipped entirely (source keeps ownership).
- **`mktemp` in `$TMPDIR` with default umask** (world-readable clipboard
  spool) → `mktemp --tmpdir="$XDG_RUNTIME_DIR"`, mode `0600`, fallback to a
  private `0700` dir under `/tmp` only if no runtime dir exists.
- **`trap` caught only `EXIT`** (temp file survived `SIGTERM`/`SIGINT`) →
  `trap cleanup EXIT INT TERM HUP`.
- **`last_hash` was a single variable** (cross-type false negatives: image
  and text with identical hash suppressed each other) → `declare -A
  last_hash`, keyed by MIME type.
- **`sha256sum` failure not checked** (empty hash matched empty `last_hash`,
  data silently dropped) → `_clip_hash_tmp` returns empty, loop `continue`s.
- **File-copy MIME regex too broad** (`x-special/` matched any subtype) →
  `FILECOPY_MIME_RE` anchored to the exact four known types.
- **`xclip` calls had no timeout** (a stuck X server hung the daemon) →
  `timeout 5` on every read/hash.
- **`while clipnotify` without preconditions** (ran silently without X) →
  explicit checks for `clipnotify`, `xclip`, `$DISPLAY`.
- **`PATH` / `LD_PRELOAD` uncontrolled** → same as security.sh.

---

## snowfox-greeting.sh — Terminal Greeting

- **`/tmp` state file with predictable name** (symlink + TOCTOU attack: a
  local attacker could symlink `/tmp/snowfox_greeted_<user>_<tty>` to suppress
  the greeting or touch timestamps of arbitrary files) → state moved to
  `$XDG_RUNTIME_DIR` (0700, user-owned) or `/run/user/<uid>`, `$USER` removed
  from the path, atomic creation via `set -o noclobber`.
- **Non-TTY shells created a state file** (cron/scp/git hooks polluted the
  state) → `tty` check before any state write, exit 0 if not a TTY.
- **`$USER` embedded in `echo -e` without sanitizing** (terminal escape
  injection via crafted environment) → `tr -cd '[:alnum:]_.-'` whitelist.
- **`touch` without exit check** (greeting repeats on read-only /tmp) →
  `: > "$STATE_FILE"` via noclobber, failure aborts.
- **`date`/`uptime`/`awk`/`df`/`sed`/`tty`/`sleep` without absolute paths**
  (PATH hijacking) → `readonly` binary paths with `/bin` fallbacks, `PATH`
  hard-set.
- **`df -h /` parsed by column index** (fragile on long device names) →
  `df -h --output=avail /` with whitespace trim.
- **State file mode unspecified** (could be world-readable depending on umask)
  → `chmod 600`.

---

## cli/theme.sh — Color Themes (Master Palette Engine)

- **Palette colors embedded unvalidated into `sed` scripts** (BRE corruption
  via `/`, `$`, metacharacters) → `_theme_valid_color()` enforces
  `#RRGGBB`/`#AARRGGBB`/`rgba()`, `theme__esc`/`theme__repl` also escape `/`.
- **Palette values not restricted to color formats** (any text accepted) →
  strict regex in `theme__load`, invalid values skipped with warning.
- **UI values (theme/icon names) not validated** → `_theme_valid_ui()` enforces
  `[a-zA-Z0-9._-]{0,63}` or `0|1`.
- **Theme names not validated** (path traversal risk) → `_theme_valid_name()`
  enforces `^[a-zA-Z0-9][a-zA-Z0-9._-]*$`, max 64.
- **`theme__patch_ui_file` embedded `$val` unescaped** → value validated and
  `sed`-escaped (`&`, `|`, `\`).
- **`theme__apply_files` non-atomic** (`sed -i` partial write on crash) →
  render to `mktemp`, then `mv` (atomic on same filesystem).
- **`theme__backup` overwrote previous backup** → timestamped
  `theme-backup-YYYYMMDDTHHMMSSZ.tar.gz`, rotate to last 3, mode 0600.
- **`theme__reload` killed unrelated dunst/xsettingsd** → `pkill -0` guard,
  only restart daemons that were already running.
- **State written before reload** (inconsistent on reload failure) → state
  saved only after successful `theme__reload`.
- **`theme__rgba_re` built regex from unvalidated fields** (false matches) →
  numeric regex check on r/g/b/a before building pattern.
- **`theme__swatch` crashed on malformed rgba** → numeric check after split.
- **`cmd_theme_gui` passed unsanitized label to `notify-send`** (UI spoofing)
  → `tr -cd '[:print:]'`.
- **State file content not validated** → `_theme_valid_name` check on read.
- **`${@:2]}` syntax error in `reset)` branch** → `${@:2}`.
- **`PATH` / `LD_PRELOAD` uncontrolled** → same as security.sh.

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
  --socks5-hostname` enforced, `torsocks` removed.
- **`_tor_port_open` also matches `0.0.0.0`** → regex
  `127\.0\.0\.1:${port}[[:space:]]`.
- **`restart` leaves network open on failure** → `_tor_enable` calls
  `_tor_disable` on failure (rollback).
- **`_tor_remove_iptables` fallback `-F OUTPUT`** (everything open) → only
  `iptables-restore` from backup; on failure the blocking state is kept.
- **`exit` in library functions** → `return`.
- **`PATH` / `LD_PRELOAD` uncontrolled** → same as security.sh.
- **Status without kill-switch verification** → `iptables -S OUTPUT` policy
  check, red if not `DROP`.
- **`curl` result without `IsTor` check** → `"IsTor":true` verified, red
  otherwise.

---

## Open items (not yet fixed)

- `configs/snowfox-mesh.sh` — webserver binding, token auth, path traversal
  (P1). *Deferred: 2500+ line module, to be rewritten separately.*
- systemd hardening for Ollama/Tor/Mesh (P1).
- `snowfox audit leak` as new subcommand (P2).
