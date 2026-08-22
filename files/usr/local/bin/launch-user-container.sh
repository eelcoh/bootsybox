#!/bin/bash
# Runs on the bootc host as the logging-in user (invoked by greetd/agreety).
# Creates/starts the user's rootless desktop container and hands off control to
# the generic in-container startup script, which picks the user's window manager.
set -euo pipefail

USER=$(id -un)
USER_UID=$(id -u)
USER_GID=$(id -g)
CONTAINER_NAME="desktop-env-$USER"
XDG_RUNTIME_DIR="/run/user/$USER_UID"

if ! podman container exists "$CONTAINER_NAME"; then
    # --userns=keep-id maps this container UID/GID 1:1 to the host instead of
    # shifting it into a subuid range, and a matching account is created below
    # so the WM can later run as this same real UID (see the podman exec
    # below) rather than as container-root.
    #
    # VT/console device access (/dev/tty0, /dev/tty2, /dev/console — see
    # below) comes from static group membership (bootsybox-seat, granted via
    # udev rule + --group-add keep-groups), not per-session logind ACLs.
    # Those devices are root-owned 0600 with no default group sharing, and
    # the natural fix — the logged-in user picking up a per-session ACL the
    # way a plain non-containerized desktop session would — turned out not
    # to apply here: `loginctl list-sessions` shows greetd never registers a
    # logind session for the authenticated user at all, only for the greeter
    # itself (pam_open_session is only ever called for the "greetd-greeter"
    # PAM service, never "greetd"), so no ACL is ever granted to chase.
    # DRM/input devices are unaffected either way, since those are
    # group-shared by default already.
    #
    # --privileged alone already auto-mounts /dev/dri and /dev/input into the
    # container; a blanket -v /dev:/dev:rw on top of that replaces the
    # container's own private /dev/pts with the host's shared one, which
    # breaks crun's pty setup for podman exec -it (chown EPERM under
    # --userns=keep-id). So mount only the specific VT/console nodes that
    # --privileged doesn't provide on its own. tty1 is deliberately left out
    # — that's greetd's own VT; startup.sh attaches the WM to tty2 (unclaimed,
    # so no forced steal needed), and this script switches the display to it
    # (see chvt call below — VT_ACTIVATE can't happen from inside the
    # container at all, namespace-scoped or not).
    # --userns=keep-id also changes podman's default: without an explicit
    # --user, the container's main process (this entrypoint) runs as the
    # keep-id-mapped (real) user instead of container-root. dnf/useradd/
    # ldconfig here need actual root inside the container, so force it
    # explicitly — this is independent of the real-UID exec used below for
    # the WM itself.
    podman create \
        --name "$CONTAINER_NAME" \
        --user root \
        --userns=keep-id \
        --group-add keep-groups \
        --cgroup-manager=systemd \
        --cgroup-parent=bootsybox-containers.slice \
        --ipc=host \
        --pid=host \
        --net=host \
        --privileged \
        -v /dev/tty0:/dev/tty0:rw \
        -v /dev/tty2:/dev/tty2:rw \
        -v /dev/console:/dev/console:rw \
        -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro \
        -v "/run/user/$USER_UID:/run/user/$USER_UID:rw" \
        -v "/var/home/$USER:/home/$USER:rw" \
        -v /etc/machine-id:/etc/machine-id:ro \
        quay.io/fedora/fedora-toolbox:44 \
        /bin/sh -c "dnf install -y flatpak distrobox mesa-dri-drivers dbus-daemon; dnf download -y --destdir=/tmp seatd; rpm2cpio /tmp/seatd-*.rpm | cpio -idmv -D /; ldconfig; groupadd -g $USER_GID $USER 2>/dev/null; useradd -u $USER_UID -g $USER_GID -d /home/$USER -M -s /bin/bash $USER 2>/dev/null; exec sleep infinity"
fi

podman start "$CONTAINER_NAME"

# Switch the display to VT2 (where startup.sh will run the WM) here, on the
# host, before handing off — this ioctl can only succeed from a real
# host-level process; see the setcap comment above. Non-fatal if it fails
# (e.g. chvt missing the capability for some reason): the exec still
# proceeds, just without a fresh error obscuring whatever startup.sh reports.
chvt 2 || echo "warning: chvt 2 failed, continuing anyway" >&2

exec podman exec -it \
    -u "$USER_UID:$USER_GID" \
    -e HOME="/home/$USER" \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
    -e XDG_SEAT=seat0 \
    "$CONTAINER_NAME" /bin/bash "/home/$USER/.config/startup.sh"
