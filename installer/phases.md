# SnowFoxOS v4 — Installer Phases

Single source of truth for the `--phase` flag. Module lists live in
`lib/phase.sh:phase_modules()`; this document explains intent and
chroot rules.

| Phase       | Purpose                                                     | Modules (in order)                                                                                      |
|-------------|-------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `full`      | Interactive full install (default)                          | base_system, kernel_drivers, desktop_environment, audio_terminal, default_apps, performance_security, boot_screen, theming_finishing, cleanup_final |
| `iso-base`  | Chroot-safe base (runs inside d-i `in-target`)              | base_system, desktop_environment, audio_terminal, default_apps, performance_security, boot_screen, theming_finishing, cleanup_final |
| `iso-gpu`   | Kernel/GPU phase (network-dependent, may exit 75)           | kernel_drivers                                                                                          |
| `firstboot` | Live-session completion after the first reboot              | firstboot                                                                                               |
| `extras`    | **DEPRECATED** alias, does nothing                          | — (prints deprecation notice, exit 0)                                                                   |

## Chroot rules

- `require_systemd_session` = `[ -d /run/systemd/system ]`. Any
  start/stop/restart goes through `systemd_safe` (downgraded to
  `enable` outside a live session) or the `systemctl` shim
  installed by `install_chroot_systemctl_shim`.
- `require_tty` aborts only in interactive mode; in defaults
  mode it logs `[default] no tty, continuing`.
- `detect_target_user` refuses to run in any phase other than
  `full` without a UID 1000 user.

## Transitional items

- ~~`installer/overlay/40-firstboot.sh` still calls `--phase extras`.
  The alias makes this a no-op today. **Prompt 7 must remove the
  call** and rewrite the overlay for v4.~~ → **erledigt**: die
  v4-Version von `40-firstboot.sh` ruft kein `--phase extras` mehr auf.
- The `extras` alias will be removed once the overlay is updated.
  It is now only kept for compatibility with any external scripts
  that call it.

## ISO path — how it hooks into `install.sh`

`installer/preseed/snowfox.preseed` (`late_command`) runs:

```text
cp -a /cdrom/snowfox /target/snowfox-install
in-target bash /snowfox-install/late.sh
```

`late.sh` orchestrates:

1. `10-apt-policy.sh` — writes `/etc/apt/apt.conf.d/99-snowfox`,
   appends `contrib non-free non-free-firmware` to sources,
   `apt-get update`. On failure: writes `/var/lib/snowfox/net-offline`
   and continues.
2. `20-base.sh` — copies `/snowfox-install/repo` to `/opt/snowfox-src`,
   runs `install.sh --phase iso-base --defaults`.
3. `30-gpu.sh` — runs `install.sh --phase iso-gpu --defaults`.
   On failure (or if `/var/lib/snowfox/net-offline` exists): writes
   `/var/lib/snowfox/firstboot-pending`, exits 75.
4. `40-firstboot.sh` — installs the firstboot payload to
   `/usr/local/lib/snowfox-installer/` and enables
   `snowfox-firstboot.service` **only** if the marker exists.

On next boot, `snowfox-firstboot.service` runs
`/usr/local/lib/snowfox-installer/firstboot.sh`, which waits for
network, retries the GPU phase, and disables itself on success.