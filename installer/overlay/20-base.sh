#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO overlay step 20: base install
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-install.log"
exec >> "$LOG" 2>&1

echo ""
echo "=== 20-base.sh $(date -Iseconds) ==="

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/repo"

# 1. Copy the embedded repo to /opt/snowfox-src
install -d -m 0755 /opt
rm -rf /opt/snowfox-src
cp -a "$REPO" /opt/snowfox-src
chmod -R go-w /opt/snowfox-src
echo "[20] repo snapshot at /opt/snowfox-src"

# 2. Run the base phase
export SCRIPT_DIR="/opt/snowfox-src"
export SNOWFOX_PHASE="iso-base"
export SNOWFOX_DEFAULTS="true"

cd /opt/snowfox-src
bash install.sh --phase iso-base --defaults
echo "[20] iso-base complete"