#!/bin/bash
# Runs on the bootc host as the logging-in user (invoked by greetd/agreety).
# Creates/starts the user's rootless desktop container and hands off control to
# the generic in-container startup script, which picks the user's window manager.
set -euo pipefail

USER_UID=$(id -u)
CONTAINER_NAME="desktop-env-$USER"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
TTY=$(tty)

if ! podman container exists "$CONTAINER_NAME"; then
    podman create \
        --name "$CONTAINER_NAME" \
        --cgroup-manager=systemd \
        --slice=bootsybox-containers.slice \
        --ipc=host \
        --pid=host \
        --net=host \
        --privileged \
        --device /dev/dri \
        --device /dev/kfd \
        --device /dev/fuse \
        --device "$TTY" \
        -v /dev:/dev:rw \
        -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro \
        -v "/run/user/$USER_UID:/run/user/$USER_UID:rw" \
        -v "/var/home/$USER:/home/$USER:rw" \
        -v /etc/machine-id:/etc/machine-id:ro \
        quay.io/fedora/fedora-toolbox:44 \
        /bin/sh -c "dnf install -y flatpak distrobox mesa-dri-drivers; exec sleep infinity"
fi

podman start "$CONTAINER_NAME"

exec podman exec -it \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
    -e XDG_SEAT=seat0 \
    "$CONTAINER_NAME" /bin/bash "/home/$USER/.config/startup.sh"
