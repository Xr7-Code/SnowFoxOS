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

# 2. Enable the unit ONLY if the marker exists. If iso-gpu
#    succeeded, there is nothing to retry, so the unit stays off.
if [[ -f /var/lib/snowfox/firstboot-pending ]]; then
    echo "[40] firstboot-pending present — enabling snowfox-firstboot.service"
    systemctl enable snowfox-firstboot.service 2>/dev/null || true
else
    echo "[40] no firstboot work pending — service left disabled"
fi