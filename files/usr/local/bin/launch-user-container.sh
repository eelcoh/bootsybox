#!/bin/bash
# Runs on the bootc host as the user authenticated by greetd. It keeps the
# replaceable outer container synchronized with the declared desktop image,
# starts it, and waits for the graphical session to end.
set -euo pipefail

USER=$(id -un)
USER_UID=$(id -u)
USER_GID=$(id -g)
CONTAINER_NAME="desktop-env-$USER"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
SEATD_SOCK=/run/seatd.sock
DESKTOP_IMAGE_FILE=/usr/share/bootsybox/desktop-image

if [ ! -S "$SEATD_SOCK" ]; then
    echo "Host seat broker is unavailable: $SEATD_SOCK" >&2
    exit 1
fi

if [ ! -r "$DESKTOP_IMAGE_FILE" ]; then
    echo "Desktop image declaration is missing: $DESKTOP_IMAGE_FILE" >&2
    exit 1
fi

DESKTOP_IMAGE=$(tr -d '[:space:]' < "$DESKTOP_IMAGE_FILE")
if [ -z "$DESKTOP_IMAGE" ]; then
    echo "Desktop image declaration is empty: $DESKTOP_IMAGE_FILE" >&2
    exit 1
fi

echo "Synchronizing desktop image: $DESKTOP_IMAGE"
if ! podman pull --quiet "$DESKTOP_IMAGE"; then
    if podman image exists "$DESKTOP_IMAGE"; then
        echo "warning: pull failed; using the cached desktop image" >&2
    else
        echo "Unable to pull $DESKTOP_IMAGE and no cached image is available" >&2
        exit 1
    fi
fi

DESIRED_IMAGE_ID=$(podman image inspect --format '{{.Id}}' "$DESKTOP_IMAGE")

if podman container exists "$CONTAINER_NAME"; then
    CURRENT_IMAGE_ID=$(podman container inspect --format '{{.Image}}' "$CONTAINER_NAME")
    if [ "$CURRENT_IMAGE_ID" != "$DESIRED_IMAGE_ID" ]; then
        echo "Replacing outdated desktop container; home data is preserved"
        podman rm --force "$CONTAINER_NAME"
    fi
fi

if ! podman container exists "$CONTAINER_NAME"; then
    # keep-id maps the graphical user to their host UID. keep-groups retains
    # bootsybox-seat, authorizing the seatd connection. seatd performs the
    # privileged VT/input/DRM opens; the read-only DRM view exists for device
    # discovery, not direct seat ownership.
    #
    # SELinux label separation remains disabled while an existing home and a
    # host Unix socket are shared. Other Podman namespaces remain enabled.
    podman create \
        --name "$CONTAINER_NAME" \
        --user root \
        --userns=keep-id \
        --group-add keep-groups \
        --cgroup-manager=systemd \
        --cgroup-parent=bootsybox-containers.slice \
        --security-opt label=disable \
        --device /dev/fuse \
        -e BOOTSYBOX_USER="$USER" \
        -e BOOTSYBOX_UID="$USER_UID" \
        -e BOOTSYBOX_GID="$USER_GID" \
        -v "$SEATD_SOCK:$SEATD_SOCK:rw" \
        -v /run/udev:/run/udev:ro \
        -v /dev/dri:/dev/dri:ro \
        -v "/var/home/$USER:/home/$USER:rw" \
        -v /etc/machine-id:/etc/machine-id:ro \
        "$DESKTOP_IMAGE"
fi

# A graphical container is session-scoped. Restarting it for every login also
# refreshes the bind mount if seatd recreated its socket since the last session.
if [ "$(podman container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" = true ]; then
    podman stop --time 10 "$CONTAINER_NAME" >/dev/null
fi
podman start "$CONTAINER_NAME"

cleanup() {
    podman stop --time 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

podman exec \
    -u "$USER_UID:$USER_GID" \
    -e HOME="/home/$USER" \
    -e USER="$USER" \
    -e LOGNAME="$USER" \
    -e SHELL=/bin/bash \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e XDG_SEAT=seat0 \
    -e LIBSEAT_BACKEND=seatd \
    -e SEATD_SOCK="$SEATD_SOCK" \
    "$CONTAINER_NAME" /usr/local/bin/bootsybox-session
