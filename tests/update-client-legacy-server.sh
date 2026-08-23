#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPDIR=$(mktemp -d)
SOCKET="$TMPDIR/update.sock"
trap 'rm -rf "$TMPDIR"' EXIT

python3 - "$SOCKET" <<'PY' &
import socket
import sys

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(sys.argv[1])
    server.listen(1)
    connection, _ = server.accept()
    with connection:
        connection.recv(4096)
        connection.sendall(b"legacy-status: ok\n")
PY
SERVER_PID=$!

for _ in {1..50}; do
    [ -S "$SOCKET" ] && break
    sleep 0.02
done
[ -S "$SOCKET" ]

OUTPUT=$(BOOTSYBOX_UPDATE_SOCKET="$SOCKET" \
    "$ROOT/files/usr/local/bin/bootsybox" desktop status)
wait "$SERVER_PID"

[ "$OUTPUT" = "legacy-status: ok" ]
