#!/bin/bash
# bootupctl shim for bootc on the Raspberry Pi CM4 -- Debian port of the Fedora
# trick in raspbian3/files/bootupctl-shim.sh.
#
# bootc treats "a `bootupctl` executable + /usr/lib/bootupd/updates both exist"
# as bootupd being available, and then runs (chrooted into the deployment, with
# the ESP at /boot/efi):
#   bootupctl backend install --write-uuid [--update-firmware --auto] --filesystem / /
# first probing `bootupctl backend install --help` for --filesystem support.
#
# Debian has no real bootupd, so this standalone shim hijacks that call to stage
# the full ESP payload (Pi firmware + u-boot.bin + systemd-boot at
# EFI/BOOT/BOOTAA64.EFI). ostree writes the BLS boot entries separately, and
# systemd-boot reads them -- so nothing else is needed here.
set -euo pipefail

if [[ "${1:-}" == "backend" && "${2:-}" == "install" ]]; then
    # Capability probe: advertise --filesystem so bootc uses the chroot path
    # (target root "/"), then does nothing else.
    if [[ "$*" == *"--help"* ]]; then
        echo "--filesystem"
        exit 0
    fi

    dest="${@: -1}"   # last arg = target root (usually "/" inside the chroot)
    esp="${dest%/}/boot/efi"
    echo "raspbian3: staging Raspberry Pi firmware into ${esp}/" >&2
    mkdir -p "${esp}"
    cp -av /usr/lib/bootc-raspi-firmwares/. "${esp}/"
    echo "raspbian3: firmware staging complete" >&2
fi

# No real bootupd on Debian -- nothing further to exec.
exit 0
