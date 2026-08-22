#!/bin/bash
# Runs inside the user's desktop container. The host owns seat management;
# this script only selects and launches a compositor installed by the user.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
LOG="$SCRIPT_DIR/startup.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(date -Is)] startup.sh starting (pid $$)"

# WAYLAND_DISPLAY must remain unset for a compositor starting on DRM. Setting
# it would ask niri/winit to run nested under an existing Wayland compositor.
unset WAYLAND_DISPLAY

export LIBSEAT_BACKEND=seatd
export SEATD_SOCK=/run/seatd.sock

if [ ! -S "$SEATD_SOCK" ]; then
    echo "Host seatd socket is unavailable: $SEATD_SOCK" >&2
    exit 1
fi

run_compositor() {
    local compositor=$1

    # niri creates WAYLAND_DISPLAY itself, so it cannot be set before launch.
    # Once its socket appears, publish the value to D-Bus activation so portals
    # and other activated GUI services inherit a usable display.
    exec dbus-run-session -- bash -c '
        compositor=$1
        (
            for _ in $(seq 1 100); do
                for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
                    if [ -S "$socket" ]; then
                        WAYLAND_DISPLAY=${socket##*/}
                        export WAYLAND_DISPLAY
                        dbus-update-activation-environment \
                            WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
                        exit 0
                    fi
                done
                sleep 0.05
            done
        ) &
        exec "$compositor"
    ' bash "$compositor"
}

if command -v niri >/dev/null 2>&1; then
    echo "[$(date -Is)] launching niri through host seatd"
    export XDG_CURRENT_DESKTOP=niri
    run_compositor niri
elif command -v sway >/dev/null 2>&1; then
    echo "[$(date -Is)] launching sway through host seatd"
    export XDG_CURRENT_DESKTOP=sway
    run_compositor sway
else
    echo "No Window Manager found! Install niri or sway in your container." >&2
    exit 1
fi
