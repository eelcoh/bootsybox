#!/bin/bash
# Runs INSIDE the user's desktop container (seeded into every new user's home
# from /etc/skel). Picks whichever window manager the user has installed in
# their own container — the host never hardcodes a WM.
set -euo pipefail

# This script runs as the real logged-in user (launch-user-container.sh execs
# with -u matching that UID, not root); VT/console device access comes from
# group membership (see launch-user-container.sh), not a logind session ACL —
# greetd doesn't register one for this login. Still use $0 rather than $HOME
# for locating this script, to keep working regardless of exec identity.
SCRIPT_DIR="$(dirname "$0")"
LOG="$SCRIPT_DIR/startup.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(date -Is)] startup.sh starting (pid $$)"

# Do NOT pre-export WAYLAND_DISPLAY here: winit (which niri uses) treats a
# set WAYLAND_DISPLAY as "run nested inside an existing compositor" and tries
# to connect to it as a client, failing with NoCompositor since nothing's
# listening. Standalone/DRM mode requires the var to be unset so niri creates
# its own socket and exports it itself.

# Container PID 1 is just `sleep infinity` — nothing else ever starts a
# session bus, but DBUS_SESSION_BUS_ADDRESS (set by launch-user-container.sh)
# points at $XDG_RUNTIME_DIR/bus, so start one there if it isn't live yet.
if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
    echo "[$(date -Is)] starting session dbus-daemon on $XDG_RUNTIME_DIR/bus"
    dbus-daemon --session --address="unix:path=$XDG_RUNTIME_DIR/bus" \
        --nofork --nopidfile &
    for _ in $(seq 1 20); do
        [ -S "$XDG_RUNTIME_DIR/bus" ] && break
        sleep 0.1
    done
fi

# Force libseat to use seatd rather than probing logind first: the host's
# system D-Bus socket is bind-mounted in, so libseat's logind backend can see
# a reachable bus and attempt a handshake that has no real session behind it.
export LIBSEAT_BACKEND=seatd

# seatd-launch's default socket path lives under /run/, which this
# unprivileged (non-root) user can't create files in directly — point it at
# somewhere actually writable instead. Both the server (seatd/seatd-launch)
# and the client (libseat, via niri) read this same env var.
export SEATD_SOCK="$XDG_RUNTIME_DIR/seatd.sock"

# podman exec -it allocates its own pty for this shell, not a real VT, so
# seatd can't correlate this process to one via its controlling terminal —
# niri stays stuck "paused" otherwise. Attach to tty2 explicitly (not tty1,
# greetd's own VT — stealing that sends SIGHUP to greetd's session and
# restarts the greeter). tty2 is unclaimed, so a plain (non-forced) ctty
# claim is enough; no eviction involved.
#
# Actually SWITCHING the display to tty2 (VT_ACTIVATE) can't happen from in
# here at all — that capability isn't namespace-scoped, so no rootless
# container can ever satisfy it, however privileged. launch-user-container.sh
# does that switch itself, on the host, before this script runs.
VTPATH=/dev/tty2

if command -v niri >/dev/null 2>&1; then
    if command -v seatd-launch >/dev/null 2>&1; then
        echo "[$(date -Is)] launching niri on $VTPATH via seatd-launch"
        exec setsid --ctty --wait seatd-launch -- niri <"$VTPATH"
    else
        echo "[$(date -Is)] seatd-launch not found, falling back to manual seatd" >&2
        seatd &
        for _ in $(seq 1 20); do
            [ -S "$SEATD_SOCK" ] && break
            sleep 0.1
        done
        exec setsid --ctty --wait niri <"$VTPATH"
    fi
elif command -v sway >/dev/null 2>&1; then
    exec setsid --ctty --wait sway <"$VTPATH"
else
    echo "No Window Manager found! Install niri or sway in your container." >&2
    exit 1
fi
