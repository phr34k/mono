# Cross-build Fedora's patched GRUB (has blscfg, which upstream GRUB and Debian
# do NOT ship) for arm64-efi, on the native host. Produces the arm64-efi modules
# incl. blscfg.mod + a self-contained BOOTAA64.EFI at /BOOTAA64.EFI.
#
# Built separately from raspbian3 (the gnulib bootstrap is slow/flaky to re-run
# every image build); raspbian3/Containerfile pulls the result via
# `COPY --from=localhost/raspbian3-grub`. Build it with:
#   podman build --platform=linux/arm64 -f raspbian3/grub-cross.Containerfile -t raspbian3-grub .
FROM --platform=$BUILDPLATFORM docker.io/library/debian:trixie AS grub

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        crossbuild-essential-arm64 git make bison flex gettext autopoint autoconf \
        automake libtool pkg-config python3 gawk gperf texinfo help2man ca-certificates \
        xz-utils patch rsync && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 -b fedora-41 https://github.com/rhboot/grub2.git .

# Generate configure (git tree has no pre-built configure); fetches gnulib.
RUN ./bootstrap

# Cross-configure for arm64-efi: host tools stay native (build CC), modules use
# the aarch64 cross toolchain.
RUN ./configure \
        --target=aarch64-linux-gnu --with-platform=efi \
        --prefix=/usr --disable-werror \
        BUILD_CC=gcc \
        TARGET_CC=aarch64-linux-gnu-gcc \
        TARGET_CXX=aarch64-linux-gnu-g++ \
        TARGET_OBJCOPY=aarch64-linux-gnu-objcopy \
        TARGET_STRIP=aarch64-linux-gnu-strip \
        TARGET_NM=aarch64-linux-gnu-nm \
        TARGET_RANLIB=aarch64-linux-gnu-ranlib

RUN make -j"$(nproc)" && make install DESTDIR=/gout

# Assemble a self-contained arm64-efi image with blscfg + the modules needed to
# read an ext4 /boot on an MBR disk and run the BLS entries ostree writes.
RUN ls /gout/usr/lib/grub/arm64-efi/blscfg.mod && \
    /gout/usr/bin/grub-mkimage \
        -O arm64-efi \
        -d /gout/usr/lib/grub/arm64-efi \
        -p /EFI/BOOT \
        -o /BOOTAA64.EFI \
        part_gpt part_msdos ext2 fat normal configfile search search_fs_uuid \
        search_fs_file search_label blscfg linux echo test all_video efi_gop \
        font gfxterm terminal loadenv cat regexp gzio halt reboot && \
    ls -l /BOOTAA64.EFI
