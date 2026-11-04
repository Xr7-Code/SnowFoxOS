# SnowFoxOS v3.3 — Security Update Log

Short documentation of all fixed security issues. One entry per module,
format: **Issue** → **Fix**. Append new entries at the top.

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

- `cli/ai.sh` — enforce Ollama binding to loopback (P0).
- `cli/desktop.sh` — `.desktop` injection in WebApp generation (P1).
- `cli/theme.sh` — palette value validation against config injection (P1).
- `configs/snowfox-mesh.sh` — webserver binding, token auth, path traversal
  (P1).
- `configs/i3/clip-saver.sh` — clipboard timeout, sensitive sources (P1).
- `snowfox-greeting.sh` — `/tmp` state → `$XDG_RUNTIME_DIR` (P2).
- systemd hardening for Ollama/Tor/Mesh (P1).
- `snowfox audit leak` as new subcommand (P2).
