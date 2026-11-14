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
CHECKSUM_JETBRAINSMONO="187c316bb77ed1c824099fe8621a17d14f7de8a6ce5b14a1a04de0ae674b4aa6"

# clipnotify — built from source, pinned by commit hash instead
# of tarball hash. The build script must check out this exact commit.
CLIPNOTIFY_COMMIT="25ba143c7da8ae0f196cb0db2797d30e6d04e15c"

# VSCodium repository signing key (GPG fingerprint, 40 hex chars)
# Get it once with:
#   curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
#     | gpg --show-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'
VSCODIUM_GPG_FPR="1302DE60231889FE1EBACADC54678CF75A278D9C"

# OnlyOffice repository signing key (GPG fingerprint)
# Get it once with:
#   curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
#     | gpg --show-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'
ONLYOFFICE_GPG_FPR="E09CA29F6E178040EF22B4098320CA65CB2DE8E5"

# bluetui — prebuilt musl binary (x86_64)
# Upstream: https://github.com/pythops/bluetui/releases
CHECKSUM_BLUETUI="b476ee473cb4f7a48cd75d440e991bedc835ff5ac704aac1f1992f8e826222fd"

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
