#!/bin/bash
# The outer desktop container is a disposable realization of an OCI image;
# durable state belongs in the bind-mounted home or declared volumes.
set -euo pipefail

USER=$(id -un)
USER_UID=$(id -u)
USER_GID=$(id -g)
CONTAINER_NAME="desktop-env-$USER"
CANDIDATE_NAME="$CONTAINER_NAME-candidate"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
SEATD_SOCK=/run/seatd.sock
UPDATE_SOCK=/run/bootsybox-update.sock
DEFAULT_DESKTOP_IMAGE_FILE=/usr/share/bootsybox/desktop-image
OVERRIDE_DESKTOP_IMAGE_FILE=/etc/bootsybox/desktop-image
EXPECTED_DESKTOP_API=1
HOST_API=1
EXPECTED_RUNTIME_API=3
STATE_DIR="$HOME/.local/state/bootsybox"
LAST_GOOD_FILE="$STATE_DIR/last-good-image"
ROLLBACK_IMAGE_FILE="$STATE_DIR/rollback-image"
FAILED_IMAGE_FILE="$STATE_DIR/failed-image"
STAGED_IMAGE_FILE="$STATE_DIR/staged-image"

fail() {
    echo "Bootsybox session failed: $*" >&2
    echo "Press Enter to return to login." >&2
    read -r _ </dev/tty || true
    exit 1
}

image_id() {
    podman image inspect --format '{{.Id}}' "$1"
}

image_api() {
    podman image inspect --format '{{index .Labels "io.bootsybox.desktop.api"}}' "$1"
}

image_host_api() {
    podman image inspect --format '{{index .Labels "io.bootsybox.desktop.host-api"}}' "$1"
}

container_image_id() {
    podman container inspect --format '{{.Image}}' "$1"
}

container_runtime_api() {
    podman container inspect --format '{{index .Config.Labels "io.bootsybox.runtime.api"}}' "$1"
}

create_container() {
    local name=$1
    local image=$2

    # This is intentionally rootless-privileged. It cannot exceed the user's
    # host privileges, but it relaxes the outer boundary so Flatpak's nested
    # Bubblewrap sandbox can construct its own namespaces. The outer container
    # is a reproducible environment, not a security boundary.
    podman create \
        --name "$name" \
        --label "io.bootsybox.runtime.api=$EXPECTED_RUNTIME_API" \
        --privileged \
        --user root \
        --userns=keep-id \
        --group-add keep-groups \
        --cgroup-manager=systemd \
        --cgroup-parent=bootsybox-containers.slice \
        -e BOOTSYBOX_USER="$USER" \
        -e BOOTSYBOX_UID="$USER_UID" \
        -e BOOTSYBOX_GID="$USER_GID" \
        -v "$SEATD_SOCK:$SEATD_SOCK:rw" \
        -v "$UPDATE_SOCK:$UPDATE_SOCK:rw" \
        -v /run/udev:/run/udev:ro \
        -v /dev/dri:/dev/dri:ro \
        -v "/var/home/$USER:/home/$USER:rw" \
        -v /etc/machine-id:/etc/machine-id:ro \
        "$image"
}

mkdir -p "$STATE_DIR"

[ -S "$SEATD_SOCK" ] || fail "host seat broker is unavailable: $SEATD_SOCK"
[ -S "$UPDATE_SOCK" ] || fail "host update broker is unavailable: $UPDATE_SOCK"
[ -r "$DEFAULT_DESKTOP_IMAGE_FILE" ] || fail "desktop image declaration is missing"

DESKTOP_IMAGE_FILE=$DEFAULT_DESKTOP_IMAGE_FILE
if [ -r "$OVERRIDE_DESKTOP_IMAGE_FILE" ]; then
    DESKTOP_IMAGE_FILE=$OVERRIDE_DESKTOP_IMAGE_FILE
fi
DESKTOP_IMAGE=$(tr -d '[:space:]' < "$DESKTOP_IMAGE_FILE")
[ -n "$DESKTOP_IMAGE" ] || fail "desktop image declaration is empty"

SELECTED_IMAGE=
SELECTED_IMAGE_ID=

if [ -r "$STAGED_IMAGE_FILE" ]; then
    STAGED_IMAGE=$(cat "$STAGED_IMAGE_FILE")
    if podman image exists "$STAGED_IMAGE"; then
        SELECTED_IMAGE=$STAGED_IMAGE
        SELECTED_IMAGE_ID=$(image_id "$SELECTED_IMAGE")
        echo "Activating staged desktop image: $SELECTED_IMAGE_ID"
    else
        fail "staged desktop image is no longer cached"
    fi
elif podman container exists "$CONTAINER_NAME"; then
    SELECTED_IMAGE_ID=$(container_image_id "$CONTAINER_NAME")
    SELECTED_IMAGE=$SELECTED_IMAGE_ID
elif [ -r "$LAST_GOOD_FILE" ] && podman image exists "$(cat "$LAST_GOOD_FILE")"; then
    SELECTED_IMAGE=$(cat "$LAST_GOOD_FILE")
    SELECTED_IMAGE_ID=$(image_id "$SELECTED_IMAGE")
else
    echo "Bootstrapping desktop image: $DESKTOP_IMAGE"
    podman pull "$DESKTOP_IMAGE" || fail "unable to bootstrap $DESKTOP_IMAGE"
    SELECTED_IMAGE=$DESKTOP_IMAGE
    SELECTED_IMAGE_ID=$(image_id "$SELECTED_IMAGE")
fi

if [ -r "$FAILED_IMAGE_FILE" ] &&
   [ "$(cat "$FAILED_IMAGE_FILE")" = "$SELECTED_IMAGE_ID" ] &&
   [ -r "$LAST_GOOD_FILE" ] &&
   podman image exists "$(cat "$LAST_GOOD_FILE")"; then
    echo "warning: selected image previously failed; using last known good image" >&2
    rm -f "$STAGED_IMAGE_FILE"
    SELECTED_IMAGE=$(cat "$LAST_GOOD_FILE")
    SELECTED_IMAGE_ID=$(image_id "$SELECTED_IMAGE")
fi

[ "$(image_api "$SELECTED_IMAGE")" = "$EXPECTED_DESKTOP_API" ] ||
    fail "desktop image API is incompatible with launcher API $EXPECTED_DESKTOP_API"
[ "$(image_host_api "$SELECTED_IMAGE")" = "$HOST_API" ] ||
    fail "desktop image requires an incompatible host API"

REPLACE_CONTAINER=false
if ! podman container exists "$CONTAINER_NAME"; then
    REPLACE_CONTAINER=true
elif [ "$(container_image_id "$CONTAINER_NAME")" != "$SELECTED_IMAGE_ID" ] ||
     [ "$(container_runtime_api "$CONTAINER_NAME")" != "$EXPECTED_RUNTIME_API" ]; then
    REPLACE_CONTAINER=true
fi

if [ "$REPLACE_CONTAINER" = true ]; then
    echo "Preparing disposable desktop environment; home data is preserved"
    podman rm --force "$CANDIDATE_NAME" >/dev/null 2>&1 || true
    if ! create_container "$CANDIDATE_NAME" "$SELECTED_IMAGE"; then
        podman rm --force "$CANDIDATE_NAME" >/dev/null 2>&1 || true
        fail "could not create candidate environment; existing environment was preserved"
    fi
    if ! podman start "$CANDIDATE_NAME" >/dev/null; then
        podman rm --force "$CANDIDATE_NAME" >/dev/null 2>&1 || true
        fail "could not start candidate environment; existing environment was preserved"
    fi
    if ! podman exec "$CANDIDATE_NAME" test -x /usr/local/bin/bootsybox-session; then
        podman rm --force "$CANDIDATE_NAME" >/dev/null 2>&1 || true
        fail "candidate image failed validation; existing environment was preserved"
    fi
    podman stop --time 10 "$CANDIDATE_NAME" >/dev/null
    podman rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman rename "$CANDIDATE_NAME" "$CONTAINER_NAME"
fi

if [ "$(podman container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" = true ]; then
    podman stop --time 10 "$CONTAINER_NAME" >/dev/null
fi
podman start "$CONTAINER_NAME" >/dev/null
podman exec "$CONTAINER_NAME" rm -f "$XDG_RUNTIME_DIR/bootsybox-session-ready"

cleanup() {
    podman stop --time 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

promote_ready_image() {
    if [ -r "$LAST_GOOD_FILE" ] &&
       [ "$(cat "$LAST_GOOD_FILE")" != "$SELECTED_IMAGE_ID" ]; then
        cp "$LAST_GOOD_FILE" "$ROLLBACK_IMAGE_FILE"
    fi
    printf '%s\n' "$SELECTED_IMAGE_ID" > "$LAST_GOOD_FILE"
    if [ -r "$STAGED_IMAGE_FILE" ] &&
       [ "$(cat "$STAGED_IMAGE_FILE")" = "$SELECTED_IMAGE_ID" ]; then
        rm -f "$STAGED_IMAGE_FILE"
    fi
    if [ ! -r "$FAILED_IMAGE_FILE" ] ||
       [ "$(cat "$FAILED_IMAGE_FILE")" = "$SELECTED_IMAGE_ID" ]; then
        rm -f "$FAILED_IMAGE_FILE"
    fi
}

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
    "$CONTAINER_NAME" /usr/local/bin/bootsybox-session &
SESSION_EXEC_PID=$!

SESSION_READY=false
for _ in $(seq 1 100); do
    if podman exec "$CONTAINER_NAME" test -f "$XDG_RUNTIME_DIR/bootsybox-session-ready" \
        >/dev/null 2>&1; then
        promote_ready_image
        SESSION_READY=true
        break
    fi
    if ! kill -0 "$SESSION_EXEC_PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

SESSION_STATUS=0
wait "$SESSION_EXEC_PID" || SESSION_STATUS=$?

if [ "$SESSION_READY" = false ] &&
   podman exec "$CONTAINER_NAME" test -f "$XDG_RUNTIME_DIR/bootsybox-session-ready" \
       >/dev/null 2>&1; then
    promote_ready_image
    SESSION_READY=true
fi

if [ "$SESSION_READY" = false ]; then
    printf '%s\n' "$SELECTED_IMAGE_ID" > "$FAILED_IMAGE_FILE"
    fail "desktop image exited before reaching a Wayland-ready state"
fi

exit "$SESSION_STATUS"
