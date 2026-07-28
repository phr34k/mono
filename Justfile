mod bcvk 'bcvk.just'

image_name := env("BUILD_IMAGE_NAME", "")
image_tag := env("BUILD_IMAGE_TAG", "latest")
base_dir := env("BUILD_BASE_DIR", ".")
filesystem := env("BUILD_FILESYSTEM", "ext4")
selinux := env("BUILD_SELINUX", "true")

options := if selinux == "true" { "-v /var/lib/containers:/var/lib/containers:Z -v /etc/containers:/etc/containers:Z -v /sys/fs/selinux:/sys/fs/selinux --security-opt label=type:unconfined_t" } else { "-v /var/lib/containers:/var/lib/containers -v /etc/containers:/etc/containers" }
container_runtime := env("CONTAINER_RUNTIME", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)
sudo_prefix := if env("NOSUDO", "") == "" { "sudo " } else { "" }

# Build image and run an ephemeral VM for boot testing
test IMAGE=image_name:
    just bcvk build-and-test {{IMAGE}}

build $image_name=image_name:
    #!/usr/bin/env bash
    set -euo pipefail
    # raspbian/raspian2 target the Raspberry Pi CM4 (aarch64), so default them to
    # an arm64 build. Override for any image with BUILD_PLATFORM=linux/amd64 etc.
    # (raspian2 cross-compiles: its builder stage pins to $BUILDPLATFORM and runs
    # natively, so --platform only sets the arm64 *target*.)
    platform="${BUILD_PLATFORM:-}"
    case "$image_name" in raspbian|raspian2) [ -z "$platform" ] && platform="linux/arm64" ;; esac
    args=()
    [ -n "$platform" ] && args+=(--platform "$platform")
    # raspian2/Containerfile is now the COMBINED build (former raspian2 + raspbian3
    # + grub-cross + bootupd-cross): it produces the complete CM4 image. Tag it
    # under its own name AND the prod name raspbian3-bootc (same image) so both the
    # name-derived recipes (bootc/test/disk-image) and remote-build resolve it.
    tag_args=(-t "${image_name}-bootc:latest")
    [ "$image_name" = raspian2 ] && tag_args+=(-t "raspbian3-bootc:latest")
    {{sudo_prefix}}{{container_runtime}} build "${args[@]}" -f "$image_name/Containerfile" "${tag_args[@]}" .

remote-build-install:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -t phr34k@192.168.56.102 'echo "phr34k ALL=(ALL) NOPASSWD: /usr/bin/podman, /usr/bin/osbuild, /usr/bin/image-builder" | sudo tee /etc/sudoers.d/nexus-build && sudo chmod 440 /etc/sudoers.d/nexus-build'




remote-pull:
    #!/usr/bin/env bash
    set -euo pipefail

    ssh phr34k@192.168.56.102 'bash -s' <<'REMOTE'
    set -euo pipefail
    cd ~/nexus-pi-gen
    sudo podman pull localhost:5000/eps-prod:latest
    sudo podman tag localhost:5000/eps-prod:latest localhost/eps-prod:latest
    sudo podman inspect --format '{{ "{{" }}.Id}}' localhost/eps-prod:latest

    REMOTE


remote-build:
    #!/usr/bin/env bash
    set -euo pipefail

    podman tag  localhost/raspbian3-bootc:latest 192.168.56.102:5000/eps-prod:latest 
    podman push 192.168.56.102:5000/eps-prod:latest

    ssh phr34k@192.168.56.102 'bash -s' <<'REMOTE'
    set -euo pipefail
    cd ~/nexus-pi-gen
    sudo podman pull localhost:5000/eps-prod:latest
    sudo podman tag localhost:5000/eps-prod:latest localhost/eps-prod:latest
    sudo podman inspect --format '{{ "{{" }}.Id}}' localhost/eps-prod:latest

    sudo image-builder manifest --bootc-ref localhost/eps-prod:latest --bootc-default-fs ext4 \
        --bootc-no-default-kernel-args --blueprint blueprint.toml --arch aarch64 raw > manifest.json
    jq '(.pipelines[]?.stages) |= map(select(.type != "org.osbuild.selinux"))' manifest.json > manifest-nosel.json
    sudo osbuild --store ./store --output-directory ./out --export gce manifest-nosel.json

    REMOTE

bootc $image_name=image_name $image_tag=image_tag *ARGS:
    sudo {{container_runtime}} run \
        --rm --privileged --pid=host \
        -it \
        {{options}} \
        -v /dev:/dev \
        -e RUST_LOG=debug \
        -v "{{base_dir}}:/data" \
        "${image_name}-bootc:${image_tag}" bootc {{ARGS}}

disk-image $image_name=image_name $image_tag=image_tag $base_dir=base_dir $filesystem=filesystem:
    #!/usr/bin/env bash
    if [ ! -e "${base_dir}/bootable.img" ] ; then
        fallocate -l 20G "${base_dir}/bootable.img"
    fi
    just bootc $image_name $image_tag install to-disk --composefs-backend --via-loopback /data/bootable.img --filesystem "${filesystem}" --wipe --bootloader systemd

rechunk $image_name=image_name:
    #!/usr/bin/env bash
    export CHUNKAH_CONFIG_STR="$(podman inspect "${image_name}-bootc")"
    podman run --rm "--mount=type=image,src=${image_name}-bootc,target=/chunkah" -e CHUNKAH_CONFIG_STR quay.io/coreos/chunkah build --label ostree.bootable=1 --label containers.bootc=1 --compressed --max-layers 128 | \
        podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} podman tag {} "${image_name}-bootc"
