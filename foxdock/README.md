# foxdock

Minimal vertical dock for SnowFoxOS v4, written in C against pure
Xlib. No GTK, no GLib, no toolkit — expected RSS around 5–10 MB.

## Why Imlib2

Icons in modern `.desktop` files are PNG or SVG. `libxpm` only reads
XPM; handling PNG and scaling would mean pulling in libpng +
libjpeg + custom scalers. Imlib2 already does all of that and is a
small, stable dependency (single library, no daemon, no session
bus). We deliberately avoid GTK/GLib because the whole point of
foxdock is to keep the process footprint tiny.

## Runtime contract

- Reads `~/.config/snowfox/palette.conf` (written atomically by
  `snowfox theme` / `lib/theme_engine.sh`).
- Reads `~/.config/foxdock/dock.conf` (`name;icon;exec` per line,
  optional `icon_size=NN` and `padding=NN` header keys).
  Defaults: `icon_size=32`, `padding=6`. Valid icon sizes are
  32 and 48; any other value is honoured but not tuned for.
- **Entry source is either/or, never both.** If `dock.conf` exists
  and contains at least one `name;icon;exec` line, those entries
  are the dock — no additional auto-scan happens. Only when
  `dock.conf` is missing or yields zero entries does foxdock scan
  `/usr/share/applications` with a minimal `.desktop` parser
  (Name/Icon/Exec/NoDisplay only — no GLib). This avoids
  duplicate icons and keeps the user's file authoritative.
- Registers `_NET_WM_STRUT_PARTIAL` on the left edge so i3
  reserves space automatically. This is the primary mechanism;
  no i3 `for_window` rule is required for the space reservation.
  The plan still recommends the sticky rule for cross-workspace
  visibility:
  `for_window [class="FoxDock"] border none, sticky enable`.

## SIGHUP contract (theme live-reload)

`snowfox theme <name>` calls `pkill -HUP -x foxdock` after the
palette has been written. foxdock treats every SIGHUP as a full
reload of `~/.config/snowfox/palette.conf`, followed by a
repaint. There is no restart, no session-bus round-trip.

Two invariants that the reload path MUST honour, because
`palette.conf` is written by an external process:

1. **Idempotent.** Sending SIGHUP N times in a row leaves the
   dock in the same state as sending it once. No accumulated
   state, no leak, no double-registration.
2. **Crash-safe.** A malformed, truncated, or half-written
   `palette.conf` must never take foxdock down. On any parse
   failure, `palette_reload()` returns non-zero and foxdock
   keeps the currently loaded palette and continues running.
   (The theme engine writes the file atomically via
   `mktemp` + `mv`, so a real half-write should never be
   observable — but the dock does not rely on that.)

If the palette file is absent at startup, foxdock initialises
with zeroed pixel values (black background) and stays alive.
It is a comfort feature, not a critical component.

## Build

    make
    sudo make install

Requires `libx11-dev` and `libimlib2-dev`.

## Known issues (v4.0)

- **Tooltip is not wired up.** `draw_tooltip()` in `draw.c` is
  complete and functional, but the main event loop in `main.c`
  does not call it. Wiring it up needs a ~500 ms hover timer so
  it does not flicker while the mouse moves across the dock.
  Planned for v4.1. In v4.0 the dock shows only the hover
  inversion, no tooltip text.

## Not in v4.0

Window list, tray, drag & drop. Planned for v4.1 if needed.

## Reference

The `## Runtime contract` section above is the canonical
description of foxdock's inputs and signals. `PROJECT_STRUCTURE.md`
should link to it rather than duplicate it.