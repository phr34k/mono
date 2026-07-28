#!/bin/bash
# bootupctl shim for bootc on the Raspberry Pi CM4 -- matches supakeen's/Ondrej
# Budai's Fedora approach: https://supakeen.com/weblog/bootc-on-the-raspberry-pi/
#
# bootc calls `bootupctl backend install <flags> <dest>`. bootupd's install is
# additive (manages files under EFI/, does not wipe the ESP root), so the Pi
# firmware (dtbs, start*.elf, fixup*.dat, config.txt, u-boot.bin, overlays) and
# the EFI bootloader (shim + GRUB) can coexist on the ESP.
#
# The hard part is finding the ESP. bootc runs us chrooted; the trailing
# positional arg ("/") points at the ostree DEPLOYMENT, whose /boot/efi is NOT
# the mounted ESP -- copying firmware there is silently lost (that was the
# "ESP has only EFI/, no firmware" bug). Rather than guess the path, we let the
# real bootupd install first (it writes EFI/BOOT to the true ESP), then find
# whichever mountpoint now holds EFI/BOOT/BOOTAA64.EFI and stage the firmware
# right next to it. (Workaround pending https://github.com/coreos/bootupd/issues/766.)
set -euo pipefail

if [[ "${1:-}" == "backend" && "${2:-}" == "install" ]]; then
    # Capability probe: advertise --filesystem (the real bootupctl supports it).
    if [[ "$*" == *"--help"* ]]; then
        echo "--filesystem"
        exit 0
    fi

    # 1) Let the real bootupd install the EFI bootloader onto the actual ESP.
    rc=0
    /usr/bin/bootupctl-orig/bootupctl "$@" || rc=$?

    # 2) Derive the --filesystem root as the primary ESP candidate.
    args=("$@")
    fsroot=""
    for ((i=0; i<${#args[@]}; i++)); do
        [[ "${args[i]}" == "--filesystem" ]] && fsroot="${args[i+1]:-}"
    done
    [[ -z "$fsroot" ]] && fsroot="${@: -1}"

    # 3) The true ESP is whichever mountpoint bootupd just wrote BOOTAA64.EFI to.
    #    Check likely mounts + every vfat in /proc/mounts (unreachable ones fail
    #    the -f test and are skipped).
    esp=""
    for cand in "${fsroot%/}/boot/efi" /sysroot/boot/efi /boot/efi /target/boot/efi \
                $(awk '$3=="vfat"{print $2}' /proc/mounts 2>/dev/null); do
        if [[ -f "$cand/EFI/BOOT/BOOTAA64.EFI" ]]; then esp="$cand"; break; fi
    done

    if [[ -n "$esp" ]]; then
        echo "raspbian3: staging Raspberry Pi firmware into ESP at ${esp}/" >&2
        # -rL (NOT -a): the ESP is vfat, which has no hard links, ownership or
        # perms. Debian's raspi-firmware hard-links identical fixup*/start*
        # variants; `cp -a` tries to recreate those links and fails with
        # "Operation not permitted" on FAT. -r copies each as an independent
        # file, -L dereferences any symlinks (also unsupported on FAT).
        cp -rvL /usr/lib/bootc-raspi-firmwares/. "${esp}/"
        # Marker on the ext4 /boot (parent of the ESP mount) for GRUB's search.
        : > "$(dirname "$esp")/bootc-boot-partition" 2>/dev/null || true
        sync
    else
        echo "raspbian3: WARNING: could not locate the ESP (no EFI/BOOT/BOOTAA64.EFI found after bootupd); firmware NOT staged" >&2
    fi
    exit "$rc"
fi

# Non-install invocations: pass through to the real bootupd unchanged.
exec /usr/bin/bootupctl-orig/bootupctl "$@"
