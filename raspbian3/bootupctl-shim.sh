#!/bin/bash
# bootupctl shim for bootc on the Raspberry Pi CM4 -- split model (Debian port of
# the Fedora trick in raspbian3/files/bootupctl-shim.sh).
#
# bootc calls `bootupctl backend install [--write-uuid --update-firmware --auto]
# --filesystem / /` (chrooted into the deployment, ESP at /boot/efi), first
# probing `... --help` for --filesystem support. This shim:
#   1. stages the Pi-specific firmware (config.txt, u-boot.bin, start4.elf, ...)
#      onto the ESP -- bootupd knows nothing about these, and
#   2. hands the EFI install (shim + GRUB) to the REAL cross-built bootupd, but
#      only the EFI component (no --update-firmware, so no efibootmgr). The image
#      ships a Debian shimaa64.efi so bootupd's vendordir detection succeeds.
#      bootupd then owns the shim+GRUB on the ESP and can update it transactionally.
set -euo pipefail

if [[ "${1:-}" == "backend" && "${2:-}" == "install" ]]; then
    # Capability probe: advertise --filesystem (bootc then calls with target "/").
    if [[ "$*" == *"--help"* ]]; then
        echo "--filesystem"
        exit 0
    fi

    root="${@: -1}"            # target root (usually "/" inside the chroot)
    esp="${root%/}/boot/efi"

    echo "raspbian3: staging Raspberry Pi firmware into ${esp}/" >&2
    mkdir -p "${esp}"
    cp -av /usr/lib/bootc-raspi-firmwares/. "${esp}/"
    # Marker so the GRUB config can `search --file` for the ext4 /boot partition.
    : > "${root%/}/boot/bootc-boot-partition" || true

    echo "raspbian3: installing GRUB EFI via bootupd (EFI component only)" >&2
    exec /usr/libexec/bootupd install --component EFI --filesystem "${root}" "${root}"
fi

exit 0
