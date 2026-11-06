#!/bin/bash
# ============================================================
#  SnowFoxOS v3 — Pinned SHA256 Checksums
#  Copyright (c) 2026 Alexander Valentin Ludwig (Xr7-Code)
# ============================================================
#
#  POLICY: Every binary fetched from an external source in the
#  installer must have its SHA256 checked against a value pinned
#  here before it is moved into place.
#
#  HOW TO UPDATE A HASH:
#    1. Download the release asset manually on a trusted machine.
#    2. Run: sha256sum <file>
#    3. Paste the hex digest below.
#    4. Never trust a hash you did not compute yourself.
#
#  If a hash is still the literal string "UNPINNED", the installer
#  will REFUSE to download that asset and abort with a clear error.
#  This is fail-closed by design: an unpinned dependency must be
#  pinned before the installer can run.
#
#  Format: CHECKSUM_<NAME>="<sha256>"
# ============================================================

# fastfetch — GitHub release (fastfetch-linux-amd64.deb)
# Upstream: https://github.com/fastfetch-cli/fastfetch/releases
CHECKSUM_FASTFETCH="06e9a1be9a863dc815f8a31a6b1abec7b29967be30084ffcc29c1bca072d801b"

# Bibata-Modern-Classic cursor theme — GitHub release (tar.xz)
# Upstream: https://github.com/ful1e5/Bibata_Cursor/releases
CHECKSUM_BIBATA="7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8"

# JetBrainsMono Nerd Font — GitHub release (zip)
# Upstream: https://github.com/ryanoasis/nerd-fonts/releases
CHECKSUM_JETBRAINSMONO="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# clipnotify — built from source, pinned by commit hash instead
# of tarball hash. The build script must check out this exact commit.
CLIPNOTIFY_COMMIT="UNPINNED"

# yt-dlp — GitHub release (standalone binary)
# Upstream: https://github.com/yt-dlp/yt-dlp/releases
# Releases frequently — update via "snowfox update-checksums".
CHECKSUM_YTDLP="UNPINNED"

# VSCodium repository signing key (GPG fingerprint, 40 hex chars)
# Get it once with:
#   curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
#     | gpg --show-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'
VSCODIUM_GPG_FPR="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
=LCWI"

# OnlyOffice repository signing key (GPG fingerprint)
# Get it once with:
#   curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
#     | gpg --show-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'
ONLYOFFICE_GPG_FPR="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
81hkBVJuWbhRoNnqaVckis0fsqCr
=5jvL"

# ── Helper: verify a file against a pinned checksum ─────────
# Usage: _verify_checksum <file> <expected> <name>
# Returns 0 on success, 1 on mismatch or unpinned.
_verify_checksum() {
    local file="$1" expected="$2" name="$3"
    local actual

    if [[ "$expected" == "UNPINNED" ]]; then
        warn "Checksum for '$name' is not pinned — refusing to install."
        warn "Pin it in lib/checksums.sh before running the installer."
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        error "Checksum target '$file' does not exist."
    fi

    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$actual" != "$expected" ]]; then
        error "SHA256 mismatch for $name
  expected: $expected
  actual:   $actual
  file:     $file"
    fi
    return 0
}
