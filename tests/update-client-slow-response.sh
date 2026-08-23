#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPDIR=$(mktemp -d)
SOCKET="$TMPDIR/update.sock"
trap 'rm -rf "$TMPDIR"' EXIT

python3 "$ROOT/tests/fixtures/slow-update-response.py" "$SOCKET" &
SERVER_PID=$!

for _ in {1..50}; do
    [ -S "$SOCKET" ] && break
    sleep 0.02
done
[ -S "$SOCKET" ]

OUTPUT=$(BOOTSYBOX_UPDATE_SOCKET="$SOCKET" \
    "$ROOT/files/usr/local/bin/bootsybox" desktop upgrade --check)
wait "$SERVER_PID"

[ "$OUTPUT" = "update-available: yes" ]
