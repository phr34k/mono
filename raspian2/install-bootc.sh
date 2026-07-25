#!/usr/bin/env bash
# Install cross-built bootc artifacts into DESTDIR (/output), mirroring the
# essential parts of bootc's `make install-all` but WITHOUT the steps that
# execute the built binary (manpages via xtask, shell completions) -- those
# can't run on the native host for a cross-compiled aarch64 binary, and they
# are cosmetic. Run this from the bootc source tree after cross-building.
set -xeuo pipefail

D=/output
prefix=/usr
T=target/aarch64-unknown-linux-gnu/release

# Main binaries
install -D -m0755 -t "$D$prefix/bin" "$T/bootc"
install -D -m0755 -t "$D$prefix/bin" "$T/system-reinstall-bootc"

# bootc runtime dirs + storage symlink (matches Makefile `install`)
install -d -m0755 "$D$prefix/lib/bootc/bound-images.d"
install -d -m0755 "$D$prefix/lib/bootc/kargs.d"
install -d "$D$prefix/lib/bootc/install"
STORAGE_RELATIVE_PATH=$(realpath -m -s --relative-to="$prefix/lib/bootc/storage" /sysroot/ostree/bootc/storage)
ln -s "$STORAGE_RELATIVE_PATH" "$D$prefix/lib/bootc/storage"

# systemd generator stub + units + prepare-root baseimage docs
install -D -m0755 crates/cli/bootc-generator-stub "$D$prefix/lib/systemd/system-generators/bootc-systemd-generator"
install -D -m0644 -t "$D$prefix/lib/systemd/system" systemd/*.service systemd/*.timer systemd/*.path systemd/*.target
install -D -m0644 -t "$D$prefix/share/doc/bootc/baseimage/base/usr/lib/ostree/" baseimage/base/usr/lib/ostree/prepare-root.conf
install -d -m755 "$D$prefix/share/doc/bootc/baseimage/base/sysroot"
cp -PfT baseimage/base/ostree "$D$prefix/share/doc/bootc/baseimage/base/ostree"
cp -Prf baseimage/dracut "$D$prefix/share/doc/bootc/baseimage/dracut"
cp -Prf baseimage/systemd "$D$prefix/share/doc/bootc/baseimage/systemd"

# initramfs setup binary + service + dracut module
install -D -m0644 -t "$D/usr/lib/systemd/system" crates/initramfs/*.service
install -D -m0755 "$T/bootc-initramfs-setup" "$D/usr/lib/bootc/initramfs-setup"
install -D -m0755 -t "$D/usr/lib/dracut/modules.d/51bootc" crates/initramfs/dracut/module-setup.sh

# ostree compatibility hooks (bootc takes over `ostree container` etc.)
install -d "$D$prefix/libexec/libostree/ext"
for x in ostree-container ostree-ima-sign ostree-provisional-repair; do
    ln -sf ../../../bin/bootc "$D$prefix/libexec/libostree/ext/$x"
done
