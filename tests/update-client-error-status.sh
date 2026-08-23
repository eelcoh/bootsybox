#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPDIR=$(mktemp -d)
SOCKET="$TMPDIR/update.sock"
trap 'rm -rf "$TMPDIR"' EXIT

python3 "$ROOT/tests/fixtures/slow-update-response.py" "$SOCKET" 42 &
SERVER_PID=$!

for _ in {1..50}; do
    [ -S "$SOCKET" ] && break
    sleep 0.02
done
[ -S "$SOCKET" ]

if OUTPUT=$(BOOTSYBOX_UPDATE_SOCKET="$SOCKET" \
    "$ROOT/files/usr/local/bin/bootsybox" desktop upgrade --check 2>&1); then
    echo "client unexpectedly accepted a failed broker request" >&2
    exit 1
fi
wait "$SERVER_PID"

[ "$OUTPUT" = "error: candidate is incompatible" ]
