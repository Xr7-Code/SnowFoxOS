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

## Transitional items (TODO for Prompt 7)

- `installer/overlay/40-firstboot.sh` still calls `--phase extras`.
  The alias makes this a no-op today. **Prompt 7 must remove the
  call** and rewrite the overlay for v4.
- The `extras` alias will be removed once the overlay is updated.
