#!/usr/bin/env bash

set -xeuo pipefail

mkdir -p /usr/lib/dracut/dracut.conf.d/
printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf
printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf"
# Derive the kernel version from the modules dir in the image and pass it to
# dracut explicitly. Relying on dracut's `uname -r` default breaks whenever the
# build host kernel differs from the image kernel (cross-arch builds, or any
# build under an emulated/foreign kernel such as WSL2).
kver="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)")"
dracut --force --kver "$kver" "/usr/lib/modules/$kver/initramfs.img"
