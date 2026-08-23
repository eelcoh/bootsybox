#!/bin/sh
set -eu

HOST_IMAGE=${BOOTSYBOX_HOST_IMAGE:-ghcr.io/eelcoh/bootsybox-host:44}

sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "$(pwd)/config.toml:/config.toml:ro" \
    -v "$(pwd)/output:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 --rootfs btrfs "$HOST_IMAGE"
