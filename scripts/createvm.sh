#!/bin/sh
set -eu

HOST_IMAGE=${BOOTSYBOX_HOST_IMAGE:-ghcr.io/eelcoh/bootsybox-host:44}

case "$HOST_IMAGE" in
    localhost/*)
        sudo podman image exists "$HOST_IMAGE" || {
            echo "Local host image is missing: $HOST_IMAGE" >&2
            echo "Build it first with sudo podman build." >&2
            exit 1
        }
        ;;
    *)
        # bootc-image-builder deliberately does not pull its input image. Pull
        # into the same rootful storage that is mounted into the builder.
        sudo podman pull "$HOST_IMAGE"
        ;;
esac

sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "$(pwd)/config.toml:/config.toml:ro" \
    -v "$(pwd)/output:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 --rootfs btrfs "$HOST_IMAGE"
