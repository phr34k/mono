#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .

# Optionally pin bootc to a specific ref (per-distro override).
if [ -n "${BOOTC_REF:-}" ]; then
    git checkout "$BOOTC_REF"
fi

# Optionally cap the ostree crate feature to match an older libostree than
# upstream bootc targets. Debian stable (trixie) ships ostree 2025.2 while
# bootc requires 2025.3 by default; capping the feature lets it build against
# the older system library. No-op unless OSTREE_FEATURE is set.
if [ -n "${OSTREE_FEATURE:-}" ]; then
    sed -i -E "s/v2025_[0-9]+/${OSTREE_FEATURE}/g" crates/ostree-ext/Cargo.toml
fi

make bin install-all DESTDIR=/output

