#!/bin/bash
# Runs on the bootc host as the user authenticated by greetd. Creates or starts
# that user's rootless desktop container and waits for its compositor session.
set -euo pipefail

USER=$(id -un)
USER_UID=$(id -u)
USER_GID=$(id -g)
CONTAINER_NAME="desktop-env-$USER"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
SEATD_SOCK=/run/seatd.sock

if [ ! -S "$SEATD_SOCK" ]; then
    echo "Host seat broker is unavailable: $SEATD_SOCK" >&2
    exit 1
fi

if ! podman container exists "$CONTAINER_NAME"; then
    # keep-id lets the compositor and home files use the authenticated user's
    # real UID. keep-groups retains bootsybox-seat, which authorizes access to
    # the host seatd socket. seatd owns the VT and devices and passes already-
    # opened file descriptors to the compositor, so no direct VT/input access,
    # host PID namespace, or privileged container is needed. A read-only DRM
    # directory is present only so udev/Smithay can discover device paths.
    #
    # SELinux label separation is disabled for this prototype because neither
    # an existing home nor a shared host socket can safely receive a private
    # container label. User, mount, PID, IPC and network namespaces remain.
    podman create \
        --name "$CONTAINER_NAME" \
        --user root \
        --userns=keep-id \
        --group-add keep-groups \
        --cgroup-manager=systemd \
        --cgroup-parent=bootsybox-containers.slice \
        --security-opt label=disable \
        --device /dev/fuse \
        -v "$SEATD_SOCK:$SEATD_SOCK:rw" \
        -v /run/udev:/run/udev:ro \
        -v /dev/dri:/dev/dri:ro \
        -v "/var/home/$USER:/home/$USER:rw" \
        -v /etc/machine-id:/etc/machine-id:ro \
        quay.io/fedora/fedora-toolbox:44 \
        /bin/sh -c "dnf install -y flatpak distrobox mesa-dri-drivers dbus-daemon; groupadd -g $USER_GID $USER 2>/dev/null || true; useradd -u $USER_UID -g $USER_GID -d /home/$USER -M -s /bin/bash $USER 2>/dev/null || true; install -d -m 0700 -o $USER_UID -g $USER_GID /run/user/$USER_UID; exec sleep infinity"
fi

podman start "$CONTAINER_NAME"

cleanup() {
    # Stopping between graphical sessions makes Podman establish a fresh bind
    # mount to seatd's current socket inode on the next login. The container's
    # writable layer and bind-mounted home remain persistent.
    podman stop --time 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

podman exec \
    -u "$USER_UID:$USER_GID" \
    -e HOME="/home/$USER" \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e XDG_SEAT=seat0 \
    -e LIBSEAT_BACKEND=seatd \
    -e SEATD_SOCK="$SEATD_SOCK" \
    "$CONTAINER_NAME" /bin/bash "/home/$USER/.config/startup.sh"
