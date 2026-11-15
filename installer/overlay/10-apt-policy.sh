#!/usr/bin/env bash
# ============================================================
#  SnowFoxOS v4 — ISO overlay step 10: APT policy + sources
# ============================================================

set -euo pipefail

LOG="/var/log/snowfox-install.log"
exec >> "$LOG" 2>&1

echo ""
echo "=== 10-apt-policy.sh $(date -Iseconds) ==="

# 1. APT policy (no recommends, no suggests) — same as git-clone path
install -d -m 0755 /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99-snowfox <<'EOF'
// SnowFoxOS APT policy — lean system, explicit packages only
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
chmod 0644 /etc/apt/apt.conf.d/99-snowfox

# 2. Sources — ensure contrib/non-free/non-free-firmware are present.
#    d-i already wrote a working sources.list; we only append missing
#    components if the file exists.
if [[ -f /etc/apt/sources.list ]]; then
    for comp in contrib non-free non-free-firmware; do
        grep -q " $comp" /etc/apt/sources.list || \
            sed -i "/^deb / s|$| $comp|" /etc/apt/sources.list
    done
fi

# 3. apt-get update — tolerate offline
if apt-get update -qq; then
    echo "[10] apt-get update ok"
else
    echo "[10] apt-get update failed — writing /var/lib/snowfox/net-offline"
    install -d -m 0755 /var/lib/snowfox
    touch /var/lib/snowfox/net-offline
fi