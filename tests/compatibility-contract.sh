#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECKER="$ROOT/files/usr/local/libexec/bootsybox-check-compatibility"

OUTPUT=$("$CHECKER" 1 1 1 1)
[ "$OUTPUT" = "compatibility: host API 1, desktop API 1" ]

if "$CHECKER" 1 2 1 1 2>/dev/null; then
    echo "accepted a desktop API unsupported by the host" >&2
    exit 1
fi

if "$CHECKER" 1 1 1 2 2>/dev/null; then
    echo "accepted a desktop requiring another host API" >&2
    exit 1
fi

if "$CHECKER" '' 1 1 1 2>/dev/null; then
    echo "accepted a missing compatibility label" >&2
    exit 1
fi
