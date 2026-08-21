#!/bin/bash
# Runs INSIDE the user's desktop container (seeded into every new user's home
# from /etc/skel). Picks whichever window manager the user has installed in
# their own container — the host never hardcodes a WM.
set -euo pipefail

export WAYLAND_DISPLAY="wayland-0"

if command -v niri >/dev/null 2>&1; then
    exec niri --session
elif command -v sway >/dev/null 2>&1; then
    exec sway
else
    echo "No Window Manager found! Install niri or sway in your container." >&2
    exit 1
fi
