#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO firstboot completion
# ============================================================
#  Runs once after reboot. ISO installs always defer some work
#  (AIDE baseline, XDG dirs, session settings); the GPU/driver
#  phase is retried too when it was left pending. Waits for
#  network, runs the regular `firstboot` phase, and disables
#  itself on success.
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-firstboot.log"
touch "$LOG"
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

# 3. Run the firstboot phase. lib/firstboot.sh retries the
#    kernel/GPU phase when /var/lib/snowfox/firstboot-pending
#    is still present, then finishes user-session setup.
export SCRIPT_DIR="/opt/snowfox-src"
export SNOWFOX_PHASE="firstboot"
export SNOWFOX_DEFAULTS="true"

if cd /opt/snowfox-src && bash install.sh --phase firstboot --defaults; then
    echo "[firstboot] firstboot phase complete"
    rm -f /var/lib/snowfox/firstboot-pending
    systemctl disable snowfox-firstboot.service 2>/dev/null || true
else
    rc=$?
    echo "[firstboot] firstboot phase failed (exit $rc) — will retry on next boot"
    exit 0
fi

echo "[firstboot] done"
