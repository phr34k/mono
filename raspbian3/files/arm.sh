#!/bin/bash

# ---------------------------------------------------------------------------
# Size trim for the eMMC target. bootc deploys the final *merged* rootfs, so
# `dnf remove` here shrinks the on-disk (eMMC) footprint even though earlier
# OCI layers still carry the bytes. All traced safe: nothing depends on these.
# ---------------------------------------------------------------------------
# NB: do NOT remove `skopeo` — both `bootc` and `rpm-ostree` require it, so
# removing skopeo cascades and drops bootc (dracut then fails at initramfs
# build: "Module 'bootc' cannot be found").
dnf remove -qy \
  adcli \
  adwaita* \
  flatpak-session-helper \
  fwupd* \
  nfs-utils \
  python3-botocore \
  qemu-user-static \
  samba* \
  xkeyboard-config

# toolbox \
# tpm2-tools \


# Firmware for hardware the CM4/CM5 doesn't have. Keep Broadcom (brcmfmac —
# onboard WiFi/BT); qcom-wwan + realtek stay in case of USB 4G / USB NICs.
dnf remove -qy \
  nvidia-gpu-firmware \
  amd-gpu-firmware \
  amd-ucode-firmware \
  atheros-firmware \
  mt7xxx-firmware \
  intel-gpu-firmware \
  intel-audio-firmware \
  cirrus-audio-firmware \
  tiwilink-firmware \
  nxpwireless-firmware

if [ "$(uname -m)" = "aarch64" ]; then
  dnf install -y bcm2711-firmware
  # U-Boot comes from the custom `uboot` build stage (bootdelay=0, no boot menu),
  # not the stock uboot-images-armv8 package — see Containerfile. bcm2711-firmware
  # still provides the GPU firmware + dtbs/overlays staged onto the ESP.
  cp -P /ctx/rpi-u-boot.bin /boot/efi/rpi-u-boot.bin && \
  mkdir -p /usr/lib/bootc-raspi-firmwares && \
  cp -a /boot/efi/. /usr/lib/bootc-raspi-firmwares/ && \
  dnf remove -y bcm2711-firmware && \
  mkdir /usr/bin/bootupctl-orig && \
  mv /usr/bin/bootupctl /usr/bin/bootupctl-orig/
  cp /ctx/bootupctl-shim.sh /usr/bin/bootupctl
  chmod +x /usr/bin/bootupctl
fi

if [ "$(uname -m)" = "aarch64" ]; then
  dnf remove -qy xorg-x11-drv-qxl
fi

if [ "$(uname -m)" != "aarch64" ]; then
  rm -f /usr/bin/bootupctl-shim
fi

# in arm.sh, before the dracut line:
rm -f /usr/lib/dracut/dracut.conf.d/50-bootc-clevis.conf 
rm -f /usr/lib/dracut/dracut.conf.d/49-bootc-tpm2-tss.conf

# KVER=$(ls /usr/lib/modules | head -1)
# rm -rf "/usr/lib/modules/$KVER/dtb"


