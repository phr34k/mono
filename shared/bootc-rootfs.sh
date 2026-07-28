#!/usr/bin/env bash

set -xeuo pipefail

# Debian/Ubuntu keep the dpkg database in /var/lib/dpkg, but bootc treats /var as
# ephemeral runtime state and wipes it below -- which breaks apt/dpkg in any image
# built FROM this one (`FROM myimage` / `RUN apt-get install ...`) and at runtime.
# Relocate the DB into /usr (immutable, matched to the installed package set, like
# Fedora's rpmdb at /usr/lib/sysimage/rpm) and leave a /var/lib/dpkg -> /usr
# symlink so apt/dpkg resolve their default path with NO extra config. No-op on
# non-dpkg distros.
if [ -d /var/lib/dpkg ] && [ ! -L /var/lib/dpkg ]; then
    mkdir -p /usr/lib/sysimage
    rm -rf /usr/lib/sysimage/dpkg
    mv /var/lib/dpkg /usr/lib/sysimage/dpkg
    dpkg_relocated=1
fi

rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg

mkdir -p /sysroot /boot /usr/lib/ostree /var

ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local

# Recreate the dpkg-DB symlink in the (now-wiped) /var: in the image itself for
# derived builds, and via tmpfiles.d so it also exists on the booted system.
if [ "${dpkg_relocated:-}" = 1 ]; then
    mkdir -p /var/lib
    ln -sT ../../usr/lib/sysimage/dpkg /var/lib/dpkg
    # apt's spool/state dirs were wiped with /var and apt won't auto-create them
    # ("Archives directory .../partial is missing"); recreate the skeleton so
    # derived `apt-get` builds AND runtime `apt-get` (after `bootc usr-overlay`)
    # work. Provided in the image (for derived builds) and via tmpfiles.d (for the
    # booted system, where /var is repopulated fresh).
    mkdir -p /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/log/apt
    printf 'd /var/lib 0755 root root -\nL /var/lib/dpkg - - - - ../../usr/lib/sysimage/dpkg\n' \
        >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf
    printf 'd /var/cache/apt/archives/partial 0700 root root -\nd /var/lib/apt/lists/partial 0755 root root -\nd /var/log/apt 0755 root root -\n' \
        >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf
fi

echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

