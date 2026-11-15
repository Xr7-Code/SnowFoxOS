#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO overlay step 30: GPU/kernel phase
#  Exit 75 = network unavailable (not fatal).
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-install.log"
exec >> "$LOG" 2>&1

echo ""
echo "=== 30-gpu.sh $(date -Iseconds) ==="

if [[ -f /var/lib/snowfox/net-offline ]]; then
    echo "[30] net-offline flag present — deferring to firstboot"
    install -d -m 0755 /var/lib/snowfox
    touch /var/lib/snowfox/firstboot-pending
    exit 75
fi

export SCRIPT_DIR="/opt/snowfox-src"
export SNOWFOX_PHASE="iso-gpu"
export SNOWFOX_DEFAULTS="true"

cd /opt/snowfox-src
if bash install.sh --phase iso-gpu --defaults; then
    echo "[30] iso-gpu complete"
else
    rc=$?
    echo "[30] iso-gpu failed (exit $rc) — firstboot will retry"
    install -d -m 0755 /var/lib/snowfox
    touch /var/lib/snowfox/firstboot-pending
    exit 75
fi