# `installer/` — ISO preparation

This folder prepares the **ISO install path**: a bootable Debian 12
installer that embeds a pristine repo snapshot and runs the same
`install.sh` as the git-clone path, but non-interactively.

The actual `simple-cdd` build lives in a separate `iso-builder/`
folder that is **not yet built** (see Master Plan §6). This folder
contains everything the ISO needs *at runtime*:

- `preseed/snowfox.preseed` — d-i preseed, verbatim from the v3
  Work Order §2. Passwords are never preseeded.
- `overlay/` — the scripts that the preseed `late_command` runs
  inside the target chroot:
  - `late.sh` — orchestrator
  - `10-apt-policy.sh` — APT policy + sources
  - `20-base.sh` — `install.sh --phase iso-base`
  - `30-gpu.sh` — `install.sh --phase iso-gpu` (exit 75 = no network)
  - `40-firstboot.sh` — installs the retry unit
  - `firstboot/` — the retry unit + script
- `phases.md` — what each phase does, and how `late.sh` maps to it.
- `apt/99-snowfox` — the APT policy file installed on both paths.

## Not in this folder

- `build.sh`, `scripts/00-40`, `config/build.conf` — these belong in
  a future `iso-builder/` folder (Master Plan §6, deferred).
- Installer branding (GRUB, splash) — also future `iso-builder/`.

## Layout mapping

The v3 Work Order calls the runtime folder `iso-builder/overlay/snowfox/`.
In v4 it is flattened to `installer/overlay/` — the extra `snowfox/`
level was unnecessary. The preseed `late_command` was adjusted to
match (`/cdrom/snowfox` → `/cdrom/snowfox`, same path, different
source location).