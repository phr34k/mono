#!/bin/bash
# bootupctl shim for bootc on the Raspberry Pi CM4 -- matches supakeen's/Ondrej
# Budai's Fedora approach: https://supakeen.com/weblog/bootc-on-the-raspberry-pi/
#
# bootc calls `bootupctl backend install <flags> <root>` (chrooted into the
# deployment, ESP at /boot/efi). We copy the Pi firmware (dtbs, start*.elf,
# fixup*.dat, config.txt, u-boot.bin, overlays) onto the ESP root, then exec the
# REAL bootupctl UNCHANGED. bootupd's `backend install` is additive -- it manages
# files under EFI/ and does NOT wipe the firmware at the ESP root -- so the Pi
# firmware and the EFI bootloader (shim + GRUB) coexist.
# (Workaround pending https://github.com/coreos/bootupd/issues/766.)
set -euo pipefail

if [[ "${1:-}" == "backend" && "${2:-}" == "install" ]]; then
    # Capability probe: advertise --filesystem (the real bootupctl supports it).
    if [[ "$*" == *"--help"* ]]; then
        echo "--filesystem"
        exit 0
    fi

    root="${@: -1}"            # target root (last arg, usually "/" in the chroot)
    echo "raspbian3: copying Raspberry Pi firmware into ${root%/}/boot/efi/" >&2
    cp -av /usr/lib/bootc-raspi-firmwares/. "${root%/}/boot/efi/"
    # Marker so the GRUB config can `search --file` for the ext4 /boot partition.
    : > "${root%/}/boot/bootc-boot-partition" || true
    # CRITICAL: flush to disk before bootupd re-mounts the ESP. Otherwise our
    # writes are still in the mount cache, bootupd's fresh mount doesn't see them,
    # and the firmware is lost (only bootupd's EFI/ survives).
    sync
fi

# Hand off to the real bootupd unchanged -- it installs the EFI bootloader.
exec /usr/bin/bootupctl-orig/bootupctl "$@"
