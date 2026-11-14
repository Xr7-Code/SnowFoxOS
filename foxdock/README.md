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
  `snowfox theme`, see `lib/theme_engine.sh`).
- Reads `~/.config/foxdock/dock.conf` (`name;icon;exec` per line,
  optional `icon_size=NN` and `padding=NN` header keys).
- If `dock.conf` is empty or missing, scans `/usr/share/applications`
  with a minimal `.desktop` parser (Name/Icon/Exec/NoDisplay only —
  no GLib).
- Reacts to `SIGHUP` by reloading `palette.conf` and repainting.
  No restart needed; this is how live theme switching works.
- Registers `_NET_WM_STRUT_PARTIAL` on the left edge so i3
  reserves space automatically. No i3 rule is strictly required,
  but the plan recommends:
  `for_window [class="FoxDock"] border none, sticky enable`.

## Build

    make
    sudo make install

Requires `libx11-dev` and `libimlib2-dev`.

## Not in v4.0

Window list, tray, drag & drop. Planned for v4.1 if needed.
