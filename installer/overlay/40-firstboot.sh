#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO overlay step 40: firstboot unit
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-install.log"
exec >> "$LOG" 2>&1

echo ""
echo "=== 40-firstboot.sh $(date -Iseconds) ==="

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install the firstboot payload (unit + script)
install -d -m 0755 /usr/local/lib/snowfox-installer
install -m 0755 "$HERE/firstboot/firstboot.sh" \
    /usr/local/lib/snowfox-installer/firstboot.sh
install -m 0644 "$HERE/firstboot/snowfox-firstboot.service" \
    /etc/systemd/system/snowfox-firstboot.service

# 2. Always enable the one-shot completion unit. ISO installs defer
#    work unconditionally (AIDE baseline, XDG dirs, session settings),
#    not only when the GPU/kernel phase failed. lib/firstboot.sh also
#    retries iso-gpu when /var/lib/snowfox/firstboot-pending exists,
#    and the unit disables itself after a successful run.
echo "[40] enabling snowfox-firstboot.service (one-shot completion)"
# In the d-i chroot `systemctl enable` often refuses to talk to
# systemd. Create the WantedBy symlink directly as a fallback.
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sfn /etc/systemd/system/snowfox-firstboot.service \
    /etc/systemd/system/multi-user.target.wants/snowfox-firstboot.service
systemctl enable snowfox-firstboot.service 2>/dev/null || true