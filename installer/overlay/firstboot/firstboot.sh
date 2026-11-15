#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO firstboot retry
# ============================================================
#  Runs once after reboot if the iso-gpu phase failed (no
#  network during install). Waits for network, retries, and
#  disables itself on success.
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-firstboot.log"
exec >> "$LOG" 2>&1
echo ""
echo "=== snowfox-firstboot $(date -Iseconds) ==="

# 1. Wait for network (max 120 s)
if ! timeout 120 bash -c 'until ping -c1 -W2 deb.debian.org >/dev/null 2>&1; do sleep 2; done'; then
    echo "[firstboot] network unavailable — leaving marker for next boot"
    exit 0
fi

# 2. Clear the stale offline flag
rm -f /var/lib/snowfox/net-offline

# 3. Retry the GPU phase
export SCRIPT_DIR="/opt/snowfox-src"
export SNOWFOX_PHASE="iso-gpu"
export SNOWFOX_DEFAULTS="true"

if cd /opt/snowfox-src && bash install.sh --phase iso-gpu --defaults; then
    echo "[firstboot] GPU phase complete"
    rm -f /var/lib/snowfox/firstboot-pending
    systemctl disable snowfox-firstboot.service 2>/dev/null || true
else
    echo "[firstboot] GPU phase still failing — will retry on next boot"
    exit 0
fi