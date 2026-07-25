# Cross-build coreos/bootupd (the real bootloader-update daemon; CLI bootupctl)
# for aarch64 on the native host. Produces the arm64 bootupd/bootupctl binary +
# its grub2-static config snippets under /bootupd-out.
#
# Built separately from raspbian3 and pulled in via COPY --from=localhost/raspbian3-bootupd:
#   podman build --platform=linux/arm64 -f raspbian3/bootupd-cross.Containerfile -t raspbian3-bootupd .
FROM --platform=$BUILDPLATFORM docker.io/library/debian:trixie AS bootupd

RUN dpkg --add-architecture arm64 && apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential crossbuild-essential-arm64 git curl ca-certificates make pkgconf \
        libssl-dev:arm64 && \
    rm -rf /var/lib/apt/lists/*

ENV CARGO_HOME=/tmp/rust RUSTUP_HOME=/tmp/rust
ENV CARGO_BUILD_TARGET=aarch64-unknown-linux-gnu
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
ENV CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
ENV PKG_CONFIG_ALLOW_CROSS=1
ENV PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR=/

WORKDIR /src
RUN git clone --depth 1 -b v0.2.35 https://github.com/coreos/bootupd.git .
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --profile minimal --default-host x86_64-unknown-linux-gnu && \
    . "${CARGO_HOME}/env" && rustup target add aarch64-unknown-linux-gnu && \
    cargo build --release

# Install manually (the Makefile reads target/release, but CARGO_BUILD_TARGET
# puts the binary under target/<triple>/release).
RUN T=target/aarch64-unknown-linux-gnu/release && \
    install -D -m0755 "$T/bootupd" /bootupd-out/usr/libexec/bootupd && \
    install -D -m0755 "$T/bootupd" /bootupd-out/usr/bin/bootupctl && \
    install -m644 -D -t /bootupd-out/usr/lib/bootupd/grub2-static src/grub2/*.cfg && \
    install -m644 -D -t /bootupd-out/usr/lib/bootupd/grub2-static/configs.d src/grub2/configs.d/*.cfg && \
    file /bootupd-out/usr/bin/bootupctl 2>/dev/null || readelf -h "$T/bootupd" | grep Machine
